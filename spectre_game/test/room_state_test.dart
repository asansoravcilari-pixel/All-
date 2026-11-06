import 'package:flutter_test/flutter_test.dart';
import 'package:spectre_core/spectre_core.dart';
import 'package:spectre_game/data/room_state.dart';

void main() {
  RoomSnapshot snap({int occupied = 2, RoundPhase phase = RoundPhase.idle, int elapsed = 0}) => RoomSnapshot(
        room: RoomSummary(id: '7', name: 'Neon', countInGamePlayers: occupied, inGamePlayers: occupied),
        seats: [
          for (var i = 0; i < kSeatCount; i++)
            SeatView(index: i, player: i < occupied ? SeatPlayer(userId: 'u$i', name: 'Oyuncu $i') : null),
        ],
        round: RoundView(phase: phase, phaseElapsedMs: elapsed, phaseTotalMs: 10000, active: occupied >= 2),
        chat: [ChatLine(text: 'Oyuncu 0 masaya oturdu', system: true)],
      );

  test('anlık görüntü uygulanır, koltuklar ve sohbet dolar', () {
    final r = RoomState('7')..handle(Ev.snapshot, snap().toJson());
    expect(r.loaded, isTrue);
    expect(r.occupied, 2);
    expect(r.seatOf('u1'), 1);
    expect(r.chat.single.system, isTrue);
  });

  test('seat.updated / seat.vacated koltukları günceller ve efekt yayınlar', () {
    final r = RoomState('7')..handle(Ev.snapshot, snap().toJson());
    final fx = <RoomFx>[];
    r.addFxListener(fx.add);
    r.handle(Ev.seatUpdated, {'index': 5, 'playerId': 'u9', 'name': 'Ece', 'avatarUrl': ''});
    expect(r.seats[5].player!.name, 'Ece');
    r.handle(Ev.seatVacated, {'index': 0});
    expect(r.seats[0].player, isNull);
    expect(fx.whereType<FxSeat>().map((e) => (e.seat, e.joined)), [(5, true), (0, false)]);
  });

  test('sohbet mesajı koltuk balonu oluşturur', () {
    final r = RoomState('7')..handle(Ev.snapshot, snap().toJson());
    r.handle(Ev.chat, ChatLine(userId: 'u1', name: 'Oyuncu 1', text: 'selam').toJson());
    expect(r.bubbleFor(1), 'selam');
    expect(r.chat.last.text, 'selam');
  });

  test('faz ilerlemesi sunucunun bildirdiği geçen süreyi hesaba katar', () {
    final r = RoomState('7')..handle(Ev.snapshot, snap(elapsed: 5000).toJson());
    final p = r.phaseProgress(DateTime.now());
    expect(p, greaterThanOrEqualTo(0.49));
    expect(p, lessThan(0.6));
  });
}
