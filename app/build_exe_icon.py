"""Собирает .ico для PyInstaller по ``app_manifest.json`` (поле ``build_ico_path``).

- Если задан ``icon_path`` и это .ico — копирует в ``build_ico_path``.
- Если ``icon_path`` — .png (или другой растр) — конвертирует в многослойный ICO через Pillow.
- Иначе — рендерит ту же сгенерированную иконку, что и в main (через Qt), пишет ICO.

Запуск из каталога app: python build_exe_icon.py
"""

from __future__ import annotations

import os
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def main() -> int:
    sys.path.insert(0, str(ROOT))
    from manifest import load_manifest  # noqa: E402

    manifest = load_manifest(ROOT)
    ico_out = (ROOT / manifest.build_ico_path).resolve()

    icon_path = manifest.icon_path
    if icon_path:
        src = (ROOT / icon_path).resolve()
        if src.is_file():
            suffix = src.suffix.lower()
            if suffix == ".ico":
                if src.resolve() != ico_out.resolve():
                    shutil.copyfile(src, ico_out)
                print(ico_out)
                return 0
            try:
                from PIL import Image
            except ImportError as exc:
                raise SystemExit("Для конвертации растра в ICO нужен Pillow: pip install Pillow") from exc

            pil = Image.open(src).convert("RGBA")
            pil.save(
                ico_out,
                format="ICO",
                sizes=[
                    (16, 16),
                    (24, 24),
                    (32, 32),
                    (48, 48),
                    (64, 64),
                    (128, 128),
                    (256, 256),
                ],
            )
            print(ico_out)
            return 0

    from PySide6.QtWidgets import QApplication

    _ = QApplication(sys.argv[:1] if sys.argv else [sys.executable])

    import main as app_main  # noqa: E402

    try:
        from PIL import Image
    except ImportError as exc:
        raise SystemExit("Для ICO из сгенерированной иконки нужен Pillow: pip install Pillow") from exc

    icon = app_main.app_icon(manifest, ROOT)
    pm = icon.pixmap(256, 256)

    fd, tmp_path = tempfile.mkstemp(suffix=".png", prefix="app_icon_")
    os.close(fd)
    try:
        if not pm.save(tmp_path, "PNG"):
            raise RuntimeError("Не удалось сохранить PNG промежуточной иконки")
        pil = Image.open(tmp_path).convert("RGBA")
        pil.save(
            ico_out,
            format="ICO",
            sizes=[
                (16, 16),
                (24, 24),
                (32, 32),
                (48, 48),
                (64, 64),
                (128, 128),
                (256, 256),
            ],
        )
    finally:
        try:
            os.remove(tmp_path)
        except OSError:
            pass

    print(ico_out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
