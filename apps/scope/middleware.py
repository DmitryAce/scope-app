"""Мидлвары приложения scope."""

from __future__ import annotations

from django.utils import timezone

from apps.scope.models import Task

SESSION_KEY = 'autoclose_done_for'


class AutoCompleteMiddleware:
    """Раз в день на сессию: закрыть вчерашнее и досоздать повторяющиеся задачи.

    Дешевле крона и не зависит от него: первая же страница после полуночи разгребает
    вчерашние пары и встречи и подливает вперёд повторы по правилам.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        user = getattr(request, 'user', None)
        if user is not None and user.is_authenticated:
            today = timezone.localdate().isoformat()
            if request.session.get(SESSION_KEY) != today:
                Task.autoclose_past(user)
                Task.spawn_all_repeats(user)
                request.session[SESSION_KEY] = today
        return self.get_response(request)
