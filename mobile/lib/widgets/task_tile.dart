import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'task_sheet.dart';

/// Карточка задачи. Свайп вправо — выполнить, влево — перенести на завтра.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    this.showDate = false,
    this.showProject = true,
  });

  final Task task;
  final bool showDate;
  final bool showProject;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final project = showProject ? store.projectById(task.projectId) : null;
    final tint = store.projectById(task.projectId)?.tint;
    final done = task.isCompleted;

    final meta = <Widget>[];
    void add(IconData icon, String text, [Color color = C.text2]) {
      meta.add(Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        if (text.isNotEmpty) ...[
          const SizedBox(width: 3),
          Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ]));
    }

    if (showDate && task.dueDate != null) {
      add(Icons.event_rounded, fmtRelDay(task.dueDate!), task.isOverdue ? C.urgent : C.text2);
    }
    if (task.dueTime != null) {
      add(
        Icons.schedule_rounded,
        task.durationMinutes != null
            ? '${task.dueTime}–${endTime(task.dueTime!, task.durationMinutes!)}'
            : task.dueTime!,
      );
    } else if (task.durationMinutes != null) {
      add(Icons.timelapse_rounded, fmtDuration(task.durationMinutes!));
    }
    if (project != null) {
      meta.add(Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: project.tint, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(project.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: C.text2, fontWeight: FontWeight.w600)),
        ),
      ]));
    }
    if (task.repeat.isNotEmpty) add(Icons.repeat_rounded, '');
    if (task.reminder != null) add(Icons.notifications_active_outlined, '');
    if (task.description.trim().isNotEmpty) add(Icons.notes_rounded, '');
    for (final id in task.tagIds) {
      final tag = store.tagById(id);
      if (tag != null) add(Icons.tag_rounded, tag.name, tag.tint);
    }

    final card = Material(
      color: C.bg2,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showTaskSheet(context, task: task),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.borderLight),
          ),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 4, color: (tint ?? C.border).withValues(alpha: done ? 0.3 : 1)),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 0, 6),
                child: Center(child: CheckCircle(task: task)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
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
                        child: Text(task.title, maxLines: 3, overflow: TextOverflow.ellipsis),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Opacity(
                          opacity: done ? 0.5 : 1,
                          child: Wrap(spacing: 10, runSpacing: 4, children: meta),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Dismissible(
        key: ValueKey('task-${task.id}-${task.isCompleted}-${task.dueDate}'),
        background: _SwipeBg(
          color: done ? C.text2 : C.low,
          icon: done ? Icons.undo_rounded : Icons.check_rounded,
          label: done ? 'Вернуть' : 'Готово',
          alignLeft: true,
        ),
        secondaryBackground: const _SwipeBg(
          color: C.accent,
          icon: Icons.east_rounded,
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
        child: card,
      ),
    );
  }
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
      Icon(icon, color: Colors.white),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    ];
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
          end: alignLeft ? Alignment.centerRight : Alignment.centerLeft,
          colors: [color, color.withValues(alpha: 0.25)],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignLeft ? children : children.reversed.toList(),
      ),
    );
  }
}

/// Круглый чекбокс в цвет приоритета, с анимацией галочки.
class CheckCircle extends StatelessWidget {
  const CheckCircle({super.key, required this.task, this.size = 26});

  final Task task;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = C.priority(task.priority);
    final done = task.isCompleted;
    return InkResponse(
      radius: 24,
      onTap: () {
        HapticFeedback.lightImpact();
        completeWithUndo(context, task);
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? color : color.withValues(alpha: 0.08),
            border: Border.all(color: done ? color : color.withValues(alpha: 0.85), width: 2),
          ),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 220),
            scale: done ? 1 : 0,
            curve: Curves.easeOutBack,
            child: Icon(Icons.check_rounded, size: size * 0.66, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
