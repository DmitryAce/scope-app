from decimal import Decimal

from django.shortcuts import render, get_object_or_404, redirect
from django.http import JsonResponse
from django.views.decorators.http import require_POST, require_GET
from django.contrib.auth.decorators import login_required
from django.utils import timezone
from django.db.models import Q, Count, Max, Sum
from datetime import datetime, timedelta, date
from calendar import monthrange
from collections import defaultdict
import json
import re

from .models import (
    Task,
    Project,
    Tag,
    ChecklistItem,
    TaskNote,
    TaskLink,
    TaskAttachment,
    BudgetMonthlyItem,
    ExpenseEntry,
    DailyBudgetPeriod,
    BulletTask,
    BulletTaskCompletion,
)


def get_sidebar_context(user):
    """Общий контекст для боковой панели - фильтрация по пользователю"""
    ctx = {
        'projects': Project.objects.filter(user=user, is_archived=False),
        'tags': Tag.objects.filter(user=user),
        'today_count': Task.objects.filter(
            user=user,
            due_date=timezone.now().date(),
            is_completed=False
        ).count(),
        'all_count': Task.objects.filter(user=user, is_completed=False).count(),
    }
    today = timezone.now().date()
    ctx['budget_sidebar'] = compute_budget_summary(user, today.year, today.month)
    ctx['daily_budget_active_period_id'] = active_daily_budget_period_id(user)
    return ctx


MONTH_NAMES_RU = (
    '', 'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
    'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
)
MONTH_NAMES_RU_SHORT = (
    '', 'янв.', 'фев.', 'мар.', 'апр.', 'мая', 'июн.',
    'июл.', 'авг.', 'сен.', 'окт.', 'ноя.', 'дек.',
)


def compute_budget_summary(user, year, month):
    """Сводка по бюджету за месяц (сайдбар + API). Суммы = сумма полей в строках."""
    year = max(2000, min(2100, int(year)))
    month = max(1, min(12, int(month)))
    items = list(
        BudgetMonthlyItem.objects.filter(user=user, year=year, month=month).order_by('sort_order', 'id')
    )
    total_planned = sum((i.amount_planned for i in items), Decimal('0'))
    total_set_aside = sum((i.amount_set_aside for i in items), Decimal('0'))
    total_remaining = sum((i.remaining for i in items), Decimal('0'))
    exp_total = ExpenseEntry.objects.filter(user=user, date__year=year, date__month=month).aggregate(
        t=Sum('amount')
    )['t'] or Decimal('0')
    pct = 0
    if total_planned > 0:
        pct = int(min(100, round(float(total_set_aside / total_planned * 100))))
    preview = [
        {
            'title': i.title,
            'remaining': str(i.remaining),
        }
        for i in items[:4]
    ]
    return {
        'year': year,
        'month': month,
        'month_label_short': f'{MONTH_NAMES_RU_SHORT[month]} {year}',
        'month_label': f'{MONTH_NAMES_RU[month]} {year}',
        'total_planned': total_planned,
        'total_set_aside': total_set_aside,
        'total_remaining': total_remaining,
        'expenses_month': exp_total,
        'progress_pct': pct,
        'preview': preview,
        'items_count': len(items),
    }


def active_daily_budget_period_id(user):
    t = timezone.now().date()
    return DailyBudgetPeriod.objects.filter(
        user=user, start_date__lte=t, end_date__gte=t
    ).order_by('-created_at').values_list('id', flat=True).first()


def compute_daily_budget_ledger(period):
    """Строки: перенос + норма = доступно; минус траты = перенос на завтра."""
    if not period:
        return []
    spent_qs = (
        ExpenseEntry.objects.filter(daily_budget_period=period)
        .values('date')
        .annotate(total=Sum('amount'))
    )
    spent_map = {row['date']: row['total'] for row in spent_qs}
    rows = []
    carry = Decimal('0')
    B = period.daily_allowance
    d = period.start_date
    today = timezone.now().date()
    while d <= period.end_date:
        carry_in = carry
        available = carry_in + B
        spent = spent_map.get(d, Decimal('0'))
        carry_out = available - spent
        rows.append({
            'date': d,
            'carry_in': carry_in,
            'daily_base': B,
            'available': available,
            'spent': spent,
            'carry_out': carry_out,
            'is_future': d > today,
            'is_neg_carry': carry_out < 0,
            'is_pos_carry': carry_out > 0,
        })
        carry = carry_out
        d += timedelta(days=1)
    return rows


