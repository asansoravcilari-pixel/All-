import 'package:flutter/material.dart';

import '../data/api.dart';
import '../platform/file_pick.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'admin_client.dart';
import 'admin_common.dart';

/// Ayarları yükleyip değiştirilmiş kopyayı tek seferde kaydeden iskelet.
class _Editable extends StatefulWidget {
  const _Editable({required this.builder});
  final Widget Function(BuildContext context, Json s, void Function(VoidCallback) edit, Future<void> Function(String what) save,
      bool dirty) builder;

  @override
  State<_Editable> createState() => _EditableState();
}

class _EditableState extends State<_Editable> {
  Json? _s;
  bool _dirty = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await AdminScope.read(context).get('/settings');
      if (mounted) {
        setState(() {
          _s = _deepCopy((d['settings'] as Map).cast<String, dynamic>());
          _dirty = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  static Json _deepCopy(Json m) => {
        for (final e in m.entries)
          e.key: e.value is Map
              ? Map<String, dynamic>.from(e.value as Map)
              : e.value is List
                  ? List<dynamic>.from(e.value as List)
                  : e.value,
      };

  Future<void> _save(String what) async {
    final s = _s;
    if (s == null) return;
    final ok = await act(context, () => AdminScope.read(context).put('/settings', {'settings': s, 'what': what}),
        ok: 'Kaydedildi — oyunculara anında yansır');
    if (ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) {
      return Center(child: _err != null ? Text(_err!, style: const TextStyle(color: SpectreColors.red)) : const CircularProgressIndicator());
    }
    return widget.builder(context, s, (f) => setState(() {
          f();
          _dirty = true;
        }), _save, _dirty);
  }
}

Widget _saveButton(bool dirty, VoidCallback onSave) => PressButton(
      onTap: dirty ? onSave : null,
      child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.save_rounded), SizedBox(width: 6), Text('Kaydet')]),
    );

// ---------------------------------------------------------------------------
// Görünüm: arka plan rengi/fotoğrafı, logo, vurgu rengi
// ---------------------------------------------------------------------------

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  static const _swatches = ['#050B14', '#0A1726', '#101828', '#1A1033', '#0B1F1A', '#24120F', '#000000', '#14213D'];
  static const _accents = ['#65C5FF', '#FF6FAE', '#FFC857', '#7CF5C4', '#B69CFF', '#FF8F6B'];

  @override
  Widget build(BuildContext context) {
    return _Editable(builder: (context, s, edit, save, dirty) {
      Future<void> pickInto(String key) async {
        final bytes = await pickImageBytes();
        if (bytes == null || !context.mounted) return;
        try {
          final url = await AdminScope.read(context).upload(bytes);
          edit(() => s[key] = url);
        } catch (e) {
          if (context.mounted) toast(context, '$e');
        }
      }

      Widget colorRow(String key, String label, List<String> swatches) {
        final current = '${s[key] ?? ''}';
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final c in swatches)
              InkWell(
                onTap: () => edit(() => s[key] = c),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: parseHexColor(c),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: current.toUpperCase() == c ? Colors.white : SpectreColors.line, width: 2),
                  ),
                ),
              ),
            SizedBox(
              width: 130,
              child: TextFormField(
                key: ValueKey('$key-$current'),
                initialValue: current,
                decoration: const InputDecoration(labelText: '#RRGGBB'),
                onChanged: (v) {
                  if (parseHexColor(v) != null) edit(() => s[key] = v.toUpperCase());
                },
              ),
            ),
          ]),
        ]);
      }

      Widget imageRow(String key, String label, String hint) {
        final url = '${s[key] ?? ''}';
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(hint, style: const TextStyle(color: SpectreColors.muted, fontSize: 12)),
          const SizedBox(height: 8),
          Row(children: [
            Container(
              width: 120,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: SpectreColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: url.isEmpty
                  ? const Center(child: Text('Yok', style: TextStyle(color: SpectreColors.muted)))
                  : Image.network(mediaUrl(url), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () => pickInto(key),
                  icon: const Icon(Icons.upload_rounded, size: 18),
                  label: const Text('Yükle'),
                ),
                if (url.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => edit(() => s[key] = ''),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Kaldır'),
                  ),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('$key-url-$url'),
            initialValue: url,
            decoration: const InputDecoration(labelText: 'veya görsel adresi (https://…)'),
            onChanged: (v) => edit(() => s[key] = v.trim()),
          ),
        ]);
      }

      final bg = parseHexColor('${s['backgroundColor']}') ?? SpectreColors.bg;
      final bgImg = mediaUrl('${s['backgroundImageUrl'] ?? ''}');
      final logo = mediaUrl('${s['logoUrl'] ?? ''}');
      return AdminPage(
        title: 'Görünüm',
        subtitle: 'Arka plan, logo ve renkler — kaydedince tüm oyunculara uygulanır',
        actions: [_saveButton(dirty, () => save('Görünüm'))],
        children: [
          SectionCard(
            title: 'Önizleme',
            icon: Icons.visibility_rounded,
            child: SizedBox(
              height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Brand(
                  background: bg,
                  backgroundImage: bgImg,
                  logo: logo,
                  child: SpectreBackground(
                    child: Center(child: BrandLogo(text: '${s['brandName']}', size: 30)),
                  ),
                ),
              ),
            ),
          ),
          SectionCard(
            title: 'Arka plan',
            icon: Icons.wallpaper_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              colorRow('backgroundColor', 'Arka plan rengi', _swatches),
              const SizedBox(height: 16),
              imageRow('backgroundImageUrl', 'Arka plan fotoğrafı', 'PNG/JPG/WEBP, en fazla 4 MB. Rengin üzerine yarı saydam yerleşir.'),
            ]),
          ),
          SectionCard(
            title: 'Logo ve vurgu rengi',
            icon: Icons.auto_awesome_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              imageRow('logoUrl', 'Logo', 'Giriş ekranı ve lobide marka yazısının yerine gösterilir.'),
              const SizedBox(height: 16),
              colorRow('accentColor', 'Vurgu rengi', _accents),
            ]),
          ),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Metinler & açılır pencereler
