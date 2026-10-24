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
    // Шаблон без интерполяции Dart: подставляем пути явно, $-переменные — PowerShell.
    final ps = r'''
$ErrorActionPreference = "Stop"
$install = "__INSTALL__"
$source = "__SOURCE__"
$work = "__WORK__"
$log = Join-Path $install "logs\update.log"
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
function Log($m) { Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format s), $m) }
Log "update: waiting for Scope to exit"
# Ждём все окна Scope из папки установки (их может быть несколько), потом закрываем оставшиеся.
$deadline = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $deadline) {
  $running = Get-CimInstance Win32_Process -Filter "Name='Scope.exe'" | Where-Object { $_.ExecutablePath -like "$install*" }
  if (-not $running) { break }
  Start-Sleep -Milliseconds 300
}
Get-CimInstance Win32_Process -Filter "Name='Scope.exe'" | Where-Object { $_.ExecutablePath -like "$install*" } | ForEach-Object {
  Log "update: closing leftover pid $($_.ProcessId)"; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Milliseconds 500
$ok = $false
for ($i = 1; $i -le 10 -and -not $ok; $i++) {
  try { Copy-Item -Path (Join-Path $source "*") -Destination $install -Recurse -Force; $ok = $true; Log "update: files copied (try $i)" }
  catch { Log "update: copy failed (try $i): $($_.Exception.Message)"; Start-Sleep -Seconds 1 }
}
# Через проводник — как будто открыл пользователь (своя среда, без наследования от скрипта).
Start-Process explorer.exe -ArgumentList ('"' + (Join-Path $install "Scope.exe") + '"')
Log ("update: relaunched, ok=" + $ok)
if ($ok) { Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue }
'''
        .replaceAll('__INSTALL__', installDir)
        .replaceAll('__SOURCE__', source)
        .replaceAll('__WORK__', work);
    await script.writeAsString(ps);
    await Process.start(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', script.path],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }
}
