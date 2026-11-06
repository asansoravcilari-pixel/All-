import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/backend.dart';
import '../data/models.dart';
import '../ui/theme.dart';
import 'admin_common.dart';

// ---------------------------------------------------------------------------
// Sistem & Güvenlik
// ---------------------------------------------------------------------------

class SystemPage extends StatelessWidget {
  const SystemPage({super.key});

  @override
  Widget build(BuildContext context) {
    final be = BackendScope.of(context);
    final s = be.settings;
    void set(String what, VoidCallback f) {
      f();
      be.touchSettings(what);
    }

    return AdminPage(
      title: 'Sistem & Güvenlik',
      subtitle: 'Erişim politikası, sınırlar, engeller ve kayıtlar',
      children: [
        SectionCard(
          title: 'Politika & bakım',
          icon: Icons.policy_rounded,
          child: Column(children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bakım modu'),
              subtitle: const Text('Yeni masaya girişleri durdurur, oyunculara mesaj gösterir'),
              value: s.maintenance,
              onChanged: (v) => set('Bakım modu ${v ? 'açık' : 'kapalı'}', () => s.maintenance = v),
            ),
            if (s.maintenance)
              TextFormField(
                initialValue: s.maintenanceText,
                decoration: const InputDecoration(labelText: 'Bakım mesajı'),
                onChanged: (v) => s.maintenanceText = v,
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Yeni kayıt'),
              value: s.registrationOpen,
              onChanged: (v) => set('Yeni kayıt', () => s.registrationOpen = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Misafir girişi'),
              value: s.guestLogin,
              onChanged: (v) => set('Misafir girişi', () => s.guestLogin = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Yöneticiler için iki adımlı doğrulama zorunlu'),
              value: s.twoFactorForAdmins,
              onChanged: (v) => set('2FA', () => s.twoFactorForAdmins = v),
            ),
          ]),
        ),
        SectionCard(
          title: 'Hız sınırları (spam koruması)',
          icon: Icons.speed_rounded,
          child: Column(children: [
            _SliderRow(
              label: 'Dakikada en fazla mesaj',
              value: s.maxMessagesPerMinute,
              min: 5,
              max: 60,
              onChanged: (v) => set('Mesaj sınırı', () => s.maxMessagesPerMinute = v),
            ),
            _SliderRow(
              label: 'Dakikada en fazla hediye',
              value: s.maxGiftsPerMinute,
              min: 1,
              max: 40,
              onChanged: (v) => set('Hediye sınırı', () => s.maxGiftsPerMinute = v),
            ),
          ]),
        ),
        LayoutBuilder(builder: (context, box) {
          final words = SectionCard(
            title: 'Yasaklı kelimeler',
            icon: Icons.do_not_disturb_on_rounded,
            trailing: IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: () async {
                final w = await askText(context, 'Yasaklı kelime');
                if (w != null && w.trim().isNotEmpty) set('Yasaklı kelime eklendi', () => s.blockedWords.add(w.trim()));
              },
            ),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final w in s.blockedWords)
                InputChip(label: Text(w), onDeleted: () => set('Yasaklı kelime silindi', () => s.blockedWords.remove(w))),
              if (s.blockedWords.isEmpty) const Text('Liste boş', style: TextStyle(color: SpectreColors.muted)),
            ]),
          );
          final ips = SectionCard(
            title: 'Engelli IP adresleri',
            icon: Icons.router_rounded,
            trailing: IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: () async {
                final w = await askText(context, 'IP adresi', hint: '203.0.113.7');
                final ok = w != null && RegExp(r'^[0-9a-fA-F:.]{3,45}(/\d{1,3})?$').hasMatch(w.trim());
                if (ok) set('IP engellendi', () => s.blockedIps.add(w.trim()));
              },
            ),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final w in s.blockedIps)
                InputChip(label: Text(w), onDeleted: () => set('IP engeli kaldırıldı', () => s.blockedIps.remove(w))),
              if (s.blockedIps.isEmpty) const Text('Liste boş', style: TextStyle(color: SpectreColors.muted)),
            ]),
          );
          if (box.maxWidth < 800) return Column(children: [words, ips]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: words),
            const SizedBox(width: 14),
            Expanded(child: ips),
          ]);
        }),
        SectionCard(
          title: 'Güvenlik olayları & şikâyetler',
          icon: Icons.gpp_maybe_rounded,
          child: Column(children: [
            for (final e in be.security.take(20))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  e.level == NoticeKind.warn ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                  color: e.level == NoticeKind.warn ? SpectreColors.amber : SpectreColors.accent,
                  size: 18,
                ),
                title: Text(e.text),
                trailing: Text(ago(e.at), style: const TextStyle(fontSize: 12, color: SpectreColors.muted)),
              ),
          ]),
        ),
        SectionCard(
          title: 'Denetim kaydı (tüm yönetim işlemleri)',
          icon: Icons.fact_check_rounded,
          child: be.audit.isEmpty
              ? const Text('Henüz kayıt yok', style: TextStyle(color: SpectreColors.muted))
              : Column(children: [
                  for (final a in be.audit.take(60))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(a.action),
                      subtitle: Text('${a.actor} → ${a.target}'),
                      trailing: Text(hm(a.at), style: const TextStyle(fontSize: 12, color: SpectreColors.muted)),
                    ),
                ]),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.label, required this.value, required this.min, required this.max, required this.onChanged});
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(width: 200, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          label: '$value',
          onChanged: (v) => onChanged(v.round()),
        ),
      ),
      SizedBox(width: 36, child: Text('$value', textAlign: TextAlign.end)),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Marka & Oyun (mevcut "Marka & Tema", "Masa Kontrolleri", "Yedek & JSON")
