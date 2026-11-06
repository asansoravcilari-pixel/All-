import 'dart:async';
import 'dart:math' as math;

import 'protocol.dart';

/// Tur süreleri ve masa kuralları. Yönetim panelinden değiştirilir.
class TableRules {
  Duration spinTimeout = const Duration(seconds: 10);
  Duration spinDuration = const Duration(milliseconds: 3400);
  Duration decideTimeout = const Duration(seconds: 8);
  Duration resultDuration = const Duration(milliseconds: 2200);

  /// Bağlantısı kopan oyuncunun koltuğu ne kadar korunur.
  Duration disconnectGrace = const Duration(seconds: 45);
  bool chatEnabled = true;
  bool giftsEnabled = true;

  Map<String, dynamic> toJson() => {
        'spinTimeoutSec': spinTimeout.inSeconds,
        'decideTimeoutSec': decideTimeout.inSeconds,
        'disconnectGraceSec': disconnectGrace.inSeconds,
        'chatEnabled': chatEnabled,
        'giftsEnabled': giftsEnabled,
      };

  void apply(Map<String, dynamic> j) {
    int? i(String k) => j[k] is num ? (j[k] as num).toInt() : null;
    if (i('spinTimeoutSec') case final v? when v >= 3 && v <= 60) spinTimeout = Duration(seconds: v);
    if (i('decideTimeoutSec') case final v? when v >= 3 && v <= 60) decideTimeout = Duration(seconds: v);
    if (i('disconnectGraceSec') case final v? when v >= 5 && v <= 600) disconnectGrace = Duration(seconds: v);
    if (j['chatEnabled'] is bool) chatEnabled = j['chatEnabled'] as bool;
    if (j['giftsEnabled'] is bool) giftsEnabled = j['giftsEnabled'] as bool;
  }
}

/// Masada olan olay — sunucu bunları WebSocket olayına çevirir.
sealed class TableEvent {
  const TableEvent();
}

class SeatUpdated extends TableEvent {
  const SeatUpdated(this.index, this.player);
  final int index;
  final SeatPlayer player;
}

class SeatVacated extends TableEvent {
  const SeatVacated(this.index, this.userId);
  final int index;
  final String userId;
}

class ChatEvent extends TableEvent {
  const ChatEvent(this.line);
  final ChatLine line;
}

class GiftEvent extends TableEvent {
  const GiftEvent(this.fromSeat, this.toSeat, this.gift);
  final int fromSeat;
  final int toSeat;
  final GiftInfo gift;
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

class NoticeEvent extends TableEvent {
  const NoticeEvent(this.text, {this.kind = 'info'});
  final String text;
  final String kind;
}

/// Tek masanın yetkili (sunucu tarafı) oyun mantığı.
///
/// Zaman dışarıdan verilir (`tick(now)`), bu yüzden testlerde deterministiktir.
class GameTable {
  GameTable({
    required this.id,
    required this.name,
    required this.rules,
    this.theme = 0,
    math.Random? random,
  })  : _rnd = random ?? math.Random.secure(),
        seats = List.generate(kSeatCount, (i) => SeatView(index: i));

  final String id;
  String name;
  final TableRules rules;
  int theme;
  final math.Random _rnd;
  final List<SeatView> seats;
  final List<ChatLine> chat = [];
  final Map<String, DateTime> _disconnectedAt = {};
  final Map<String, DateTime> leftAt = {};

  bool closed = false;
  bool locked = false;
  int totalMatches = 0;
  int totalGifts = 0;

  RoundPhase phase = RoundPhase.idle;
  int roundNo = 0;
  int spinnerSeat = 0;
  int? targetSeat;
  double fromAngle = 0;
  double bottleAngle = 0;
  DateTime? phaseStarted;
  bool? spinnerAccepted;
  bool? targetAccepted;

  final _events = StreamController<TableEvent>.broadcast(sync: true);
  Stream<TableEvent> get events => _events.stream;

  /// Durum her değiştiğinde artar; sunucu yalnız değişince anlık görüntü yollar.
  int version = 0;

