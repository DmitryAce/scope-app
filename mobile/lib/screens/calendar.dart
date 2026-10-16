import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/agenda.dart';
import '../widgets/common.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => CalendarScreenState();
}

class CalendarScreenState extends State<CalendarScreen> {
  static const _origin = 1000;

  DateTime selected = dayOnly(DateTime.now());
  bool _month = false;
  final _showDone = ValueNotifier(true);
  late final DateTime _baseMonday = _mondayOf(dayOnly(DateTime.now()));
  late final DateTime _baseMonth = DateTime(DateTime.now().year, DateTime.now().month);
  late PageController _weeks = PageController(initialPage: _origin);
  late PageController _months = PageController(initialPage: _origin);

  static DateTime _mondayOf(DateTime d) => d.subtract(Duration(days: d.weekday - 1));

  DateTime _weekAt(int page) => _baseMonday.add(Duration(days: (page - _origin) * 7));

  DateTime _monthAt(int page) => DateTime(_baseMonth.year, _baseMonth.month + page - _origin);

  int _weekPageOf(DateTime d) => _origin + _mondayOf(d).difference(_baseMonday).inDays ~/ 7;

  int _monthPageOf(DateTime d) =>
      _origin + (d.year - _baseMonth.year) * 12 + (d.month - _baseMonth.month);

  @override
  void dispose() {
    _weeks.dispose();
    _months.dispose();
    super.dispose();
  }

  void _select(DateTime d, {bool jump = false}) {
    HapticFeedback.selectionClick();
    setState(() => selected = dayOnly(d));
    _load(d);
    if (jump) {
      _weeks.dispose();
      _months.dispose();
      _weeks = PageController(initialPage: _weekPageOf(d));
      _months = PageController(initialPage: _monthPageOf(d));
    }
  }

  void _load(DateTime around) {
    StoreScope.read(context).ensureRange(
      DateTime(around.year, around.month - 1, 1),
      DateTime(around.year, around.month + 2, 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final today = dayOnly(DateTime.now());
    final shownMonth = selected;

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
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                child: Row(children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: selected,
                        firstDate: DateTime(today.year - 3),
                        lastDate: DateTime(today.year + 5),
                        locale: const Locale('ru'),
                      );
                      if (d != null) _select(d, jump: true);
                    },
                    child: Row(children: [
                      Text(fmtMonth(shownMonth),
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                      const Icon(Icons.arrow_drop_down_rounded, color: C.text2),
                    ]),
                  ),
                  const Spacer(),
                  if (selected != today)
                    TextButton(onPressed: () => _select(today, jump: true), child: const Text('Сегодня')),
                  IconButton(
                    tooltip: _month ? 'Неделя' : 'Месяц',
                    onPressed: () => setState(() {
                      _month = !_month;
                      _weeks.dispose();
                      _months.dispose();
                      _weeks = PageController(initialPage: _weekPageOf(selected));
                      _months = PageController(initialPage: _monthPageOf(selected));
                    }),
                    icon: Icon(_month ? Icons.view_week_rounded : Icons.calendar_view_month_rounded),
                  ),
                ]),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: _month ? _buildMonth(today) : _buildWeek(today),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(children: [
                Text(fmtLongDay(selected), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                if (selected == today)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: C.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('сегодня',
                        style: TextStyle(fontSize: 12, color: C.accent2, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ),
          ...dayAgendaSlivers(context, selected, showDone: _showDone),
          const SliverToBoxAdapter(child: SizedBox(height: 110)),
        ],
      ),
    );
  }

  Widget _buildWeek(DateTime today) {
    return SizedBox(
      height: 92,
      child: PageView.builder(
        controller: _weeks,
        onPageChanged: (p) => _load(_weekAt(p)),
        itemBuilder: (context, page) {
          final monday = _weekAt(page);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              for (var i = 0; i < 7; i++)
                Expanded(child: _DayCell(day: monday.add(Duration(days: i)), selected: selected, today: today, onTap: _select)),
            ]),
          );
        },
      ),
    );
  }

  Widget _buildMonth(DateTime today) {
    const names = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          for (final n in names)
            Expanded(
              child: Center(
                child: Text(n,
                    style: const TextStyle(color: C.muted, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ),
      SizedBox(
        height: 6 * 52,
        child: PageView.builder(
          controller: _months,
          onPageChanged: (p) {
            final m = _monthAt(p);
            _load(m);
            if (selected.month != m.month || selected.year != m.year) {
              setState(() => selected = m);
            }
          },
          itemBuilder: (context, page) {
            final month = _monthAt(page);
            final first = _mondayOf(month);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(children: [
                for (var w = 0; w < 6; w++)
                  SizedBox(
                    height: 52,
                    child: Row(children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: _MonthCell(
                            day: first.add(Duration(days: w * 7 + i)),
                            month: month.month,
                            selected: selected,
                            today: today,
                            onTap: _select,
                          ),
                        ),
                    ]),
                  ),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.selected, required this.today, required this.onTap});

  final DateTime day;
  final DateTime selected;
  final DateTime today;
  final void Function(DateTime) onTap;

  @override
  Widget build(BuildContext context) {
    final (total, done) = StoreScope.of(context).dayLoad(day);
    final isSel = day == selected;
    final isToday = day == today;
    final weekend = day.weekday >= 6;
    return GestureDetector(
      onTap: () => onTap(day),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: isSel
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [C.accent, Color(0xFF5B21B6)],
                )
              : null,
          color: isSel ? null : C.bg2,
          border: Border.all(color: isToday && !isSel ? C.accent2 : (isSel ? Colors.transparent : C.borderLight)),
          boxShadow: isSel ? [BoxShadow(color: C.accent.withValues(alpha: 0.45), blurRadius: 14)] : null,
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(fmtShortWeekday(day),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSel ? Colors.white70 : (weekend ? C.logo.withValues(alpha: 0.9) : C.text2),
              )),
          const SizedBox(height: 2),
          Text('${day.day}',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: isSel ? Colors.white : C.text,
              )),
          const SizedBox(height: 4),
          _LoadDots(total: total, done: done, light: isSel),
        ]),
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.day,
    required this.month,
    required this.selected,
    required this.today,
    required this.onTap,
  });

  final DateTime day;
  final int month;
  final DateTime selected;
  final DateTime today;
  final void Function(DateTime) onTap;

  @override
  Widget build(BuildContext context) {
    final (total, done) = StoreScope.of(context).dayLoad(day);
    final isSel = day == selected;
    final isToday = day == today;
    final outside = day.month != month;
    return GestureDetector(
      onTap: () => onTap(day),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: isSel ? C.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: isToday && !isSel ? Border.all(color: C.accent2) : null,
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${day.day}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isSel ? Colors.white : (outside ? C.muted.withValues(alpha: 0.6) : C.text),
              )),
          const SizedBox(height: 3),
          _LoadDots(total: total, done: done, light: isSel),
        ]),
      ),
    );
  }
}

/// До трёх точек: сколько задач на день; зелёные — сделанные.
class _LoadDots extends StatelessWidget {
  const _LoadDots({required this.total, required this.done, required this.light});

  final int total;
  final int done;
  final bool light;

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox(height: 5);
    final n = total.clamp(1, 3);
    final doneDots = total == 0 ? 0 : (done * n / total).round();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < n; i++)
        Container(
          width: 5,
          height: 5,
          margin: const EdgeInsets.symmetric(horizontal: 1.2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: light ? (i < doneDots ? C.low : Colors.white) : (i < doneDots ? C.low : C.accent2),
          ),
        ),
    ]);
  }
}
