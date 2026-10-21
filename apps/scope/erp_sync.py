"""Задачи из ERP в Scope — только чтение, у каждого пользователя свои подключения.

Подключение (ErpConnection) — адрес ERP и личный API-токен пользователя. ERP
должна отдавать ленту задач в формате интеграций Webstead/OmniWebers:
GET <base>/api/v1/integrations/tasks/?relation=assignee (Bearer-токен).

Каждый прогон забирает все открытые задачи, где пользователь исполнитель, и
приводит к ним Scope:

* новой задаче — создаёт Scope-задачу в проекте «ERP · <подключение> › <проект ERP>»;
* у существующей обновляет название, описание, приоритет, статус и ссылку;
  срок — только если он поменялся в самой ERP (свой перенос в Scope не затирается);
* задача пропала из открытых (закрыли в ERP или сняли с пользователя) —
  закрывает её в Scope.

Закрытие в Scope обратно в ERP не уходит: это личная отметка.
"""

from __future__ import annotations

import ipaddress
import json
import socket
import urllib.error
import urllib.parse
import urllib.request
from datetime import date

from django.db import transaction
from django.utils import timezone

from apps.scope.models import ErpConnection, Project, Task

# Готовые подключения: ключ → (название, адрес, цвет).
PRESETS = {
    'webstead': ('Webstead', 'https://erp.webstead.ru', '#B3365B'),
    'omniwebers': ('OmniWebers', 'https://erp.omniwebers.ru', '#06B6D4'),
}

# Коды приоритетов ERP → 1..4 Scope.
PRIORITY = {
    'minimal': 1, 'low': 1,
    'normal': 2, 'medium': 2,
    'important': 3, 'high': 3,
    'urgent': 4, 'critical': 4, 'blocker': 4,
}


class ErpError(Exception):
    """Понятная пользователю причина, почему ERP не ответила как надо."""


# ---------- сеть ----------

def check_public_https(url: str) -> str:
    """Адрес ERP: только https и только публичный хост — сервер не ходит во внутреннюю сеть."""
    parsed = urllib.parse.urlparse(url.strip())
    if parsed.scheme != 'https' or not parsed.hostname:
        raise ErpError('Адрес ERP должен начинаться с https://')
    try:
        infos = socket.getaddrinfo(parsed.hostname, parsed.port or 443)
    except socket.gaierror:
        raise ErpError('Не нашёл такой адрес')
    for info in infos:
        ip = ipaddress.ip_address(info[4][0])
        if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved or ip.is_multicast:
            raise ErpError('Адрес ведёт во внутреннюю сеть — такие подключать нельзя')
    return f'{parsed.scheme}://{parsed.netloc}'


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):  # редирект мог бы увести во внутреннюю сеть
        return None


_opener = urllib.request.build_opener(_NoRedirect)


