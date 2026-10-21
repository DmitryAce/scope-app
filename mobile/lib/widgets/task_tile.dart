import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'task_actions.dart';
import 'task_sheet.dart';

/// Строка задачи внутри [Group]. Свайп вправо — выполнить, влево — на завтра.
///
/// [timeColumn] — время слева колонкой (лента дня); тогда в мете его не дублируем.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    this.showDate = false,
    this.showProject = true,
    this.timeColumn = false,
    this.dim = false,
  });

  final Task task;
  final bool showDate;
  final bool showProject;
  final bool timeColumn;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final project = store.projectById(task.projectId);
    final done = task.isCompleted;
    final metaColor = done ? C.muted : C.text2;
    TextStyle metaStyle(Color c) => TextStyle(fontSize: 12.5, color: c, fontWeight: FontWeight.w600);

    // Мета — строго в одну строку: длинное (проект, тег) обрезается.
    final parts = <Widget>[];
    if (task.isExternal && task.externalCode.isNotEmpty) {
      // Код задачи ERP — сразу видно, откуда она и как её найти там.
      final color = Color(erpSources[task.externalSource]?.$2 ?? 0xFF9090A0);
      parts.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: done ? 0.08 : 0.16),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(task.externalCode,
            maxLines: 1,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: done ? C.muted : color)),
      ));
    }
    if (showDate && task.dueDate != null) {
      parts.add(Text(fmtShortDay(task.dueDate!), style: metaStyle(task.isOverdue ? C.urgent : metaColor)));
    }
    if (!timeColumn && task.dueTime != null) {
      parts.add(Text(
        task.durationMinutes != null
            ? '${task.dueTime}–${endTime(task.dueTime!, task.durationMinutes!)}'
            : task.dueTime!,
        style: metaStyle(metaColor),
      ));
    } else if (!timeColumn && task.durationMinutes != null) {
      parts.add(Text(fmtDuration(task.durationMinutes!), style: metaStyle(metaColor)));
    }
    if (showProject && project != null) {
      parts.add(Flexible(
        child: Text(project.name,
            maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: metaStyle(metaColor)),
      ));
    }
    // Все теги в одну строку, каждый своим цветом; что не влезло — обрезается «…».
    final tags = task.tagIds.map(store.tagById).whereType<Tag>().toList();
    if (tags.isNotEmpty) {
      parts.add(Flexible(
        flex: 2,
        child: Text.rich(
          TextSpan(children: [
            for (final (i, t) in tags.indexed)
              TextSpan(text: '${i == 0 ? '' : '  '}#${t.name}', style: metaStyle(done ? C.muted : t.tint)),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ));
    }
    if (task.checklist.isNotEmpty) {
      final doneItems = task.checklist.where((c) => c.isCompleted).length;
      final all = doneItems == task.checklist.length;
      parts.insert(
        0,
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(PhosphorIconsBold.listChecks, size: 13, color: all ? C.low : C.muted),
          const SizedBox(width: 3),
          Text('$doneItems/${task.checklist.length}', style: metaStyle(all ? C.low : metaColor)),
        ]),
      );
    }
    final flags = <IconData>[
      if (task.repeat.isNotEmpty) PhosphorIconsBold.repeat,
      if (task.reminder != null) PhosphorIconsBold.bellSimple,
    ];

    final metaChildren = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) metaChildren.add(const _Dot());
      metaChildren.add(parts[i]);
    }
    for (final f in flags) {
      metaChildren
        ..add(SizedBox(width: metaChildren.isEmpty ? 0 : 8))
        ..add(Icon(f, size: 12, color: C.muted));
    }

    final now = TimeOfDay.now();
    final nowMin = now.hour * 60 + now.minute;
    final start = task.startMinute;
    final running = timeColumn &&
        !done &&
        start != null &&
        task.dueDate == dayOnly(DateTime.now()) &&
        nowMin >= start &&
        nowMin < start + (task.durationMinutes ?? 0);

    final row = InkWell(
      onTap: () => showTaskSheet(context, task: task),
      onLongPress: () => showTaskActions(context, task),
      child: Opacity(
        opacity: dim ? 0.55 : 1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 5, 14, 5),
          child: Row(children: [
            if (timeColumn)
              SizedBox(
                width: 52,
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(task.dueTime ?? '',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: running ? C.accent2 : (done ? C.muted : C.text),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        )),
                    if (task.durationMinutes != null && task.dueTime != null)
                      Text(endTime(task.dueTime!, task.durationMinutes!),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: C.muted,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          )),
                  ]),
                ),
              ),
            CheckCircle(task: task),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 15,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: done ? C.muted : C.text,
                      decoration: done ? TextDecoration.lineThrough : null,
                      decorationColor: C.muted,
                    ),
                    child: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                  if (metaChildren.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(children: metaChildren),
                  ],
                ]),
              ),
            ),
            if (showProject && project != null) ...[
              const SizedBox(width: 10),
              Opacity(opacity: done ? 0.45 : 1, child: ProjectAvatar(project: project, size: 28)),
            ],
          ]),
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('task-${task.id}-${task.isCompleted}-${task.dueDate}'),
      background: _SwipeBg(
        color: done ? C.muted : C.low,
        icon: done ? PhosphorIconsBold.arrowCounterClockwise : PhosphorIconsBold.check,
        label: done ? 'Вернуть' : 'Готово',
        alignLeft: true,
      ),
      secondaryBackground: const _SwipeBg(
        color: C.medium,
        icon: PhosphorIconsBold.arrowRight,
        label: 'На завтра',
        alignLeft: false,
      ),
      confirmDismiss: (dir) async {
        HapticFeedback.mediumImpact();
        final store = StoreScope.read(context);
        if (dir == DismissDirection.startToEnd) {
          completeWithUndo(context, task);
        } else {
          final base = task.dueDate != null && !task.isOverdue ? task.dueDate! : DateTime.now();
          final target = dayOnly(base).add(const Duration(days: 1));
          store.moveTo(task, target);
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text('Перенесено: ${fmtRelDay(target).toLowerCase()}'),
              action: SnackBarAction(label: 'Отменить', onPressed: () => store.moveTo(task, task.dueDate)),
            ));
        }
        return false;
      },
      child: row,
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Text('·', style: TextStyle(color: C.muted, fontWeight: FontWeight.w800)),
      );
}

