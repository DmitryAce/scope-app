from django.urls import path
from . import views

app_name = 'scope'

urlpatterns = [
    # Главная страница - Все задачи
    path('', views.dashboard, name='dashboard'),
    
    # Сегодня
    path('today/', views.today_view, name='today'),
    
    # Календарь
    path('calendar/', views.calendar_view, name='calendar'),
    
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
    
    # API для календаря
    path('api/tasks/', views.api_tasks, name='api_tasks'),
    path('api/calendar-events/', views.api_calendar_events, name='api_calendar_events'),
]

