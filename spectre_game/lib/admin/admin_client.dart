import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../data/api.dart';

/// Yönetici oturumu (oyuncu oturumundan ayrı). Token yalnız bellekte tutulur.
class AdminClient extends ChangeNotifier {
  final api = Api();
  String? username;
  String? role;

  bool get loggedIn => api.token != null;

  Future<void> login(String user, String password) async {
    final r = await api.post('/admin/api/v1/login', {'username': user, 'password': password});
    api.token = r['token'] as String;
    username = r['username'] as String?;
    role = r['role'] as String?;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.post('/admin/api/v1/logout');
    } catch (_) {}
    api.token = null;
    username = null;
    role = null;
    notifyListeners();
  }

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? q]) => _guard(api.get('/admin/api/v1$path', q));
  Future<Map<String, dynamic>> post(String path, [Object? body]) => _guard(api.post('/admin/api/v1$path', body));
  Future<Map<String, dynamic>> put(String path, Object body) => _guard(api.put('/admin/api/v1$path', body));

  /// Görsel yükler, sunucudaki adresini döner (`/uploads/...`).
  Future<String> upload(Uint8List bytes) async => '${(await _guard(api.upload('/admin/api/v1/upload', bytes)))['url']}';

  Future<Map<String, dynamic>> _guard(Future<Map<String, dynamic>> f) async {
    try {
      return await f;
    } on ApiException catch (e) {
      if (e.status == 401) {
        api.token = null;
        notifyListeners();
      }
      rethrow;
    }
  }
}

class AdminScope extends InheritedNotifier<AdminClient> {
  const AdminScope({super.key, required AdminClient admin, required super.child}) : super(notifier: admin);
  static AdminClient of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AdminScope>()!.notifier!;
  static AdminClient read(BuildContext context) => context.getInheritedWidgetOfExactType<AdminScope>()!.notifier!;
}
