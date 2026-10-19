import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Вход переживает перезагрузку: токен лежит и в настройках, и в защищённом
/// хранилище системы (Windows — «Диспетчер учётных данных», Android — Keystore).
/// Если при старте одно из них не прочиталось, вход берётся из другого.
class Session {
  static const _secure = FlutterSecureStorage();

  static Future<(String?, String?)> readBackup() async {
    try {
      return (await _secure.read(key: 'token'), await _secure.read(key: 'username'));
    } catch (_) {
      return (null, null);
    }
  }

  static Future<void> save(String token, String username) async {
    try {
      await _secure.write(key: 'token', value: token);
      await _secure.write(key: 'username', value: username);
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      await _secure.delete(key: 'token');
      await _secure.delete(key: 'username');
    } catch (_) {}
  }

  /// Короткий журнал запусков: откуда взялся вход. Нужен, чтобы поймать,
  /// если приложение снова «забудет» вход. Сам токен не пишется.
  static Future<void> log(String line) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}startup.log');
      final old = await file.exists() ? await file.readAsLines() : <String>[];
      final lines = [...old.skip(old.length > 60 ? old.length - 60 : 0), '${DateTime.now().toIso8601String()} $line'];
      await file.writeAsString('${lines.join('\n')}\n');
    } catch (_) {}
  }
}
