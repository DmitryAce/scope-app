import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';

/// Редактируемая копия задачи: общая для быстрого ввода и полного экрана.
class TaskDraft {
  TaskDraft.fromTask(Task? t, {DateTime? day, int? projectId})
      : title = t?.title ?? '',
        description = t?.description ?? '',
        date = t != null ? t.dueDate : (day ?? (projectId == null ? dayOnly(DateTime.now()) : null)),
        time = t?.startMinute == null ? null : TimeOfDay(hour: t!.startMinute! ~/ 60, minute: t.startMinute! % 60),
        duration = t?.durationMinutes,
        priority = t?.priority ?? 2,
        projectId = t?.projectId ?? projectId,
        repeat = t?.repeat ?? '',
        tags = {...?t?.tagIds},
        autoComplete = t?.autoComplete ?? false,
        reminder = t?.reminderAt;

  String title;
  String description;
  DateTime? date;
  TimeOfDay? time;
  int? duration;
  int priority;
  int? projectId;
  String repeat;
  Set<int> tags;
  bool autoComplete;
  DateTime? reminder;

  /// Пункты чек-листа новой задачи — уходят на сервер после создания.
  final List<String> newChecklist = [];

  String? get timeStr => time == null ? null : _hm(time!.hour, time!.minute);

  static String _hm(int h, int m) => '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  String? get reminderStr => reminder == null ? null : '${ymd(reminder!)} ${_hm(reminder!.hour, reminder!.minute)}';

  String dateLabel() => date == null ? 'Без даты' : fmtRelDay(date!);

  String reminderLabel() => reminder == null ? 'Нет' : '${fmtShortDay(reminder!)}, ${_hm(reminder!.hour, reminder!.minute)}';

  /// Тело запроса. [old] — исходная задача: повтор шлём только если он изменился,
  /// иначе сервер заново раскладывает копии.
  Map<String, dynamic> toBody({Task? old}) {
    final body = <String, dynamic>{
      'title': title.trim(),
      'description': description.trim(),
      'priority': priority,
      'project_id': projectId,
      'due_date': date == null ? '' : ymd(date!),
      'due_time': date == null ? '' : (timeStr ?? ''),
      'duration_minutes': duration,
      'auto_complete': autoComplete,
      'reminder': reminderStr ?? '',
      'tag_ids': tags.toList(),
    };
    if (old == null || repeat != old.repeat) body['repeat'] = repeat;
    if (old == null) body.removeWhere((k, v) => v == '');
    return body;
  }
}

/// Выборы полей. Каждый возвращает true, если черновик изменился.
class Pick {
  static Future<bool> day(BuildContext context, TaskDraft d) async {
    final today = dayOnly(DateTime.now());
    final monday = today.add(Duration(days: 8 - today.weekday));
    final v = await choose<String>(context, 'Когда', [
      ('today', 'Сегодня', PhosphorIconsRegular.sun, C.high),
      ('tomorrow', 'Завтра', PhosphorIconsRegular.sunHorizon, C.accent2),
      ('monday', 'В понедельник · ${fmtShortDay(monday)}', PhosphorIconsRegular.calendarPlus, C.medium),
      ('pick', 'Выбрать дату…', PhosphorIconsRegular.calendarBlank, C.text2),
      ('none', 'Без даты', PhosphorIconsRegular.tray, C.muted),
    ]);
    if (v == null || !context.mounted) return false;
    switch (v) {
      case 'today':
        d.date = today;
      case 'tomorrow':
        d.date = today.add(const Duration(days: 1));
      case 'monday':
        d.date = monday;
      case 'none':
        d.date = null;
        d.time = null;
        d.repeat = '';
      case 'pick':
        final p = await showDatePicker(
          context: context,
          initialDate: d.date ?? today,
          firstDate: DateTime(today.year - 2),
          lastDate: DateTime(today.year + 5),
          locale: const Locale('ru'),
        );
        if (p == null) return false;
        d.date = p;
    }
    return true;
  }

  static Future<bool> time(BuildContext context, TaskDraft d) async {
    final t = await showTimePicker(
      context: context,
      initialTime: d.time ?? TimeOfDay(hour: (TimeOfDay.now().hour + 1) % 24, minute: 0),
      builder: _h24,
    );
    if (t == null) return false;
    d.time = t;
    d.date ??= dayOnly(DateTime.now());
    return true;
  }

  static Future<bool> duration(BuildContext context, TaskDraft d) async {
    final v = await choose<int>(
      context,
      'Длительность',
      [
        for (final m in [15, 30, 45, 60, 90, 120, 180]) (m, fmtDuration(m), PhosphorIconsRegular.timer, null),
        (0, 'Без длительности', PhosphorIconsRegular.prohibit, C.muted),
      ],
      current: d.duration ?? 0,
    );
    if (v == null) return false;
    d.duration = v == 0 ? null : v;
    return true;
  }

