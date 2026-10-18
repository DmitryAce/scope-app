import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'task_draft.dart';
import 'task_sheet.dart';
import 'task_tile.dart';

/// Быстрые действия по долгому нажатию на задачу.
Future<void> showTaskActions(BuildContext context, Task task) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TaskActions(task: task, host: context),
  );
}

class _TaskActions extends StatelessWidget {
  const _TaskActions({required this.task, required this.host});

  final Task task;

  /// Контекст экрана под шторкой: снекбары и следующие окна открываем от него.
  final BuildContext host;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = store.taskById(task.id) ?? task;
    final project = store.projectById(t.projectId);
    final today = dayOnly(DateTime.now());

    void close() => Navigator.pop(context);

    Future<void> moveTo(DateTime? day) async {
      close();
      await store.moveTo(t, day);
      if (host.mounted) {
        ScaffoldMessenger.of(host)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(day == null ? 'Без даты' : 'Перенесено: ${fmtRelDay(day).toLowerCase()}'),
            action: SnackBarAction(label: 'Отменить', onPressed: () => store.moveTo(t, t.dueDate)),
          ));
      }
    }

    Future<void> pickDate() async {
      close();
      final d = await showDatePicker(
        context: host,
        initialDate: t.dueDate ?? today,
        firstDate: DateTime(today.year - 2),
        lastDate: DateTime(today.year + 5),
        locale: const Locale('ru'),
      );
      if (d != null) await store.moveTo(t, d);
    }

    Future<void> editField(Future<bool> Function(BuildContext, TaskDraft) picker, List<String> keys) async {
      close();
      final draft = TaskDraft.fromTask(t);
      if (!host.mounted || !await picker(host, draft)) return;
      final body = draft.toBody(old: t);
      await store.updateTask(t.id, {for (final k in keys) k: body[k]});
    }

    Future<void> duplicate() async {
      close();
      final body = TaskDraft.fromTask(t).toBody();
      body['title'] = t.title;
      final copy = await store.createTask(body);
      for (final c in t.checklist) {
        await store.addChecklistItem(copy.id, c.text);
      }
      if (host.mounted) {
        ScaffoldMessenger.of(host).showSnackBar(const SnackBar(content: Text('Копия создана')));
      }
    }

    Future<void> delete() async {
      close();
      await store.deleteTask(t);
      if (host.mounted) {
        ScaffoldMessenger.of(host)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('Удалено: ${t.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
            action: SnackBarAction(label: 'Вернуть', onPressed: () => store.restoreTask(t)),
          ));
      }
    }

    final nextMonday = today.add(Duration(days: 8 - today.weekday));

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.25)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (t.dueDate != null) fmtRelDay(t.dueDate!),
                      if (t.dueTime != null) t.dueTime!,
                      if (project != null) project.name,
                    ].join(' · '),
                    style: const TextStyle(color: C.text2, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ]),
              ),
              if (project != null) ...[const SizedBox(width: 12), ProjectAvatar(project: project, size: 36)],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              _DateTile(PhosphorIconsRegular.sun, 'Сегодня', C.high, () => moveTo(today)),
              _DateTile(PhosphorIconsRegular.sunHorizon, 'Завтра', C.accent2,
                  () => moveTo(today.add(const Duration(days: 1)))),
              _DateTile(PhosphorIconsRegular.calendarPlus, 'Пн, ${nextMonday.day}', C.medium, () => moveTo(nextMonday)),
              _DateTile(PhosphorIconsRegular.calendarDots, 'Дата…', C.text2, pickDate),
              _DateTile(PhosphorIconsRegular.tray, 'Без даты', C.muted, () => moveTo(null)),
            ]),
          ),
          const SizedBox(height: 14),
          Group(children: [
            _Action(
              t.isCompleted ? PhosphorIconsRegular.arrowCounterClockwise : PhosphorIconsRegular.checkCircle,
              t.isCompleted ? 'Вернуть в работу' : 'Выполнено',
              () {
                close();
                completeWithUndo(host, t);
              },
              color: t.isCompleted ? null : C.low,
            ),
            _Action(PhosphorIconsRegular.pencilSimple, 'Открыть', () {
              close();
              showTaskSheet(host, task: t);
            }),
            _Action(PhosphorIconsRegular.clock, 'Время', () => editField(Pick.time, ['due_date', 'due_time'])),
            _Action(PhosphorIconsRegular.timer, 'Длительность', () => editField(Pick.duration, ['duration_minutes'])),
            _Action(PhosphorIconsRegular.flag, 'Приоритет', () => editField(Pick.priority, ['priority'])),
            _Action(PhosphorIconsRegular.folderSimple, 'Проект', () => editField(Pick.project, ['project_id'])),
            _Action(PhosphorIconsRegular.copy, 'Дублировать', duplicate),
          ]),
          const SizedBox(height: 12),
          Group(children: [
            _Action(PhosphorIconsRegular.trash, 'Удалить', delete, color: C.urgent),
          ]),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile(this.icon, this.label, this.color, this.onTap);

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: C.bg3,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 6),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: C.text2)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap, {this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(children: [
          Icon(icon, size: 21, color: color ?? C.text2),
          const SizedBox(width: 18),
          Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color ?? C.text)),
        ]),
      ),
    );
  }
}
