import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Блок «Задачи из ERP» в настройках: подключения пользователя и кнопка «Подключить».
///
/// Токен ERP уходит на сервер Scope один раз и хранится там зашифрованным —
/// в приложение он больше не возвращается.
class ErpSection extends StatelessWidget {
  const ErpSection({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final erp = store.erp;
    if (erp == null) return const SizedBox.shrink(); // старый сервер
    final connections = ((erp['connections'] ?? const []) as List).cast<Map>();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('Задачи из ERP'),
      _Card(children: [
        for (final c in connections) _ConnectionTile(conn: c),
        ListTile(
          leading: Icon(PhosphorIconsRegular.plusCircle, color: C.accent2),
          title: const Text('Подключить ERP', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            connections.isEmpty
                ? 'Задачи, где вы исполнитель, появятся здесь. Галочка в Scope закрывает их только у вас.'
                : 'Ещё одна ERP',
            style: const TextStyle(color: C.muted, fontSize: 12),
          ),
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => _ConnectSheet(presets: ((erp['presets'] ?? const []) as List).cast<Map>()),
          ),
        ),
      ]),
    ]);
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({required this.conn});

  final Map conn;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final error = (conn['error'] as String? ?? '');
    final color = parseHex(conn['color'] as String?);
    final lastRun = conn['last_run'] == null ? null : DateTime.parse(conn['last_run']).toLocal();
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(11)),
        child: Icon(PhosphorIconsRegular.briefcase, color: color, size: 19),
      ),
      title: Text('${conn['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        error.isNotEmpty
            ? error
            : lastRun == null
                ? 'Ещё не синхронизировалось'
                : '${conn['open_tasks']} открытых · ${DateFormat('d MMM, HH:mm', 'ru').format(lastRun)}',
        style: TextStyle(color: error.isNotEmpty ? C.urgent : C.text2, fontSize: 13),
      ),
      trailing: const Icon(PhosphorIconsBold.caretRight, size: 14, color: C.muted),
      onTap: () => _actions(context, store),
    );
  }

  Future<void> _actions(BuildContext context, AppStore store) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${conn['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ),
          ListTile(
            leading: const Icon(PhosphorIconsRegular.arrowsClockwise),
            title: const Text('Подтянуть сейчас'),
            onTap: () => Navigator.pop(c, 'sync'),
          ),
          ListTile(
            leading: const Icon(PhosphorIconsRegular.key),
            title: const Text('Обновить токен'),
            onTap: () => Navigator.pop(c, 'token'),
          ),
          ListTile(
            leading: const Icon(PhosphorIconsRegular.plugs, color: C.high),
            title: const Text('Отключить, задачи закрыть'),
            subtitle: const Text('Останутся в истории выполненными', style: TextStyle(color: C.muted, fontSize: 12)),
            onTap: () => Navigator.pop(c, 'close'),
          ),
          ListTile(
            leading: const Icon(PhosphorIconsRegular.trash, color: C.urgent),
            title: const Text('Отключить и удалить задачи', style: TextStyle(color: C.urgent)),
            onTap: () => Navigator.pop(c, 'delete'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;
    try {
      switch (choice) {
        case 'sync':
          await store.syncErpNow();
        case 'token':
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => _ConnectSheet(presets: const [], reconnect: conn),
          );
        case 'close':
        case 'delete':
          await store.disconnectErp(conn['id'] as int, deleteTasks: choice == 'delete');
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

/// Подключение: выбрать ERP (или свою по адресу) и вставить личный API-токен.
class _ConnectSheet extends StatefulWidget {
  const _ConnectSheet({required this.presets, this.reconnect});

  final List<Map> presets;

  /// Обновить токен существующего подключения.
  final Map? reconnect;

  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<_ConnectSheet> {
  late String _preset = widget.reconnect != null
      ? (widget.reconnect!['source'] as String).startsWith('erp-')
          ? ''
          : widget.reconnect!['source'] as String
      : (widget.presets.isNotEmpty ? widget.presets.first['key'] as String : '');
  late final _url = TextEditingController(text: widget.reconnect?['base_url'] as String? ?? 'https://');
  late final _name = TextEditingController(text: widget.reconnect?['name'] as String? ?? '');
  final _token = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await StoreScope.read(context).connectErp(
        preset: _preset,
        baseUrl: _preset.isEmpty ? _url.text.trim() : '',
        name: _preset.isEmpty ? _name.text.trim() : '',
        token: _token.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final custom = _preset.isEmpty;
    final reconnecting = widget.reconnect != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(reconnecting ? 'Новый токен · ${widget.reconnect!['name']}' : 'Подключить ERP',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          if (!reconnecting) ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in widget.presets)
                ChoiceChip(
                  label: Text('${p['name']}'),
                  selected: _preset == p['key'],
                  showCheckmark: false,
                  selectedColor: C.accent,
                  onSelected: (_) => setState(() => _preset = p['key'] as String),
                ),
              ChoiceChip(
                label: const Text('Другая ERP'),
                selected: custom,
                showCheckmark: false,
                selectedColor: C.accent,
                onSelected: (_) => setState(() => _preset = ''),
              ),
            ]),
            const SizedBox(height: 14),
          ],
          if (custom && !reconnecting) ...[
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'https://erp.example.ru', labelText: 'Адрес ERP'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              decoration: const InputDecoration(hintText: 'Как называть в Scope', labelText: 'Название'),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _token,
            obscureText: _hide,
            autofocus: true,
            onSubmitted: (_) => _connect(),
            decoration: InputDecoration(
              labelText: 'API-токен',
              hintText: 'Вставьте токен из профиля ERP',
              prefixIcon: const Icon(PhosphorIconsRegular.key, size: 20, color: C.muted),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _hide = !_hide),
                icon: Icon(_hide ? PhosphorIconsRegular.eye : PhosphorIconsRegular.eyeSlash, color: C.muted),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Токен выдаётся в профиле ERP. Он проверяется и хранится на сервере Scope зашифрованным; '
            'Scope только читает задачи, где вы исполнитель, и ничего не меняет в ERP.',
            style: TextStyle(color: C.muted, fontSize: 12, height: 1.35),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              const Icon(PhosphorIconsRegular.warningCircle, color: C.urgent, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_error!, style: const TextStyle(color: C.urgent))),
            ]),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: C.accent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _busy ? null : _connect,
              child: _busy
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: C.onAccent))
                  : Text(reconnecting ? 'Сохранить токен' : 'Подключить',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: C.bg2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: C.borderLight),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
}
