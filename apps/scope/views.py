from django.shortcuts import render, get_object_or_404, redirect
from django.http import JsonResponse
from django.views.decorators.http import require_POST, require_GET
from django.contrib.auth.decorators import login_required
from django.utils import timezone
from django.db.models import Q, Count, Max
from datetime import datetime, timedelta, date
import json

from .models import Task, Project, Tag, ChecklistItem, TaskNote, TaskLink, TaskAttachment


def get_sidebar_context(user):
    """Общий контекст для боковой панели - фильтрация по пользователю"""
    return {
        'projects': Project.objects.filter(user=user, is_archived=False),
        'tags': Tag.objects.filter(user=user),
        'today_count': Task.objects.filter(
            user=user,
            due_date=timezone.now().date(),
            is_completed=False
        ).count(),
        'all_count': Task.objects.filter(user=user, is_completed=False).count(),
    }


# ==================
# Главные страницы
# ==================

@login_required
def dashboard(request):
    """Главная страница - все задачи"""
    tasks = Task.objects.filter(user=request.user, is_completed=False)
    completed_tasks = Task.objects.filter(user=request.user, is_completed=True)[:10]
    
    # Фильтрация
    project_id = request.GET.get('project')
    tag_id = request.GET.get('tag')
    priority = request.GET.get('priority')
    search = request.GET.get('search')
    
    if project_id:
        tasks = tasks.filter(project_id=project_id)
    if tag_id:
        tasks = tasks.filter(tags__id=tag_id)
    if priority:
        tasks = tasks.filter(priority=priority)
    if search:
        tasks = tasks.filter(Q(title__icontains=search) | Q(description__icontains=search))
    
    context = {
        'tasks': tasks,
        'completed_tasks': completed_tasks,
        'page_title': 'Все задачи',
        'current_page': 'dashboard',
        **get_sidebar_context(request.user),
    }
    return render(request, 'scope/dashboard.html', context)


@login_required
def today_view(request):
    """Задачи на сегодня"""
    today = timezone.now().date()
    tasks = Task.objects.filter(user=request.user, due_date=today, is_completed=False)
    overdue_tasks = Task.objects.filter(user=request.user, due_date__lt=today, is_completed=False)
    
    context = {
        'tasks': tasks,
        'overdue_tasks': overdue_tasks,
        'page_title': 'Сегодня',
        'current_page': 'today',
        'today': today,
        **get_sidebar_context(request.user),
    }
    return render(request, 'scope/today.html', context)


@login_required
def calendar_view(request):
    """Календарный вид"""
    context = {
        'page_title': 'Календарь',
        'current_page': 'calendar',
        **get_sidebar_context(request.user),
    }
    return render(request, 'scope/calendar.html', context)


# ==================
# Проекты
# ==================

@login_required
def project_list(request):
    """Список проектов"""
    projects = Project.objects.filter(user=request.user, is_archived=False)
    archived_projects = Project.objects.filter(user=request.user, is_archived=True)
    
    context = {
        'page_title': 'Проекты',
        'current_page': 'projects',
        'project_list': projects,
        'archived_projects': archived_projects,
        **get_sidebar_context(request.user),
    }
    return render(request, 'scope/project_list.html', context)


@login_required
def project_detail(request, pk):
    """Детали проекта"""
    project = get_object_or_404(Project, pk=pk, user=request.user)
    tasks = project.tasks.filter(is_completed=False)
    completed_tasks = project.tasks.filter(is_completed=True)
    
    context = {
        'project': project,
        'tasks': tasks,
        'completed_tasks': completed_tasks,
        'page_title': project.name,
        'current_page': f'project_{pk}',
        **get_sidebar_context(request.user),
    }
    return render(request, 'scope/project_detail.html', context)


