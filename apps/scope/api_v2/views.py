from __future__ import annotations

import json
from datetime import datetime

from django.db.models import Max
from django.http import JsonResponse
from django.views.decorators.http import require_GET, require_http_methods

from apps.scope.models import Project, Tag, Task
from apps.scope.api_v2.auth import v2
from apps.scope.api_v2.serializers import project_to_dict, tag_to_dict, task_to_dict


def _json_error(code: str, message: str, status: int = 400, **extra):
    body = {'error': {'code': code, 'message': message}}
    if extra:
        body['error']['details'] = extra
    return JsonResponse(body, status=status)


def _parse_body(request):
    if request.method in ('GET', 'HEAD') or not request.body:
        return {}
    try:
        return json.loads(request.body)
    except json.JSONDecodeError:
        return None


def _parse_date(s):
    if s is None or s == '':
        return None
    if isinstance(s, str):
        return datetime.strptime(s, '%Y-%m-%d').date()
    raise ValueError('due_date must be YYYY-MM-DD string')


def _parse_time_val(s):
    if s is None or s == '':
        return None
    if not isinstance(s, str):
        raise ValueError('due_time must be a string')
    for fmt in ('%H:%M:%S', '%H:%M'):
        try:
            return datetime.strptime(s, fmt).time()
        except ValueError:
            continue
    raise ValueError('due_time must be HH:MM or HH:MM:SS')


@v2
@require_GET
def root(request):
    return JsonResponse({
        'data': {
            'api': 'scope',
            'version': 2,
            'auth': ['Authorization: Bearer <token>', 'X-API-Key: <token>'],
        }
    })


@v2
@require_GET
def me(request):
    u = request.user
    return JsonResponse({
        'data': {
            'id': u.id,
            'username': u.username,
            'email': u.email,
            'is_staff': u.is_staff,
        }
    })


@v2
@require_http_methods(['GET', 'POST'])
def projects_collection(request):
    user = request.user
    if request.method == 'GET':
        archived = request.GET.get('archived', '').lower() in ('1', 'true', 'yes')
        qs = Project.objects.filter(user=user, is_archived=archived).order_by('-created_at')
        return JsonResponse({'data': [project_to_dict(p) for p in qs], 'meta': {'count': qs.count()}})

    data = _parse_body(request)
    if data is None:
        return _json_error('bad_json', 'Тело запроса не JSON', 400)
    name = (data.get('name') or '').strip()
    if not name:
        return _json_error('validation_error', 'Поле name обязательно')
    p = Project.objects.create(
        user=user,
        name=name[:200],
        description=(data.get('description') or '')[:5000],
        color=(data.get('color') or '#7C3AED')[:7],
        icon=(data.get('icon') or 'folder')[:50],
    )
    return JsonResponse({'data': project_to_dict(p)}, status=201)


@v2
@require_http_methods(['GET', 'PATCH', 'DELETE'])
def project_detail(request, pk: int):
    user = request.user
    try:
        p = Project.objects.get(pk=pk, user=user)
    except Project.DoesNotExist:
        return _json_error('not_found', 'Проект не найден', 404)

    if request.method == 'GET':
        return JsonResponse({'data': project_to_dict(p)})

    if request.method == 'DELETE':
        p.delete()
        return JsonResponse({'data': {'deleted': True}})

    data = _parse_body(request)
    if data is None:
        return _json_error('bad_json', 'Тело запроса не JSON', 400)
    if 'name' in data and (data.get('name') or '').strip():
        p.name = (data.get('name') or '').strip()[:200]
    if 'description' in data:
        p.description = (data.get('description') or '')[:5000]
    if 'color' in data and data['color']:
        p.color = str(data['color'])[:7]
    if 'icon' in data and data['icon'] is not None:
        p.icon = str(data['icon'])[:50]
    if 'is_archived' in data:
        p.is_archived = bool(data['is_archived'])
    p.save()
    return JsonResponse({'data': project_to_dict(p)})


