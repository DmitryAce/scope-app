from django.urls import include, path
from . import views

app_name = 'scope'

urlpatterns = [
    path('api/v2/', include('apps.scope.api_v2.urls')),
    # Главная страница - Все задачи
    path('', views.dashboard, name='dashboard'),
    
    # Сегодня
    path('today/', views.today_view, name='today'),
    
    # Календарь
    path('calendar/', views.calendar_view, name='calendar'),

    # Микрозадачи BulletTasks
    path('bullet-tasks/', views.bullet_tasks_view, name='bullet_tasks'),

    # Бюджет
    path('budget/', views.budget_view, name='budget'),
    
    # Проекты
    path('projects/', views.project_list, name='project_list'),
    path('projects/create/', views.project_create, name='project_create'),
    path('projects/<int:pk>/', views.project_detail, name='project_detail'),
    path('projects/<int:pk>/edit/', views.project_edit, name='project_edit'),
    path('projects/<int:pk>/delete/', views.project_delete, name='project_delete'),
    path('projects/<int:pk>/restore/', views.project_restore, name='project_restore'),
    
    # Задачи
    path('tasks/create/', views.task_create, name='task_create'),
    path('tasks/<int:pk>/', views.task_detail, name='task_detail'),
    path('tasks/<int:pk>/edit/', views.task_edit, name='task_edit'),
    path('tasks/<int:pk>/delete/', views.task_delete, name='task_delete'),
    path('tasks/<int:pk>/toggle/', views.task_toggle, name='task_toggle'),
    path('tasks/<int:pk>/update-inline/', views.task_update_inline, name='task_update_inline'),
    
    # Чек-листы (AJAX)
    path('tasks/<int:task_pk>/checklist/add/', views.checklist_add, name='checklist_add'),
    path('checklist/<int:pk>/toggle/', views.checklist_toggle, name='checklist_toggle'),
    path('checklist/<int:pk>/delete/', views.checklist_delete, name='checklist_delete'),
    
    # Теги
    path('tags/', views.tag_list, name='tag_list'),
    path('tags/create/', views.tag_create, name='tag_create'),
    path('tags/<int:pk>/delete/', views.tag_delete, name='tag_delete'),
    
    # Ссылки задач
    path('tasks/<int:task_pk>/links/add/', views.link_add, name='link_add'),
    path('links/<int:pk>/delete/', views.link_delete, name='link_delete'),
    
    # Вложения задач
    path('tasks/<int:task_pk>/attachments/add/', views.attachment_add, name='attachment_add'),
    path('attachments/<int:pk>/delete/', views.attachment_delete, name='attachment_delete'),
    
    # Обновление даты задачи (drag-and-drop)
    path('tasks/<int:pk>/update-date/', views.task_update_date, name='task_update_date'),
    path('tasks/<int:pk>/kanban-reorder/', views.task_kanban_reorder, name='task_kanban_reorder'),

    # API
    path('api/tasks/', views.api_tasks, name='api_tasks'),
    path('api/calendar-events/', views.api_calendar_events, name='api_calendar_events'),
    path('api/kanban-events/', views.api_kanban_events, name='api_kanban_events'),
    path('api/stats/', views.api_stats, name='api_stats'),
    path('api/sidebar/', views.api_sidebar, name='api_sidebar'),
    path('api/budget/summary/', views.api_budget_summary, name='api_budget_summary'),
    path('api/budget/item/add/', views.api_budget_item_add, name='api_budget_item_add'),
    path('api/budget/item/update/', views.api_budget_item_update, name='api_budget_item_update'),
    path('api/budget/item/delete/', views.api_budget_item_delete, name='api_budget_item_delete'),
    path('api/budget/expense/add/', views.api_budget_expense_add, name='api_budget_expense_add'),
    path('api/budget/expense/delete/', views.api_budget_expense_delete, name='api_budget_expense_delete'),
    path('api/budget/daily-period/add/', views.api_budget_daily_period_add, name='api_budget_daily_period_add'),
    path('api/budget/daily-period/delete/', views.api_budget_daily_period_delete, name='api_budget_daily_period_delete'),

    path('api/bullet-tasks/', views.api_bullet_tasks_list, name='api_bullet_tasks_list'),
    path('api/bullet-tasks/save/', views.api_bullet_tasks_save, name='api_bullet_tasks_save'),
    path('api/bullet-tasks/delete/', views.api_bullet_tasks_delete, name='api_bullet_tasks_delete'),
    path('api/bullet-tasks/toggle/', views.api_bullet_tasks_toggle, name='api_bullet_tasks_toggle'),
    path('api/bullet-tasks/history/', views.api_bullet_tasks_history, name='api_bullet_tasks_history'),
]