@login_required
def project_create(request):
    """Создание проекта"""
    if request.method == 'POST':
        name = request.POST.get('name')
        description = request.POST.get('description', '')
        color = request.POST.get('color', '#7C3AED')
        icon = request.POST.get('icon', 'folder')
        
        project = Project.objects.create(
            name=name,
            description=description,
            color=color,
            icon=icon,
            user=request.user,
        )
        
        if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
            return JsonResponse({'success': True, 'id': project.id, 'name': project.name})
        return redirect('scope:project_detail', pk=project.id)
    
    context = {
        'page_title': 'Новый проект',
        'current_page': 'projects',
        **get_sidebar_context(request.user),
    }
    return render(request, 'scope/project_form.html', context)


@login_required
def project_edit(request, pk):
    """Редактирование проекта"""
    project = get_object_or_404(Project, pk=pk, user=request.user)
    
    if request.method == 'POST':
        # Обновляем только переданные поля
        if 'name' in request.POST:
            project.name = request.POST.get('name') or project.name
        if 'description' in request.POST:
            project.description = request.POST.get('description', '')
        if 'color' in request.POST:
            project.color = request.POST.get('color', project.color)
        if 'icon' in request.POST:
            project.icon = request.POST.get('icon', project.icon)
        if 'is_archived' in request.POST:
            project.is_archived = request.POST.get('is_archived') == 'true'
        project.save()
        
        if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
            return JsonResponse({'success': True})
        return redirect('scope:project_detail', pk=project.id)
    
    context = {
        'project': project,
        'page_title': f'Редактировать {project.name}',
        'current_page': f'project_{pk}',
        **get_sidebar_context(request.user),
    }
    return render(request, 'scope/project_form.html', context)


@login_required
@require_POST
def project_delete(request, pk):
    """Удаление проекта"""
    project = get_object_or_404(Project, pk=pk, user=request.user)
    project.delete()
    
    if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
        return JsonResponse({'success': True})
    return redirect('scope:project_list')


@login_required
@require_POST
def project_restore(request, pk):
    """Восстановление проекта из архива"""
    project = get_object_or_404(Project, pk=pk, user=request.user)
    project.is_archived = False
    project.save()
    
    if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
        return JsonResponse({'success': True})
    return redirect('scope:project_list')


# ==================
# Задачи
# ==================

@login_required
def task_create(request):
    """Создание задачи"""
    if request.method == 'POST':
        title = request.POST.get('title')
        description = request.POST.get('description', '')
        project_id = request.POST.get('project')
        priority = request.POST.get('priority', 2)
        due_date = request.POST.get('due_date')
        due_time = request.POST.get('due_time')
        tag_ids = request.POST.getlist('tags')
        
        order_val = 0
        if due_date:
            max_o = Task.objects.filter(user=request.user, due_date=due_date).aggregate(m=Max('order'))['m']
            order_val = (max_o if max_o is not None else -1) + 1

        task = Task.objects.create(
            title=title,
            description=description,
            project_id=project_id if project_id else None,
            priority=int(priority),
            due_date=due_date if due_date else None,
            due_time=due_time if due_time else None,
            user=request.user,
            order=order_val,
        )
        
        if tag_ids:
            task.tags.set(tag_ids)
        
        if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
            return JsonResponse({
                'success': True,
                'id': task.id,
                'title': task.title,
                'html': render_task_html(task),
            })
        
        next_url = request.POST.get('next', 'scope:dashboard')
        return redirect(next_url)
    
    context = {
        'page_title': 'Новая задача',
        'current_page': 'dashboard',
        **get_sidebar_context(request.user),
    }
    return render(request, 'scope/task_form.html', context)


@login_required
def task_detail(request, pk):
    """Детальная страница задачи"""
    task = get_object_or_404(Task, pk=pk, user=request.user)
    
    context = {
        'task': task,
        'page_title': task.title,
        'current_page': 'dashboard',
        **get_sidebar_context(request.user),
    }
    return render(request, 'scope/task_detail.html', context)


