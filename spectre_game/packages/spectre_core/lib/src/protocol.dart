// SPECTRE sunucu <-> istemci protokolü.
//
// REST (JSON):
//   GET  /room/api/v1/room                 -> {"items": [RoomSummary]}
//   GET  /room/api/v1/room/{roomId}        -> RoomSummary
//   GET  /room/api/v1/roomPlayer?roomId=&status=active&limit=12
//                                          -> {"items": [RoomPlayer]}
//   GET  /user/api/v1/user/{userId}        -> PublicUser (isOnline dahil)
//
// WebSocket (/ws?token=...):
//   istemci -> sunucu: {"op": "...", ...}
//   sunucu  -> istemci: {"channel": "room<roomId>" | null, "event": "...", "data": {...}}

/// Masa başına koltuk sayısı (index 0..11).
const int kSeatCount = 12;

String roomChannel(String roomId) => 'room$roomId';

enum RoundPhase { idle, spinning, deciding, result }

enum Presence { online, away, spinning, waiting, chosen }

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

int _int(Object? v, [int d = 0]) => v is int ? v : (v is num ? v.toInt() : (int.tryParse('$v') ?? d));
double _dbl(Object? v, [double d = 0]) => v is num ? v.toDouble() : (double.tryParse('$v') ?? d);
String _str(Object? v, [String d = '']) => v == null ? d : '$v';
bool _bool(Object? v, [bool d = false]) => v is bool ? v : d;
Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};
List<dynamic> _list(Object? v) => v is List ? v : const [];

/// `GET /room/api/v1/room/{roomId}`
class RoomSummary {
  RoomSummary({
    required this.id,
    required this.name,
    this.gameType = 'bottle',
    this.capacity = kSeatCount,
    this.inGamePlayers = 0,
    this.countInGamePlayers = 0,
    this.theme = 0,
    this.locked = false,
    this.closed = false,
  });

  final String id;
  final String name;
  final String gameType;
  final int capacity;

  /// Masada oturan ve oyunda olan oyuncu sayısı.
  final int inGamePlayers;

  /// Masadaki toplam kişi (oturan + bağlantısı kopmuş ama koltuğu duran).
  final int countInGamePlayers;
  final int theme;
  final bool locked;
  final bool closed;

  bool get isFull => countInGamePlayers >= capacity;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'gameType': gameType,
        'capacity': capacity,
        'inGamePlayers': inGamePlayers,
        'countInGamePlayers': countInGamePlayers,
        'theme': theme,
        'locked': locked,
        'closed': closed,
      };

  factory RoomSummary.fromJson(Map<String, dynamic> j) => RoomSummary(
        id: _str(j['id']),
        name: _str(j['name']),
        gameType: _str(j['gameType'], 'bottle'),
        capacity: _int(j['capacity'], kSeatCount),
        inGamePlayers: _int(j['inGamePlayers']),
        countInGamePlayers: _int(j['countInGamePlayers']),
        theme: _int(j['theme']),
        locked: _bool(j['locked']),
        closed: _bool(j['closed']),
      );
}

/// Koltuktaki oyuncunun herkese açık bilgisi.
class SeatPlayer {
  SeatPlayer({
    required this.userId,
    required this.name,
    this.avatarUrl = '',
    this.color = 0xFF65C5FF,
    this.level = 1,
    this.vip = false,
    this.hearts = 0,
  });

  final String userId;
  final String name;
  final String avatarUrl;
  final int color;
  final int level;
  final bool vip;
  int hearts;

  Map<String, dynamic> toJson() => {
        'playerId': userId,
        'userId': userId,
        'name': name,
        'avatarUrl': avatarUrl,
        'color': color,
        'level': level,
        'vip': vip,
        'hearts': hearts,
      };

  factory SeatPlayer.fromJson(Map<String, dynamic> j) => SeatPlayer(
        userId: _str(j['userId'] ?? j['playerId']),
        name: _str(j['name']),
        avatarUrl: _str(j['avatarUrl']),
        color: _int(j['color'], 0xFF65C5FF),
        level: _int(j['level'], 1),
        vip: _bool(j['vip']),
        hearts: _int(j['hearts']),
      );
}

/// `GET /room/api/v1/roomPlayer` öğesi.
class RoomPlayer {
  RoomPlayer({required this.index, required this.player, required this.isPlaying, this.leaveAt});
  final int index;
  final SeatPlayer player;
  final bool isPlaying;

  /// null ise oyuncu hâlâ masada.
  final DateTime? leaveAt;

  Map<String, dynamic> toJson() => {
        'index': index,
        'slot': index,
        ...player.toJson(),
        'isPlaying': isPlaying,
        'leaveAt': leaveAt?.toUtc().toIso8601String(),
      };

  factory RoomPlayer.fromJson(Map<String, dynamic> j) => RoomPlayer(
        index: _int(j['index'] ?? j['slot']),
        player: SeatPlayer.fromJson(j),
        isPlaying: _bool(j['isPlaying']),
        leaveAt: j['leaveAt'] == null ? null : DateTime.tryParse(_str(j['leaveAt'])),
      );
}

class SeatView {
  SeatView({required this.index, this.player, this.presence = Presence.online, this.connected = true});
  final int index;
  SeatPlayer? player;
  Presence presence;

  /// Oyuncunun bağlantısı açık mı (kapalıysa "uzakta" gösterilir).
  bool connected;

  Map<String, dynamic> toJson() => {
        'index': index,
        'player': player?.toJson(),
        'presence': presence.name,
        'connected': connected,
      };

