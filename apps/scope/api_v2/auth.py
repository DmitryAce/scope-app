from __future__ import annotations

import hashlib
from functools import wraps

from django.http import JsonResponse
from django.utils import timezone

from apps.scope.models import ApiAccessToken


def _hash_raw_token(raw: str) -> str:
    return hashlib.sha256(raw.encode('utf-8')).hexdigest()


def extract_raw_token(request) -> str | None:
    auth = request.headers.get('Authorization', '') or ''
    if auth.startswith('Bearer '):
        t = auth[7:].strip()
        return t if t else None
    x = request.headers.get('X-API-Key', '') or ''
    return x.strip() if x.strip() else None


def authenticate_token(request):
    """
    Возвращает User при валидном токене, иначе None.
    Обновляет last_used_at у записи токена.
    """
    raw = extract_raw_token(request)
    if not raw:
        return None
    digest = _hash_raw_token(raw)
    try:
        row = ApiAccessToken.objects.select_related('user').get(key_hash=digest, is_active=True)
    except ApiAccessToken.DoesNotExist:
        return None
    if not row.user.is_active:
        return None
    ApiAccessToken.objects.filter(pk=row.pk).update(last_used_at=timezone.now())
    return row.user


def api_token_required(view):
    """Декоратор: только Bearer / X-API-Key, без сессии. CSRF не требуется."""

    @wraps(view)
    def _wrapped(request, *args, **kwargs):
        user = authenticate_token(request)
        if user is None:
            return JsonResponse(
                {'error': {'code': 'unauthorized', 'message': 'Нужен заголовок Authorization: Bearer <token> или X-API-Key'}},
                status=401,
            )
        request.user = user
        return view(request, *args, **kwargs)

    return _wrapped


def csrf_exempt_api(view):
    from django.views.decorators.csrf import csrf_exempt

    return csrf_exempt(view)


def v2(view):
    """CSRF exempt + API token auth."""
    return csrf_exempt_api(api_token_required(view))
