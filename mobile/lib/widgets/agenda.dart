import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
          icon: isToday ? PhosphorIconsLight.coffee : PhosphorIconsLight.calendarBlank,
          title: isToday ? 'На сегодня ничего' : 'В этот день пусто',
          subtitle: 'Нажмите «+», чтобы запланировать',
        ),
      ),
    ];
  }

  return [
    if (timed.isNotEmpty) ...[
      SliverToBoxAdapter(child: SectionHeader('Расписание', count: timed.length)),
      SliverToBoxAdapter(child: _Schedule(tasks: timed, isToday: isToday)),
    ],
    if (untimed.isNotEmpty) ...[
      SliverToBoxAdapter(child: SectionHeader(timed.isEmpty ? 'Задачи' : 'Без времени', count: untimed.length)),
      SliverToBoxAdapter(child: Group(children: [for (final t in untimed) TaskTile(task: t)])),
    ],
    if (done.isNotEmpty)
      SliverToBoxAdapter(
        child: ValueListenableBuilder<bool>(
          valueListenable: showDone,
          builder: (context, open, _) => Column(children: [
            SectionHeader(
              'Сделано',
              count: done.length,
              color: C.text2,
              onTap: () => showDone.value = !open,
              trailing: Caret(open: open),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: open
                  ? Group(children: [for (final t in done) TaskTile(task: t, timeColumn: t.dueTime != null)])
                  : const SizedBox(width: double.infinity),
            ),
          ]),
        ),
      ),
  ];
}

/// Задачи со временем; сегодня между ними — красная линия «сейчас».
class _Schedule extends StatelessWidget {
  const _Schedule({required this.tasks, required this.isToday});

  final List<Task> tasks;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    final nowMin = now.hour * 60 + now.minute;
    final rows = <Widget>[];
    var nowPlaced = !isToday;

    for (final t in tasks) {
      final start = t.startMinute!;
      final end = start + (t.durationMinutes ?? 0);
      if (!nowPlaced && nowMin < start) {
        rows.add(const _NowLine());
        nowPlaced = true;
      }
      final past = isToday && nowMin >= (t.durationMinutes != null ? end : start + 1);
      rows.add(TaskTile(task: t, timeColumn: true, dim: past));
    }
    if (!nowPlaced) rows.add(const _NowLine());

    // Линия «сейчас» — без разделителей вокруг.
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      final prevIsLine = i > 0 && rows[i - 1] is _NowLine;
      if (i > 0 && rows[i] is! _NowLine && !prevIsLine) {
        children.add(const Divider(height: 1, thickness: 0.6, indent: 106, color: C.border));
      }
      children.add(rows[i]);
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: C.bg2, borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _NowLine extends StatelessWidget {
  const _NowLine();

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    final label = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return SizedBox(
      height: 18,
      child: Row(children: [
        SizedBox(
          width: 56,
          child: Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: C.urgent,
                  fontFeatures: [FontFeature.tabularFigures()],
                )),
          ),
        ),
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(color: C.urgent, shape: BoxShape.circle),
        ),
        Expanded(child: Container(height: 1.4, color: C.urgent.withValues(alpha: 0.75))),
      ]),
    );
  }
}
