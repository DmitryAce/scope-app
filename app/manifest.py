"""Загрузка ``app_manifest.json`` — имя приложения, URL, пути профиля, иконка, имя exe."""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass
from pathlib import Path


MANIFEST_FILENAME = "app_manifest.json"


@dataclass(frozen=True)
class AppManifest:
    display_name: str
    organization_name: str
    start_url: str
    profile_data_folder: str
    web_engine_profile_name: str
    executable_basename: str
    build_ico_path: str
    icon_path: str | None
    generated_icon_letter: str
    generated_icon_gradient_start: str
    generated_icon_gradient_end: str


def load_manifest(root: Path) -> AppManifest:
    path = root / MANIFEST_FILENAME
    if not path.is_file():
        raise FileNotFoundError(
            f"Нет {MANIFEST_FILENAME} в {root}. Скопируйте и заполните манифест рядом с main.py."
        )
    raw = json.loads(path.read_text(encoding="utf-8"))
    gen = raw.get("generated_icon") if isinstance(raw.get("generated_icon"), dict) else {}
    icon_path = raw.get("icon_path")
    if isinstance(icon_path, str) and not icon_path.strip():
        icon_path = None
    return AppManifest(
        display_name=str(raw["display_name"]),
        organization_name=str(raw.get("organization_name") or raw["display_name"]),
        start_url=str(raw["start_url"]),
        profile_data_folder=str(raw["profile_data_folder"]),
        web_engine_profile_name=str(raw["web_engine_profile_name"]),
        executable_basename=str(raw["executable_basename"]),
        build_ico_path=str(raw["build_ico_path"]),
        icon_path=str(icon_path) if icon_path else None,
        generated_icon_letter=str(gen.get("letter", "S")),
        generated_icon_gradient_start=str(gen.get("gradient_start", "#8B2942")),
        generated_icon_gradient_end=str(gen.get("gradient_end", "#6B1D32")),
    )


def _cli(root: Path) -> None:
    if len(sys.argv) < 2:
        print("Использование: python manifest.py <exe|ico>", file=sys.stderr)
        raise SystemExit(2)
    m = load_manifest(root)
    key = sys.argv[1].strip().lower()
    if key == "exe":
        print(m.executable_basename, end="")
    elif key == "ico":
        print((root / m.build_ico_path).resolve(), end="")
    else:
        print(f"Неизвестный ключ: {sys.argv[1]}", file=sys.stderr)
        raise SystemExit(2)


if __name__ == "__main__":
    _cli(Path(__file__).resolve().parent)
