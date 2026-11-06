import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../data/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'pages_commerce.dart';
import 'pages_core.dart';
import 'pages_system.dart';

/// Derleme anında verilir: `--dart-define=ADMIN_PIN=xxxx`.
/// Not: İstemci tarafı PIN gerçek güvenlik değildir; canlıda yetki sunucuda doğrulanmalı.
const _adminPin = String.fromEnvironment('ADMIN_PIN', defaultValue: '0000');

class AdminSection {
  const AdminSection(this.title, this.icon, this.builder);
  final String title;
  final IconData icon;
  final Widget Function() builder;
}

final adminSections = <AdminSection>[
  AdminSection('Kontrol Merkezi', Icons.space_dashboard_rounded, () => const DashboardPage()),
  AdminSection('Oyuncular', Icons.groups_rounded, () => const PlayersPage()),
  AdminSection('Canlı Masalar', Icons.table_restaurant_rounded, () => const LiveTablesPage()),
  AdminSection('Ekonomi & Finans', Icons.query_stats_rounded, () => const EconomyPage()),
  AdminSection('Market', Icons.storefront_rounded, () => const MarketAdminPage()),
  AdminSection('Siparişler & Ödeme', Icons.receipt_long_rounded, () => const OrdersPage()),
  AdminSection('Sistem & Güvenlik', Icons.shield_rounded, () => const SystemPage()),
  AdminSection('Marka & Oyun', Icons.palette_rounded, () => const BrandGamePage()),
];

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;
  bool _unlocked = false;
  final _pin = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _tryUnlock() {
    if (_pin.text == _adminPin) {
      setState(() => _unlocked = true);
      BackendScope.read(context).security.insert(0, SecurityEvent(NoticeKind.info, 'Yönetici oturumu açıldı'));
    } else {
      setState(() => _err = 'PIN hatalı');
      BackendScope.read(context).security.insert(0, SecurityEvent(NoticeKind.warn, 'Hatalı yönetici PIN denemesi'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_unlocked) return _lock(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final section = adminSections[_index];
    final content = AnimatedSwitcher(
      duration: SpectreMotion.normal,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(position: Tween(begin: const Offset(0.02, 0), end: Offset.zero).animate(a), child: c),
      ),
      child: KeyedSubtree(key: ValueKey(_index), child: section.builder()),
    );
    return Scaffold(
      backgroundColor: SpectreColors.bg,
      appBar: wide
          ? null
          : AppBar(
              backgroundColor: SpectreColors.bg2,
              title: Text(section.title, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
      drawer: wide
          ? null
          : Drawer(
              backgroundColor: SpectreColors.bg2,
              child: SafeArea(child: _menu(context, closeDrawer: true)),
            ),
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  Container(
                    width: 250,
                    decoration: const BoxDecoration(
                      color: SpectreColors.bg2,
                      border: Border(right: BorderSide(color: SpectreColors.line)),
                    ),
                    child: _menu(context),
                  ),
                  Expanded(child: content),
                ],
              )
            : content,
      ),
    );
  }

  Widget _menu(BuildContext context, {bool closeDrawer = false}) {
    final be = BackendScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
          child: Row(children: [
            const Icon(Icons.shield_moon_rounded, color: SpectreColors.accent),
            const SizedBox(width: 8),
            Text('${be.settings.brandName} Admin',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: be.settings.maintenance ? SpectreColors.amber : SpectreColors.green,
              ),
            ),
            const SizedBox(width: 6),
            Text(be.settings.maintenance ? 'Bakım modunda' : 'Sistem çalışıyor',
                style: const TextStyle(color: SpectreColors.muted, fontSize: 12)),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              for (var i = 0; i < adminSections.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: ListTile(
                    dense: true,
                    selected: i == _index,
                    selectedTileColor: SpectreColors.accent.withOpacity(0.12),
                    selectedColor: SpectreColors.accent,
                    iconColor: SpectreColors.muted,
                    textColor: SpectreColors.ink,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: Icon(adminSections[i].icon, size: 20),
                    title: Text(adminSections[i].title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    onTap: () {
                      setState(() => _index = i);
                      if (closeDrawer) Navigator.pop(context);
                    },
                  ),
                ),
            ],
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.sports_esports_rounded, size: 20),
          title: const Text('Oyuna dön'),
          onTap: () {
            if (closeDrawer) Navigator.pop(context);
            Navigator.of(context).maybePop();
          },
        ),
      ],
    );
  }

  Widget _lock(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      body: SpectreBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GlassPanel(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.lock_rounded, size: 40, color: SpectreColors.accent),
                    const SizedBox(height: 10),
                    const Text('Yönetim Merkezi',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pin,
                      obscureText: true,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      onSubmitted: (_) => _tryUnlock(),
                      decoration: InputDecoration(labelText: 'Yönetici PIN', errorText: _err),
                    ),
                    const SizedBox(height: 14),
                    PressButton(onTap: _tryUnlock, child: const Center(child: Text('Giriş'))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
