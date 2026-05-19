"""Окно Qt WebEngine: стартовый URL и брендинг из ``app_manifest.json`` (см. manifest.py).

Зависимости: PySide6, PySide6-Addons; для сборки ico из сгенерированной иконки: Pillow.
Сборка exe: из каталога ``app`` — ``make build`` (иконка по манифесту, PyInstaller ``app.spec``).
Запуск: python main.py
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from PySide6.QtCore import QRectF, QUrl, Qt
from PySide6.QtGui import (
    QColor,
    QFont,
    QIcon,
    QKeySequence,
    QLinearGradient,
    QPainter,
    QPainterPath,
    QPixmap,
    QShortcut,
)
from PySide6.QtWidgets import QApplication, QMainWindow
from PySide6.QtWebEngineWidgets import QWebEngineView
from PySide6.QtWebEngineCore import QWebEnginePage, QWebEngineProfile

from manifest import AppManifest, load_manifest


def app_base_dir() -> Path:
    """Каталог с манифестом и ресурсами: в onefile — извлечённый bundle (_MEIPASS)."""
    if getattr(sys, "frozen", False) and getattr(sys, "_MEIPASS", None):
        return Path(sys._MEIPASS)
    return Path(__file__).resolve().parent


def _is_bundled_executable() -> bool:
    return bool(getattr(sys, "frozen", False) or getattr(sys, "_MEIPASS", None))


def web_engine_profile_dir(manifest: AppManifest) -> str:
    """Стабильный каталог для cookies / localStorage."""
    name = manifest.profile_data_folder
    if _is_bundled_executable():
        if sys.platform == "win32":
            base = os.environ.get("LOCALAPPDATA")
            if not base:
                base = os.path.join(os.path.expanduser("~"), "AppData", "Local")
            path = os.path.join(base, name, "browser_profile")
        elif sys.platform == "darwin":
            path = os.path.join(
                os.path.expanduser("~"),
                "Library",
                "Application Support",
                name,
                "browser_profile",
            )
        else:
            xdg = os.environ.get("XDG_DATA_HOME", os.path.join(os.path.expanduser("~"), ".local", "share"))
            path = os.path.join(xdg, name, "browser_profile")
        return os.path.abspath(path)

    root = Path(__file__).resolve().parent
    return os.path.abspath(str(root / "browser_profile"))


def _scoped_web_profile(app: QApplication, manifest: AppManifest) -> QWebEngineProfile:
    cached = getattr(app, "_embedded_browser_profile", None)
    if isinstance(cached, QWebEngineProfile):
        return cached

    profile_dir = web_engine_profile_dir(manifest)
    os.makedirs(profile_dir, exist_ok=True)

    profile = QWebEngineProfile(manifest.web_engine_profile_name, app)
    profile.setPersistentStoragePath(profile_dir)
    profile.setCachePath(os.path.join(profile_dir, "cache"))
    profile.setPersistentCookiesPolicy(QWebEngineProfile.ForcePersistentCookies)

    app._embedded_browser_profile = profile  # noqa: SLF001
    return profile


def app_icon(manifest: AppManifest, base: Path) -> QIcon:
    """Иконка из ``icon_path`` (png/ico), иначе — сгенерированная по полям манифеста."""
    if manifest.icon_path:
        p = (base / manifest.icon_path).resolve()
        if p.is_file():
            return QIcon(str(p))

    size = 256
    corner = int(round(6 * size / 32))
    px = QPixmap(size, size)
    px.fill(Qt.GlobalColor.transparent)

    painter = QPainter(px)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    painter.setRenderHint(QPainter.RenderHint.TextAntialiasing)

    body = QPainterPath()
    body.addRoundedRect(0.0, 0.0, float(size), float(size), float(corner), float(corner))

    gradient = QLinearGradient(0.0, 0.0, float(size), float(size))
    gradient.setColorAt(0.0, QColor(manifest.generated_icon_gradient_start))
    gradient.setColorAt(1.0, QColor(manifest.generated_icon_gradient_end))
    painter.fillPath(body, gradient)

    font = QFont("Arial")
    font.setBold(True)
    font.setPixelSize(round(20 * size / 32))

    painter.setFont(font)
    painter.setPen(QColor("#ffffff"))
    painter.drawText(
        QRectF(0.0, 0.0, float(size), float(size)),
        int(Qt.AlignmentFlag.AlignCenter),
        manifest.generated_icon_letter[:1] or "?",
    )

    painter.end()

    icon = QIcon()
    for side in (16, 24, 32, 48, 64, 128, 256):
        scaled = px.scaled(
            side,
            side,
            Qt.AspectRatioMode.KeepAspectRatio,
            Qt.TransformationMode.SmoothTransformation,
        )
        icon.addPixmap(scaled)
    return icon


class BrowserWindow(QMainWindow):
    def __init__(self, manifest: AppManifest, base: Path) -> None:
        super().__init__()
        self._manifest = manifest
        self._base = base

        self.setWindowTitle(manifest.display_name)
        self.resize(1280, 800)

        app = QApplication.instance()
        assert app is not None
        self.profile = _scoped_web_profile(app, manifest)

        self.view = QWebEngineView(self)
        page = QWebEnginePage(self.profile, self.view)
        self.view.setPage(page)
        self.view.setUrl(QUrl(manifest.start_url))

        self.setCentralWidget(self.view)

        self.setMinimumSize(800, 600)

        self.setWindowIcon(app_icon(manifest, base))

        # F11 / Esc: QMainWindow.keyPressEvent не получает события, пока фокус у
        # QWebEngineView (Chromium). Глобальные шорткаты приложения срабатывают всегда.
        fs = QShortcut(QKeySequence(Qt.Key_F11), self)
        fs.setContext(Qt.ShortcutContext.ApplicationShortcut)
        fs.activated.connect(self._toggle_fullscreen)

        esc = QShortcut(QKeySequence(Qt.Key_Escape), self)
        esc.setContext(Qt.ShortcutContext.ApplicationShortcut)
        esc.activated.connect(self._leave_fullscreen_if_needed)

    def _toggle_fullscreen(self) -> None:
        if self.isFullScreen():
            self.showNormal()
        else:
            self.showFullScreen()

    def _leave_fullscreen_if_needed(self) -> None:
        if self.isFullScreen():
            self.showNormal()

    def keyPressEvent(self, event) -> None:
        if event.key() == Qt.Key_F11:
            self._toggle_fullscreen()
            return
        if event.key() == Qt.Key_Escape and self.isFullScreen():
            self.showNormal()
            return
        super().keyPressEvent(event)


def main() -> int:
    base = app_base_dir()
    manifest = load_manifest(base)

    app = QApplication(sys.argv)
    app.setApplicationName(manifest.display_name)
    app.setOrganizationName(manifest.organization_name)
    app.setWindowIcon(app_icon(manifest, base))

    window = BrowserWindow(manifest, base)
    window.show()

    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