def _parse_json(request):
    try:
        return json.loads(request.body.decode() or '{}')
    except json.JSONDecodeError:
        return {}


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


@login_required
def bullet_tasks_view(request):
    """Микрозадачи BulletTasks"""
    context = {
        'page_title': 'Микроцели',
        'current_page': 'bullet_tasks',
        **get_sidebar_context(request.user),
    }
    return render(request, 'scope/bullet_tasks.html', context)


def _daily_periods_for_calendar_month(user, y, m):
    """Периоды дневного лимита, которые пересекаются с календарным месяцем (y, m)."""
    month_start = date(y, m, 1)
    month_end = date(y, m, monthrange(y, m)[1])
    return list(
        DailyBudgetPeriod.objects.filter(
            user=user,
            start_date__lte=month_end,
            end_date__gte=month_start,
        ).order_by('-start_date', '-id')
    )


def _pick_daily_period_for_month(user, y, m, daily_periods, requested_pk=None):
    """
    Выбор периода для экрана бюджета: только из пересечений с месяцем.
    requested_pk — из ?daily_period= если период действительно попадает в этот месяц.
    """
    today = timezone.now().date()
    month_start = date(y, m, 1)
    month_end = date(y, m, monthrange(y, m)[1])
    if not daily_periods:
        return None
    if requested_pk is not None:
        try:
            cand = DailyBudgetPeriod.objects.get(pk=int(requested_pk), user=user)
        except (ValueError, DailyBudgetPeriod.DoesNotExist):
            cand = None
        else:
            if cand.start_date <= month_end and cand.end_date >= month_start:
                return cand
    anchor = today if (today.year == y and today.month == m) else month_start
    for p in daily_periods:
        if p.start_date <= anchor <= p.end_date:
            return p
    return daily_periods[0]


@login_required
def budget_view(request):
    """Планировщик бюджета: обязательные платежи и расходы за месяц."""
    today = timezone.now().date()
    y = int(request.GET.get('year', today.year))
    m = int(request.GET.get('month', today.month))
    y = max(2000, min(2100, y))
    m = max(1, min(12, m))

    if m == 12:
        next_y, next_m = y + 1, 1
    else:
        next_y, next_m = y, m + 1
    if m == 1:
        prev_y, prev_m = y - 1, 12
    else:
        prev_y, prev_m = y, m - 1

    items = BudgetMonthlyItem.objects.filter(user=request.user, year=y, month=m).order_by('sort_order', 'id')
    expenses = ExpenseEntry.objects.filter(user=request.user, date__year=y, date__month=m)[:500]
    summary = compute_budget_summary(request.user, y, m)

    daily_periods = _daily_periods_for_calendar_month(request.user, y, m)
    dp_param = request.GET.get('daily_period')
    req_pk = int(dp_param) if (dp_param and str(dp_param).isdigit()) else None
    selected_daily = _pick_daily_period_for_month(
        request.user, y, m, daily_periods, requested_pk=req_pk
    )
    daily_ledger = compute_daily_budget_ledger(selected_daily) if selected_daily else []

    _, last_dom = monthrange(y, m)
    budget_calendar_month_start = date(y, m, 1)
    budget_calendar_month_end = date(y, m, last_dom)
    daily_period_day_count = 0
    daily_period_norm_total = None
    if selected_daily:
        daily_period_day_count = (selected_daily.end_date - selected_daily.start_date).days + 1
        daily_period_norm_total = selected_daily.daily_allowance * daily_period_day_count

    if today.year == y and today.month == m:
        expense_date_default = today
    else:
        expense_date_default = date(y, m, 1)

    context = {
        'page_title': 'Бюджет',
        'current_page': 'budget',
        'budget_year': y,
        'budget_month': m,
        'budget_prev': (prev_y, prev_m),
        'budget_next': (next_y, next_m),
        'budget_items': items,
        'budget_expenses': expenses,
        'budget_summary': summary,
        'daily_budget_periods': daily_periods,
        'selected_daily_budget': selected_daily,
        'daily_budget_ledger': daily_ledger,
        'budget_calendar_month_start': budget_calendar_month_start,
        'budget_calendar_month_end': budget_calendar_month_end,
        'daily_period_day_count': daily_period_day_count,
        'daily_period_norm_total': daily_period_norm_total,
        'budget_expense_date_default': expense_date_default,
        **get_sidebar_context(request.user),
    }
    return render(request, 'scope/budget.html', context)


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


