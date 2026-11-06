import 'dart:async';
import 'dart:convert';

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

  SeatPlayer asSeatPlayer() =>
      SeatPlayer(userId: id, name: displayName, color: color, level: level, vip: vip, hearts: hearts);
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
      await refreshConfig();
      final token = prefs.getString(_tokenKey);
      if (token != null) {
        api.token = token;
        try {
          me = Me(await api.get('/api/v1/me'));
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
    config = PublicConfig(await api.get('/api/v1/config'));
    notifyListeners();
  }

  Future<void> login(String username, String password) =>
      _auth(api.post('/api/v1/auth/login', {'username': username, 'password': password}));

  Future<void> register(String username, String password, String displayName) => _auth(api.post(
      '/api/v1/auth/register', {'username': username, 'password': password, 'displayName': displayName}));

  Future<void> guest() => _auth(api.post('/api/v1/auth/guest'));

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
      await api.post('/api/v1/auth/logout');
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
      final r = await api.get('/room/api/v1/room');
      rooms = [for (final x in (r['items'] as List? ?? const [])) RoomSummary.fromJson((x as Map).cast<String, dynamic>())];
      notifyListeners();
    } on ApiException catch (e) {
      if (e.status == 401) await logout();
    }
  }

  Future<void> _loadGifts() async {
    try {
      final r = await api.get('/api/v1/gifts');
      gifts = [for (final x in (r['items'] as List? ?? const [])) GiftInfo.fromJson((x as Map).cast<String, dynamic>())];
    } catch (_) {}
  }

  Future<int> claimDaily() async {
    final r = await api.post('/api/v1/me/daily');
    me = Me((r['me'] as Map).cast<String, dynamic>());
    notifyListeners();
    return (r['amount'] as num).toInt();
  }

  Future<void> rename(String name) async {
    me = Me(await api.patch('/api/v1/me', {'displayName': name}));
    notifyListeners();
  }

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
    final r = await api.get('/api/v1/market/packages');
    return [for (final x in (r['items'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
  }

  Future<Map<String, dynamic>> createOrder(String packageId, String provider) =>
      api.post('/api/v1/orders', {'packageId': packageId, 'provider': provider});

  @override
  void dispose() {
    _disposed = true;
    _closeWs();
    _poll?.cancel();
    _errors.close();
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