  // ---------------------------------------------------------------------------
  // Sorgular
  // ---------------------------------------------------------------------------

  int get occupied => seats.where((s) => s.player != null).length;
  int get playing => seats.where((s) => s.player != null && s.connected).length;
  bool get isFull => occupied >= seats.length;
  Iterable<SeatPlayer> get players => seats.map((s) => s.player).whereType<SeatPlayer>();

  int? seatOf(String userId) {
    for (final s in seats) {
      if (s.player?.userId == userId) return s.index;
    }
    return null;
  }

  /// Koltuğun masa merkezine göre açısı (0 = üst, saat yönünde artar).
  static double seatAngle(int index, [int count = kSeatCount]) => -math.pi / 2 + index * 2 * math.pi / count;

  Duration get _phaseTotal => switch (phase) {
        RoundPhase.idle => rules.spinTimeout,
        RoundPhase.spinning => rules.spinDuration,
        RoundPhase.deciding => rules.decideTimeout,
        RoundPhase.result => rules.resultDuration,
      };

  RoomSummary summary() => RoomSummary(
        id: id,
        name: name,
        inGamePlayers: playing,
        countInGamePlayers: occupied,
        theme: theme,
        locked: locked,
        closed: closed,
      );

  RoundView roundView(DateTime now) => RoundView(
        phase: phase,
        roundNo: roundNo,
        spinnerSeat: spinnerSeat,
        targetSeat: targetSeat,
        fromAngle: fromAngle,
        bottleAngle: bottleAngle,
        phaseElapsedMs: phaseStarted == null ? 0 : now.difference(phaseStarted!).inMilliseconds,
        phaseTotalMs: _phaseTotal.inMilliseconds,
        spinnerAccepted: spinnerAccepted,
        targetAccepted: targetAccepted,
        active: occupied >= 2,
      );

  RoomSnapshot snapshot(DateTime now) => RoomSnapshot(
        room: summary(),
        seats: seats,
        round: roundView(now),
        chat: chat.length > 60 ? chat.sublist(chat.length - 60) : chat,
      );

  List<RoomPlayer> roomPlayers({bool activeOnly = true}) => [
        for (final s in seats)
          if (s.player != null) RoomPlayer(index: s.index, player: s.player!, isPlaying: s.connected),
      ];

  // ---------------------------------------------------------------------------
  // Katılım
  // ---------------------------------------------------------------------------

  /// Oyuncuyu oturtur. Başarılıysa koltuk numarasını, değilse null döner.
  int? join(SeatPlayer p, DateTime now, {int? preferredSeat}) {
    final existing = seatOf(p.userId);
    if (existing != null) {
      setConnected(p.userId, true, now);
      return existing;
    }
    if (closed || locked) return null;
    SeatView? target;
    if (preferredSeat != null && preferredSeat >= 0 && preferredSeat < seats.length && seats[preferredSeat].player == null) {
      target = seats[preferredSeat];
    } else {
      final free = seats.where((s) => s.player == null).toList();
      if (free.isEmpty) return null;
      target = free[_rnd.nextInt(free.length)];
    }
    target
      ..player = p
      ..presence = Presence.online
      ..connected = true;
    leftAt.remove(p.userId);
    _emit(SeatUpdated(target.index, p));
    _system('${p.name} masaya oturdu');
    if (occupied == 2 && phase == RoundPhase.idle) _startIdle(now, target.index);
    _changed();
    return target.index;
  }

  void leave(String userId, DateTime now, {String? reason}) {
    final idx = seatOf(userId);
    if (idx == null) return;
    final p = seats[idx].player!;
    seats[idx]
      ..player = null
      ..presence = Presence.online
      ..connected = true;
    _disconnectedAt.remove(userId);
    leftAt[userId] = now;
    _emit(SeatVacated(idx, userId));
    _system(reason == null ? '${p.name} masadan kalktı' : '${p.name} $reason');
    if (spinnerSeat == idx || targetSeat == idx) {
      _startIdle(now, _nextOccupied(idx) ?? 0);
    }
    _changed();
  }

