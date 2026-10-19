import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'store.dart';

/// Сборка, опубликованная на сервере (`manage.py scope_publish_app`).
class AppUpdate {
  AppUpdate({required this.version, required this.build, required this.url, required this.size, required this.notes});

  final String version;
  final int build;
  final String url;
  final int size;
  final String notes;

  factory AppUpdate.fromJson(Map<String, dynamic> j) => AppUpdate(
        version: '${j['version']}',
        build: (j['build'] ?? 0) as int,
        url: '${j['url']}',
        size: (j['size'] ?? 0) as int,
        notes: '${j['notes'] ?? ''}',
      );
}

/// Проверка и установка обновлений: Android — APK через системный установщик,
/// Windows — архив распаковывается и подменяет файлы после выхода приложения.
class Updater {
  static String? get platform => Platform.isAndroid
      ? 'android'
      : Platform.isWindows
          ? 'windows'
          : null;

  static PackageInfo? _info;

  static Future<PackageInfo> current() async => _info ??= await PackageInfo.fromPlatform();

  static Future<String> currentLabel() async {
    final i = await current();
    return '${i.version} (${i.buildNumber})';
  }

  /// Новая сборка, если она есть; null — уже последняя версия.
  static Future<AppUpdate?> check(AppStore store) async {
    final p = platform;
    if (p == null) return null;
    final data = await store.api.get('app/latest/', {'platform': p});
    if (data == null) return null;
    final update = AppUpdate.fromJson(data as Map<String, dynamic>);
    final mine = int.tryParse((await current()).buildNumber) ?? 0;
    return update.build > mine ? update : null;
  }

  /// Скачать в temp. [onProgress] — доля 0..1. Сертификат домашнего сервера
  /// принимается через общий HttpOverrides приложения.
  static Future<File> download(AppStore store, AppUpdate u, void Function(double) onProgress) async {
    final url = store.api.mediaUrl(u.url)!;
    final dir = await Directory.systemTemp.createTemp('scope-update');
    final file = File('${dir.path}${Platform.pathSeparator}${Uri.parse(url).pathSegments.last}');
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('Сервер ответил ${res.statusCode}');
      final total = res.contentLength > 0 ? res.contentLength : u.size;
      final sink = file.openWrite();
      var got = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
      await sink.close();
      return file;
    } finally {
      client.close();
    }
  }

  static Future<void> install(File file) async {
    if (Platform.isAndroid) {
      final r = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
      if (r.type != ResultType.done) throw Exception('Установщик не открылся: ${r.message}');
      return;
    }
    if (Platform.isWindows) return _installWindows(file);
  }

  /// Распаковать рядом, а подменить файлы может только внешний процесс —
  /// пока Scope.exe запущен, он заблокирован. Скрипт ждёт выхода, копирует и запускает.
  static Future<void> _installWindows(File zip) async {
    final work = zip.parent.path;
    final unpacked = '$work\\unpacked';
    await extractFileToDisk(zip.path, unpacked);
    // В архиве папка Scope\ с файлами приложения.
    final inner = Directory('$unpacked\\Scope');
    final source = await inner.exists() ? inner.path : unpacked;
    final installDir = File(Platform.resolvedExecutable).parent.path;
    final script = File('$work\\apply.ps1');
    await script.writeAsString('''
\$ErrorActionPreference = "Stop"
Wait-Process -Id $pid -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
Copy-Item -Path "$source\\*" -Destination "$installDir" -Recurse -Force
Start-Process -FilePath "$installDir\\Scope.exe" -WorkingDirectory "$installDir"
Remove-Item -Path "$work" -Recurse -Force -ErrorAction SilentlyContinue
''');
    await Process.start(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', script.path],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }
}
