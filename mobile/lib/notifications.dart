import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

/// Напоминания о задачах — локальные, без сервера пушей.
///
/// Как в десктопном приложении: за N минут до задачи со временем, а если у задачи
/// стоит личное напоминание — ровно в него. После каждой синхронизации расписание
/// пересобирается целиком на неделю вперёд.
class Reminders {
  Reminders._();

  static final instance = Reminders._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  // Время задач на сервере — московское, телефон может жить в другом поясе.
  late final tz.Location _zone;

  static const _channel = AndroidNotificationDetails(
    'scope_reminders',
    'Напоминания о задачах',
    channelDescription: 'Перед задачами со временем',
    importance: Importance.high,
    priority: Priority.high,
    color: _accent,
    category: AndroidNotificationCategory.reminder,
  );

  static const _accent = Color(0xFF7C3AED);

  Future<void> init() async {
    tzdata.initializeTimeZones();
    _zone = tz.getLocation('Europe/Moscow');
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        // На Windows — обычные тосты; GUID постоянный, иначе Windows считает это новым приложением.
        windows: WindowsInitializationSettings(
          appName: 'Scope',
          appUserModelId: 'DrXeno.Scope',
          guid: '6f3c2a7e-1b4d-4e8a-9c21-5d7e8f0a3b64',
        ),
      ),
    );
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> requestPermissions() async {
    await _android?.requestNotificationsPermission();
  }

  Future<bool> canExact() async => await _android?.canScheduleExactNotifications() ?? false;

  Future<void> requestExact() async => _android?.requestExactAlarmsPermission();

  Future<void> cancelAll() async {
    if (_ready) await _plugin.cancelAll();
  }

  Future<void> schedule(
      Iterable<Task> tasks, int leadMinutes, Project? Function(int?) projectOf) async {
    if (!_ready) return;
    await _plugin.cancelAllPendingNotifications();

    final now = tz.TZDateTime.now(_zone);
    final horizon = now.add(const Duration(days: 7));
    final mode = await canExact()
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    final plan = <(Task, tz.TZDateTime)>[];
    for (final t in tasks) {
      if (t.isCompleted) continue;
      tz.TZDateTime? at;
      final r = t.reminderAt;
      final s = t.startsAt;
      if (r != null) {
        at = tz.TZDateTime(_zone, r.year, r.month, r.day, r.hour, r.minute);
      } else if (s != null && leadMinutes > 0) {
        at = tz.TZDateTime(_zone, s.year, s.month, s.day, s.hour, s.minute)
            .subtract(Duration(minutes: leadMinutes));
      }
      if (at != null && at.isAfter(now) && at.isBefore(horizon)) plan.add((t, at));
    }
    // Android держит ограниченное число будильников на приложение — берём ближайшие.
    plan.sort((a, b) => a.$2.compareTo(b.$2));

    for (final (t, at) in plan.take(48)) {
      final project = projectOf(t.projectId);
      final title = t.dueTime == null
          ? 'Напоминание'
          : leadMinutes > 0 && t.reminderAt == null
              ? 'Через $leadMinutes мин · ${t.dueTime}'
              : 'В ${t.dueTime}';
      try {
        await _plugin.zonedSchedule(
          id: t.id,
          scheduledDate: at,
          notificationDetails: const NotificationDetails(android: _channel, windows: WindowsNotificationDetails()),
          androidScheduleMode: mode,
          title: title,
          body: project == null ? t.title : '${t.title}\n${project.name}',
          payload: '${t.id}',
        );
      } catch (_) {
        // Без разрешения на точные будильники часть систем бросает исключение — пропускаем.
      }
    }
  }
}
