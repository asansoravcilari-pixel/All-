import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:spectre_core/spectre_core.dart';

import 'auth.dart';
import 'mail.dart';
import 'paytr.dart';
import 'store.dart';
import 'support.dart';

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
    _applyAnimRules();
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
    for (final f in kBuiltinFeatures) {
      if (store.feature(f.key) == null) store.features.add(FeatureRec.fromJson(f.toJson()));
    }
    if (store.kb.isEmpty && store.users.isEmpty) store.kb.addAll(kDefaultKb);
    await _ensureOwner(adminUser, adminPassword);
    _http = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    _http!.autoCompress = true;
    _http!.listen(_handle);
    _tick = Timer.periodic(tickInterval, (_) => _onTick());
    _flush = Timer.periodic(const Duration(seconds: 2), (_) => store.flush());
    _expiry = Timer.periodic(const Duration(seconds: 30), (_) => checkExpiry(DateTime.now()));
  }

  Timer? _expiry;

  /// Animasyon süreleri tur zamanlamasını da belirler.
  void _applyAnimRules() {
    final a = store.settings.effectiveAnimations;
    rules.spinDuration = Duration(milliseconds: ((a['spinMs'] as num?) ?? 3400).toInt().clamp(1500, 10000));
    rules.resultDuration = Duration(milliseconds: ((a['resultMs'] as num?) ?? 2200).toInt().clamp(800, 8000));
  }

  Future<void> stop() async {
    _tick?.cancel();
    _flush?.cancel();
    _expiry?.cancel();
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
        if (!line.system && store.settings.translateEnabled) {
          final langs = {
            for (final p in t.players)
              if (store.users[p.userId] case final u? when allowed(u, 'translate')) u.lang,
          };
          _translateFor(line.text, langs).then((tr) {
            if (tr.isEmpty) return;
            t.addTranslations(line.id, tr);
            _toChannel(ch, Ev.chatTranslated, {'id': line.id, 'translations': tr});
          });
        }
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
              final other = t.seats[idx == a ? b : a].player?.name ?? '';
              _notify(u.id, 'match', '$other ile eşleştin! +1 ♥');
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
      final eps = store.settings.effectiveEndpoints;
      if (path == eps['ws'] || path == '/ws') return await _upgrade(req);
      if (path.startsWith('/admin/api/')) return await _json(req, await _admin(req));
      if (path.startsWith('/uploads/')) return await _upload(req);
      if (path == '/eposta-dogrula') return await _verifyPage(req);
      if (path == '/sifre-sifirla') return await _resetPage(req);
      if (path == '/api/v1/pay/paytr/callback' && req.method == 'POST') return await _paytrCallback(req);
      if (path == '/api/v1/config' || path == '/api/v1/health') return await _json(req, await _public(req, path, const {}));
      final route = _match(path, eps);
      if (route != null) return await _json(req, await _public(req, route.$1, route.$2));
      if (path.startsWith('/api/')) throw ApiError(404, 'Bulunamadı');
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
        'lang': u.lang,
        'canClaimDaily': _canClaimDaily(u),
        'unreadNotices': store.unreadNotices(u.id),
        'unreadDms': store.unreadDms(u.id),
        'email': u.email,
        'emailVerified': u.emailVerified,
        'entitlements': {
          for (final e in u.entitlements.entries)
            if (DateTime.now().isBefore(e.value)) e.key: e.value.toIso8601String(),
        },
        'locked': [for (final f in store.features) if (!allowed(u, f.key)) f.key],
        'features': {for (final f in store.features) f.key: f.name},
        'inventory': {for (final e in u.inventory.entries) if (e.value > 0) e.key: e.value},
      };

  /// Kullanıcı bu özelliği kullanabilir mi? (Kilitli değilse herkes; kilitliyse hakkı olan.)
  bool allowed(UserRec u, String key) {
    final f = store.feature(key);
    if (f == null || !f.locked) return true;
    return u.has(key);
  }

  String _lockedMsg(String key) => '${store.feature(key)?.name ?? key} paketinde yok — Market\'ten açabilirsin';

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
        vip: u.isVip || u.has('vipBadge'),
        hearts: u.hearts,
      );

  UserRec _createUser(String username, String displayName, String password, {bool guest = false, String email = ''}) {
    final u = UserRec(
      email: email,
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

  // ---------------------------------------------------------------------------
  // Haklar (abonelik / özellik), paket içi hediyeler, otomatik bitiş
  // ---------------------------------------------------------------------------

  static final _forever = DateTime(2100);

  /// Ödenen paketin içeriğini tanımlar: coin, özellik hakları, hediyeler.
  List<String> grantPackage(UserRec u, PackageRec pkg, {int sign = 1}) {
    final now = DateTime.now();
    final granted = <String>[];
    final keys = {...pkg.features, if (pkg.vipDays > 0) 'vipBadge'};
    for (final k in keys) {
      final days = k == 'vipBadge' && pkg.vipDays > 0 && !pkg.features.contains(k) ? pkg.vipDays : pkg.periodDays;
      final cur = u.entitlements[k];
      if (sign > 0) {
        final base = cur != null && cur.isAfter(now) ? cur : now;
        u.entitlements[k] = days <= 0 ? _forever : base.add(Duration(days: days));
        u.expiryWarned.removeWhere((w) => w.startsWith('$k@'));
      } else if (cur != null) {
        final back = days <= 0 ? now : cur.subtract(Duration(days: days));
        if (back.isAfter(now)) {
          u.entitlements[k] = back;
        } else {
          u.entitlements.remove(k);
        }
      }
      granted.add(store.feature(k)?.name ?? k);
    }
    for (final g in pkg.gifts) {
      final id = '${g['giftId']}';
      final qty = (g['qty'] as num?)?.toInt() ?? 0;
      if (qty <= 0) continue;
      u.inventory[id] = math.max(0, (u.inventory[id] ?? 0) + sign * qty);
    }
    store.markDirty();
    tableOf(u.id)?.updatePlayer(_seatPlayer(u));
    return granted;
  }

  /// Süresi dolan hakları kaldırır, bitmeden 3 gün önce uyarır.
  void checkExpiry(DateTime now) {
    for (final u in store.users.values) {
      if (u.entitlements.isEmpty) continue;
      var changed = false;
      for (final e in u.entitlements.entries.toList()) {
        final name = store.feature(e.key)?.name ?? e.key;
        if (!now.isBefore(e.value)) {
          u.entitlements.remove(e.key);
          changed = true;
          _notify(u.id, 'order', '$name süren doldu');
          _mail(u, 'expired', {'feature': name, 'expires': _date(e.value)});
        } else if (e.value != _forever && e.value.difference(now).inDays < 3) {
          final tag = '${e.key}@${e.value.toIso8601String()}';
          if (u.expiryWarned.add(tag)) {
            changed = true;
            final days = math.max(1, e.value.difference(now).inHours ~/ 24);
            _notify(u.id, 'order', '$name $days gün içinde bitiyor');
            _mail(u, 'expiring', {'feature': name, 'days': '$days', 'expires': _date(e.value)});
          }
        }
      }
      if (changed) {
        store.markDirty();
        _toUser(u.id, Ev.me, meJson(u));
        tableOf(u.id)?.updatePlayer(_seatPlayer(u));
      }
    }
  }

  static String _date(DateTime d) => d == _forever
      ? 'süresiz'
      : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------------------
  // Mail
  // ---------------------------------------------------------------------------

  /// Test için gönderim yerine geçebilir.
  Future<void> Function(MailConfig c, String to, String subject, String html)? mailSender;

  MailConfig get _mailConfig {
    final s = store.settings;
    return MailConfig(
      host: s.smtpHost,
      port: s.smtpPort,
      security: s.smtpSecurity,
      user: s.smtpUser,
      password: s.smtpPassword,
      from: s.mailFrom,
      fromName: s.mailFromName,
    );
  }

  Map<String, String> templateOf(String key) => {
        ...?kDefaultMailTemplates[key],
        ...?store.settings.mailTemplates[key],
      };

  Future<bool> sendTemplate(String to, String key, Map<String, String> vars) async {
    final s = store.settings;
    final tpl = templateOf(key);
    final all = {'brand': s.brandName, 'site': s.publicBaseUrl, ...vars};
    final subject = renderTemplate(tpl['subject'] ?? '', all);
    final html = renderTemplate(tpl['body'] ?? '', all, html: true);
    final entry = <String, dynamic>{'at': DateTime.now().toIso8601String(), 'to': to, 'template': key, 'subject': subject};
    try {
      final sender = mailSender;
      if (sender != null) {
        await sender(_mailConfig, to, subject, html);
      } else {
        await sendMail(_mailConfig, to: to, subject: subject, html: html);
      }
      entry['ok'] = true;
      return true;
    } catch (e) {
      entry['ok'] = false;
      entry['error'] = '$e'.length > 200 ? '$e'.substring(0, 200) : '$e';
      return false;
    } finally {
      store.mailLog.add(entry);
      if (store.mailLog.length > 300) store.mailLog.removeAt(0);
      store.markDirty();
    }
  }

  /// Kullanıcıya şablonlu mail (mail kapalıysa ya da adres yoksa sessizce geçer).
  void _mail(UserRec u, String key, Map<String, String> vars) {
    if (!store.settings.mailEnabled || u.email.isEmpty) return;
    sendTemplate(u.email, key, {'name': u.displayName, 'username': u.username, ...vars});
  }

  String _link(String path, String token) {
    final base = store.settings.publicBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base$path?token=${Uri.encodeQueryComponent(token)}';
  }

  String _newToken(UserRec u, String kind, Duration ttl) {
    store.tokens.removeWhere((t) => t.userId == u.id && t.kind == kind);
    final t = TokenRec(randomToken(24), u.id, kind, DateTime.now().add(ttl));
    store.tokens.add(t);
    store.markDirty();
    return t.token;
  }

  TokenRec? _takeToken(String? token, String kind) {
    if (token == null) return null;
    final t = store.tokens.where((x) => x.token == token && x.kind == kind).firstOrNull;
    if (t == null) return null;
    store.tokens.remove(t);
    store.markDirty();
    return DateTime.now().isBefore(t.expires) ? t : null;
  }

  void _sendVerify(UserRec u, {bool welcome = false}) {
    if (u.email.isEmpty) return;
    final link = _link('/eposta-dogrula', _newToken(u, 'verify', const Duration(hours: 48)));
    _mail(u, welcome ? 'welcome' : 'verify', {'link': link});
  }

  static final _emailPattern = RegExp(r'^[^@\s]{1,64}@[^@\s]{1,190}\.[^@\s]{2,24}$');

  /// Basit HTML sayfası (e-posta doğrulama / şifre sıfırlama).
  Future<void> _page(HttpRequest req, String title, String bodyHtml, {int status = 200}) async {
    final s = store.settings;
    String esc(String v) => v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    final res = req.response;
    res.statusCode = status;
    res.headers
      ..contentType = ContentType.html
      ..set('Cache-Control', 'no-store')
      ..set('Content-Security-Policy', "default-src 'self'; style-src 'unsafe-inline'; form-action 'self'");
    res.write('<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>${esc(title)}</title><style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:${esc(s.backgroundColor)};'
        'font-family:system-ui,sans-serif;color:#eff8ff}main{background:#122737;border:1px solid #a3d4f22e;border-radius:18px;padding:28px;'
        'width:min(92vw,380px)}h1{font-size:20px;margin:0 0 12px}input{width:100%;box-sizing:border-box;padding:12px;border-radius:10px;'
        'border:1px solid #3e7aa1;background:#0b2843;color:#fff;margin:6px 0 12px}button{width:100%;padding:12px;border:0;border-radius:10px;'
        'background:${esc(s.accentColor)};color:#021220;font-weight:800}a{color:${esc(s.accentColor)}}p{color:#adc6d8}</style></head>'
        '<body><main><h1>${esc(s.brandName)} — ${esc(title)}</h1>$bodyHtml</main></body></html>');
    await res.close();
  }

  Future<void> _verifyPage(HttpRequest req) async {
    final t = _takeToken(req.uri.queryParameters['token'], 'verify');
    final u = t == null ? null : store.users[t.userId];
    if (u == null) return _page(req, 'E-posta doğrulama', '<p>Bağlantı geçersiz ya da süresi dolmuş.</p>', status: 400);
    u.emailVerified = true;
    store.markDirty();
    _toUser(u.id, Ev.me, meJson(u));
    return _page(req, 'E-posta doğrulandı', '<p>Teşekkürler ${u.displayName}, e-posta adresin doğrulandı. Oyuna dönebilirsin.</p>');
  }

  Future<void> _resetPage(HttpRequest req) async {
    final token = req.uri.queryParameters['token'] ?? '';
    final valid = store.tokens.any((x) => x.token == token && x.kind == 'reset' && DateTime.now().isBefore(x.expires));
    if (req.method == 'POST') {
      final form = Uri.splitQueryString(await utf8.decoder.bind(req).join());
      final t = _takeToken(form['token'], 'reset');
      final u = t == null ? null : store.users[t.userId];
      if (u == null) return _page(req, 'Şifre sıfırlama', '<p>Bağlantı geçersiz ya da süresi dolmuş.</p>', status: 400);
      final pe = validatePassword(form['password'] ?? '');
      if (pe != null || form['password'] != form['password2']) {
        final nt = _newToken(u, 'reset', const Duration(hours: 1));
        return _page(req, 'Şifre sıfırlama',
            '<p>${pe ?? 'Şifreler aynı değil'}</p><a href="/sifre-sifirla?token=$nt">Tekrar dene</a>', status: 400);
      }
      u.passwordHash = hashPassword(form['password']!);
      _sessions.removeWhere((_, s) => !s.admin && s.subject == u.id);
      store.securityEvent('info', 'Şifre sıfırlandı: ${u.username}');
      store.markDirty();
      return _page(req, 'Şifre değişti', '<p>Yeni şifrenle giriş yapabilirsin.</p><p><a href="/">Oyuna git</a></p>');
    }
    if (!valid) return _page(req, 'Şifre sıfırlama', '<p>Bağlantı geçersiz ya da süresi dolmuş.</p>', status: 400);
    return _page(
        req,
        'Yeni şifre',
        '<form method="post" action="/sifre-sifirla"><input type="hidden" name="token" value="${Uri.encodeQueryComponent(token)}">'
            '<label>Yeni şifre<input type="password" name="password" minlength="8" required autocomplete="new-password"></label>'
            '<label>Yeni şifre (tekrar)<input type="password" name="password2" minlength="8" required autocomplete="new-password"></label>'
            '<button type="submit">Şifreyi değiştir</button></form>');
  }

  // ---------------------------------------------------------------------------
  // Sanal POS (PayTR)
  // ---------------------------------------------------------------------------

  Paytr get _paytr {
    final s = store.settings;
    return Paytr(
      merchantId: s.paytrMerchantId,
      merchantKey: s.paytrMerchantKey,
      merchantSalt: s.paytrMerchantSalt,
      testMode: s.paytrTestMode,
    );
  }

  /// PayTR ödeme bildirimi: imza doğrulanır, sipariş otomatik onaylanır.
  Future<void> _paytrCallback(HttpRequest req) async {
    final form = Uri.splitQueryString(await utf8.decoder.bind(req).join());
    final oid = form['merchant_oid'] ?? '';
    final status = form['status'] ?? '';
    final total = form['total_amount'] ?? '';
    final ok = _paytr.configured &&
        _paytr.verifyCallback(merchantOid: oid, status: status, totalAmount: total, hash: form['hash'] ?? '');
    final res = req.response;
    res.headers.contentType = ContentType.text;
    if (!ok) {
      store.securityEvent('warn', 'Geçersiz PayTR bildirimi (sipariş $oid, ${_ip(req)})');
      res.statusCode = 400;
      res.write('PAYTR notification failed: bad hash');
      await res.close();
      return;
    }
    final o = store.orders.where((x) => x.id == oid).firstOrNull;
    if (o != null && o.status == 'pending') {
      if (status == 'success') {
        _applyOrder(o, 'approve', 'paytr');
      } else {
        o.status = 'failed';
        o.note = form['failed_reason_msg'] ?? '';
        o.updatedAt = DateTime.now();
        final u = store.users[o.userId];
        if (u != null) _notify(u.id, 'order', 'Ödeme tamamlanamadı: ${o.packageName}');
      }
      store.markDirty();
    }
    // PayTR, yanıt "OK" olana kadar bildirimi tekrarlar.
    res.write('OK');
    await res.close();
  }

  // ---------------------------------------------------------------------------
  // Destek robotu
  // ---------------------------------------------------------------------------

  Ticket _ticketOf(UserRec u) {
    final open = store.tickets.where((t) => t.userId == u.id && t.status != 'closed').lastOrNull;
    if (open != null) return open;
    final t = Ticket(id: store.nextId('t'), userId: u.id);
    t.messages.add(TicketMsg('bot', store.settings.supportGreeting));
    store.tickets.add(t);
    store.markDirty();
    return t;
  }

  String _botReply(UserRec u, Ticket t, String text) {
    final s = store.settings;
    final low = text.toLowerCase();
    if (wantsHuman(text)) {
      if (u.guest && s.supportHumanForMembersOnly) {
        return 'Canlı desteğe yalnız üyeler bağlanabilir. Kayıt olduktan sonra tekrar yazabilirsin.';
      }
      t.status = 'waiting';
      for (final a in store.admins.values) {
        store.securityEvent('info', 'Destek talebi bekliyor: ${u.username}', actor: a.username);
        break;
      }
      return 'Talebini bir yetkiliye ilettim. En kısa sürede burada yanıt verilecek.';
    }
    if (low.contains('abonelik') || low.contains('paketim') || low.contains('hakkım') || low.contains('haklarım')) {
      final active = [
        for (final e in u.entitlements.entries)
          if (DateTime.now().isBefore(e.value)) '${store.feature(e.key)?.name ?? e.key}: ${_date(e.value)}'
      ];
      return active.isEmpty ? 'Şu an aktif bir paket hakkın görünmüyor.' : 'Aktif hakların:\n${active.join('\n')}';
    }
    if (low.contains('sipariş')) {
      final o = store.orders.where((o) => o.userId == u.id).firstOrNull;
      if (o == null) return 'Henüz bir siparişin yok.';
      const st = {'pending': 'onay bekliyor', 'paid': 'ödendi', 'failed': 'başarısız', 'refunded': 'iade edildi', 'cancelled': 'iptal'};
      return 'Son siparişin ${o.id} (${o.packageName}): ${st[o.status] ?? o.status}.';
    }
    if ((low.contains('şifre') || low.contains('parola')) && u.email.isNotEmpty && s.mailEnabled) {
      final link = _link('/sifre-sifirla', _newToken(u, 'reset', const Duration(hours: 1)));
      _mail(u, 'reset', {'link': link});
      return 'Kayıtlı e-posta adresine şifre sıfırlama bağlantısı gönderdim.';
    }
    final kb = bestAnswer(store.kb, text);
    if (kb != null) return kb.answer;
    return 'Bunu tam anlayamadım. Başka şekilde sorabilir ya da "yetkili" yazarak bir yetkiliye bağlanabilirsin.';
  }

  /// İstek yolunu uç nokta haritasıyla eşleştirir: (anahtar, yol parametreleri).
  (String, Map<String, String>)? _match(String path, Map<String, String> eps) {
    final segs = path.split('/').where((e) => e.isNotEmpty).toList();
    for (final e in eps.entries) {
      if (e.key == 'ws') continue;
      final t = e.value.split('/').where((x) => x.isNotEmpty).toList();
      if (t.length != segs.length) continue;
      final params = <String, String>{};
      var ok = true;
      for (var i = 0; i < t.length; i++) {
        if (t[i].startsWith('{') && t[i].endsWith('}')) {
          params[t[i].substring(1, t[i].length - 1)] = Uri.decodeComponent(segs[i]);
        } else if (t[i] != segs[i]) {
          ok = false;
          break;
        }
      }
      if (ok) return (e.key, params);
    }
    return null;
  }

  Directory get uploadsDir {
    final f = store.file;
    final d = f == null
        ? Directory('${Directory.systemTemp.path}/spectre-uploads-$hashCode')
        : Directory('${f.parent.path}/uploads');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static const _imageTypes = {'png': 'image/png', 'jpg': 'image/jpeg', 'webp': 'image/webp', 'gif': 'image/gif'};

  /// Gövdedeki görseli doğrulayıp kaydeder; `/uploads/<ad>` döner.
  Future<String> _saveImage(HttpRequest req, {int maxBytes = 2 * 1024 * 1024}) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in req) {
      builder.add(chunk);
      if (builder.length > maxBytes) throw ApiError(413, 'Dosya çok büyük (en fazla ${maxBytes ~/ 1024 ~/ 1024} MB)');
    }
    final b = builder.takeBytes();
    String? ext;
    if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) ext = 'png';
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) ext = 'jpg';
    if (b.length > 12 && String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' && String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') {
      ext = 'webp';
    }
    if (b.length > 6 && String.fromCharCodes(b.sublist(0, 3)) == 'GIF') ext = 'gif';
    if (ext == null) throw ApiError(415, 'Yalnız PNG, JPG, WEBP veya GIF yüklenebilir');
    final name = '${randomToken(12).replaceAll(RegExp(r'[^A-Za-z0-9]'), 'x')}.$ext';
    await File('${uploadsDir.path}/$name').writeAsBytes(b, flush: true);
    return '/uploads/$name';
  }

  Future<void> _upload(HttpRequest req) async {
    final name = req.uri.pathSegments.length == 2 ? req.uri.pathSegments[1] : '';
    final m = RegExp(r'^[A-Za-z0-9]+\.(png|jpg|webp|gif)$').firstMatch(name);
    if (m == null || req.method != 'GET') throw ApiError(404, 'Bulunamadı');
    final f = File('${uploadsDir.path}/$name');
    if (!await f.exists()) throw ApiError(404, 'Bulunamadı');
    final res = req.response;
    res.headers
      ..set(HttpHeaders.contentTypeHeader, _imageTypes[m.group(1)]!)
      ..set('Cache-Control', 'public, max-age=604800')
      ..set('Cross-Origin-Resource-Policy', 'same-origin');
    await res.addStream(f.openRead());
    await res.close();
  }

  /// Bildirim oluşturur ve kullanıcıya okunmamış sayısıyla iletir.
  void _notify(String userId, String kind, String text) {
    final n = store.addNotice(userId, kind, text);
    _toUser(userId, Ev.notify, {'notice': n.toJson(), 'unread': store.unreadNotices(userId), 'unreadDm': store.unreadDms(userId)});
  }

  /// LibreTranslate uyumlu servis ile çeviri. Hata olursa null.
  Future<String?> _translate(String text, String target) async {
    final s = store.settings;
    if (!s.translateEnabled || s.translateUrl.isEmpty || text.trim().isEmpty) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.postUrl(Uri.parse(s.translateUrl));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'q': text,
        'source': 'auto',
        'target': target,
        'format': 'text',
        if (s.translateApiKey.isNotEmpty) 'api_key': s.translateApiKey,
      }));
      final res = await req.close().timeout(const Duration(seconds: 8));
      final body = await utf8.decoder.bind(res).join();
      if (res.statusCode != 200) return null;
      final j = jsonDecode(body);
      if (j is! Map) return null;
      final out = j['translatedText'];
      final detected = (j['detectedLanguage'] is Map) ? (j['detectedLanguage'] as Map)['language'] : null;
      if (out is! String || out.trim().isEmpty || detected == target || out.trim() == text.trim()) return null;
      return out;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, String>> _translateFor(String text, Iterable<String> langs) async {
    final out = <String, String>{};
    for (final l in langs.toSet()) {
      final t = await _translate(text, l);
      if (t != null) out[l] = t;
    }
    return out;
  }

  Map<String, dynamic> _dmJson(DmRec d) {
    final from = store.users[d.from];
    return {...d.toJson(), 'fromName': from?.displayName ?? '?', 'fromAvatar': from?.avatarUrl ?? '', 'fromColor': from?.color ?? 0};
  }

  Future<Object?> _public(HttpRequest req, String key, Map<String, String> params) async {
    final m = req.method;
    final s = store.settings;
    final ip = _ip(req);

    switch (key) {
      case '/api/v1/health':
        return {'ok': true};
      case '/api/v1/config':
        return s.publicJson();

      // --- Kimlik ---
      case 'authRegister' when m == 'POST':
        if (!s.registrationOpen) throw ApiError(403, 'Yeni kayıt şu an kapalı');
        final b = await _body(req);
        final username = '${b['username'] ?? ''}'.trim();
        final password = '${b['password'] ?? ''}';
        final display = '${b['displayName'] ?? username}'.trim();
        final email = '${b['email'] ?? ''}'.trim().toLowerCase();
        if (email.isNotEmpty && !_emailPattern.hasMatch(email)) throw ApiError(400, 'Geçerli bir e-posta adresi girin');
        if (email.isEmpty && s.requireEmail) throw ApiError(400, 'E-posta adresi gerekli');
        if (email.isNotEmpty && store.users.values.any((x) => x.email == email)) {
          throw ApiError(409, 'Bu e-posta adresiyle kayıtlı bir hesap var');
        }
        if (!usernamePattern.hasMatch(username)) {
          throw ApiError(400, 'Kullanıcı adı 3–20 karakter olmalı (harf, rakam, . _ -)');
        }
        final pe = validatePassword(password);
        if (pe != null) throw ApiError(400, pe);
        if (store.userByName(username) != null) throw ApiError(409, 'Bu kullanıcı adı alınmış');
        final u = _createUser(username, display.isEmpty ? username : _clip(display, 20), password, email: email);
        _sendVerify(u, welcome: true);
        return {'token': _issue(u.id, admin: false), 'me': meJson(u)};
      case 'authForgot' when m == 'POST':
        final b = await _body(req);
        final key = 'f:$ip';
        _throttleLogin(key);
        _loginFailures.putIfAbsent(key, () => []).add(DateTime.now()); // kötüye kullanım sınırı
        final q = '${b['email'] ?? b['username'] ?? ''}'.trim().toLowerCase();
        final u = store.users.values.where((x) => x.email.isNotEmpty && (x.email == q || x.username.toLowerCase() == q)).firstOrNull;
        if (u != null && s.mailEnabled) {
          _mail(u, 'reset', {'link': _link('/sifre-sifirla', _newToken(u, 'reset', const Duration(hours: 1)))});
        }
        // Hesabın var olup olmadığı açığa çıkarılmaz.
        return {'ok': true, 'message': 'Kayıtlı bir e-posta varsa sıfırlama bağlantısı gönderildi.'};
      case 'authReset' when m == 'POST':
        final b = await _body(req);
        final t = _takeToken('${b['token'] ?? ''}', 'reset');
        final u = t == null ? null : store.users[t.userId];
        if (u == null) throw ApiError(400, 'Bağlantı geçersiz ya da süresi dolmuş');
        final pe = validatePassword('${b['password'] ?? ''}');
        if (pe != null) throw ApiError(400, pe);
        u.passwordHash = hashPassword('${b['password']}');
        _sessions.removeWhere((_, x) => !x.admin && x.subject == u.id);
        store.markDirty();
        return {'ok': true};
      case 'authLogin' when m == 'POST':
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
      case 'authGuest' when m == 'POST':
        if (!s.guestLogin) throw ApiError(403, 'Misafir girişi kapalı');
        final n = 1000 + _rnd.nextInt(9000);
        final u = _createUser('misafir_${store.seq + 1}', 'Misafir $n', '', guest: true);
        return {'token': _issue(u.id, admin: false), 'me': meJson(u)};
      case 'authLogout' when m == 'POST':
        final t = _bearer(req);
        if (t != null) _sessions.remove(t);
        return {'ok': true};

      // --- Masa ve koltuk durumu ---
      case 'roomList' when m == 'GET':
        _requireUser(req);
        return {
          'items': [
            for (final t in tables.values)
              if (!t.closed) t.summary().toJson()
          ]
        };
      case 'roomDetail' when m == 'GET':
        _requireUser(req);
        final t = tables[params['roomId']] ?? (throw ApiError(404, 'Masa bulunamadı'));
        return t.summary().toJson();
      case 'roomPlayer' when m == 'GET':
        final me = _requireUser(req);
        final q = req.uri.queryParameters;
        final t = tables[q['roomId']] ?? tableOf(q['userId'] ?? me.id);
        if (t == null) return {'items': []};
        final limit = int.tryParse(q['limit'] ?? '') ?? kSeatCount;
        final items = t.roomPlayers().take(limit.clamp(1, kSeatCount)).map((e) => e.toJson()).toList();
        if (q['status'] != 'active') {
          for (final e in t.leftAt.entries) {
            if (DateTime.now().difference(e.value).inMinutes > 30) continue;
            final u = store.users[e.key];
            if (u == null) continue;
            items.add(RoomPlayer(index: -1, player: _seatPlayer(u), isPlaying: false, leaveAt: e.value).toJson());
          }
        }
        return {'roomId': t.id, 'items': items};
      case 'user' when m == 'GET':
        _requireUser(req);
        final u = store.users[params['userId']] ?? (throw ApiError(404, 'Oyuncu bulunamadı'));
        return publicUser(u);

      // --- Hesap ---
      case 'me':
        final u = _requireUser(req);
        if (m == 'GET') return meJson(u);
        if (m == 'PATCH') {
          final b = await _body(req);
          if (b['displayName'] != null) {
            final d = '${b['displayName']}'.trim();
            if (d.length < 2) throw ApiError(400, 'Ad en az 2 karakter olmalı');
            if (_blocked(d)) throw ApiError(400, 'Bu ad kullanılamaz');
            u.displayName = _clip(d, 20);
          }
          if (b['lang'] is String && s.languages.contains(b['lang'])) u.lang = b['lang'] as String;
          if (b['email'] is String) {
            final email = (b['email'] as String).trim().toLowerCase();
            if (email.isNotEmpty && !_emailPattern.hasMatch(email)) throw ApiError(400, 'Geçerli bir e-posta adresi girin');
            if (email.isNotEmpty && store.users.values.any((x) => x.id != u.id && x.email == email)) {
              throw ApiError(409, 'Bu e-posta adresi kullanımda');
            }
            if (email != u.email) {
              u.email = email;
              u.emailVerified = false;
              _sendVerify(u);
            }
          }
          if (b['resendVerify'] == true) _sendVerify(u);
          store.markDirty();
          tableOf(u.id)?.updatePlayer(_seatPlayer(u));
          return meJson(u);
        }
      case 'meAvatar' when m == 'POST':
        final u = _requireUser(req);
        if (u.guest) throw ApiError(403, 'Fotoğraf için üye girişi gerekli');
        if (!allowed(u, 'avatar')) throw ApiError(403, _lockedMsg('avatar'));
        u.avatarUrl = await _saveImage(req, maxBytes: 1536 * 1024);
        store.markDirty();
        tableOf(u.id)?.updatePlayer(_seatPlayer(u));
        return meJson(u);
      case 'meDaily' when m == 'POST':
        final u = _requireUser(req);
        if (!_canClaimDaily(u)) throw ApiError(409, 'Günlük ödül zaten alındı');
        u.lastDaily = DateTime.now();
        u.coins += s.dailyRewardCoins;
        store.addLedger(LedgerRec(u.id, 'reward', s.dailyRewardCoins, 'Günlük ödül'));
        return {'amount': s.dailyRewardCoins, 'me': meJson(u)};

      // --- Bildirimler ---
      case 'notifications' when m == 'GET':
        final u = _requireUser(req);
        final list = store.notices.reversed.where((n) => n.userId == u.id).take(100).map((n) => n.toJson()).toList();
        return {'unread': store.unreadNotices(u.id), 'items': list};
      case 'notificationsRead' when m == 'POST':
        final u = _requireUser(req);
        for (final n in store.notices.where((n) => n.userId == u.id && !n.read)) {
          n.read = true;
        }
        store.markDirty();
        return {'unread': 0};

      // --- Özel mesajlar ---
      case 'dmThreads' when m == 'GET':
        final u = _requireUser(req);
        final last = <String, DmRec>{};
        final unread = <String, int>{};
        for (final d in store.dms) {
          if (d.from != u.id && d.to != u.id) continue;
          final peer = d.from == u.id ? d.to : d.from;
          last[peer] = d;
          if (d.to == u.id && !d.read) unread[peer] = (unread[peer] ?? 0) + 1;
        }
        final items = last.entries.toList()..sort((a, b) => b.value.at.compareTo(a.value.at));
        return {
          'unread': store.unreadDms(u.id),
          'items': [
            for (final e in items)
              if (store.users[e.key] != null)
                {'peer': publicUser(store.users[e.key]!), 'last': _dmJson(e.value), 'unread': unread[e.key] ?? 0}
          ],
        };
      case 'dmThread':
        final u = _requireUser(req);
        final peer = store.users[params['userId']] ?? (throw ApiError(404, 'Oyuncu bulunamadı'));
        if (peer.id == u.id) throw ApiError(400, 'Kendine mesaj gönderemezsin');
        if (m == 'GET') {
          var changed = false;
          final list = <Map<String, dynamic>>[];
          for (final d in store.dms) {
            if (!((d.from == u.id && d.to == peer.id) || (d.from == peer.id && d.to == u.id))) continue;
            if (d.to == u.id && !d.read) {
              d.read = true;
              changed = true;
            }
            list.add(_dmJson(d));
          }
          if (changed) store.markDirty();
          return {'peer': publicUser(peer), 'items': list.length > 200 ? list.sublist(list.length - 200) : list};
        }
        if (m == 'POST') {
          if (u.status == 'muted') throw ApiError(403, 'Susturuldunuz');
          if (!allowed(u, 'dm')) throw ApiError(403, _lockedMsg('dm'));
          final b = await _body(req);
          final text = _clip('${b['text'] ?? ''}'.trim(), 500);
          if (text.isEmpty) throw ApiError(400, 'Mesaj boş');
          if (_blocked(text)) throw ApiError(400, 'Mesaj topluluk kurallarına uymuyor');
          final d = DmRec(id: store.nextId('d'), from: u.id, to: peer.id, text: text);
          store.dms.add(d);
          if (store.dms.length > 100000) store.dms.removeAt(0);
          store.markDirty();
          final j = _dmJson(d);
          _toUser(peer.id, Ev.dm, {...j, 'unreadDm': store.unreadDms(peer.id)});
          _toUser(u.id, Ev.dm, j);
          // Alıcının diline otomatik çeviri (arka planda)
          if (peer.lang != u.lang && allowed(peer, 'translate')) {
            _translateFor(text, [peer.lang]).then((t) {
              if (t.isEmpty) return;
              d.translations.addAll(t);
              store.markDirty();
              final upd = _dmJson(d);
              _toUser(peer.id, Ev.dm, {...upd, 'unreadDm': store.unreadDms(peer.id)});
              _toUser(u.id, Ev.dm, upd);
            });
          }
          return j;
        }

      // --- Sanal POS ---
      case 'payStart' when m == 'POST':
        final u = _requireUser(req);
        if (!s.marketOpen) throw ApiError(403, 'Market kapalı');
        if (u.guest) throw ApiError(403, 'Satın alma için üye girişi gerekli');
        if (!s.paytrEnabled || !_paytr.configured) throw ApiError(503, 'Kartla ödeme şu an kullanılamıyor');
        if (s.publicBaseUrl.isEmpty) throw ApiError(503, 'Site adresi ayarlanmamış');
        final b = await _body(req);
        final pkg = store.packages.where((x) => x.id == b['packageId'] && x.active).firstOrNull ??
            (throw ApiError(404, 'Paket bulunamadı'));
        final o = OrderRec(
          id: store.nextId('S'),
          userId: u.id,
          packageId: pkg.id,
          packageName: pkg.name,
          amountKurus: pkg.priceKurus,
          coins: pkg.totalCoins,
          provider: 'paytr',
          createdAt: DateTime.now(),
        );
        store.orders.insert(0, o);
        store.markDirty();
        final base = s.publicBaseUrl.replaceAll(RegExp(r'/+$'), '');
        try {
          final url = await _paytr.createPayment(
            userIp: ip,
            merchantOid: o.id,
            email: u.email.isNotEmpty ? u.email : '${u.username}@${Uri.parse(base).host}',
            userName: u.displayName,
            productName: pkg.name,
            amountKurus: pkg.priceKurus,
            okUrl: '$base/?odeme=basarili',
            failUrl: '$base/?odeme=hata',
          );
          return {'order': o.toJson(), 'paymentUrl': url};
        } catch (e) {
          o.status = 'failed';
          o.note = '$e';
          throw ApiError(502, 'Ödeme başlatılamadı: $e');
        }

      // --- Destek ---
      case 'support':
        final u = _requireUser(req);
        if (!s.supportEnabled) throw ApiError(403, 'Destek şu an kapalı');
        final t = _ticketOf(u);
        if (m == 'POST') {
          if (t.locked) throw ApiError(423, 'Görüşme geçici olarak kilitlendi');
          final b = await _body(req);
          final text = _clip('${b['text'] ?? ''}'.trim(), 1000);
          if (text.isEmpty) throw ApiError(400, 'Mesaj boş');
          t.messages.add(TicketMsg('user', text));
          final hit = safetyHit(s.supportSafetyWords, text) ?? (_blocked(text) ? 'küfür' : null);
          if (hit != null) {
            t.status = 'locked';
            t.lockedUntil = DateTime.now().add(Duration(minutes: s.supportLockMinutes));
            t.messages.add(TicketMsg('bot', 'Bu görüşme kurallara aykırı içerik nedeniyle kilitlendi.'));
            store.securityEvent('warn', 'Destekte kural dışı ifade (${u.username}): "$hit"');
          } else if (t.status == 'waiting' || t.status == 'answered') {
            t.status = 'waiting';
          } else {
            t.messages.add(TicketMsg('bot', _botReply(u, t, text)));
          }
          t.updatedAt = DateTime.now();
          store.markDirty();
        }
        return {
          'botName': s.supportBotName,
          'ticket': t.toJson(),
        };

      // --- Market ---
      case 'gifts' when m == 'GET':
        _requireUser(req);
        return {'items': store.gifts.where((g) => g['enabled'] != false).toList()};
      case 'packages' when m == 'GET':
        _requireUser(req);
        if (!s.marketOpen) return {'items': [], 'open': false};
        return {'items': [for (final p in store.packages) if (p.active) p.toJson()], 'open': true};
      case 'orders':
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
          return {'order': o.toJson(), 'next': provider == 'manual' ? 'manual' : 'pending_provider', 'manualInfo': s.manualPaymentInfo};
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
    final fromInventory = (u.inventory[gift.id] ?? 0) > 0;
    if (!fromInventory && u.coins < gift.price) return _err(c, 'Yetersiz coin');
    c.giftTimes.removeWhere((x) => now.difference(x).inSeconds >= 60);
    if (c.giftTimes.length >= store.settings.maxGiftsPerMinute) return _err(c, 'Çok hızlı hediye gönderiyorsunuz');
    c.giftTimes.add(now);
    if (!t.deliverGift(u.id, toSeat, gift)) return _err(c, 'Hediye gönderilemedi');
    final rec = store.users[to.userId];
    if (fromInventory) {
      u.inventory[gift.id] = u.inventory[gift.id]! - 1;
    } else {
      u.coins -= gift.price;
      store.addLedger(LedgerRec(u.id, 'gift', -gift.price, '${gift.name} → ${to.name}'));
    }
    u.giftsSent++;
    if (rec != null) {
      final share = (gift.price * 0.1).round();
      rec.giftsReceived++;
      if (share > 0) {
        rec.coins += share;
        store.addLedger(LedgerRec(rec.id, 'giftIncome', share, '${gift.name} ← ${u.displayName}'));
      }
      _toUser(rec.id, Ev.me, meJson(rec));
      _notify(rec.id, 'gift', '${u.displayName} sana ${gift.emoji} ${gift.name} gönderdi');
    }
    _toUser(u.id, Ev.me, meJson(u));
  }

  /// Toplu hediye: masadaki herkese (kendisi hariç) aynı hediye.
  void _giftAll(_Client c, UserRec u, Map<String, dynamic> msg, DateTime now) {
    if (!rules.giftsEnabled) return _err(c, 'Hediyeler şu an kapalı');
    if (!allowed(u, 'groupGift')) return _err(c, _lockedMsg('groupGift'));
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
        _notify(rec.id, 'gift', '${u.displayName} masaya ${gift.emoji} ${gift.name} dağıttı');
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
          final granted = pkg == null ? <String>[] : grantPackage(u, pkg);
          if (o.coins > 0) store.addLedger(LedgerRec(u.id, 'purchase', o.coins, '${o.packageName} (${o.id})'));
          _toUser(u.id, Ev.me, meJson(u));
          _notify(u.id, 'order',
              'Siparişin onaylandı: ${o.packageName}${o.coins > 0 ? ' (+${o.coins} 🪙)' : ''}${granted.isEmpty ? '' : ' — ${granted.join(', ')}'}');
          final exp = pkg == null || pkg.features.isEmpty ? null : u.entitlements[pkg.features.first];
          _mail(u, 'purchase', {
            'order': o.id,
            'package': o.packageName,
            'amount': '${(o.amountKurus / 100).toStringAsFixed(2)} TL',
            'coins': '${o.coins}',
            'features': granted.isEmpty ? '-' : granted.join(', '),
            'expires': exp == null ? '-' : _date(exp),
          });
        }
      case 'refund':
        if (o.status != 'paid') throw ApiError(409, 'Yalnız ödenmiş sipariş iade edilir');
        o.status = 'refunded';
        if (u != null) {
          final take = math.min(u.coins, o.coins);
          u.coins -= take;
          u.totalSpent -= o.amountKurus;
          final pkg = store.packages.where((p) => p.id == o.packageId).firstOrNull;
          if (pkg != null) grantPackage(u, pkg, sign: -1);
          store.addLedger(LedgerRec(u.id, 'refund', -take, 'İade ${o.id}'));
          _toUser(u.id, Ev.me, meJson(u));
          _notify(u.id, 'order', 'Siparişin iade edildi: ${o.packageName}');
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
    if (m == 'POST' && path == '/upload') {
      final url = await _saveImage(req, maxBytes: 4 * 1024 * 1024);
      store.log(actor, 'Görsel yüklendi', url);
      return {'url': url};
    }
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
          _notify(u.id, 'admin', 'Yönetici uyarısı: $w');
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
        case 'grant':
          final key = '${b['feature']}';
          if (store.feature(key) == null) throw ApiError(400, 'Özellik yok');
          final days = (b['days'] as num?)?.toInt() ?? 30;
          final now = DateTime.now();
          final cur = u.entitlements[key];
          final base = cur != null && cur.isAfter(now) ? cur : now;
          u.entitlements[key] = days <= 0 ? _forever : base.add(Duration(days: days.clamp(1, 3650)));
          u.expiryWarned.removeWhere((w) => w.startsWith('$key@'));
          tableOf(u.id)?.updatePlayer(_seatPlayer(u));
          _toUser(u.id, Ev.me, meJson(u));
          _notify(u.id, 'order', '${store.feature(key)!.name} hakkı tanımlandı (${days <= 0 ? 'süresiz' : '$days gün'})');
          store.log(actor, 'Hak tanımlandı: $key ${days <= 0 ? 'süresiz' : '$days gün'}', u.username);
        case 'revoke':
          final key = '${b['feature']}';
          u.entitlements.remove(key);
          tableOf(u.id)?.updatePlayer(_seatPlayer(u));
          _toUser(u.id, Ev.me, meJson(u));
          store.log(actor, 'Hak kaldırıldı: $key', u.username);
        case 'inventory':
          final gid = '${b['giftId']}';
          if (!store.gifts.any((g) => g['id'] == gid)) throw ApiError(400, 'Hediye yok');
          final qty = (b['qty'] as num?)?.toInt() ?? 0;
          u.inventory[gid] = math.max(0, (u.inventory[gid] ?? 0) + qty);
          _toUser(u.id, Ev.me, meJson(u));
          store.log(actor, 'Hediye envanteri $gid ${qty >= 0 ? '+' : ''}$qty', u.username);
        case 'rename':
          final d = _clip('${b['displayName'] ?? ''}'.trim(), 20);
          if (d.length < 2) throw ApiError(400, 'Ad çok kısa');
          u.displayName = d;
          tableOf(u.id)?.updatePlayer(_seatPlayer(u));
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
    // --- Özellikler (kilitlenebilir haklar) ---
    if (path == '/features') {
      if (m == 'GET') return {'items': [for (final f in store.features) f.toJson()]};
      if (m == 'POST') {
        final b = await _body(req);
        final key = '${b['key'] ?? ''}'.trim();
        if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]{1,31}$').hasMatch(key)) throw ApiError(400, 'Geçersiz anahtar (harf/rakam/_)');
        var f = store.feature(key);
        if (f == null) {
          f = FeatureRec(key: key, name: key);
          store.features.add(f);
        }
        f
          ..name = _clip('${b['name'] ?? f.name}'.trim(), 40)
          ..description = _clip('${b['description'] ?? f.description}', 200)
          ..locked = b['locked'] as bool? ?? f.locked;
        if (b['delete'] == true && !f.builtin) store.features.remove(f);
        store.log(actor, 'Özellik kaydedildi', key);
        for (final c in _clients) {
          final u = store.users[c.userId];
          if (u != null) c.send({'event': Ev.me, 'data': meJson(u)});
        }
        return f.toJson();
      }
    }

    // --- Mail ---
    if (path == '/mail/templates') {
      if (m == 'GET') {
        return {
          'items': {
            for (final k in kDefaultMailTemplates.keys) k: {...templateOf(k), 'name': kDefaultMailTemplates[k]!['name']}
          },
          'variables': ['brand', 'site', 'name', 'username', 'link', 'order', 'package', 'amount', 'coins', 'features', 'expires', 'feature', 'days', 'message'],
        };
      }
    }
    if (m == 'POST' && path == '/mail/test') {
      final b = await _body(req);
      final to = '${b['to'] ?? ''}'.trim();
      if (!_emailPattern.hasMatch(to)) throw ApiError(400, 'Geçerli bir adres girin');
      final key = kDefaultMailTemplates.containsKey(b['template']) ? b['template'] as String : 'welcome';
      final ok = await sendTemplate(to, key, {
        'name': 'Test Oyuncu',
        'username': 'test',
        'link': _link('/eposta-dogrula', 'ornek'),
        'order': 'S0000',
        'package': 'Örnek paket',
        'amount': '49.99 TL',
        'coins': '500',
        'features': 'Özel mesaj',
        'expires': _date(DateTime.now().add(const Duration(days: 30))),
        'feature': 'Özel mesaj',
        'days': '3',
        'message': 'Örnek yanıt',
      });
      if (!ok) throw ApiError(502, 'Gönderilemedi: ${store.mailLog.last['error']}');
      return {'ok': true};
    }
    if (m == 'GET' && path == '/mail/log') return {'items': store.mailLog.reversed.take(100).toList()};

    // --- Destek ---
    if (path == '/support/kb') {
      if (m == 'GET') return {'items': [for (final e in store.kb) e.toJson()]};
      if (m == 'PUT') {
        final b = await _body(req);
        final list = (b['items'] as List? ?? const []).whereType<Map>().take(300).toList();
        store.kb
          ..clear()
          ..addAll([
            for (final e in list)
              KbEntry(
                id: '${e['id'] ?? store.nextId('kb')}',
                question: _clip('${e['question'] ?? ''}', 200),
                keywords: [for (final k in (e['keywords'] as List? ?? const [])) _clip('$k'.trim().toLowerCase(), 40)]
                    .where((k) => k.isNotEmpty)
                    .toList(),
                answer: _clip('${e['answer'] ?? ''}', 2000),
              )
          ]);
        store.log(actor, 'Destek bilgi tabanı güncellendi', '${store.kb.length} kayıt');
        return {'items': [for (final e in store.kb) e.toJson()]};
      }
    }
    if (m == 'GET' && path == '/support/tickets') {
      final status = req.uri.queryParameters['status'] ?? '';
      final list = store.tickets.where((t) => status.isEmpty || t.status == status).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return {
        'counts': {
          for (final st in const ['bot', 'waiting', 'answered', 'locked', 'closed'])
            st: store.tickets.where((t) => t.status == st).length
        },
        'items': [
          for (final t in list.take(200))
            {
              ...t.toJson(),
              'username': store.users[t.userId]?.username,
              'displayName': store.users[t.userId]?.displayName,
              'avatarUrl': store.users[t.userId]?.avatarUrl,
            }
        ],
      };
    }
    if (seg.length == 4 && seg[0] == 'support' && seg[1] == 'tickets' && seg[3] == 'action' && m == 'POST') {
      final t = store.tickets.where((x) => x.id == seg[2]).firstOrNull ?? (throw ApiError(404, 'Talep yok'));
      final u = store.users[t.userId];
      final b = await _body(req);
      switch ('${b['action']}') {
        case 'reply':
          final text = _clip('${b['text'] ?? ''}'.trim(), 2000);
          if (text.isEmpty) throw ApiError(400, 'Yanıt boş');
          t.messages.add(TicketMsg('admin:$actor', text));
          t.status = 'answered';
          if (u != null) {
            _notify(u.id, 'admin', 'Destek yanıtı: ${text.length > 80 ? '${text.substring(0, 80)}…' : text}');
            _mail(u, 'supportReply', {'message': text});
          }
        case 'close':
          t.status = 'closed';
        case 'unlock':
          t.lockedUntil = null;
          t.status = 'waiting';
        default:
          throw ApiError(400, 'Bilinmeyen işlem');
      }
      t.updatedAt = DateTime.now();
      store.log(actor, 'Destek: ${b['action']}', u?.username ?? t.id);
      return {
        ...t.toJson(),
        'username': u?.username,
        'displayName': u?.displayName,
      };
    }

    if (path == '/packages') {
      if (m == 'GET') return {'items': [for (final p in store.packages) p.toJson()]};
      if (m == 'POST') {
        final b = await _body(req);
        final name = _clip('${b['name'] ?? ''}'.trim(), 40);
        final coins = (b['coins'] as num?)?.toInt() ?? 0;
        final price = (b['priceKurus'] as num?)?.toInt() ?? -1;
        final kind = const {'coins', 'subscription', 'feature'}.contains(b['kind']) ? b['kind'] as String : 'coins';
        final feats = [
          for (final f in (b['features'] as List? ?? const []))
            if (store.feature('$f') != null) '$f'
        ];
        final gifts = [
          for (final g in (b['gifts'] as List? ?? const []))
            if (g is Map && store.gifts.any((x) => x['id'] == g['giftId']) && (g['qty'] as num? ?? 0) > 0)
              {'giftId': '${g['giftId']}', 'qty': (g['qty'] as num).toInt().clamp(1, 100000)}
        ];
        if (name.isEmpty || price <= 0) throw ApiError(400, 'Ad ve fiyat gerekli');
        if (coins < 0 || (coins == 0 && feats.isEmpty && gifts.isEmpty && ((b['vipDays'] as num?) ?? 0) == 0)) {
          throw ApiError(400, 'Paket en az coin, özellik ya da hediye içermeli');
        }
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
          ..featured = b['featured'] as bool? ?? p.featured
          ..kind = kind
          ..periodDays = ((b['periodDays'] as num?)?.toInt() ?? 0).clamp(0, 3650)
          ..description = _clip('${b['description'] ?? ''}', 400)
          ..features = feats
          ..gifts = gifts;
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
        _applyAnimRules();
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
