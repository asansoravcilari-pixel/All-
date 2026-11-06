# SPECTRE Sunucu API'si

Tüm uçlar JSON döner. Oyuncu uçları `Authorization: Bearer <token>` ister
(token `/api/v1/auth/*` yanıtından gelir). Hata biçimi: `{"error": "mesaj"}`.

## Masa ve koltuk durumu

| İstek | Yanıt |
|---|---|
| `GET /room/api/v1/room` | `{"items": [RoomSummary]}` — açık masalar |
| `GET /room/api/v1/room/{roomId}` | `RoomSummary` |
| `GET /room/api/v1/roomPlayer?roomId=&userId=&limit=12&status=active` | `{"roomId", "items": [RoomPlayer]}` |
| `GET /user/api/v1/user/{userId}` | `{"id","name","avatarUrl","level","vip","hearts","isOnline","roomId"}` |

**RoomSummary:** `id`, `name`, `gameType` (`"bottle"`), `capacity` (12),
`inGamePlayers` (oturan ve bağlı), `countInGamePlayers` (toplam oturan),
`theme`, `locked`, `closed`. Doluluk = `countInGamePlayers / capacity`.

**RoomPlayer:** `index`/`slot` (0–11), `userId`/`playerId`, `name`, `avatarUrl`,
`isPlaying` (bağlantı açık mı), `leaveAt` (null = hâlâ masada).
`status=active` dışında son 30 dakikada kalkanlar da `leaveAt` dolu ve `index: -1` ile gelir.

Bağlantısı kopan oyuncunun koltuğu `disconnectGraceSec` (varsayılan 45 sn) korunur;
bu sürede `isPlaying: false`, sonra koltuk boşalır.

## WebSocket — `/ws?token=<token>`

İstemci → sunucu: `{"op": ...}`

| op | alanlar |
|---|---|
| `subscribe` / `unsubscribe` | `channel`: `room<roomId>` |
| `join` | `roomId`, isteğe bağlı `seat` (0–11) — oturur ve kanala abone olur |
| `leave` | — |
| `spin` | — (sıra sendeyse) |
| `decide` | `accept`: true/false |
| `chat` | `text` |
| `react` | `emoji` |
| `gift` | `toSeat`, `giftId` |
| `ping` | — |

Sunucu → istemci: `{"channel": "room<roomId>" | null, "event": ..., "data": {...}}`

| event | data |
|---|---|
| `hello` | `me`, `roomId` (bağlanınca) |
| `room.snapshot` | `room`, `seats[12]`, `round`, `chat` (durum değişince) |
| `seat.updated` | `index`, `playerId`, `name`, `avatarUrl`, `color`, `level`, `vip`, `hearts` |
| `seat.vacated` | `index`, `playerId` |
| `chat.message` | `userId`, `name`, `text`, `system`, `at` |
| `gift.sent` | `fromSeat`, `toSeat`, `gift` |
| `reaction` | `seat`, `emoji` |
| `match` | `a`, `b`, `success` |
| `notice` | `text`, `kind` |
| `me.updated` | oyuncunun güncel bakiyesi/durumu (kanalsız, yalnız kendisine) |
| `error` | `message` |

`round`: `phase` (`idle|spinning|deciding|result`), `roundNo`, `spinnerSeat`,
`targetSeat`, `fromAngle`, `bottleAngle`, `phaseElapsedMs`, `phaseTotalMs`,
`spinnerAccepted`, `targetAccepted`, `active`.
İstemci saat farkından etkilenmemek için `phaseElapsedMs` ile kendi saatinde senkronlanır.

## Hesap

`POST /api/v1/auth/register {username, password, displayName?}` ·
`POST /api/v1/auth/login {username, password}` · `POST /api/v1/auth/guest` ·
`POST /api/v1/auth/logout` · `GET|PATCH /api/v1/me` · `POST /api/v1/me/daily` ·
`GET /api/v1/config` (oturumsuz) · `GET /api/v1/gifts` · `GET /api/v1/market/packages` ·
`GET|POST /api/v1/orders {packageId, provider}`

Şifreler PBKDF2-HMAC-SHA256 (60.000 tur, tuzlu) ile saklanır. Aynı IP'den
10 dakikada 8 hatalı girişten sonra giriş geçici olarak kilitlenir.

## Yönetim — `/admin/api/v1` (ayrı yönetici oturumu)

`POST /login {username, password}` · `POST /logout` · `GET /me` · `POST /password {current, next}` ·
`GET|POST /admins` (yalnız `owner` ekleyebilir) · `GET /dashboard` · `POST /broadcast {text}` ·
`GET /users?q=&status=&role=&online=1&sort=` · `GET /users/{id}` ·
`POST /users/{id}/action {action: coins|status|role|warn|note|kick|rename|resetPassword, ...}` ·
`GET|POST /rooms` · `POST /rooms/{id}/action {action: lock|unlock|close|open|rename|theme|broadcast|delete}` ·
`GET /economy?days=` · `GET|POST /packages` · `GET|POST /gifts` ·
`GET /orders?status=&q=` · `POST /orders/{id}/action {action: approve|refund|cancel}` ·
`GET|PUT /settings {settings?, rules?}` · `GET /security` · `GET /export`

Her yönetim işlemi denetim kaydına (`/security` → `audit`) yazılır.
