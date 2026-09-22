"""Окно Qt WebEngine: стартовый URL и брендинг из ``app_manifest.json`` (см. manifest.py).

Зависимости: PySide6, PySide6-Addons; для сборки ico из сгенерированной иконки: Pillow.
Сборка exe: из каталога ``app`` — ``make build`` (иконка по манифесту, PyInstaller ``app.spec``).
Запуск: python main.py

Ctrl+F5 (или Ctrl+Shift+R) — очистка HTTP-кэша и перезагрузка страницы (после обновления сервера).

Напоминания: приложение живёт в трее и шлёт системные уведомления Windows о задачах
с временем — за столько минут, сколько выбрано в меню трея. Ключ ``--tray`` стартует
свёрнутым (для автозагрузки).

Сервер в локальной сети отдаёт самоподписанный сертификат: хосты из
``trusted_insecure_hosts`` манифеста принимаются без предупреждения, остальные — нет.
"""

from __future__ import annotations

import json
import os
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

from PySide6.QtCore import QRectF, QSettings, QTimer, QUrl, Qt
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
from PySide6.QtGui import QAction, QActionGroup
from PySide6.QtWidgets import QApplication, QMainWindow, QMenu, QSystemTrayIcon
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


REMINDER_CHOICES = (0, 5, 10, 15, 30, 60)
DEFAULT_LEAD_MINUTES = 15
POLL_INTERVAL_MS = 30_000

# Страница сама держит свежий список задач на сегодня: у неё уже есть сессия,
# поэтому приложению не нужен отдельный токен к API.
SNAPSHOT_JS = """
(function () {
    if (window.__scopeSnapshotTimer) return 'already';
    async function pull() {
        try {
            const d = new Date();
            const s = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0')
                      + '-' + String(d.getDate()).padStart(2, '0');
            const res = await fetch(`/api/kanban-events/?start=${s}&end=${s}`, {credentials: 'same-origin'});
            const ct = res.headers.get('content-type') || '';
            if (!res.ok || ct.indexOf('json') === -1) { window.__scopeSnapshot = null; return; }
            window.__scopeSnapshot = {at: Date.now(), events: await res.json()};
        } catch (e) {
            window.__scopeSnapshot = null;
        }
    }
    pull();
    window.__scopeSnapshotTimer = setInterval(pull, 30000);
    return 'started';
})();
"""


class Reminders:
    """Системные уведомления Windows о задачах, до которых осталось меньше N минут."""

    def __init__(self, window: QMainWindow, tray: QSystemTrayIcon, settings: QSettings) -> None:
        self._window = window
        self._tray = tray
        self._settings = settings
        self._notified: set[int] = set()
        self._day = date.today()

        self._timer = QTimer(window)
        self._timer.setInterval(POLL_INTERVAL_MS)
        self._timer.timeout.connect(self._tick)
        self._timer.start()

    @property
    def lead_minutes(self) -> int:
        try:
            value = int(self._settings.value("reminders/lead_minutes", DEFAULT_LEAD_MINUTES))
        except (TypeError, ValueError):
            return DEFAULT_LEAD_MINUTES
        return value if value in REMINDER_CHOICES else DEFAULT_LEAD_MINUTES

    def set_lead_minutes(self, minutes: int) -> None:
        self._settings.setValue("reminders/lead_minutes", int(minutes))
        # Другой интервал — другие задачи попадают в окно предупреждения.
        self._notified.clear()

    def install_snapshot(self) -> None:
        """Вживить в страницу сборщик задач (после каждой загрузки)."""
        page = self._window.view.page()
        if page is not None:
            page.runJavaScript(SNAPSHOT_JS)

    def _tick(self) -> None:
        if self.lead_minutes == 0:
            return
        page = self._window.view.page()
        if page is None:
            return
        page.runJavaScript("JSON.stringify(window.__scopeSnapshot || null)", self._on_snapshot)

    def _on_snapshot(self, raw) -> None:
        if not raw:
            return
        try:
            data = json.loads(raw)
        except (TypeError, ValueError):
            return
        if not isinstance(data, dict):
            return

        today = date.today()
        if today != self._day:
            self._day = today
            self._notified.clear()

        lead = self.lead_minutes
        now = datetime.now()
        for event in data.get("events") or []:
            if not isinstance(event, dict) or event.get("completed"):
                continue
            task_id = event.get("id")
            raw_time = event.get("time")
            if task_id in self._notified:
                continue

            start_at = None
            if raw_time:
                try:
                    start_at = datetime.combine(today, datetime.strptime(raw_time, "%H:%M").time())
                except ValueError:
                    start_at = None

            # Личное время напоминания у задачи важнее общего интервала.
            remind_at = None
            raw_reminder = event.get("reminder")
            if raw_reminder:
                try:
                    remind_at = datetime.strptime(str(raw_reminder).replace("T", " ")[:16], "%Y-%m-%d %H:%M")
                except ValueError:
                    remind_at = None

            if remind_at is not None:
                # Окно в час: если приложение было выключено дольше — не будим задним числом.
                if not (timedelta(0) <= now - remind_at <= timedelta(hours=1)):
                    continue
                self._notified.add(task_id)
                left = (start_at - now) / timedelta(minutes=1) if start_at else None
                self._notify(event, left, raw_time)
                continue

            if start_at is None:
                continue
            left = (start_at - now) / timedelta(minutes=1)
            if 0 < left <= lead:
                self._notified.add(task_id)
                self._notify(event, left, raw_time)

    def _notify(self, event: dict, minutes_left, at) -> None:
        if minutes_left is None:
            title = "Напоминание"
        elif minutes_left >= 90:
            title = f"Через {int(round(minutes_left / 60))} ч · {at}"
        else:
            title = f"Через {max(1, int(round(minutes_left)))} мин · {at}"
        body = str(event.get("title") or "Задача")
        project = event.get("project")
        if project:
            body += f"\n{project}"
        print(f"[напоминание] {title} — {body}".replace("\n", " · "), file=sys.stderr)
        self._tray.showMessage(title, body, QSystemTrayIcon.MessageIcon.Information, 15000)


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
        page.certificateError.connect(self._on_certificate_error)
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

        # Жёсткое обновление после деплоя: сброс HTTP-кэша Chromium + reload без кэша.
        for seq in (QKeySequence("Ctrl+F5"), QKeySequence("Ctrl+Shift+R")):
            hard = QShortcut(seq, self)
            hard.setContext(Qt.ShortcutContext.ApplicationShortcut)
            hard.activated.connect(self._hard_reload)

        self.reminders: Reminders | None = None
        self._tray_hint_shown = False
        self.view.loadFinished.connect(self._on_load_finished)

    def _on_load_finished(self, ok: bool) -> None:
        if ok and self.reminders is not None:
            self.reminders.install_snapshot()

    def closeEvent(self, event) -> None:
        """Крестик прячет окно в трей — иначе напоминания умирают вместе с окном."""
        tray = getattr(self, "tray", None)
        if tray is not None and tray.isVisible():
            event.ignore()
            self.hide()
            if not self._tray_hint_shown:
                self._tray_hint_shown = True
                tray.showMessage(
                    self._manifest.display_name,
                    "Свёрнут в трей и следит за расписанием.\nВыход — правой кнопкой по значку.",
                    QSystemTrayIcon.MessageIcon.Information,
                    6000,
                )
            return
        super().closeEvent(event)

    def _on_certificate_error(self, error) -> None:
        """Самоподписанный сертификат своего сервера — принять, чужой — отклонить."""
        host = error.url().host().lower()
        if host in self._manifest.trusted_insecure_hosts:
            error.acceptCertificate()
            return
        print(f"Сертификат отклонён: {host} — {error.description()}", file=sys.stderr)
        error.rejectCertificate()

    def _hard_reload(self) -> None:
        page = self.view.page()
        if page is None:
            return
        self.profile.clearHttpCache()
        page.reload(QWebEnginePage.ReloadBypassCache)

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


