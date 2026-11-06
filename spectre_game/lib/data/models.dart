import 'dart:ui' show Color;

/// Oyuncunun masadaki anlık durumu.
enum PresenceState { online, away, spinning, waiting, chosen, muted }

enum PlayerRole { player, vip, moderator, admin }

enum AccountStatus { active, muted, suspended, banned }

class Player {
  Player({
    required this.id,
    required this.name,
    required this.color,
    this.age = 0,
    this.level = 1,
    this.coins = 0,
    this.gems = 0,
    this.role = PlayerRole.player,
    this.status = AccountStatus.active,
    this.isBot = false,
    DateTime? joinedAt,
    this.email = '',
    this.country = 'TR',
  }) : joinedAt = joinedAt ?? DateTime.now();

  final String id;
  String name;
  final Color color;
  int age;
  int level;
  int coins;
  int gems;
  PlayerRole role;
  AccountStatus status;
  final bool isBot;
  final DateTime joinedAt;
  String email;
  String country;
  DateTime lastSeen = DateTime.now();
  int hearts = 0;
  int spins = 0;
  int giftsSent = 0;
  int giftsReceived = 0;
  int totalSpent = 0; // kuruş
  final List<String> notes = [];
  final List<String> warnings = [];

  bool get isVip => role == PlayerRole.vip;
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters2.toUpperCase();
    return (parts[0].characters1 + parts[1].characters1).toUpperCase();
  }
}

extension on String {
  String get characters1 => isEmpty ? '' : String.fromCharCode(runes.first);
  String get characters2 =>
      runes.take(2).map(String.fromCharCode).join();
}

class Seat {
  Seat(this.index);
  final int index;
  Player? player;
  PresenceState presence = PresenceState.online;
  String? bubble; // kısa sohbet balonu
  DateTime? bubbleAt;
}

enum RoundPhase { idle, spinning, deciding, result }

class RoundState {
  RoundPhase phase = RoundPhase.idle;
  int spinnerSeat = 0;
  int? targetSeat;
  double bottleAngle = 0; // radyan, mutlak
  double fromAngle = 0;
  DateTime? phaseStarted;
  bool? spinnerAccepted;
  bool? targetAccepted;
  int roundNo = 0;
}

class ChatMessage {
  ChatMessage({
    required this.from,
    required this.text,
    this.system = false,
    DateTime? at,
  }) : at = at ?? DateTime.now();
  final Player? from;
  final String text;
  final bool system;
  final DateTime at;
}

class Gift {
  const Gift({
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
  final int price; // coin
  final String category;
  final bool enabled;

  Gift copyWith({String? name, String? emoji, int? price, String? category, bool? enabled}) => Gift(
        id: id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
        price: price ?? this.price,
        category: category ?? this.category,
        enabled: enabled ?? this.enabled,
      );
}

/// Masada yayınlanan olay — efekt katmanı ve bildirimler bunu dinler.
sealed class TableEvent {
  const TableEvent();
}

class GiftEvent extends TableEvent {
  const GiftEvent(this.fromSeat, this.toSeat, this.gift);
  final int fromSeat;
  final int toSeat;
  final Gift gift;
}

class ReactionEvent extends TableEvent {
  const ReactionEvent(this.seat, this.emoji);
  final int seat;
  final String emoji;
}

class MatchEvent extends TableEvent {
  const MatchEvent(this.a, this.b, this.success);
  final int a;
  final int b;
  final bool success;
}

class JoinEvent extends TableEvent {
  const JoinEvent(this.seat, this.joined);
  final int seat;
  final bool joined;
}

class NoticeEvent extends TableEvent {
  const NoticeEvent(this.text, {this.kind = NoticeKind.info});
  final String text;
  final NoticeKind kind;
}

enum NoticeKind { info, success, warn, gift }

// ---------------------------------------------------------------------------
// Ticaret
// ---------------------------------------------------------------------------

class StorePackage {
  StorePackage({
    required this.id,
    required this.name,
    required this.coins,
    required this.priceKurus,
    this.bonusPercent = 0,
    this.vipDays = 0,
    this.active = true,
    this.featured = false,
  });
  final String id;
  String name;
  int coins;
  int priceKurus;
  int bonusPercent;
  int vipDays;
  bool active;
  bool featured;
}

enum OrderStatus { pending, paid, failed, refunded, cancelled }

enum PaymentProvider { paytr, shopier, manual }

class Order {
  Order({
    required this.id,
    required this.playerId,
    required this.packageId,
    required this.amountKurus,
    required this.provider,
    required this.createdAt,
    this.status = OrderStatus.pending,
  });
  final String id;
  final String playerId;
  final String packageId;
  final int amountKurus;
  final PaymentProvider provider;
  final DateTime createdAt;
  OrderStatus status;
  String? note;
}

/// Ekonomi defteri: her coin hareketi kaydedilir.
enum LedgerKind { purchase, gift, reward, adminAdjust, refund }

class LedgerEntry {
  LedgerEntry({
    required this.playerId,
    required this.kind,
    required this.delta,
    required this.at,
    this.memo = '',
  });
  final String playerId;
  final LedgerKind kind;
  final int delta;
  final DateTime at;
  final String memo;
}

class AuditEntry {
  AuditEntry(this.actor, this.action, this.target, {DateTime? at})
      : at = at ?? DateTime.now();
  final String actor;
  final String action;
  final String target;
  final DateTime at;
}

class SecurityEvent {
  SecurityEvent(this.level, this.text, {DateTime? at}) : at = at ?? DateTime.now();
  final NoticeKind level;
  final String text;
  final DateTime at;
}
