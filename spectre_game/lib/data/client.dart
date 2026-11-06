import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectre_core/spectre_core.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';
import 'room_state.dart';

class Me {
  Me(this.j);
  final Map<String, dynamic> j;
  String get id => '${j['id']}';
  String get username => '${j['username'] ?? ''}';
  String get displayName => '${j['displayName'] ?? username}';
  int get coins => (j['coins'] as num?)?.toInt() ?? 0;
  int get level => (j['level'] as num?)?.toInt() ?? 1;
  int get hearts => (j['hearts'] as num?)?.toInt() ?? 0;
  int get color => (j['color'] as num?)?.toInt() ?? 0xFF65C5FF;
  bool get guest => j['guest'] == true;
  bool get vip => j['role'] == 'vip';
  bool get canClaimDaily => j['canClaimDaily'] == true;
  String get status => '${j['status'] ?? 'active'}';
  String get avatarUrl => '${j['avatarUrl'] ?? ''}';
  String get lang => '${j['lang'] ?? 'tr'}';
  int get unreadNotices => (j['unreadNotices'] as num?)?.toInt() ?? 0;
  int get unreadDms => (j['unreadDms'] as num?)?.toInt() ?? 0;

  String get email => '${j['email'] ?? ''}';
  bool get emailVerified => j['emailVerified'] == true;

  /// Özellik anahtarı → bitiş.
  Map<String, DateTime> get entitlements => {
        for (final e in ((j['entitlements'] as Map?) ?? const {}).entries)
          if (DateTime.tryParse('${e.value}') != null) '${e.key}': DateTime.parse('${e.value}').toLocal(),
      };

  /// Bu kullanıcı için kilitli özellikler.
  Set<String> get locked => {for (final x in (j['locked'] as List? ?? const [])) '$x'};
  bool isLocked(String feature) => locked.contains(feature);