void completeWithUndo(BuildContext context, Task task) {
  final store = StoreScope.read(context);
  store.toggle(task);
  if (!task.isCompleted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 3),
        content: Text('Готово: ${task.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () {
            final now = store.taskById(task.id);
            if (now != null && now.isCompleted) store.toggle(now);
          },
        ),
      ));
  }
}

class _SwipeBg extends StatelessWidget {
  const _SwipeBg({required this.color, required this.icon, required this.label, required this.alignLeft});

  final Color color;
  final IconData icon;
  final String label;
  final bool alignLeft;

  @override
  Widget build(BuildContext context) {
    final children = [
      Icon(icon, color: Colors.white, size: 20),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    ];
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignLeft ? children : children.reversed.toList(),
      ),
    );
  }
}

/// Круглый чекбокс: важные задачи — цветной обводкой, обычные — нейтральной.
class CheckCircle extends StatelessWidget {
  const CheckCircle({super.key, required this.task, this.size = 22});

  final Task task;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ring = task.priority >= 3 ? C.priority(task.priority) : C.muted;
    final done = task.isCompleted;
    return InkResponse(
      radius: 22,
      onTap: () {
        HapticFeedback.lightImpact();
        completeWithUndo(context, task);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? C.accent : Colors.transparent,
            border: Border.all(color: done ? C.accent : ring, width: 1.8),
          ),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 200),
            scale: done ? 1 : 0,
            curve: Curves.easeOutBack,
            child: Icon(PhosphorIconsBold.check, size: size * 0.6, color: C.onAccent),
          ),
        ),
      ),
    );
  }
}