@v2
@require_http_methods(['GET', 'POST'])
def tags_collection(request):
    user = request.user
    if request.method == 'GET':
        qs = Tag.objects.filter(user=user).order_by('name')
        return JsonResponse({'data': [tag_to_dict(t) for t in qs], 'meta': {'count': qs.count()}})

    data = _parse_body(request)
    if data is None:
        return _json_error('bad_json', 'Тело запроса не JSON', 400)
    name = (data.get('name') or '').strip()
    if not name:
        return _json_error('validation_error', 'Поле name обязательно')
    t = Tag.objects.create(
        user=user,
        name=name[:50],
        color=(data.get('color') or '#7C3AED')[:7],
    )
    return JsonResponse({'data': tag_to_dict(t)}, status=201)


@v2
@require_http_methods(['GET', 'POST'])
def tasks_collection(request):
    user = request.user
    if request.method == 'GET':
        qs = Task.objects.filter(user=user).select_related('project').prefetch_related('tags')
        if request.GET.get('project'):
            try:
                qs = qs.filter(project_id=int(request.GET['project']))
            except ValueError:
                return _json_error('validation_error', 'project должен быть числом')
        c = request.GET.get('completed')
        if c is not None and c != '':
            qs = qs.filter(is_completed=c.lower() in ('1', 'true', 'yes'))
        if request.GET.get('due_before'):
            try:
                qs = qs.filter(due_date__lte=_parse_date(request.GET['due_before']))
            except ValueError as e:
                return _json_error('validation_error', str(e))
        if request.GET.get('due_after'):
            try:
                qs = qs.filter(due_date__gte=_parse_date(request.GET['due_after']))
            except ValueError as e:
                return _json_error('validation_error', str(e))
        try:
            limit = min(int(request.GET.get('limit', 100)), 500)
            offset = max(int(request.GET.get('offset', 0)), 0)
        except ValueError:
            return _json_error('validation_error', 'limit/offset должны быть числами')
        total = qs.count()
        tasks = qs.order_by('is_completed', '-priority', 'order', '-created_at')[offset : offset + limit]
        return JsonResponse({
            'data': [task_to_dict(t) for t in tasks],
            'meta': {'count': total, 'limit': limit, 'offset': offset},
        })

    data = _parse_body(request)
    if data is None:
        return _json_error('bad_json', 'Тело запроса не JSON', 400)
    title = (data.get('title') or '').strip()
    if not title:
        return _json_error('validation_error', 'Поле title обязательно')

    project_id = data.get('project_id')
    if project_id is not None:
        try:
            project_id = int(project_id)
        except (TypeError, ValueError):
            return _json_error('validation_error', 'project_id должен быть числом')
        if not Project.objects.filter(pk=project_id, user=user).exists():
            return _json_error('validation_error', 'Проект не найден', 400)

    try:
        priority = int(data.get('priority', 2))
    except (TypeError, ValueError):
        return _json_error('validation_error', 'priority должен быть числом 1..4')
    if priority not in (1, 2, 3, 4):
        return _json_error('validation_error', 'priority должен быть 1..4')

    due_date = None
    if data.get('due_date'):
        try:
            due_date = _parse_date(data['due_date'])
        except ValueError as e:
            return _json_error('validation_error', str(e))

    due_time_val = None
    if data.get('due_time'):
        try:
            due_time_val = _parse_time_val(data['due_time'])
        except ValueError as e:
            return _json_error('validation_error', str(e))

    order_val = 0
    if due_date:
        max_o = Task.objects.filter(user=user, due_date=due_date).aggregate(m=Max('order'))['m']
        order_val = (max_o if max_o is not None else -1) + 1

    task = Task.objects.create(
        user=user,
        title=title[:500],
        description=(data.get('description') or '')[:10000],
        project_id=project_id,
        priority=priority,
        due_date=due_date,
        due_time=due_time_val,
        order=order_val,
    )
    tag_ids = data.get('tag_ids') or data.get('tags')
    if tag_ids is not None:
        if not isinstance(tag_ids, (list, tuple)):
            return _json_error('validation_error', 'tag_ids должен быть массивом')
        ids = []
        for x in tag_ids:
            try:
                ids.append(int(x))
            except (TypeError, ValueError):
                return _json_error('validation_error', 'каждый tag_id должен быть числом')
        uniq = list(dict.fromkeys(ids))
        if Tag.objects.filter(user=user, pk__in=uniq).count() != len(uniq):
            return _json_error('validation_error', 'Не все теги найдены или принадлежат вам')
        task.tags.set(uniq)

    task.refresh_from_db()
    return JsonResponse({'data': task_to_dict(task)}, status=201)


