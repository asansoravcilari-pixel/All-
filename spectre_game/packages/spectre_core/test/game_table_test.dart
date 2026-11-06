import 'dart:convert';
import 'dart:math' as math;

import 'package:spectre_core/spectre_core.dart';
import 'package:test/test.dart';

SeatPlayer _p(String id) => SeatPlayer(userId: id, name: 'Oyuncu $id');

void main() {
  late GameTable t;
  late DateTime now;

  setUp(() {
    t = GameTable(id: '1', name: 'Test', rules: TableRules(), random: math.Random(1));
    now = DateTime(2026, 1, 1, 12);
  });

  test('iki oyuncu oturunca tur başlar, sırası olmayan çeviremez', () {
    t.join(_p('a'), now, preferredSeat: 0);
    t.join(_p('b'), now, preferredSeat: 5);
    expect(t.phase, RoundPhase.idle);
    final spinner = t.seats[t.spinnerSeat].player!.userId;
    expect(t.spin(spinner == 'a' ? 'b' : 'a', now), isFalse);
    expect(t.spin(spinner, now), isTrue);
  });

  test('şişe hedef koltuğa bakarak durur', () {
    t.join(_p('a'), now, preferredSeat: 0);
    t.join(_p('b'), now, preferredSeat: 3);
    t.spinnerSeat = 0;
    expect(t.spin('a', now), isTrue);
    expect(t.targetSeat, 3);
    final expected = GameTable.seatAngle(3) + math.pi / 2;
    final diff = ((t.bottleAngle - expected) % (2 * math.pi) + 2 * math.pi) % (2 * math.pi);
    expect(math.min(diff, 2 * math.pi - diff), lessThan(0.05));
  });

  test('tam tur: çevir → karar → eşleşme → sıra hedefe geçer', () {
    t.join(_p('a'), now, preferredSeat: 0);
    t.join(_p('b'), now, preferredSeat: 6);
    t.spinnerSeat = 0;
    t.spin('a', now);
    now = now.add(t.rules.spinDuration);
    t.tick(now);
    expect(t.phase, RoundPhase.deciding);
    expect(t.decide('a', true, now), isTrue);
    expect(t.decide('b', true, now), isTrue);
    expect(t.phase, RoundPhase.result);
    expect(t.totalMatches, 1);
    now = now.add(t.rules.resultDuration);
    t.tick(now);
    expect(t.phase, RoundPhase.idle);
    expect(t.spinnerSeat, 6);
  });

  test('süre dolunca otomatik çevrilir, karar verilmezse pas sayılır', () {
    t.join(_p('a'), now, preferredSeat: 0);
    t.join(_p('b'), now, preferredSeat: 2);
    t.tick(now);
    now = now.add(t.rules.spinTimeout);
    t.tick(now);
    expect(t.phase, RoundPhase.spinning);
    now = now.add(t.rules.spinDuration);
    t.tick(now);
    now = now.add(t.rules.decideTimeout);
    t.tick(now);
    expect(t.phase, RoundPhase.result);
    expect(t.totalMatches, 0);
  });

  test('bağlantısı kopan oyuncu süre sonunda kaldırılır, olaylar yayınlanır', () {
    final events = <TableEvent>[];
    t.events.listen(events.add);
    t.join(_p('a'), now, preferredSeat: 0);
    t.join(_p('b'), now, preferredSeat: 4);
    expect(events.whereType<SeatUpdated>().length, 2);
    t.setConnected('b', false, now);
    expect(t.summary().inGamePlayers, 1);
    expect(t.summary().countInGamePlayers, 2);
    now = now.add(t.rules.disconnectGrace);
    t.tick(now);
    expect(t.seatOf('b'), isNull);
    expect(events.whereType<SeatVacated>().single.index, 4);
    expect(t.leftAt['b'], now);
  });

  test('kare düzen: her koltuğun açısı farklı ve şişe en yakın koltuğu gösterir', () {
    final angles = [for (var i = 0; i < kSeatCount; i++) GameTable.seatAngle(i)];
    for (var i = 0; i < kSeatCount; i++) {
      final a = angles[i];
      var best = -1;
      var bestDiff = 99.0;
      for (var j = 0; j < kSeatCount; j++) {
        final d = ((angles[j] - a + math.pi) % (2 * math.pi) - math.pi).abs();
        if (d < bestDiff) {
          bestDiff = d;
          best = j;
        }
      }
      expect(best, i);
    }
    // Sol üst köşe sol-yukarı, sağ alt köşe sağ-aşağı yönünde
    expect(math.cos(angles[0]), lessThan(0));
    expect(math.sin(angles[0]), lessThan(0));
    expect(math.cos(angles[11]), greaterThan(0));
    expect(math.sin(angles[11]), greaterThan(0));
  });

  test('kilitli masaya oturulamaz', () {
    t.locked = true;
    expect(t.join(_p('a'), now), isNull);
  });

  test('anlık görüntü JSON üzerinden kayıpsız taşınır', () {
    t.join(_p('a'), now, preferredSeat: 0);
    t.join(_p('b'), now, preferredSeat: 7);
    t.say('a', 'merhaba');
    final json = jsonDecode(jsonEncode(t.snapshot(now).toJson())) as Map<String, dynamic>;
    final s = RoomSnapshot.fromJson(json);
    expect(s.room.countInGamePlayers, 2);
    expect(s.room.gameType, 'bottle');
    expect(s.seats[7].player!.userId, 'b');
    expect(s.chat.last.text, 'merhaba');
    final rp = t.roomPlayers().map((e) => RoomPlayer.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>));
    expect(rp.map((e) => e.index), [0, 7]);
    expect(rp.every((e) => e.leaveAt == null && e.isPlaying), isTrue);
  });
}