  static Future<bool> priority(BuildContext context, TaskDraft d) async {
    final v = await choose<int>(
      context,
      'Приоритет',
      [for (final p in [4, 3, 2, 1]) (p, priorityLabels[p]!, PhosphorIconsFill.flag, C.priority(p))],
      current: d.priority,
    );
    if (v == null) return false;
    d.priority = v;
    return true;
  }

  static Future<bool> repeat(BuildContext context, TaskDraft d) async {
    final v = await choose<String>(
      context,
      'Повтор',
      [for (final e in repeatLabels.entries) (e.key, e.value, PhosphorIconsRegular.repeat, null)],
      current: d.repeat,
    );
    if (v == null) return false;
    d.repeat = v;
    if (v.isNotEmpty) d.date ??= dayOnly(DateTime.now());
    return true;
  }

  static Future<bool> reminder(BuildContext context, TaskDraft d) async {
    final options = <(String, String, IconData, Color?)>[];
    if (d.date != null && d.time != null) {
      final start = d.date!.add(Duration(hours: d.time!.hour, minutes: d.time!.minute));
      for (final m in [10, 30, 60]) {
        if (start.subtract(Duration(minutes: m)).isAfter(DateTime.now())) {
          options.add(('-$m', 'За ${m == 60 ? 'час' : '$m мин'} до начала', PhosphorIconsRegular.bellSimple, null));
        }
      }
    }
    options.add(('pick', 'Выбрать время…', PhosphorIconsRegular.clock, null));
    if (d.reminder != null) options.add(('none', 'Не напоминать', PhosphorIconsRegular.bellSimpleSlash, C.muted));
    final v = await choose<String>(context, 'Напомнить', options);
    if (v == null || !context.mounted) return false;
    if (v == 'none') {
      d.reminder = null;
      return true;
    }
    if (v.startsWith('-')) {
      final start = d.date!.add(Duration(hours: d.time!.hour, minutes: d.time!.minute));
      d.reminder = start.subtract(Duration(minutes: int.parse(v.substring(1))));
      return true;
    }
    final base = d.reminder ?? DateTime.now().add(const Duration(hours: 1));
    final day = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      helpText: 'День напоминания',
      locale: const Locale('ru'),
    );
    if (day == null || !context.mounted) return false;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(base), helpText: 'Время напоминания', builder: _h24);
    if (t == null) return false;
    d.reminder = DateTime(day.year, day.month, day.day, t.hour, t.minute);
    return true;
  }

  static Future<bool> project(BuildContext context, TaskDraft d) async {
    final store = StoreScope.read(context);
    Widget row(BuildContext c, Project? p, {bool nested = false}) => ListTile(
          contentPadding: EdgeInsets.only(left: nested ? 44 : 20, right: 20),
          leading: ProjectAvatar(project: p, size: nested ? 28 : 34),
          title: Text(p?.name ?? 'Без проекта', style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: (p?.id ?? 0) == (d.projectId ?? 0)
              ? const Icon(PhosphorIconsBold.check, color: C.accent2, size: 18)
              : null,
          onTap: () => Navigator.pop(c, p?.id ?? 0),
        );
    final v = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (c) => _SheetFrame(title: 'Проект', children: [
        row(c, null),
        for (final p in store.rootProjects) ...[
          row(c, p),
          for (final ch in store.childrenOf(p.id)) row(c, ch, nested: true),
        ],
      ]),
    );
    if (v == null) return false;
    d.projectId = v == 0 ? null : v;
    return true;
  }

  static Future<bool> tags(BuildContext context, TaskDraft d) async {
    final store = StoreScope.read(context);
    final selected = {...d.tags};
    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => _SheetFrame(
          title: 'Теги',
          footer: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(onPressed: () => Navigator.pop(c, selected), child: const Text('Готово')),
            ),
          ),
          children: [
            if (store.tags.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Тегов пока нет', style: TextStyle(color: C.text2)),
              ),
            for (final t in store.tags)
              CheckboxListTile(
                value: selected.contains(t.id),
                activeColor: t.tint,
                title: Text(t.name),
                secondary: Icon(PhosphorIconsRegular.hash, color: t.tint),
                onChanged: (on) => set(() => on! ? selected.add(t.id) : selected.remove(t.id)),
              ),
          ],
        ),
      ),
    );
    if (result == null) return false;
    d.tags = result;
    return true;
  }

  static Widget _h24(BuildContext c, Widget? child) =>
      MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!);
}

/// Простой список вариантов в шторке.
Future<T?> choose<T>(BuildContext context, String title, List<(T, String, IconData, Color?)> options, {T? current}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (c) => _SheetFrame(title: title, children: [
      for (final (value, label, icon, color) in options)
        ListTile(
          leading: Icon(icon, color: color ?? C.text2, size: 22),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: value == current ? const Icon(PhosphorIconsBold.check, color: C.accent2, size: 18) : null,
          onTap: () => Navigator.pop(c, value),
        ),
    ]),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.children, this.footer});

  final String title;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ),
          Flexible(child: ListView(shrinkWrap: true, children: children)),
          footer ?? const SizedBox(height: 8),
        ]),
      ),
    );
  }
}
