import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models.dart';
import '../screens/task_editor.dart';
import '../theme.dart';
import 'common.dart';
import 'task_draft.dart';

/// Открыть задачу: существующую — на полном экране, новую — в быстрой шторке.
Future<void> showTaskSheet(
  BuildContext context, {
  Task? task,
  DateTime? day,
  int? projectId,
}) {
  if (task != null) {
    return Navigator.push(context, MaterialPageRoute(builder: (_) => TaskEditorScreen(task: task)));
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (_) => QuickAddSheet(draft: TaskDraft.fromTask(null, day: day, projectId: projectId)),
  );
}

/// Быстрое добавление: название, заметка и одна строка значков.
class QuickAddSheet extends StatefulWidget {
  const QuickAddSheet({super.key, required this.draft});

  final TaskDraft draft;

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  late final _title = TextEditingController(text: widget.draft.title);
  late final _desc = TextEditingController(text: widget.draft.description);
  bool _saving = false;

  TaskDraft get d => widget.draft;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _sync() {
    d.title = _title.text;
    d.description = _desc.text;
  }

  Future<void> _pick(Future<bool> Function(BuildContext, TaskDraft) picker) async {
    _sync();
    if (await picker(context, d) && mounted) setState(() {});
  }

  Future<void> _save() async {
    _sync();
    if (d.title.trim().isEmpty) {
      HapticFeedback.heavyImpact();
      return;
    }
    setState(() => _saving = true);
    try {
      await StoreScope.read(context).createTask(d.toBody());
      HapticFeedback.lightImpact();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  void _expand() {
    _sync();
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => TaskEditorScreen(draft: d)));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final project = store.projectById(d.projectId);
    final pColor = C.priority(d.priority);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 8, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TextField(
                controller: _title,
                autofocus: true,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.3),
                decoration: _bare('Что нужно сделать?'),
              ),
            ),
            IconButton(
              tooltip: 'Подробнее',
              onPressed: _expand,
              icon: const Icon(PhosphorIconsRegular.arrowsOutSimple, size: 20, color: C.text2),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _desc,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 14, color: C.text2),
            decoration: _bare('Заметка'),
          ),
        ),
        const SizedBox(height: 10),
        const Divider(height: 1, thickness: 0.6, color: C.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _Token(
                    icon: d.date == null ? PhosphorIconsRegular.tray : PhosphorIconsRegular.calendarBlank,
                    label: d.dateLabel(),
                    color: d.date == null
                        ? null
                        : d.date!.isBefore(dayOnly(DateTime.now()))
                            ? C.urgent
                            : C.low,
                    onTap: () => _pick(Pick.day),
                  ),
                  _Token(
                    icon: PhosphorIconsRegular.clock,
                    label: d.timeStr,
                    onTap: () => _pick(Pick.time),
                    onClear: d.time == null ? null : () => setState(() => d.time = null),
                  ),
                  _Token(
                    icon: PhosphorIconsRegular.folderSimple,
                    leading: project == null ? null : ProjectAvatar(project: project, size: 18),
                    label: project?.name,
                    onTap: () => _pick(Pick.project),
                  ),
                  _Token(
                    icon: d.priority >= 3 ? PhosphorIconsFill.flag : PhosphorIconsRegular.flag,
                    label: d.priority == 2 ? null : priorityLabels[d.priority],
                    color: d.priority == 2 ? null : pColor,
                    onTap: () => _pick(Pick.priority),
                  ),
                  _Token(
                    icon: PhosphorIconsRegular.bellSimple,
                    label: d.reminder == null ? null : d.reminderLabel(),
                    onTap: () => _pick(Pick.reminder),
                  ),
                  _Token(
                    icon: PhosphorIconsRegular.repeat,
                    label: d.repeat.isEmpty ? null : repeatLabels[d.repeat],
                    onTap: () => _pick(Pick.repeat),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: C.accent),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.onAccent))
                    : Icon(PhosphorIconsBold.arrowUp, size: 20, color: C.onAccent),
              ),
            ),
          ]),
        ),
      ]),
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
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
    );

/// Значок-параметр: пустой — только иконка, заданный — иконка с подписью.
class _Token extends StatelessWidget {
  const _Token({required this.icon, required this.onTap, this.label, this.color, this.leading, this.onClear});

  final IconData icon;
  final String? label;
  final Color? color;
  final Widget? leading;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final set = label != null;
    final c = color ?? (set ? C.text : C.text2);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: set ? C.bg3 : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          onLongPress: onClear,
          child: Container(
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: set ? 10 : 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              leading ?? Icon(icon, size: 19, color: c),
              if (set) ...[
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
