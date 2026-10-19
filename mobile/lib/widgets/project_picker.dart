import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models.dart';
import '../theme.dart';
import 'common.dart';

/// Выбор проекта с поиском: дерево «родитель → подпроекты», при поиске — плоский
/// список совпадений с подписью родителя. Возвращает id, 0 — «без проекта», null — отмена.
Future<int?> showProjectPicker(
  BuildContext context, {
  required String title,
  int? selectedId,
  bool Function(Project)? allow,
  String noneLabel = 'Без проекта',
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ProjectPicker(
      title: title,
      selectedId: selectedId,
      allow: allow,
      noneLabel: noneLabel,
    ),
  );
}

class _ProjectPicker extends StatefulWidget {
  const _ProjectPicker({
    required this.title,
    required this.selectedId,
    required this.allow,
    required this.noneLabel,
  });

  final String title;
  final int? selectedId;
  /// Какие проекты можно выбрать (остальные видны блёкло — для понимания дерева).
  final bool Function(Project)? allow;
  final String noneLabel;

  @override
  State<_ProjectPicker> createState() => _ProjectPickerState();
}

class _ProjectPickerState extends State<_ProjectPicker> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final query = _q.text.trim().toLowerCase();

    Widget row(Project? p, {int depth = 0, String? hint}) {
      final selected = (p?.id ?? 0) == (widget.selectedId ?? 0);
      final enabled = p == null || widget.allow == null || widget.allow!(p);
      return InkWell(
        onTap: enabled ? () => Navigator.pop(context, p?.id ?? 0) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
          child: Padding(
            padding: EdgeInsets.fromLTRB(18.0 + depth * 22, 9, 18, 9),
            child: Row(children: [
              ProjectAvatar(project: p, size: depth == 0 ? 34 : 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p?.name ?? widget.noneLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  if (hint != null)
                    Text(hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w600)),
                ]),
              ),
              if (selected) Icon(PhosphorIconsBold.check, color: C.accent2, size: 18),
            ]),
          ),
        ),
      );
    }

    final rows = <Widget>[];
    if (query.isEmpty) {
      rows.add(row(null));
      for (final (p, depth) in store.projectTree()) {
        rows.add(row(p, depth: depth));
      }
    } else {
      for (final p in store.projects) {
        if (!p.name.toLowerCase().contains(query)) continue;
        if (widget.allow != null && !widget.allow!(p)) continue;
        final path = store.ancestorsOf(p).map((x) => x.name).join(' › ');
        rows.add(row(p, hint: path.isEmpty ? null : path));
      }
      if (rows.isEmpty) {
        rows.add(const Padding(
          padding: EdgeInsets.all(28),
          child: Center(child: Text('Ничего не найдено', style: TextStyle(color: C.muted))),
        ));
      }
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _q,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Найти проект',
              prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass, size: 20, color: C.muted),
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 16), children: rows)),
      ]),
    );
  }
}