  /// Bağlantı koptu/geri geldi. Kopukken koltuk [TableRules.disconnectGrace] kadar korunur.
  void setConnected(String userId, bool connected, DateTime now) {
    final idx = seatOf(userId);
    if (idx == null) return;
    final s = seats[idx];
    if (s.connected == connected) return;
    s
      ..connected = connected
      ..presence = connected ? Presence.online : Presence.away;
    if (connected) {
      _disconnectedAt.remove(userId);
    } else {
      _disconnectedAt[userId] = now;
    }
    _changed();
  }

  // ---------------------------------------------------------------------------
  // Oyuncu eylemleri
  // ---------------------------------------------------------------------------

  bool spin(String userId, DateTime now) {
    if (phase != RoundPhase.idle || occupied < 2) return false;
    if (seats[spinnerSeat].player?.userId != userId) return false;
    return _doSpin(now);
  }

  bool _doSpin(DateTime now) {
    final candidates =
        seats.where((s) => s.player != null && s.index != spinnerSeat).map((s) => s.index).toList();
    if (candidates.isEmpty) return false;
    final target = candidates[_rnd.nextInt(candidates.length)];
    // Şişenin ucu hedef koltuğa baksın: en az 4 tam tur + koltuk dilimi içinde küçük sapma.
    final targetAngle = seatAngle(target) + math.pi / 2;
    final current = bottleAngle % (2 * math.pi);
    var delta = targetAngle - current;
    while (delta < 0) {
      delta += 2 * math.pi;
    }
    final turns = 4 + _rnd.nextInt(3);
    final jitter = (_rnd.nextDouble() - 0.5) * (2 * math.pi / kSeatCount) * 0.35;
    fromAngle = bottleAngle;
    bottleAngle = bottleAngle + delta + turns * 2 * math.pi + jitter;
    targetSeat = target;
    phase = RoundPhase.spinning;
    phaseStarted = now;
    spinnerAccepted = null;
    targetAccepted = null;
    roundNo += 1;
    seats[spinnerSeat].presence = Presence.spinning;
    _changed();
    return true;
  }

  bool decide(String userId, bool accept, DateTime now) {
    if (phase != RoundPhase.deciding) return false;
    final spinner = seats[spinnerSeat].player;
    final target = targetSeat == null ? null : seats[targetSeat!].player;
    if (spinner?.userId == userId && spinnerAccepted == null) {
      spinnerAccepted = accept;
    } else if (target?.userId == userId && targetAccepted == null) {
      targetAccepted = accept;
    } else {
      return false;
    }
    if (spinnerAccepted != null && targetAccepted != null) _finishRound(now);
    _changed();
    return true;
  }

  bool say(String userId, String text) {
    final idx = seatOf(userId);
    final clean = text.trim();
    if (idx == null || clean.isEmpty || !rules.chatEnabled) return false;
    final p = seats[idx].player!;
    final line = ChatLine(
        userId: p.userId, name: p.name, color: p.color, text: clean.length > 200 ? clean.substring(0, 200) : clean);
    _addChat(line);
    _emit(ChatEvent(line));
    return true;
  }

  bool react(String userId, String emoji) {
    final idx = seatOf(userId);
    if (idx == null || emoji.isEmpty || emoji.length > 16) return false;
    _emit(ReactionEvent(idx, emoji));
    return true;
  }

  /// Coin kontrolü çağıran tarafta (sunucu) yapılır.
  bool deliverGift(String fromUserId, int toSeat, GiftInfo gift) {
    final from = seatOf(fromUserId);
    if (from == null || toSeat < 0 || toSeat >= seats.length) return false;
    final to = seats[toSeat].player;
    if (to == null || to.userId == fromUserId) return false;
    totalGifts += 1;
    _emit(GiftEvent(from, toSeat, gift));
    _system('${seats[from].player!.name} → ${to.name}: ${gift.emoji} ${gift.name}');
    _changed();
    return true;
  }

