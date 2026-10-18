import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Теги: список, создание, переименование, цвет, удаление.
class TagsScreen extends StatelessWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Теги'),
        actions: [
          IconButton(
            tooltip: 'Новый тег',
            onPressed: () => showTagEditor(context),
            icon: const Icon(PhosphorIconsRegular.plusCircle, size: 25),
          ),
        ],
      ),
      body: store.tags.isEmpty
          ? const EmptyState(
              icon: PhosphorIconsLight.hash,
              title: 'Тегов пока нет',
              subtitle: 'Создайте первый — плюс вверху справа',
            )
          : ListView(padding: const EdgeInsets.only(top: 8, bottom: 40), children: [
              Group(children: [
                for (final t in store.tags)
                  InkWell(
                    onTap: () => showTagEditor(context, tag: t),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                      child: Row(children: [
                        Icon(PhosphorIconsBold.hash, size: 20, color: t.tint),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Text(t.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                        const Icon(PhosphorIconsBold.caretRight, size: 13, color: C.muted),
                      ]),
                    ),
                  ),
              ]),
            ]),
    );
  }
}

/// Создать или изменить тег. Возвращает созданный/изменённый тег.
Future<Tag?> showTagEditor(BuildContext context, {Tag? tag}) {
  return showModalBottomSheet<Tag>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _TagEditor(tag: tag),
  );
}

class _TagEditor extends StatefulWidget {
  const _TagEditor({this.tag});

  final Tag? tag;

  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  late final _name = TextEditingController(text: widget.tag?.name ?? '');
  late Color _color = widget.tag?.tint ?? C.projectPalette[2];
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim().replaceFirst(RegExp(r'^#+'), '');
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final store = StoreScope.read(context);
    try {
      Tag result;
      if (widget.tag == null) {
        result = await store.createTag(name, hexOf(_color));
      } else {
        await store.updateTag(widget.tag!.id, name: name, color: hexOf(_color));
        result = store.tagById(widget.tag!.id)!;
      }
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Удалить тег «${widget.tag!.name}»?'),
        content: const Text('Задачи останутся, у них просто пропадёт этот тег.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Удалить', style: TextStyle(color: C.urgent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final store = StoreScope.read(context);
    final nav = Navigator.of(context);
    try {
      await store.deleteTag(widget.tag!.id);
      nav.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.tag != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(editing ? 'Тег' : 'Новый тег', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        TextField(
          controller: _name,
          autofocus: !editing,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            hintText: 'Название',
            prefixIcon: Icon(PhosphorIconsBold.hash, size: 18, color: _color),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in C.projectPalette)
            GestureDetector(
              onTap: () => setState(() => _color = c),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c.toARGB32() == _color.toARGB32() ? Colors.white : Colors.transparent,
                    width: 2.5,
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          if (editing) ...[
            IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: C.bg3, fixedSize: const Size(50, 50)),
              onPressed: _delete,
              icon: const Icon(PhosphorIconsRegular.trash, color: C.urgent),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: SizedBox(
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: C.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _busy ? null : _save,
                child: Text(editing ? 'Сохранить' : 'Создать', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}