def _budget_item_json(item):
    return {
        'id': item.id,
        'title': item.title,
        'amount_planned': str(item.amount_planned),
        'amount_set_aside': str(item.amount_set_aside),
        'is_paid': item.is_paid,
        'remaining': str(item.remaining),
        'notes': item.notes,
    }


@login_required
@require_GET
def api_budget_summary(request):
    """Сводка бюджета для сайдбара и виджетов."""
    today = timezone.now().date()
    y = int(request.GET.get('year', today.year))
    m = int(request.GET.get('month', today.month))
    s = compute_budget_summary(request.user, y, m)
    return JsonResponse({
        'success': True,
        'year': s['year'],
        'month': s['month'],
        'month_label_short': s['month_label_short'],
        'total_planned': str(s['total_planned']),
        'total_set_aside': str(s['total_set_aside']),
        'total_remaining': str(s['total_remaining']),
        'expenses_month': str(s['expenses_month']),
        'progress_pct': s['progress_pct'],
        'preview': s['preview'],
        'items_count': s['items_count'],
    })


@login_required
@require_POST
def api_budget_item_add(request):
    data = _parse_json(request)
    today = timezone.now().date()
    y = int(data.get('year', today.year))
    m = int(data.get('month', today.month))
    y = max(2000, min(2100, y))
    m = max(1, min(12, m))
    title = (data.get('title') or '').strip()
    if not title:
        return JsonResponse({'success': False, 'error': 'Укажите название'}, status=400)
    try:
        amount = Decimal(str(data.get('amount_planned', '0')).replace(',', '.'))
    except Exception:
        return JsonResponse({'success': False, 'error': 'Неверная сумма'}, status=400)
    if amount < Decimal('0.01'):
        return JsonResponse({'success': False, 'error': 'Сумма должна быть больше нуля'}, status=400)
    last = BudgetMonthlyItem.objects.filter(user=request.user, year=y, month=m).aggregate(mx=Max('sort_order'))
    sort_order = (last['mx'] or 0) + 1
    item = BudgetMonthlyItem.objects.create(
        user=request.user,
        year=y,
        month=m,
        title=title,
        amount_planned=amount,
        sort_order=sort_order,
    )
    return JsonResponse({'success': True, 'item': _budget_item_json(item)})


@login_required
@require_POST
def api_budget_item_update(request):
    data = _parse_json(request)
    pk = data.get('id')
    if not pk:
        return JsonResponse({'success': False, 'error': 'Нет id'}, status=400)
    item = get_object_or_404(BudgetMonthlyItem, pk=pk, user=request.user)
    if 'title' in data:
        t = (data.get('title') or '').strip()
        if t:
            item.title = t
    if 'amount_planned' in data:
        raw_p = data['amount_planned']
        if raw_p is None or (isinstance(raw_p, str) and not str(raw_p).strip()):
            pass
        else:
            try:
                item.amount_planned = max(Decimal('0.01'), Decimal(str(raw_p).replace(',', '.')))
            except Exception:
                return JsonResponse({'success': False, 'error': 'Неверная сумма плана'}, status=400)
    if 'amount_set_aside' in data:
        raw_a = data['amount_set_aside']
        if raw_a is None or (isinstance(raw_a, str) and not str(raw_a).strip()):
            item.amount_set_aside = Decimal('0')
        else:
            try:
                v = Decimal(str(raw_a).replace(',', '.'))
                if v < Decimal('0'):
                    v = Decimal('0')
                item.amount_set_aside = v
            except Exception:
                return JsonResponse({'success': False, 'error': 'Неверная сумма «отложено»'}, status=400)
    if 'notes' in data:
        item.notes = (data.get('notes') or '')[:500]
    if 'is_paid' in data:
        item.is_paid = bool(data['is_paid'])
    item.save()
    return JsonResponse({'success': True, 'item': _budget_item_json(item)})