@login_required
def task_edit(request, pk):
    """Редактирование задачи"""
    task = get_object_or_404(Task, pk=pk, user=request.user)
    
    if request.method == 'POST':
        task.title = request.POST.get('title', task.title)
        task.description = request.POST.get('description', task.description)
        task.priority = int(request.POST.get('priority', task.priority))
        
        project_id = request.POST.get('project')
        task.project_id = project_id if project_id else None
        
        due_date_raw = request.POST.get('due_date')
        parsed_date = datetime.strptime(due_date_raw, '%Y-%m-%d').date() if due_date_raw else None
        if parsed_date != task.due_date:
            task.due_date = parsed_date
            if parsed_date:
                max_o = Task.objects.filter(
                    user=request.user, due_date=parsed_date
                ).exclude(pk=task.pk).aggregate(m=Max('order'))['m']
                task.order = (max_o if max_o is not None else -1) + 1
            else:
                task.order = 0

        due_time = request.POST.get('due_time')
        task.due_time = due_time if due_time else None

        tag_ids = request.POST.getlist('tags')
        task.tags.set(tag_ids)

        task.save()
        
        if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
            return JsonResponse({'success': True})
        return redirect('scope:task_detail', pk=task.id)
    
    context = {
        'task': task,
        'page_title': f'Редактировать задачу',
        'current_page': 'dashboard',
        **get_sidebar_context(request.user),
    }
    return render(request, 'scope/task_form.html', context)


@login_required
@require_POST
def task_delete(request, pk):
    """Удаление задачи"""
    task = get_object_or_404(Task, pk=pk, user=request.user)
    task.delete()
    
    if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
        return JsonResponse({'success': True})
    return redirect('scope:dashboard')


@login_required
@require_POST
def task_toggle(request, pk):
    """Переключение статуса задачи"""
    task = get_object_or_404(Task, pk=pk, user=request.user)
    task.is_completed = not task.is_completed
    task.save()
    
    return JsonResponse({
        'success': True,
        'is_completed': task.is_completed,
    })


@login_required
@require_POST
def task_update_inline(request, pk):
    """Инлайн обновление задачи (название, приоритет)"""
    task = get_object_or_404(Task, pk=pk, user=request.user)
    
    # Обновляем только переданные поля
    title = request.POST.get('title')
    priority = request.POST.get('priority')
    
    if title is not None and title.strip():
        task.title = title.strip()
    
    if priority is not None:
        try:
            task.priority = int(priority)
        except ValueError:
            pass
    
    task.save()
    
    return JsonResponse({
        'success': True,
        'title': task.title,
        'priority': task.priority,
        'priority_display': task.get_priority_display(),
    })


# ==================
# Чек-листы
# ==================

@login_required
@require_POST
def checklist_add(request, task_pk):
    """Добавление элемента чек-листа"""
    task = get_object_or_404(Task, pk=task_pk, user=request.user)
    text = request.POST.get('text')
    
    if text:
        item = ChecklistItem.objects.create(task=task, text=text)
        return JsonResponse({
            'success': True,
            'id': item.id,
            'text': item.text,
        })
    return JsonResponse({'success': False, 'error': 'Текст обязателен'})


@login_required
@require_POST
def checklist_toggle(request, pk):
    """Переключение статуса элемента чек-листа"""
    item = get_object_or_404(ChecklistItem, pk=pk, task__user=request.user)
    item.is_completed = not item.is_completed
    item.save()
    
    progress = item.task.checklist_progress
    return JsonResponse({
        'success': True,
        'is_completed': item.is_completed,
        'progress': progress,
    })


@login_required
@require_POST
def checklist_delete(request, pk):
    """Удаление элемента чек-листа"""
    item = get_object_or_404(ChecklistItem, pk=pk, task__user=request.user)
    task = item.task
    item.delete()
    
    progress = task.checklist_progress
    return JsonResponse({
        'success': True,
        'progress': progress,
    })


# ==================
# Ссылки
# ==================

