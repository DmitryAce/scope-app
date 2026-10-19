#!/usr/bin/env bash
# Собрать и опубликовать новую версию: приложения увидят её по «Проверить обновления».
#
#   tool/publish.sh android "Что нового"
#   tool/publish.sh windows "Что нового"
#   tool/publish.sh all     "Что нового"
#
# Версия и номер сборки — из pubspec.yaml (version: 1.4.0+5). Номер сборки должен
# расти с каждым релизом, иначе приложения не поймут, что вышло новое.
# Сервер — малинка (ssh-алиас xenolab), контейнер scope_web.
set -euo pipefail

cd "$(dirname "$0")/.."
target="${1:?android | windows | all}"
notes="${2:-}"
host="${SCOPE_HOST:-xenolab}"

full=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
version="${full%%+*}"
build="${full##*+}"
echo "Scope $version ($build)"

publish() {  # platform file
  local platform="$1" file="$2" name
  name="$(basename "$file")"
  scp -q "$file" "$host:/tmp/$name"
  # Заметки передаём через файл: так не ломаются кавычки и кириллица.
  printf '%s' "$notes" | ssh "$host" "cat > /tmp/scope-notes.txt"
  ssh "$host" "docker cp /tmp/$name scope_web:/tmp/$name && docker cp /tmp/scope-notes.txt scope_web:/tmp/scope-notes.txt \
    && docker exec scope_web sh -c 'python manage.py scope_publish_app $platform $version $build /tmp/$name --notes \"\$(cat /tmp/scope-notes.txt)\" && rm /tmp/$name /tmp/scope-notes.txt' \
    && rm /tmp/$name /tmp/scope-notes.txt" 2>&1 | grep -v "openclaw\|rfkill" || true
}

if [[ "$target" == android || "$target" == all ]]; then
  flutter build apk --release
  publish android build/app/outputs/flutter-apk/app-release.apk
fi

if [[ "$target" == windows || "$target" == all ]]; then
  flutter build windows --release
  zip="build/Scope-windows.zip"
  rm -f "$zip"
  powershell.exe -NoProfile -Command "\$t = Join-Path \$env:TEMP 'scope-pack'; Remove-Item \$t -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force \"\$t\\Scope\" | Out-Null; Copy-Item 'build\\windows\\x64\\runner\\Release\\*' \"\$t\\Scope\" -Recurse; Compress-Archive -Path \"\$t\\Scope\" -DestinationPath '$zip'; Remove-Item \$t -Recurse -Force"
  publish windows "$zip"
fi