@login_required
@require_POST
def api_budget_item_delete(request):
    data = _parse_json(request)
    pk = data.get('id')
    if not pk:
        return JsonResponse({'success': False, 'error': 'Нет id'}, status=400)
    BudgetMonthlyItem.objects.filter(pk=pk, user=request.user).delete()
    return JsonResponse({'success': True})


@login_required
@require_POST
def api_budget_expense_add(request):
    data = _parse_json(request)
    today = timezone.now().date()
    ds = data.get('date') or str(today)
    try:
        entry_date = date.fromisoformat(ds)
    except ValueError:
        return JsonResponse({'success': False, 'error': 'Неверная дата'}, status=400)
    try:
        amount = Decimal(str(data.get('amount', '0')).replace(',', '.'))
    except Exception:
        return JsonResponse({'success': False, 'error': 'Неверная сумма'}, status=400)
    if amount < Decimal('0.01'):
        return JsonResponse({'success': False, 'error': 'Сумма должна быть больше нуля'}, status=400)
    note = (data.get('note') or '')[:200]
    category = (data.get('category') or '')[:50]
    period = None
    pid = data.get('daily_budget_period_id')
    if pid is not None and str(pid).strip() != '':
        try:
            period = DailyBudgetPeriod.objects.get(pk=int(pid), user=request.user)
        except (ValueError, DailyBudgetPeriod.DoesNotExist):
            return JsonResponse({'success': False, 'error': 'Неверный период'}, status=400)
        if not (period.start_date <= entry_date <= period.end_date):
            return JsonResponse({'success': False, 'error': 'Дата вне выбранного периода'}, status=400)
    if period is None:
        period = DailyBudgetPeriod.objects.filter(
            user=request.user,
            start_date__lte=entry_date,
            end_date__gte=entry_date,
        ).order_by('-start_date', '-id').first()
    exp = ExpenseEntry.objects.create(
        user=request.user,
        date=entry_date,
        amount=amount,
        note=note,
        category=category,
        daily_budget_period=period,
    )
    return JsonResponse({
        'success': True,
        'expense': {
            'id': exp.id,
            'date': exp.date.isoformat(),
            'amount': str(exp.amount),
            'note': exp.note,
            'category': exp.category,
            'daily_budget_period_id': exp.daily_budget_period_id,
        },
    })


@login_required
@require_POST
def api_budget_expense_delete(request):
    data = _parse_json(request)
    pk = data.get('id')
    if not pk:
        return JsonResponse({'success': False, 'error': 'Нет id'}, status=400)
    ExpenseEntry.objects.filter(pk=pk, user=request.user).delete()
    return JsonResponse({'success': True})


@login_required
@require_POST
def api_budget_daily_period_add(request):
    data = _parse_json(request)
    title = (data.get('title') or '')[:200]
    try:
        start = date.fromisoformat(data.get('start_date', ''))
        end = date.fromisoformat(data.get('end_date', ''))
    except ValueError:
        return JsonResponse({'success': False, 'error': 'Неверные даты'}, status=400)
    if end < start:
        return JsonResponse({'success': False, 'error': 'Конец раньше начала'}, status=400)
    mode = (data.get('mode') or 'daily').strip()
    try:
        if mode == 'total':
            total = Decimal(str(data.get('total_amount', '0')).replace(',', '.'))
            if total < Decimal('0.01'):
                return JsonResponse({'success': False, 'error': 'Укажите сумму за период'}, status=400)
            daily = DailyBudgetPeriod.compute_daily_from_total(total, start, end)
        else:
            daily = Decimal(str(data.get('daily_allowance', '0')).replace(',', '.'))
            if daily < Decimal('0.01'):
                return JsonResponse({'success': False, 'error': 'Укажите дневную норму'}, status=400)
    except Exception:
        return JsonResponse({'success': False, 'error': 'Неверная сумма'}, status=400)
    p = DailyBudgetPeriod.objects.create(
        user=request.user,
        title=title,
        start_date=start,
        end_date=end,
        daily_allowance=daily,
    )
    return JsonResponse({
        'success': True,
        'period': {
            'id': p.id,
            'title': p.title,
            'start_date': p.start_date.isoformat(),
            'end_date': p.end_date.isoformat(),
            'daily_allowance': str(p.daily_allowance),
        },
    })


