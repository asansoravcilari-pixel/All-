# SPECTRE (Flutter / WebAssembly)

Özgün şişe çevirme sosyal oyunu ve yönetim merkezi.

## Çalıştırma

```bash
cd spectre_game
flutter pub get
flutter run -d chrome                              # geliştirme
flutter build web --wasm --release                 # WebAssembly üretim derlemesi → build/web
flutter build web --wasm --release --dart-define=ADMIN_PIN=1234
flutter test                                       # otomatik testler
```

Gereksinim: Flutter 3.24+ (Dart 3.5+).

## Neler var

- **Masa:** 12 koltuk, vektörel şişe ve zemin, yavaşlayarak duran dönüş,
  hedef ışını, süre halkası, kabul/pas kararı, sohbet balonları, uçan
  hediyeler, tepkiler, eşleşme efekti, bildirim kartları, oyuncu kartı.
- **Lobi:** canlı masalar, hızlı oyna, günlük ödül, market, hafif mod.
- **Yönetim merkezi** (menü → Yönetim merkezi, varsayılan PIN `0000`):
  Kontrol Merkezi, Oyuncular, Canlı Masalar, Ekonomi & Finans, Market,
  Siparişler & Ödeme, Sistem & Güvenlik, Marka & Oyun.

Şu an veriler tarayıcı içinde botlarla çalışan bir benzetimdir.
Ayrıntılı geçiş planı ve sonraki adımlar: [`docs/GECIS_PLANI.md`](docs/GECIS_PLANI.md).

Yazı tipi: Manrope, SIL Open Font License 1.1 (`assets/fonts/OFL.txt`).

## Ekran görüntüleri

| Masa (telefon) | Masa (masaüstü) |
|---|---|
| ![](docs/ekran/masa-telefon.png) | ![](docs/ekran/masa-masaustu.png) |

| Kontrol Merkezi | Canlı Masalar |
|---|---|
| ![](docs/ekran/admin-kontrol-merkezi.png) | ![](docs/ekran/admin-canli-masalar.png) |
