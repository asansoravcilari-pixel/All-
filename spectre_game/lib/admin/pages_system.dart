import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/theme.dart';
import 'admin_client.dart';
import 'admin_common.dart';

class _SliderRow extends StatefulWidget {
  const _SliderRow({required this.label, required this.value, required this.min, required this.max, required this.onChanged});
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  late double _v = widget.value.toDouble().clamp(widget.min.toDouble(), widget.max.toDouble());

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(width: 200, child: Text(widget.label)),
      Expanded(
        child: Slider(
          value: _v,
          min: widget.min.toDouble(),
          max: widget.max.toDouble(),
          divisions: (widget.max - widget.min).clamp(1, 200),
          label: '${_v.round()}',
          onChanged: (v) => setState(() => _v = v),
          onChangeEnd: (v) => widget.onChanged(v.round()),
        ),
      ),
      SizedBox(width: 44, child: Text('${_v.round()}', textAlign: TextAlign.end)),
    ]);
  }
}

/// Ayarları yükleyip tek tek kaydeden ortak iskelet.
class _SettingsView extends StatefulWidget {
  const _SettingsView({required this.builder});
  final Widget Function(BuildContext context, Json settings, Json rules, Future<void> Function(Json patch, String what) set,
      Future<void> Function(Json patch, String what) setRules) builder;

