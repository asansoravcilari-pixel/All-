# SPECTRE → Flutter (WebAssembly) Geçiş Planı

Bu belge, SPECTRE'nin HTML/JS sürümünden (v39) Flutter Web + WebAssembly
sürümüne **tasarım kimliği ve işlevler kaybedilmeden** nasıl geçileceğini anlatır.

## 0. Temel karar: Özgün oyun

Yeni sürüm, başka bir oyunun sunucusuna, hesaplarına ya da dosyalarına
bağlanmayan **kendi SPECTRE oyunumuzdur**:

- Masa, şişe, efektler ve hediye simgeleri bu projede sıfırdan çizildi
  (vektör `CustomPainter` + sistem emojileri). Başka bir oyundan alınmış
  görsel, Spine dosyası ya da ikon kullanılmaz.
- Oyuncular SPECTRE hesabıyla SPECTRE sunucusunda oynar.
- v39'daki üçüncü taraf oyuna yönelik "otomasyon / köprü / hesap bağlama"
  bölümleri taşınmaz.

## 1. Korunan SPECTRE kimliği

| Öğe | v39 kaynağı | Flutter karşılığı |
|---|---|---|
| Electric-blue palet (`--sp-accent #65c5ff` vb.) | `v38/electric-blue-v38.css` | `lib/ui/theme.dart` → `SpectreColors` |
| Manrope yazı tipi (OFL) | `v38/manrope-variable-v38.ttf` | `assets/fonts/Manrope-*.ttf` (400–800 statik ağırlıklar) |
| Cam yüzeyler, yumuşak gölgeler | `spectre-modern.css`, `platinum-materials-v38.css` | `GlassPanel`, `PressButton` |
| 12 koltuklu masa + ortada şişe | `spectre-masa.html` | `TableStage` |
| Masa üstü üç sütun / telefonda tek sütun | `spectre-modern.css` (≥1100 px) | `TableScreen` (≥1000 px'te sağda sohbet) |
| Admin bölümleri | `admin.html`, `admin-ext*.js` | `lib/admin/*` (aşağıdaki eşleme) |

## 2. Admin bölümleri eşlemesi

| v39 sekmesi | Yeni yer | Durum |
|---|---|---|
| Marka & Tema, Logolar & Metinler | Marka & Oyun → Marka | ✅ ad + slogan; logo yükleme sunucu ile gelecek |
| Masa Kontrolleri, Oyuncu Düğmeleri | Marka & Oyun → Masa kuralları | ✅ süreler, sohbet, hediye, hafif mod |
| Özellikler, Paketler | Market | ✅ paket ekle/düzenle/pasifleştir, hediye kataloğu |
| Siparişler, Ödeme | Siparişler & Ödeme | ✅ onay, iade, iptal, PayTR/Shopier/manuel anahtarları |
| Müşteriler (Yönet) | Oyuncular | ✅ arama/filtre, coin düzeltme, sustur, masadan çıkar, askıya al, yasakla, rol, uyarı, iç not, coin geçmişi |
| Politika & Bakım | Sistem & Güvenlik | ✅ bakım modu, kayıt, misafir girişi, 2FA zorunluluğu |
| Yedek & JSON | Marka & Oyun → Yedek & JSON | ✅ dışa aktarma (içe aktarma sunucu ile) |
| PWA & Performans | Flutter web manifest + hafif mod | ✅ temel; ikon seti güncellenecek |
| Mail, Giriş & Kayıt, Canlı Destek, Bildirimler, Tanıtım sitesi | — | ⏳ Faz 3 (sunucu gerektiriyor) |
| Otomasyon / Efekt / Bağlantı Motoru | — | ❌ taşınmaz (üçüncü taraf oyuna yönelikti) |

**Yeni bölümler:** Kontrol Merkezi (canlı özet + gelir grafiği + doluluk),
Canlı Masalar (anlık izleme, duyuru, kilitle, kapat, oyuncu detayı),
Ekonomi & Finans (brüt/net gelir, iade, ARPPU, dönüşüm, sağlayıcı ve paket
dağılımı, coin defteri, en çok harcayanlar), güvenlik olayları ve tam denetim kaydı.

## 3. Mimari

```
lib/
  data/
    models.dart       Oyuncu, koltuk, tur, hediye, sipariş, defter, denetim
    game_table.dart   Masa kuralları (saf mantık, zaman dışarıdan → test edilebilir)
    backend.dart      Tek veri kaynağı (şimdilik istemci içi benzetim)
  game/               Lobi, masa ekranı, sahne, efekt katmanı, market
  admin/              Yönetim merkezi sayfaları
  ui/                 Tema ve ortak bileşenler
```

`SpectreBackend` şu an tarayıcı içinde botlarla çalışan bir **benzetimdir**
(canlı masalar, sohbet, hediye, sipariş akışı). Arayüz yalnızca bu sınıfın
genel API'sini kullanır; gerçek sunucuya geçerken arayüz değişmez, sadece bu
katman WebSocket istemcisine dönüştürülür.

## 4. Fazlar

### Faz 1 — Tamamlandı (bu teslim)
- Flutter projesi, WebAssembly derlemesi (`flutter build web --wasm`)
- Masa: vektörel zemin ve şişe, gerçekçi yavaşlayan dönüş, hedef ışını,
  süre halkası, karar rozetleri, sohbet balonları, uçan hediye, tepki,
  eşleşme patlaması, giriş dalgası, bildirim kartları
- Lobi, hızlı oyna, günlük ödül, market (benzetim ödeme)
- Yönetim merkezi (8 bölüm), PIN kapısı
- 13 otomatik test (oyun kuralları, ekonomi, sipariş/iade, yasak, bakım, widget)

### Faz 2 — Sunucu (önerilen: mevcut `control.py` üzerine)
- Hesap: kayıt / giriş / e-posta doğrulama / şifre sıfırlama (v39 `mailer.py` yeniden kullanılır)
- Gerçek zamanlı masa: WebSocket; tur zamanlayıcısı **sunucuda** (hile önleme)
- Coin defteri ve siparişler veritabanında (SQLite → PostgreSQL)
- PayTR bildirim (callback) doğrulaması sunucuda; anahtarlar ortam değişkeninde
- Admin yetkisi sunucuda (rol tabanlı), istemci PIN'i kaldırılır

### Faz 3 — Kalan v39 özellikleri
- Mail ayarları, canlı destek (v39 `support.py`), bildirim merkezi, tanıtım sitesi
- Logo / arka plan yükleme, metin ve etiket yönetimi
- Yedekten geri yükleme

### Faz 4 — Mağaza ve cihazlar
- Android/iOS derlemeleri (aynı kod), gerçek cihaz testleri
- Push bildirimleri

## 5. WebAssembly notları

- Derleme: `flutter build web --wasm --release` → `build/web` (WASM + JS yedeği).
  Tarayıcı WasmGC desteklemiyorsa otomatik olarak JS sürümü yüklenir.
- En iyi performans (çok iş parçacıklı Skwasm) için sunucu şu başlıkları göndermeli:
  ```
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp
  ```
  NGINX örneği:
  ```nginx
  location / {
      root /var/www/spectre_game;
      add_header Cross-Origin-Opener-Policy same-origin always;
      add_header Cross-Origin-Embedder-Policy require-corp always;
      try_files $uri $uri/ /index.html;
  }
  ```
- Motor dosyaları (`canvaskit/`) dış CDN yerine kendi sunucumuzdan yüklenir
  (`web/flutter_bootstrap.js`).
- Kod `dart:html` / `dart:io` kullanmaz; WASM ile uyumludur.

## 6. Bilinen sınırlar

- Veriler kalıcı değildir (sayfa yenilenince benzetim sıfırlanır) — Faz 2.
- Ödeme akışı benzetimdir; gerçek PayTR/Shopier entegrasyonu sunucu ister.
- Admin PIN'i (`--dart-define=ADMIN_PIN=...`, varsayılan `0000`) yalnız
  önizleme içindir; gerçek güvenlik değildir.
- Gerçek telefonlarda test edilmedi; tarayıcıda 390×844 ve 1366×820 boyutlarında denendi.
- Emoji görünümü cihazın emoji yazı tipine bağlıdır.