@login_required
@require_POST
def link_add(request, task_pk):
    """Добавление ссылки к задаче"""
    task = get_object_or_404(Task, pk=task_pk, user=request.user)
    url = request.POST.get('url', '').strip()
    title = request.POST.get('title', '').strip()
    
    if not url:
        return JsonResponse({'success': False, 'error': 'URL обязателен'})
    
    # Добавляем http:// если нет протокола
    if not url.startswith(('http://', 'https://')):
        url = 'https://' + url
    
    link = TaskLink.objects.create(task=task, url=url, title=title)
    
    return JsonResponse({
        'success': True,
        'id': link.id,
        'url': link.url,
        'title': link.display_title,
        'favicon': link.favicon_url,
    })


@login_required
@require_POST
def link_delete(request, pk):
    """Удаление ссылки"""
    link = get_object_or_404(TaskLink, pk=pk, task__user=request.user)
    link.delete()
    return JsonResponse({'success': True})


# ==================
# Вложения
# ==================

@login_required
@require_POST
def attachment_add(request, task_pk):
    """Добавление вложения к задаче"""
    task = get_object_or_404(Task, pk=task_pk, user=request.user)
    
    if 'file' not in request.FILES:
        return JsonResponse({'success': False, 'error': 'Файл не выбран'})
    
    uploaded_file = request.FILES['file']
    
    # Ограничение размера файла (1 ГБ)
    max_size = 1024 * 1024 * 1024  # 1 GB
    if uploaded_file.size > max_size:
        return JsonResponse({'success': False, 'error': 'Файл слишком большой (макс. 1 ГБ)'})
    
    attachment = TaskAttachment.objects.create(
        task=task,
        file=uploaded_file,
        filename=uploaded_file.name,
        file_size=uploaded_file.size,
    )
    
    return JsonResponse({
        'success': True,
        'id': attachment.id,
        'filename': attachment.filename,
        'file_size': attachment.file_size_display,
        'file_url': attachment.file.url,
        'icon': attachment.file_icon,
    })


@login_required
@require_POST
def attachment_delete(request, pk):
    """Удаление вложения"""
    attachment = get_object_or_404(TaskAttachment, pk=pk, task__user=request.user)
    # Удаляем файл
    if attachment.file:
        attachment.file.delete(save=False)
    attachment.delete()
    return JsonResponse({'success': True})


# ==================
# Теги
# ==================

@login_required
def tag_list(request):
    """Список тегов"""
    tags = Tag.objects.filter(user=request.user)
    
    context = {
        'tag_list': tags,
        'page_title': 'Теги',
        'current_page': 'tags',
        **get_sidebar_context(request.user),
    }
    return render(request, 'scope/tag_list.html', context)


@login_required
def tag_create(request):
    """Создание тега"""
    if request.method == 'POST':
        name = request.POST.get('name')
        color = request.POST.get('color', '#7C3AED')
        
        tag = Tag.objects.create(name=name, color=color, user=request.user)
        
        if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
            return JsonResponse({'success': True, 'id': tag.id, 'name': tag.name, 'color': tag.color})
        return redirect('scope:tag_list')
    
    return render(request, 'scope/tag_form.html', get_sidebar_context(request.user))


@login_required
@require_POST
def tag_delete(request, pk):
    """Удаление тега"""
    tag = get_object_or_404(Tag, pk=pk, user=request.user)
    tag.delete()
    
    if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
        return JsonResponse({'success': True})
    return redirect('scope:tag_list')


# ==================
# API
# ==================

@login_required
@require_GET
def api_tasks(request):
    """API для получения задач"""
    tasks = Task.objects.filter(user=request.user)
    
    project_id = request.GET.get('project')
    completed = request.GET.get('completed')
    
    if project_id:
        tasks = tasks.filter(project_id=project_id)
    if completed:
        tasks = tasks.filter(is_completed=completed == 'true')
    
    data = [{
        'id': task.id,
        'title': task.title,
        'description': task.description,
        'is_completed': task.is_completed,
        'priority': task.priority,
        'due_date': task.due_date.isoformat() if task.due_date else None,
        'project': task.project.name if task.project else None,
    } for task in tasks]
    
    return JsonResponse({'tasks': data})


