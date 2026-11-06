import 'package:flutter/material.dart';

import '../data/api.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'admin_client.dart';
import 'pages_brand.dart';
import 'pages_commerce.dart';
import 'pages_core.dart';
import 'pages_system.dart';

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
  AdminSection('Görünüm', Icons.palette_rounded, () => const AppearancePage()),
  AdminSection('Metinler & Pencereler', Icons.text_fields_rounded, () => const TextsPage()),
  AdminSection('Marka & Oyun', Icons.tune_rounded, () => const BrandGamePage()),
  AdminSection('Bağlantı & Çeviri', Icons.alt_route_rounded, () => const ConnectionPage()),
];

/// Yönetim merkezi. Giriş kullanıcı adı + şifre ile; doğrulama sunucuda yapılır.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  final _admin = AdminClient();

  @override
  void dispose() {
    _admin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminScope(
      admin: _admin,
      child: ListenableBuilder(
        listenable: _admin,
        builder: (context, _) => AnimatedSwitcher(
          duration: SpectreMotion.normal,
          child: _admin.loggedIn ? const _AdminHome(key: ValueKey('home')) : const _AdminLogin(key: ValueKey('login')),
        ),
      ),
    );
  }
}

class _AdminLogin extends StatefulWidget {
  const _AdminLogin({super.key});

  @override
  State<_AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<_AdminLogin> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _passFocus = FocusNode();
  bool _busy = false;
  bool _hide = true;
  String? _err;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _err = 'Kullanıcı adı ve şifre gerekli');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await AdminScope.read(context).login(_user.text.trim(), _pass.text);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _err = e.message);
        _pass.selection = TextSelection(baseOffset: 0, extentOffset: _pass.text.length);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted && _err != null) _passFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      body: SpectreBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: GlassPanel(
                padding: const EdgeInsets.all(22),
                child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.shield_moon_rounded, size: 44, color: SpectreColors.accent),
                      const SizedBox(height: 10),
                      const Text('Yönetim Merkezi',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _user,
                        autofocus: true,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Kullanıcı adı', prefixIcon: Icon(Icons.person_rounded)),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _pass,
                        focusNode: _passFocus,
                        obscureText: _hide,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Şifre',
                          prefixIcon: const Icon(Icons.lock_rounded),
                          errorText: _err,
                          suffixIcon: IconButton(
                            icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                            onPressed: () => setState(() => _hide = !_hide),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      PressButton(
                        onTap: _busy ? null : _submit,
                        child: Center(
                          child: _busy
                              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Giriş'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminHome extends StatefulWidget {
  const _AdminHome({super.key});

  @override
  State<_AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<_AdminHome> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
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
      drawer: wide ? null : Drawer(backgroundColor: SpectreColors.bg2, child: SafeArea(child: _menu(context, true))),
      body: SafeArea(
        child: wide
            ? Row(children: [
                Container(
                  width: 250,
                  decoration: const BoxDecoration(
                    color: SpectreColors.bg2,
                    border: Border(right: BorderSide(color: SpectreColors.line)),
                  ),
                  child: _menu(context, false),
                ),
                Expanded(child: content),
              ])
            : content,
      ),
    );
  }

  Widget _menu(BuildContext context, bool drawer) {
    final admin = AdminScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, 4),
          child: Row(children: [
            Icon(Icons.shield_moon_rounded, color: SpectreColors.accent),
            SizedBox(width: 8),
            Text('SPECTRE Admin', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Text('${admin.username} · ${admin.role}', style: const TextStyle(color: SpectreColors.muted, fontSize: 12)),
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
                      if (drawer) Navigator.pop(context);
                    },
                  ),
                ),
            ],
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout_rounded, size: 20),
          title: const Text('Çıkış'),
          onTap: () {
            if (drawer) Navigator.pop(context);
            admin.logout();
          },
        ),
        ListTile(
          leading: const Icon(Icons.sports_esports_rounded, size: 20),
          title: const Text('Oyuna dön'),
          onTap: () {
            if (drawer) Navigator.pop(context);
            Navigator.of(context).maybePop();
          },
        ),
      ],
    );
  }
}
