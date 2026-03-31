from django.urls import path

from apps.scope.api_v2 import views as v2

urlpatterns = [
    path('', v2.root, name='api_v2_root'),
    path('me/', v2.me, name='api_v2_me'),
    path('projects/', v2.projects_collection, name='api_v2_projects'),
    path('projects/<int:pk>/', v2.project_detail, name='api_v2_project_detail'),
    path('tags/', v2.tags_collection, name='api_v2_tags'),
    path('tasks/', v2.tasks_collection, name='api_v2_tasks'),
    path('tasks/<int:pk>/', v2.task_detail, name='api_v2_task_detail'),
    path('tasks/<int:pk>/toggle/', v2.task_toggle, name='api_v2_task_toggle'),
]