@v2
@require_http_methods(['GET', 'PATCH', 'DELETE'])
def task_detail(request, pk: int):
    user = request.user
    try:
        task = Task.objects.prefetch_related('tags').get(pk=pk, user=user)
    except Task.DoesNotExist:
        return _json_error('not_found', 'Задача не найдена', 404)

    if request.method == 'GET':
        return JsonResponse({'data': task_to_dict(task)})

    if request.method == 'DELETE':
        task.delete()
        return JsonResponse({'data': {'deleted': True}})

    data = _parse_body(request)
    if data is None:
        return _json_error('bad_json', 'Тело запроса не JSON', 400)

    if 'title' in data:
        t = (data.get('title') or '').strip()
        if t:
            task.title = t[:500]
    if 'description' in data:
        task.description = (data.get('description') or '')[:10000]

    if 'priority' in data:
        try:
            pr = int(data['priority'])
        except (TypeError, ValueError):
            return _json_error('validation_error', 'priority должен быть числом 1..4')
        if pr not in (1, 2, 3, 4):
            return _json_error('validation_error', 'priority должен быть 1..4')
        task.priority = pr

    if 'is_completed' in data:
        task.is_completed = bool(data['is_completed'])

    if 'project_id' in data:
        pid = data['project_id']
        if pid is None:
            task.project_id = None
        else:
            try:
                pid = int(pid)
            except (TypeError, ValueError):
                return _json_error('validation_error', 'project_id должен быть числом или null')
            if not Project.objects.filter(pk=pid, user=user).exists():
                return _json_error('validation_error', 'Проект не найден')
            task.project_id = pid

    if 'due_date' in data:
        raw = data['due_date']
        if raw is None or raw == '':
            task.due_date = None
            task.order = 0
        else:
            try:
                nd = _parse_date(raw)
            except ValueError as e:
                return _json_error('validation_error', str(e))
            if nd != task.due_date:
                task.due_date = nd
                if nd:
                    max_o = Task.objects.filter(user=user, due_date=nd).exclude(pk=task.pk).aggregate(m=Max('order'))['m']
                    task.order = (max_o if max_o is not None else -1) + 1
                else:
                    task.order = 0

    if 'due_time' in data:
        raw = data['due_time']
        if raw is None or raw == '':
            task.due_time = None
        else:
            try:
                task.due_time = _parse_time_val(data['due_time'])
            except ValueError as e:
                return _json_error('validation_error', str(e))

    if 'tag_ids' in data or 'tags' in data:
        tag_ids = data.get('tag_ids') if 'tag_ids' in data else data.get('tags')
        if tag_ids is None:
            task.tags.clear()
        else:
            if not isinstance(tag_ids, (list, tuple)):
                return _json_error('validation_error', 'tag_ids должен быть массивом')
            ids = []
            for x in tag_ids:
                try:
                    ids.append(int(x))
                except (TypeError, ValueError):
                    return _json_error('validation_error', 'каждый tag_id должен быть числом')
            uniq = list(dict.fromkeys(ids))
            if Tag.objects.filter(user=user, pk__in=uniq).count() != len(uniq):
                return _json_error('validation_error', 'Не все теги найдены или принадлежат вам')
            task.tags.set(uniq)

    task.save()
    task.refresh_from_db()
    return JsonResponse({'data': task_to_dict(task)})


@v2
@require_http_methods(['POST'])
def task_toggle(request, pk: int):
    user = request.user
    try:
        task = Task.objects.get(pk=pk, user=user)
    except Task.DoesNotExist:
        return _json_error('not_found', 'Задача не найдена', 404)
    task.is_completed = not task.is_completed
    task.save()
    return JsonResponse({'data': {'id': task.id, 'is_completed': task.is_completed}})