// ---------------------------------------------------------------------------

class BrandGamePage extends StatelessWidget {
  const BrandGamePage({super.key});

  @override
  Widget build(BuildContext context) {
    final be = BackendScope.of(context);
    final s = be.settings;
    final r = be.rules;
    void set(String what, VoidCallback f) {
      f();
      be.touchSettings(what);
    }

    return AdminPage(
      title: 'Marka & Oyun',
      subtitle: 'Marka metinleri, masa kuralları, ekonomi ayarları ve yedek',
      children: [
        SectionCard(
          title: 'Marka',
          icon: Icons.palette_rounded,
          child: Column(children: [
            TextFormField(
              initialValue: s.brandName,
              decoration: const InputDecoration(labelText: 'Marka adı'),
              onChanged: (v) => set('Marka adı', () => s.brandName = v.trim().isEmpty ? 'SPECTRE' : v.trim()),
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: s.tagline,
              decoration: const InputDecoration(labelText: 'Slogan'),
              onChanged: (v) => set('Slogan', () => s.tagline = v),
            ),
          ]),
        ),
        SectionCard(
          title: 'Masa kuralları',
          icon: Icons.tune_rounded,
          child: Column(children: [
            _SliderRow(
              label: 'Çevirme süresi (sn)',
              value: r.spinTimeout.inSeconds,
              min: 4,
              max: 20,
              onChanged: (v) => set('Çevirme süresi', () => r.spinTimeout = Duration(seconds: v)),
            ),
            _SliderRow(
              label: 'Karar süresi (sn)',
              value: r.decideTimeout.inSeconds,
              min: 3,
              max: 15,
              onChanged: (v) => set('Karar süresi', () => r.decideTimeout = Duration(seconds: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Masa sohbeti'),
              value: r.chatEnabled,
              onChanged: (v) => set('Sohbet', () => r.chatEnabled = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hediye gönderimi'),
              value: r.giftsEnabled,
              onChanged: (v) => set('Hediyeler', () => r.giftsEnabled = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hafif mod (efektleri azalt)'),
              subtitle: const Text('Düşük donanımlı cihazlar için'),
              value: s.lightMode,
              onChanged: (v) => set('Hafif mod', () => s.lightMode = v),
            ),
          ]),
        ),
        SectionCard(
          title: 'Ekonomi ayarları',
          icon: Icons.toll_rounded,
          child: Column(children: [
            _SliderRow(
              label: 'Günlük ödül (coin)',
              value: s.dailyRewardCoins,
              min: 0,
              max: 500,
              onChanged: (v) => set('Günlük ödül', () => s.dailyRewardCoins = v),
            ),
            _SliderRow(
              label: 'Başlangıç coini',
              value: s.startingCoins,
              min: 0,
              max: 2000,
              onChanged: (v) => set('Başlangıç coini', () => s.startingCoins = v),
            ),
          ]),
        ),
        SectionCard(
          title: 'Yedek & JSON',
          icon: Icons.backup_rounded,
          trailing: TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: be.exportJson()));
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
              child: SelectableText(
                be.exportJson(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: SpectreColors.cyan),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
