"""Шифрование токенов внешних сервисов в базе (Fernet).

Ключ — ENCRYPTION_KEY из окружения; если его нет, выводится из SECRET_KEY.
Дамп базы без ключа токены не раскрывает. Смена ключа делает старые токены
нечитаемыми — пользователям придётся подключить ERP заново.
"""

from __future__ import annotations

import base64
import hashlib
from functools import lru_cache

from cryptography.fernet import Fernet, InvalidToken
from decouple import config
from django.conf import settings


@lru_cache(maxsize=1)
def _fernet() -> Fernet:
    secret = config('ENCRYPTION_KEY', default='') or settings.SECRET_KEY
    key = base64.urlsafe_b64encode(hashlib.sha256(f'scope-secrets:{secret}'.encode()).digest())
    return Fernet(key)


def encrypt(raw: str) -> str:
    return _fernet().encrypt(raw.encode()).decode()


def decrypt(token: str) -> str:
    try:
        return _fernet().decrypt(token.encode()).decode()
    except InvalidToken:
        return ''
