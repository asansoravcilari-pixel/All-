import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Derleme anında sabit sunucu adresi (isteğe bağlı):
/// `--dart-define=SPECTRE_API=https://oyun.alanadin.com`
const _apiOverride = String.fromEnvironment('SPECTRE_API');

/// Yönetim panelinden gelen adres ayarları (`/api/v1/config` → apiBase, wsUrl, endpoints).
abstract final class ApiConfig {
  static String apiBase = '';
  static String wsUrl = '';
  static Map<String, String> endpoints = Map.of(defaultEndpoints);

  static const defaultEndpoints = {
    'authRegister': '/api/v1/auth/register',
    'authLogin': '/api/v1/auth/login',
    'authGuest': '/api/v1/auth/guest',
    'authLogout': '/api/v1/auth/logout',
    'me': '/api/v1/me',
    'meDaily': '/api/v1/me/daily',
    'meAvatar': '/api/v1/me/avatar',
    'roomList': '/room/api/v1/room',
    'roomDetail': '/room/api/v1/room/{roomId}',
    'roomPlayer': '/room/api/v1/roomPlayer',
    'user': '/user/api/v1/user/{userId}',
    'gifts': '/api/v1/gifts',
    'packages': '/api/v1/market/packages',
    'orders': '/api/v1/orders',
    'dmThreads': '/api/v1/dm',
    'dmThread': '/api/v1/dm/{userId}',
    'notifications': '/api/v1/notifications',
    'notificationsRead': '/api/v1/notifications/read',
    'ws': '/ws',
  };

  static void apply(Map<String, dynamic> cfg) {
    apiBase = '${cfg['apiBase'] ?? ''}';
    wsUrl = '${cfg['wsUrl'] ?? ''}';
    final eps = cfg['endpoints'];
    endpoints = {
      ...defaultEndpoints,
      if (eps is Map)
        for (final e in eps.entries)
          if (e.key is String && e.value is String) e.key as String: e.value as String,
    };
  }

  /// Anahtarın yolunu parametreleriyle doldurur: `ep('user', {'userId': '7'})`.
  static String ep(String key, [Map<String, String> params = const {}]) {
    var p = endpoints[key] ?? defaultEndpoints[key] ?? '/';
    params.forEach((k, v) => p = p.replaceAll('{$k}', Uri.encodeComponent(v)));
    return p;
  }
}

/// Uygulamanın sunulduğu adres; yönetim panelinde başka adres verildiyse o.
Uri apiBase() {
  if (_apiOverride.isNotEmpty) return Uri.parse(_apiOverride);
  if (ApiConfig.apiBase.startsWith('http')) return Uri.parse(ApiConfig.apiBase);
  final b = Uri.base;
  return Uri(scheme: b.scheme, host: b.host, port: b.hasPort ? b.port : null);
}

/// Göreli görsel yollarını (`/uploads/...`) tam adrese çevirir.
String mediaUrl(String url) {
  if (url.isEmpty || url.startsWith('http')) return url;
  return apiBase().resolve(url).toString();
}

Uri wsUri(String token) {
  if (ApiConfig.wsUrl.startsWith('ws')) {
    final u = Uri.parse(ApiConfig.wsUrl);
    return u.replace(queryParameters: {...u.queryParameters, 'token': token});
  }
  final b = apiBase();
  return b.replace(
    scheme: b.scheme == 'https' ? 'wss' : 'ws',
    path: ApiConfig.ep('ws'),
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

  /// Ham dosya yükleme (görsel).
  Future<Map<String, dynamic>> upload(String path, Uint8List bytes) =>
      _send('POST', path, raw: bytes);

  Future<Map<String, dynamic>> _send(String method, String path,
      {Object? body, Map<String, String>? query, Uint8List? raw}) async {
    final uri = apiBase().replace(path: path, queryParameters: query == null || query.isEmpty ? null : query);
    final req = http.Request(method, uri);
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (raw != null) {
      req.headers['Content-Type'] = 'application/octet-stream';
      req.bodyBytes = raw;
    } else if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 20)));
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
