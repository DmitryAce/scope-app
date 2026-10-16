from django.urls import path

from apps.scope.api_v2 import views as v2

urlpatterns = [
    path('', v2.root, name='api_v2_root'),
    path('me/', v2.me, name='api_v2_me'),
    path('auth/login/', v2.auth_login, name='api_v2_auth_login'),
    path('auth/logout/', v2.auth_logout, name='api_v2_auth_logout'),
    path('housekeeping/', v2.housekeeping, name='api_v2_housekeeping'),
    path('projects/', v2.projects_collection, name='api_v2_projects'),
    path('projects/<int:pk>/', v2.project_detail, name='api_v2_project_detail'),
    path('projects/<int:pk>/avatar/', v2.project_avatar, name='api_v2_project_avatar'),
    path('tags/', v2.tags_collection, name='api_v2_tags'),
    path('tasks/', v2.tasks_collection, name='api_v2_tasks'),
    path('tasks/<int:pk>/', v2.task_detail, name='api_v2_task_detail'),
    path('tasks/<int:pk>/toggle/', v2.task_toggle, name='api_v2_task_toggle'),
    path('tasks/<int:pk>/checklist/', v2.checklist_collection, name='api_v2_checklist'),
    path('checklist/<int:pk>/', v2.checklist_item, name='api_v2_checklist_item'),
]
