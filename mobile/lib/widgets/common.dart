import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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

/// Коротко для строки задачи: «Сегодня», «Вчера», «24 сент», «24 сент 2025».
String fmtShortDay(DateTime d) {
  final today = dayOnly(DateTime.now());
  final diff = dayOnly(d).difference(today).inDays;
  if (diff == 0) return 'Сегодня';
  if (diff == 1) return 'Завтра';
  if (diff == -1) return 'Вчера';
  final s = DateFormat(d.year == today.year ? 'd MMM' : 'd MMM yy', 'ru').format(d);
  return s.replaceAll('.', '');
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

/// Откуда данные: дома по локалке, через интернет, офлайн. Тихая строка, не баннер.
class ConnectionPill extends StatelessWidget {
  const ConnectionPill({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context);
    final (IconData icon, String label, Color color) = s.syncing
        ? (PhosphorIconsRegular.arrowsClockwise, 'обновляю', C.text2)
        : s.error != null
            ? (PhosphorIconsRegular.cloudSlash, 'офлайн', C.high)
            : s.activeBase == null
                ? (PhosphorIconsRegular.cloud, 'подключаюсь', C.text2)
                : s.onLocal
                    ? (PhosphorIconsFill.house, 'дома', C.low)
                    : (PhosphorIconsRegular.globeSimple, 'интернет', C.medium);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }
}

/// Заголовок секции: обычный регистр, число рядом приглушённо.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.count, this.trailing, this.color, this.onTap});

  final String title;
  final int? count;
  final Widget? trailing;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 14, 8),
        child: Row(children: [
          Text(title,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color ?? C.text)),
          if (count != null) ...[
            const SizedBox(width: 7),
            Text('$count', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.muted)),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ]),
      ),
    );
  }
}

/// Стрелка сворачивания секции.
class Caret extends StatelessWidget {
  const Caret({super.key, required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
        turns: open ? 0 : -0.25,
        duration: const Duration(milliseconds: 200),
        child: const Icon(PhosphorIconsBold.caretDown, size: 15, color: C.muted),
      );
}

/// Сгруппированный блок строк с тонкими разделителями — как настройки iOS/Android.
class Group extends StatelessWidget {
  const Group({super.key, required this.children, this.margin = const EdgeInsets.symmetric(horizontal: 14)});

  final List<Widget> children;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(height: 1, thickness: 0.6, indent: 54, color: C.border));
      rows.add(children[i]);
    }
    return Container(
      margin: margin,
      decoration: BoxDecoration(color: C.bg2, borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
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
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(children: [
        Icon(icon, size: 40, color: C.muted),
        const SizedBox(height: 14),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.text2)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: C.muted, fontSize: 13)),
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
        borderRadius: BorderRadius.circular(size * 0.26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [C.logo, C.logoDark],
        ),
      ),
      child: Text('S',
          style: TextStyle(color: Colors.white, fontSize: size * 0.58, fontWeight: FontWeight.w800, height: 1.1)),
    );
  }
}

/// Аватарка проекта: загруженная картинка или монограмма в цвете проекта.
class ProjectAvatar extends StatelessWidget {
  const ProjectAvatar({super.key, required this.project, this.size = 36});

  final Project? project;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final radius = BorderRadius.circular(size * 0.3);
    if (p == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: C.bg3, borderRadius: radius),
        child: Icon(PhosphorIconsRegular.tray, size: size * 0.55, color: C.text2),
      );
    }
    final url = StoreScope.of(context).avatarUrl(p);
    final monogram = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.tint.withValues(alpha: 0.2), borderRadius: radius),
      child: Text(
        p.name.trim().isEmpty ? '?' : p.name.trim().characters.first.toUpperCase(),
        style: TextStyle(color: p.tint, fontSize: size * 0.46, fontWeight: FontWeight.w800, height: 1.1),
      ),
    );
    if (url == null) return monogram;
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * MediaQuery.of(context).devicePixelRatio).round(),
        errorBuilder: (_, __, ___) => monogram,
        frameBuilder: (_, child, frame, sync) => sync || frame != null ? child : monogram,
      ),
    );
  }
}

void showError(BuildContext context, Object e) {
  final msg = e is ApiException ? e.message : '$e';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}
