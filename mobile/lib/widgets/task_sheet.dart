import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';

/// Создание и редактирование задачи в шторке снизу.
Future<void> showTaskSheet(
  BuildContext context, {
  Task? task,
  DateTime? day,
  int? projectId,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => TaskSheet(task: task, day: day, projectId: projectId),
  );
}

class TaskSheet extends StatefulWidget {
  const TaskSheet({super.key, this.task, this.day, this.projectId});

  final Task? task;
  final DateTime? day;
  final int? projectId;

  @override
  State<TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<TaskSheet> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late DateTime? _date;
  late TimeOfDay? _time;
  late int? _duration;
  late int _priority;
  late int? _projectId;
  late String _repeat;
  late Set<int> _tags;
  late bool _autoComplete;
  late DateTime? _reminder;
  bool _showDesc = false;
  bool _saving = false;

  bool get _isNew => widget.task == null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _title = TextEditingController(text: t?.title ?? '');
    _desc = TextEditingController(text: t?.description ?? '');
    _showDesc = (t?.description ?? '').isNotEmpty;
    _date = t != null ? t.dueDate : (widget.day ?? (widget.projectId == null ? dayOnly(DateTime.now()) : null));
    final m = t?.startMinute;
    _time = m == null ? null : TimeOfDay(hour: m ~/ 60, minute: m % 60);
    _duration = t?.durationMinutes;
    _priority = t?.priority ?? 2;
    _projectId = t?.projectId ?? widget.projectId;
    _repeat = t?.repeat ?? '';
    _tags = {...?t?.tagIds};
    _autoComplete = t?.autoComplete ?? false;
    _reminder = t?.reminderAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  String? get _timeStr => _time == null
      ? null
      : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      HapticFeedback.heavyImpact();
      return;
    }
    setState(() => _saving = true);
    final store = StoreScope.read(context);
    final body = <String, dynamic>{
      'title': title,
      'description': _desc.text.trim(),
      'priority': _priority,
      'project_id': _projectId,
      'due_date': _date == null ? '' : ymd(_date!),
      'due_time': _date == null ? '' : (_timeStr ?? ''),
      'duration_minutes': _duration,
      'auto_complete': _autoComplete,
      'reminder': _reminder == null
          ? ''
          : '${ymd(_reminder!)} ${_reminder!.hour.toString().padLeft(2, '0')}:${_reminder!.minute.toString().padLeft(2, '0')}',
      'tag_ids': _tags.toList(),
    };
    if (_isNew || _repeat != widget.task!.repeat) body['repeat'] = _repeat;
    try {
      if (_isNew) {
        if (body['due_date'] == '') body.remove('due_date');
        if (body['due_time'] == '') body.remove('due_time');
        if (body['reminder'] == '') body.remove('reminder');
        await store.createTask(body);
      } else {
        await store.updateTask(widget.task!.id, body);
      }
      HapticFeedback.lightImpact();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  Future<void> _delete() async {
    final t = widget.task!;
    final store = StoreScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    await store.deleteTask(t);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Удалено: ${t.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
        action: SnackBarAction(label: 'Вернуть', onPressed: () => store.restoreTask(t)),
      ));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
      locale: const Locale('ru'),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay(hour: (TimeOfDay.now().hour + 1) % 24, minute: 0),
      builder: (c, child) =>
          MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t != null) {
      setState(() {
        _time = t;
        _date ??= dayOnly(DateTime.now());
      });
    }
  }

  Future<void> _pickReminder() async {
    final base = _reminder ??
        (_date != null && _time != null
            ? _date!.add(Duration(hours: _time!.hour, minutes: _time!.minute - 30))
            : DateTime.now().add(const Duration(hours: 1)));
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      helpText: 'День напоминания',
      locale: const Locale('ru'),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      helpText: 'Время напоминания',
      builder: (c, child) =>
          MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t != null) setState(() => _reminder = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _pickDuration() async {
    final v = await _choose<int>(
      'Длительность',
      [
        for (final m in [15, 30, 45, 60, 90, 120, 180, 240]) (m, fmtDuration(m), PhosphorIconsRegular.timer, null),
        (0, 'Без длительности', PhosphorIconsRegular.prohibit, null),
      ],
      _duration ?? 0,
    );
    if (v != null) setState(() => _duration = v == 0 ? null : v);
  }

  Future<void> _pickPriority() async {
    final v = await _choose<int>(
      'Приоритет',
      [for (final p in [4, 3, 2, 1]) (p, priorityLabels[p]!, PhosphorIconsFill.flag, C.priority(p))],
      _priority,
    );
    if (v != null) setState(() => _priority = v);
  }

  Future<void> _pickRepeat() async {
    final v = await _choose<String>(
      'Повтор',
      [for (final e in repeatLabels.entries) (e.key, e.value, PhosphorIconsRegular.repeat, null)],
      _repeat,
    );
    if (v != null) {
      setState(() {
        _repeat = v;
        if (v.isNotEmpty) _date ??= dayOnly(DateTime.now());
      });
    }
  }

  Future<void> _pickProject() async {
    final store = StoreScope.read(context);
    Widget row(BuildContext c, Project? p, {bool nested = false}) => ListTile(
          contentPadding: EdgeInsets.only(left: nested ? 44 : 20, right: 20),
          leading: ProjectAvatar(project: p, size: nested ? 28 : 34),
          title: Text(p?.name ?? 'Без проекта', style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: (p?.id ?? 0) == (_projectId ?? 0)
              ? const Icon(PhosphorIconsBold.check, color: C.accent2, size: 18)
              : null,
          onTap: () => Navigator.pop(c, p?.id ?? 0),
        );
    final v = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.75),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const _SheetTitle('Проект'),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                row(c, null),
                for (final p in store.rootProjects) ...[
                  row(c, p),
                  for (final ch in store.childrenOf(p.id)) row(c, ch, nested: true),
                ],
              ]),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
    if (v != null) setState(() => _projectId = v == 0 ? null : v);
  }

  Future<void> _pickTags() async {
    final store = StoreScope.read(context);
    final selected = {..._tags};
    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const _SheetTitle('Теги'),
            if (store.tags.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Тегов пока нет', style: TextStyle(color: C.text2)),
              ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final t in store.tags)
                  CheckboxListTile(
                    value: selected.contains(t.id),
                    activeColor: t.tint,
                    title: Text(t.name),
                    secondary: Icon(PhosphorIconsRegular.hash, color: t.tint),
                    onChanged: (on) => set(() => on! ? selected.add(t.id) : selected.remove(t.id)),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(c, selected),
                  child: const Text('Готово'),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
    if (result != null) setState(() => _tags = result);
  }

  Future<T?> _choose<T>(String title, List<(T, String, IconData, Color?)> options, T current) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _SheetTitle(title),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final (value, label, icon, color) in options)
                  ListTile(
                    leading: Icon(icon, color: color ?? C.accent2),
                    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: value == current ? const Icon(PhosphorIconsBold.check, color: C.accent2) : null,
                    onTap: () => Navigator.pop(c, value),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final project = store.projectById(_projectId);
    final today = dayOnly(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(_isNew ? 'Новая задача' : 'Задача',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.text2, letterSpacing: 1)),
            const Spacer(),
            if (!_isNew) ...[
              _DoneToggle(task: store.taskById(widget.task!.id) ?? widget.task!),
              IconButton(
                tooltip: 'Удалить',
                onPressed: _delete,
                icon: const Icon(PhosphorIconsRegular.trash, color: C.urgent),
              ),
            ],
          ]),
          TextField(
            controller: _title,
            autofocus: _isNew,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.25),
            decoration: const InputDecoration(
              hintText: 'Что нужно сделать?',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _showDesc
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _desc,
                      maxLines: 6,
                      minLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(hintText: 'Описание, заметки, ссылки…'),
                    ),
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _showDesc = true),
                      icon: const Icon(PhosphorIconsRegular.textAlignLeft, size: 18),
                      label: const Text('Описание'),
                    ),
                  ),
          ),
          // Быстрый выбор дня
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _DayChip('Сегодня', PhosphorIconsFill.sun, _date == today, () => setState(() => _date = today)),
              _DayChip('Завтра', PhosphorIconsRegular.sunHorizon, _date == tomorrow, () => setState(() => _date = tomorrow)),
              _DayChip(
                _date != null && _date != today && _date != tomorrow ? fmtRelDay(_date!) : 'Дата',
                PhosphorIconsRegular.calendarBlank,
                _date != null && _date != today && _date != tomorrow,
                _pickDate,
              ),
              _DayChip('Без даты', PhosphorIconsRegular.tray, _date == null, () => setState(() {
                    _date = null;
                    _time = null;
                    _repeat = '';
                  })),
            ]),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _OptChip(
              icon: PhosphorIconsRegular.clock,
              label: _timeStr ?? 'Время',
              active: _time != null,
              onTap: _pickTime,
              onClear: _time == null ? null : () => setState(() => _time = null),
            ),
            _OptChip(
              icon: PhosphorIconsRegular.timer,
              label: _duration == null ? 'Длительность' : fmtDuration(_duration!),
              active: _duration != null,
              onTap: _pickDuration,
            ),
            _OptChip(
              icon: PhosphorIconsFill.flag,
              label: priorityLabels[_priority]!,
              active: _priority != 2,
              color: C.priority(_priority),
              onTap: _pickPriority,
            ),
            _OptChip(
              icon: PhosphorIconsRegular.folderSimple,
              leading: project == null ? null : ProjectAvatar(project: project, size: 18),
              label: project?.name ?? 'Проект',
              active: project != null,
              color: project?.tint,
              onTap: _pickProject,
            ),
            _OptChip(
              icon: PhosphorIconsRegular.repeat,
              label: _repeat.isEmpty ? 'Повтор' : repeatLabels[_repeat]!,
              active: _repeat.isNotEmpty,
              onTap: _pickRepeat,
            ),
            _OptChip(
              icon: PhosphorIconsRegular.bellSimple,
              label: _reminder == null
                  ? 'Напомнить'
                  : '${fmtRelDay(_reminder!)}, ${_reminder!.hour.toString().padLeft(2, '0')}:${_reminder!.minute.toString().padLeft(2, '0')}',
              active: _reminder != null,
              onTap: _pickReminder,
              onClear: _reminder == null ? null : () => setState(() => _reminder = null),
            ),
            _OptChip(
              icon: PhosphorIconsRegular.hash,
              label: _tags.isEmpty
                  ? 'Теги'
                  : _tags.map((id) => store.tagById(id)?.name).whereType<String>().join(', '),
              active: _tags.isNotEmpty,
              onTap: _pickTags,
            ),
            _OptChip(
              icon: PhosphorIconsRegular.moonStars,
              label: 'Закрыть, когда день пройдёт',
              active: _autoComplete,
              onTap: () => setState(() => _autoComplete = !_autoComplete),
            ),
          ]),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: C.accent,
              ),
              child: TextButton(
                onPressed: _saving ? null : _save,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Text(_isNew ? 'Создать' : 'Сохранить',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _DoneToggle extends StatelessWidget {
  const _DoneToggle({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final done = task.isCompleted;
    return TextButton.icon(
      onPressed: () {
        HapticFeedback.lightImpact();
        StoreScope.read(context).toggle(task);
      },
      icon: Icon(done ? PhosphorIconsFill.checkCircle : PhosphorIconsRegular.circle,
          color: done ? C.low : C.text2, size: 20),
      label: Text(done ? 'Выполнено' : 'Не выполнено',
          style: TextStyle(color: done ? C.low : C.text2, fontWeight: FontWeight.w700)),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
      );
}

class _DayChip extends StatelessWidget {
  const _DayChip(this.label, this.icon, this.selected, this.onTap);

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? C.accent : C.bg3,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? C.accent : C.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Icon(icon, size: 17, color: selected ? Colors.white : C.text2),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : C.text,
                  )),
            ]),
          ),
        ),
      ),
    );
  }
}

class _OptChip extends StatelessWidget {
  const _OptChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.color,
    this.onClear,
    this.leading,
  });

  final Widget? leading;
  final IconData icon;
  final String label;
  final bool active;
  final Color? color;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = color ?? C.accent2;
    return Material(
      color: active ? c.withValues(alpha: 0.14) : C.bg3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: active ? c.withValues(alpha: 0.5) : C.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 8, onClear == null ? 12 : 4, 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            leading ?? Icon(icon, size: 16, color: active ? c : C.text2),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: active ? C.text : C.text2,
                  )),
            ),
            if (onClear != null)
              InkResponse(
                radius: 14,
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(PhosphorIconsRegular.x, size: 16, color: C.text2),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
