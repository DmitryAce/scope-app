import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme.dart';
import '../updater.dart';
import 'common.dart';

/// Окно обновления: проверка → «что нового» → скачивание с прогрессом → установка.
Future<void> showUpdateDialog(BuildContext context, {AppUpdate? known}) {
  return showDialog(context: context, builder: (_) => _UpdateDialog(known: known));
}

enum _Stage { checking, latest, available, downloading, installing, failed }

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({this.known});

  final AppUpdate? known;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _Stage _stage = _Stage.checking;
  AppUpdate? _update;
  double _progress = 0;
  String _current = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final store = StoreScope.read(context);
    _current = await Updater.currentLabel();
    if (widget.known != null) {
      setState(() {
        _update = widget.known;
        _stage = _Stage.available;
      });
      return;
    }
    try {
      final u = await Updater.check(store);
      if (!mounted) return;
      setState(() {
        _update = u;
        _stage = u == null ? _Stage.latest : _Stage.available;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.failed;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _install() async {
    setState(() {
      _stage = _Stage.downloading;
      _progress = 0;
    });
    try {
      final file = await Updater.download(StoreScope.read(context), _update!, (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      setState(() => _stage = _Stage.installing);
      await Updater.install(file);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.failed;
          _error = '$e';
        });
      }
    }
  }

  String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ';

  @override
  Widget build(BuildContext context) {
    final u = _update;
    final (IconData icon, Color color, String title) = switch (_stage) {
      _Stage.checking => (PhosphorIconsRegular.arrowsClockwise, C.text2, 'Проверяю обновления'),
      _Stage.latest => (PhosphorIconsRegular.checkCircle, C.low, 'Последняя версия'),
      _Stage.available => (PhosphorIconsRegular.downloadSimple, C.accent2, 'Доступна версия ${u!.version}'),
      _Stage.downloading => (PhosphorIconsRegular.downloadSimple, C.accent2, 'Скачиваю ${u!.version}'),
      _Stage.installing => (PhosphorIconsRegular.package, C.accent2, 'Устанавливаю'),
      _Stage.failed => (PhosphorIconsRegular.warningCircle, C.urgent, 'Не получилось'),
    };

    return AlertDialog(
      icon: Icon(icon, color: color, size: 34),
      title: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Сейчас установлена $_current', style: const TextStyle(color: C.muted, fontSize: 13)),
          if (_stage == _Stage.checking) ...[
            const SizedBox(height: 18),
            const LinearProgressIndicator(),
          ],
          if (_stage == _Stage.available && u != null) ...[
            const SizedBox(height: 14),
            if (u.notes.trim().isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: C.bg3, borderRadius: BorderRadius.circular(12)),
                child: Text(u.notes, style: const TextStyle(height: 1.4)),
              ),
            if (u.size > 0) ...[
              const SizedBox(height: 8),
              Text(_mb(u.size), style: const TextStyle(color: C.muted, fontSize: 12)),
            ],
          ],
          if (_stage == _Stage.downloading) ...[
            const SizedBox(height: 18),
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            const SizedBox(height: 6),
            Text('${(_progress * 100).round()}%', style: const TextStyle(color: C.text2, fontSize: 12)),
          ],
          if (_stage == _Stage.installing) ...[
            const SizedBox(height: 12),
            const Text('Сейчас откроется установщик — подтвердите обновление.',
                textAlign: TextAlign.center, style: TextStyle(color: C.text2)),
          ],
          if (_stage == _Stage.failed && _error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: C.text2, fontSize: 13)),
          ],
        ]),
      ),
      actions: [
        if (_stage != _Stage.downloading && _stage != _Stage.installing)
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть')),
        if (_stage == _Stage.available)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.accent),
            onPressed: _install,
            child: const Text('Обновить', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        if (_stage == _Stage.failed)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.accent),
            onPressed: () {
              setState(() => _stage = _Stage.checking);
              _check();
            },
            child: const Text('Ещё раз'),
          ),
      ],
    );
  }
}
