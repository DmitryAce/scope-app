from __future__ import annotations

from django.utils import timezone

from apps.scope.models import Project, Tag, Task


def project_to_dict(p: Project) -> dict:
    return {
        'id': p.id,
        'name': p.name,
        'description': p.description,
        'color': p.color,
        'icon': p.icon,
        'is_archived': p.is_archived,
        'parent_id': p.parent_id,
        # Относительный путь: клиент сам подставляет сервер (дом или интернет).
        'avatar': p.avatar.url if p.avatar else None,
        'created_at': p.created_at.isoformat() if p.created_at else None,
        'updated_at': p.updated_at.isoformat() if p.updated_at else None,
    }


def tag_to_dict(t: Tag) -> dict:
    return {
        'id': t.id,
        'name': t.name,
        'color': t.color,
    }


def task_to_dict(task: Task) -> dict:
    due_time = None
    if task.due_time:
        due_time = task.due_time.strftime('%H:%M')
    return {
        'id': task.id,
        'title': task.title,
        'description': task.description,
        'priority': task.priority,
        'priority_label': task.get_priority_display(),
        'is_completed': task.is_completed,
        'auto_complete': task.auto_complete,
        'completed_at': task.completed_at.isoformat() if task.completed_at else None,
        'due_date': task.due_date.isoformat() if task.due_date else None,
        'due_time': due_time,
        'duration_minutes': task.duration_minutes,
        'repeat': task.repeat,
        'repeat_until': task.repeat_until.isoformat() if task.repeat_until else None,
        'reminder': timezone.localtime(task.reminder).strftime('%Y-%m-%d %H:%M') if task.reminder else None,
        'project_id': task.project_id,
        'order': task.order,
        'is_overdue': task.is_overdue,
        'tag_ids': [t.id for t in task.tags.all()],
        'checklist': [
            {'id': c.id, 'text': c.text, 'is_completed': c.is_completed}
            for c in task.checklist_items.all()
        ],
        'created_at': task.created_at.isoformat() if task.created_at else None,
        'updated_at': task.updated_at.isoformat() if task.updated_at else None,
    }
