import 'dart:io';

import 'package:spectre_server/spectre_server.dart';

/// Kullanım:
///   dart run bin/server.dart --port 8080 --data ./data --web ../build/web
///
/// Ortam değişkenleri (ilk açılışta yönetici hesabı için):
///   SPECTRE_ADMIN_USER, SPECTRE_ADMIN_PASSWORD (en az 8 karakter)
///   Verilmezse rastgele şifre üretilir ve data/admin-ilk-sifre.txt dosyasına yazılır.
///   SPECTRE_CORS_ORIGIN: Uygulama başka bir adresten sunuluyorsa izin verilecek köken.
Future<void> main(List<String> args) async {
  String? opt(String name, [String? def]) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : def;
  }

  final port = int.tryParse(opt('port', Platform.environment['PORT'] ?? '8080')!) ?? 8080;
  final dataDir = Directory(opt('data', 'data')!);
  final web = opt('web');
  await dataDir.create(recursive: true);

  final server = SpectreServer(
    store: Store(File('${dataDir.path}/spectre-data.json')),
    webRoot: web == null ? null : Directory(web),
    corsOrigin: Platform.environment['SPECTRE_CORS_ORIGIN'],
  );
  await server.start(
    port: port,
    address: InternetAddress(opt('host', '0.0.0.0')!),
    adminUser: Platform.environment['SPECTRE_ADMIN_USER'],
    adminPassword: Platform.environment['SPECTRE_ADMIN_PASSWORD'],
  );
  stdout.writeln('SPECTRE sunucusu çalışıyor: http://localhost:${server.port}');

  Future<void> shutdown(ProcessSignal s) async {
    stdout.writeln('Kapatılıyor…');
    await server.stop();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(shutdown);
}
