from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand

from apps.scope.models import Task


class Command(BaseCommand):
    help = 'Закрыть задачи с автозакрытием, день которых уже прошёл (для крона).'

    def handle(self, *args, **options):
        total = 0
        for user in get_user_model().objects.filter(is_active=True):
            closed = Task.autoclose_past(user)
            if closed:
                total += closed
                self.stdout.write(f'{user.username}: закрыто {closed}')
        self.stdout.write(self.style.SUCCESS(f'Всего закрыто: {total}'))
