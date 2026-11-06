# SPECTRE (Flutter WebAssembly + kendi sunucusu)

Özgün şişe çevirme sosyal oyunu, oyun sunucusu ve yönetim merkezi.
Tüm veriler (oyuncular, masalar, koltuklar, sohbet, hediyeler, siparişler)
**SPECTRE sunucusundan** gelir; uygulamada sahte/örnek veri yoktur.

```
spectre_game/
  lib/                     Flutter uygulaması (oyun + yönetim merkezi)
  packages/spectre_core/   Ortak oyun kuralları ve protokol (sunucu + uygulama)
  server/                  Oyun sunucusu (Dart, REST + WebSocket, JSON dosyada kalıcı veri)
  deploy/                  systemd ve NGINX örnekleri
  docs/                    Geçiş planı, API, ekran görüntüleri
```

## Hızlı başlangıç

```bash
cd spectre_game
flutter pub get
flutter build web --wasm --release                     # → build/web

cd server
dart pub get
SPECTRE_ADMIN_USER=admin SPECTRE_ADMIN_PASSWORD='en-az-8-karakter' \
  dart run bin/server.dart --port 8090 --data ./data --web ../build/web
```

Tarayıcıda `http://localhost:8090` açın.

1. Menü → **Yönetim merkezi** → kullanıcı adı + şifre ile giriş.
2. **Canlı Masalar → Masa aç** ile masaları oluşturun.
3. **Market** bölümünden hediye kataloğunu ve coin paketlerini ekleyin.
4. Oyuncular **Kayıt ol** (kullanıcı adı + şifre) ya da misafir girişiyle oynar.

`SPECTRE_ADMIN_PASSWORD` verilmezse ilk açılışta rastgele bir şifre üretilir ve
`data/admin-ilk-sifre.txt` dosyasına yazılır.

## Testler

```bash
cd packages/spectre_core && dart test     # oyun kuralları (7)
cd server && dart test                    # gerçek HTTP + WebSocket uçtan uca (5)
flutter test                              # istemci masa durumu (4)
```

## Neler var

- **Masa:** 12 koltuk, vektörel şişe, yavaşlayarak duran dönüş, hedef ışını,
  süre halkası, kabul/pas, sohbet balonları, uçan hediye, tepkiler, eşleşme
  efekti, bağlantısı kopan oyuncu soluk görünür.
  Masaüstü üç sütun (oyuncu listesi | masa | sohbet), tablet iki sütun,
  telefon tek sütun + açılır sohbet.
- **Sunucu yetkili:** Tur zamanlayıcısı, hedef seçimi, coin düşümü sunucuda.
  Hız sınırları, yasaklı kelime, IP engeli, hatalı giriş kilidi.
- **Yönetim merkezi:** Kontrol Merkezi, Oyuncular (coin, sustur, masadan çıkar,
  askıya al, yasakla, rol, uyarı, not, ad/şifre sıfırlama), Canlı Masalar,
  Ekonomi & Finans, Market, Siparişler & Ödeme, Sistem & Güvenlik
  (yöneticiler, şifre değiştirme, denetim kaydı), Marka & Oyun.

API ayrıntıları: [`docs/API.md`](docs/API.md) · Geçiş planı: [`docs/GECIS_PLANI.md`](docs/GECIS_PLANI.md)

Yazı tipi: Manrope, SIL Open Font License 1.1 (`assets/fonts/OFL.txt`).

## Ekran görüntüleri (gerçek sunucuyla, iki oyuncu)

| Masa (masaüstü, 3 sütun) | Masa (telefon) |
|---|---|
| ![](docs/ekran/masa-masaustu.png) | ![](docs/ekran/masa-telefon.png) |

| Kontrol Merkezi | Canlı Masalar |
|---|---|
| ![](docs/ekran/admin-kontrol-merkezi.png) | ![](docs/ekran/admin-canli-masalar.png) |
