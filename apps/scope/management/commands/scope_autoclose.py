from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand

from apps.scope.models import Task


class Command(BaseCommand):
    help = 'Закрыть просроченные задачи с автозакрытием и досоздать повторы (для крона).'

    def handle(self, *args, **options):
        total = 0
        spawned = 0
        for user in get_user_model().objects.filter(is_active=True):
            closed = Task.autoclose_past(user)
            made = Task.spawn_all_repeats(user)
            if closed or made:
                total += closed
                spawned += made
                self.stdout.write(f'{user.username}: закрыто {closed}, создано повторов {made}')
        self.stdout.write(self.style.SUCCESS(f'Всего закрыто: {total}, повторов создано: {spawned}'))
