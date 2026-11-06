import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectre_game/data/backend.dart';
import 'package:spectre_game/data/game_table.dart';
import 'package:spectre_game/data/models.dart';
import 'package:spectre_game/main.dart';

Player _p(String id) => Player(id: id, name: 'Oyuncu $id', color: Colors.blue, coins: 100);

void main() {
  group('GameTable', () {
    late GameTable t;
    late DateTime now;

    setUp(() {
      t = GameTable(id: 't', name: 'Test', rules: TableRules(), random: math.Random(1));
      now = DateTime(2026, 1, 1, 12);
    });

    test('iki oyuncu katılınca tur başlar, sıradaki çevirir', () {
      t.humanId = 'a';
      t.join(_p('a'), preferredSeat: 0, now: now);
      t.join(_p('b'), preferredSeat: 5, now: now);
      expect(t.round.phase, RoundPhase.idle);
      final spinnerId = t.seats[t.round.spinnerSeat].player!.id;
      expect(t.spin(spinnerId == 'a' ? 'b' : 'a', now), isFalse, reason: 'sırası olmayan çeviremez');
    });

    test('şişe hedef koltuğa bakarak durur', () {
      t.humanId = 'a';
      t.join(_p('a'), preferredSeat: 0, now: now);
      t.join(_p('b'), preferredSeat: 3, now: now);
      t.round.spinnerSeat = 0;
      expect(t.spin('a', now), isTrue);
      expect(t.round.targetSeat, 3);
      final expected = GameTable.seatAngle(3, 12) + math.pi / 2;
      final diff = ((t.round.bottleAngle - expected) % (2 * math.pi) + 2 * math.pi) % (2 * math.pi);
      final err = math.min(diff, 2 * math.pi - diff);
      expect(err, lessThan(2 * math.pi / 12 / 2), reason: 'sapma koltuk dilimi içinde kalmalı');
      expect(t.round.bottleAngle - t.round.fromAngle, greaterThan(4 * 2 * math.pi - 1));
    });

    test('tam tur: çevir → karar → sonuç → sıra hedefe geçer', () {
      t.humanId = 'x'; // ikisi de insan değil → bot kararları
      t.join(_p('a'), preferredSeat: 0, now: now);
      t.join(_p('b'), preferredSeat: 6, now: now);
      t.round.spinnerSeat = 0;
      t.spin('a', now);
      now = now.add(t.rules.spinDuration);
      t.tick(now);
      expect(t.round.phase, RoundPhase.deciding);
      t.decide('a', true, now);
      t.decide('b', true, now);
      expect(t.round.phase, RoundPhase.result);
      expect(t.totalMatches, 1);
      expect(t.seats[0].player!.hearts, 1);
      now = now.add(t.rules.resultDuration);
      t.tick(now);
      expect(t.round.phase, RoundPhase.idle);
      expect(t.round.spinnerSeat, 6);
    });

    test('karar süresi dolarsa pas sayılır', () {
      t.humanId = 'a';
      t.join(_p('a'), preferredSeat: 0, now: now);
      t.join(_p('b'), preferredSeat: 2, now: now);
      t.humanId = 'b';
      t.round.spinnerSeat = 0;
      t.spin('a', now);
      now = now.add(t.rules.spinDuration);
      t.tick(now);
      now = now.add(t.rules.decideTimeout);
      t.tick(now);
      expect(t.round.phase, RoundPhase.result);
      expect(t.totalMatches, 0);
    });

    test('yasaklı oyuncu masaya giremez', () {
      final p = _p('z')..status = AccountStatus.banned;
      expect(t.join(p), isNull);
    });

    test('turdaki oyuncu çıkınca tur güvenle sıfırlanır', () {
      t.join(_p('a'), preferredSeat: 0, now: now);
      t.join(_p('b'), preferredSeat: 4, now: now);
      t.join(_p('c'), preferredSeat: 8, now: now);
      t.round.spinnerSeat = 0;
      t.humanId = 'a';
      t.spin('a', now);
      final target = t.round.targetSeat!;
      t.leave(t.seats[target].player!.id, now: now);
      expect(t.round.phase, RoundPhase.idle);
      expect(t.seats[t.round.spinnerSeat].player, isNotNull);
    });
  });

  group('SpectreBackend', () {
    test('hediye coin düşer, deftere yazılır', () {
      final be = SpectreBackend(seed: 3, autoStart: false);
      final t = be.joinTable(be.tables.first)!;
      final other = t.seats.firstWhere((s) => s.player != null && s.player!.id != be.me.id);
      final before = be.me.coins;
      final gift = be.gifts.first;
      expect(be.sendGift(t, other.index, gift), isNull);
      expect(be.me.coins, before - gift.price);
      expect(be.ledger.last.kind, LedgerKind.gift);
    });

    test('yetersiz coin hatası', () {
      final be = SpectreBackend(seed: 3, autoStart: false);
      final t = be.joinTable(be.tables.first)!;
      final other = t.seats.firstWhere((s) => s.player != null && s.player!.id != be.me.id);
      be.me.coins = 0;
      expect(be.sendGift(t, other.index, be.gifts.first), 'Yetersiz coin');
    });

    test('sipariş onay ve iade coin bakiyesini doğru günceller', () {
      final be = SpectreBackend(seed: 3, autoStart: false);
      be.settings.manualApproval = true;
      final pkg = be.packages.first;
      final start = be.me.coins;
      final o = be.buyPackage(pkg, PaymentProvider.manual);
      expect(o.status, OrderStatus.pending);
      expect(be.me.coins, start);
      be.approveOrder(o);
      expect(o.status, OrderStatus.paid);
      expect(be.me.coins, start + pkg.coins);
      be.refundOrder(o);
      expect(o.status, OrderStatus.refunded);
      expect(be.me.coins, start);
      expect(be.audit.any((a) => a.action.contains('iade')), isTrue);
    });

    test('yasaklanan oyuncu masadan çıkarılır', () {
      final be = SpectreBackend(seed: 3, autoStart: false);
      final t = be.tables.first;
      final victim = t.players.first;
      be.setStatus(victim, AccountStatus.banned, reason: 'test');
      expect(t.seatOf(victim.id), isNull);
    });

    test('bakım modunda masaya girilemez', () {
      final be = SpectreBackend(seed: 3, autoStart: false);
      be.settings.maintenance = true;
      expect(be.joinTable(be.tables.first), isNull);
    });

    test('benzetim uzun süre hatasız çalışır', () {
      final be = SpectreBackend(seed: 5, autoStart: false);
      var now = DateTime.now();
      for (var i = 0; i < 4000; i++) {
        now = now.add(const Duration(milliseconds: 250));
        be.tick(now);
      }
      expect(be.tables.fold(0, (a, t) => a + t.round.roundNo), greaterThan(50));
    });
  });

  testWidgets('lobi açılır ve masalar listelenir', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final be = SpectreBackend(seed: 2, autoStart: false);
    await tester.pumpWidget(SpectreApp(backend: be));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Canlı masalar'), findsOneWidget);
    expect(find.text('Neon Salon'), findsOneWidget);
  });
}
