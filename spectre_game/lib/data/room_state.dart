import 'package:flutter/foundation.dart';
import 'package:spectre_core/spectre_core.dart';

/// Masada olan, efekt katmanının ve bildirimlerin dinlediği anlık olaylar.
sealed class RoomFx {
  const RoomFx();
}

class FxGift extends RoomFx {
  const FxGift(this.fromSeat, this.toSeat, this.gift);
  final int fromSeat;
  final int toSeat;
  final GiftInfo gift;
}

class FxReaction extends RoomFx {
  const FxReaction(this.seat, this.emoji);
  final int seat;
  final String emoji;
}

class FxMatch extends RoomFx {
  const FxMatch(this.a, this.b, this.success);
  final int a;
  final int b;
  final bool success;
}

class FxSeat extends RoomFx {
  const FxSeat(this.seat, this.joined);
  final int seat;
  final bool joined;
}

class FxNotice extends RoomFx {
  const FxNotice(this.text, this.kind);
  final String text;
  final String kind; // info | warn | success | gift
}

/// Sunucudan gelen masa durumunun istemci tarafı kopyası.
class RoomState extends ChangeNotifier {
  RoomState(this.roomId);

  final String roomId;
  RoomSummary? room;
  List<SeatView> seats = List.generate(kSeatCount, (i) => SeatView(index: i));
  RoundView round = RoundView();
  final List<ChatLine> chat = [];

  /// Fazın yerel saatle başladığı an (sunucu saati farkından bağımsız).
  DateTime _phaseStartLocal = DateTime.now();

  /// Son 5 sn içindeki sohbet balonları (koltuk -> metin).
  final Map<int, (String, DateTime)> bubbles = {};

  final List<void Function(RoomFx)> _fxListeners = [];
  void addFxListener(void Function(RoomFx) f) => _fxListeners.add(f);
  void removeFxListener(void Function(RoomFx) f) => _fxListeners.remove(f);
  void _fx(RoomFx e) {
    for (final f in List.of(_fxListeners)) {
      f(e);
    }
  }

  bool get loaded => room != null;
  int get occupied => seats.where((s) => s.player != null).length;
  bool get isFull => occupied >= seats.length;

  int? seatOf(String userId) {
    for (final s in seats) {
      if (s.player?.userId == userId) return s.index;
    }
    return null;
  }

  double phaseProgress(DateTime now) {
    if (round.phaseTotalMs <= 0) return 0;
    return (now.difference(_phaseStartLocal).inMilliseconds / round.phaseTotalMs).clamp(0.0, 1.0);
  }

  Duration remaining(DateTime now) {
    final left = round.phaseTotalMs - now.difference(_phaseStartLocal).inMilliseconds;
    return Duration(milliseconds: left < 0 ? 0 : left);
  }

  String? bubbleFor(int seat) {
    final b = bubbles[seat];
    if (b == null) return null;
    if (DateTime.now().difference(b.$2).inSeconds >= 5) {
      bubbles.remove(seat);
      return null;
    }
    return b.$1;
  }

  // ---------------------------------------------------------------------------

  void applySnapshot(RoomSnapshot s) {
    final prevPhase = round.phase;
    final prevRound = round.roundNo;
    room = s.room;
    seats = s.seats.length == kSeatCount ? s.seats : List.generate(kSeatCount, (i) => SeatView(index: i));
    // Faz değişmediyse yerel başlangıcı koru (titremeyi önler).
    if (s.round.phase != prevPhase || s.round.roundNo != prevRound || !loadedRound) {
      _phaseStartLocal = DateTime.now().subtract(Duration(milliseconds: s.round.phaseElapsedMs));
    }
    round = s.round;
    loadedRound = true;
    if (chat.isEmpty || s.chat.length > chat.length) {
      chat
        ..clear()
        ..addAll(s.chat);
    }
    notifyListeners();
  }

  bool loadedRound = false;

  void handle(String event, Map<String, dynamic> data) {
    switch (event) {
      case Ev.snapshot:
        applySnapshot(RoomSnapshot.fromJson(data));
      case Ev.seatUpdated:
        final idx = data['index'] as int? ?? -1;
        if (idx >= 0 && idx < kSeatCount) {
          seats[idx].player = SeatPlayer.fromJson(data);
          _fx(FxSeat(idx, true));
          notifyListeners();
        }
      case Ev.seatVacated:
        final idx = data['index'] as int? ?? -1;
        if (idx >= 0 && idx < kSeatCount) {
          seats[idx].player = null;
          _fx(FxSeat(idx, false));
          notifyListeners();
        }
      case Ev.chat:
        final line = ChatLine.fromJson(data);
        chat.add(line);
        if (chat.length > 200) chat.removeAt(0);
        if (!line.system && line.userId != null) {
          final idx = seatOf(line.userId!);
          if (idx != null) {
            bubbles[idx] = (line.text.length > 42 ? '${line.text.substring(0, 40)}…' : line.text, DateTime.now());
          }
        }
        notifyListeners();
      case Ev.chatTranslated:
        final id = '${data['id']}';
        final tr = data['translations'];
        if (tr is Map) {
          for (final l in chat.reversed) {
            if (l.id == id) {
              for (final e in tr.entries) {
                if (e.value is String) l.translations['${e.key}'] = e.value as String;
              }
              break;
            }
          }
          notifyListeners();
        }
      case Ev.gift:
        _fx(FxGift(data['fromSeat'] as int, data['toSeat'] as int,
            GiftInfo.fromJson((data['gift'] as Map).cast<String, dynamic>())));
      case Ev.reaction:
        _fx(FxReaction(data['seat'] as int, '${data['emoji']}'));
      case Ev.match:
        _fx(FxMatch(data['a'] as int, data['b'] as int, data['success'] == true));
      case Ev.notice:
        _fx(FxNotice('${data['text']}', '${data['kind'] ?? 'info'}'));
    }
  }
}
