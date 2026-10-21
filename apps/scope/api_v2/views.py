from __future__ import annotations

import json
from datetime import datetime

from django.db.models import Max
from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_http_methods

from apps.scope.models import ApiAccessToken, ChecklistItem, Project, Tag, Task
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


_REPEAT_KEYS = {key for key, _ in Task.REPEAT_CHOICES if key}


def _parse_duration(value):
    """Длительность задачи в минутах: число, пусто или None."""
    if value in (None, ''):
        return None
    try:
        minutes = int(value)
    except (TypeError, ValueError):
        raise ValueError('duration_minutes должен быть числом минут')
    if minutes <= 0 or minutes > 24 * 60:
        raise ValueError('duration_minutes: от 1 до 1440')
    return minutes


def _parse_reminder(s):
    """Время персонального напоминания: 'YYYY-MM-DD HH:MM' (локальное) или пусто."""
    if s is None or s == '':
        return None
    if not isinstance(s, str):
        raise ValueError('reminder must be a string')
    text = s.strip().replace('T', ' ')
    for fmt in ('%Y-%m-%d %H:%M:%S', '%Y-%m-%d %H:%M'):
        try:
            naive = datetime.strptime(text, fmt)
        except ValueError:
            continue
        return timezone.make_aware(naive, timezone.get_current_timezone())
    raise ValueError('reminder must be YYYY-MM-DD HH:MM')


# Уровней всего: проект → подпроект → под-подпроект → под-под-подпроект.
PROJECT_MAX_LEVELS = 4


def _depth(project) -> int:
    """0 — проект верхнего уровня."""
    d, cur = 0, project
    while cur.parent_id:
        cur = cur.parent
        d += 1
        if d > 50:  # защита от испорченных данных с циклом
            break
    return d


def _subtree_height(project) -> int:
    """Сколько уровней под проектом (0 — нет подпроектов)."""
    children = list(project.children.all())
    return 1 + max(_subtree_height(c) for c in children) if children else 0


def _resolve_parent(user, project, raw):
    """Родитель проекта: только свой, без циклов и не глубже PROJECT_MAX_LEVELS уровней."""
    if raw in (None, ''):
        return None
    try:
        pid = int(raw)
    except (TypeError, ValueError):
        raise ValueError('parent_id должен быть числом или null')
    try:
        parent = Project.objects.get(pk=pid, user=user)
    except Project.DoesNotExist:
        raise ValueError('Родительский проект не найден')
    height = 0
    if project is not None:
        cur = parent
        while cur is not None:
            if cur.pk == project.pk:
                raise ValueError('Нельзя вложить проект в самого себя или в свой подпроект')
            cur = cur.parent
        height = _subtree_height(project)
    if _depth(parent) + 1 + height > PROJECT_MAX_LEVELS - 1:
        raise ValueError(f'Вложенность — не больше {PROJECT_MAX_LEVELS} уровней')
    return parent


