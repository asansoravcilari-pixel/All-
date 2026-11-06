import 'dart:convert';

import 'package:http/http.dart' as http;

/// Sunucu adresi. Varsayılan: uygulamanın sunulduğu adres (aynı köken).
/// Farklı bir sunucu için: `--dart-define=SPECTRE_API=https://oyun.alanadin.com`
const _apiOverride = String.fromEnvironment('SPECTRE_API');

Uri apiBase() {
  if (_apiOverride.isNotEmpty) return Uri.parse(_apiOverride);
  final b = Uri.base;
  return Uri(scheme: b.scheme, host: b.host, port: b.hasPort ? b.port : null);
}

Uri wsUri(String token) {
  final b = apiBase();
  return b.replace(
    scheme: b.scheme == 'https' ? 'wss' : 'ws',
    path: '/ws',
    queryParameters: {'token': token},
  );
}

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Basit JSON istemcisi.
class Api {
  Api({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;
  String? token;

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? query]) => _send('GET', path, query: query);
  Future<Map<String, dynamic>> post(String path, [Object? body]) => _send('POST', path, body: body ?? const {});
  Future<Map<String, dynamic>> put(String path, Object body) => _send('PUT', path, body: body);
  Future<Map<String, dynamic>> patch(String path, Object body) => _send('PATCH', path, body: body);

  Future<Map<String, dynamic>> _send(String method, String path, {Object? body, Map<String, String>? query}) async {
    final uri = apiBase().replace(path: path, queryParameters: query == null || query.isEmpty ? null : query);
    final req = http.Request(method, uri);
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 15)));
    } catch (_) {
      throw ApiException(0, 'Sunucuya ulaşılamıyor');
    }
    Map<String, dynamic> data = const {};
    if (res.body.isNotEmpty) {
      try {
        final d = jsonDecode(utf8.decode(res.bodyBytes));
        if (d is Map) data = d.cast<String, dynamic>();
      } catch (_) {
        throw ApiException(res.statusCode, 'Sunucudan beklenmeyen yanıt');
      }
    }
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, '${data['error'] ?? 'İstek başarısız (${res.statusCode})'}');
    }
    return data;
  }
}