@login_required
@require_POST
def api_budget_daily_period_delete(request):
    data = _parse_json(request)
    pk = data.get('id')
    if not pk:
        return JsonResponse({'success': False, 'error': 'Нет id'}, status=400)
    DailyBudgetPeriod.objects.filter(pk=pk, user=request.user).delete()
    return JsonResponse({'success': True})


# --- BulletTasks (микрозадачи) ---

_HEX_COLOR = re.compile(r'^#[0-9A-Fa-f]{6}$')
_BULLET_ICON = re.compile(r'^[a-z0-9_]{1,80}$')

def _bullet_norm_mask(s: str) -> str:
    raw = (s or '1111111')[:7]
    raw = raw.ljust(7, '1')
    return ''.join('1' if c == '1' else '0' for c in raw)

def _bullet_weekday_ok(mask: str, d: date) -> bool:
    w = d.weekday()
    if len(mask) != 7:
        return True
    return mask[w] == '1'

def _bullet_count_scheduled(st: date, en: date, mask: str) -> int:
    n = 0
    d = st
    while d <= en:
        if _bullet_weekday_ok(mask, d):
            n += 1
        d += timedelta(days=1)
    return n

def _bullet_task_json(bt, today, day_sets, comp_by_task) -> dict:
    mask = _bullet_norm_mask(bt.weekday_mask)
    st, en = bt.start_date, bt.end_date
    t_id = bt.id
    ds = day_sets.get(t_id) or set()
    progress_done = len([x for x in ds if st <= x <= en and _bullet_weekday_ok(mask, x)])
    progress_total = _bullet_count_scheduled(st, en, mask) or 1
    today_sched = st <= today <= en and _bullet_weekday_ok(mask, today)
    today_done = bool(today_sched and today in ds)
    rows = comp_by_task.get(t_id) or []
    total_points = sum(
        r['points_earned'] for r in rows
        if st <= r['day'] <= en
    )
    return {
        'id': bt.id,
        'title': bt.title,
        'color': bt.color,
        'icon': bt.icon,
        'start_date': st.isoformat(),
        'end_date': en.isoformat(),
        'duration_days': bt.duration_days,
        'points_per_completion': bt.points_per_completion,
        'weekday_mask': mask,
        'today': {
            'scheduled': today_sched,
            'done': today_done,
        },
        'progress': {
            'done': progress_done,
            'total': max(1, progress_total),
        },
        'total_points': total_points,
    }

@login_required
@require_GET
def api_bullet_tasks_list(request):
    today = timezone.now().date()
    tasks = list(BulletTask.objects.filter(user=request.user).order_by('-created_at'))
    if not tasks:
        return JsonResponse({
            'success': True,
            'today': today.isoformat(),
            'tasks': [],
        })
    lo = min(t.start_date for t in tasks)
    hi = max(t.end_date for t in tasks)
    comps = list(
        BulletTaskCompletion.objects.filter(
            bullet_task__in=tasks,
            day__gte=lo,
            day__lte=hi,
        ).values('bullet_task_id', 'day', 'points_earned')
    )
    day_sets: dict = defaultdict(set)
    comp_by_task: dict = defaultdict(list)
    for c in comps:
        tid = c['bullet_task_id']
        dday = c['day']
        day_sets[tid].add(dday)
        comp_by_task[tid].append({'day': dday, 'points_earned': c['points_earned']})
    return JsonResponse({
        'success': True,
        'today': today.isoformat(),
        'tasks': [_bullet_task_json(t, today, day_sets, comp_by_task) for t in tasks],
    })

