import json
import shutil
from pathlib import Path

from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from apps.scope.api_v2.views import APP_PLATFORMS, app_releases_dir, read_app_manifest

KEEP_PER_PLATFORM = 2


class Command(BaseCommand):
    help = 'Опубликовать сборку приложения: её увидит кнопка «Проверить обновления».'

    def add_arguments(self, parser):
        parser.add_argument('platform', choices=APP_PLATFORMS)
        parser.add_argument('version', help='Версия для людей, например 1.4.0')
        parser.add_argument('build', type=int, help='Номер сборки (versionCode), растёт с каждым релизом')
        parser.add_argument('file', help='Путь к .apk или .zip')
        parser.add_argument('--notes', default='', help='Что нового — короткий текст')

    def handle(self, *args, platform, version, build, file, notes, **options):
        src = Path(file)
        if not src.is_file():
            raise CommandError(f'Нет файла {src}')
        folder = app_releases_dir()
        folder.mkdir(parents=True, exist_ok=True)

        name = f'Scope-{version}-{platform}{src.suffix}'
        shutil.copyfile(src, folder / name)

        manifest = read_app_manifest()
        manifest[platform] = {
            'version': version,
            'build': build,
            'file': name,
            'size': src.stat().st_size,
            'notes': notes,
            'published_at': timezone.now().isoformat(),
        }
        (folder / 'latest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')

        # Старые сборки этой платформы не копим: последние KEEP_PER_PLATFORM.
        old = sorted(folder.glob(f'Scope-*-{platform}.*'), key=lambda p: p.stat().st_mtime, reverse=True)
        for stale in old[KEEP_PER_PLATFORM:]:
            stale.unlink(missing_ok=True)

        self.stdout.write(self.style.SUCCESS(f'{platform} {version} ({build}) -> {name}'))
