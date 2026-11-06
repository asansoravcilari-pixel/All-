import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:spectre_core/spectre_core.dart';

import 'auth.dart';
import 'store.dart';

class ApiError implements Exception {
  ApiError(this.status, this.message);
  final int status;
  final String message;
}

class _Session {
  _Session(this.subject, this.admin) : created = DateTime.now();
  final String subject; // userId veya admin kullanıcı adı
  final bool admin;
  final DateTime created;
  DateTime lastUsed = DateTime.now();
}

class _Client {
  _Client(this.socket, this.userId);
  final WebSocket socket;
  final String userId;
  final Set<String> channels = {};
  final List<DateTime> chatTimes = [];
  final List<DateTime> giftTimes = [];

  bool closed = false;

  void send(Map<String, dynamic> msg) => sendRaw(jsonEncode(msg));

  void sendRaw(String data) {
    if (closed || socket.readyState != WebSocket.open) return;
    try {
      socket.add(data);
    } catch (_) {
      closed = true;
    }
  }

  void close() {
    if (closed) return;
    closed = true;
    socket.close();
  }
}

const _palette = [0xFF65C5FF, 0xFFFF7AB6, 0xFFFFC857, 0xFF7CF5C4, 0xFFB69CFF, 0xFFFF8F6B, 0xFF6BE3FF, 0xFFF2A1FF];

class SpectreServer {
  SpectreServer({required this.store, this.webRoot, this.corsOrigin, this.tickInterval = const Duration(milliseconds: 200)});

  final Store store;
  final Directory? webRoot;
  final String? corsOrigin;
  final Duration tickInterval;

  final rules = TableRules();
  final Map<String, GameTable> tables = {};
  final Map<String, StreamSubscription<TableEvent>> _tableSubs = {};
  final Map<String, int> _sentVersion = {};
  final Map<String, _Session> _sessions = {};
  final List<_Client> _clients = [];
  final Map<String, List<DateTime>> _loginFailures = {};
  HttpServer? _http;
  Timer? _tick;
  Timer? _flush;
  final _rnd = math.Random.secure();

  int get port => _http!.port;

  // ---------------------------------------------------------------------------
  // Başlatma
  // ---------------------------------------------------------------------------

  Future<void> start({int port = 8080, InternetAddress? address, String? adminUser, String? adminPassword}) async {
    await store.load();
    rules.apply(store.rules);
    if (store.rooms.isEmpty) {
      // Projedeki varsayılan masalar (baglantilar.json → aktif_masalar).
      for (var i = 1; i <= 4; i++) {
        store.rooms.add(RoomRec(id: '$i', name: 'Masa $i', theme: (i - 1) % 4));
      }
      store.markDirty();
    }
    for (final r in store.rooms) {
      _mountTable(r);
    }
    await _ensureOwner(adminUser, adminPassword);
    _http = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    _http!.autoCompress = true;
    _http!.listen(_handle);
    _tick = Timer.periodic(tickInterval, (_) => _onTick());
    _flush = Timer.periodic(const Duration(seconds: 2), (_) => store.flush());
  }

  Future<void> stop() async {
    _tick?.cancel();
    _flush?.cancel();
    for (final c in List.of(_clients)) {
      c.close();
    }
    for (final s in _tableSubs.values) {
      await s.cancel();
    }
    await _http?.close(force: true);
    await store.flush(force: true);
  }

  Future<void> _ensureOwner(String? user, String? password) async {
    if (store.admins.isNotEmpty) return;
    final name = (user == null || user.trim().isEmpty) ? 'admin' : user.trim();
    var pass = password ?? '';
    var generated = false;
    if (pass.length < 8) {
      pass = randomToken(12);
      generated = true;
    }
    store.admins[name.toLowerCase()] = AdminRec(username: name, passwordHash: hashPassword(pass), role: 'owner');
    store.securityEvent('info', 'İlk yönetici hesabı oluşturuldu: $name');
    store.markDirty();
    if (generated) {
      final f = store.file;
      final msg = 'Yönetici kullanıcı adı: $name\nŞifre: $pass\n(İlk girişten sonra admin panelinden değiştirin ve bu dosyayı silin.)\n';
      if (f != null) {
        final out = File('${f.parent.path}/admin-ilk-sifre.txt');
        await out.writeAsString(msg);
        stdout.writeln('İlk yönetici şifresi ${out.path} dosyasına yazıldı.');
      } else {
        stdout.writeln(msg);
      }
    }
    await store.flush(force: true);
  }

  GameTable _mountTable(RoomRec r) {
    final t = GameTable(id: r.id, name: r.name, rules: rules, theme: r.theme)
      ..locked = r.locked
      ..closed = r.closed;
    tables[r.id] = t;
    _tableSubs[r.id] = t.events.listen((e) => _onTableEvent(t, e));
    return t;
  }

  // ---------------------------------------------------------------------------
  // Zamanlayıcı
  // ---------------------------------------------------------------------------

  void _onTick() {
    final now = DateTime.now();
    for (final t in tables.values) {
      final beforeRound = t.roundNo;
      final beforeSpinner = t.spinnerSeat;
      t.tick(now);
      if (t.roundNo != beforeRound) {
        // otomatik çevirme de bir çevirme sayılır
        final u = store.users[t.seats[beforeSpinner].player?.userId];
        if (u != null) u.spins++;
      }
      if (_sentVersion[t.id] != t.version) {
        _sentVersion[t.id] = t.version;
        _toChannel(roomChannel(t.id), Ev.snapshot, t.snapshot(now).toJson());
      }
    }
  }

  void _onTableEvent(GameTable t, TableEvent e) {
    final ch = roomChannel(t.id);
    switch (e) {
      case SeatUpdated(:final index, :final player):
        _toChannel(ch, Ev.seatUpdated, {'index': index, ...player.toJson()});
      case SeatVacated(:final index, :final userId):
        _toChannel(ch, Ev.seatVacated, {'index': index, 'playerId': userId});
      case ChatEvent(:final line):
        _toChannel(ch, Ev.chat, line.toJson());
      case GiftEvent(:final fromSeat, :final toSeat, :final gift):
        _toChannel(ch, Ev.gift, {'fromSeat': fromSeat, 'toSeat': toSeat, 'gift': gift.toJson()});
      case ReactionEvent(:final seat, :final emoji):
        _toChannel(ch, Ev.reaction, {'seat': seat, 'emoji': emoji});
      case MatchEvent(:final a, :final b, :final success):
        if (success) {
          for (final idx in [a, b]) {
            final u = store.users[t.seats[idx].player?.userId];
            if (u != null) {
              u.hearts++;
              store.markDirty();
            }
          }
        }
        _toChannel(ch, Ev.match, {'a': a, 'b': b, 'success': success});
      case NoticeEvent(:final text, :final kind):
        _toChannel(ch, Ev.notice, {'text': text, 'kind': kind});
    }
  }