@login_required
@require_POST
def api_bullet_tasks_save(request):
    data = _parse_json(request)
    uid = data.get('id')
    today = timezone.now().date()
    title = (data.get('title') or '').strip()[:200]
    if not title:
        return JsonResponse({'success': False, 'error': 'Введите название'}, status=400)
    col = (data.get('color') or '#7C3AED').strip()
    if not _HEX_COLOR.match(col):
        return JsonResponse({'success': False, 'error': 'Неверный цвет'}, status=400)
    icon = (data.get('icon') or 'task_alt').strip()[:80]
    if not _BULLET_ICON.match(icon):
        return JsonResponse({'success': False, 'error': 'Неверная иконка'}, status=400)
    try:
        duration_days = int(data.get('duration_days', 15))
    except (TypeError, ValueError):
        duration_days = 15
    duration_days = max(1, min(3660, duration_days))
    try:
        points = int(data.get('points_per_completion', 10))
    except (TypeError, ValueError):
        points = 10
    points = max(1, min(1_000_000, points))
    if data.get('start_date'):
        try:
            y, m, d = (int(x) for x in str(data.get('start_date')).split('-')[:3])
            start_date = date(y, m, d)
        except (ValueError, TypeError):
            start_date = today
    else:
        start_date = today
    mask = _bullet_norm_mask(str(data.get('weekday_mask', '1111111')))
    if '1' not in mask:
        return JsonResponse({'success': False, 'error': 'Выберите хотя бы один день недели'}, status=400)

    if uid:
        bt = get_object_or_404(BulletTask, pk=int(uid), user=request.user)
    else:
        bt = BulletTask(user=request.user)
    bt.title = title
    bt.color = col
    bt.icon = icon
    bt.start_date = start_date
    bt.duration_days = duration_days
    bt.points_per_completion = points
    bt.weekday_mask = mask
    bt.save()
    return JsonResponse({'success': True, 'id': bt.id})

@login_required
@require_POST
def api_bullet_tasks_delete(request):
    data = _parse_json(request)
    pk = data.get('id')
    if not pk:
        return JsonResponse({'success': False, 'error': 'Нет id'}, status=400)
    BulletTask.objects.filter(pk=pk, user=request.user).delete()
    return JsonResponse({'success': True})

@login_required
@require_POST
def api_bullet_tasks_toggle(request):
    data = _parse_json(request)
    pk = data.get('id')
    if not pk:
        return JsonResponse({'success': False, 'error': 'Нет id'}, status=400)
    bt = get_object_or_404(BulletTask, pk=int(pk), user=request.user)
    today = timezone.now().date()
    mask = _bullet_norm_mask(bt.weekday_mask)
    st, en = bt.start_date, bt.end_date
    if not (st <= today <= en and _bullet_weekday_ok(mask, today)):
        return JsonResponse({'success': False, 'error': 'Сегодня эта микрозадача не запланирована'}, status=400)
    ex = BulletTaskCompletion.objects.filter(bullet_task=bt, day=today).first()
    if ex:
        ex.delete()
        return JsonResponse({'success': True, 'done': False})
    BulletTaskCompletion.objects.create(
        bullet_task=bt,
        day=today,
        points_earned=bt.points_per_completion,
    )
    return JsonResponse({'success': True, 'done': True, 'points': bt.points_per_completion})

@login_required
@require_GET
def api_bullet_tasks_history(request):
    today = timezone.now().date()
    y = int(request.GET.get('year', today.year))
    m = int(request.GET.get('month', today.month))
    y = max(2000, min(2100, y))
    m = max(1, min(12, m))
    _, last = monthrange(y, m)
    d0, d1 = date(y, m, 1), date(y, m, last)
    items = list(
        BulletTaskCompletion.objects.filter(
            bullet_task__user=request.user,
            day__gte=d0,
            day__lte=d1,
        )
        .select_related('bullet_task')
        .order_by('-day', '-id')
    )
    by_date: dict = defaultdict(list)
    for c in items:
        by_date[str(c.day)].append({
            'id': c.bullet_task_id,
            'title': c.bullet_task.title,
            'color': c.bullet_task.color,
            'icon': c.bullet_task.icon,
            'points': c.points_earned,
        })
    # Дни в порядке убывания
    day_keys = sorted(by_date.keys(), reverse=True)
    return JsonResponse({
        'success': True,
        'year': y,
        'month': m,
        'days': [{'date': d, 'items': by_date[d]} for d in day_keys],
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
