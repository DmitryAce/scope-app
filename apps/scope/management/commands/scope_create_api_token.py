from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand

from apps.scope.models import ApiAccessToken


class Command(BaseCommand):
    help = 'Создать токен API v2 (headless / MCP). Секрет выводится один раз.'

    def add_arguments(self, parser):
        parser.add_argument('username', type=str, help='Логин пользователя Django')
        parser.add_argument('--name', default='', help='Подпись: mcp, ci, …')

    def handle(self, *args, **options):
        User = get_user_model()
        username = options['username']
        try:
            user = User.objects.get(username=username)
        except User.DoesNotExist:
            self.stderr.write(self.style.ERROR(f'Пользователь {username!r} не найден.'))
            return
        raw, row = ApiAccessToken.issue(user, name=options['name'] or '')
        self.stdout.write(self.style.SUCCESS('Токен создан. Сохраните его — повторно не показывается:'))
        self.stdout.write(raw)
        self.stdout.write(f'(id={row.id}, prefix={row.key_prefix}…)')
