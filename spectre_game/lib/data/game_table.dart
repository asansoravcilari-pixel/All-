import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'models.dart';

/// Tur süreleri. Admin panelinden değiştirilebilir.
class TableRules {
  Duration spinTimeout = const Duration(seconds: 8);
  Duration spinDuration = const Duration(milliseconds: 3400);
  Duration decideTimeout = const Duration(seconds: 6);
  Duration resultDuration = const Duration(milliseconds: 2200);
  int seatCount = 12;
  bool chatEnabled = true;
  bool giftsEnabled = true;
  int minLevelToChat = 1;
}

/// Tek bir masanın oyun mantığı. Zaman dışarıdan verilir (`tick(now)`),
/// bu yüzden testlerde tamamen deterministik çalışır.
class GameTable extends ChangeNotifier {
  GameTable({
    required this.id,
    required this.name,
    required this.rules,
    math.Random? random,
    this.theme = 0,
  })  : _rnd = random ?? math.Random(),
        seats = List.generate(12, Seat.new);

  final String id;
  String name;
  final TableRules rules;
  final int theme;
  final math.Random _rnd;
  final List<Seat> seats;
  final RoundState round = RoundState();
  final List<ChatMessage> chat = [];
  bool closed = false;
  bool locked = false;
  int totalMatches = 0;
  int totalGifts = 0;

  final _events = StreamController<TableEvent>.broadcast();
  Stream<TableEvent> get events => _events.stream;

  /// İnsan oyuncunun kimliği (bot kararlarını atlamak için).
  String? humanId;

  // Bot karar zamanlamaları
  DateTime? _botSpinAt;
  DateTime? _spinnerDecideAt;
  DateTime? _targetDecideAt;
  bool? _spinnerBotChoice;
  bool? _targetBotChoice;

  // ---------------------------------------------------------------------------
  // Sorgular
  // ---------------------------------------------------------------------------

  int get occupied => seats.where((s) => s.player != null).length;
  bool get isFull => occupied >= seats.length;
  Iterable<Player> get players => seats.map((s) => s.player).whereType<Player>();

  int? seatOf(String playerId) {
    for (final s in seats) {
      if (s.player?.id == playerId) return s.index;
    }
    return null;
  }

  /// Koltuğun masa merkezine göre açısı (0 = üst, saat yönünde).
  static double seatAngle(int index, int count) =>
      -math.pi / 2 + index * 2 * math.pi / count;

  Duration remaining(DateTime now) {
    final started = round.phaseStarted;
    if (started == null) return Duration.zero;
    final total = switch (round.phase) {
      RoundPhase.idle => rules.spinTimeout,
      RoundPhase.spinning => rules.spinDuration,
      RoundPhase.deciding => rules.decideTimeout,
      RoundPhase.result => rules.resultDuration,
    };
    final left = total - now.difference(started);
    return left.isNegative ? Duration.zero : left;
  }