def _http_get(url: str, token: str) -> dict:
    req = urllib.request.Request(url, headers={'Authorization': f'Bearer {token}', 'Accept': 'application/json'})
    try:
        with _opener.open(req, timeout=25) as res:
            return json.loads(res.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            raise ErpError('ERP не приняла токен — проверьте, что он скопирован целиком и не отозван')
        if e.code == 404:
            raise ErpError('По этому адресу нет API интеграций ERP')
        raise ErpError(f'ERP ответила {e.code}')
    except urllib.error.URLError as e:
        raise ErpError(f'ERP недоступна: {e.reason}')
    except ValueError:
        raise ErpError('ERP ответила не JSON — это точно адрес ERP?')


def fetch_open_tasks(base_url: str, token: str, opener=None, max_pages: int = 50) -> list[dict]:
    """Открытые задачи, где владелец токена — исполнитель (с пагинацией)."""
    opener = opener or _http_get
    tasks, cursor = [], None
    for _ in range(max_pages):
        params = {'relation': 'assignee', 'limit': '200'}
        if cursor:
            params['cursor'] = cursor
        page = opener(f"{base_url.rstrip('/')}/api/v1/integrations/tasks/?{urllib.parse.urlencode(params)}", token)
        if not isinstance(page, dict) or not page.get('success', True) or 'tasks' not in page:
            raise ErpError('Неожиданный ответ ERP')
        tasks.extend(page['tasks'] or [])
        cursor = page.get('next_cursor')
        if not page.get('has_more') or not cursor:
            return tasks
    if max_pages == 1:
        return tasks
    raise ErpError('Слишком много страниц в ответе ERP')


# ---------- подключение ----------

def connect(user, *, token: str, preset: str = '', base_url: str = '', name: str = '', opener=None,
            check_host=True) -> ErpConnection:
    """Проверить токен и сохранить подключение (повторное — обновляет токен)."""
    token = (token or '').strip()
    if not token:
        raise ErpError('Нужен API-токен из профиля ERP')
    if preset:
        if preset not in PRESETS:
            raise ErpError('Неизвестная ERP')
        title, url, color = PRESETS[preset]
        source = preset
    else:
        url = base_url
        title, color, source = (name or '').strip()[:60], '#64748B', ''
    if check_host:
        url = check_public_https(url)
    if not preset:
        title = title or urllib.parse.urlparse(url).hostname
        existing = ErpConnection.objects.filter(user=user, base_url=url).first()
        source = existing.source if existing else ''
    fetch_open_tasks(url, token, opener, max_pages=1)  # бросит ErpError, если что-то не так

    conn = ErpConnection.objects.filter(user=user, source=source).first() if source else None
    if conn is None:
        conn = ErpConnection(user=user, source=source or 'tmp', name=title, base_url=url, color=color)
    conn.token = token
    conn.base_url = url
    conn.is_active = True
    conn.last_error = ''
    conn.save()
    if not source:
        conn.source = f'erp-{conn.pk}'
        conn.save(update_fields=['source'])
    return conn


def disconnect(conn: ErpConnection, delete_tasks: bool = False) -> None:
    """Отключить ERP. Задачи — закрыть (останутся в истории) или удалить вместе с пустыми проектами."""
    with transaction.atomic():
        tasks = Task.objects.filter(user=conn.user, external_source=conn.source)
        if delete_tasks:
            tasks.delete()
            # Сначала подпроекты, потом корень — только пустые.
            for p in Project.objects.filter(user=conn.user, external_source=conn.source).exclude(external_id='root'):
                if not p.tasks.exists() and not p.children.exists():
                    p.delete()
            for p in Project.objects.filter(user=conn.user, external_source=conn.source, external_id='root'):
                if not p.tasks.exists() and not p.children.exists():
                    p.delete()
        else:
            tasks.filter(is_completed=False).update(
                is_completed=True, completed_at=timezone.now(), external_status='ERP отключена')
        conn.delete()


# ---------- синхронизация ----------

def _root_project(conn: ErpConnection) -> Project:
    project, _ = Project.objects.get_or_create(
        user=conn.user, external_source=conn.source, external_id='root',
        defaults={'name': f'ERP · {conn.name}', 'color': conn.color, 'icon': 'briefcase'},
    )
    return project


def _erp_project(conn: ErpConnection, data: dict | None, cache: dict) -> Project:
    if 'root' not in cache:
        cache['root'] = _root_project(conn)
    if not data or not data.get('id'):
        return cache['root']
    key = str(data['id'])
    if key not in cache:
        project, _ = Project.objects.get_or_create(
            user=conn.user, external_source=conn.source, external_id=key,
            defaults={'name': (data.get('name') or data.get('code') or key)[:200], 'color': conn.color,
                      'parent': cache['root']},
        )
        cache[key] = project
    return cache[key]


def _parse_date(value) -> date | None:
    try:
        return date.fromisoformat(value) if value else None
    except ValueError:
        return None


def apply_tasks(conn: ErpConnection, items: list[dict]) -> dict:
    """Привести задачи Scope к открытым задачам ERP. Возвращает счётчики."""
    user, source = conn.user, conn.source
    stats = {'created': 0, 'updated': 0, 'closed': 0, 'open': len(items)}
    projects: dict = {}
    seen = set()
    with transaction.atomic():
        existing = {t.external_id: t for t in Task.objects.filter(user=user, external_source=source)}
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
                    user=user, external_source=source, external_id=ext_id,
                    project=_erp_project(conn, item.get('project'), projects),
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
            Task.objects.filter(user=user, external_source=source, is_completed=False)
            .exclude(external_id__in=seen)
            .update(is_completed=True, completed_at=timezone.now(), external_status='Закрыта в ERP или снята с вас')
        )
    return stats


def sync_connection(conn: ErpConnection, opener=None) -> dict:
    try:
        token = conn.token
        if not token:
            raise ErpError('Токен не расшифровался — подключите ERP заново')
        stats = apply_tasks(conn, fetch_open_tasks(conn.base_url, token, opener))
        conn.last_error = ''
        conn.open_tasks = stats['open']
    except Exception as e:  # сеть, токен, формат — показываем в приложении, задачи не трогаем
        stats = {'error': str(e)[:500]}
        conn.last_error = str(e)[:2000]
    conn.last_run = timezone.now()
    conn.save(update_fields=['last_error', 'open_tasks', 'last_run'])
    return stats


def sync_user(user, opener=None) -> dict:
    return {c.source: sync_connection(c, opener) for c in ErpConnection.objects.filter(user=user, is_active=True)}


def sync_everyone(opener=None) -> dict:
    return {
        f'{c.user.username}/{c.source}': sync_connection(c, opener)
        for c in ErpConnection.objects.filter(is_active=True).select_related('user')
    }
