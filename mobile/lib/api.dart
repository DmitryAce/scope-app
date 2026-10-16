import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http_parser/http_parser.dart';

/// Откуда ходить на сервер.
enum BackendMode { auto, local, remote }

/// Домашний сервер в локалке (быстро, самоподписанный сертификат) и он же снаружи.
/// Для тестовых сборок адреса можно подменить: `--dart-define=SCOPE_LOCAL=...`.
const defaultLocalUrl = String.fromEnvironment('SCOPE_LOCAL', defaultValue: 'https://192.168.1.93:1230');
const defaultRemoteUrl =
    String.fromEnvironment('SCOPE_REMOTE', defaultValue: 'https://scope.drxeno.netcraze.pro');

class ApiException implements Exception {
  final String code;
  final String message;
  final int status;

  const ApiException(this.code, this.message, [this.status = 0]);

  bool get isAuth => status == 401;
  bool get isNetwork => status == 0;

  @override
  String toString() => message;
}

class ScopeApi {
  ScopeApi({
    required this.localUrl,
    required this.remoteUrl,
    this.mode = BackendMode.auto,
    this.token,
  });

  String localUrl;
  String remoteUrl;
  BackendMode mode;
  String? token;

  /// Адрес, на который сейчас идут запросы; null — ещё не выбран.
  String? activeBase;

  bool get onLocal => activeBase != null && activeBase == _norm(localUrl);

  late final http.Client _http = IOClient(_ioClient());

  HttpClient _ioClient() {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    // Свой сервер в локалке отдаёт самоподписанный сертификат — верим только ему.
    c.badCertificateCallback = (cert, host, port) => host == Uri.parse(localUrl).host;
    return c;
  }

  static String _norm(String url) => url.trim().replaceAll(RegExp(r'/+$'), '');

  /// Дома по Wi-Fi локальный сервер отвечает за миллисекунды — пробуем его первым.
  Future<String> resolve({bool force = false}) async {
    if (!force && activeBase != null) return activeBase!;
    switch (mode) {
      case BackendMode.local:
        activeBase = _norm(localUrl);
      case BackendMode.remote:
        activeBase = _norm(remoteUrl);
      case BackendMode.auto:
        activeBase = await _probe(_norm(localUrl)) ? _norm(localUrl) : _norm(remoteUrl);
    }
    return activeBase!;
  }

  Future<bool> _probe(String base) async {
    try {
      final res = await _http
          .get(Uri.parse('$base/api/v2/'))
          .timeout(const Duration(milliseconds: 1500));
      // Без токена API честно отвечает 401 JSON-ом — значит, сервер живой.
      return (res.headers['content-type'] ?? '').contains('json');
    } catch (_) {
      return false;
    }
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> get(String path, [Map<String, String>? query]) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body);

  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(String method, String path,
      {Map<String, String>? query, Object? body, bool raw = false, bool retried = false}) async {
    final base = await resolve();
    final uri = Uri.parse('$base/api/v2/$path').replace(queryParameters: query);
    final req = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);

    http.Response res;
    try {
      res = await http.Response.fromStream(
          await _http.send(req).timeout(const Duration(seconds: 15)));
    } on SocketException {
      // Ушли из дома или вернулись: перевыбираем сервер и пробуем ещё раз.
      if (!retried && mode == BackendMode.auto) {
        await resolve(force: true);
        return _send(method, path, query: query, body: body, raw: raw, retried: true);
      }
      throw const ApiException('network', 'Нет связи с сервером');
    } on TimeoutException {
      if (!retried && mode == BackendMode.auto && method == 'GET') {
        await resolve(force: true);
        return _send(method, path, query: query, body: body, raw: raw, retried: true);
      }
      throw const ApiException('network', 'Сервер не отвечает');
    } on HandshakeException {
      throw const ApiException('network', 'Не удалось установить защищённое соединение');
    } on http.ClientException catch (e) {
      throw ApiException('network', 'Сеть: ${e.message}');
    }

    dynamic json;
    try {
      json = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      json = null;
    }
    if (res.statusCode >= 400 || json == null) {
      final err = json is Map ? json['error'] : null;
      if (err is Map) {
        throw ApiException(
            '${err['code']}', '${err['message'] ?? 'Ошибка ${res.statusCode}'}', res.statusCode);
      }
      throw ApiException('http', 'Сервер ответил ${res.statusCode}', res.statusCode);
    }
    if (raw) return json;
    return json is Map ? json['data'] : json;
  }

  Future<List<Map<String, dynamic>>> getAll(String path, Map<String, String> query) async {
    final out = <Map<String, dynamic>>[];
    var offset = 0;
    const limit = 500;
    while (true) {
      final page = await _send('GET', path,
          query: {...query, 'limit': '$limit', 'offset': '$offset'}, raw: true) as Map;
      final data = (page['data'] as List).cast<Map<String, dynamic>>();
      out.addAll(data);
      final count = (page['meta']?['count'] ?? data.length) as int;
      offset += limit;
      if (offset >= count || data.isEmpty || offset >= 3000) break;
    }
    return out;
  }

  /// Аватарка проекта: картинку уже уменьшил image_picker.
  Future<dynamic> uploadAvatar(int projectId, List<int> bytes, String filename) async {
    final base = await resolve();
    final ext = filename.toLowerCase().split('.').last;
    final type = switch (ext) { 'png' => 'png', 'webp' => 'webp', _ => 'jpeg' };
    final req = http.MultipartRequest('POST', Uri.parse('$base/api/v2/projects/$projectId/avatar/'))
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: 'avatar.$ext', contentType: MediaType('image', type)));
    final res = await http.Response.fromStream(
        await _http.send(req).timeout(const Duration(seconds: 30)));
    final json = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      final err = json is Map ? json['error'] : null;
      throw ApiException('${err?['code'] ?? 'http'}', '${err?['message'] ?? 'Ошибка ${res.statusCode}'}',
          res.statusCode);
    }
    return json['data'];
  }

  /// Полный адрес картинки на текущем сервере.
  String? mediaUrl(String? path) {
    if (path == null || path.isEmpty || activeBase == null) return null;
    return path.startsWith('http') ? path : '$activeBase$path';
  }

  Future<String> login(String username, String password) async {
    final data = await post('auth/login/', {
      'username': username,
      'password': password,
      'device': 'Android',
    });
    return (data as Map)['token'] as String;
  }
}
