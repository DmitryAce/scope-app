import time

from django.core.management.base import BaseCommand

from apps.scope.erp_sync import sources, sync_all, sync_user


class Command(BaseCommand):
    help = 'Подтянуть задачи из ERP (Webstead, OmniWebers) в Scope. --loop N — повторять каждые N секунд.'

    def add_arguments(self, parser):
        parser.add_argument('--loop', type=int, default=0, help='Интервал в секундах; 0 — один прогон')

    def handle(self, *args, loop, **options):
        user = sync_user()
        if user is None or not sources():
            self.stderr.write('ERP_SYNC_USERNAME или токены ERP не заданы — синхронизировать нечего.')
            if not loop:
                return
        while True:
            if user is not None:
                for source, stats in sync_all(user).items():
                    self.stdout.write(f'{source}: {stats}')
            if not loop:
                return
            time.sleep(loop)
