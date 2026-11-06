import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'game_table.dart';
import 'models.dart';

/// Platform ayarları — admin paneli "Sistem & Güvenlik" ile yönetilir.
class PlatformSettings {
  bool maintenance = false;
  String maintenanceText = 'Kısa bir bakım yapıyoruz, birazdan döneceğiz.';
  bool registrationOpen = true;
  bool marketOpen = true;
  bool guestLogin = true;
  int maxMessagesPerMinute = 20;
  int maxGiftsPerMinute = 10;
  int dailyRewardCoins = 50;
  int startingCoins = 500;
  final List<String> blockedWords = ['küfür1', 'küfür2'];
  final List<String> blockedIps = [];
  bool twoFactorForAdmins = true;
  bool lightMode = false; // düşük donanımlı cihazlar için efektleri azaltır
  // Ödeme
  bool paytrEnabled = true;
  bool paytrTestMode = true;
  String paytrMerchantId = '';
  bool shopierEnabled = false;
  bool manualApproval = true;
  // Marka
  String brandName = 'SPECTRE';
  String tagline = 'Çevir · Tanış · Eşleş';
  Color accent = const Color(0xFF65C5FF);
}

/// Tüm uygulamanın tek veri kaynağı.
///
/// Şu an tamamen istemci tarafında çalışan bir benzetim (botlarla canlı
/// masalar). [GameTable] ve bu sınıfın genel API'si, ileride kendi
/// SPECTRE sunucunuza (WebSocket) bağlanacak gerçek uygulamanın sözleşmesidir;
/// arayüz kodu değişmeden yalnızca bu katman değiştirilir.
class SpectreBackend extends ChangeNotifier {
  SpectreBackend({int? seed, bool autoStart = true})
      : _rnd = math.Random(seed) {
    _seed();
    if (autoStart) start();
  }

  final math.Random _rnd;
  final settings = PlatformSettings();
  final rules = TableRules();
  final Map<String, Player> players = {};
  final List<GameTable> tables = [];
  final List<Gift> gifts = [];
  final List<StorePackage> packages = [];
  final List<Order> orders = [];
  final List<LedgerEntry> ledger = [];
  final List<AuditEntry> audit = [];
  final List<SecurityEvent> security = [];
  final List<String> adminNotifications = [];
  late Player me;
  Timer? _timer;
  int _botCounter = 0;
  int _orderCounter = 1000;
  DateTime? lastDailyClaim;

  // ---------------------------------------------------------------------------
  // Yaşam döngüsü
  // ---------------------------------------------------------------------------

