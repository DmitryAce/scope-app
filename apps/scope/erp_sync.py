"""Задачи из ERP (Webstead, OmniWebers) в Scope — только чтение.

Каждый прогон забирает все открытые задачи, где пользователь исполнитель, и
приводит к ним Scope:

* новой задаче — создаёт Scope-задачу в проекте «ERP · <источник> › <проект ERP>»;
* у существующей обновляет название, описание, приоритет, статус и ссылку;
  срок — только если он поменялся в самой ERP (свой перенос в Scope не затирается);
* задача пропала из открытых (закрыли в ERP или сняли с пользователя) —
  закрывает её в Scope.

Закрытие в Scope обратно в ERP не уходит: это личная отметка.
Проекты, созданные синхронизацией, можно переносить и переименовывать —
связь держится на external_id, а не на имени.
"""

from __future__ import annotations

import json
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import date

from decouple import config
from django.contrib.auth.models import User
from django.db import transaction
from django.utils import timezone

from apps.scope.models import ErpSyncState, Project, Task


@dataclass(frozen=True)
class Source:
    key: str
    name: str
    base_url: str
    token: str
    color: str


def sources() -> list[Source]:
    """Источники, для которых на сервере есть токен."""
    found = [
        Source('webstead', 'Webstead', config('WEBSTEAD_ERP_URL', default='https://erp.webstead.ru'),
               config('WEBSTEAD_ERP_TOKEN', default=''), '#8B2942'),
        Source('omniwebers', 'OmniWebers', config('OMNIWEBERS_ERP_URL', default='https://erp.omniwebers.ru'),
               config('OMNIWEBERS_ERP_TOKEN', default=''), '#06B6D4'),
    ]
    return [s for s in found if s.token]


def sync_user() -> User | None:
    """Чей это Scope: задачи из ERP кладутся этому пользователю."""
    username = config('ERP_SYNC_USERNAME', default='')
    return User.objects.filter(username=username).first() if username else None


# Коды приоритетов обеих ERP → 1..4 Scope.
PRIORITY = {
    'minimal': 1, 'low': 1,
    'normal': 2, 'medium': 2,
    'important': 3, 'high': 3,
    'urgent': 4, 'critical': 4, 'blocker': 4,
}


def fetch_open_tasks(source: Source, opener=None) -> list[dict]:
    """Все открытые задачи, где владелец токена — исполнитель (с пагинацией)."""
    opener = opener or _http_get
    tasks, cursor = [], None
    for _ in range(50):  # предохранитель от бесконечного курсора
        params = {'relation': 'assignee', 'limit': '200'}
        if cursor:
            params['cursor'] = cursor
        url = f"{source.base_url.rstrip('/')}/api/v1/integrations/tasks/?{urllib.parse.urlencode(params)}"
        page = opener(url, source.token)
        if not page.get('success', True):
            raise RuntimeError(f'{source.name}: {page}')
        tasks.extend(page.get('tasks') or [])
        if not page.get('has_more'):
            return tasks
        cursor = page.get('next_cursor')
        if not cursor:
            return tasks
    raise RuntimeError(f'{source.name}: слишком много страниц')


def _http_get(url: str, token: str) -> dict:
    req = urllib.request.Request(url, headers={'Authorization': f'Bearer {token}', 'Accept': 'application/json'})
    with urllib.request.urlopen(req, timeout=25) as res:
        return json.loads(res.read().decode('utf-8'))


def _root_project(user: User, source: Source) -> Project:
    project, _ = Project.objects.get_or_create(
        user=user, external_source=source.key, external_id='root',
        defaults={'name': f'ERP · {source.name}', 'color': source.color, 'icon': 'briefcase'},
    )
    return project


def _erp_project(user: User, source: Source, data: dict | None, cache: dict) -> Project:
    root = cache.setdefault('root', None) or _root_project(user, source)
    cache['root'] = root
    if not data or not data.get('id'):
        return root
    key = str(data['id'])
    if key not in cache:
        project, created = Project.objects.get_or_create(
            user=user, external_source=source.key, external_id=key,
            defaults={'name': (data.get('name') or data.get('code') or key)[:200], 'color': source.color,
                      'parent': root},
        )
        cache[key] = project
    return cache[key]


def _parse_date(value) -> date | None:
    try:
        return date.fromisoformat(value) if value else None
    except ValueError:
        return None


def apply_tasks(user: User, source: Source, items: list[dict]) -> dict:
    """Привести задачи Scope к открытым задачам ERP. Возвращает счётчики."""
    stats = {'created': 0, 'updated': 0, 'closed': 0, 'open': len(items)}
    projects: dict = {}
    seen = set()
    with transaction.atomic():
        existing = {
            t.external_id: t
            for t in Task.objects.filter(user=user, external_source=source.key)
        }
        for item in items:
            ext_id = str(item['id'])
            seen.add(ext_id)
            deadline = _parse_date(item.get('deadline'))
            fields = {
                'title': (item.get('title') or item.get('code') or ext_id)[:500],
                'description': (item.get('description') or '')[:10000],
                'priority': PRIORITY.get((item.get('priority') or {}).get('code', ''), 2),
                'external_code': (item.get('code') or '')[:50],
                'external_url': (item.get('url') or '')[:500],
                'external_status': ((item.get('status') or {}).get('label') or '')[:100],
            }
            task = existing.get(ext_id)
            if task is None:
                Task.objects.create(
                    user=user, external_source=source.key, external_id=ext_id,
                    project=_erp_project(user, source, item.get('project'), projects),
                    due_date=deadline, external_deadline=deadline, **fields,
                )
                stats['created'] += 1
                continue
            changed = [k for k, v in fields.items() if getattr(task, k) != v]
            for k in changed:
                setattr(task, k, fields[k])
            if deadline != task.external_deadline:
                # Срок поменяли в ERP — он важнее локального переноса.
                task.external_deadline = deadline
                task.due_date = deadline
                changed += ['external_deadline', 'due_date']
            if changed:
                task.save(update_fields=[*changed, 'updated_at'])
                stats['updated'] += 1
        stats['closed'] = (
            Task.objects.filter(user=user, external_source=source.key, is_completed=False)
            .exclude(external_id__in=seen)
            .update(is_completed=True, completed_at=timezone.now(), external_status='Закрыта в ERP или снята с вас')
        )
    return stats


def sync_source(user: User, source: Source, opener=None) -> dict:
    state, _ = ErpSyncState.objects.get_or_create(user=user, source=source.key)
    try:
        items = fetch_open_tasks(source, opener)
        stats = apply_tasks(user, source, items)
        state.last_error = ''
        state.open_tasks = stats['open']
    except Exception as e:  # сеть, токен, формат — показываем в настройках, остальное не трогаем
        stats = {'error': str(e)[:500]}
        state.last_error = str(e)[:2000]
    state.last_run = timezone.now()
    state.save()
    return stats


def sync_all(user: User | None = None, opener=None) -> dict:
    user = user or sync_user()
    if user is None:
        return {}
    return {s.key: sync_source(user, s, opener) for s in sources()}