  @override
  State<_SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<_SettingsView> {
  int _gen = 0;

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.read(context);
    return ApiView(
      key: ValueKey(_gen),
      load: (a) => a.get('/settings'),
      builder: (context, d, reload) {
        Future<void> set(Json patch, String what) =>
            act(context, () => admin.put('/settings', {'settings': patch, 'what': what}), ok: 'Kaydedildi', then: () => setState(() => _gen++));
        Future<void> setRules(Json patch, String what) =>
            act(context, () => admin.put('/settings', {'rules': patch, 'what': what}), ok: 'Kaydedildi', then: () => setState(() => _gen++));
        return widget.builder(
          context,
          (d['settings'] as Map).cast<String, dynamic>(),
          (d['rules'] as Map).cast<String, dynamic>(),
          set,
          setRules,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Sistem & Güvenlik
// ---------------------------------------------------------------------------

class SystemPage extends StatelessWidget {
  const SystemPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _SettingsView(builder: (context, s, rules, set, setRules) {
      final words = [for (final w in (s['blockedWords'] as List? ?? const [])) '$w'];
      final ips = [for (final w in (s['blockedIps'] as List? ?? const [])) '$w'];
      return AdminPage(
        title: 'Sistem & Güvenlik',
        subtitle: 'Erişim politikası, sınırlar, engeller, yöneticiler ve kayıtlar',
        children: [
          SectionCard(
            title: 'Politika & bakım',
            icon: Icons.policy_rounded,
            child: Column(children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Bakım modu'),
                subtitle: const Text('Oyuncular masaya oturamaz, girişte mesaj görür'),
                value: s['maintenance'] == true,
                onChanged: (v) => set({'maintenance': v}, 'Bakım modu'),
              ),
              TextFormField(
                initialValue: '${s['maintenanceText'] ?? ''}',
                decoration: const InputDecoration(labelText: 'Bakım mesajı (Enter ile kaydet)'),
                onFieldSubmitted: (v) => set({'maintenanceText': v}, 'Bakım mesajı'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Yeni kayıt'),
                value: s['registrationOpen'] == true,
                onChanged: (v) => set({'registrationOpen': v}, 'Yeni kayıt'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Misafir girişi'),
                value: s['guestLogin'] == true,
                onChanged: (v) => set({'guestLogin': v}, 'Misafir girişi'),
              ),
            ]),
          ),
          SectionCard(
            title: 'Hız sınırları (spam koruması)',
            icon: Icons.speed_rounded,
            child: Column(children: [
              _SliderRow(
                label: 'Dakikada en fazla mesaj',
                value: jn(s['maxMessagesPerMinute']),
                min: 5,
                max: 60,
                onChanged: (v) => set({'maxMessagesPerMinute': v}, 'Mesaj sınırı'),
              ),
              _SliderRow(
                label: 'Dakikada en fazla hediye',
                value: jn(s['maxGiftsPerMinute']),
                min: 1,
                max: 40,
                onChanged: (v) => set({'maxGiftsPerMinute': v}, 'Hediye sınırı'),
              ),
            ]),
          ),
          LayoutBuilder(builder: (context, box) {
            final w = SectionCard(
              title: 'Yasaklı kelimeler',
              icon: Icons.do_not_disturb_on_rounded,
              trailing: IconButton(
                icon: const Icon(Icons.add_rounded),
                onPressed: () async {
                  final v = await askText(context, 'Yasaklı kelime');
                  if (v != null && v.trim().isNotEmpty) await set({'blockedWords': [...words, v.trim()]}, 'Yasaklı kelime');
                },
              ),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final x in words)
                  InputChip(label: Text(x), onDeleted: () => set({'blockedWords': words.where((e) => e != x).toList()}, 'Yasaklı kelime')),
                if (words.isEmpty) const Text('Liste boş', style: TextStyle(color: SpectreColors.muted)),
              ]),
            );
            final ip = SectionCard(
              title: 'Engelli IP adresleri',
              icon: Icons.router_rounded,
              trailing: IconButton(
                icon: const Icon(Icons.add_rounded),
                onPressed: () async {
                  final v = await askText(context, 'IP adresi', hint: '203.0.113.7');
                  if (v != null && RegExp(r'^[0-9a-fA-F:.]{3,45}$').hasMatch(v.trim())) {
                    await set({'blockedIps': [...ips, v.trim()]}, 'IP engeli');
                  }
                },
              ),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final x in ips)
                  InputChip(label: Text(x), onDeleted: () => set({'blockedIps': ips.where((e) => e != x).toList()}, 'IP engeli')),
                if (ips.isEmpty) const Text('Liste boş', style: TextStyle(color: SpectreColors.muted)),
              ]),
            );
            if (box.maxWidth < 800) return Column(children: [w, ip]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: w),
              const SizedBox(width: 14),
              Expanded(child: ip),
            ]);
          }),
          const _AdminsCard(),
          ApiView(
            refresh: const Duration(seconds: 15),
            load: (a) => a.get('/security'),
            builder: (context, d, reload) {
              final events = jl(d['events']);
              final audit = jl(d['audit']);
              return Column(children: [
                SectionCard(
                  title: 'Güvenlik olayları',
                  icon: Icons.gpp_maybe_rounded,
                  child: events.isEmpty
                      ? const Text('Kayıt yok', style: TextStyle(color: SpectreColors.muted))
                      : Column(children: [
                          for (final e in events.take(30))
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                e['level'] == 'warn' ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                                color: e['level'] == 'warn' ? SpectreColors.amber : SpectreColors.accent,
                                size: 18,
                              ),
                              title: Text('${e['action']}'),
                              trailing: Text(ago(jd(e['at']) ?? DateTime.now()),
                                  style: const TextStyle(fontSize: 12, color: SpectreColors.muted)),
                            ),
                        ]),
                ),
                SectionCard(
                  title: 'Denetim kaydı (tüm yönetim işlemleri)',
                  icon: Icons.fact_check_rounded,
                  child: audit.isEmpty
                      ? const Text('Kayıt yok', style: TextStyle(color: SpectreColors.muted))
                      : Column(children: [
                          for (final a in audit.take(80))
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text('${a['action']}'),
                              subtitle: Text('${a['actor']} → ${a['target']}'),
                              trailing: Text(hm(jd(a['at']) ?? DateTime.now()),
                                  style: const TextStyle(fontSize: 12, color: SpectreColors.muted)),
                            ),
                        ]),
                ),
              ]);
            },
          ),
        ],
      );
    });
  }
}

class _AdminsCard extends StatefulWidget {
  const _AdminsCard();

  @override
  State<_AdminsCard> createState() => _AdminsCardState();
}

