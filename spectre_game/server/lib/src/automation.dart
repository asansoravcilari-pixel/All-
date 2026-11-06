/// Oyuncu otomasyonları — SPECTRE'nin kendi sunucusunda çalışan resmi oyun özellikleri.
///
/// Her otomasyon kilitlenebilir bir özelliktir (paketle açılır). Ayarlar oyuncu başına saklanır.
library;

/// Otomasyon özellikleri (anahtar → ad, açıklama).
const kAutomationFeatures = <String, (String, String)>{
  'kick': ('Tekme', 'Masadaki oyuncuyu coin karşılığı masadan çıkarma'),
  'autoKick': ('Oto Tekme', 'Tekme listesindeki oyuncu masana oturunca otomatik tekme'),
  'multiKick': ('Çoklu Tekme', 'Seçilen birden fazla oyuncuya tek seferde tekme'),
  'save': ('Save Koruması', 'Kendimi Koru ve koruma listesi (bu oyunculara tekme atılmaz)'),
  'autoKiss': ('Oto Öpücük', 'Sıra gelince otomatik kabul (herkese ya da listedekilere)'),
  'autoReject': ('Otomatik Red', 'Red listesindekilerle eşleşmeyi otomatik pas geç'),
  'luck': ('Şans', 'Şişenin seçtiğin oyunculara gelme ağırlığını artır (1–10)'),
  'autoSpin': ('Oto Çevir', 'Sıra sana gelince şişeyi otomatik çevir'),
  'autoGreet': ('Oto Mesaj', 'Masaya gelen oyuncuyu bir kez karşılama mesajı'),
  'autoEnter': ('Masa Girişi', 'Bağlanınca seçtiğin ya da en kalabalık masaya otomatik otur'),
  'autoSwap': ('Masa Değiştir', 'Masa boşalınca daha kalabalık masaya otomatik geç'),
};

/// Varsayılan olarak paketle açılan (kilitli) otomasyonlar. 'kick' herkese açıktır (coin ile).
const kAutomationLockedByDefault = {
  'autoKick', 'multiKick', 'save', 'autoKiss', 'autoReject', 'luck', 'autoSpin', 'autoGreet', 'autoEnter', 'autoSwap'
};

List<String> _ids(Object? v) =>
    v is List ? [for (final x in v) if (x is String && x.isNotEmpty && x.length <= 40) x].take(200).toList() : <String>[];

bool _b(Object? v) => v == true;

int _i(Object? v, int def, int min, int max) => v is num ? v.toInt().clamp(min, max) : def;

String _s(Object? v, int max) {
  final s = v is String ? v.trim() : '';
  return s.length > max ? s.substring(0, max) : s;
}

/// Gelen ayarları güvenli biçime getirir (bilinmeyen alanlar atılır).
Map<String, dynamic> normalizeAutomation(Map<String, dynamic> j) {
  Map<String, dynamic> m(String k) => (j[k] as Map?)?.cast<String, dynamic>() ?? const {};
  final luck = <String, int>{};
  final lk = m('luck')['list'];
  if (lk is Map) {
    for (final e in lk.entries) {
      if (e.key is String && e.value is num) luck[e.key as String] = (e.value as num).toInt().clamp(1, 10);
      if (luck.length >= 200) break;
    }
  }
  return {
    'autoSpin': {'enabled': _b(m('autoSpin')['enabled'])},
    'autoKiss': {
      'enabled': _b(m('autoKiss')['enabled']),
      'mode': m('autoKiss')['mode'] == 'list' ? 'list' : 'all',
      'list': _ids(m('autoKiss')['list']),
    },
    'autoReject': {'enabled': _b(m('autoReject')['enabled']), 'list': _ids(m('autoReject')['list'])},
    'luck': {'enabled': _b(m('luck')['enabled']), 'list': luck},
    'save': {'selfProtect': _b(m('save')['selfProtect']), 'list': _ids(m('save')['list'])},
    'autoKick': {
      'enabled': _b(m('autoKick')['enabled']),
      'list': _ids(m('autoKick')['list']),
      'delayMs': _i(m('autoKick')['delayMs'], 800, 300, 10000),
    },
    'autoGreet': {
      'enabled': _b(m('autoGreet')['enabled']),
      'text': _s(m('autoGreet')['text'], 120).isEmpty ? 'Hoş geldin {ad}!' : _s(m('autoGreet')['text'], 120),
    },
    'autoEnter': {'enabled': _b(m('autoEnter')['enabled']), 'roomId': _s(m('autoEnter')['roomId'], 40)},
    'autoSwap': {'enabled': _b(m('autoSwap')['enabled']), 'minPlayers': _i(m('autoSwap')['minPlayers'], 4, 2, 12)},
  };
}

/// Ayarın açık olup olmadığı (alt alan 'enabled').
bool autoOn(Map<String, dynamic> auto, String key) => (auto[key] as Map?)?['enabled'] == true;

List<String> autoList(Map<String, dynamic> auto, String key) => _ids((auto[key] as Map?)?['list']);
