# SPECTRE → Flutter (WebAssembly) Geçiş Planı

## Temel karar

SPECTRE, başka bir oyunun sunucusuna, hesaplarına ya da dosyalarına bağlanmayan
**kendi oyunumuzdur**. Masa, şişe, efektler ve simgeler bu projede çizildi.
Oyuncular SPECTRE hesabıyla SPECTRE sunucusunda oynar. v39'daki üçüncü taraf
oyuna yönelik "bağlantı motoru / otomasyon motoru / oyun hesabı bağlama"
bölümleri taşınmaz.

## Korunan SPECTRE kimliği

| Öğe | v39 | Flutter |
|---|---|---|
| Electric-blue palet | `v38/electric-blue-v38.css` | `lib/ui/theme.dart` |
| Manrope yazı tipi (OFL) | `v38/manrope-variable-v38.ttf` | `assets/fonts/Manrope-*.ttf` |
| Cam yüzeyler | `spectre-modern.css` | `GlassPanel`, `PressButton` |
| 12 koltuk kare düzen (4 üst, 2+2 yan, 4 alt) + ortada şişe | `spectre-masa.html` (`.seat[data-pos]`) | `TableStage`, `kSeatOrigins` |
| Mobil masa yapısı: üst çubuk · araç düğmeleri · masa · sohbet · mesaj satırı · bağlantı | `spectre-masa.html` | `TableScreen` |
| Masa adları `Masa 1`–`Masa 4` | `baglantilar.json` | sunucu ilk açılış |
| Masaüstünde çok sütun | `spectre-modern.css` (≥1100 px) | `TableScreen` (≥1200 px üç, ≥900 px iki sütun) |

## Admin bölümleri eşlemesi

| v39 sekmesi | Yeni yer | Durum |
|---|---|---|
| Marka & Tema, Logolar & Metinler | Marka & Oyun | ✅ ad, slogan · ⏳ logo yükleme |
| Masa Kontrolleri | Marka & Oyun → Masa kuralları | ✅ süreler, sohbet, hediye, koltuk koruma |
| Özellikler, Paketler | Market | ✅ |
| Siparişler, Ödeme | Siparişler & Ödeme | ✅ onay/iade/iptal, Havale/EFT bilgisi · ⏳ PayTR/Shopier callback |
| Müşteriler | Oyuncular | ✅ |
| Politika & Bakım | Sistem & Güvenlik | ✅ |
| Yedek & JSON | Marka & Oyun → Yedek | ✅ dışa aktarma · ⏳ içe aktarma |
| Giriş & Kayıt | Oyuncu girişi + Sistem | ✅ kullanıcı adı/şifre, misafir, kayıt aç/kapa · ⏳ e-posta doğrulama, Google |
| Mail, Canlı Destek, Bildirimler, Tanıtım sitesi | — | ⏳ Faz 3 |
| Otomasyon / Bağlantı Motoru, çoklu oyun hesabı | — | ❌ taşınmaz |

## Fazlar

### Faz 1 — Tamamlandı
Flutter projesi, WebAssembly derlemesi, masa/lobi/market arayüzü, yönetim merkezi.

### Faz 2 — Tamamlandı (bu teslim)
- `packages/spectre_core`: sunucu ve uygulamanın ortak oyun kuralları + protokol.
- `server/`: Dart oyun sunucusu. Kayıt/giriş (PBKDF2), oturumlar, masalar,
  `room` / `roomPlayer` / `user` uçları, WebSocket `room<roomId>` kanalı,
  `seat.updated` / `seat.vacated`, sunucu yetkili tur zamanlayıcısı,
  hediye ve coin defteri, siparişler, yönetici hesapları, denetim kaydı,
  JSON dosyada kalıcı veri, Flutter web dosyalarını COOP/COEP başlıklarıyla sunma.
- Uygulamadaki benzetim (botlar, örnek oyuncu/sipariş) tamamen kaldırıldı.
- Yönetici girişi kullanıcı adı + şifre (sunucuda doğrulanır).
- Masaüstü üç sütunlu masa ekranı.

### Faz 3 — Sıradaki
- PayTR / Shopier ödeme bildirimi (callback) doğrulaması
- E-posta doğrulama ve şifre sıfırlama (v39 `mailer.py` mantığı), Google girişi
- Avatar/fotoğraf yükleme, logo yükleme
- Canlı destek, bildirim merkezi, tanıtım sitesi
- Veri büyüyünce JSON dosyadan SQLite/PostgreSQL'e geçiş (aynı `Store` arayüzü)

### Faz 4
Android/iOS derlemeleri (aynı kod), gerçek cihaz testleri, push bildirimleri.

## WebAssembly

- `flutter build web --wasm --release` → WASM + JS yedeği.
- Sunucu `Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy`
  başlıklarını kendisi gönderir (çok iş parçacıklı Skwasm için).
- Motor dosyaları dış CDN yerine kendi sunucudan yüklenir (`web/flutter_bootstrap.js`).

## Bilinen sınırlar

- Kartlı ödeme otomatik onaylanmaz; siparişler yönetici onayına düşer.
- Tek sunucu süreci için tasarlandı (yatay ölçekleme yok).
- Gerçek telefonlarda test edilmedi; tarayıcıda 390×844 ve 1440×860 denendi.
