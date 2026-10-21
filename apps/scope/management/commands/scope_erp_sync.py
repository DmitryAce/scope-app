import time

from django.core.management.base import BaseCommand

from apps.scope.erp_sync import sync_everyone


class Command(BaseCommand):
    help = 'Подтянуть задачи из ERP всем, у кого есть подключение. --loop N — повторять каждые N секунд.'

    def add_arguments(self, parser):
        parser.add_argument('--loop', type=int, default=0, help='Интервал в секундах; 0 — один прогон')

    def handle(self, *args, loop, **options):
        while True:
            for key, stats in sync_everyone().items():
                self.stdout.write(f'{key}: {stats}')
            if not loop:
                return
            time.sleep(loop)
