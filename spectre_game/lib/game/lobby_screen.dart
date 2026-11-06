import 'package:flutter/material.dart';

import '../admin/admin_shell.dart';
import '../data/backend.dart';
import '../data/game_table.dart';
import '../data/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
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

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  void _open(BuildContext context, GameTable? t) {
    final be = BackendScope.read(context);
    if (be.settings.maintenance) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(be.settings.maintenanceText)));
      return;
    }
    if (t == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uygun masa bulunamadı')));
      return;
    }
    Navigator.of(context).push(spectreRoute(TableScreen(table: t)));
  }

  @override
  Widget build(BuildContext context) {
    final be = BackendScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 1200 ? 3 : (width >= 720 ? 2 : 1);
    final tables = be.tables.where((t) => !t.closed).toList();
    return Scaffold(
      body: SpectreBackground(
        animate: !be.settings.lightMode,
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Header(backend: be)),
              if (be.settings.maintenance)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: GlassPanel(
                      tint: SpectreColors.amber.withOpacity(0.3),
                      child: Row(children: [
                        const Icon(Icons.construction_rounded, color: SpectreColors.amber),
                        const SizedBox(width: 10),
                        Expanded(child: Text(be.settings.maintenanceText)),
                      ]),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: _HeroCard(onPlay: () => _open(context, be.quickJoin()), backend: be),
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Text('Canlı masalar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 128,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _TableCard(
                      table: tables[i],
                      onTap: () => _open(ctx, tables[i].locked ? null : be.joinTable(tables[i])),
                    ),
                    childCount: tables.length,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.backend});
  final SpectreBackend backend;

  @override
  Widget build(BuildContext context) {
    final s = backend.settings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(colors: [SpectreColors.cyan, SpectreColors.accent, Color(0xFF3A5BFF)])
                .createShader(r),
            child: Text(s.brandName,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 4, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(s.tagline,
                overflow: TextOverflow.ellipsis, style: const TextStyle(color: SpectreColors.muted, fontSize: 12)),
          ),
          CoinPill(coins: backend.me.coins),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: 'Menü',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              switch (v) {
                case 'market':
                  Navigator.of(context).push(spectreRoute(const MarketScreen()));
                case 'name':
                  _rename(context, backend);
                case 'light':
                  s.lightMode = !s.lightMode;
                  backend.touchSettings('Hafif mod');
                case 'admin':
                  Navigator.of(context).push(spectreRoute(const AdminShell()));
              }
            },
            itemBuilder: (_) => [
              if (s.marketOpen) const PopupMenuItem(value: 'market', child: Text('🛒  Market')),
              const PopupMenuItem(value: 'name', child: Text('✏️  Adımı değiştir')),
              PopupMenuItem(value: 'light', child: Text(s.lightMode ? '✨  Efektleri aç' : '🔋  Hafif mod')),
              const PopupMenuItem(value: 'admin', child: Text('🛡️  Yönetim merkezi')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, SpectreBackend be) async {
    final ctl = TextEditingController(text: be.me.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpectreColors.panel,
        title: const Text('Oyuncu adı'),
        content: TextField(controller: ctl, autofocus: true, maxLength: 20),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Kaydet')),
        ],
      ),
    );
    if (name != null) be.renameMe(name);
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.onPlay, required this.backend});
  final VoidCallback onPlay;
  final SpectreBackend backend;

  @override
  Widget build(BuildContext context) {
    final me = backend.me;
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          PlayerAvatar(player: me, size: 64, presence: PresenceState.online),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Merhaba, ${me.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('${backend.onlineCount} oyuncu şu an masalarda',
                    style: const TextStyle(color: SpectreColors.muted, fontSize: 13)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    PressButton(
                      onTap: onPlay,
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.play_arrow_rounded),
                        SizedBox(width: 6),
                        Text('Hızlı oyna'),
                      ]),
                    ),
                    PressButton(
                      filled: false,
                      color: SpectreColors.gold,
                      onTap: backend.canClaimDaily
                          ? () {
                              final n = backend.claimDaily();
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text('Günlük ödül: +$n 🪙')));
                            }
                          : null,
                      child: Text(backend.canClaimDaily ? '🎁 Günlük ödül' : '✓ Ödül alındı'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({required this.table, required this.onTap});
  final GameTable table;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final th = TableTheme.all[table.theme % TableTheme.all.length];
    final players = table.players.take(6).toList();
    return PressButton(
      filled: false,
      glow: false,
      color: th.primary,
      padding: const EdgeInsets.all(14),
      onTap: table.locked ? null : onTap,
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [th.primary.withOpacity(0.5), th.floor]),
              border: Border.all(color: th.primary.withOpacity(0.6), width: 2),
            ),
            child: const Center(child: Text('🍾', style: TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(table.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: SpectreColors.ink)),
                  ),
                  if (table.locked) const Text('  🔒'),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: table.occupied / table.seats.length,
                    minHeight: 5,
                    backgroundColor: Colors.white10,
                    color: th.primary,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 24,
                  child: Stack(
                    children: [
                      for (var i = 0; i < players.length; i++)
                        Positioned(left: i * 16.0, child: PlayerAvatar(player: players[i], size: 24)),
                      Positioned(
                        left: players.length * 16.0 + 14,
                        top: 4,
                        child: Text('${table.occupied}/${table.seats.length}',
                            style: const TextStyle(fontSize: 12, color: SpectreColors.muted)),
                      ),
                    ],
                  ),
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

