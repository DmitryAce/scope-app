import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Короткий журнал запусков: откуда взялся вход. Пишется в папку настроек
  /// и рядом с exe — чтобы найти его, даже если папку настроек не удалось определить.
  /// Сам токен не пишется.
  static Future<void> log(String line) async {
    final stamp = '${DateTime.now().toIso8601String()} pid=$pid $line';
    String? supportPath;
    try {
      supportPath = (await getApplicationSupportDirectory()).path;
      await _append(File('$supportPath${Platform.pathSeparator}startup.log'), stamp);
    } catch (e) {
      supportPath = 'ERROR $e';
    }
    if (Platform.isWindows) {
      try {
        final dir = File(Platform.resolvedExecutable).parent.path;
        await _append(File([dir, 'logs', 'startup.log'].join(Platform.pathSeparator)), '$stamp | support=$supportPath');
      } catch (_) {}
    }
  }

  static Future<void> _append(File file, String line) async {
    await file.parent.create(recursive: true);
    final old = await file.exists() ? await file.readAsLines() : <String>[];
    final lines = [...old.skip(old.length > 100 ? old.length - 100 : 0), line];
    await file.writeAsString('${lines.join('\n')}\n');
  }

  /// Windows: если плагин вернул пустые настройки, прочитать файл напрямую
  /// из %APPDATA%/DrXeno/Scope и вернуть значения в SharedPreferences.
  static Future<bool> restorePrefsIfEmpty(SharedPreferences prefs) async {
    if (!Platform.isWindows || prefs.getKeys().isNotEmpty) return false;
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData == null) return false;
      final file = File([appData, 'DrXeno', 'Scope', 'shared_preferences.json'].join(Platform.pathSeparator));
      if (!await file.exists()) return false;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in data.entries) {
        if (!key.startsWith('flutter.')) continue;
        final k = key.substring('flutter.'.length);
        switch (value) {
          case String v:
            await prefs.setString(k, v);
          case bool v:
            await prefs.setBool(k, v);
          case int v:
            await prefs.setInt(k, v);
          case double v:
            await prefs.setDouble(k, v);
          case List v:
            await prefs.setStringList(k, v.map((e) => '$e').toList());
        }
      }
      await log('prefs were empty, restored ${data.length} keys from ${file.path}');
      return true;
    } catch (e) {
      await log('prefs restore failed: $e');
      return false;
    }
  }
}