AVATAR_MAX_BYTES = 5 * 1024 * 1024
AVATAR_TYPES = {'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp'}


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
        qs = Project.objects.filter(user=user, is_archived=archived)
        return JsonResponse({'data': [project_to_dict(p) for p in qs], 'meta': {'count': qs.count()}})

    data = _parse_body(request)
    if data is None:
        return _json_error('bad_json', 'Тело запроса не JSON', 400)
    name = (data.get('name') or '').strip()
    if not name:
        return _json_error('validation_error', 'Поле name обязательно')
    try:
        parent = _resolve_parent(user, None, data.get('parent_id'))
    except ValueError as e:
        return _json_error('validation_error', str(e))
    p = Project.objects.create(
        user=user,
        name=name[:200],
        description=(data.get('description') or '')[:5000],
        color=(data.get('color') or '#7C3AED')[:7],
        icon=(data.get('icon') or 'folder')[:50],
        parent=parent,
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
    if 'is_pinned' in data:
        p.is_pinned = bool(data['is_pinned'])
    if 'position' in data:
        try:
            p.position = int(data['position'])
        except (TypeError, ValueError):
            return _json_error('validation_error', 'position должен быть числом')
    if 'parent_id' in data:
        try:
            p.parent = _resolve_parent(user, p, data['parent_id'])
        except ValueError as e:
            return _json_error('validation_error', str(e))
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
        qs = Task.objects.filter(user=user).select_related('project').prefetch_related('tags', 'checklist_items')
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

    try:
        reminder_val = _parse_reminder(data.get('reminder'))
    except ValueError as e:
        return _json_error('validation_error', str(e))

    try:
        duration_val = _parse_duration(data.get('duration_minutes'))
    except ValueError as e:
        return _json_error('validation_error', str(e))

    repeat_val = str(data.get('repeat') or '')
    if repeat_val and repeat_val not in _REPEAT_KEYS:
        return _json_error('validation_error', f'repeat: допустимо {sorted(_REPEAT_KEYS)}')

    repeat_until_val = None
    if data.get('repeat_until'):
        try:
            repeat_until_val = _parse_date(data['repeat_until'])
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
        auto_complete=bool(data.get('auto_complete', False)),
        auto_delete=bool(data.get('auto_delete', False)),
        reminder=reminder_val,
        duration_minutes=duration_val,
        repeat=repeat_val,
        repeat_until=repeat_until_val,
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

    task.spawn_repeats()
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

    if 'auto_complete' in data:
        task.auto_complete = bool(data['auto_complete'])

    if 'auto_delete' in data:
        task.auto_delete = bool(data['auto_delete'])

    if 'reminder' in data:
        try:
            task.reminder = _parse_reminder(data['reminder'])
        except ValueError as e:
            return _json_error('validation_error', str(e))

    if 'duration_minutes' in data:
        try:
            task.duration_minutes = _parse_duration(data['duration_minutes'])
        except ValueError as e:
            return _json_error('validation_error', str(e))

    if 'repeat' in data:
        value = str(data.get('repeat') or '')
        if value and value not in _REPEAT_KEYS:
            return _json_error('validation_error', f'repeat: допустимо {sorted(_REPEAT_KEYS)}')
        task.repeat = value

    if 'repeat_until' in data:
        raw = data['repeat_until']
        if raw in (None, ''):
            task.repeat_until = None
        else:
            try:
                task.repeat_until = _parse_date(raw)
            except ValueError as e:
                return _json_error('validation_error', str(e))

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
    task.spawn_repeats()
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


# Вход из мобильного приложения: логин/пароль меняются на токен API v2.
# Сервер торчит наружу, поэтому неудачные попытки с одного адреса ограничены.
LOGIN_FAIL_LIMIT = 8
LOGIN_FAIL_WINDOW = 10 * 60


def _client_ip(request) -> str:
    forwarded = request.META.get('HTTP_X_FORWARDED_FOR', '')
    return (forwarded.split(',')[0].strip() if forwarded else '') or request.META.get('REMOTE_ADDR', '')


@csrf_exempt
@require_http_methods(['POST'])
def auth_login(request):
    from django.contrib.auth import authenticate
    from django.core.cache import cache

    data = _parse_body(request)
    if data is None:
        return _json_error('bad_json', 'Тело запроса не JSON', 400)

    key = f'scope_api_login_fail:{_client_ip(request)}'
    fails = cache.get(key, 0)
    if fails >= LOGIN_FAIL_LIMIT:
        return _json_error('throttled', 'Слишком много попыток, подождите 10 минут', 429)

    username = (data.get('username') or '').strip()
    password = data.get('password') or ''
    user = authenticate(request, username=username, password=password) if username and password else None
    if user is None or not user.is_active:
        cache.set(key, fails + 1, LOGIN_FAIL_WINDOW)
        return _json_error('invalid_credentials', 'Неверный логин или пароль', 401)

    cache.delete(key)
    device = str(data.get('device') or 'mobile')[:60]
    raw, _ = ApiAccessToken.issue(user, name=f'app: {device}')
    return JsonResponse({'data': {'token': raw, 'user': {'id': user.id, 'username': user.username}}}, status=201)


@v2
@require_http_methods(['POST'])
def auth_logout(request):
    from apps.scope.api_v2.auth import _hash_raw_token, extract_raw_token

    ApiAccessToken.objects.filter(key_hash=_hash_raw_token(extract_raw_token(request) or '')).update(is_active=False)
    return JsonResponse({'data': {'logged_out': True}})


@v2
@require_http_methods(['POST'])
def housekeeping(request):
    """То же, что мидлвара делает раз в день для браузера: у API нет сессии."""
    closed = Task.autoclose_past(request.user)
    spawned = Task.spawn_all_repeats(request.user)
    return JsonResponse({'data': {'closed': closed, 'spawned': spawned}})


@v2
@require_http_methods(['POST', 'DELETE'])
def project_avatar(request, pk: int):
    """POST multipart с полем file — поставить аватарку, DELETE — убрать."""
    try:
        p = Project.objects.get(pk=pk, user=request.user)
    except Project.DoesNotExist:
        return _json_error('not_found', 'Проект не найден', 404)

    if request.method == 'DELETE':
        if p.avatar:
            p.avatar.delete(save=False)
        p.avatar = ''
        p.save(update_fields=['avatar', 'updated_at'])
        return JsonResponse({'data': project_to_dict(p)})

    upload = request.FILES.get('file')
    if upload is None:
        return _json_error('validation_error', 'Нужен файл в поле file')
    ext = AVATAR_TYPES.get((upload.content_type or '').lower())
    if ext is None:
        return _json_error('validation_error', 'Аватарка: только JPEG, PNG или WebP')
    if upload.size > AVATAR_MAX_BYTES:
        return _json_error('validation_error', 'Аватарка больше 5 МБ')

    old = p.avatar.name if p.avatar else None
    p.avatar.save(f'project-{p.pk}-{timezone.now():%Y%m%d%H%M%S}.{ext}', upload, save=False)
    p.save(update_fields=['avatar', 'updated_at'])
    if old and old != p.avatar.name:
        p.avatar.storage.delete(old)
    return JsonResponse({'data': project_to_dict(p)})


@v2
@require_http_methods(['POST'])
def checklist_collection(request, pk: int):
    """Добавить пункт чек-листа. Ответ — задача целиком, чтобы клиенту не склеивать."""
    try:
        task = Task.objects.get(pk=pk, user=request.user)
    except Task.DoesNotExist:
        return _json_error('not_found', 'Задача не найдена', 404)
    data = _parse_body(request)
    if data is None:
        return _json_error('bad_json', 'Тело запроса не JSON', 400)
    text = (data.get('text') or '').strip()
    if not text:
        return _json_error('validation_error', 'Поле text обязательно')
    last = task.checklist_items.aggregate(m=Max('order'))['m']
    ChecklistItem.objects.create(task=task, text=text[:500], order=(last if last is not None else -1) + 1)
    return JsonResponse({'data': task_to_dict(task)}, status=201)


@v2
@require_http_methods(['PATCH', 'DELETE'])
def checklist_item(request, pk: int):
    try:
        item = ChecklistItem.objects.select_related('task').get(pk=pk, task__user=request.user)
    except ChecklistItem.DoesNotExist:
        return _json_error('not_found', 'Пункт не найден', 404)
    task = item.task
    if request.method == 'DELETE':
        item.delete()
        return JsonResponse({'data': task_to_dict(task)})
    data = _parse_body(request)
    if data is None:
        return _json_error('bad_json', 'Тело запроса не JSON', 400)
    if 'text' in data and (data.get('text') or '').strip():
        item.text = data['text'].strip()[:500]
    if 'is_completed' in data:
        item.is_completed = bool(data['is_completed'])
    item.save()
    return JsonResponse({'data': task_to_dict(task)})


@v2
@require_http_methods(['POST'])
def projects_reorder(request):
    """Порядок проектов после перетаскивания: {"ids": [3, 1, 2]} — сверху вниз."""
    data = _parse_body(request)
    if data is None or not isinstance(data.get('ids'), list):
        return _json_error('validation_error', 'Нужен массив ids')
    try:
        ids = [int(x) for x in data['ids']]
    except (TypeError, ValueError):
        return _json_error('validation_error', 'ids — только числа')
    owned = set(Project.objects.filter(user=request.user, pk__in=ids).values_list('pk', flat=True))
    if owned != set(ids):
        return _json_error('validation_error', 'Не все проекты найдены')
    for position, pk in enumerate(ids):
        Project.objects.filter(pk=pk).update(position=position)
    return JsonResponse({'data': {'reordered': len(ids)}})


@v2
@require_http_methods(['PATCH', 'DELETE'])
def tag_detail(request, pk: int):
    try:
        tag = Tag.objects.get(pk=pk, user=request.user)
    except Tag.DoesNotExist:
        return _json_error('not_found', 'Тег не найден', 404)
    if request.method == 'DELETE':
        tag.delete()
        return JsonResponse({'data': {'deleted': True}})
    data = _parse_body(request)
    if data is None:
        return _json_error('bad_json', 'Тело запроса не JSON', 400)
    if (data.get('name') or '').strip():
        tag.name = data['name'].strip()[:50]
    if data.get('color'):
        tag.color = str(data['color'])[:7]
    tag.save()
    return JsonResponse({'data': tag_to_dict(tag)})


# ---------- обновления приложения ----------
# Сборки лежат в MEDIA_ROOT/app_releases/, описание последних — в latest.json.
# Публикуются командой `manage.py scope_publish_app`.

APP_PLATFORMS = ('android', 'windows')


def app_releases_dir():
    from pathlib import Path

    from django.conf import settings

    return Path(settings.MEDIA_ROOT) / 'app_releases'


def read_app_manifest() -> dict:
    path = app_releases_dir() / 'latest.json'
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return {}


@v2
@require_GET
def app_latest(request):
    """Последняя опубликованная сборка: ?platform=android|windows."""
    from django.conf import settings

    platform = request.GET.get('platform', '')
    if platform not in APP_PLATFORMS:
        return _json_error('validation_error', f'platform: {", ".join(APP_PLATFORMS)}')
    entry = read_app_manifest().get(platform)
    if not entry:
        return JsonResponse({'data': None})
    return JsonResponse({
        'data': {
            **entry,
            'url': f"{settings.MEDIA_URL}app_releases/{entry['file']}",
        }
    })



# ---------- задачи из ERP ----------

ERP_SYNC_COOLDOWN_SECONDS = 60


def _erp_states(user) -> list[dict]:
    from apps.scope.erp_sync import sources
    from apps.scope.models import ErpSyncState

    states = {s.source: s for s in ErpSyncState.objects.filter(user=user)}
    out = []
    for src in sources():
        st = states.get(src.key)
        out.append({
            'source': src.key,
            'name': src.name,
            'last_run': st.last_run.isoformat() if st and st.last_run else None,
            'open_tasks': st.open_tasks if st else 0,
            'error': st.last_error if st else '',
        })
    return out


@v2
@require_http_methods(['GET', 'POST'])
def erp_sync(request):
    """GET — состояние синхронизации, POST — подтянуть задачи из ERP сейчас.

    Работает только для владельца ERP-токенов (ERP_SYNC_USERNAME); чаще раза
    в минуту в ERP не ходим — приложение дёргает это при каждом обновлении.
    """
    from apps.scope.erp_sync import sync_all, sync_user
    from apps.scope.models import ErpSyncState

    owner = sync_user()
    if owner is None or owner.pk != request.user.pk:
        return JsonResponse({'data': {'enabled': False, 'sources': []}})
    ran = False
    if request.method == 'POST':
        last = ErpSyncState.objects.filter(user=owner).order_by('-last_run').values_list('last_run', flat=True).first()
        force = request.GET.get('force') in ('1', 'true')
        if force or last is None or (timezone.now() - last).total_seconds() > ERP_SYNC_COOLDOWN_SECONDS:
            sync_all(owner)
            ran = True
    return JsonResponse({'data': {'enabled': True, 'ran': ran, 'sources': _erp_states(owner)}})
