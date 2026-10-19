import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'project_picker.dart';
import '../screens/tags.dart';

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
        autoDelete = t?.autoDelete ?? false,
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
  bool autoDelete;
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
      'auto_delete': autoDelete,
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
    // Результат: дата из полосы недели или код пункта списка.
    final v = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (c) => _SheetFrame(title: 'Когда', children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: WeekDayPicker(current: d.date, onPick: (day) => Navigator.pop(c, day)),
        ),
        for (final (value, label, icon, color) in [
          ('monday', 'Следующий понедельник · ${fmtShortDay(monday)}', PhosphorIconsRegular.calendarPlus, C.medium),
          ('pick', 'Выбрать дату…', PhosphorIconsRegular.calendarBlank, C.text2),
          ('none', 'Без даты', PhosphorIconsRegular.tray, C.muted),
        ])
          ListTile(
            leading: Icon(icon, color: color, size: 22),
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: value == 'none' && d.date == null
                ? Icon(PhosphorIconsBold.check, color: C.accent2, size: 18)
                : null,
            onTap: () => Navigator.pop(c, value),
          ),
      ]),
    );
    if (v == null || !context.mounted) return false;
    if (v is DateTime) {
      d.date = v;
      return true;
    }
    switch (v) {
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

  /// Длительность: быстрые варианты и барабан «часы : минуты» с шагом 5 минут.
  static Future<bool> duration(BuildContext context, TaskDraft d) async {
    var value = Duration(minutes: d.duration ?? 60);
    var preset = 0; // меняется только от чипов — тогда барабан встаёт на новое значение
    final result = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final minutes = value.inMinutes;
        final ends = d.timeStr == null || minutes == 0 ? null : endTime(d.timeStr!, minutes);
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Row(children: [
                const Text('Длительность', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(
                  minutes == 0 ? '—' : (ends == null ? fmtDuration(minutes) : '${fmtDuration(minutes)} · до $ends'),
                  style: TextStyle(color: C.accent2, fontWeight: FontWeight.w700),
                ),
              ]),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final m in [15, 30, 45, 60, 90, 120, 180, 240])
                    Padding(
                      padding: const EdgeInsets.only(right: 6, top: 6),
                      child: ChoiceChip(
                        label: Text(fmtDuration(m)),
                        selected: minutes == m,
                        showCheckmark: false,
                        selectedColor: C.accent,
                        onSelected: (_) => set(() {
                          value = Duration(minutes: m);
                          preset++;
                        }),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 190,
              child: CupertinoTheme(
                data: const CupertinoThemeData(
                  brightness: Brightness.dark,
                  textTheme: CupertinoTextThemeData(
                    pickerTextStyle: TextStyle(fontFamily: 'Manrope', fontSize: 21, color: C.text),
                  ),
                ),
                child: CupertinoTimerPicker(
                  key: ValueKey(preset),
                  mode: CupertinoTimerPickerMode.hm,
                  minuteInterval: 5,
                  initialTimerDuration: Duration(minutes: (minutes ~/ 5) * 5),
                  onTimerDurationChanged: (v) => set(() => value = v),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(c, 0),
                      child: const Text('Без длительности'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: C.accent),
                      onPressed: () => Navigator.pop(c, value.inMinutes),
                      child: const Text('Готово', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        );
      }),
    );
    if (result == null) return false;
    d.duration = result == 0 ? null : result;
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
    final v = await showProjectPicker(context, title: 'Проект', selectedId: d.projectId);
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
            ListTile(
              leading: Icon(PhosphorIconsRegular.plus, color: C.accent2),
              title: Text('Новый тег', style: TextStyle(color: C.accent2, fontWeight: FontWeight.w700)),
              onTap: () async {
                final t = await showTagEditor(c);
                if (t != null) set(() => selected.add(t.id));
              },
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
          trailing: value == current ? Icon(PhosphorIconsBold.check, color: C.accent2, size: 18) : null,
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


/// Семь квадратиков от сегодня: день недели и число. Текущий срок обведён.
class WeekDayPicker extends StatelessWidget {
  const WeekDayPicker({super.key, required this.current, required this.onPick});

  final DateTime? current;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final today = dayOnly(DateTime.now());
    final cur = current == null ? null : dayOnly(current!);
    return Row(children: [
      for (var i = 0; i < 7; i++)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _DaySquare(
              day: today.add(Duration(days: i)),
              isToday: i == 0,
              selected: cur == today.add(Duration(days: i)),
              onTap: () => onPick(today.add(Duration(days: i))),
            ),
          ),
        ),
    ]);
  }
}

class _DaySquare extends StatelessWidget {
  const _DaySquare({required this.day, required this.isToday, required this.selected, required this.onTap});

  final DateTime day;
  final bool isToday;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final weekend = day.weekday >= 6;
    return Material(
      color: selected ? C.accent.withValues(alpha: 0.16) : C.bg3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? C.accent2 : Colors.transparent, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
              isToday ? 'Сег' : fmtShortWeekday(day),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: isToday ? C.accent2 : (weekend ? C.logo.withValues(alpha: 0.95) : C.muted),
              ),
            ),
            const SizedBox(height: 3),
            Text('${day.day}',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: selected ? C.text : C.text,
                )),
          ]),
        ),
      ),
    );
  }
}
