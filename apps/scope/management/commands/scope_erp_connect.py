import os

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError

from apps.scope.erp_sync import PRESETS, ErpError, connect, sync_connection


class Command(BaseCommand):
    help = 'Подключить пользователю ERP из консоли (токен — из переменной окружения, не из аргументов).'

    def add_arguments(self, parser):
        parser.add_argument('username')
        parser.add_argument('preset', choices=sorted(PRESETS))
        parser.add_argument('--token-env', required=True, help='Имя переменной окружения с токеном')

    def handle(self, *args, username, preset, token_env, **options):
        user = get_user_model().objects.filter(username=username).first()
        if user is None:
            raise CommandError(f'Нет пользователя {username}')
        token = os.environ.get(token_env, '')
        try:
            conn = connect(user, token=token, preset=preset)
        except ErpError as e:
            raise CommandError(str(e))
        self.stdout.write(self.style.SUCCESS(f'{username}: {conn.name} подключена -> {sync_connection(conn)}'))
