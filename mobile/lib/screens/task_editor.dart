import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/task_draft.dart';
import '../widgets/task_tile.dart';

/// Задача на весь экран: название, заметка, чек-лист и поля списком.
///
/// Существующая задача сохраняется сама при выходе; новая — кнопкой «Создать».
class TaskEditorScreen extends StatefulWidget {
  const TaskEditorScreen({super.key, this.task, this.draft, this.onClose});

  final Task? task;
  final TaskDraft? draft;

  /// Встроен в правую панель десктопа: закрытие — через колбэк, а не Navigator.
  final VoidCallback? onClose;

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  late final TaskDraft d = widget.draft ?? TaskDraft.fromTask(widget.task);
  late final _title = TextEditingController(text: d.title);
  late final _desc = TextEditingController(text: d.description);
  final _newItem = TextEditingController();
  final _newItemFocus = FocusNode();
  bool _dirty = false;
  bool _saving = false;
  bool _deleted = false;

  bool get _isNew => widget.task == null;
  bool get _embedded => widget.onClose != null;
  late AppStore _store;
  bool _closed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _store = StoreScope.read(context);
  }

  void _close() {
    _closed = true;
    if (_embedded) {
      widget.onClose!();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _typing?.cancel();
    // В панели задачу могли сменить кликом по другой — сохраняем молча.
    if (_embedded && !_closed) _autosave(silent: true);
    _title.dispose();
    _desc.dispose();
    _newItem.dispose();
    _newItemFocus.dispose();
    super.dispose();
  }

  Timer? _typing;

  /// Название и заметку сохраняем, когда перестали печатать.
  void _typed() {
    _dirty = true;
    if (_isNew) return;
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 900), () => _autosave(silent: true));
  }

  void _sync() {
    if (d.title != _title.text || d.description != _desc.text) _dirty = true;
    d.title = _title.text;
    d.description = _desc.text;
  }

  Future<void> _pick(Future<bool> Function(BuildContext, TaskDraft) picker) async {
    _sync();
    if (await picker(context, d) && mounted) {
      setState(() => _dirty = true);
      // Изменение сразу уходит на сервер — список за панелью обновляется тут же.
      _autosave();
    }
  }

  /// Выход с экрана: существующую задачу молча сохраняем.
  Future<void> _autosave({bool silent = false}) async {
    _sync();
    if (_isNew || _deleted || !_dirty || d.title.trim().isEmpty) return;
    _dirty = false;
    final messenger = silent ? null : ScaffoldMessenger.of(context);
    try {
      await _store.updateTask(widget.task!.id, d.toBody(old: widget.task));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Не сохранилось: $e')));
    }
  }

  Future<void> _create() async {
    _sync();
    if (d.title.trim().isEmpty) {
      HapticFeedback.heavyImpact();
      return;
    }
    setState(() => _saving = true);
    final store = StoreScope.read(context);
    try {
      final t = await store.createTask(d.toBody());
      for (final text in d.newChecklist) {
        await store.addChecklistItem(t.id, text);
      }
      HapticFeedback.lightImpact();
      if (mounted) _close();
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
    _deleted = true;
    _close();
    await store.deleteTask(t);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Удалено: ${t.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
        action: SnackBarAction(label: 'Вернуть', onPressed: () => store.restoreTask(t)),
      ));
  }

  void _addItem() {
    final text = _newItem.text.trim();
    if (text.isEmpty) return;
    _newItem.clear();
    if (_isNew) {
      setState(() => d.newChecklist.add(text));
    } else {
      StoreScope.read(context).addChecklistItem(widget.task!.id, text);
    }
    _newItemFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final live = _isNew ? null : (store.taskById(widget.task!.id) ?? widget.task!);
    final project = store.projectById(d.projectId);
    final tagNames = d.tags.map((id) => store.tagById(id)?.name).whereType<String>().join(', ');

    final checklist = live?.checklist ?? const <ChecklistItem>[];
    final itemsDone = checklist.where((c) => c.isCompleted).length;
    final itemCount = _isNew ? d.newChecklist.length : checklist.length;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _autosave();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: () async {
              if (!_embedded) return Navigator.maybePop(context).then((_) {});
              await _autosave();
              _close();
            },
            icon: Icon(_isNew || _embedded ? PhosphorIconsRegular.x : PhosphorIconsRegular.caretLeft),
          ),
          title: Text(_isNew ? 'Новая задача' : '',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          actions: [
            if (_isNew)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: C.accent, visualDensity: VisualDensity.compact),
                  onPressed: _saving ? null : _create,
                  child: const Text('Создать', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              )
            else
              PopupMenuButton<String>(
                icon: const Icon(PhosphorIconsRegular.dotsThreeVertical),
                onSelected: (v) {
                  if (v == 'delete') _delete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(PhosphorIconsRegular.trash, color: C.urgent, size: 20),
                      SizedBox(width: 12),
                      Text('Удалить', style: TextStyle(color: C.urgent)),
                    ]),
                  ),
                ],
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 20, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (live != null)
                  Padding(padding: const EdgeInsets.only(top: 4), child: CheckCircle(task: live, size: 24))
                else
                  const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _title,
                    autofocus: _isNew && d.title.isEmpty,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => _typed(),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                      color: live?.isCompleted == true ? C.text2 : C.text,
                    ),
                    decoration: _bare('Что нужно сделать?'),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(live != null ? 52 : 20, 0, 20, 4),
              child: TextField(
                controller: _desc,
                minLines: 1,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => _typed(),
                style: const TextStyle(fontSize: 15, color: C.text2, height: 1.45),
                decoration: _bare('Заметка'),
              ),
            ),

            // ---- чек-лист ----
            SectionHeader(
              'Чек-лист',
              count: itemCount == 0 ? null : itemCount,
              trailing: !_isNew && itemCount > 0
                  ? Text('$itemsDone из $itemCount',
                      style: const TextStyle(color: C.muted, fontWeight: FontWeight.w700, fontSize: 13))
                  : null,
            ),
            Group(children: [
              if (_isNew)
                for (var i = 0; i < d.newChecklist.length; i++)
                  _ItemRow(
                    key: ValueKey('new-$i-${d.newChecklist[i]}'),
                    text: d.newChecklist[i],
                    done: false,
                    onToggle: null,
                    onRename: (v) => setState(() => d.newChecklist[i] = v),
                    onDelete: () => setState(() => d.newChecklist.removeAt(i)),
                  )
              else
                for (final c in checklist)
                  _ItemRow(
                    key: ValueKey('item-${c.id}'),
                    text: c.text,
                    done: c.isCompleted,
                    onRename: (v) => store.renameChecklistItem(live!, c, v),
                    onToggle: () {
                      HapticFeedback.selectionClick();
                      store.toggleChecklistItem(live!, c);
                    },
                    onDelete: () => store.deleteChecklistItem(live!, c),
                  ),
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: Row(children: [
                  const Icon(PhosphorIconsRegular.plus, size: 18, color: C.muted),
                  const SizedBox(width: 18),
                  Expanded(
                    child: TextField(
                      controller: _newItem,
                      focusNode: _newItemFocus,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _addItem(),
                      decoration: _bare('Добавить пункт').copyWith(
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),

            // ---- поля ----
            const SectionHeader('Детали'),
            Group(children: [
              _Field(
                icon: PhosphorIconsRegular.calendarBlank,
                label: 'Дата',
                value: d.dateLabel(),
                valueColor: d.date != null && d.date!.isBefore(dayOnly(DateTime.now())) ? C.urgent : null,
                onTap: () => _pick(Pick.day),
              ),
              _Field(
                icon: PhosphorIconsRegular.clock,
                label: 'Время',
                value: d.timeStr,
                onTap: () => _pick(Pick.time),
                onClear: d.time == null
                    ? null
                    : () => setState(() {
                          d.time = null;
                          _dirty = true;
                          _autosave();
                        }),
              ),
              _Field(
                icon: PhosphorIconsRegular.timer,
                label: 'Длительность',
                value: d.duration == null ? null : fmtDuration(d.duration!),
                onTap: () => _pick(Pick.duration),
              ),
              _Field(
                icon: PhosphorIconsRegular.repeat,
                label: 'Повтор',
                value: d.repeat.isEmpty ? null : repeatLabels[d.repeat],
                onTap: () => _pick(Pick.repeat),
              ),
              _Field(
                icon: PhosphorIconsRegular.bellSimple,
                label: 'Напомнить',
                value: d.reminder == null ? null : d.reminderLabel(),
                onTap: () => _pick(Pick.reminder),
              ),
            ]),
            const SizedBox(height: 14),
            Group(children: [
              _Field(
                icon: PhosphorIconsRegular.folderSimple,
                label: 'Проект',
                value: project?.name,
                trailingLead: project == null ? null : ProjectAvatar(project: project, size: 22),
                onTap: () => _pick(Pick.project),
              ),
              _Field(
                icon: PhosphorIconsRegular.flag,
                label: 'Приоритет',
                value: priorityLabels[d.priority],
                valueColor: d.priority == 2 ? null : C.priority(d.priority),
                onTap: () => _pick(Pick.priority),
              ),
              _Field(
                icon: PhosphorIconsRegular.hash,
                label: 'Теги',
                value: tagNames.isEmpty ? null : tagNames,
                onTap: () => _pick(Pick.tags),
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.only(left: 16, right: 10),
                secondary: const Icon(PhosphorIconsRegular.moonStars, size: 21, color: C.text2),
                title: const Text('Закрыть, когда день пройдёт',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                value: d.autoComplete,
                activeTrackColor: C.accent,
                onChanged: (v) => setState(() {
                  d.autoComplete = v;
                  if (v) d.autoDelete = false;
                  _dirty = true;
                  _autosave();
                }),
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.only(left: 16, right: 10),
                secondary: const Icon(PhosphorIconsRegular.trashSimple, size: 21, color: C.text2),
                title: const Text('Удалить, когда день пройдёт',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                subtitle: const Text('Одноразовая: на следующий день её не будет',
                    style: TextStyle(fontSize: 12, color: C.muted)),
                value: d.autoDelete,
                activeTrackColor: C.urgent,
                onChanged: (v) => setState(() {
                  d.autoDelete = v;
                  if (v) d.autoComplete = false;
                  _dirty = true;
                  _autosave();
                }),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

InputDecoration _bare(String hint) => InputDecoration(
      hintText: hint,
      filled: false,
      isDense: true,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
    );

/// Строка поля: иконка, название, значение справа.
class _Field extends StatelessWidget {
  const _Field({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.valueColor,
    this.trailingLead,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final String? value;
  final Color? valueColor;
  final Widget? trailingLead;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onClear,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(children: [
          Icon(icon, size: 21, color: C.text2),
          const SizedBox(width: 18),
          Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (trailingLead != null) ...[trailingLead!, const SizedBox(width: 8)],
              Flexible(
                child: Text(
                  value ?? 'Нет',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: value == null ? C.muted : (valueColor ?? C.text2),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 6),
          const Icon(PhosphorIconsBold.caretRight, size: 13, color: C.muted),
        ]),
      ),
    );
  }
}

class _ItemRow extends StatefulWidget {
  const _ItemRow({
    super.key,
    required this.text,
    required this.done,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
  });

  final String text;
  final bool done;
  final VoidCallback? onToggle;
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

/// Пункт чек-листа: квадрат — отметить, текст — сразу редактируется.
class _ItemRowState extends State<_ItemRow> {
  late final _text = TextEditingController(text: widget.text);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_ItemRow old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.text != _text.text) _text.text = widget.text;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final v = _text.text.trim();
    if (v.isEmpty) {
      _text.text = widget.text;
    } else if (v != widget.text) {
      widget.onRename(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = widget.done;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: Row(children: [
        InkResponse(
          radius: 22,
          onTap: widget.onToggle,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: done ? C.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: done ? C.accent : C.muted, width: 1.6),
              ),
              child: done ? Icon(PhosphorIconsBold.check, size: 13, color: C.onAccent) : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _text,
            focusNode: _focus,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _focus.unfocus(),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: done ? C.muted : C.text,
              decoration: done ? TextDecoration.lineThrough : null,
              decorationColor: C.muted,
            ),
            decoration: _bare('').copyWith(contentPadding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: widget.onDelete,
          icon: const Icon(PhosphorIconsRegular.x, size: 16, color: C.muted),
        ),
      ]),
    );
  }
}