  double phaseProgress(DateTime now) {
    final started = round.phaseStarted;
    if (started == null) return 0;
    final total = switch (round.phase) {
      RoundPhase.idle => rules.spinTimeout,
      RoundPhase.spinning => rules.spinDuration,
      RoundPhase.deciding => rules.decideTimeout,
      RoundPhase.result => rules.resultDuration,
    };
    return (now.difference(started).inMilliseconds / total.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  // ---------------------------------------------------------------------------
  // Katılım
  // ---------------------------------------------------------------------------

  int? join(Player p, {int? preferredSeat, DateTime? now}) {
    if (closed || seatOf(p.id) != null) return seatOf(p.id);
    if (p.status == AccountStatus.banned || p.status == AccountStatus.suspended) {
      return null;
    }
    Seat? target;
    if (preferredSeat != null && seats[preferredSeat].player == null) {
      target = seats[preferredSeat];
    } else {
      final free = seats.where((s) => s.player == null).toList();
      if (free.isEmpty) return null;
      target = free[_rnd.nextInt(free.length)];
    }
    target
      ..player = p
      ..presence = PresenceState.online;
    _emit(JoinEvent(target.index, true));
    _system('${p.name} masaya katıldı');
    if (occupied == 2 && round.phase == RoundPhase.idle) {
      _startIdle(now ?? DateTime.now(), target.index);
    }
    notifyListeners();
    return target.index;
  }

  void leave(String playerId, {String? reason, DateTime? now}) {
    final idx = seatOf(playerId);
    if (idx == null) return;
    final p = seats[idx].player!;
    seats[idx]
      ..player = null
      ..bubble = null;
    _emit(JoinEvent(idx, false));
    _system(reason == null ? '${p.name} masadan ayrıldı' : '${p.name} $reason');
    // Turdaki biri çıktıysa turu güvenli şekilde sıfırla.
    if (round.spinnerSeat == idx || round.targetSeat == idx) {
      final next = _nextOccupied(idx);
      _startIdle(now ?? DateTime.now(), next ?? 0);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Oyuncu eylemleri
  // ---------------------------------------------------------------------------

  /// Sıradaki oyuncu şişeyi çevirir. Hedef rastgele dolu koltuktur.
  bool spin(String playerId, DateTime now) {
    if (round.phase != RoundPhase.idle) return false;
    if (seats[round.spinnerSeat].player?.id != playerId) return false;
    return _doSpin(now);
  }

  bool _doSpin(DateTime now) {
    final candidates = seats
        .where((s) => s.player != null && s.index != round.spinnerSeat)
        .map((s) => s.index)
        .toList();
    if (candidates.isEmpty) return false;
    final target = candidates[_rnd.nextInt(candidates.length)];
    final count = seats.length;
    // Şişenin ucu hedef koltuğa baksın; en az 4 tam tur + küçük sapma.
    final targetAngle = seatAngle(target, count) + math.pi / 2;
    final current = round.bottleAngle % (2 * math.pi);
    var delta = targetAngle - current;
    while (delta < 0) {
      delta += 2 * math.pi;
    }
    final turns = 4 + _rnd.nextInt(3);
    final jitter = (_rnd.nextDouble() - 0.5) * (2 * math.pi / count) * 0.35;
    round
      ..fromAngle = round.bottleAngle
      ..bottleAngle = round.bottleAngle + delta + turns * 2 * math.pi + jitter
      ..targetSeat = target
      ..phase = RoundPhase.spinning
      ..phaseStarted = now
      ..spinnerAccepted = null
      ..targetAccepted = null
      ..roundNo += 1;
    seats[round.spinnerSeat].player?.spins += 1;
    seats[round.spinnerSeat].presence = PresenceState.spinning;
    _botSpinAt = null;
    notifyListeners();
    return true;
  }

  /// Çevirenin ya da hedefin kararı.
  bool decide(String playerId, bool accept, DateTime now) {
    if (round.phase != RoundPhase.deciding) return false;
    final spinner = seats[round.spinnerSeat].player;
    final target = round.targetSeat == null ? null : seats[round.targetSeat!].player;
    if (spinner?.id == playerId && round.spinnerAccepted == null) {
      round.spinnerAccepted = accept;
    } else if (target?.id == playerId && round.targetAccepted == null) {
      round.targetAccepted = accept;
    } else {
      return false;
    }
    if (round.spinnerAccepted != null && round.targetAccepted != null) {
      _finishRound(now);
    }
    notifyListeners();
    return true;
  }

  void say(Player p, String text) {
    final clean = text.trim();
    if (clean.isEmpty || !rules.chatEnabled) return;
    if (p.status == AccountStatus.muted) return;
    final idx = seatOf(p.id);
    chat.add(ChatMessage(from: p, text: clean));
    if (chat.length > 200) chat.removeAt(0);
    if (idx != null) {
      seats[idx]
        ..bubble = clean.length > 42 ? '${clean.substring(0, 40)}…' : clean
        ..bubbleAt = DateTime.now();
    }
    notifyListeners();
  }

  void react(String playerId, String emoji) {
    final idx = seatOf(playerId);
    if (idx == null) return;
    _emit(ReactionEvent(idx, emoji));
  }

  /// Hediye gönderimi — coin kontrolü sunucu (backend) tarafında yapılır.
  void deliverGift(int fromSeat, int toSeat, Gift gift) {
    final from = seats[fromSeat].player;
    final to = seats[toSeat].player;
    if (from == null || to == null) return;
    from.giftsSent += 1;
    to.giftsReceived += 1;
    totalGifts += 1;
    _emit(GiftEvent(fromSeat, toSeat, gift));
    _emit(NoticeEvent('${from.name} → ${to.name}: ${gift.emoji} ${gift.name}',
        kind: NoticeKind.gift));
    notifyListeners();
  }

  void broadcast(String text) {
    _system('📢 $text');
    _emit(NoticeEvent(text, kind: NoticeKind.warn));
    notifyListeners();
  }

  void setPresence(String playerId, PresenceState s) {
    final idx = seatOf(playerId);
    if (idx == null) return;
    seats[idx].presence = s;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Zaman ilerletme
  // ---------------------------------------------------------------------------

  void tick(DateTime now) {
    if (closed) return;
    // Eski sohbet balonlarını temizle
    for (final s in seats) {
      if (s.bubbleAt != null && now.difference(s.bubbleAt!).inSeconds >= 5) {
        s
          ..bubble = null
          ..bubbleAt = null;
      }
    }
    if (occupied < 2) {
      if (round.phase != RoundPhase.idle) {
        round
          ..phase = RoundPhase.idle
          ..targetSeat = null;
      }
      round.phaseStarted = null;
      return;
    }
    final started = round.phaseStarted ?? now;
    final elapsed = now.difference(started);
    switch (round.phase) {
      case RoundPhase.idle:
        round.phaseStarted ??= now;
        final spinner = seats[round.spinnerSeat].player;
        if (spinner == null) {
          _startIdle(now, _nextOccupied(round.spinnerSeat) ?? 0);
          return;
        }
        if (spinner.id != humanId) {
          _botSpinAt ??= now.add(Duration(milliseconds: 900 + _rnd.nextInt(1600)));
          if (!now.isBefore(_botSpinAt!)) _doSpin(now);
        } else if (elapsed >= rules.spinTimeout) {
          _doSpin(now); // süre dolunca otomatik çevir
        }
      case RoundPhase.spinning:
        if (elapsed >= rules.spinDuration) {
          round
            ..phase = RoundPhase.deciding
            ..phaseStarted = now;
          seats[round.spinnerSeat].presence = PresenceState.waiting;
          if (round.targetSeat != null) {
            seats[round.targetSeat!].presence = PresenceState.chosen;
          }
          _planBotDecisions(now);
          notifyListeners();
        }
      case RoundPhase.deciding:
        _applyBotDecisions(now);
        if (round.phase == RoundPhase.deciding && elapsed >= rules.decideTimeout) {
          round.spinnerAccepted ??= false;
          round.targetAccepted ??= false;
          _finishRound(now);
          notifyListeners();
        }
      case RoundPhase.result:
        if (elapsed >= rules.resultDuration) {
          final next = round.targetSeat != null && seats[round.targetSeat!].player != null
              ? round.targetSeat!
              : (_nextOccupied(round.spinnerSeat) ?? 0);
          _startIdle(now, next);
          notifyListeners();
        }
    }
  }

  // ---------------------------------------------------------------------------
  // İç yardımcılar
  // ---------------------------------------------------------------------------

  void _planBotDecisions(DateTime now) {
    final spinner = seats[round.spinnerSeat].player;
    final target = round.targetSeat == null ? null : seats[round.targetSeat!].player;
    _spinnerDecideAt = null;
    _targetDecideAt = null;
    if (spinner != null && spinner.id != humanId) {
      _spinnerDecideAt = now.add(Duration(milliseconds: 600 + _rnd.nextInt(2400)));
      _spinnerBotChoice = _rnd.nextDouble() < 0.75;
    }
    if (target != null && target.id != humanId) {
      _targetDecideAt = now.add(Duration(milliseconds: 600 + _rnd.nextInt(2800)));
      _targetBotChoice = _rnd.nextDouble() < 0.7;
    }
  }

  void _applyBotDecisions(DateTime now) {
    var changed = false;
    if (_spinnerDecideAt != null && !now.isBefore(_spinnerDecideAt!) &&
        round.spinnerAccepted == null) {
      round.spinnerAccepted = _spinnerBotChoice;
      _spinnerDecideAt = null;
      changed = true;
    }
    if (_targetDecideAt != null && !now.isBefore(_targetDecideAt!) &&
        round.targetAccepted == null) {
      round.targetAccepted = _targetBotChoice;
      _targetDecideAt = null;
      changed = true;
    }
    if (round.spinnerAccepted != null && round.targetAccepted != null) {
      _finishRound(now);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void _finishRound(DateTime now) {
    if (round.phase == RoundPhase.result) return;
    final a = round.spinnerSeat;
    final b = round.targetSeat;
    round
      ..phase = RoundPhase.result
      ..phaseStarted = now;
    if (b == null) return;
    final ok = (round.spinnerAccepted ?? false) && (round.targetAccepted ?? false);
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
      if (s.player != null &&
          (s.presence == PresenceState.spinning ||
              s.presence == PresenceState.waiting ||
              s.presence == PresenceState.chosen)) {
        s.presence = PresenceState.online;
      }
    }
    final idx = seats[spinner].player != null ? spinner : (_nextOccupied(spinner) ?? 0);
    round
      ..phase = RoundPhase.idle
      ..spinnerSeat = idx
      ..targetSeat = null
      ..spinnerAccepted = null
      ..targetAccepted = null
      ..fromAngle = round.bottleAngle
      ..phaseStarted = now;
    _botSpinAt = null;
  }

  int? _nextOccupied(int from) {
    for (var i = 1; i <= seats.length; i++) {
      final idx = (from + i) % seats.length;
      if (seats[idx].player != null) return idx;
    }
    return null;
  }

  void _system(String text) {
    chat.add(ChatMessage(from: null, text: text, system: true));
    if (chat.length > 200) chat.removeAt(0);
  }

  void _emit(TableEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  @override
  void dispose() {
    _events.close();
    super.dispose();
  }
}