  void broadcast(String text) {
    _system('📢 $text');
    _emit(NoticeEvent(text, kind: 'warn'));
    _changed();
  }

  // ---------------------------------------------------------------------------
  // Zaman
  // ---------------------------------------------------------------------------

  void tick(DateTime now) {
    if (closed) return;
    // Uzun süre bağlantısı kopuk olanları kaldır.
    for (final e in _disconnectedAt.entries.toList()) {
      if (now.difference(e.value) >= rules.disconnectGrace) {
        leave(e.key, now, reason: 'bağlantısı koptuğu için masadan ayrıldı');
      }
    }
    if (occupied < 2) {
      if (phase != RoundPhase.idle || phaseStarted != null) {
        phase = RoundPhase.idle;
        targetSeat = null;
        phaseStarted = null;
        _changed();
      }
      return;
    }
    phaseStarted ??= now;
    final elapsed = now.difference(phaseStarted!);
    switch (phase) {
      case RoundPhase.idle:
        if (seats[spinnerSeat].player == null) {
          _startIdle(now, _nextOccupied(spinnerSeat) ?? 0);
          _changed();
        } else if (elapsed >= rules.spinTimeout) {
          _doSpin(now); // süre dolunca otomatik çevrilir
        }
      case RoundPhase.spinning:
        if (elapsed >= rules.spinDuration) {
          phase = RoundPhase.deciding;
          phaseStarted = now;
          seats[spinnerSeat].presence = Presence.waiting;
          if (targetSeat != null) seats[targetSeat!].presence = Presence.chosen;
          _changed();
        }
      case RoundPhase.deciding:
        if (elapsed >= rules.decideTimeout) {
          spinnerAccepted ??= false;
          targetAccepted ??= false;
          _finishRound(now);
          _changed();
        }
      case RoundPhase.result:
        if (elapsed >= rules.resultDuration) {
          final next = targetSeat != null && seats[targetSeat!].player != null
              ? targetSeat!
              : (_nextOccupied(spinnerSeat) ?? 0);
          _startIdle(now, next);
          _changed();
        }
    }
  }

  // ---------------------------------------------------------------------------

  void _finishRound(DateTime now) {
    if (phase == RoundPhase.result) return;
    final a = spinnerSeat;
    final b = targetSeat;
    phase = RoundPhase.result;
    phaseStarted = now;
    if (b == null) return;
    final ok = (spinnerAccepted ?? false) && (targetAccepted ?? false);
    if (ok) {
      seats[a].player?.hearts += 1;
      seats[b].player?.hearts += 1;
      totalMatches += 1;
    }
    _emit(MatchEvent(a, b, ok));
    final pa = seats[a].player?.name ?? '?';
    final pb = seats[b].player?.name ?? '?';
    _system(ok ? '💞 $pa ve $pb eşleşti!' : '$pa ve $pb bu turu pas geçti');
  }

  void _startIdle(DateTime now, int spinner) {
    for (final s in seats) {
      if (s.player != null && s.connected) s.presence = Presence.online;
    }
    final idx = seats[spinner].player != null ? spinner : (_nextOccupied(spinner) ?? 0);
    phase = RoundPhase.idle;
    spinnerSeat = idx;
    targetSeat = null;
    spinnerAccepted = null;
    targetAccepted = null;
    fromAngle = bottleAngle;
    phaseStarted = now;
  }

  int? _nextOccupied(int from) {
    for (var i = 1; i <= seats.length; i++) {
      final idx = (from + i) % seats.length;
      if (seats[idx].player != null) return idx;
    }
    return null;
  }

  void _addChat(ChatLine line) {
    chat.add(line);
    if (chat.length > 200) chat.removeAt(0);
  }

  void _system(String text) {
    final line = ChatLine(text: text, system: true);
    _addChat(line);
    _emit(ChatEvent(line));
  }

  void _emit(TableEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  void _changed() => version++;

  Future<void> dispose() => _events.close();
}