class _AdminsCardState extends State<_AdminsCard> {
  int _gen = 0;

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.of(context);
    return ApiView(
      key: ValueKey(_gen),
      load: (a) => a.get('/admins'),
      builder: (context, d, reload) => SectionCard(
        title: 'Yöneticiler',
        icon: Icons.admin_panel_settings_rounded,
        trailing: Wrap(spacing: 4, children: [
          TextButton.icon(
            onPressed: () async {
              final cur = await askText(context, 'Mevcut şifre');
              if (cur == null || !context.mounted) return;
              final next = await askText(context, 'Yeni şifre (en az 8 karakter)');
              if (next == null || !context.mounted) return;
              await act(context, () => admin.post('/password', {'current': cur, 'next': next}), ok: 'Şifre değişti');
            },
            icon: const Icon(Icons.key_rounded, size: 18),
            label: const Text('Şifremi değiştir'),
          ),
          if (admin.role == 'owner')
            TextButton.icon(
              onPressed: () async {
                final u = await askText(context, 'Yeni yönetici kullanıcı adı');
                if (u == null || u.trim().isEmpty || !context.mounted) return;
                final p = await askText(context, 'Şifre (en az 8 karakter)');
                if (p == null || !context.mounted) return;
                await act(context, () => admin.post('/admins', {'username': u.trim(), 'password': p, 'role': 'admin'}),
                    ok: 'Yönetici eklendi', then: () => setState(() => _gen++));
              },
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: const Text('Yönetici ekle'),
            ),
        ]),
        child: Column(children: [
          for (final a in jl(d['items']))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.shield_rounded, size: 18, color: SpectreColors.accent),
              title: Text('${a['username']}'),
              subtitle: Text('${a['role']}'),
              trailing: Text(jd(a['lastLogin']) == null ? 'hiç girmedi' : 'son giriş ${ago(jd(a['lastLogin'])!)}',
                  style: const TextStyle(fontSize: 12, color: SpectreColors.muted)),
            ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Marka & Oyun
// ---------------------------------------------------------------------------

class BrandGamePage extends StatelessWidget {
  const BrandGamePage({super.key});

  @override
  Widget build(BuildContext context) {
    return _SettingsView(builder: (context, s, r, set, setRules) {
      return AdminPage(
        title: 'Marka & Oyun',
        subtitle: 'Marka metinleri, masa kuralları, ekonomi ayarları ve yedek',
        children: [
          SectionCard(
            title: 'Marka',
            icon: Icons.palette_rounded,
            child: Column(children: [
              TextFormField(
                initialValue: '${s['brandName']}',
                decoration: const InputDecoration(labelText: 'Marka adı (Enter ile kaydet)'),
                onFieldSubmitted: (v) => set({'brandName': v}, 'Marka adı'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                initialValue: '${s['tagline']}',
                decoration: const InputDecoration(labelText: 'Slogan (Enter ile kaydet)'),
                onFieldSubmitted: (v) => set({'tagline': v}, 'Slogan'),
              ),
            ]),
          ),
          SectionCard(
            title: 'Masa kuralları',
            icon: Icons.tune_rounded,
            child: Column(children: [
              _SliderRow(
                label: 'Çevirme süresi (sn)',
                value: jn(r['spinTimeoutSec']),
                min: 3,
                max: 30,
                onChanged: (v) => setRules({'spinTimeoutSec': v}, 'Çevirme süresi'),
              ),
              _SliderRow(
                label: 'Karar süresi (sn)',
                value: jn(r['decideTimeoutSec']),
                min: 3,
                max: 30,
                onChanged: (v) => setRules({'decideTimeoutSec': v}, 'Karar süresi'),
              ),
              _SliderRow(
                label: 'Bağlantı kopunca koltuk (sn)',
                value: jn(r['disconnectGraceSec']),
                min: 5,
                max: 300,
                onChanged: (v) => setRules({'disconnectGraceSec': v}, 'Koltuk koruma süresi'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Masa sohbeti'),
                value: r['chatEnabled'] == true,
                onChanged: (v) => setRules({'chatEnabled': v}, 'Sohbet'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hediye gönderimi'),
                value: r['giftsEnabled'] == true,
                onChanged: (v) => setRules({'giftsEnabled': v}, 'Hediyeler'),
              ),
            ]),
          ),
          SectionCard(
            title: 'Ekonomi ayarları',
            icon: Icons.toll_rounded,
            child: Column(children: [
              _SliderRow(
                label: 'Günlük ödül (coin)',
                value: jn(s['dailyRewardCoins']),
                min: 0,
                max: 500,
                onChanged: (v) => set({'dailyRewardCoins': v}, 'Günlük ödül'),
              ),
              _SliderRow(
                label: 'Başlangıç coini',
                value: jn(s['startingCoins']),
                min: 0,
                max: 2000,
                onChanged: (v) => set({'startingCoins': v}, 'Başlangıç coini'),
              ),
            ]),
          ),
          ApiView(
            load: (a) => a.get('/export'),
            builder: (context, d, reload) {
              final text = const JsonEncoder.withIndent('  ').convert(d);
              return SectionCard(
                title: 'Yedek (JSON)',
                icon: Icons.backup_rounded,
                trailing: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) toast(context, 'Yapılandırma panoya kopyalandı');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Kopyala'),
                ),
                child: Container(
                  height: 220,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)),
                  child: SingleChildScrollView(
                    child: SelectableText(text,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: SpectreColors.cyan)),
                  ),
                ),
              );
            },
          ),
        ],
      );
    });
  }
}