  factory SeatView.fromJson(Map<String, dynamic> j) => SeatView(
        index: _int(j['index']),
        player: j['player'] == null ? null : SeatPlayer.fromJson(_map(j['player'])),
        presence: _enum(Presence.values, j['presence'], Presence.online),
        connected: _bool(j['connected'], true),
      );
}

class RoundView {
  RoundView({
    this.phase = RoundPhase.idle,
    this.roundNo = 0,
    this.spinnerSeat = 0,
    this.targetSeat,
    this.fromAngle = 0,
    this.bottleAngle = 0,
    this.phaseElapsedMs = 0,
    this.phaseTotalMs = 0,
    this.spinnerAccepted,
    this.targetAccepted,
    this.active = false,
  });

  RoundPhase phase;
  int roundNo;
  int spinnerSeat;
  int? targetSeat;
  double fromAngle;
  double bottleAngle;

  /// Mesaj gönderildiği anda fazın ne kadar ilerlediği (saat farkından bağımsız senkron için).
  int phaseElapsedMs;
  int phaseTotalMs;
  bool? spinnerAccepted;
  bool? targetAccepted;

  /// Masada en az iki oyuncu varsa tur aktiftir.
  bool active;

  Map<String, dynamic> toJson() => {
        'phase': phase.name,
        'roundNo': roundNo,
        'spinnerSeat': spinnerSeat,
        'targetSeat': targetSeat,
        'fromAngle': fromAngle,
        'bottleAngle': bottleAngle,
        'phaseElapsedMs': phaseElapsedMs,
        'phaseTotalMs': phaseTotalMs,
        'spinnerAccepted': spinnerAccepted,
        'targetAccepted': targetAccepted,
        'active': active,
      };

  factory RoundView.fromJson(Map<String, dynamic> j) => RoundView(
        phase: _enum(RoundPhase.values, j['phase'], RoundPhase.idle),
        roundNo: _int(j['roundNo']),
        spinnerSeat: _int(j['spinnerSeat']),
        targetSeat: j['targetSeat'] == null ? null : _int(j['targetSeat']),
        fromAngle: _dbl(j['fromAngle']),
        bottleAngle: _dbl(j['bottleAngle']),
        phaseElapsedMs: _int(j['phaseElapsedMs']),
        phaseTotalMs: _int(j['phaseTotalMs']),
        spinnerAccepted: j['spinnerAccepted'] as bool?,
        targetAccepted: j['targetAccepted'] as bool?,
        active: _bool(j['active']),
      );
}

class ChatLine {
  ChatLine({this.userId, this.name = '', required this.text, this.system = false, this.color = 0xFFEFF8FF, DateTime? at})
      : at = at ?? DateTime.now();
  final String? userId;
  final String name;
  final String text;
  final bool system;
  final int color;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'name': name,
        'text': text,
        'system': system,
        'color': color,
        'at': at.millisecondsSinceEpoch,
      };

  factory ChatLine.fromJson(Map<String, dynamic> j) => ChatLine(
        userId: j['userId'] as String?,
        name: _str(j['name']),
        text: _str(j['text']),
        system: _bool(j['system']),
        color: _int(j['color'], 0xFFEFF8FF),
        at: DateTime.fromMillisecondsSinceEpoch(_int(j['at'])),
      );
}

/// `room.snapshot` olayının verisi.
class RoomSnapshot {
  RoomSnapshot({required this.room, required this.seats, required this.round, required this.chat});
  final RoomSummary room;
  final List<SeatView> seats;
  final RoundView round;
  final List<ChatLine> chat;

  Map<String, dynamic> toJson() => {
        'room': room.toJson(),
        'seats': [for (final s in seats) s.toJson()],
        'round': round.toJson(),
        'chat': [for (final c in chat) c.toJson()],
      };

  factory RoomSnapshot.fromJson(Map<String, dynamic> j) => RoomSnapshot(
        room: RoomSummary.fromJson(_map(j['room'])),
        seats: [for (final s in _list(j['seats'])) SeatView.fromJson(_map(s))],
        round: RoundView.fromJson(_map(j['round'])),
        chat: [for (final c in _list(j['chat'])) ChatLine.fromJson(_map(c))],
      );
}

class GiftInfo {
  const GiftInfo({
    required this.id,
    required this.name,
    required this.emoji,
    required this.price,
    this.category = 'Klasik',
    this.enabled = true,
  });
  final String id;
  final String name;
  final String emoji;
  final int price;
  final String category;
  final bool enabled;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'emoji': emoji, 'price': price, 'category': category, 'enabled': enabled};

  factory GiftInfo.fromJson(Map<String, dynamic> j) => GiftInfo(
        id: _str(j['id']),
        name: _str(j['name']),
        emoji: _str(j['emoji'], '🎁'),
        price: _int(j['price']),
        category: _str(j['category'], 'Klasik'),
        enabled: _bool(j['enabled'], true),
      );
}

/// Sunucu olay adları.
abstract final class Ev {
  static const snapshot = 'room.snapshot';
  static const seatUpdated = 'seat.updated';
  static const seatVacated = 'seat.vacated';
  static const chat = 'chat.message';
  static const gift = 'gift.sent';
  static const reaction = 'reaction';
  static const match = 'match';
  static const notice = 'notice';
  static const me = 'me.updated';
  static const error = 'error';
  static const hello = 'hello';
}

/// İstemci işlem adları.
abstract final class Op {
  static const subscribe = 'subscribe';
  static const unsubscribe = 'unsubscribe';
  static const join = 'join';
  static const leave = 'leave';
  static const spin = 'spin';
  static const decide = 'decide';
  static const chat = 'chat';
  static const react = 'react';
  static const gift = 'gift';
  static const ping = 'ping';
}
