import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/agenda.dart';
import '../widgets/common.dart';
import '../widgets/task_tile.dart';
import 'search.dart';
import 'settings.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final _showDone = ValueNotifier(false);
  final _showOverdue = ValueNotifier(true);

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final today = dayOnly(DateTime.now());
    final overdue = store.overdue;
    final inbox = store.inbox;

    return RefreshIndicator(
      color: C.accent2,
      backgroundColor: C.bg3,
      onRefresh: store.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          SliverSafeArea(
            bottom: false,
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 10, 0),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Сегодня',
                          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                      const SizedBox(height: 2),
                      Row(children: [
                        Text(fmtLongDay(today),
                            style: const TextStyle(color: C.text2, fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(width: 6),
                        ConnectionPill(
                          onTap: () => Navigator.push(
                              context, MaterialPageRoute(builder: (_) => const ServerSettingsScreen())),
                        ),
                      ]),
                    ]),
                  ),
                  IconButton(
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
                    icon: const Icon(PhosphorIconsRegular.magnifyingGlass, size: 24),
                  ),
                ]),
              ),
            ),
          ),
          SliverToBoxAdapter(child: _DaySummary(day: today)),
          if (overdue.isNotEmpty)
            SliverToBoxAdapter(
              child: ValueListenableBuilder<bool>(
                valueListenable: _showOverdue,
                builder: (context, open, _) => Column(children: [
                  SectionHeader(
                    'Просрочено',
                    count: overdue.length,
                    color: C.urgent,
                    onTap: () => _showOverdue.value = !open,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        onPressed: () => _moveAllToToday(context),
                        child: const Text('На сегодня'),
                      ),
                      Caret(open: open),
                    ]),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: open
                        ? Group(children: [for (final t in overdue) TaskTile(task: t, showDate: true)])
                        : const SizedBox(width: double.infinity),
                  ),
                ]),
              ),
            ),
          ...dayAgendaSlivers(context, today, showDone: _showDone),
          if (inbox.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionHeader('Без даты', count: inbox.length, color: C.text2)),
            SliverToBoxAdapter(
              child: Group(children: [for (final t in inbox.take(6)) TaskTile(task: t)]),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 130)),
        ],
      ),
    );
  }

  Future<void> _moveAllToToday(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final store = StoreScope.read(context);
    final list = store.overdue;
    for (final t in list) {
      await store.moveTo(t, DateTime.now());
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Перенесено на сегодня: ${list.length}')));
    }
  }
}

/// Сводка дня одной строкой: сколько сделано и что дальше.
class _DaySummary extends StatelessWidget {
  const _DaySummary({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final tasks = store.tasksOn(day);
    final total = tasks.length;
    if (total == 0) return const SizedBox(height: 8);
    final done = tasks.where((t) => t.isCompleted).length;
    final left = total - done;

    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    Task? next;
    for (final t in tasks) {
      final m = t.startMinute;
      if (!t.isCompleted && m != null && m + (t.durationMinutes ?? 0) >= nowMin) {
        next = t;
        break;
      }
    }

    final title = left == 0
        ? 'Всё сделано'
        : '${_plural(left, 'Осталась', 'Осталось', 'Осталось')} $left ${_plural(left, 'задача', 'задачи', 'задач')}';
    final subtitle = next != null
        ? 'Дальше в ${next.dueTime}: ${next.title}'
        : left == 0
            ? 'Свободный вечер'
            : 'Задач по времени больше нет';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        decoration: BoxDecoration(color: C.bg2, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          SizedBox(
            width: 44,
            height: 44,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: done / total),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => Stack(alignment: Alignment.center, children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: v,
                    strokeWidth: 4,
                    strokeCap: StrokeCap.round,
                    backgroundColor: C.bg3,
                    color: left == 0 ? C.low : C.accent2,
                  ),
                ),
                Text('$done/$total',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: C.text2)),
              ]),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: C.text2, fontSize: 13, fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
      ),
    );
  }
}

String _plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}
