"""Операции над деревом проектов, которые затрагивают несколько моделей."""

from __future__ import annotations

from django.db import transaction

from apps.scope.models import ErpConnection, ErpProjectLink, Project, Task

MAX_LEVELS = 4


def _depth(p: Project) -> int:
    d, cur = 0, p
    while cur.parent_id and d < 50:
        cur = cur.parent
        d += 1
    return d


def _height(p: Project) -> int:
    children = list(p.children.all())
    return 1 + max(_height(c) for c in children) if children else 0


def _is_descendant(candidate: Project, of: Project) -> bool:
    cur = candidate
    for _ in range(50):
        if cur is None:
            return False
        if cur.pk == of.pk:
            return True
        cur = cur.parent
    return False


def merge_projects(source: Project, target: Project) -> None:
    """Влить source в target: задачи, подпроекты и связи с ERP переезжают, source удаляется.

    Если source был корнем подключения ERP, новые проекты этой ERP тоже пойдут в target.
    """
    if source.user_id != target.user_id:
        raise ValueError('Проекты разных пользователей')
    if source.pk == target.pk:
        raise ValueError('Нельзя объединить проект сам с собой')
    if _is_descendant(target, source):
        raise ValueError('Нельзя влить проект в его же подпроект')
    children = list(source.children.all())
    if children:
        deepest = max(_height(c) for c in children)
        if _depth(target) + 1 + deepest > MAX_LEVELS - 1:
            raise ValueError(f'После объединения вложенность превысит {MAX_LEVELS} уровня')
    with transaction.atomic():
        Task.objects.filter(project=source).update(project=target)
        Project.objects.filter(parent=source).update(parent=target)
        ErpProjectLink.objects.filter(project=source).update(project=target)
        ErpConnection.objects.filter(root_project=source).update(root_project=target)
        source.delete()