class MarketScreen extends StatelessWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final be = BackendScope.of(context);
    final pkgs = be.packages.where((p) => p.active).toList();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Market', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [Padding(padding: const EdgeInsets.only(right: 12), child: CoinPill(coins: be.me.coins))],
      ),
      extendBodyBehindAppBar: true,
      body: SpectreBackground(
        animate: !be.settings.lightMode,
        child: SafeArea(
          child: !be.settings.marketOpen
              ? const Center(child: Text('Market şu an kapalı'))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 280,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 210,
                  ),
                  itemCount: pkgs.length,
                  itemBuilder: (ctx, i) {
                    final p = pkgs[i];
                    final total = p.coins + (p.coins * p.bonusPercent / 100).round();
                    return GlassPanel(
                      tint: p.featured ? SpectreColors.accent.withOpacity(0.35) : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(p.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                            if (p.featured)
                              const Chip(label: Text('Popüler'), visualDensity: VisualDensity.compact),
                          ]),
                          const SizedBox(height: 6),
                          Text('🪙 $total', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: SpectreColors.gold)),
                          if (p.bonusPercent > 0)
                            Text('+%${p.bonusPercent} bonus', style: const TextStyle(color: SpectreColors.green, fontSize: 12)),
                          if (p.vipDays > 0)
                            Text('👑 ${p.vipDays} gün VIP', style: const TextStyle(color: SpectreColors.gold, fontSize: 12)),
                          const Spacer(),
                          SizedBox(
                            width: double.infinity,
                            child: PressButton(
                              onTap: () async {
                                final provider = await _pickProvider(ctx, be);
                                if (provider == null) return;
                                final o = be.buyPackage(p, provider);
                                if (!ctx.mounted) return;
                                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                  content: Text(o.status == OrderStatus.paid
                                      ? 'Ödeme alındı, coin eklendi (${o.id})'
                                      : 'Sipariş oluşturuldu, onay bekliyor (${o.id})'),
                                ));
                              },
                              child: Center(child: Text(tl(p.priceKurus))),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<PaymentProvider?> _pickProvider(BuildContext context, SpectreBackend be) {
    final s = be.settings;
    final options = [
      if (s.paytrEnabled) PaymentProvider.paytr,
      if (s.shopierEnabled) PaymentProvider.shopier,
      if (s.manualApproval) PaymentProvider.manual,
    ];
    return showModalBottomSheet<PaymentProvider>(
      context: context,
      backgroundColor: SpectreColors.panel,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Ödeme yöntemi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            for (final o in options)
              ListTile(
                leading: Icon(o == PaymentProvider.manual ? Icons.receipt_long_rounded : Icons.credit_card_rounded),
                title: Text(providerLabel(o)),
                subtitle: Text(o == PaymentProvider.manual
                    ? 'Havale/EFT — yönetici onayı sonrası yüklenir'
                    : (s.paytrTestMode && o == PaymentProvider.paytr ? 'Test modu' : 'Kart ile güvenli ödeme')),
                onTap: () => Navigator.pop(ctx, o),
              ),
            if (options.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('Etkin ödeme yöntemi yok')),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