@login_required
@require_GET
def api_calendar_events(request):
    """API для календаря"""
    start = request.GET.get('start')
    end = request.GET.get('end')
    
    tasks = Task.objects.filter(user=request.user, due_date__isnull=False).select_related('project')
    
    if start:
        tasks = tasks.filter(due_date__gte=start)
    if end:
        tasks = tasks.filter(due_date__lte=end)
    
    events = []
    for task in tasks:
        # Цвет по приоритету
        priority_colors = {
            1: '#22C55E',  # Зелёный - низкий
            2: '#3B82F6',  # Синий - средний
            3: '#F59E0B',  # Оранжевый - высокий
            4: '#EF4444',  # Красный - срочный
        }
        color = priority_colors.get(task.priority, '#7C3AED')
        
        if task.is_completed:
            color = '#22C55E'  # Зелёный для завершённых
        elif task.is_overdue:
            color = '#EF4444'  # Красный для просроченных
        
        events.append({
            'id': task.id,
            'title': task.title,
            'description': task.description[:100] if task.description else '',
            'start': task.due_date.isoformat(),
            'time': task.due_time.strftime('%H:%M') if task.due_time else None,
            'color': color,
            'priority': task.priority,
            'completed': task.is_completed,
            'url': f'/tasks/{task.id}/',
            'project': task.project.name if task.project else None,
            'projectColor': task.project.color if task.project else None,
        })
    
    return JsonResponse(events, safe=False)


# ==================
# Вспомогательные функции
# ==================

@login_required
@require_POST
def task_update_date(request, pk):
    """Обновление даты задачи (для drag-and-drop в канбане) — в конец списка дня"""
    task = get_object_or_404(Task, pk=pk, user=request.user)
    due_date_str = request.POST.get('due_date', '').strip()
    if due_date_str:
        task.due_date = datetime.strptime(due_date_str, '%Y-%m-%d').date()
        siblings = Task.objects.filter(
            user=request.user, due_date=task.due_date
        ).exclude(pk=task.pk)
        max_o = siblings.aggregate(m=Max('order'))['m']
        task.order = (max_o if max_o is not None else -1) + 1
    else:
        task.due_date = None
        task.order = 0
    task.save()
    return JsonResponse({
        'success': True,
        'due_date': task.due_date.isoformat() if task.due_date else None,
        'order': task.order,
    })


@login_required
@require_POST
def task_kanban_reorder(request, pk):
    """Порядок задачи в дне календаря: due_date + вставка перед before_id (пусто = в конец)"""
    task = get_object_or_404(Task, pk=pk, user=request.user)
    due_date_str = request.POST.get('due_date', '').strip()
    if not due_date_str:
        return JsonResponse({'success': False, 'error': 'due_date required'}, status=400)
    new_date = datetime.strptime(due_date_str, '%Y-%m-%d').date()

    before_raw = request.POST.get('before_id', '').strip()
    before_id = None
    if before_raw:
        try:
            before_id = int(before_raw)
        except ValueError:
            before_id = None

    others = list(
        Task.objects.filter(user=request.user, due_date=new_date)
        .exclude(pk=task.pk)
        .order_by('order', 'id')
    )

    if before_id is not None and not any(t.id == before_id for t in others):
        before_id = None

    new_list = []
    inserted = False
    for t in others:
        if before_id is not None and t.id == before_id and not inserted:
            new_list.append(task)
            inserted = True
        new_list.append(t)
    if not inserted:
        new_list.append(task)

    task.due_date = new_date
    for i, t in enumerate(new_list):
        t.order = i
    Task.objects.bulk_update(new_list, ['order', 'due_date'])

    return JsonResponse({
        'success': True,
        'due_date': new_date.isoformat(),
        'orders': [{'id': t.id, 'order': t.order} for t in new_list],
    })


