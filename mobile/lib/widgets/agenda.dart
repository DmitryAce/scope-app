import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'task_tile.dart';

/// Лента одного дня: расписание по времени, задачи без времени и сделанное.
List<Widget> dayAgendaSlivers(BuildContext context, DateTime day, {required ValueNotifier<bool> showDone}) {
  final store = StoreScope.of(context);
  final all = store.tasksOn(day);
  final timed = all.where((t) => !t.isCompleted && t.startMinute != null).toList();
  final untimed = all.where((t) => !t.isCompleted && t.startMinute == null).toList();
  final done = all.where((t) => t.isCompleted).toList();
  final isToday = dayOnly(day) == dayOnly(DateTime.now());

  if (all.isEmpty) {
    return [
      SliverToBoxAdapter(
        child: EmptyState(
          icon: isToday ? Icons.self_improvement_rounded : Icons.event_available_rounded,
          title: isToday ? 'На сегодня пусто' : 'В этот день задач нет',
          subtitle: 'Нажмите «+», чтобы запланировать',
        ),
      ),
    ];
  }

  return [
    if (timed.isNotEmpty) ...[
      SliverToBoxAdapter(child: SectionHeader('Расписание', count: timed.length)),
      SliverToBoxAdapter(child: Timeline(tasks: timed, isToday: isToday)),
    ],
    if (untimed.isNotEmpty) ...[
      SliverToBoxAdapter(child: SectionHeader('Без времени', count: untimed.length)),
      SliverList.builder(
        itemCount: untimed.length,
        itemBuilder: (_, i) => TaskTile(task: untimed[i]),
      ),
    ],
    if (done.isNotEmpty)
      SliverToBoxAdapter(
        child: ValueListenableBuilder<bool>(
          valueListenable: showDone,
          builder: (context, open, _) => Column(children: [
            SectionHeader(
              'Выполнено',
              count: done.length,
              color: C.low,
              trailing: IconButton(
                onPressed: () => showDone.value = !open,
                icon: AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_rounded, color: C.text2),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: open
                  ? Column(children: [for (final t in done) TaskTile(task: t)])
                  : const SizedBox(width: double.infinity),
            ),
          ]),
        ),
      ),
  ];
}

/// Задачи со временем на вертикальной шкале; сейчас — красная линия «Сейчас».
class Timeline extends StatelessWidget {
  const Timeline({super.key, required this.tasks, required this.isToday});

  final List<Task> tasks;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    final nowMin = now.hour * 60 + now.minute;
    final rows = <Widget>[];
    var nowPlaced = !isToday;

    for (var i = 0; i < tasks.length; i++) {
      final t = tasks[i];
      final start = t.startMinute!;
      final end = start + (t.durationMinutes ?? 0);
      if (!nowPlaced && nowMin < start) {
        rows.add(const _NowLine());
        nowPlaced = true;
      }
      final running = isToday && t.durationMinutes != null && nowMin >= start && nowMin < end;
      final past = isToday && nowMin >= (t.durationMinutes != null ? end : start + 1);
      rows.add(_TimelineRow(task: t, running: running, past: past, last: i == tasks.length - 1));
      if (running && !nowPlaced) nowPlaced = true;
    }
    if (!nowPlaced) rows.add(const _NowLine());
    return Column(children: rows);
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.task, required this.running, required this.past, required this.last});

  final Task task;
  final bool running;
  final bool past;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final color = store.projectById(task.projectId)?.tint ?? C.accent;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 62,
          child: Padding(
            padding: const EdgeInsets.only(left: 16, top: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(task.dueTime!,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: running ? C.accent2 : (past ? C.muted : C.text),
                  )),
              if (task.durationMinutes != null)
                Text(endTime(task.dueTime!, task.durationMinutes!),
                    style: const TextStyle(fontSize: 11, color: C.muted, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        SizedBox(
          width: 14,
          child: Column(children: [
            const SizedBox(height: 20),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: running ? color : C.bg,
                border: Border.all(color: past ? C.muted : color, width: 2.5),
                boxShadow: running ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 10)] : null,
              ),
            ),
            if (!last)
              Expanded(
                child: Container(width: 2, color: C.border),
              ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 0),
            child: Opacity(
              opacity: past && !running ? 0.72 : 1,
              child: TaskTile(task: task),
            ),
          ),
        ),
      ]),
    );
  }
}

class _NowLine extends StatelessWidget {
  const _NowLine();

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    final label = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 20, 6),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: C.urgent, borderRadius: BorderRadius.circular(8)),
          child: Text(label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        Expanded(child: Container(height: 2, color: C.urgent.withValues(alpha: 0.7))),
      ]),
    );
  }
}