  void _toChannel(String channel, String event, Map<String, dynamic> data) {
    final msg = {'channel': channel, 'event': event, 'data': data};
    final encoded = jsonEncode(msg);
    for (final c in _clients) {
      if (c.channels.contains(channel)) c.sendRaw(encoded);
    }
  }

  void _toUser(String userId, String event, Map<String, dynamic> data) {
    for (final c in _clients.where((c) => c.userId == userId)) {
      c.send({'channel': null, 'event': event, 'data': data});
    }
  }

  bool isOnline(String userId) => _clients.any((c) => c.userId == userId);

  GameTable? tableOf(String userId) {
    for (final t in tables.values) {
      if (t.seatOf(userId) != null) return t;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // HTTP
  // ---------------------------------------------------------------------------

  String _ip(HttpRequest req) {
    final fwd = req.headers.value('x-forwarded-for');
    if (fwd != null && fwd.isNotEmpty) return fwd.split(',').first.trim();
    return req.connectionInfo?.remoteAddress.address ?? '?';
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'same-origin');
    if (corsOrigin != null) {
      res.headers
        ..set('Access-Control-Allow-Origin', corsOrigin!)
        ..set('Access-Control-Allow-Headers', 'Authorization, Content-Type')
        ..set('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
    }
    try {
      if (store.settings.blockedIps.contains(_ip(req))) throw ApiError(403, 'Erişim engellendi');
      if (req.method == 'OPTIONS') {
        res.statusCode = 204;
        await res.close();
        return;
      }
      final path = req.uri.path;
      if (path == '/ws') return await _upgrade(req);
      if (path.startsWith('/admin/api/')) return await _json(req, await _admin(req));
      if (path.startsWith('/api/') || path.startsWith('/room/api/') || path.startsWith('/user/api/')) {
        return await _json(req, await _public(req));
      }
      await _static(req);
    } on ApiError catch (e) {
      await _json(req, {'error': e.message}, status: e.status);
    } on FormatException {
      await _json(req, {'error': 'Geçersiz istek'}, status: 400);
    } catch (e, st) {
      stderr.writeln('HATA ${req.method} ${req.uri.path}: $e\n$st');
      await _json(req, {'error': 'Sunucu hatası'}, status: 500);
    }
  }

  Future<void> _json(HttpRequest req, Object? body, {int status = 200}) async {
    final res = req.response;
    res.statusCode = status;
    res.headers
      ..contentType = ContentType.json
      ..set('Cache-Control', 'no-store');
    res.write(jsonEncode(body));
    await res.close();
  }

  Future<Map<String, dynamic>> _body(HttpRequest req) async {
    final text = await utf8.decoder.bind(req).join();
    if (text.length > 64 * 1024) throw ApiError(413, 'İstek çok büyük');
    if (text.trim().isEmpty) return {};
    final v = jsonDecode(text);
    if (v is! Map) throw ApiError(400, 'JSON nesnesi bekleniyor');
    return v.cast<String, dynamic>();
  }

  String? _bearer(HttpRequest req) {
    final h = req.headers.value(HttpHeaders.authorizationHeader);
    if (h != null && h.startsWith('Bearer ')) return h.substring(7).trim();
    return req.uri.queryParameters['token'];
  }

  _Session? _session(String? token, {required bool admin}) {
    if (token == null) return null;
    final s = _sessions[token];
    if (s == null || s.admin != admin) return null;
    final ttl = admin ? const Duration(hours: 12) : const Duration(days: 30);
    if (DateTime.now().difference(s.lastUsed) > ttl) {
      _sessions.remove(token);
      return null;
    }
    s.lastUsed = DateTime.now();
    return s;
  }

  UserRec _requireUser(HttpRequest req) {
    final s = _session(_bearer(req), admin: false);
    final u = s == null ? null : store.users[s.subject];
    if (u == null) throw ApiError(401, 'Oturum gerekli');
    if (u.status == 'banned' || u.status == 'suspended') throw ApiError(403, 'Hesap erişime kapalı');
    return u;
  }

  AdminRec _requireAdmin(HttpRequest req) {
    final s = _session(_bearer(req), admin: true);
    final a = s == null ? null : store.admins[s.subject.toLowerCase()];
    if (a == null) throw ApiError(401, 'Yönetici oturumu gerekli');
    return a;
  }

  void _throttleLogin(String key) {
    final now = DateTime.now();
    final list = _loginFailures.putIfAbsent(key, () => []);
    list.removeWhere((t) => now.difference(t) > const Duration(minutes: 10));
    if (list.length >= 8) throw ApiError(429, 'Çok fazla hatalı deneme. 10 dakika sonra tekrar deneyin.');
  }

  void _loginFailed(String key, String what) {
    _loginFailures.putIfAbsent(key, () => []).add(DateTime.now());
    store.securityEvent('warn', 'Hatalı giriş denemesi: $what');
  }

  String _issue(String subject, {required bool admin}) {
    final token = randomToken();
    _sessions[token] = _Session(subject, admin);
    return token;
  }

  // ---------------------------------------------------------------------------
  // Oyuncu API'si
  // ---------------------------------------------------------------------------

  Map<String, dynamic> meJson(UserRec u) => {
        'id': u.id,
        'username': u.username,
        'displayName': u.displayName,
        'role': u.role,
        'status': u.status,
        'coins': u.coins,
        'level': u.level,
        'hearts': u.hearts,
        'color': u.color,
        'guest': u.guest,
        'avatarUrl': u.avatarUrl,
        'canClaimDaily': _canClaimDaily(u),
      };

  Map<String, dynamic> publicUser(UserRec u) => {
        'id': u.id,
        'name': u.displayName,
        'avatarUrl': u.avatarUrl,
        'color': u.color,
        'level': u.level,
        'vip': u.isVip,
        'hearts': u.hearts,
        'isOnline': isOnline(u.id),
        'roomId': tableOf(u.id)?.id,
      };

  bool _canClaimDaily(UserRec u) => u.lastDaily == null || DateTime.now().difference(u.lastDaily!).inHours >= 20;

  SeatPlayer _seatPlayer(UserRec u) => SeatPlayer(
        userId: u.id,
        name: u.displayName,
        avatarUrl: u.avatarUrl,
        color: u.color,
        level: u.level,
        vip: u.isVip,
        hearts: u.hearts,
      );

  UserRec _createUser(String username, String displayName, String password, {bool guest = false}) {
    final u = UserRec(
      id: store.nextId('u'),
      username: username,
      displayName: displayName,
      passwordHash: password.isEmpty ? '' : hashPassword(password),
      createdAt: DateTime.now(),
      coins: store.settings.startingCoins,
      color: _palette[_rnd.nextInt(_palette.length)],
      guest: guest,
    );
    store.users[u.id] = u;
    if (u.coins > 0) store.addLedger(LedgerRec(u.id, 'reward', u.coins, 'Başlangıç coini'));
    store.markDirty();
    return u;
  }

  Future<Object?> _public(HttpRequest req) async {
    final p = req.uri.pathSegments;
    final m = req.method;
    final s = store.settings;
    final ip = _ip(req);

    // --- Genel ---
    if (m == 'GET' && req.uri.path == '/api/v1/health') return {'ok': true};
    if (m == 'GET' && req.uri.path == '/api/v1/config') return s.publicJson();

    // --- Kimlik ---
    if (m == 'POST' && req.uri.path == '/api/v1/auth/register') {
      if (!s.registrationOpen) throw ApiError(403, 'Yeni kayıt şu an kapalı');
      final b = await _body(req);
      final username = '${b['username'] ?? ''}'.trim();
      final password = '${b['password'] ?? ''}';
      final display = '${b['displayName'] ?? username}'.trim();
      if (!usernamePattern.hasMatch(username)) {
        throw ApiError(400, 'Kullanıcı adı 3–20 karakter olmalı (harf, rakam, . _ -)');
      }
      final pe = validatePassword(password);
      if (pe != null) throw ApiError(400, pe);
      if (store.userByName(username) != null) throw ApiError(409, 'Bu kullanıcı adı alınmış');
      final u = _createUser(username, display.isEmpty ? username : _clip(display, 20), password);
      return {'token': _issue(u.id, admin: false), 'me': meJson(u)};
    }
    if (m == 'POST' && req.uri.path == '/api/v1/auth/login') {
      final b = await _body(req);
      final username = '${b['username'] ?? ''}'.trim();
      final key = 'u:$ip';
      _throttleLogin(key);
      final u = store.userByName(username);
      if (u == null || u.passwordHash.isEmpty || !verifyPassword('${b['password'] ?? ''}', u.passwordHash)) {
        _loginFailed(key, 'oyuncu "$username" ($ip)');
        throw ApiError(401, 'Kullanıcı adı veya şifre hatalı');
      }
      if (u.status == 'banned') throw ApiError(403, 'Hesabınız yasaklanmıştır');
      if (u.status == 'suspended') throw ApiError(403, 'Hesabınız askıya alınmıştır');
      u.lastSeen = DateTime.now();
      return {'token': _issue(u.id, admin: false), 'me': meJson(u)};
    }
    if (m == 'POST' && req.uri.path == '/api/v1/auth/guest') {
      if (!s.guestLogin) throw ApiError(403, 'Misafir girişi kapalı');
      final n = 1000 + _rnd.nextInt(9000);
      final u = _createUser('misafir_${store.seq + 1}', 'Misafir $n', '', guest: true);
      return {'token': _issue(u.id, admin: false), 'me': meJson(u)};
    }
    if (m == 'POST' && req.uri.path == '/api/v1/auth/logout') {
      final t = _bearer(req);
      if (t != null) _sessions.remove(t);
      return {'ok': true};
    }

    // --- Oda (sizin verdiğiniz sözleşme) ---
    if (m == 'GET' && p.length == 4 && p[0] == 'room' && p[3] == 'room') {
      _requireUser(req);
      return {
        'items': [
          for (final t in tables.values)
            if (!t.closed) t.summary().toJson()
        ]
      };
    }
    if (m == 'GET' && p.length == 5 && p[0] == 'room' && p[3] == 'room') {
      _requireUser(req);
      final t = tables[p[4]] ?? (throw ApiError(404, 'Masa bulunamadı'));
      return t.summary().toJson();
    }
    if (m == 'GET' && p.length == 4 && p[0] == 'room' && p[3] == 'roomPlayer') {
      final me = _requireUser(req);
      final q = req.uri.queryParameters;
      final t = tables[q['roomId']] ?? tableOf(q['userId'] ?? me.id);
      if (t == null) return {'items': []};
      final limit = int.tryParse(q['limit'] ?? '') ?? kSeatCount;
      final items = t.roomPlayers().take(limit.clamp(1, kSeatCount)).map((e) => e.toJson()).toList();
      if (q['status'] != 'active') {
        // Son 30 dakikada ayrılanlar (leaveAt dolu)
        for (final e in t.leftAt.entries) {
          if (DateTime.now().difference(e.value).inMinutes > 30) continue;
          final u = store.users[e.key];
          if (u == null) continue;
          items.add(RoomPlayer(index: -1, player: _seatPlayer(u), isPlaying: false, leaveAt: e.value).toJson());
        }
      }
      return {'roomId': t.id, 'items': items};
    }
    if (m == 'GET' && p.length == 5 && p[0] == 'user' && p[3] == 'user') {
      _requireUser(req);
      final u = store.users[p[4]] ?? (throw ApiError(404, 'Oyuncu bulunamadı'));
      return publicUser(u);
    }

    // --- Hesap ---
    if (req.uri.path == '/api/v1/me') {
      final u = _requireUser(req);
      if (m == 'GET') return meJson(u);
      if (m == 'PATCH') {
        final b = await _body(req);
        final d = '${b['displayName'] ?? ''}'.trim();
        if (d.length < 2) throw ApiError(400, 'Ad en az 2 karakter olmalı');
        if (_blocked(d)) throw ApiError(400, 'Bu ad kullanılamaz');
        u.displayName = _clip(d, 20);
        store.markDirty();
        return meJson(u);
      }
    }
    if (m == 'POST' && req.uri.path == '/api/v1/me/daily') {
      final u = _requireUser(req);
      if (!_canClaimDaily(u)) throw ApiError(409, 'Günlük ödül zaten alındı');
      u.lastDaily = DateTime.now();
      u.coins += s.dailyRewardCoins;
      store.addLedger(LedgerRec(u.id, 'reward', s.dailyRewardCoins, 'Günlük ödül'));
      return {'amount': s.dailyRewardCoins, 'me': meJson(u)};
    }

    // --- Market ---
    if (m == 'GET' && req.uri.path == '/api/v1/gifts') {
      _requireUser(req);
      return {'items': store.gifts.where((g) => g['enabled'] != false).toList()};
    }
    if (m == 'GET' && req.uri.path == '/api/v1/market/packages') {
      _requireUser(req);
      if (!s.marketOpen) return {'items': [], 'open': false};
      return {'items': [for (final p in store.packages) if (p.active) p.toJson()], 'open': true};
    }
    if (req.uri.path == '/api/v1/orders') {
      final u = _requireUser(req);
      if (m == 'GET') {
        return {'items': [for (final o in store.orders) if (o.userId == u.id) o.toJson()]};
      }
      if (m == 'POST') {
        if (!s.marketOpen) throw ApiError(403, 'Market kapalı');
        if (u.guest) throw ApiError(403, 'Satın alma için üye girişi gerekli');
        final b = await _body(req);
        final pkg = store.packages.where((x) => x.id == b['packageId'] && x.active).firstOrNull ??
            (throw ApiError(404, 'Paket bulunamadı'));
        final provider = '${b['provider']}';
        final allowed = {
          if (s.paytrEnabled) 'paytr',
          if (s.shopierEnabled) 'shopier',
          if (s.manualPayment) 'manual',
        };
        if (!allowed.contains(provider)) throw ApiError(400, 'Bu ödeme yöntemi kapalı');
        final o = OrderRec(
          id: store.nextId('S'),
          userId: u.id,
          packageId: pkg.id,
          packageName: pkg.name,
          amountKurus: pkg.priceKurus,
          coins: pkg.totalCoins,
          provider: provider,
          createdAt: DateTime.now(),
        );
        store.orders.insert(0, o);
        store.markDirty();
        return {
          'order': o.toJson(),
          // Kartlı ödeme sağlayıcı entegrasyonu henüz yok: sipariş yönetici onayına düşer.
          'next': provider == 'manual' ? 'manual' : 'pending_provider',
          'manualInfo': s.manualPaymentInfo,
        };
      }
    }
    throw ApiError(404, 'Bulunamadı');
  }

  bool _blocked(String text) {
    final low = text.toLowerCase();
    return store.settings.blockedWords.any((w) => w.isNotEmpty && low.contains(w.toLowerCase()));
  }

  static String _clip(String s, int n) => s.length > n ? s.substring(0, n) : s;

  // ---------------------------------------------------------------------------
  // WebSocket
  // ---------------------------------------------------------------------------

  Future<void> _upgrade(HttpRequest req) async {
    final s = _session(req.uri.queryParameters['token'], admin: false);
    final u = s == null ? null : store.users[s.subject];
    if (u == null || u.status == 'banned' || u.status == 'suspended') throw ApiError(401, 'Oturum gerekli');
    if (!WebSocketTransformer.isUpgradeRequest(req)) throw ApiError(400, 'WebSocket bekleniyor');
    final ws = await WebSocketTransformer.upgrade(req);
    ws.pingInterval = const Duration(seconds: 20);
    final c = _Client(ws, u.id);
    _clients.add(c);
    u.lastSeen = DateTime.now();
    tableOf(u.id)?.setConnected(u.id, true, DateTime.now());
    c.send({'channel': null, 'event': Ev.hello, 'data': {'me': meJson(u), 'roomId': tableOf(u.id)?.id}});
    ws.listen(
      (data) {
        try {
          if (data is! String || data.length > 4096) return;
          final msg = jsonDecode(data);
          if (msg is Map) _onWs(c, msg.cast<String, dynamic>());
        } catch (_) {
          c.send({'event': Ev.error, 'data': {'message': 'Geçersiz mesaj'}});
        }
      },
      onDone: () => _onWsClosed(c),
      onError: (_) => _onWsClosed(c),
      cancelOnError: true,
    );
  }

  void _onWsClosed(_Client c) {
    if (!_clients.remove(c)) return;
    final u = store.users[c.userId];
    if (u != null) u.lastSeen = DateTime.now();
    if (!isOnline(c.userId)) tableOf(c.userId)?.setConnected(c.userId, false, DateTime.now());
  }

  void _err(_Client c, String m) => c.send({'channel': null, 'event': Ev.error, 'data': {'message': m}});

  void _onWs(_Client c, Map<String, dynamic> msg) {
    final u = store.users[c.userId];
    if (u == null) return;
    final now = DateTime.now();
    final s = store.settings;
    switch (msg['op']) {
      case Op.ping:
        c.send({'event': 'pong', 'data': {'t': now.millisecondsSinceEpoch}});
      case Op.subscribe:
        final ch = '${msg['channel']}';
        if (!ch.startsWith('room') || !tables.containsKey(ch.substring(4))) return _err(c, 'Kanal yok');
        c.channels.add(ch);
        c.send({'channel': ch, 'event': Ev.snapshot, 'data': tables[ch.substring(4)]!.snapshot(now).toJson()});
      case Op.unsubscribe:
        c.channels.remove('${msg['channel']}');
      case Op.join:
        if (s.maintenance) return _err(c, s.maintenanceText);
        if (u.status == 'banned' || u.status == 'suspended') return _err(c, 'Hesap erişime kapalı');
        final t = tables[msg['roomId']];
        if (t == null || t.closed) return _err(c, 'Masa bulunamadı');
        if (t.locked && t.seatOf(u.id) == null) return _err(c, 'Masa kilitli');
        final current = tableOf(u.id);
        if (current != null && current != t) current.leave(u.id, now);
        final seat = t.join(_seatPlayer(u), now, preferredSeat: msg['seat'] is int ? msg['seat'] as int : null);
        if (seat == null) return _err(c, 'Masada boş koltuk yok');
        c.channels.add(roomChannel(t.id));
        c.send({'channel': roomChannel(t.id), 'event': Ev.snapshot, 'data': t.snapshot(now).toJson()});
      case Op.leave:
        tableOf(u.id)?.leave(u.id, now);
      case Op.spin:
        final t = tableOf(u.id);
        if (t != null && t.spin(u.id, now)) {
          u.spins++;
          store.markDirty();
        }
      case Op.decide:
        tableOf(u.id)?.decide(u.id, msg['accept'] == true, now);
      case Op.chat:
        if (u.status == 'muted') return _err(c, 'Susturuldunuz');
        final text = '${msg['text'] ?? ''}';
        if (_blocked(text)) return _err(c, 'Mesaj topluluk kurallarına uymuyor');
        c.chatTimes.removeWhere((t) => now.difference(t).inSeconds >= 60);
        if (c.chatTimes.length >= s.maxMessagesPerMinute) return _err(c, 'Çok hızlı yazıyorsunuz');
        c.chatTimes.add(now);
        tableOf(u.id)?.say(u.id, text);
      case Op.react:
        tableOf(u.id)?.react(u.id, '${msg['emoji'] ?? ''}');
      case Op.gift:
        _gift(c, u, msg, now);
      case Op.giftAll:
        _giftAll(c, u, msg, now);
      default:
        _err(c, 'Bilinmeyen işlem');
    }
  }

  void _gift(_Client c, UserRec u, Map<String, dynamic> msg, DateTime now) {
    if (!rules.giftsEnabled) return _err(c, 'Hediyeler şu an kapalı');
    final t = tableOf(u.id);
    if (t == null) return _err(c, 'Önce masaya otur');
    final g = store.gifts.where((g) => g['id'] == msg['giftId'] && g['enabled'] != false).firstOrNull;
    if (g == null) return _err(c, 'Hediye bulunamadı');
    final gift = GiftInfo.fromJson(g);
    final toSeat = msg['toSeat'] is int ? msg['toSeat'] as int : -1;
    final to = toSeat >= 0 && toSeat < kSeatCount ? t.seats[toSeat].player : null;
    if (to == null || to.userId == u.id) return _err(c, 'Geçersiz alıcı');
    if (u.coins < gift.price) return _err(c, 'Yetersiz coin');
    c.giftTimes.removeWhere((x) => now.difference(x).inSeconds >= 60);
    if (c.giftTimes.length >= store.settings.maxGiftsPerMinute) return _err(c, 'Çok hızlı hediye gönderiyorsunuz');
    c.giftTimes.add(now);
    if (!t.deliverGift(u.id, toSeat, gift)) return _err(c, 'Hediye gönderilemedi');
    final rec = store.users[to.userId];
    u.coins -= gift.price;
    u.giftsSent++;
    store.addLedger(LedgerRec(u.id, 'gift', -gift.price, '${gift.name} → ${to.name}'));
    if (rec != null) {
      final share = (gift.price * 0.1).round();
      rec.giftsReceived++;
      if (share > 0) {
        rec.coins += share;
        store.addLedger(LedgerRec(rec.id, 'giftIncome', share, '${gift.name} ← ${u.displayName}'));
      }
      _toUser(rec.id, Ev.me, meJson(rec));
    }
    _toUser(u.id, Ev.me, meJson(u));
  }

  /// Toplu hediye: masadaki herkese (kendisi hariç) aynı hediye.
  void _giftAll(_Client c, UserRec u, Map<String, dynamic> msg, DateTime now) {
    if (!rules.giftsEnabled) return _err(c, 'Hediyeler şu an kapalı');
    final t = tableOf(u.id);
    if (t == null) return _err(c, 'Önce masaya otur');
    final g = store.gifts.where((g) => g['id'] == msg['giftId'] && g['enabled'] != false).firstOrNull;
    if (g == null) return _err(c, 'Hediye bulunamadı');
    final gift = GiftInfo.fromJson(g);
    final targets = [for (final s in t.seats) if (s.player != null && s.player!.userId != u.id) s.index];
    if (targets.isEmpty) return _err(c, 'Masada başka oyuncu yok');
    final total = gift.price * targets.length;
    if (u.coins < total) return _err(c, 'Yetersiz coin (gereken: $total)');
    c.giftTimes.removeWhere((x) => now.difference(x).inSeconds >= 60);
    if (c.giftTimes.length >= store.settings.maxGiftsPerMinute) return _err(c, 'Çok hızlı hediye gönderiyorsunuz');
    c.giftTimes.add(now);
    for (final seat in targets) {
      final to = t.seats[seat].player!;
      if (!t.deliverGift(u.id, seat, gift)) continue;
      u.coins -= gift.price;
      u.giftsSent++;
      final rec = store.users[to.userId];
      if (rec != null) {
        rec.giftsReceived++;
        final share = (gift.price * 0.1).round();
        if (share > 0) {
          rec.coins += share;
          store.addLedger(LedgerRec(rec.id, 'giftIncome', share, '${gift.name} ← ${u.displayName}'));
        }
        _toUser(rec.id, Ev.me, meJson(rec));
      }
    }
    store.addLedger(LedgerRec(u.id, 'gift', -total, 'Toplu ${gift.name} × ${targets.length}'));
    _toUser(u.id, Ev.me, meJson(u));
  }

  // ---------------------------------------------------------------------------
  // Admin API'si
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _adminUserRow(UserRec u) => {
        'id': u.id,
        'username': u.username,
        'displayName': u.displayName,
        'role': u.role,
        'status': u.status,
        'coins': u.coins,
        'level': u.level,
        'hearts': u.hearts,
        'color': u.color,
        'guest': u.guest,
        'totalSpent': u.totalSpent,
        'giftsSent': u.giftsSent,
        'giftsReceived': u.giftsReceived,
        'spins': u.spins,
        'email': u.email,
        'createdAt': u.createdAt.toIso8601String(),
        'lastSeen': u.lastSeen?.toIso8601String(),
        'isOnline': isOnline(u.id),
        'roomId': tableOf(u.id)?.id,
        'roomName': tableOf(u.id)?.name,
      };

  Map<String, dynamic> _adminRoom(GameTable t) {
    final now = DateTime.now();
    return {
      ...t.summary().toJson(),
      'round': t.roundView(now).toJson(),
      'seats': [for (final s in t.seats) s.toJson()],
      'chat': [for (final c in (t.chat.length > 20 ? t.chat.sublist(t.chat.length - 20) : t.chat)) c.toJson()],
      'totalMatches': t.totalMatches,
      'totalGifts': t.totalGifts,
    };
  }

  int _sumPaid(Iterable<OrderRec> os) => os.where((o) => o.status == 'paid').fold(0, (a, o) => a + o.amountKurus);

  List<int> _dailyRevenue(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = List<int>.filled(days, 0);
    for (final o in store.orders) {
      if (o.status != 'paid') continue;
      final d = today.difference(DateTime(o.createdAt.year, o.createdAt.month, o.createdAt.day)).inDays;
      if (d >= 0 && d < days) out[days - 1 - d] += o.amountKurus;
    }
    return out;
  }

  void _setUserStatus(UserRec u, String status) {
    u.status = status;
    final now = DateTime.now();
    if (status == 'banned' || status == 'suspended') {
      tableOf(u.id)?.leave(u.id, now, reason: 'masadan uzaklaştırıldı');
      for (final c in _clients.where((c) => c.userId == u.id).toList()) {
        c.send({'event': Ev.error, 'data': {'message': 'Hesabınız erişime kapatıldı'}});
        _clients.remove(c);
        c.close();
      }
      _sessions.removeWhere((_, s) => !s.admin && s.subject == u.id);
      return;
    }
    _toUser(u.id, Ev.me, meJson(u));
  }

  void _applyOrder(OrderRec o, String action, String actor) {
    final u = store.users[o.userId];
    switch (action) {
      case 'approve':
        if (o.status != 'pending' && o.status != 'failed') throw ApiError(409, 'Bu sipariş onaylanamaz');
        o.status = 'paid';
        if (u != null) {
          u.coins += o.coins;
          u.totalSpent += o.amountKurus;
          final pkg = store.packages.where((p) => p.id == o.packageId).firstOrNull;
          if ((pkg?.vipDays ?? 0) > 0 && u.role == 'player') u.role = 'vip';
          store.addLedger(LedgerRec(u.id, 'purchase', o.coins, '${o.packageName} (${o.id})'));
          _toUser(u.id, Ev.me, meJson(u));
        }
      case 'refund':
        if (o.status != 'paid') throw ApiError(409, 'Yalnız ödenmiş sipariş iade edilir');
        o.status = 'refunded';
        if (u != null) {
          final take = math.min(u.coins, o.coins);
          u.coins -= take;
          u.totalSpent -= o.amountKurus;
          store.addLedger(LedgerRec(u.id, 'refund', -take, 'İade ${o.id}'));
          _toUser(u.id, Ev.me, meJson(u));
        }
      case 'cancel':
        if (o.status != 'pending') throw ApiError(409, 'Yalnız bekleyen sipariş iptal edilir');
        o.status = 'cancelled';
      default:
        throw ApiError(400, 'Bilinmeyen işlem');
    }
    o.updatedAt = DateTime.now();
    store.log(actor, 'Sipariş: $action', o.id);
  }

  Future<Object?> _admin(HttpRequest req) async {
    final path = req.uri.path.substring('/admin/api/v1'.length);
    final m = req.method;
    final ip = _ip(req);

    if (m == 'POST' && path == '/login') {
      final b = await _body(req);
      final key = 'a:$ip';
      _throttleLogin(key);
      final name = '${b['username'] ?? ''}'.trim();
      final a = store.admins[name.toLowerCase()];
      if (a == null || !verifyPassword('${b['password'] ?? ''}', a.passwordHash)) {
        _loginFailed(key, 'yönetici "$name" ($ip)');
        throw ApiError(401, 'Kullanıcı adı veya şifre hatalı');
      }
      a.lastLogin = DateTime.now();
      store.securityEvent('info', 'Yönetici girişi: ${a.username} ($ip)', actor: a.username);
      return {'token': _issue(a.username, admin: true), 'username': a.username, 'role': a.role};
    }

    final admin = _requireAdmin(req);
    final actor = admin.username;
    final seg = path.split('/').where((e) => e.isNotEmpty).toList();

    if (m == 'POST' && path == '/logout') {
      final t = _bearer(req);
      if (t != null) _sessions.remove(t);
      return {'ok': true};
    }
    if (m == 'GET' && path == '/me') return {'username': admin.username, 'role': admin.role};
    if (m == 'POST' && path == '/password') {
      final b = await _body(req);
      if (!verifyPassword('${b['current'] ?? ''}', admin.passwordHash)) throw ApiError(400, 'Mevcut şifre hatalı');
      final next = '${b['next'] ?? ''}';
      final e = validatePassword(next);
      if (e != null) throw ApiError(400, e);
      admin.passwordHash = hashPassword(next);
      _sessions.removeWhere((k, s) => s.admin && s.subject == admin.username && k != _bearer(req));
      store.securityEvent('info', 'Yönetici şifresi değişti: $actor', actor: actor);
      return {'ok': true};
    }

    // --- Yöneticiler ---
    if (path == '/admins') {
      if (m == 'GET') {
        return {
          'items': [
            for (final a in store.admins.values)
              {'username': a.username, 'role': a.role, 'lastLogin': a.lastLogin?.toIso8601String()}
          ]
        };
      }
      if (m == 'POST') {
        if (admin.role != 'owner') throw ApiError(403, 'Yalnız sahip hesap yönetici ekleyebilir');
        final b = await _body(req);
        final name = '${b['username'] ?? ''}'.trim();
        if (!usernamePattern.hasMatch(name)) throw ApiError(400, 'Geçersiz kullanıcı adı');
        if (store.admins.containsKey(name.toLowerCase())) throw ApiError(409, 'Bu yönetici zaten var');
        final pe = validatePassword('${b['password'] ?? ''}');
        if (pe != null) throw ApiError(400, pe);
        final role = b['role'] == 'moderator' ? 'moderator' : 'admin';
        store.admins[name.toLowerCase()] =
            AdminRec(username: name, passwordHash: hashPassword('${b['password']}'), role: role);
        store.log(actor, 'Yönetici eklendi ($role)', name);
        return {'ok': true};
      }
    }

    // --- Kontrol merkezi ---
    if (m == 'GET' && path == '/dashboard') {
      final now = DateTime.now();
      final today = store.orders.where((o) => now.difference(o.createdAt).inHours < 24);
      return {
        'online': _clients.map((c) => c.userId).toSet().length,
        'seated': tables.values.fold(0, (a, t) => a + t.occupied),
        'activeRooms': tables.values.where((t) => !t.closed).length,
        'users': store.users.length,
        'banned': store.users.values.where((u) => u.status == 'banned').length,
        'todayRevenue': _sumPaid(today),
        'pendingOrders': store.orders.where((o) => o.status == 'pending').length,
        'revenue14': _dailyRevenue(14),
        'rooms': [for (final t in tables.values) if (!t.closed) t.summary().toJson()],
        'audit': [for (final a in store.audit.take(10)) a.toJson()],
        'maintenance': store.settings.maintenance,
      };
    }
    if (m == 'POST' && path == '/broadcast') {
      final b = await _body(req);
      final text = _clip('${b['text'] ?? ''}'.trim(), 300);
      if (text.isEmpty) throw ApiError(400, 'Metin boş');
      for (final t in tables.values.where((t) => !t.closed)) {
        t.broadcast(text);
      }
      store.log(actor, 'Duyuru', text);
      return {'ok': true};
    }

    // --- Oyuncular ---
    if (m == 'GET' && path == '/users') {
      final q = req.uri.queryParameters;
      final text = (q['q'] ?? '').toLowerCase();
      var list = store.users.values.where((u) {
        if (text.isNotEmpty &&
            !u.username.toLowerCase().contains(text) &&
            !u.displayName.toLowerCase().contains(text) &&
            !u.email.toLowerCase().contains(text) &&
            u.id != text) {
          return false;
        }
        if ((q['status'] ?? '').isNotEmpty && u.status != q['status']) return false;
        if ((q['role'] ?? '').isNotEmpty && u.role != q['role']) return false;
        if (q['online'] == '1' && !isOnline(u.id)) return false;
        return true;
      }).toList();
      int Function(UserRec, UserRec) cmp = switch (q['sort']) {
        'coins' => (a, b) => b.coins.compareTo(a.coins),
        'spent' => (a, b) => b.totalSpent.compareTo(a.totalSpent),
        'hearts' => (a, b) => b.hearts.compareTo(a.hearts),
        'level' => (a, b) => b.level.compareTo(a.level),
        _ => (a, b) => b.createdAt.compareTo(a.createdAt),
      };
      list.sort(cmp);
      final total = list.length;
      list = list.take(300).toList();
      return {'total': total, 'items': [for (final u in list) _adminUserRow(u)]};
    }
    if (seg.length == 2 && seg[0] == 'users' && m == 'GET') {
      final u = store.users[seg[1]] ?? (throw ApiError(404, 'Oyuncu yok'));
      return {
        ..._adminUserRow(u),
        'notes': u.notes,
        'warnings': u.warnings,
        'ledger': [for (final e in store.ledger.reversed.where((e) => e.userId == u.id).take(40)) e.toJson()],
        'orders': [for (final o in store.orders.where((o) => o.userId == u.id).take(40)) o.toJson()],
      };
    }
    if (seg.length == 3 && seg[0] == 'users' && seg[2] == 'action' && m == 'POST') {
      final u = store.users[seg[1]] ?? (throw ApiError(404, 'Oyuncu yok'));
      final b = await _body(req);
      final action = '${b['action']}';
      switch (action) {
        case 'coins':
          final delta = b['delta'] is num ? (b['delta'] as num).toInt() : 0;
          if (delta == 0 || delta.abs() > 10000000) throw ApiError(400, 'Geçersiz miktar');
          final memo = _clip('${b['memo'] ?? 'manuel'}', 120);
          final applied = delta < 0 ? -math.min(u.coins, -delta) : delta;
          u.coins += applied;
          store.addLedger(LedgerRec(u.id, 'adminAdjust', applied, '$memo ($actor)'));
          store.log(actor, 'Coin ${applied >= 0 ? '+' : ''}$applied ($memo)', u.username);
          _toUser(u.id, Ev.me, meJson(u));
        case 'status':
          final st = '${b['status']}';
          if (!const {'active', 'muted', 'suspended', 'banned'}.contains(st)) throw ApiError(400, 'Geçersiz durum');
          _setUserStatus(u, st);
          store.log(actor, 'Durum → $st${b['reason'] != null ? ' (${_clip('${b['reason']}', 120)})' : ''}', u.username);
        case 'role':
          final r = '${b['role']}';
          if (!const {'player', 'vip', 'moderator'}.contains(r)) throw ApiError(400, 'Geçersiz rol');
          u.role = r;
          store.log(actor, 'Rol → $r', u.username);
        case 'warn':
          final w = _clip('${b['text'] ?? ''}'.trim(), 300);
          if (w.isEmpty) throw ApiError(400, 'Metin boş');
          u.warnings.add(w);
          _toUser(u.id, Ev.error, {'message': 'Yönetici uyarısı: $w'});
          store.log(actor, 'Uyarı: $w', u.username);
        case 'note':
          final w = _clip('${b['text'] ?? ''}'.trim(), 500);
          if (w.isEmpty) throw ApiError(400, 'Metin boş');
          u.notes.add('$w — $actor');
          store.log(actor, 'Not eklendi', u.username);
        case 'kick':
          final t = tableOf(u.id) ?? (throw ApiError(409, 'Oyuncu masada değil'));
          t.leave(u.id, DateTime.now(), reason: 'yönetici tarafından masadan çıkarıldı');
          store.log(actor, 'Masadan çıkarıldı (${t.name})', u.username);
        case 'rename':
          final d = _clip('${b['displayName'] ?? ''}'.trim(), 20);
          if (d.length < 2) throw ApiError(400, 'Ad çok kısa');
          u.displayName = d;
          store.log(actor, 'Ad değiştirildi → $d', u.username);
        case 'resetPassword':
          final pe = validatePassword('${b['password'] ?? ''}');
          if (pe != null) throw ApiError(400, pe);
          u.passwordHash = hashPassword('${b['password']}');
          _sessions.removeWhere((_, s) => !s.admin && s.subject == u.id);
          store.log(actor, 'Şifre sıfırlandı', u.username);
        default:
          throw ApiError(400, 'Bilinmeyen işlem');
      }
      store.markDirty();
      return _adminUserRow(u);
    }

    // --- Masalar ---
    if (path == '/rooms') {
      if (m == 'GET') return {'items': [for (final t in tables.values) _adminRoom(t)]};
      if (m == 'POST') {
        final b = await _body(req);
        final name = _clip('${b['name'] ?? ''}'.trim(), 40);
        if (name.isEmpty) throw ApiError(400, 'Masa adı gerekli');
        final r = RoomRec(id: '${store.seq + 1}', name: name, theme: (b['theme'] as num?)?.toInt() ?? store.rooms.length % 4);
        store.seq++;
        store.rooms.add(r);
        _mountTable(r);
        store.log(actor, 'Masa oluşturuldu', name);
        return _adminRoom(tables[r.id]!);
      }
    }
    if (seg.length == 3 && seg[0] == 'rooms' && seg[2] == 'action' && m == 'POST') {
      final t = tables[seg[1]] ?? (throw ApiError(404, 'Masa yok'));
      final r = store.rooms.firstWhere((x) => x.id == t.id);
      final b = await _body(req);
      final now = DateTime.now();
      switch ('${b['action']}') {
        case 'lock':
          t.locked = r.locked = true;
        case 'unlock':
          t.locked = r.locked = false;
        case 'close':
          for (final p in t.players.toList()) {
            t.leave(p.userId, now, reason: 'masa kapatıldığı için ayrıldı');
          }
          t.closed = r.closed = true;
        case 'open':
          t.closed = r.closed = false;
        case 'rename':
          final n = _clip('${b['name'] ?? ''}'.trim(), 40);
          if (n.isEmpty) throw ApiError(400, 'Ad boş');
          t.name = r.name = n;
        case 'theme':
          t.theme = r.theme = ((b['theme'] as num?)?.toInt() ?? 0) % 4;
        case 'broadcast':
          final text = _clip('${b['text'] ?? ''}'.trim(), 300);
          if (text.isEmpty) throw ApiError(400, 'Metin boş');
          t.broadcast(text);
        case 'delete':
          if (t.occupied > 0) throw ApiError(409, 'Önce masayı kapatın');
          store.rooms.remove(r);
          tables.remove(t.id);
          await _tableSubs.remove(t.id)?.cancel();
          store.log(actor, 'Masa silindi', t.name);
          return {'ok': true};
        default:
          throw ApiError(400, 'Bilinmeyen işlem');
      }
      t.version++;
      store.log(actor, 'Masa: ${b['action']}', t.name);
      return _adminRoom(t);
    }

    // --- Ekonomi ---
    if (m == 'GET' && path == '/economy') {
      final days = (int.tryParse(req.uri.queryParameters['days'] ?? '') ?? 30).clamp(1, 365);
      final since = DateTime.now().subtract(Duration(days: days));
      final inRange = store.orders.where((o) => o.createdAt.isAfter(since)).toList();
      final paid = inRange.where((o) => o.status == 'paid').toList();
      final revenue = _sumPaid(inRange);
      final refunded =
          inRange.where((o) => o.status == 'refunded').fold(0, (a, o) => a + o.amountKurus);
      final buyers = paid.map((o) => o.userId).toSet().length;
      final byProvider = <String, int>{};
      final byPackage = <String, int>{};
      for (final o in paid) {
        byProvider[o.provider] = (byProvider[o.provider] ?? 0) + o.amountKurus;
        byPackage[o.packageName] = (byPackage[o.packageName] ?? 0) + o.amountKurus;
      }
      final ledger = <String, int>{};
      for (final e in store.ledger.where((e) => e.at.isAfter(since))) {
        ledger[e.kind] = (ledger[e.kind] ?? 0) + e.delta;
      }
      final top = store.users.values.where((u) => u.totalSpent > 0).toList()
        ..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
      return {
        'days': days,
        'revenue': revenue,
        'refunded': refunded,
        'net': revenue - refunded,
        'buyers': buyers,
        'arppu': buyers == 0 ? 0 : revenue ~/ buyers,
        'conversion': store.users.isEmpty ? 0 : buyers / store.users.length * 100,
        'failed': inRange.where((o) => o.status == 'failed').length,
        'daily': _dailyRevenue(days),
        'byProvider': byProvider,
        'byPackage': byPackage,
        'ledger': ledger,
        'coinsInCirculation': store.users.values.fold(0, (a, u) => a + u.coins),
        'top': [for (final u in top.take(10)) _adminUserRow(u)],
      };
    }

    // --- Market ---
    if (path == '/packages') {
      if (m == 'GET') return {'items': [for (final p in store.packages) p.toJson()]};
      if (m == 'POST') {
        final b = await _body(req);
        final name = _clip('${b['name'] ?? ''}'.trim(), 40);
        final coins = (b['coins'] as num?)?.toInt() ?? -1;
        final price = (b['priceKurus'] as num?)?.toInt() ?? -1;
        if (name.isEmpty || coins <= 0 || price <= 0) throw ApiError(400, 'Ad, coin ve fiyat gerekli');
        var p = store.packages.where((x) => x.id == b['id']).firstOrNull;
        if (p == null) {
          p = PackageRec(id: store.nextId('p'), name: name, coins: coins, priceKurus: price);
          store.packages.add(p);
        }
        p
          ..name = name
          ..coins = coins
          ..priceKurus = price
          ..bonusPercent = ((b['bonusPercent'] as num?)?.toInt() ?? 0).clamp(0, 500)
          ..vipDays = ((b['vipDays'] as num?)?.toInt() ?? 0).clamp(0, 3650)
          ..active = b['active'] as bool? ?? p.active
          ..featured = b['featured'] as bool? ?? p.featured;
        store.log(actor, 'Paket kaydedildi', name);
        return p.toJson();
      }
    }
    if (path == '/gifts') {
      if (m == 'GET') return {'items': store.gifts};
      if (m == 'POST') {
        final b = await _body(req);
        final name = _clip('${b['name'] ?? ''}'.trim(), 30);
        final price = (b['price'] as num?)?.toInt() ?? -1;
        if (name.isEmpty || price < 0) throw ApiError(400, 'Ad ve fiyat gerekli');
        final g = GiftInfo(
          id: (b['id'] is String && (b['id'] as String).isNotEmpty) ? b['id'] as String : store.nextId('g'),
          name: name,
          emoji: _clip('${b['emoji'] ?? '🎁'}', 16),
          price: price,
          category: _clip('${b['category'] ?? 'Klasik'}', 30),
          enabled: b['enabled'] as bool? ?? true,
        ).toJson();
        final i = store.gifts.indexWhere((x) => x['id'] == g['id']);
        if (i < 0) {
          store.gifts.add(g);
        } else {
          store.gifts[i] = g;
        }
        store.log(actor, 'Hediye kaydedildi', name);
        return g;
      }
    }

    // --- Siparişler ---
    if (m == 'GET' && path == '/orders') {
      final q = req.uri.queryParameters;
      final text = (q['q'] ?? '').toLowerCase();
      final list = store.orders.where((o) {
        if ((q['status'] ?? '').isNotEmpty && o.status != q['status']) return false;
        if (text.isNotEmpty) {
          final u = store.users[o.userId];
          if (!o.id.toLowerCase().contains(text) && !(u?.username.toLowerCase().contains(text) ?? false)) return false;
        }
        return true;
      }).take(300);
      final counts = <String, int>{};
      for (final o in store.orders) {
        counts[o.status] = (counts[o.status] ?? 0) + 1;
      }
      return {
        'counts': counts,
        'items': [
          for (final o in list)
            {...o.toJson(), 'username': store.users[o.userId]?.username, 'displayName': store.users[o.userId]?.displayName}
        ]
      };
    }
    if (seg.length == 3 && seg[0] == 'orders' && seg[2] == 'action' && m == 'POST') {
      final o = store.orders.where((o) => o.id == seg[1]).firstOrNull ?? (throw ApiError(404, 'Sipariş yok'));
      final b = await _body(req);
      _applyOrder(o, '${b['action']}', actor);
      store.markDirty();
      return o.toJson();
    }

    // --- Ayarlar ---
    if (path == '/settings') {
      if (m == 'GET') return {'settings': store.settings.toJson(), 'rules': rules.toJson()};
      if (m == 'PUT') {
        final b = await _body(req);
        final before = store.settings.toJson().toString() + rules.toJson().toString();
        if (b['settings'] is Map) store.settings.apply((b['settings'] as Map).cast<String, dynamic>());
        if (b['rules'] is Map) rules.apply((b['rules'] as Map).cast<String, dynamic>());
        store.rules = rules.toJson();
        if (before != store.settings.toJson().toString() + rules.toJson().toString()) {
          store.log(actor, 'Ayarlar güncellendi', (b['what'] ?? '').toString());
        }
        return {'settings': store.settings.toJson(), 'rules': rules.toJson()};
      }
    }
    if (m == 'GET' && path == '/security') {
      return {
        'events': [for (final e in store.security.take(100)) e.toJson()],
        'audit': [for (final e in store.audit.take(200)) e.toJson()],
      };
    }
    if (m == 'GET' && path == '/export') {
      return {
        'exportedAt': DateTime.now().toIso8601String(),
        'settings': store.settings.toJson(),
        'rules': rules.toJson(),
        'rooms': [for (final r in store.rooms) r.toJson()],
        'packages': [for (final p in store.packages) p.toJson()],
        'gifts': store.gifts,
      };
    }
    throw ApiError(404, 'Bulunamadı');
  }

  // ---------------------------------------------------------------------------
  // Statik dosyalar (Flutter web derlemesi)
  // ---------------------------------------------------------------------------

  static const _types = {
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'mjs': 'text/javascript; charset=utf-8',
    'json': 'application/json',
    'wasm': 'application/wasm',
    'css': 'text/css',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'svg': 'image/svg+xml',
    'ico': 'image/x-icon',
    'ttf': 'font/ttf',
    'otf': 'font/otf',
    'woff2': 'font/woff2',
    'bin': 'application/octet-stream',
    'symbols': 'text/plain',
  };

  Future<void> _static(HttpRequest req) async {
    final root = webRoot;
    final res = req.response;
    if (root == null || (req.method != 'GET' && req.method != 'HEAD')) throw ApiError(404, 'Bulunamadı');
    // Çok iş parçacıklı WebAssembly (Skwasm) için gerekli başlıklar.
    res.headers
      ..set('Cross-Origin-Opener-Policy', 'same-origin')
      ..set('Cross-Origin-Embedder-Policy', 'require-corp');
    var rel = Uri.decodeComponent(req.uri.path);
    if (rel.endsWith('/')) rel += 'index.html';
    final segments = rel.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.any((s) => s == '..' || s.startsWith('.'))) throw ApiError(404, 'Bulunamadı');
    var file = File([root.path, ...segments].join(Platform.pathSeparator));
    if (!await file.exists()) file = File('${root.path}${Platform.pathSeparator}index.html');
    if (!await file.exists()) throw ApiError(404, 'Bulunamadı');
    final ext = file.path.split('.').last.toLowerCase();
    res.headers.set(HttpHeaders.contentTypeHeader, _types[ext] ?? 'application/octet-stream');
    final noCache = ext == 'html' || file.path.endsWith('flutter_bootstrap.js') || file.path.endsWith('version.json');
    res.headers.set('Cache-Control', noCache ? 'no-cache' : 'public, max-age=3600');
    if (req.method == 'HEAD') {
      await res.close();
      return;
    }
    await res.addStream(file.openRead());
    await res.close();
  }
}