@login_required
@require_GET
def api_stats(request):
    """API статистики продуктивности"""
    user = request.user
    today = timezone.now().date()
    week_start = today - timedelta(days=today.weekday())

    completed_today = Task.objects.filter(
        user=user, is_completed=True, completed_at__date=today
    ).count()
    completed_this_week = Task.objects.filter(
        user=user, is_completed=True, completed_at__date__gte=week_start
    ).count()
    total_active = Task.objects.filter(user=user, is_completed=False).count()
    total_completed = Task.objects.filter(user=user, is_completed=True).count()
    overdue = Task.objects.filter(
        user=user, is_completed=False, due_date__lt=today
    ).count()
    today_tasks = Task.objects.filter(
        user=user, is_completed=False, due_date=today
    ).count()

    streak = 0
    check_date = today
    while True:
        if Task.objects.filter(user=user, is_completed=True, completed_at__date=check_date).exists():
            streak += 1
            check_date -= timedelta(days=1)
        else:
            break

    return JsonResponse({
        'completed_today': completed_today,
        'completed_this_week': completed_this_week,
        'total_active': total_active,
        'total_completed': total_completed,
        'overdue': overdue,
        'today_tasks': today_tasks,
        'streak': streak,
    })


@login_required
@require_GET
def api_kanban_events(request):
    """API для канбан-календаря — задачи на указанный период"""
    start = request.GET.get('start')
    end = request.GET.get('end')

    tasks = Task.objects.filter(
        user=request.user, due_date__isnull=False
    ).select_related('project').prefetch_related('tags').order_by('due_date', 'order', 'id')

    if start:
        tasks = tasks.filter(due_date__gte=start)
    if end:
        tasks = tasks.filter(due_date__lte=end)

    events = []
    for task in tasks:
        priority_labels = {1: 'low', 2: 'medium', 3: 'high', 4: 'urgent'}
        events.append({
            'id': task.id,
            'order': task.order,
            'title': task.title,
            'start': task.due_date.isoformat(),
            'time': task.due_time.strftime('%H:%M') if task.due_time else None,
            'priority': task.priority,
            'priority_class': priority_labels.get(task.priority, 'medium'),
            'completed': task.is_completed,
            'overdue': task.is_overdue,
            'project': task.project.name if task.project else None,
            'projectColor': task.project.color if task.project else None,
            'tags': [{'name': t.name, 'color': t.color} for t in task.tags.all()],
            'url': f'/tasks/{task.id}/',
        })

    return JsonResponse(events, safe=False)


@login_required
@require_GET
def api_sidebar(request):
    """API для обновления сайдбара — проекты, теги, счётчики"""
    user = request.user
    today = timezone.now().date()

    projects = list(Project.objects.filter(user=user, is_archived=False).values(
        'id', 'name', 'color'
    ))
    for p in projects:
        p['task_count'] = Task.objects.filter(
            project_id=p['id'], user=user, is_completed=False
        ).count()

    tags = list(Tag.objects.filter(user=user).values('id', 'name', 'color'))

    return JsonResponse({
        'projects': projects,
        'tags': tags,
        'today_count': Task.objects.filter(user=user, due_date=today, is_completed=False).count(),
        'all_count': Task.objects.filter(user=user, is_completed=False).count(),
    })


def render_task_html(task):
    """Рендерит HTML для одной задачи (для AJAX)"""
    priority_classes = {1: 'low', 2: 'medium', 3: 'high', 4: 'urgent'}
    priority_class = priority_classes.get(task.priority, 'medium')
    
    html = f'''
    <div class="task-item" data-id="{task.id}" data-priority="{task.priority}">
        <div class="task-checkbox">
            <input type="checkbox" id="task-{task.id}" {'checked' if task.is_completed else ''}>
            <label for="task-{task.id}"></label>
        </div>
        <div class="task-content">
            <a href="/tasks/{task.id}/" class="task-title">{task.title}</a>
            <div class="task-meta">
    '''
    
    if task.due_date:
        html += f'<span class="task-due">📅 {task.due_date}</span>'
    
    if task.project:
        html += f'<span class="task-project" style="color: {task.project.color}">{task.project.name}</span>'
    
    html += f'''
            </div>
        </div>
        <div class="task-priority priority-{priority_class}"></div>
    </div>
    '''
    
    return html
