import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:spectre_core/spectre_core.dart';
import 'package:spectre_server/spectre_server.dart';
import 'package:test/test.dart';

late SpectreServer server;
late String base;

Future<(int, Map<String, dynamic>)> call(String method, String path, {Object? body, String? token}) async {
  final c = HttpClient();
  try {
    final req = await c.openUrl(method, Uri.parse('$base$path'));
    if (token != null) req.headers.set('Authorization', 'Bearer $token');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await utf8.decoder.bind(res).join();
    return (res.statusCode, (text.isEmpty ? <String, dynamic>{} : jsonDecode(text)) as Map<String, dynamic>);
  } finally {
    c.close();
  }
}

class WsProbe {
  WsProbe(this.ws) {
    ws.listen((d) => seen.add(jsonDecode(d as String) as Map<String, dynamic>));
  }
  final WebSocket ws;
  final List<Map<String, dynamic>> seen = [];

  static Future<WsProbe> connect(String token) async =>
      WsProbe(await WebSocket.connect('${base.replaceFirst('http', 'ws')}/ws?token=$token'));

  void send(Map<String, dynamic> m) => ws.add(jsonEncode(m));

  /// Gelen mesajlar arasında [event] olayını bekler (sırayla tüketir).
  Future<Map<String, dynamic>> next(String event, {bool Function(Map<String, dynamic> data)? where}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      for (final m in seen) {
        final data = (m['data'] as Map).cast<String, dynamic>();
        if (m['event'] == event && (where == null || where(data))) {
          seen.remove(m);
          return data;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('bekleniyordu: $event, görülen: ${seen.map((m) => m['event']).toList()}');
  }
}

void main() {
  setUpAll(() async {
    server = SpectreServer(store: Store(null), tickInterval: const Duration(milliseconds: 50));
    await server.start(port: 0, address: InternetAddress.loopbackIPv4, adminUser: 'patron', adminPassword: 'cok-gizli-123');
    base = 'http://127.0.0.1:${server.port}';
  });
  tearDownAll(() => server.stop());

  test('kimlik doğrulaması olmadan oda listesi alınamaz', () async {
    final (s, _) = await call('GET', '/room/api/v1/room');
    expect(s, 401);
  });

  test('admin girişi: yanlış şifre reddedilir, doğru şifre token verir', () async {
    final (bad, _) = await call('POST', '/admin/api/v1/login', body: {'username': 'patron', 'password': 'yanlis'});
    expect(bad, 401);
    final (ok, j) = await call('POST', '/admin/api/v1/login', body: {'username': 'patron', 'password': 'cok-gizli-123'});
    expect(ok, 200);
    expect(j['token'], isA<String>());
    expect(j['role'], 'owner');
    final (noAuth, _) = await call('GET', '/admin/api/v1/dashboard');
    expect(noAuth, 401);
  });

  test('tam akış: kayıt → masa → oturma → seat.updated → roomPlayer → hediye → yasak', () async {
    final (_, a) = await call('POST', '/admin/api/v1/login', body: {'username': 'patron', 'password': 'cok-gizli-123'});
    final admin = a['token'] as String;

    // Admin: masa ve hediye oluştur
    final (rs, room) = await call('POST', '/admin/api/v1/rooms', token: admin, body: {'name': 'Neon'});
    expect(rs, 200);
    final roomId = room['id'] as String;
    final (_, gift) = await call('POST', '/admin/api/v1/gifts', token: admin, body: {'name': 'Gül', 'emoji': '🌹', 'price': 10});

    // Oyuncular
    final (r1, u1) = await call('POST', '/api/v1/auth/register', body: {'username': 'ada', 'password': 'sifre-1234'});
    expect(r1, 200);
    final (dup, _) = await call('POST', '/api/v1/auth/register', body: {'username': 'ADA', 'password': 'sifre-1234'});
    expect(dup, 409);
    final (_, u2) = await call('POST', '/api/v1/auth/register', body: {'username': 'mert', 'password': 'sifre-5678'});
    final t1 = u1['token'] as String, t2 = u2['token'] as String;
    final id1 = (u1['me'] as Map)['id'] as String, id2 = (u2['me'] as Map)['id'] as String;

    final (ls, login) = await call('POST', '/api/v1/auth/login', body: {'username': 'ada', 'password': 'sifre-1234'});
    expect(ls, 200);
    expect(login['token'], isNotEmpty);

    // Oda listesi
    final (_, list) = await call('GET', '/room/api/v1/room', token: t1);
    final names = [for (final r in list['items'] as List) r['name']];
    expect(names, containsAll(['Masa 1', 'Masa 2', 'Masa 3', 'Masa 4', 'Neon']));
    expect((list['items'] as List).every((r) => r['gameType'] == 'bottle' && r['capacity'] == 12), isTrue);

    final w1 = await WsProbe.connect(t1);
    final w2 = await WsProbe.connect(t2);
    await w1.next('hello');
    await w2.next('hello');
    w1.send({'op': 'join', 'roomId': roomId, 'seat': 0});
    await w1.next(Ev.snapshot);
    w2.send({'op': 'subscribe', 'channel': roomChannel(roomId)});
    await w2.next(Ev.snapshot);
    w2.send({'op': 'join', 'roomId': roomId, 'seat': 5});
    final seat = await w1.next(Ev.seatUpdated, where: (d) => d['index'] == 5);
    expect(seat['playerId'], id2);
    expect(seat['name'], 'mert');

    // REST sözleşmesi
    final (_, detail) = await call('GET', '/room/api/v1/room/$roomId', token: t1);
    expect(detail['inGamePlayers'], 2);
    expect(detail['countInGamePlayers'], 2);
    expect(detail['capacity'], 12);
    final (_, players) = await call('GET', '/room/api/v1/roomPlayer?userId=$id1&limit=12&status=active', token: t1);
    final items = (players['items'] as List).cast<Map<String, dynamic>>();
    expect(items.map((e) => e['index']), [0, 5]);
    expect(items.every((e) => e['isPlaying'] == true && e['leaveAt'] == null), isTrue);
    final (_, pub) = await call('GET', '/user/api/v1/user/$id2', token: t1);
    expect(pub['isOnline'], isTrue);

    // Hediye: coin düşer, me.updated gelir, iki tarafta gift.sent
    w1.send({'op': 'gift', 'toSeat': 5, 'giftId': gift['id']});
    final g = await w2.next(Ev.gift);
    expect(g['toSeat'], 5);
    final me = await w1.next(Ev.me);
    expect(me['coins'], 200 - 10);

    // Sohbet
    w2.send({'op': 'chat', 'text': 'selam'});
    final chat = await w1.next(Ev.chat, where: (d) => d['text'] == 'selam');
    expect(chat['name'], 'mert');

    // Admin: masa listesinde iki oyuncu görünür
    final (_, rooms) = await call('GET', '/admin/api/v1/rooms', token: admin);
    expect((rooms['items'] as List).firstWhere((r) => r['id'] == roomId)['countInGamePlayers'], 2);

    // Toplu hediye: masadaki diğer herkese
    w1.send({'op': 'giftAll', 'giftId': gift['id']});
    await w2.next(Ev.gift);
    final me2 = await w1.next(Ev.me);
    expect(me2['coins'], 200 - 10 - 10);

    // Admin: yasakla → masadan kalkar, seat.vacated yayınlanır, giriş reddedilir
    final (bs, _) = await call('POST', '/admin/api/v1/users/$id2/action', token: admin, body: {'action': 'status', 'status': 'banned'});
    expect(bs, 200);
    final vac = await w1.next(Ev.seatVacated);
    expect(vac['index'], 5);
    final (bl, _) = await call('POST', '/api/v1/auth/login', body: {'username': 'mert', 'password': 'sifre-5678'});
    expect(bl, 403);

    // Denetim kaydı
    final (_, sec) = await call('GET', '/admin/api/v1/security', token: admin);
    expect((sec['audit'] as List).any((e) => '${e['action']}'.contains('banned')), isTrue);

    await w1.ws.close();
    await w2.ws.close();
  });

  test('sipariş: oluşturma → admin onayı → coin yüklenir → iade', () async {
    final (_, a) = await call('POST', '/admin/api/v1/login', body: {'username': 'patron', 'password': 'cok-gizli-123'});
    final admin = a['token'] as String;
    final (_, pkg) = await call('POST', '/admin/api/v1/packages',
        token: admin, body: {'name': 'Başlangıç', 'coins': 100, 'priceKurus': 2999, 'bonusPercent': 10});
    final (_, u) = await call('POST', '/api/v1/auth/register', body: {'username': 'elif', 'password': 'sifre-0000'});
    final t = u['token'] as String;
    final (os, order) = await call('POST', '/api/v1/orders', token: t, body: {'packageId': pkg['id'], 'provider': 'manual'});
    expect(os, 200);
    final id = (order['order'] as Map)['id'];
    final (_, before) = await call('GET', '/api/v1/me', token: t);
    await call('POST', '/admin/api/v1/orders/$id/action', token: admin, body: {'action': 'approve'});
    final (_, after) = await call('GET', '/api/v1/me', token: t);
    expect(after['coins'], (before['coins'] as int) + 110);
    final (_, eco) = await call('GET', '/admin/api/v1/economy?days=7', token: admin);
    expect(eco['revenue'], 2999);
    await call('POST', '/admin/api/v1/orders/$id/action', token: admin, body: {'action': 'refund'});
    final (_, refunded) = await call('GET', '/api/v1/me', token: t);
    expect(refunded['coins'], before['coins']);
  });

  test('ayarlar: bakım modu masaya girişi engeller', () async {
    final (_, a) = await call('POST', '/admin/api/v1/login', body: {'username': 'patron', 'password': 'cok-gizli-123'});
    final admin = a['token'] as String;
    await call('PUT', '/admin/api/v1/settings', token: admin, body: {'settings': {'maintenance': true}});
    final (_, cfg) = await call('GET', '/api/v1/config');
    expect(cfg['maintenance'], isTrue);
    final (_, u) = await call('POST', '/api/v1/auth/register', body: {'username': 'kaan', 'password': 'sifre-9999'});
    final (_, rooms) = await call('GET', '/room/api/v1/room', token: u['token'] as String);
    final w = await WsProbe.connect(u['token'] as String);
    await w.next('hello');
    w.send({'op': 'join', 'roomId': (rooms['items'] as List).first['id']});
    final err = await w.next(Ev.error);
    expect(err['message'], contains('bakım'));
    await call('PUT', '/admin/api/v1/settings', token: admin, body: {'settings': {'maintenance': false}});
    await w.ws.close();
  });

  test('DM: gönderme, okunmamış sayısı, çeviri ve bildirimler', () async {
    // Sahte çeviri servisi (LibreTranslate biçimi)
    final tr = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    tr.listen((req) async {
      final b = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'translatedText': '[${b['target']}] ${b['q']}',
        'detectedLanguage': {'language': 'tr', 'confidence': 90}
      }));
      await req.response.close();
    });
    final (_, a) = await call('POST', '/admin/api/v1/login', body: {'username': 'patron', 'password': 'cok-gizli-123'});
    final admin = a['token'] as String;
    await call('PUT', '/admin/api/v1/settings', token: admin, body: {
      'settings': {'translateEnabled': true, 'translateUrl': 'http://127.0.0.1:${tr.port}/translate'}
    });

    final (_, x) = await call('POST', '/api/v1/auth/register', body: {'username': 'deniz', 'password': 'sifre-aaaa'});
    final (_, y) = await call('POST', '/api/v1/auth/register', body: {'username': 'lara', 'password': 'sifre-bbbb'});
    final tx = x['token'] as String, ty = y['token'] as String;
    final idy = (y['me'] as Map)['id'];
    await call('PATCH', '/api/v1/me', token: ty, body: {'lang': 'en'});

    final wy = await WsProbe.connect(ty);
    await wy.next('hello');
    final (ds, _) = await call('POST', '/api/v1/dm/$idy', token: tx, body: {'text': 'merhaba'});
    expect(ds, 200);
    final dm = await wy.next(Ev.dm);
    expect(dm['text'], 'merhaba');
    expect(dm['fromName'], 'deniz');
    expect(dm['unreadDm'], 1);
    expect(dm.containsKey('from'), isTrue);
    final translated = await wy.next(Ev.dm, where: (d) => d['translations'] != null);
    expect((translated['translations'] as Map)['en'], '[en] merhaba');

    final (_, threads) = await call('GET', '/api/v1/dm', token: ty);
    expect(threads['unread'], 1);
    expect(((threads['items'] as List).single as Map)['peer']['name'], 'deniz');
    await call('GET', '/api/v1/dm/${(x['me'] as Map)['id']}', token: ty); // okundu işaretler
    final (_, me) = await call('GET', '/api/v1/me', token: ty);
    expect(me['unreadDms'], 0);

    // Bildirim: yönetici uyarısı
    await call('POST', '/admin/api/v1/users/$idy/action', token: admin, body: {'action': 'warn', 'text': 'kurallara uy'});
    final n = await wy.next(Ev.notify);
    expect(n['unread'], 1);
    final (_, list) = await call('GET', '/api/v1/notifications', token: ty);
    expect(((list['items'] as List).first as Map)['text'], contains('kurallara uy'));
    await call('POST', '/api/v1/notifications/read', token: ty);
    final (_, me2) = await call('GET', '/api/v1/me', token: ty);
    expect(me2['unreadNotices'], 0);

    await call('PUT', '/admin/api/v1/settings', token: admin, body: {'settings': {'translateEnabled': false}});
    await wy.ws.close();
    await tr.close(force: true);
  });

  test('profil fotoğrafı yükleme: yalnız gerçek görsel kabul edilir ve sunulur', () async {
    final (_, u) = await call('POST', '/api/v1/auth/register', body: {'username': 'foto', 'password': 'sifre-cccc'});
    final t = u['token'] as String;
    Future<(int, Map<String, dynamic>)> upload(List<int> bytes) async {
      final c = HttpClient();
      final req = await c.postUrl(Uri.parse('$base/api/v1/me/avatar'));
      req.headers.set('Authorization', 'Bearer $t');
      req.add(bytes);
      final res = await req.close();
      final text = await utf8.decoder.bind(res).join();
      c.close();
      return (res.statusCode, jsonDecode(text) as Map<String, dynamic>);
    }

    final (bad, _) = await upload(utf8.encode('<script>alert(1)</script>'));
    expect(bad, 415);
    // 1x1 PNG
    final png = base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');
    final (ok, me) = await upload(png);
    expect(ok, 200);
    final url = me['avatarUrl'] as String;
    expect(url, startsWith('/uploads/'));
    final c = HttpClient();
    final res = await (await c.getUrl(Uri.parse('$base$url'))).close();
    expect(res.statusCode, 200);
    expect(res.headers.contentType?.mimeType, 'image/png');
    await res.drain<void>();
    c.close();
  });

  test('uç nokta yolu admin panelinden değiştirilebilir', () async {
    final (_, a) = await call('POST', '/admin/api/v1/login', body: {'username': 'patron', 'password': 'cok-gizli-123'});
    final admin = a['token'] as String;
    final (bad, badBody) = await call('PUT', '/admin/api/v1/settings', token: admin, body: {
      'settings': {'endpoints': {'roomList': '/admin/hack'}}
    });
    expect(bad, 200);
    expect((badBody['settings']['endpoints'] as Map)['roomList'], '/room/api/v1/room');
    await call('PUT', '/admin/api/v1/settings', token: admin, body: {
      'settings': {'endpoints': {'roomList': '/oyun/v2/masalar'}}
    });
    final (_, cfg) = await call('GET', '/api/v1/config');
    expect((cfg['endpoints'] as Map)['roomList'], '/oyun/v2/masalar');
    final (_, u) = await call('POST', '/api/v1/auth/register', body: {'username': 'yolcu', 'password': 'sifre-dddd'});
    final (st, rooms) = await call('GET', '/oyun/v2/masalar', token: u['token'] as String);
    expect(st, 200);
    expect((rooms['items'] as List), isNotEmpty);
    await call('PUT', '/admin/api/v1/settings', token: admin, body: {'settings': {'endpoints': <String, String>{}}});
    final (_, cfg2) = await call('GET', '/api/v1/config');
    expect((cfg2['endpoints'] as Map)['roomList'], '/room/api/v1/room');
  });

  group('ticaret, mail ve destek', () {
    late String admin;
    final sent = <(String, String, String)>[]; // (alıcı, konu, html)

    setUp(() async {
      final (_, a) = await call('POST', '/admin/api/v1/login', body: {'username': 'patron', 'password': 'cok-gizli-123'});
      admin = a['token'] as String;
      server.mailSender = (c, to, subject, html) async => sent.add((to, subject, html));
      await call('PUT', '/admin/api/v1/settings', token: admin, body: {
        'settings': {'mailEnabled': true, 'smtpHost': 'smtp.ornek', 'mailFrom': 'oyun@ornek.com', 'publicBaseUrl': 'https://oyun.ornek.com'}
      });
    });

    String linkIn(String html) => RegExp(r'href="([^"]+)"').firstMatch(html)!.group(1)!.replaceAll('&amp;', '&');

    test('kayıt e-postası, doğrulama ve şifremi unuttum akışı', () async {
      sent.clear();
      final (st, r) = await call('POST', '/api/v1/auth/register',
          body: {'username': 'mailci', 'password': 'sifre-1111', 'email': 'Mailci@Ornek.com'});
      expect(st, 200);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sent.single.$1, 'mailci@ornek.com');
      expect(sent.single.$2, contains('hoş geldin'));
      // Doğrulama bağlantısı
      final verify = Uri.parse(linkIn(sent.single.$3));
      expect(verify.path, '/eposta-dogrula');
      final c = HttpClient();
      final vres = await (await c.getUrl(Uri.parse('$base/eposta-dogrula?token=${verify.queryParameters['token']}'))).close();
      expect(vres.statusCode, 200);
      await vres.drain<void>();
      final (_, me) = await call('GET', '/api/v1/me', token: r['token'] as String);
      expect(me['emailVerified'], isTrue);

      // Şifremi unuttum
      sent.clear();
      final (fs, f) = await call('POST', '/api/v1/auth/forgot', body: {'email': 'mailci@ornek.com'});
      expect(fs, 200);
      expect(f['ok'], isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final reset = Uri.parse(linkIn(sent.single.$3));
      expect(reset.path, '/sifre-sifirla');
      final (rs, _) = await call('POST', '/api/v1/auth/reset', body: {'token': reset.queryParameters['token'], 'password': 'yeni-sifre-22'});
      expect(rs, 200);
      final (again, _) = await call('POST', '/api/v1/auth/reset', body: {'token': reset.queryParameters['token'], 'password': 'baska-sifre-3'});
      expect(again, 400, reason: 'bağlantı tek kullanımlık');
      final (ls, _) = await call('POST', '/api/v1/auth/login', body: {'username': 'mailci', 'password': 'yeni-sifre-22'});
      expect(ls, 200);
      // Var olmayan adres: aynı yanıt, mail yok
      sent.clear();
      final (ns, _) = await call('POST', '/api/v1/auth/forgot', body: {'email': 'yok@ornek.com'});
      expect(ns, 200);
      expect(sent, isEmpty);
      c.close();
    });

    test('abonelik paketi: kilitli özellik açılır, hediye envantere girer, süre bitince kilitlenir', () async {
      // DM özelliğini kilitle
      await call('POST', '/admin/api/v1/features', token: admin, body: {'key': 'dm', 'locked': true});
      final (_, gift) = await call('POST', '/admin/api/v1/gifts', token: admin, body: {'name': 'Yıldız', 'emoji': '⭐', 'price': 50});
      final (ps, pkg) = await call('POST', '/admin/api/v1/packages', token: admin, body: {
        'name': 'Aylık Sohbet',
        'kind': 'subscription',
        'priceKurus': 4999,
        'coins': 0,
        'periodDays': 30,
        'features': ['dm', 'yokboyle'],
        'gifts': [
          {'giftId': gift['id'], 'qty': 3}
        ],
      });
      expect(ps, 200);
      expect(pkg['features'], ['dm']);
      final (_, a) = await call('POST', '/api/v1/auth/register', body: {'username': 'abone', 'password': 'sifre-2222', 'email': 'abone@ornek.com'});
      final (_, b) = await call('POST', '/api/v1/auth/register', body: {'username': 'karsi', 'password': 'sifre-3333'});
      final ta = a['token'] as String;
      final idb = (b['me'] as Map)['id'];

      final (locked, err) = await call('POST', '/api/v1/dm/$idb', token: ta, body: {'text': 'selam'});
      expect(locked, 403);
      expect(err['error'], contains('Özel mesaj'));
      final (_, me0) = await call('GET', '/api/v1/me', token: ta);
      expect(me0['locked'], contains('dm'));

      // Sipariş (havale) → admin onayı → hak + hediye + satın alma maili
      sent.clear();
      final (_, o) = await call('POST', '/api/v1/orders', token: ta, body: {'packageId': pkg['id'], 'provider': 'manual'});
      await call('POST', '/admin/api/v1/orders/${(o['order'] as Map)['id']}/action', token: admin, body: {'action': 'approve'});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sent.any((m) => m.$1 == 'abone@ornek.com' && m.$2.contains('onaylandı')), isTrue);
      final (_, me1) = await call('GET', '/api/v1/me', token: ta);
      expect((me1['entitlements'] as Map).keys, contains('dm'));
      expect(me1['locked'], isNot(contains('dm')));
      expect((me1['inventory'] as Map)[gift['id']], 3);
      final (ok, _) = await call('POST', '/api/v1/dm/$idb', token: ta, body: {'text': 'selam'});
      expect(ok, 200);

      // Süre doldu → kilit + "bitti" maili
      sent.clear();
      server.checkExpiry(DateTime.now().add(const Duration(days: 29)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sent.any((m) => m.$2.contains('bitiyor')), isTrue);
      server.checkExpiry(DateTime.now().add(const Duration(days: 31)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sent.any((m) => m.$2.contains('doldu')), isTrue);
      final (again, _) = await call('POST', '/api/v1/dm/$idb', token: ta, body: {'text': 'tekrar'});
      expect(again, 403);
      await call('POST', '/admin/api/v1/features', token: admin, body: {'key': 'dm', 'locked': false});
    });

    test('sanal POS bildirimi: yanlış imza reddedilir, doğru imza siparişi otomatik onaylar', () async {
      await call('PUT', '/admin/api/v1/settings', token: admin, body: {
        'settings': {'paytrEnabled': true, 'paytrMerchantId': '123456', 'paytrMerchantKey': 'anahtar', 'paytrMerchantSalt': 'tuz'}
      });
      final (_, set) = await call('GET', '/admin/api/v1/settings', token: admin);
      expect((set['settings'] as Map).containsKey('paytrMerchantKey'), isFalse, reason: 'gizli anahtar dışarı verilmez');
      expect((set['settings'] as Map)['paytrKeySet'], isTrue);

      final (_, pkg) = await call('POST', '/admin/api/v1/packages', token: admin,
          body: {'name': 'Kart Paketi', 'coins': 300, 'priceKurus': 2999});
      final (_, u) = await call('POST', '/api/v1/auth/register', body: {'username': 'kartli', 'password': 'sifre-4444'});
      final t = u['token'] as String;
      final (_, o) = await call('POST', '/api/v1/orders', token: t, body: {'packageId': pkg['id'], 'provider': 'manual'});
      final oid = (o['order'] as Map)['id'] as String;

      Future<(int, String)> notify(String hash) async {
        final c = HttpClient();
        final req = await c.postUrl(Uri.parse('$base/api/v1/pay/paytr/callback'));
        req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
        req.write(Uri(queryParameters: {'merchant_oid': oid, 'status': 'success', 'total_amount': '2999', 'hash': hash}).query);
        final res = await req.close();
        final body = await utf8.decoder.bind(res).join();
        c.close();
        return (res.statusCode, body);
      }

      final (bad, _) = await notify('sahte');
      expect(bad, 400);
      final hash = base64.encode(
          Hmac(sha256, utf8.encode('anahtar')).convert(utf8.encode('${oid}tuzsuccess2999')).bytes);
      final (good, body) = await notify(hash);
      expect(good, 200);
      expect(body, 'OK');
      final (_, me) = await call('GET', '/api/v1/me', token: t);
      expect(me['coins'], 200 + 300);
      final (again, _) = await notify(hash); // tekrar bildirim: çift yükleme yok
      expect(again, 200);
      final (_, me2) = await call('GET', '/api/v1/me', token: t);
      expect(me2['coins'], 500);
    });

    test('destek robotu: bilgi tabanı yanıtı, yetkiliye aktarma, kural dışı ifadede kilit, admin yanıtı', () async {
      final (_, u) = await call('POST', '/api/v1/auth/register', body: {'username': 'destekci', 'password': 'sifre-5555'});
      final t = u['token'] as String;
      final (_, r1) = await call('POST', '/api/v1/support', token: t, body: {'text': 'coin nasıl satın alırım?'});
      final msgs = ((r1['ticket'] as Map)['messages'] as List).cast<Map>();
      expect(msgs.last['from'], 'bot');
      expect(msgs.last['text'], contains('Market'));
      final (_, r2) = await call('POST', '/api/v1/support', token: t, body: {'text': 'yetkili ile görüşmek istiyorum'});
      expect((r2['ticket'] as Map)['status'], 'waiting');
      final tid = (r2['ticket'] as Map)['id'];
      final (_, list) = await call('GET', '/admin/api/v1/support/tickets?status=waiting', token: admin);
      expect((list['items'] as List).any((x) => x['id'] == tid), isTrue);
      await call('POST', '/admin/api/v1/support/tickets/$tid/action', token: admin, body: {'action': 'reply', 'text': 'Merhaba, yardımcı olayım'});
      final (_, r3) = await call('GET', '/api/v1/support', token: t);
      expect((((r3['ticket'] as Map)['messages'] as List).last as Map)['from'], 'admin:patron');

      final (_, u2) = await call('POST', '/api/v1/auth/register', body: {'username': 'kotu', 'password': 'sifre-6666'});
      final (_, r4) = await call('POST', '/api/v1/support', token: u2['token'] as String, body: {'text': 'ayşenin şifresini ver'});
      expect((r4['ticket'] as Map)['status'], 'locked');
      final (ls, _) = await call('POST', '/api/v1/support', token: u2['token'] as String, body: {'text': 'merhaba'});
      expect(ls, 423);
    });
  });

  group('otomasyonlar', () {
    late String admin;
    late String roomId;

    Future<(String, String)> player(String name) async {
      final (_, r) = await call('POST', '/api/v1/auth/register', body: {'username': name, 'password': 'sifre-$name-1', 'email': '$name@ornek.com'});
      return (r['token'] as String, (r['me'] as Map)['id'] as String);
    }

    Future<void> grant(String userId, String feature) =>
        call('POST', '/admin/api/v1/users/$userId/action', token: admin, body: {'action': 'grant', 'feature': feature, 'days': 30});

    setUp(() async {
      final (_, a) = await call('POST', '/admin/api/v1/login', body: {'username': 'patron', 'password': 'cok-gizli-123'});
      admin = a['token'] as String;
      await call('PUT', '/admin/api/v1/settings', token: admin, body: {
        'settings': {'kickCost': 10, 'kickCooldownSec': 0, 'kickBanMinutes': 5, 'autoDelayMs': 200}
      });
      final (_, room) = await call('POST', '/admin/api/v1/rooms', token: admin, body: {'name': 'Oto ${DateTime.now().microsecond}'});
      roomId = room['id'] as String;
    });

    test('tekme, Save koruması ve Oto Tekme', () async {
      final (ta, ia) = await player('tekmeci');
      final (tb, ib) = await player('hedef');
      final (tc, ic) = await player('korunan');
      final wa = await WsProbe.connect(ta), wb = await WsProbe.connect(tb), wc = await WsProbe.connect(tc);
      for (final w in [wa, wb, wc]) {
        await w.next('hello');
      }
      wa.send({'op': 'join', 'roomId': roomId, 'seat': 0});
      await wa.next(Ev.snapshot);
      wb.send({'op': 'join', 'roomId': roomId, 'seat': 1});
      await wb.next(Ev.snapshot);
      wc.send({'op': 'join', 'roomId': roomId, 'seat': 2});
      await wc.next(Ev.snapshot);

      // Save: C kendini korur (hak gerekir)
      final (locked, _) = await call('PUT', '/api/v1/automation', token: tc, body: {'save': {'selfProtect': true}});
      expect(locked, 403);
      await grant(ic, 'save');
      final (ok, _) = await call('PUT', '/api/v1/automation', token: tc, body: {'save': {'selfProtect': true}});
      expect(ok, 200);

      wa.send({'op': 'kick', 'seat': 2});
      final e1 = await wa.next(Ev.error);
      expect(e1['message'], contains('korumalı'));

      wa.send({'op': 'kick', 'seat': 1});
      final vac = await wa.next(Ev.seatVacated, where: (d) => d['index'] == 1);
      expect(vac['playerId'], ib);
      final kicked = await wb.next('room.kicked');
      expect(kicked['minutes'], 5);
      final me = await wa.next(Ev.me);
      expect(me['coins'], 200 - 10);
      wb.send({'op': 'join', 'roomId': roomId});
      final ban = await wb.next(Ev.error);
      expect(ban['message'], contains('çıkarıldın'));

      // Oto Tekme: A'nın listesine D eklenir, D oturunca çıkarılır
      final (td, id) = await player('istenmeyen');
      await grant(ia, 'autoKick');
      final (st, _) = await call('PUT', '/api/v1/automation', token: ta, body: {
        'autoKick': {'enabled': true, 'list': [id], 'delayMs': 300}
      });
      expect(st, 200);
      final wd = await WsProbe.connect(td);
      await wd.next('hello');
      wd.send({'op': 'join', 'roomId': roomId, 'seat': 5});
      await wd.next(Ev.snapshot);
      final out = await wa.next(Ev.seatVacated, where: (d) => d['index'] == 5);
      expect(out['playerId'], id);
      final (_, auto) = await call('GET', '/api/v1/automation', token: ta);
      expect(((auto['players'] as Map)[id] as Map)['name'], 'istenmeyen');
      for (final w in [wa, wb, wc, wd]) {
        await w.ws.close();
      }
    });

    test('Oto Çevir + Oto Öpücük: tur kendiliğinden eşleşmeyle biter', () async {
      final (ta, ia) = await player('otoa');
      final (tb, ib) = await player('otob');
      for (final (t, i) in [(ta, ia), (tb, ib)]) {
        await grant(i, 'autoSpin');
        await grant(i, 'autoKiss');
        final (st, _) = await call('PUT', '/api/v1/automation', token: t, body: {
          'autoSpin': {'enabled': true},
          'autoKiss': {'enabled': true, 'mode': 'all'},
        });
        expect(st, 200);
      }
      final wa = await WsProbe.connect(ta), wb = await WsProbe.connect(tb);
      await wa.next('hello');
      await wb.next('hello');
      wa.send({'op': 'join', 'roomId': roomId, 'seat': 0});
      await wa.next(Ev.snapshot);
      wb.send({'op': 'join', 'roomId': roomId, 'seat': 6});
      final m = await wa.next(Ev.match);
      expect(m['success'], isTrue);
      await wa.ws.close();
      await wb.ws.close();
    });

    test('başarısız girişte hesap sahibine uyarı e-postası', () async {
      final sent = <String>[];
      server.mailSender = (c, to, subject, html) async => sent.add('$to|$subject');
      await call('PUT', '/admin/api/v1/settings', token: admin, body: {
        'settings': {'mailEnabled': true, 'smtpHost': 'smtp.ornek', 'mailFrom': 'oyun@ornek.com', 'publicBaseUrl': 'https://o.com', 'mailOnLoginFail': true}
      });
      await player('dikkat');
      for (var i = 0; i < 3; i++) {
        await call('POST', '/api/v1/auth/login', body: {'username': 'dikkat', 'password': 'yanlis-$i'});
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sent.where((x) => x.startsWith('dikkat@ornek.com|') && x.contains('başarısız')).length, 1);
    });
  });

  test('yeni üye ücretsiz deneme: seçilen özellikler, ayarlanan gün; kapatılabilir', () async {
    final (_, a) = await call('POST', '/admin/api/v1/login', body: {'username': 'patron', 'password': 'cok-gizli-123'});
    final admin = a['token'] as String;
    await call('POST', '/admin/api/v1/features', token: admin, body: {'key': 'groupGift', 'locked': true});
    await call('PUT', '/admin/api/v1/settings', token: admin, body: {
      'settings': {'trialEnabled': true, 'trialDays': 2, 'trialFeatures': ['groupGift']}
    });
    final (_, u) = await call('POST', '/api/v1/auth/register', body: {'username': 'denemeci', 'password': 'sifre-7777'});
    final ent = ((u['me'] as Map)['entitlements'] as Map);
    expect(ent.keys, contains('groupGift'));
    final until = DateTime.parse('${ent['groupGift']}');
    expect(until.difference(DateTime.now()).inHours, inInclusiveRange(47, 48));
    expect((u['me'] as Map)['locked'], isNot(contains('groupGift')));
    expect((u['me'] as Map)['locked'], isNot(contains('dm')), reason: 'DM varsayılan olarak ücretsiz');

    await call('PUT', '/admin/api/v1/settings', token: admin, body: {'settings': {'trialEnabled': false}});
    final (_, u2) = await call('POST', '/api/v1/auth/register', body: {'username': 'denemesiz', 'password': 'sifre-8888'});
    expect(((u2['me'] as Map)['entitlements'] as Map), isNot(contains('groupGift')));
    await call('POST', '/admin/api/v1/features', token: admin, body: {'key': 'groupGift', 'locked': false});
  });
}
