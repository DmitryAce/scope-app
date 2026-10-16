import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(fmtLongDay(today),
                          style: const TextStyle(color: C.text2, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        '${greeting()}${store.username != null ? ', ${store.username}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                      ),
                    ]),
                  ),
                  IconButton(
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
                    icon: const Icon(Icons.search_rounded),
                  ),
                ]),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConnectionPill(
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const ServerSettingsScreen())),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: _ProgressCard(day: today)),
          if (overdue.isNotEmpty)
            SliverToBoxAdapter(
              child: ValueListenableBuilder<bool>(
                valueListenable: _showOverdue,
                builder: (context, open, _) => Column(children: [
                  SectionHeader(
                    'Просрочено',
                    count: overdue.length,
                    color: C.urgent,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      TextButton(
                        onPressed: () => _moveAllToToday(context),
                        child: const Text('Всё на сегодня'),
                      ),
                      IconButton(
                        onPressed: () => _showOverdue.value = !open,
                        icon: AnimatedRotation(
                          turns: open ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(Icons.expand_more_rounded, color: C.text2),
                        ),
                      ),
                    ]),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    child: open
                        ? Column(children: [for (final t in overdue) TaskTile(task: t, showDate: true)])
                        : const SizedBox(width: double.infinity),
                  ),
                ]),
              ),
            ),
          ...dayAgendaSlivers(context, today, showDone: _showDone),
          if (inbox.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionHeader('Входящие · без даты', count: inbox.length)),
            SliverList.builder(
              itemCount: math.min(inbox.length, 8),
              itemBuilder: (_, i) => TaskTile(task: inbox[i]),
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

/// Карточка дня: кольцо прогресса и ближайшая задача.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final tasks = store.tasksOn(day);
    final total = tasks.length;
    final done = tasks.where((t) => t.isCompleted).length;
    final progress = total == 0 ? 0.0 : done / total;

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
    final busy = tasks
        .where((t) => !t.isCompleted && t.durationMinutes != null)
        .fold<int>(0, (s, t) => s + t.durationMinutes!);

    String headline;
    if (total == 0) {
      headline = 'Свободный день';
    } else if (done == total) {
      headline = 'Всё сделано! 🎉';
    } else {
      headline = '$done из $total готово';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [C.accent.withValues(alpha: 0.32), C.logo.withValues(alpha: 0.22), C.bg2],
            stops: const [0, 0.55, 1],
          ),
          border: Border.all(color: C.accent.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          SizedBox(
            width: 76,
            height: 76,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => Stack(alignment: Alignment.center, children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: v,
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    color: done == total && total > 0 ? C.low : C.accent2,
                  ),
                ),
                Text('${(v * 100).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ]),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(headline, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              if (next != null)
                Row(children: [
                  const Icon(Icons.bolt_rounded, size: 16, color: C.high),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('${next.dueTime} · ${next.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: C.text, fontWeight: FontWeight.w600)),
                  ),
                ])
              else
                Text(total == 0 ? 'Можно что-нибудь запланировать' : 'Ближайших задач по времени нет',
                    style: const TextStyle(color: C.text2)),
              if (busy > 0) ...[
                const SizedBox(height: 4),
                Text('Занято ещё ${fmtDuration(busy)}',
                    style: const TextStyle(color: C.text2, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
