import 'package:flutter/material.dart';
import 'package:spectre_core/spectre_core.dart';

import '../admin/admin_shell.dart';
import '../data/api.dart';
import '../data/client.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'social.dart';
import 'stage_painters.dart';
import 'table_screen.dart';

Route<T> spectreRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: SpectreMotion.slow,
      reverseTransitionDuration: SpectreMotion.normal,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) {
        final c = CurvedAnimation(parent: a, curve: SpectreMotion.curve);
        return FadeTransition(
          opacity: c,
          child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(c), child: child),
        );
      },
    );

String tl(int kurus) {
  final s = (kurus / 100).toStringAsFixed(2);
  final parts = s.split('.');
  final buf = StringBuffer();
  final int0 = parts[0];
  for (var i = 0; i < int0.length; i++) {
    if (i > 0 && (int0.length - i) % 3 == 0) buf.write('.');
    buf.write(int0[i]);
  }
  return '₺$buf,${parts[1]}';
}

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  static void openRoom(BuildContext context, RoomSummary r, {bool sit = true}) {
    final c = ClientScope.read(context);
    if (c.config.maintenance) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(c.config.maintenanceText)));
      return;
    }
    final state = c.openRoom(r.id, sit: sit && !r.locked && !r.isFull);
    Navigator.of(context).push(spectreRoute(TableScreen(room: state)));
  }

  @override
  Widget build(BuildContext context) {
    final c = ClientScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 1200 ? 3 : (width >= 720 ? 2 : 1);
    final rooms = c.rooms;
    return Scaffold(
      body: SpectreBackground(
        animate: !c.lightMode,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: c.refreshRooms,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _Header(client: c)),
                if (c.config.maintenance)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: GlassPanel(
                        tint: SpectreColors.amber.withOpacity(0.3),
                        child: Row(children: [
                          const Icon(Icons.construction_rounded, color: SpectreColors.amber),
                          const SizedBox(width: 10),
                          Expanded(child: Text(c.config.maintenanceText)),
                        ]),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: _HeroCard(client: c),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Row(children: [
                      Text(c.t('lobby.tables', 'Masalar'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Text('${rooms.fold(0, (a, r) => a + r.countInGamePlayers)} oyuncu',
                          style: const TextStyle(color: SpectreColors.muted)),
                    ]),
                  ),
                ),
                if (rooms.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(children: [
                        const Icon(Icons.table_restaurant_outlined, size: 48, color: SpectreColors.muted),
                        const SizedBox(height: 10),
                        Text(c.t('lobby.empty', 'Henüz açık masa yok'), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: 112,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _TableCard(room: rooms[i], onTap: () => openRoom(ctx, rooms[i])),
                        childCount: rooms.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.client});
  final SpectreClient client;

  @override
  Widget build(BuildContext context) {
    final cfg = client.config;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          BrandLogo(text: cfg.brandName),
          const SizedBox(width: 10),
          Expanded(
            child: Text(cfg.tagline,
                overflow: TextOverflow.ellipsis, style: const TextStyle(color: SpectreColors.muted, fontSize: 12)),
          ),
          CoinPill(coins: client.me?.coins ?? 0),
          PopupMenuButton<String>(
            tooltip: 'Menü',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) async {
              switch (v) {
                case 'market':
                  Navigator.of(context).push(spectreRoute(const MarketScreen()));
                case 'name':
                  await _rename(context, client);
                case 'light':
                  await client.setLightMode(!client.lightMode);
                case 'admin':
                  Navigator.of(context).push(spectreRoute(const AdminShell()));
                case 'logout':
                  await client.logout();
              }
            },
            itemBuilder: (_) => [
              if (cfg.marketOpen) const PopupMenuItem(value: 'market', child: Text('🛒  Market')),
              const PopupMenuItem(value: 'name', child: Text('✏️  Adımı değiştir')),
              PopupMenuItem(value: 'light', child: Text(client.lightMode ? '✨  Efektleri aç' : '🔋  Hafif mod')),
              const PopupMenuItem(value: 'admin', child: Text('🛡️  Yönetim merkezi')),
              const PopupMenuItem(value: 'logout', child: Text('🚪  Çıkış yap')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, SpectreClient c) async {
    final ctl = TextEditingController(text: c.me?.displayName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpectreColors.panel,
        title: const Text('Görünen ad'),
        content: TextField(controller: ctl, autofocus: true, maxLength: 20),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Kaydet')),
        ],
      ),
    );
    if (name == null) return;
    try {
      await c.rename(name);
    } on ApiException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.client});
  final SpectreClient client;

  void _quickPlay(BuildContext context) {
    final open = client.rooms.where((r) => !r.locked && !r.isFull).toList()
      ..sort((a, b) => b.countInGamePlayers.compareTo(a.countInGamePlayers));
    if (open.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Boş koltuğu olan masa yok')));
      return;
    }
    LobbyScreen.openRoom(context, open.first);
  }

  @override
  Widget build(BuildContext context) {
    final me = client.me;
    if (me == null) return const SizedBox.shrink();
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          SquareAvatar(name: me.displayName, color: me.color, url: me.avatarUrl, size: 64, online: true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${client.t('lobby.hello', 'Merhaba')}, ${me.displayName}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('Seviye ${me.level} · ♥ ${me.hearts}${me.guest ? ' · Misafir' : ''}',
                    style: const TextStyle(color: SpectreColors.muted, fontSize: 13)),
                const SizedBox(height: 10),
                Wrap(spacing: 10, runSpacing: 8, children: [
                  PressButton(
                    onTap: () => _quickPlay(context),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.play_arrow_rounded),
                      const SizedBox(width: 6),
                      Text(client.t('lobby.quickPlay', 'Hızlı oyna')),
                    ]),
                  ),
                  PressButton(
                    filled: false,
                    color: SpectreColors.gold,
                    onTap: me.canClaimDaily
                        ? () async {
                            try {
                              final n = await client.claimDaily();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Günlük ödül: +$n 🪙')));
                              }
                            } on ApiException catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                              }
                            }
                          }
                        : null,
                    child: Text(me.canClaimDaily ? '🎁 ${client.t('lobby.daily', 'Günlük ödül')}' : '✓ Ödül alındı'),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({required this.room, required this.onTap});
  final RoomSummary room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final th = TableTheme.all[room.theme % TableTheme.all.length];
    return PressButton(
      filled: false,
      glow: false,
      color: th.primary,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [th.primary.withOpacity(0.5), th.floor]),
              border: Border.all(color: th.primary.withOpacity(0.6), width: 2),
            ),
            child: Center(
              child: Text('${room.countInGamePlayers}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(room.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: SpectreColors.ink)),
                  ),
                  if (room.locked) const Text('  🔒'),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: room.countInGamePlayers / room.capacity,
                    minHeight: 5,
                    backgroundColor: Colors.white10,
                    color: th.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${room.countInGamePlayers}/${room.capacity} koltuk dolu · ${room.inGamePlayers} aktif',
                  style: const TextStyle(fontSize: 12, color: SpectreColors.muted),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: th.primary),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Market
// ---------------------------------------------------------------------------

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  late Future<List<Map<String, dynamic>>> _pkgs = ClientScope.read(context).packages();

  @override
  Widget build(BuildContext context) {
    final c = ClientScope.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(c.t('market.title', 'Market'), style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [Padding(padding: const EdgeInsets.only(right: 12), child: CoinPill(coins: c.me?.coins ?? 0))],
      ),
      extendBodyBehindAppBar: true,
      body: SpectreBackground(
        animate: !c.lightMode,
        child: SafeArea(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _pkgs,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: () => setState(() => _pkgs = c.packages()),
                    child: Text('${snap.error} — tekrar dene'),
                  ),
                );
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final pkgs = snap.data!;
              if (pkgs.isEmpty) {
                return const Center(child: Text('Şu an satışta paket yok', style: TextStyle(color: SpectreColors.muted)));
              }
              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 210,
                ),
                itemCount: pkgs.length,
                itemBuilder: (ctx, i) => _PackageCard(p: pkgs[i], client: c),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.p, required this.client});
  final Map<String, dynamic> p;
  final SpectreClient client;

  @override
  Widget build(BuildContext context) {
    final featured = p['featured'] == true;
    final bonus = (p['bonusPercent'] as num?)?.toInt() ?? 0;
    final vip = (p['vipDays'] as num?)?.toInt() ?? 0;
    return GlassPanel(
      tint: featured ? SpectreColors.accent.withOpacity(0.35) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text('${p['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            if (featured) const Chip(label: Text('Öne çıkan'), visualDensity: VisualDensity.compact),
          ]),
          const SizedBox(height: 6),
          Text('🪙 ${p['totalCoins']}',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: SpectreColors.gold)),
          if (bonus > 0) Text('+%$bonus bonus', style: const TextStyle(color: SpectreColors.green, fontSize: 12)),
          if (vip > 0) Text('👑 $vip gün VIP', style: const TextStyle(color: SpectreColors.gold, fontSize: 12)),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: PressButton(
              onTap: client.me?.guest == true ? null : () => _buy(context),
              child: Center(child: Text(client.me?.guest == true ? 'Üye girişi gerekli' : tl((p['priceKurus'] as num).toInt()))),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _buy(BuildContext context) async {
    final pay = client.config.payment;
    final options = [
      if (pay['paytr'] == true) ('paytr', 'Kart ile (PayTR)'),
      if (pay['shopier'] == true) ('shopier', 'Kart ile (Shopier)'),
      if (pay['manual'] == true) ('manual', 'Havale / EFT'),
    ];
    final provider = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: SpectreColors.panel,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Ödeme yöntemi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          for (final o in options)
            ListTile(
              leading: Icon(o.$1 == 'manual' ? Icons.receipt_long_rounded : Icons.credit_card_rounded),
              title: Text(o.$2),
              onTap: () => Navigator.pop(ctx, o.$1),
            ),
          if (options.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Etkin ödeme yöntemi yok')),
          const SizedBox(height: 12),
        ]),
      ),
    );
    if (provider == null || !context.mounted) return;
    try {
      final r = await client.createOrder('${p['id']}', provider);
      final id = (r['order'] as Map)['id'];
      if (!context.mounted) return;
      final info = '${r['manualInfo'] ?? ''}';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: SpectreColors.panel,
          title: Text('Sipariş alındı ($id)'),
          content: Text(provider == 'manual'
              ? 'Ödemeniz yönetici onayından sonra hesabınıza yüklenir.${info.isEmpty ? '' : '\n\n$info'}'
              : 'Siparişiniz oluşturuldu. Ödeme onaylandığında coinler hesabınıza yüklenir.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam'))],
        ),
      );
    } on ApiException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
