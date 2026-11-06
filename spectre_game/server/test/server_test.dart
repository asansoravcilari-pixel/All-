import 'dart:convert';
import 'dart:io';

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
}