  void start() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 250), (_) => tick(DateTime.now()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  int _ticks = 0;

  void tick(DateTime now) {
    _ticks++;
    for (final t in tables) {
      t.tick(now);
    }
    // Yaklaşık her 2 sn'de bir bot hareketleri
    if (_ticks % 8 == 0) _botLife(now);
    // Arada bir yeni sipariş (canlı finans ekranı için)
    if (_ticks % 120 == 0 && _rnd.nextDouble() < 0.6) _simulateOrder(now);
    if (_ticks % 8 == 0) notifyListeners();
  }

  @override
  void dispose() {
    stop();
    for (final t in tables) {
      t.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Oturum
  // ---------------------------------------------------------------------------

  void renameMe(String name) {
    if (name.trim().isEmpty) return;
    me.name = name.trim();
    notifyListeners();
  }

  GameTable? tableOf(String playerId) {
    for (final t in tables) {
      if (t.seatOf(playerId) != null) return t;
    }
    return null;
  }

  /// Masaya otur. Bakım modunda ya da yasaklıysa null döner.
  GameTable? joinTable(GameTable t) {
    if (settings.maintenance) return null;
    tableOf(me.id)?.leave(me.id);
    t.humanId = me.id;
    final seat = t.join(me);
    if (seat == null) return null;
    notifyListeners();
    return t;
  }

  GameTable? quickJoin() {
    final open = tables.where((t) => !t.closed && !t.locked && !t.isFull).toList()
      ..sort((a, b) => b.occupied.compareTo(a.occupied));
    if (open.isEmpty) return null;
    return joinTable(open.first);
  }

  void leaveTable() {
    final t = tableOf(me.id);
    t?.leave(me.id);
    t?.humanId = null;
    notifyListeners();
  }

  /// Hediye: coin düşülür, deftere yazılır, masada efekt yayınlanır.
  String? sendGift(GameTable t, int toSeat, Gift gift) {
    if (!rules.giftsEnabled) return 'Hediyeler şu an kapalı';
    final from = t.seatOf(me.id);
    if (from == null) return 'Önce masaya otur';
    final to = t.seats[toSeat].player;
    if (to == null) return 'Koltuk boş';
    if (me.coins < gift.price) return 'Yetersiz coin';
    me.coins -= gift.price;
    to.coins += (gift.price * 0.1).round(); // alıcıya küçük pay
    ledger.add(LedgerEntry(
        playerId: me.id, kind: LedgerKind.gift, delta: -gift.price, at: DateTime.now(),
        memo: '${gift.name} → ${to.name}'));
    t.deliverGift(from, toSeat, gift);
    notifyListeners();
    return null;
  }

  bool get canClaimDaily =>
      lastDailyClaim == null || DateTime.now().difference(lastDailyClaim!).inHours >= 20;

  int claimDaily() {
    if (!canClaimDaily) return 0;
    lastDailyClaim = DateTime.now();
    final amount = settings.dailyRewardCoins;
    me.coins += amount;
    ledger.add(LedgerEntry(
        playerId: me.id, kind: LedgerKind.reward, delta: amount, at: DateTime.now(),
        memo: 'Günlük ödül'));
    notifyListeners();
    return amount;
  }

  /// Market satın alma (benzetim — gerçek ödeme sağlayıcı yönlendirmesi yerine).
  Order buyPackage(StorePackage p, PaymentProvider provider) {
    final o = Order(
      id: 'S${_orderCounter++}',
      playerId: me.id,
      packageId: p.id,
      amountKurus: p.priceKurus,
      provider: provider,
      createdAt: DateTime.now(),
    );
    orders.insert(0, o);
    if (!settings.manualApproval || provider != PaymentProvider.manual) {
      _markPaid(o, actor: 'sistem');
    }
    notifyListeners();
    return o;
  }

  // ---------------------------------------------------------------------------
  // Admin — oyuncu yönetimi
  // ---------------------------------------------------------------------------

  void _log(String action, String target) {
    audit.insert(0, AuditEntry('admin', action, target));
    if (audit.length > 500) audit.removeLast();
  }

  void setStatus(Player p, AccountStatus s, {String reason = ''}) {
    p.status = s;
    if (s == AccountStatus.banned || s == AccountStatus.suspended) {
      tableOf(p.id)?.leave(p.id, reason: 'masadan uzaklaştırıldı');
    }
    _log('Durum → ${statusLabel(s)}${reason.isEmpty ? '' : ' ($reason)'}', p.name);
    notifyListeners();
  }

  void setRole(Player p, PlayerRole r) {
    p.role = r;
    _log('Rol → ${roleLabel(r)}', p.name);
    notifyListeners();
  }

  void adjustCoins(Player p, int delta, String memo) {
    p.coins = math.max(0, p.coins + delta);
    ledger.add(LedgerEntry(
        playerId: p.id, kind: LedgerKind.adminAdjust, delta: delta, at: DateTime.now(),
        memo: memo));
    _log('Coin ${delta >= 0 ? '+' : ''}$delta ($memo)', p.name);
    notifyListeners();
  }

  void warn(Player p, String text) {
    p.warnings.add(text);
    _log('Uyarı: $text', p.name);
    notifyListeners();
  }

  void addNote(Player p, String text) {
    p.notes.add(text);
    _log('Not eklendi', p.name);
    notifyListeners();
  }

  void kick(Player p) {
    final t = tableOf(p.id);
    if (t == null) return;
    t.leave(p.id, reason: 'yönetici tarafından masadan çıkarıldı');
    _log('Masadan çıkarıldı (${t.name})', p.name);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Admin — masalar
  // ---------------------------------------------------------------------------

  GameTable createTable(String name) {
    final t = GameTable(
        id: 't${tables.length + 1}', name: name, rules: rules, random: _rnd,
        theme: tables.length % 4);
    tables.add(t);
    _log('Masa oluşturuldu', name);
    notifyListeners();
    return t;
  }

  void closeTable(GameTable t) {
    for (final p in t.players.toList()) {
      t.leave(p.id, reason: 'masa kapatıldı');
    }
    t.closed = true;
    _log('Masa kapatıldı', t.name);
    notifyListeners();
  }

  void reopenTable(GameTable t) {
    t.closed = false;
    _log('Masa açıldı', t.name);
    notifyListeners();
  }

  void toggleLock(GameTable t) {
    t.locked = !t.locked;
    _log(t.locked ? 'Masa kilitlendi' : 'Masa kilidi açıldı', t.name);
    notifyListeners();
  }

  void broadcastAll(String text) {
    for (final t in tables.where((t) => !t.closed)) {
      t.broadcast(text);
    }
    _log('Duyuru', text);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Admin — ticaret
  // ---------------------------------------------------------------------------

  void _markPaid(Order o, {required String actor}) {
    if (o.status == OrderStatus.paid) return;
    o.status = OrderStatus.paid;
    final pkg = packages.firstWhere((p) => p.id == o.packageId, orElse: () => packages.first);
    final p = players[o.playerId];
    if (p != null) {
      final coins = pkg.coins + (pkg.coins * pkg.bonusPercent / 100).round();
      p.coins += coins;
      p.totalSpent += o.amountKurus;
      if (pkg.vipDays > 0 && p.role == PlayerRole.player) p.role = PlayerRole.vip;
      ledger.add(LedgerEntry(
          playerId: p.id, kind: LedgerKind.purchase, delta: coins, at: DateTime.now(),
          memo: '${pkg.name} (${o.id})'));
    }
    if (actor != 'sistem') _log('Sipariş onaylandı', o.id);
  }

  void approveOrder(Order o) {
    _markPaid(o, actor: 'admin');
    notifyListeners();
  }

  void refundOrder(Order o) {
    if (o.status != OrderStatus.paid) return;
    o.status = OrderStatus.refunded;
    final pkg = packages.firstWhere((p) => p.id == o.packageId, orElse: () => packages.first);
    final p = players[o.playerId];
    if (p != null) {
      p.coins = math.max(0, p.coins - pkg.coins);
      p.totalSpent -= o.amountKurus;
      ledger.add(LedgerEntry(
          playerId: p.id, kind: LedgerKind.refund, delta: -pkg.coins, at: DateTime.now(),
          memo: 'İade ${o.id}'));
    }
    _log('Sipariş iade edildi', o.id);
    notifyListeners();
  }

  void cancelOrder(Order o) {
    if (o.status != OrderStatus.pending) return;
    o.status = OrderStatus.cancelled;
    _log('Sipariş iptal edildi', o.id);
    notifyListeners();
  }

  void upsertPackage(StorePackage p) {
    final i = packages.indexWhere((x) => x.id == p.id);
    if (i < 0) {
      packages.add(p);
      _log('Paket eklendi', p.name);
    } else {
      packages[i] = p;
      _log('Paket güncellendi', p.name);
    }
    notifyListeners();
  }

  void upsertGift(Gift g) {
    final i = gifts.indexWhere((x) => x.id == g.id);
    if (i < 0) {
      gifts.add(g);
      _log('Hediye eklendi', g.name);
    } else {
      gifts[i] = g;
      _log('Hediye güncellendi', g.name);
    }
    notifyListeners();
  }

  void touchSettings(String what) {
    _log('Ayar değişti', what);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Raporlar
  // ---------------------------------------------------------------------------

  int get onlineCount => tables.fold(0, (a, t) => a + t.occupied);
  int get revenueKurus => orders
      .where((o) => o.status == OrderStatus.paid)
      .fold(0, (a, o) => a + o.amountKurus);
  int get refundedKurus => orders
      .where((o) => o.status == OrderStatus.refunded)
      .fold(0, (a, o) => a + o.amountKurus);
  int get coinsInCirculation => players.values.fold(0, (a, p) => a + p.coins);

  /// Son [days] günün günlük gelir serisi (kuruş).
  List<int> dailyRevenue(int days) {
    final now = DateTime.now();
    final out = List<int>.filled(days, 0);
    for (final o in orders) {
      if (o.status != OrderStatus.paid) continue;
      final d = now.difference(o.createdAt).inDays;
      if (d >= 0 && d < days) out[days - 1 - d] += o.amountKurus;
    }
    return out;
  }

  Map<LedgerKind, int> ledgerTotals() {
    final m = {for (final k in LedgerKind.values) k: 0};
    for (final e in ledger) {
      m[e.kind] = m[e.kind]! + e.delta;
    }
    return m;
  }

  String exportJson() {
    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': {
        'maintenance': settings.maintenance,
        'registrationOpen': settings.registrationOpen,
        'marketOpen': settings.marketOpen,
        'dailyRewardCoins': settings.dailyRewardCoins,
        'startingCoins': settings.startingCoins,
        'blockedWords': settings.blockedWords,
        'blockedIps': settings.blockedIps,
        'brandName': settings.brandName,
        'tagline': settings.tagline,
      },
      'rules': {
        'spinTimeoutSec': rules.spinTimeout.inSeconds,
        'decideTimeoutSec': rules.decideTimeout.inSeconds,
        'chatEnabled': rules.chatEnabled,
        'giftsEnabled': rules.giftsEnabled,
      },
      'packages': [
        for (final p in packages)
          {'id': p.id, 'name': p.name, 'coins': p.coins, 'priceKurus': p.priceKurus,
           'bonusPercent': p.bonusPercent, 'vipDays': p.vipDays, 'active': p.active}
      ],
      'gifts': [
        for (final g in gifts)
          {'id': g.id, 'name': g.name, 'emoji': g.emoji, 'price': g.price,
           'category': g.category, 'enabled': g.enabled}
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  // ---------------------------------------------------------------------------
  // Benzetim: botlar ve örnek veriler
  // ---------------------------------------------------------------------------

  static const _names = [
    'Ada', 'Mert', 'Elif', 'Kaan', 'Zeynep', 'Deniz', 'Arda', 'Selin', 'Emir', 'Ece',
    'Can', 'Defne', 'Baran', 'Nehir', 'Yiğit', 'Lara', 'Efe', 'Mira', 'Ozan', 'Duru',
    'Kerem', 'Asya', 'Tuna', 'İpek', 'Bora', 'Su', 'Alp', 'Naz', 'Onur', 'Ela',
  ];
  static const _palette = [
    Color(0xFF65C5FF), Color(0xFFFF7AB6), Color(0xFFFFC857), Color(0xFF7CF5C4),
    Color(0xFFB69CFF), Color(0xFFFF8F6B), Color(0xFF6BE3FF), Color(0xFFF2A1FF),
  ];
  static const _chatLines = [
    'Selam herkese 👋', 'Bu masa çok iyi 😄', 'Kim çevirecek?', 'Hadi bakalım 🍾',
    'Çok tatlısınız', 'Ben geldim!', 'İyi akşamlar', 'Bir tur daha 🔄', '😂😂',
    'Hediye için teşekkürler 💐', 'Nerelisiniz?', 'Müzik açın 🎶',
  ];
  static const _reactions = ['❤️', '😂', '😮', '👏', '🔥', '😍'];

  Player _newBot() {
    _botCounter++;
    final name = _names[_rnd.nextInt(_names.length)];
    final p = Player(
      id: 'b$_botCounter',
      name: name,
      color: _palette[_rnd.nextInt(_palette.length)],
      age: 18 + _rnd.nextInt(22),
      level: 1 + _rnd.nextInt(60),
      coins: _rnd.nextInt(4000),
      gems: _rnd.nextInt(40),
      role: _rnd.nextDouble() < 0.15 ? PlayerRole.vip : PlayerRole.player,
      isBot: true,
      joinedAt: DateTime.now().subtract(Duration(days: _rnd.nextInt(400))),
      email: '${name.toLowerCase()}$_botCounter@ornek.spectre',
      country: const ['TR', 'TR', 'TR', 'DE', 'AZ', 'NL'][_rnd.nextInt(6)],
    );
    p.hearts = _rnd.nextInt(300);
    players[p.id] = p;
    return p;
  }

  void _seed() {
    me = Player(
      id: 'me',
      name: 'Misafir',
      color: const Color(0xFF65C5FF),
      age: 24,
      level: 7,
      coins: settings.startingCoins,
      gems: 5,
      email: 'oyuncu@spectre.local',
    );
    players[me.id] = me;

    gifts.addAll(const [
      Gift(id: 'g1', name: 'Gül', emoji: '🌹', price: 10),
      Gift(id: 'g2', name: 'Kalp', emoji: '💖', price: 15),
      Gift(id: 'g3', name: 'Çikolata', emoji: '🍫', price: 20),
      Gift(id: 'g4', name: 'Kahve', emoji: '☕', price: 12),
      Gift(id: 'g5', name: 'Pasta', emoji: '🎂', price: 40, category: 'Kutlama'),
      Gift(id: 'g6', name: 'Balon', emoji: '🎈', price: 25, category: 'Kutlama'),
      Gift(id: 'g7', name: 'Yıldız', emoji: '⭐', price: 60, category: 'Premium'),
      Gift(id: 'g8', name: 'Taç', emoji: '👑', price: 150, category: 'Premium'),
      Gift(id: 'g9', name: 'Elmas', emoji: '💎', price: 300, category: 'Premium'),
      Gift(id: 'g10', name: 'Roket', emoji: '🚀', price: 500, category: 'Premium'),
      Gift(id: 'g11', name: 'Ayıcık', emoji: '🧸', price: 35),
      Gift(id: 'g12', name: 'Havai fişek', emoji: '🎆', price: 90, category: 'Kutlama'),
    ]);

    packages.addAll([
      StorePackage(id: 'p1', name: 'Başlangıç', coins: 250, priceKurus: 2999),
      StorePackage(id: 'p2', name: 'Popüler', coins: 700, priceKurus: 6999, bonusPercent: 10, featured: true),
      StorePackage(id: 'p3', name: 'Mega', coins: 1600, priceKurus: 13999, bonusPercent: 20),
      StorePackage(id: 'p4', name: 'VIP Aylık', coins: 1000, priceKurus: 19999, vipDays: 30),
    ]);

    const tableNames = ['Neon Salon', 'Gece Kulübü', 'Mavi Teras', 'Yıldız Odası', 'Sahil', 'Lounge 7'];
    for (final n in tableNames) {
      tables.add(GameTable(
          id: 't${tables.length + 1}', name: n, rules: rules, random: _rnd,
          theme: tables.length % 4));
    }
    final now = DateTime.now();
    for (final t in tables) {
      final fill = 4 + _rnd.nextInt(7);
      for (var i = 0; i < fill; i++) {
        t.join(_newBot(), now: now);
      }
      t.chat.clear();
    }
    // Ek, masada olmayan oyuncular
    for (var i = 0; i < 24; i++) {
      _newBot();
    }
    // Geçmiş siparişler (finans grafiği için)
    for (var d = 0; d < 30; d++) {
      final n = 1 + _rnd.nextInt(6);
      for (var k = 0; k < n; k++) {
        _simulateOrder(now.subtract(Duration(days: d, minutes: _rnd.nextInt(1400))));
      }
    }
    security.addAll([
      SecurityEvent(NoticeKind.info, 'Yönetici oturumu açıldı'),
      SecurityEvent(NoticeKind.warn, 'Aynı IP adresinden 5 başarısız giriş denemesi'),
    ]);
  }

  void _simulateOrder(DateTime at) {
    final bots = players.values.where((p) => p.isBot).toList();
    if (bots.isEmpty || packages.isEmpty) return;
    final p = bots[_rnd.nextInt(bots.length)];
    final pkg = packages[_rnd.nextInt(packages.length)];
    final provider = PaymentProvider.values[_rnd.nextInt(PaymentProvider.values.length)];
    final o = Order(
      id: 'S${_orderCounter++}',
      playerId: p.id,
      packageId: pkg.id,
      amountKurus: pkg.priceKurus,
      provider: provider,
      createdAt: at,
    );
    orders.insert(0, o);
    final r = _rnd.nextDouble();
    if (r < 0.82) {
      _markPaid(o, actor: 'sistem');
    } else if (r < 0.9) {
      o.status = OrderStatus.failed;
    }
    orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void _botLife(DateTime now) {
    for (final t in tables) {
      if (t.closed) continue;
      final bots = t.players.where((p) => p.isBot).toList();
      // Sohbet
      if (bots.isNotEmpty && _rnd.nextDouble() < 0.18) {
        t.say(bots[_rnd.nextInt(bots.length)], _chatLines[_rnd.nextInt(_chatLines.length)]);
      }
      // Tepki
      if (bots.isNotEmpty && _rnd.nextDouble() < 0.12) {
        t.react(bots[_rnd.nextInt(bots.length)].id, _reactions[_rnd.nextInt(_reactions.length)]);
      }
      // Hediye
      if (bots.length >= 2 && rules.giftsEnabled && _rnd.nextDouble() < 0.05) {
        final a = bots[_rnd.nextInt(bots.length)];
        final others = t.players.where((p) => p.id != a.id).toList();
        final b = others[_rnd.nextInt(others.length)];
        final g = gifts.where((g) => g.enabled).toList();
        if (g.isNotEmpty) {
          final gift = g[_rnd.nextInt(g.length)];
          ledger.add(LedgerEntry(
              playerId: a.id, kind: LedgerKind.gift, delta: -gift.price, at: now,
              memo: gift.name));
          t.deliverGift(t.seatOf(a.id)!, t.seatOf(b.id)!, gift);
        }
      }
      // Giriş / çıkış (turun ortasında oyunu bozmamak için yalnız boşta)
      if (t.round.phase == RoundPhase.idle && !t.locked) {
        if (_rnd.nextDouble() < 0.03 && bots.length > 3) {
          final b = bots[_rnd.nextInt(bots.length)];
          if (t.seats[t.round.spinnerSeat].player?.id != b.id) t.leave(b.id, now: now);
        } else if (_rnd.nextDouble() < 0.04 && !t.isFull) {
          final idle = players.values
              .where((p) => p.isBot && p.status == AccountStatus.active && tableOf(p.id) == null)
              .toList();
          if (idle.isNotEmpty) t.join(idle[_rnd.nextInt(idle.length)], now: now);
        }
      }
      // Durum: ara sıra "uzakta"
      if (bots.isNotEmpty && _rnd.nextDouble() < 0.05) {
        final b = bots[_rnd.nextInt(bots.length)];
        final s = t.seats[t.seatOf(b.id)!];
        if (s.presence == PresenceState.online) {
          s.presence = PresenceState.away;
        } else if (s.presence == PresenceState.away) {
          s.presence = PresenceState.online;
        }
      }
    }
  }
}

String statusLabel(AccountStatus s) => switch (s) {
      AccountStatus.active => 'Aktif',
      AccountStatus.muted => 'Susturuldu',
      AccountStatus.suspended => 'Askıda',
      AccountStatus.banned => 'Yasaklı',
    };

String roleLabel(PlayerRole r) => switch (r) {
      PlayerRole.player => 'Oyuncu',
      PlayerRole.vip => 'VIP',
      PlayerRole.moderator => 'Moderatör',
      PlayerRole.admin => 'Yönetici',
    };

String orderStatusLabel(OrderStatus s) => switch (s) {
      OrderStatus.pending => 'Bekliyor',
      OrderStatus.paid => 'Ödendi',
      OrderStatus.failed => 'Başarısız',
      OrderStatus.refunded => 'İade',
      OrderStatus.cancelled => 'İptal',
    };

String providerLabel(PaymentProvider p) => switch (p) {
      PaymentProvider.paytr => 'PayTR',
      PaymentProvider.shopier => 'Shopier',
      PaymentProvider.manual => 'Manuel',
    };

String tl(int kurus) {
  final s = (kurus / 100).toStringAsFixed(2).replaceAll('.', ',');
  final parts = s.split(',');
  final buf = StringBuffer();
  final int0 = parts[0];
  for (var i = 0; i < int0.length; i++) {
    if (i > 0 && (int0.length - i) % 3 == 0) buf.write('.');
    buf.write(int0[i]);
  }
  return '₺$buf,${parts[1]}';
}

/// Uygulamanın her yerinden backend'e erişim.
class BackendScope extends InheritedNotifier<SpectreBackend> {
  const BackendScope({super.key, required SpectreBackend backend, required super.child})
      : super(notifier: backend);

  static SpectreBackend of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BackendScope>()!.notifier!;

  static SpectreBackend read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BackendScope>()!.notifier!;
}
