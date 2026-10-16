import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';

/// Доступ к стору из любого виджета: `StoreScope.of(context)`.
class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child})
      : super(notifier: store);

  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;

  static AppStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String fmtLongDay(DateTime d) => _cap(DateFormat('EEEE, d MMMM', 'ru').format(d));

String fmtMonth(DateTime d) => _cap(DateFormat('LLLL yyyy', 'ru').format(d));

String fmtShortWeekday(DateTime d) => _cap(DateFormat('EE', 'ru').format(d));

/// «Сегодня», «Завтра», «Вчера», «пт, 24 окт.»
String fmtRelDay(DateTime d) {
  final today = dayOnly(DateTime.now());
  final diff = dayOnly(d).difference(today).inDays;
  if (diff == 0) return 'Сегодня';
  if (diff == 1) return 'Завтра';
  if (diff == 2) return 'Послезавтра';
  if (diff == -1) return 'Вчера';
  if (d.year == today.year) return DateFormat('EE, d MMM', 'ru').format(d);
  return DateFormat('d MMM yyyy', 'ru').format(d);
}

String fmtDuration(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m мин';
  if (m == 0) return '$h ч';
  return '$h ч $m мин';
}

String endTime(String start, int minutes) {
  final p = start.split(':');
  final total = int.parse(p[0]) * 60 + int.parse(p[1]) + minutes;
  return '${((total ~/ 60) % 24).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
}

String greeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Доброй ночи';
  if (h < 12) return 'Доброе утро';
  if (h < 18) return 'Добрый день';
  return 'Добрый вечер';
}

/// Плашка «откуда данные»: дома по локалке, через интернет или из кэша.
class ConnectionPill extends StatelessWidget {
  const ConnectionPill({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final (IconData icon, String label, Color color) = s.syncing
        ? (Icons.sync_rounded, 'Синхронизация', C.accent2)
        : s.error != null
            ? (Icons.cloud_off_rounded, 'Офлайн', C.high)
            : s.activeBase == null
                ? (Icons.cloud_queue_rounded, 'Подключение', C.text2)
                : s.onLocal
                    ? (Icons.home_rounded, 'Дома · локалка', C.low)
                    : (Icons.public_rounded, 'Интернет', C.medium);
    return Material(
      color: color.withValues(alpha: 0.12),
      shape: StadiumBorder(side: BorderSide(color: color.withValues(alpha: 0.35))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            s.syncing
                ? SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2, color: color),
                  )
                : Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ]),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.count, this.trailing, this.color});

  final String title;
  final int? count;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 12, 8),
      child: Row(children: [
        Text(title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
              color: color ?? C.text2,
            )),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: (color ?? C.text2).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$count',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color ?? C.text2)),
          ),
        ],
        const Spacer(),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      child: Column(children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [C.accent.withValues(alpha: 0.25), C.logo.withValues(alpha: 0.18)],
            ),
          ),
          child: Icon(icon, size: 34, color: C.accent2),
        ),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: C.text2)),
        ],
      ]),
    );
  }
}

/// Фирменный значок: бордовый квадрат с «S», как favicon веб-версии.
class ScopeLogo extends StatelessWidget {
  const ScopeLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [C.logo, C.logoDark],
        ),
        boxShadow: [BoxShadow(color: C.logo.withValues(alpha: 0.45), blurRadius: size * 0.5)],
      ),
      child: Text('S',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.6,
            fontWeight: FontWeight.w800,
            height: 1.1,
          )),
    );
  }
}

void showError(BuildContext context, Object e) {
  final msg = e is ApiException ? e.message : '$e';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}