def build_tray(window: BrowserWindow, icon: QIcon, manifest: AppManifest, settings: QSettings) -> QSystemTrayIcon:
    """Значок в трее: показать окно, выбрать интервал напоминаний, выйти."""
    tray = QSystemTrayIcon(icon, window)
    tray.setToolTip(manifest.display_name)

    menu = QMenu()
    open_action = QAction("Открыть Scope", menu)
    open_action.triggered.connect(lambda: _show_window(window))
    menu.addAction(open_action)

    menu.addSeparator()
    reminders_menu = menu.addMenu("Напоминать")
    group = QActionGroup(menu)
    group.setExclusive(True)

    window.tray = tray  # noqa: B010 — closeEvent проверяет наличие трея
    reminders = Reminders(window, tray, settings)
    window.reminders = reminders

    for minutes in REMINDER_CHOICES:
        label = "Не напоминать" if minutes == 0 else f"за {minutes} мин"
        action = QAction(label, reminders_menu)
        action.setCheckable(True)
        action.setChecked(minutes == reminders.lead_minutes)
        action.triggered.connect(lambda _checked=False, m=minutes: reminders.set_lead_minutes(m))
        group.addAction(action)
        reminders_menu.addAction(action)

    menu.addSeparator()
    quit_action = QAction("Выход", menu)
    quit_action.triggered.connect(QApplication.quit)
    menu.addAction(quit_action)

    tray.setContextMenu(menu)
    tray.activated.connect(
        lambda reason: _show_window(window)
        if reason == QSystemTrayIcon.ActivationReason.Trigger
        else None
    )
    tray.messageClicked.connect(lambda: _show_window(window))
    tray.show()
    return tray


def _show_window(window: QMainWindow) -> None:
    window.showNormal()
    window.raise_()
    window.activateWindow()


def main() -> int:
    base = app_base_dir()
    manifest = load_manifest(base)

    app = QApplication(sys.argv)
    app.setApplicationName(manifest.display_name)
    app.setOrganizationName(manifest.organization_name)
    icon = app_icon(manifest, base)
    app.setWindowIcon(icon)

    window = BrowserWindow(manifest, base)

    settings = QSettings(manifest.organization_name, manifest.display_name)
    if QSystemTrayIcon.isSystemTrayAvailable():
        build_tray(window, icon, manifest, settings)
        # Окно закрыто — приложение живёт в трее и продолжает напоминать.
        app.setQuitOnLastWindowClosed(False)

    if "--tray" not in sys.argv:
        window.show()

    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