// ---------------------------------------------------------------------------

class TextsPage extends StatefulWidget {
  const TextsPage({super.key});

  @override
  State<TextsPage> createState() => _TextsPageState();
}

class _TextsPageState extends State<TextsPage> {
  String _q = '';

  static const _groups = {
    'login': 'Giriş ekranı',
    'lobby': 'Lobi',
    'hud': 'Üst bilgi çubuğu',
    'tools': 'Araç düğmeleri',
    'table': 'Masa',
    'chat': 'Masa sohbeti',
    'composer': 'Mesaj satırı',
    'link': 'Bağlantı durumu',
    'dm': 'Mesaj kutusu',
    'notifications': 'Bildirimler',
    'market': 'Market',
  };

  static const _popupNames = {
    'tables': 'Aktif masa seçimi',
    'bonus': 'Günlük bonus',
    'market': 'Market',
    'gift': 'Oyuncuya hediye',
    'groupGift': 'Toplu hediye',
    'profile': 'Profil',
    'exit': 'Çıkış menüsü',
    'dm': 'Mesaj kutusu',
    'notifications': 'Bildirimler',
  };

  @override
  Widget build(BuildContext context) {
    return _Editable(builder: (context, s, edit, save, dirty) {
      final texts = (s['texts'] as Map).cast<String, dynamic>();
      final popups = (s['popups'] as Map).cast<String, dynamic>();
      final keys = texts.keys.where((k) => _q.isEmpty || k.contains(_q) || '${texts[k]}'.toLowerCase().contains(_q)).toList()
        ..sort();
      final byGroup = <String, List<String>>{};
      for (final k in keys) {
        byGroup.putIfAbsent(k.split('.').first, () => []).add(k);
      }
      return AdminPage(
        title: 'Metinler & Pencereler',
        subtitle: 'Oyundaki tüm yazılar ve açılır pencere açıklamaları',
        actions: [_saveButton(dirty, () => save('Metinler'))],
        children: [
          SizedBox(
            width: 320,
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Metin ara'),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
          ),
          const SizedBox(height: 12),
          for (final g in byGroup.entries)
            SectionCard(
              title: _groups[g.key] ?? g.key,
              icon: Icons.text_fields_rounded,
              child: Column(children: [
                for (final k in g.value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextFormField(
                      initialValue: '${texts[k]}',
                      decoration: InputDecoration(labelText: k),
                      onChanged: (v) => edit(() => texts[k] = v),
                    ),
                  ),
              ]),
            ),
          SectionCard(
            title: 'Açılır pencere içerikleri',
            icon: Icons.web_asset_rounded,
            child: Column(children: [
              for (final k in popups.keys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextFormField(
                    initialValue: '${popups[k]}',
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(labelText: _popupNames[k] ?? k, hintText: 'Boş bırakılırsa gösterilmez'),
                    onChanged: (v) => edit(() => popups[k] = v),
                  ),
                ),
            ]),
          ),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Bağlantı & API + otomatik çeviri
// ---------------------------------------------------------------------------

class ConnectionPage extends StatelessWidget {
  const ConnectionPage({super.key});

  static const _labels = {
    'authRegister': 'Kayıt',
    'authLogin': 'Giriş',
    'authGuest': 'Misafir girişi',
    'authLogout': 'Çıkış',
    'me': 'Hesabım',
    'meDaily': 'Günlük ödül',
    'meAvatar': 'Profil fotoğrafı',
    'roomList': 'Masa listesi',
    'roomDetail': 'Masa detayı',
    'roomPlayer': 'Masadaki oyuncular',
    'user': 'Oyuncu bilgisi',
    'gifts': 'Hediyeler',
    'packages': 'Paketler',
    'orders': 'Siparişler',
    'dmThreads': 'Mesaj kutusu',
    'dmThread': 'Mesajlaşma',
    'notifications': 'Bildirimler',
    'notificationsRead': 'Bildirimleri okundu say',
    'ws': 'WebSocket',
  };

  @override
  Widget build(BuildContext context) {
    return _Editable(builder: (context, s, edit, save, dirty) {
      final eps = (s['endpoints'] as Map).cast<String, dynamic>();
      final langs = [for (final l in (s['languages'] as List? ?? const [])) '$l'];
      return AdminPage(
        title: 'Bağlantı & Çeviri',
        subtitle: 'Sunucu adresi, uç nokta yolları ve otomatik çeviri servisi',
        actions: [_saveButton(dirty, () => save('Bağlantı'))],
        children: [
          SectionCard(
            title: 'Sunucu adresi',
            icon: Icons.dns_rounded,
            child: Column(children: [
              TextFormField(
                initialValue: '${s['apiBase'] ?? ''}',
                decoration: const InputDecoration(
                    labelText: 'API adresi', hintText: 'Boş = uygulamanın açıldığı adres (ör. https://api.alanadin.com)'),
                onChanged: (v) => edit(() => s['apiBase'] = v.trim()),
              ),
              const SizedBox(height: 10),
              TextFormField(
                initialValue: '${s['wsUrl'] ?? ''}',
                decoration: const InputDecoration(labelText: 'WebSocket adresi', hintText: 'Boş = API adresi + WebSocket yolu'),
                onChanged: (v) => edit(() => s['wsUrl'] = v.trim()),
              ),
            ]),
          ),
          SectionCard(
            title: 'Uç nokta yolları',
            icon: Icons.alt_route_rounded,
            trailing: TextButton(
              onPressed: () => edit(() => eps
                ..clear()
                ..addAll(ApiConfig.defaultEndpoints)),
              child: const Text('Varsayılana dön'),
            ),
            child: Column(children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Yollar sunucu ve uygulamada birlikte değişir. {roomId}, {userId} gibi parçalar korunmalıdır. '
                    '/admin ve /uploads ile başlayan yollar kullanılamaz.',
                    style: TextStyle(color: SpectreColors.muted, fontSize: 12),
                  ),
                ),
              ),
              for (final k in ApiConfig.defaultEndpoints.keys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextFormField(
                    key: ValueKey('$k-${eps[k]}'),
                    initialValue: '${eps[k] ?? ApiConfig.defaultEndpoints[k]}',
                    decoration: InputDecoration(labelText: '${_labels[k] ?? k}  ($k)'),
                    onChanged: (v) => edit(() => eps[k] = v.trim()),
                  ),
                ),
            ]),
          ),
          SectionCard(
            title: 'Otomatik çeviri',
            icon: Icons.translate_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sohbet ve mesajları otomatik çevir'),
                subtitle: const Text('Her oyuncu profilinden kendi dilini seçer; sunucu çeviriyi ekler.'),
                value: s['translateEnabled'] == true,
                onChanged: (v) => edit(() => s['translateEnabled'] = v),
              ),
              TextFormField(
                initialValue: '${s['translateUrl'] ?? ''}',
                decoration: const InputDecoration(
                    labelText: 'Çeviri servisi adresi (LibreTranslate uyumlu)', hintText: 'https://ceviri.alanadin.com/translate'),
                onChanged: (v) => edit(() => s['translateUrl'] = v.trim()),
              ),
              const SizedBox(height: 10),
              TextFormField(
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'API anahtarı',
                  hintText: s['translateApiKeySet'] == true ? '•••••• (kayıtlı — değiştirmek için yazın)' : 'İsteğe bağlı',
                ),
                onChanged: (v) => edit(() => s['translateApiKey'] = v),
              ),
              const SizedBox(height: 12),
              const Text('Diller', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final l in const ['tr', 'en', 'de', 'ar', 'ru', 'az', 'fr', 'es', 'nl'])
                  FilterChip(
                    label: Text(l),
                    selected: langs.contains(l),
                    onSelected: (v) => edit(() => s['languages'] = v ? [...langs, l] : langs.where((e) => e != l).toList()),
                  ),
              ]),
            ]),
          ),
        ],
      );
    });
  }
}