  /// Özellik anahtarı → görünen ad.
  Map<String, String> get featureNames => {for (final e in ((j['features'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'};

  /// Hediye kimliği → adet.
  Map<String, int> get inventory =>
      {for (final e in ((j['inventory'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()};

  Me copyWith(Map<String, dynamic> patch) => Me({...j, ...patch});

  SeatPlayer asSeatPlayer() => SeatPlayer(
      userId: id, name: displayName, color: color, level: level, vip: vip, hearts: hearts, avatarUrl: mediaUrl(avatarUrl));
}

class PublicConfig {
  PublicConfig(this.j);
  final Map<String, dynamic> j;
  String get brandName => '${j['brandName'] ?? 'SPECTRE'}';
  String get tagline => '${j['tagline'] ?? ''}';
  bool get maintenance => j['maintenance'] == true;
  String get maintenanceText => '${j['maintenanceText'] ?? ''}';
  bool get registrationOpen => j['registrationOpen'] != false;
  bool get guestLogin => j['guestLogin'] == true;
  bool get marketOpen => j['marketOpen'] == true;
  Map<String, dynamic> get payment => (j['payment'] as Map?)?.cast<String, dynamic>() ?? const {};
  String get backgroundColor => '${j['backgroundColor'] ?? ''}';
  String get backgroundImageUrl => mediaUrl('${j['backgroundImageUrl'] ?? ''}');
  String get logoUrl => mediaUrl('${j['logoUrl'] ?? ''}');
  bool get translate => j['translate'] == true;
  bool get paytrReady => j['paytrReady'] == true;
  bool get mailReady => j['mailReady'] == true;
  bool get requireEmail => j['requireEmail'] == true;
  bool get support => j['support'] == true;
  String get supportBotName => '${j['supportBotName'] ?? 'Asistan'}';
  Map<String, dynamic> get animations => (j['animations'] as Map?)?.cast<String, dynamic>() ?? const {};
  List<String> get languages => [for (final l in (j['languages'] as List? ?? const ['tr'])) '$l'];

  /// Yönetim panelinden düzenlenen arayüz metni.
  String t(String key, String fallback) {
    final m = j['texts'];
    final v = m is Map ? m[key] : null;
    return v is String && v.isNotEmpty ? v : fallback;
  }

  /// Açılır pencere açıklama metni (boş olabilir).
  String popup(String key) {
    final m = j['popups'];
    final v = m is Map ? m[key] : null;
    return v is String ? v : '';
  }
}

/// Özel mesaj.
class DmMessage {
  DmMessage(this.j);
  final Map<String, dynamic> j;
  String get id => '${j['id']}';
  String get from => '${j['from']}';
  String get to => '${j['to']}';
  String get text => '${j['text'] ?? ''}';
  String get fromName => '${j['fromName'] ?? ''}';
  String get fromAvatar => mediaUrl('${j['fromAvatar'] ?? ''}');
  int get fromColor => (j['fromColor'] as num?)?.toInt() ?? 0xFF65C5FF;
  DateTime get at => DateTime.tryParse('${j['at']}')?.toLocal() ?? DateTime.now();
  String? translation(String lang) {
    final t = j['translations'];
    return t is Map && t[lang] is String ? t[lang] as String : null;
  }
}

enum LinkState { offline, connecting, online }

/// Oyuncu oturumu: REST + WebSocket bağlantısı + açık masa durumu.
class SpectreClient extends ChangeNotifier {
  SpectreClient({Api? api}) : api = api ?? Api();

  final Api api;
  PublicConfig config = PublicConfig(const {});
  Me? me;
  List<RoomSummary> rooms = [];
  List<GiftInfo> gifts = [];
  RoomState? room;
  LinkState link = LinkState.offline;
  String? lastError;
  bool lightMode = false;
  bool booting = true;

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _reconnect;
  Timer? _poll;
  int _backoff = 1;
  bool _disposed = false;
  final _errors = StreamController<String>.broadcast();

  /// Kullanıcıya gösterilecek hata/uyarı mesajları.
  Stream<String> get errors => _errors.stream;

  static const _tokenKey = 'spectre.token';
  static const _lightKey = 'spectre.light';

  // ---------------------------------------------------------------------------
  // Açılış ve oturum
  // ---------------------------------------------------------------------------

  Future<void> boot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      lightMode = prefs.getBool(_lightKey) ?? false;
      showTranslations = prefs.getBool('spectre.showTr') ?? true;
      await refreshConfig();
      final token = prefs.getString(_tokenKey);
      if (token != null) {
        api.token = token;
        try {
          me = Me(await api.get(ApiConfig.ep('me')));
          await _afterLogin();
        } on ApiException catch (e) {
          if (e.status == 401 || e.status == 403) {
            api.token = null;
            await prefs.remove(_tokenKey);
          } else {
            lastError = e.message;
          }
        }
      }
    } on ApiException catch (e) {
      lastError = e.message;
    } finally {
      booting = false;
      notifyListeners();
    }
  }

  Future<void> refreshConfig() async {
    final j = await api.get('/api/v1/config');
    ApiConfig.apply(j);
    config = PublicConfig(j);
    notifyListeners();
  }

  /// Arayüz metni kısayolu.
  String t(String key, String fallback) => config.t(key, fallback);

  Future<void> login(String username, String password) =>
      _auth(api.post(ApiConfig.ep('authLogin'), {'username': username, 'password': password}));

  Future<void> register(String username, String password, String displayName, {String email = ''}) => _auth(api.post(
      ApiConfig.ep('authRegister'),
      {'username': username, 'password': password, 'displayName': displayName, if (email.isNotEmpty) 'email': email}));

  Future<String> forgotPassword(String emailOrUsername) async {
    final r = await api.post(ApiConfig.ep('authForgot'), {'email': emailOrUsername});
    return '${r['message'] ?? 'Gönderildi'}';
  }

  Future<void> setEmail(String email) async {
    me = Me(await api.patch(ApiConfig.ep('me'), {'email': email}));
    notifyListeners();
  }

  Future<void> resendVerify() => api.patch(ApiConfig.ep('me'), {'resendVerify': true});

  /// Kartla ödeme: sipariş oluşturur, ödeme sayfası adresini döner.
  Future<String> startCardPayment(String packageId) async {
    final r = await api.post(ApiConfig.ep('payStart'), {'packageId': packageId});
    return '${r['paymentUrl']}';
  }

  /// Sohbette çevirileri göster (sohbet başlığındaki düğme).
  bool showTranslations = true;

  Future<void> setShowTranslations(bool v) async {
    showTranslations = v;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setBool('spectre.showTr', v);
    } catch (_) {}
  }

  /// Tek bir metni oyuncunun diline çevirir.
  Future<String?> translateText(String text) async {
    final r = await api.post(ApiConfig.ep('translate'), {'text': text});
    return r['translated'] == true ? '${r['text']}' : null;
  }

  Future<Map<String, dynamic>> support([String? text]) =>
      text == null ? api.get(ApiConfig.ep('support')) : api.post(ApiConfig.ep('support'), {'text': text});

  Future<void> guest() => _auth(api.post(ApiConfig.ep('authGuest')));

  Future<void> _auth(Future<Map<String, dynamic>> f) async {
    final r = await f;
    api.token = r['token'] as String;
    me = Me((r['me'] as Map).cast<String, dynamic>());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, api.token!);
    } catch (_) {}
    await _afterLogin();
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.post(ApiConfig.ep('authLogout'));
    } catch (_) {}
    api.token = null;
    me = null;
    room = null;
    rooms = [];
    _closeWs();
    _poll?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _afterLogin() async {
    await Future.wait([refreshRooms(), _loadGifts()]);
    _connectWs();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (room == null) refreshRooms();
    });
  }

  Future<void> refreshRooms() async {
    try {
      final r = await api.get(ApiConfig.ep('roomList'));
      rooms = [for (final x in (r['items'] as List? ?? const [])) RoomSummary.fromJson((x as Map).cast<String, dynamic>())];
      notifyListeners();
    } on ApiException catch (e) {
      if (e.status == 401) await logout();
    }
  }

  Future<void> _loadGifts() async {
    try {
      final r = await api.get(ApiConfig.ep('gifts'));
      gifts = [for (final x in (r['items'] as List? ?? const [])) GiftInfo.fromJson((x as Map).cast<String, dynamic>())];
    } catch (_) {}
  }

  Future<int> claimDaily() async {
    final r = await api.post(ApiConfig.ep('meDaily'));
    me = Me((r['me'] as Map).cast<String, dynamic>());
    notifyListeners();
    return (r['amount'] as num).toInt();
  }

  Future<void> rename(String name) async {
    me = Me(await api.patch(ApiConfig.ep('me'), {'displayName': name}));
    notifyListeners();
  }

  Future<void> setLang(String lang) async {
    me = Me(await api.patch(ApiConfig.ep('me'), {'lang': lang}));
    notifyListeners();
  }

  Future<void> uploadAvatar(Uint8List bytes) async {
    me = Me(await api.upload(ApiConfig.ep('meAvatar'), bytes));
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Bildirimler ve özel mesajlar
  // ---------------------------------------------------------------------------

  final _dmCtl = StreamController<DmMessage>.broadcast();

  /// Gelen/giden özel mesajlar (açık sohbet penceresi dinler).
  Stream<DmMessage> get dmStream => _dmCtl.stream;

  Future<List<Map<String, dynamic>>> notifications() async {
    final r = await api.get(ApiConfig.ep('notifications'));
    return [for (final x in (r['items'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
  }

  Future<void> markNotificationsRead() async {
    await api.post(ApiConfig.ep('notificationsRead'));
    if (me != null) me = me!.copyWith({'unreadNotices': 0});
    notifyListeners();
  }

  Future<Map<String, dynamic>> dmThreads() => api.get(ApiConfig.ep('dmThreads'));

  Future<(Map<String, dynamic> peer, List<DmMessage> items)> dmThread(String userId) async {
    final r = await api.get(ApiConfig.ep('dmThread', {'userId': userId}));
    // Okunan mesajlar sunucuda işaretlendi; sayacı tazele.
    try {
      me = Me(await api.get(ApiConfig.ep('me')));
      notifyListeners();
    } catch (_) {}
    return (
      (r['peer'] as Map).cast<String, dynamic>(),
      [for (final x in (r['items'] as List? ?? const [])) DmMessage((x as Map).cast<String, dynamic>())]
    );
  }

  Future<void> sendDm(String userId, String text) => api.post(ApiConfig.ep('dmThread', {'userId': userId}), {'text': text});

  Future<void> setLightMode(bool v) async {
    lightMode = v;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setBool(_lightKey, v);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // WebSocket
  // ---------------------------------------------------------------------------

  void _connectWs() {
    final token = api.token;
    if (token == null || _disposed) return;
    _closeWs();
    link = LinkState.connecting;
    notifyListeners();
    try {
      final ch = WebSocketChannel.connect(wsUri(token));
      _ws = ch;
      _wsSub = ch.stream.listen(
        (data) {
          if (data is String) _onMessage(data);
        },
        onDone: _onWsDown,
        onError: (_) => _onWsDown(),
        cancelOnError: true,
      );
    } catch (_) {
      _onWsDown();
    }
  }

  void _closeWs() {
    _reconnect?.cancel();
    _wsSub?.cancel();
    _ws?.sink.close();
    _ws = null;
    _wsSub = null;
    link = LinkState.offline;
  }

  void _onWsDown() {
    if (_disposed) return;
    _ws = null;
    link = LinkState.offline;
    notifyListeners();
    if (api.token == null) return;
    _reconnect?.cancel();
    _reconnect = Timer(Duration(seconds: _backoff), _connectWs);
    _backoff = (_backoff * 2).clamp(1, 20);
  }

  void _send(Map<String, dynamic> m) {
    final ws = _ws;
    if (ws == null) {
      _errors.add('Bağlantı yok, yeniden bağlanılıyor…');
      return;
    }
    ws.sink.add(jsonEncode(m));
  }

  void _onMessage(String raw) {
    final Map<String, dynamic> msg;
    try {
      msg = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final event = '${msg['event']}';
    final data = (msg['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final channel = msg['channel'] as String?;
    switch (event) {
      case Ev.hello:
        link = LinkState.online;
        _backoff = 1;
        me = Me((data['me'] as Map).cast<String, dynamic>());
        // Yeniden bağlanınca açık masaya geri abone ol.
        final r = room;
        if (r != null) _send({'op': Op.join, 'roomId': r.roomId});
        notifyListeners();
      case Ev.me:
        me = Me(data);
        notifyListeners();
      case Ev.error:
        _errors.add('${data['message']}');
      case Ev.notify:
        if (me != null) {
          me = me!.copyWith({'unreadNotices': data['unread'], 'unreadDms': data['unreadDm']});
        }
        final n = data['notice'];
        if (n is Map) _noticeCtl.add('${n['text']}');
        notifyListeners();
      case Ev.dm:
        final m = DmMessage(data);
        if (me != null && data['unreadDm'] != null) me = me!.copyWith({'unreadDms': data['unreadDm']});
        _dmCtl.add(m);
        notifyListeners();
      default:
        final r = room;
        if (r != null && channel == roomChannel(r.roomId)) r.handle(event, data);
    }
  }

  // ---------------------------------------------------------------------------
  // Masa işlemleri
  // ---------------------------------------------------------------------------

  /// Masayı açar (izleyici olarak abone olur) ve isteğe bağlı olarak oturur.
  RoomState openRoom(String roomId, {bool sit = true, int? seat}) {
    if (room?.roomId != roomId) {
      final old = room;
      if (old != null) _send({'op': Op.unsubscribe, 'channel': roomChannel(old.roomId)});
      room = RoomState(roomId);
    }
    if (sit) {
      _send({'op': Op.join, 'roomId': roomId, if (seat != null) 'seat': seat});
    } else {
      _send({'op': Op.subscribe, 'channel': roomChannel(roomId)});
    }
    notifyListeners();
    return room!;
  }

  void sit({int? seat}) {
    final r = room;
    if (r != null) _send({'op': Op.join, 'roomId': r.roomId, if (seat != null) 'seat': seat});
  }

  void standUp() => _send({'op': Op.leave});

  void closeRoom() {
    final r = room;
    if (r == null) return;
    if (me != null && r.seatOf(me!.id) != null) _send({'op': Op.leave});
    _send({'op': Op.unsubscribe, 'channel': roomChannel(r.roomId)});
    room = null;
    notifyListeners();
    refreshRooms();
  }

  void spin() => _send({'op': Op.spin});
  void decide(bool accept) => _send({'op': Op.decide, 'accept': accept});
  void say(String text) => _send({'op': Op.chat, 'text': text});
  void react(String emoji) => _send({'op': Op.react, 'emoji': emoji});
  void sendGift(int toSeat, GiftInfo g) => _send({'op': Op.gift, 'toSeat': toSeat, 'giftId': g.id});
  void sendGiftAll(GiftInfo g) => _send({'op': Op.giftAll, 'giftId': g.id});

  // ---------------------------------------------------------------------------
  // Market
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> packages() async {
    final r = await api.get(ApiConfig.ep('packages'));
    return [for (final x in (r['items'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
  }

  Future<Map<String, dynamic>> createOrder(String packageId, String provider) =>
      api.post(ApiConfig.ep('orders'), {'packageId': packageId, 'provider': provider});

  final _noticeCtl = StreamController<String>.broadcast();

  /// Sunucudan gelen yeni bildirim metinleri (anlık kart için).
  Stream<String> get notices => _noticeCtl.stream;

  @override
  void dispose() {
    _disposed = true;
    _closeWs();
    _poll?.cancel();
    _errors.close();
    _dmCtl.close();
    _noticeCtl.close();
    super.dispose();
  }
}

class ClientScope extends InheritedNotifier<SpectreClient> {
  const ClientScope({super.key, required SpectreClient client, required super.child}) : super(notifier: client);

  static SpectreClient of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ClientScope>()!.notifier!;

  static SpectreClient read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ClientScope>()!.notifier!;
}
