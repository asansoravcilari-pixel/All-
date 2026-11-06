import 'dart:convert';
import 'dart:io';

import 'support.dart';

/// Kalıcı kayıtlar. Tümü tek JSON dosyasında tutulur (küçük/orta ölçek için yeterli;
/// büyüyünce aynı arayüzle veritabanına taşınabilir).

class UserRec {
  UserRec({
    required this.id,
    required this.username,
    required this.displayName,
    required this.passwordHash,
    required this.createdAt,
    this.role = 'player',
    this.status = 'active',
    this.coins = 0,
    this.level = 1,
    this.hearts = 0,
    this.color = 0xFF65C5FF,
    this.guest = false,
    this.totalSpent = 0,
    this.giftsSent = 0,
    this.giftsReceived = 0,
    this.spins = 0,
    this.email = '',
    this.avatarUrl = '',
    this.lastSeen,
    this.lastDaily,
    this.lang = 'tr',
    this.emailVerified = false,
    List<String>? notes,
    List<String>? warnings,
    Map<String, DateTime>? entitlements,
    Map<String, int>? inventory,
    Set<String>? expiryWarned,
    Map<String, dynamic>? auto,
  })  : auto = auto ?? {},
        notes = notes ?? [],
        warnings = warnings ?? [],
        entitlements = entitlements ?? {},
        inventory = inventory ?? {},
        expiryWarned = expiryWarned ?? {};

  final String id;
  String username;
  String displayName;
  String passwordHash;
  final DateTime createdAt;
  String role; // player | vip | moderator
  String status; // active | muted | suspended | banned
  int coins;
  int level;
  int hearts;
  int color;
  bool guest;
  int totalSpent; // kuruş
  int giftsSent;
  int giftsReceived;
  int spins;
  String email;
  String avatarUrl;
  DateTime? lastSeen;
  DateTime? lastDaily;
  String lang;
  bool emailVerified;
  final List<String> notes;
  final List<String> warnings;

  /// Özellik anahtarı → bitiş zamanı.
  final Map<String, DateTime> entitlements;

  /// Hediye kimliği → adet (paketle gelen hediyeler).
  final Map<String, int> inventory;

  /// Bitiş uyarısı gönderilmiş haklar (anahtar@bitiş).
  final Set<String> expiryWarned;

  /// Otomasyon ayarları (bkz. automation.dart).
  Map<String, dynamic> auto;
  DateTime? lastKickAt;
  final List<DateTime> loginFailures = [];
  DateTime? lastFailMail;

  bool has(String feature) {
    final e = entitlements[feature];
    return e != null && DateTime.now().isBefore(e);
  }

  bool get isVip => role == 'vip';

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'displayName': displayName,
        'passwordHash': passwordHash,
        'createdAt': createdAt.toIso8601String(),
        'role': role,
        'status': status,
        'coins': coins,
        'level': level,
        'hearts': hearts,
        'color': color,
        'guest': guest,
        'totalSpent': totalSpent,
        'giftsSent': giftsSent,
        'giftsReceived': giftsReceived,
        'spins': spins,
        'email': email,
        'avatarUrl': avatarUrl,
        'lastSeen': lastSeen?.toIso8601String(),
        'lastDaily': lastDaily?.toIso8601String(),
        'lang': lang,
        'emailVerified': emailVerified,
        'entitlements': {for (final e in entitlements.entries) e.key: e.value.toIso8601String()},
        'inventory': inventory,
        'expiryWarned': expiryWarned.toList(),
        'auto': auto,
        'notes': notes,
        'warnings': warnings,
      };

  factory UserRec.fromJson(Map<String, dynamic> j) => UserRec(
        id: j['id'] as String,
        username: j['username'] as String,
        displayName: j['displayName'] as String? ?? j['username'] as String,
        passwordHash: j['passwordHash'] as String? ?? '',
        createdAt: DateTime.parse(j['createdAt'] as String),
        role: j['role'] as String? ?? 'player',
        status: j['status'] as String? ?? 'active',
        coins: j['coins'] as int? ?? 0,
        level: j['level'] as int? ?? 1,
        hearts: j['hearts'] as int? ?? 0,
        color: j['color'] as int? ?? 0xFF65C5FF,
        guest: j['guest'] as bool? ?? false,
        totalSpent: j['totalSpent'] as int? ?? 0,
        giftsSent: j['giftsSent'] as int? ?? 0,
        giftsReceived: j['giftsReceived'] as int? ?? 0,
        spins: j['spins'] as int? ?? 0,
        email: j['email'] as String? ?? '',
        avatarUrl: j['avatarUrl'] as String? ?? '',
        lastSeen: j['lastSeen'] == null ? null : DateTime.tryParse(j['lastSeen'] as String),
        lastDaily: j['lastDaily'] == null ? null : DateTime.tryParse(j['lastDaily'] as String),
        lang: j['lang'] as String? ?? 'tr',
        emailVerified: j['emailVerified'] as bool? ?? false,
        entitlements: {
          for (final e in ((j['entitlements'] as Map?) ?? const {}).entries)
            if (DateTime.tryParse('${e.value}') != null) '${e.key}': DateTime.parse('${e.value}'),
        },
        inventory: {for (final e in ((j['inventory'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()},
        expiryWarned: {for (final x in (j['expiryWarned'] as List? ?? const [])) '$x'},
        auto: (j['auto'] as Map?)?.cast<String, dynamic>(),
        notes: (j['notes'] as List?)?.cast<String>(),
        warnings: (j['warnings'] as List?)?.cast<String>(),
      );
}

class AdminRec {
  AdminRec({required this.username, required this.passwordHash, this.role = 'admin', DateTime? createdAt, this.lastLogin})
      : createdAt = createdAt ?? DateTime.now();
  final String username;
  String passwordHash;
  String role; // owner | admin | moderator
  final DateTime createdAt;
  DateTime? lastLogin;

  Map<String, dynamic> toJson() => {
        'username': username,
        'passwordHash': passwordHash,
        'role': role,
        'createdAt': createdAt.toIso8601String(),
        'lastLogin': lastLogin?.toIso8601String(),
      };

  factory AdminRec.fromJson(Map<String, dynamic> j) => AdminRec(
        username: j['username'] as String,
        passwordHash: j['passwordHash'] as String,
        role: j['role'] as String? ?? 'admin',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
        lastLogin: j['lastLogin'] == null ? null : DateTime.tryParse(j['lastLogin'] as String),
      );
}

class RoomRec {
  RoomRec({required this.id, required this.name, this.theme = 0, this.locked = false, this.closed = false});
  final String id;
  String name;
  int theme;
  bool locked;
  bool closed;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'theme': theme, 'locked': locked, 'closed': closed};
  factory RoomRec.fromJson(Map<String, dynamic> j) => RoomRec(
        id: j['id'] as String,
        name: j['name'] as String,
        theme: j['theme'] as int? ?? 0,
        locked: j['locked'] as bool? ?? false,
        closed: j['closed'] as bool? ?? false,
      );
}

class PackageRec {
  PackageRec({
    required this.id,
    required this.name,
    required this.coins,
    required this.priceKurus,
    this.bonusPercent = 0,
    this.vipDays = 0,
    this.active = true,
    this.featured = false,
    this.kind = 'coins',
    this.periodDays = 0,
    this.description = '',
    List<String>? features,
    List<Map<String, dynamic>>? gifts,
  })  : features = features ?? [],
        gifts = gifts ?? [];
  final String id;
  String name;
  int coins;
  int priceKurus;
  int bonusPercent;
  int vipDays;
  bool active;
  bool featured;

  /// coins | subscription | feature
  String kind;

  /// Hakların süresi (gün). 0 = süresiz.
  int periodDays;
  String description;

  /// Pakete dahil özellik anahtarları.
  List<String> features;

  /// Pakete dahil hediyeler: [{giftId, qty}]
  List<Map<String, dynamic>> gifts;

  int get totalCoins => coins + (coins * bonusPercent / 100).round();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'coins': coins,
        'priceKurus': priceKurus,
        'bonusPercent': bonusPercent,
        'vipDays': vipDays,
        'active': active,
        'featured': featured,
        'totalCoins': totalCoins,
        'kind': kind,
        'periodDays': periodDays,
        'description': description,
        'features': features,
        'gifts': gifts,
      };

  factory PackageRec.fromJson(Map<String, dynamic> j) => PackageRec(
        id: j['id'] as String,
        name: j['name'] as String,
        coins: j['coins'] as int? ?? 0,
        priceKurus: j['priceKurus'] as int? ?? 0,
        bonusPercent: j['bonusPercent'] as int? ?? 0,
        vipDays: j['vipDays'] as int? ?? 0,
        active: j['active'] as bool? ?? true,
        featured: j['featured'] as bool? ?? false,
        kind: j['kind'] as String? ?? 'coins',
        periodDays: j['periodDays'] as int? ?? 0,
        description: j['description'] as String? ?? '',
        features: [for (final f in (j['features'] as List? ?? const [])) '$f'],
        gifts: [for (final g in (j['gifts'] as List? ?? const [])) (g as Map).cast<String, dynamic>()],
      );
}

/// Satılabilir/kilitlenebilir özellik.
class FeatureRec {
  FeatureRec({required this.key, required this.name, this.description = '', this.locked = false, this.builtin = false});
  final String key;
  String name;
  String description;

  /// true: hakkı olmayan kullanıcı için özellik kilitlidir.
  bool locked;
  final bool builtin;

  Map<String, dynamic> toJson() => {'key': key, 'name': name, 'description': description, 'locked': locked, 'builtin': builtin};
  factory FeatureRec.fromJson(Map<String, dynamic> j) => FeatureRec(
        key: j['key'] as String,
        name: j['name'] as String? ?? j['key'] as String,
        description: j['description'] as String? ?? '',
        locked: j['locked'] as bool? ?? false,
        builtin: j['builtin'] as bool? ?? false,
      );
}

/// Uygulamada gerçekten kilitlenebilen hazır özellikler.
final kBuiltinFeatures = <FeatureRec>[
  FeatureRec(key: 'dm', name: 'Özel mesaj', description: 'Oyunculara özel mesaj gönderme', builtin: true),
  FeatureRec(key: 'groupGift', name: 'Toplu hediye', description: 'Masadaki herkese hediye', builtin: true),
  FeatureRec(key: 'translate', name: 'Otomatik çeviri', description: 'Sohbet ve mesajların çevirisi', builtin: true),
  FeatureRec(key: 'avatar', name: 'Profil fotoğrafı', description: 'Fotoğraf yükleme', builtin: true),
  FeatureRec(key: 'vipBadge', name: 'VIP rozeti', description: 'Masada taç ve VIP çerçeve', builtin: true),
];

/// E-posta doğrulama / şifre sıfırlama tek kullanımlık bağlantıları.
class TokenRec {
  TokenRec(this.token, this.userId, this.kind, this.expires);
  final String token;
  final String userId;
  final String kind; // verify | reset
  final DateTime expires;

  Map<String, dynamic> toJson() =>
      {'token': token, 'userId': userId, 'kind': kind, 'expires': expires.toIso8601String()};
  factory TokenRec.fromJson(Map<String, dynamic> j) =>
      TokenRec(j['token'] as String, j['userId'] as String, j['kind'] as String, DateTime.parse(j['expires'] as String));
}

class OrderRec {
  OrderRec({
    required this.id,
    required this.userId,
    required this.packageId,
    required this.packageName,
    required this.amountKurus,
    required this.coins,
    required this.provider,
    required this.createdAt,
    this.status = 'pending',
    this.updatedAt,
    this.note = '',
  });
  final String id;
  final String userId;
  final String packageId;
  final String packageName;
  final int amountKurus;
  final int coins;
  final String provider; // paytr | shopier | manual
  final DateTime createdAt;
  String status; // pending | paid | failed | refunded | cancelled
  DateTime? updatedAt;
  String note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'packageId': packageId,
        'packageName': packageName,
        'amountKurus': amountKurus,
        'coins': coins,
        'provider': provider,
        'createdAt': createdAt.toIso8601String(),
        'status': status,
        'updatedAt': updatedAt?.toIso8601String(),
        'note': note,
      };

  factory OrderRec.fromJson(Map<String, dynamic> j) => OrderRec(
        id: j['id'] as String,
        userId: j['userId'] as String,
        packageId: j['packageId'] as String,
        packageName: j['packageName'] as String? ?? '',
        amountKurus: j['amountKurus'] as int,
        coins: j['coins'] as int? ?? 0,
        provider: j['provider'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        status: j['status'] as String? ?? 'pending',
        updatedAt: j['updatedAt'] == null ? null : DateTime.tryParse(j['updatedAt'] as String),
        note: j['note'] as String? ?? '',
      );
}

class LedgerRec {
  LedgerRec(this.userId, this.kind, this.delta, this.memo, {DateTime? at}) : at = at ?? DateTime.now();
  final String userId;
  final String kind; // purchase | gift | giftIncome | reward | adminAdjust | refund
  final int delta;
  final String memo;
  final DateTime at;

  Map<String, dynamic> toJson() =>
      {'userId': userId, 'kind': kind, 'delta': delta, 'memo': memo, 'at': at.toIso8601String()};
  factory LedgerRec.fromJson(Map<String, dynamic> j) => LedgerRec(
        j['userId'] as String,
        j['kind'] as String,
        j['delta'] as int,
        j['memo'] as String? ?? '',
        at: DateTime.parse(j['at'] as String),
      );
}

class LogRec {
  LogRec(this.level, this.actor, this.action, this.target, {DateTime? at}) : at = at ?? DateTime.now();
  final String level; // info | warn
  final String actor;
  final String action;
  final String target;
  final DateTime at;

  Map<String, dynamic> toJson() =>
      {'level': level, 'actor': actor, 'action': action, 'target': target, 'at': at.toIso8601String()};
  factory LogRec.fromJson(Map<String, dynamic> j) => LogRec(
        j['level'] as String? ?? 'info',
        j['actor'] as String? ?? '',
        j['action'] as String? ?? '',
        j['target'] as String? ?? '',
        at: DateTime.parse(j['at'] as String),
      );
}


class NoticeRec {
  NoticeRec({required this.id, required this.userId, required this.kind, required this.text, DateTime? at, this.read = false})
      : at = at ?? DateTime.now();
  final String id;
  final String userId;
  final String kind; // gift | match | order | admin | system
  final String text;
  final DateTime at;
  bool read;

  Map<String, dynamic> toJson() =>
      {'id': id, 'userId': userId, 'kind': kind, 'text': text, 'at': at.toIso8601String(), 'read': read};
  factory NoticeRec.fromJson(Map<String, dynamic> j) => NoticeRec(
        id: j['id'] as String,
        userId: j['userId'] as String,
        kind: j['kind'] as String? ?? 'system',
        text: j['text'] as String? ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? ''),
        read: j['read'] as bool? ?? false,
      );
}

class DmRec {
  DmRec({required this.id, required this.from, required this.to, required this.text, DateTime? at, this.read = false, Map<String, String>? translations})
      : at = at ?? DateTime.now(),
        translations = translations ?? {};
  final String id;
  final String from;
  final String to;
  final String text;
  final DateTime at;
  bool read;
  final Map<String, String> translations;

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'to': to,
        'text': text,
        'at': at.toIso8601String(),
        'read': read,
        if (translations.isNotEmpty) 'translations': translations,
      };
  factory DmRec.fromJson(Map<String, dynamic> j) => DmRec(
        id: j['id'] as String,
        from: j['from'] as String,
        to: j['to'] as String,
        text: j['text'] as String? ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? ''),
        read: j['read'] as bool? ?? false,
        translations: (j['translations'] as Map?)?.cast<String, String>(),
      );
}

/// Uygulamanın kullandığı uç nokta yolları (admin panelinden değiştirilebilir).
/// `{param}` biçimindeki parçalar yol parametresidir.
const Map<String, String> kDefaultEndpoints = {
  'authRegister': '/api/v1/auth/register',
  'authLogin': '/api/v1/auth/login',
  'authGuest': '/api/v1/auth/guest',
  'authLogout': '/api/v1/auth/logout',
  'me': '/api/v1/me',
  'meDaily': '/api/v1/me/daily',
  'meAvatar': '/api/v1/me/avatar',
  'roomList': '/room/api/v1/room',
  'roomDetail': '/room/api/v1/room/{roomId}',
  'roomPlayer': '/room/api/v1/roomPlayer',
  'user': '/user/api/v1/user/{userId}',
  'gifts': '/api/v1/gifts',
  'packages': '/api/v1/market/packages',
  'orders': '/api/v1/orders',
  'dmThreads': '/api/v1/dm',
  'dmThread': '/api/v1/dm/{userId}',
  'notifications': '/api/v1/notifications',
  'notificationsRead': '/api/v1/notifications/read',
  'authForgot': '/api/v1/auth/forgot',
  'authReset': '/api/v1/auth/reset',
  'payStart': '/api/v1/pay/paytr/start',
  'support': '/api/v1/support',
  'automation': '/api/v1/automation',
  'ws': '/ws',
};

/// Arayüz metinlerinin varsayılanları (admin panelinden değiştirilebilir).
const Map<String, String> kDefaultTexts = {
  'login.title': 'Giriş yap',
  'login.register': 'Kayıt ol',
  'login.guest': 'Misafir olarak devam et',
  'lobby.hello': 'Merhaba',
  'lobby.quickPlay': 'Hızlı oyna',
  'lobby.daily': 'Günlük ödül',
  'lobby.tables': 'Masalar',
  'lobby.empty': 'Henüz açık masa yok',
  'hud.round': 'Tur',
  'hud.hearts': 'Kalp',
  'hud.players': 'Oyuncu',
  'tools.tables': 'Aktif masa seçimi',
  'tools.bonus': 'Günlük bonus',
  'tools.market': 'Market',
  'tools.profile': 'Profil',
  'tools.notifications': 'Bildirimler',
  'tools.exit': 'Çıkış menüsü',
  'table.sit': 'Otur',
  'table.spin': 'ÇEVİR',
  'table.accept': 'Kabul',
  'table.reject': 'Pas',
  'table.yourTurn': 'Sıra sende',
  'table.waiting': 'İkinci oyuncu bekleniyor',
  'table.empty': 'Masa boş',
  'table.match': 'Eşleşme!',
  'table.pass': 'Pas geçildi',
  'chat.title': 'Masa Sohbeti',
  'chat.placeholder': 'Mesaj yaz',
  'chat.sitToWrite': 'Yazmak için masaya otur',
  'composer.react': 'Tepki',
  'composer.gift': 'Oyuncuya hediye',
  'composer.groupGift': 'Toplu hediye',
  'composer.messages': 'Mesaj kutusu',
  'link.online': 'Canlı bağlantı',
  'link.offline': 'Canlı oyun bağlantısı yok',
  'dm.title': 'Mesaj kutusu',
  'dm.empty': 'Henüz mesaj yok',
  'notifications.title': 'Bildirimler',
  'notifications.empty': 'Bildirim yok',
  'market.title': 'Market',
  'payment.success': 'Ödemen alındı. Onaylandığında haklar hesabına otomatik tanımlanır.',
  'payment.failed': 'Ödeme tamamlanamadı. Tekrar deneyebilirsin.',
  'login.success': 'Hoş geldin {ad}!',
  'login.failed': 'Kullanıcı adı veya şifre hatalı.',
  'auto.title': 'Otomasyon Merkezi',
  'auto.selectHint': 'Hedef seçmek için oyuncunun fotoğrafına 1,5 saniye basılı tut.',
};

/// Açılır pencerelerin üst/alt açıklama metinleri (admin panelinden).
const Map<String, String> kDefaultPopups = {
  'tables': 'Geçmek istediğin masayı seç.',
  'bonus': 'Her gün bir kez bonus coin alabilirsin.',
  'market': 'Paketler ödeme onaylandığında hesabına yüklenir.',
  'gift': 'Hediye seç ve gönder.',
  'groupGift': 'Seçtiğin hediye masadaki herkese gönderilir.',
  'profile': '',
  'exit': '',
  'dm': '',
  'notifications': '',
};

class Settings {
  bool maintenance = false;
  String maintenanceText = 'Kısa bir bakım yapıyoruz, birazdan döneceğiz.';
  bool registrationOpen = true;
  bool guestLogin = true;
  bool marketOpen = true;
  int maxMessagesPerMinute = 20;
  int maxGiftsPerMinute = 10;
  // Tekme ve otomasyon
  int kickCost = 20;
  int kickCooldownSec = 20;
  int kickBanMinutes = 5;
  int greetPerMinute = 3;
  int autoDelayMs = 900;
  // Oturum bildirimleri
  bool mailOnLogin = false;
  // Yeni üye ücretsiz deneme
  bool trialEnabled = true;
  int trialDays = 2;
  List<String> trialFeatures = [];
  bool mailOnLoginFail = true;
  int dailyRewardCoins = 50;
  int startingCoins = 200;
  List<String> blockedWords = [];
  List<String> blockedIps = [];
  bool paytrEnabled = false;
  bool paytrTestMode = true;
  String paytrMerchantId = '';
  bool shopierEnabled = false;
  bool manualPayment = true;
  String manualPaymentInfo = '';
  String brandName = 'SPECTRE';
  String tagline = 'Çevir · Tanış · Eşleş';
  // Görünüm
  String backgroundColor = '#050B14';
  String backgroundImageUrl = '';
  String logoUrl = '';
  String accentColor = '#65C5FF';
  Map<String, String> texts = {};
  Map<String, String> popups = {};
  // Bağlantı
  String apiBase = '';
  String wsUrl = '';
  Map<String, String> endpoints = {};
  // Otomatik çeviri (LibreTranslate uyumlu servis)
  bool translateEnabled = false;
  String translateUrl = '';
  String translateApiKey = '';
  // Sanal POS (PayTR) gizli bilgileri — dışarı verilmez
  String paytrMerchantKey = '';
  String paytrMerchantSalt = '';
  // Site adresi: mail bağlantıları ve ödeme dönüşleri için
  String publicBaseUrl = '';
  // Mail (SMTP)
  bool mailEnabled = false;
  String smtpHost = '';
  int smtpPort = 587;
  String smtpSecurity = 'starttls';
  String smtpUser = '';
  String smtpPassword = '';
  String mailFrom = '';
  String mailFromName = 'SPECTRE';
  bool requireEmail = false;
  Map<String, Map<String, String>> mailTemplates = {};
  // Destek robotu
  bool supportEnabled = true;
  String supportBotName = 'SPECTRE Asistan';
  String supportGreeting = 'Merhaba! Sana nasıl yardımcı olabilirim?';
  bool supportHumanForMembersOnly = true;
  int supportLockMinutes = 60;
  List<String> supportSafetyWords = List.of(kDefaultSafetyWords);
  // Animasyonlar
  Map<String, dynamic> animations = {};
  List<String> languages = ['tr', 'en', 'de', 'ar', 'ru', 'az'];

  Map<String, String> get effectiveEndpoints => {...kDefaultEndpoints, ...endpoints};
  Map<String, String> get effectiveTexts => {...kDefaultTexts, ...texts};
  Map<String, String> get effectivePopups => {...kDefaultPopups, ...popups};

  static const kDefaultAnimations = <String, dynamic>{
    'spinMs': 3400,
    'resultMs': 2200,
    'matchEmoji': '💞',
    'rejectEmoji': '💔',
    'burstCount': 16,
    'giftFlightMs': 1300,
    'reactions': '❤️ 😂 😮 👏 🔥 😍',
    'bottleWobble': true,
    'targetBeam': true,
    'floorGlow': true,
  };
  Map<String, dynamic> get effectiveAnimations => {...kDefaultAnimations, ...animations};

  Map<String, dynamic> toJson() => {
        'maintenance': maintenance,
        'maintenanceText': maintenanceText,
        'registrationOpen': registrationOpen,
        'guestLogin': guestLogin,
        'marketOpen': marketOpen,
        'maxMessagesPerMinute': maxMessagesPerMinute,
        'maxGiftsPerMinute': maxGiftsPerMinute,
        'dailyRewardCoins': dailyRewardCoins,
        'startingCoins': startingCoins,
        'blockedWords': blockedWords,
        'blockedIps': blockedIps,
        'paytrEnabled': paytrEnabled,
        'paytrTestMode': paytrTestMode,
        'paytrMerchantId': paytrMerchantId,
        'shopierEnabled': shopierEnabled,
        'manualPayment': manualPayment,
        'manualPaymentInfo': manualPaymentInfo,
        'brandName': brandName,
        'tagline': tagline,
        'backgroundColor': backgroundColor,
        'backgroundImageUrl': backgroundImageUrl,
        'logoUrl': logoUrl,
        'accentColor': accentColor,
        'texts': effectiveTexts,
        'popups': effectivePopups,
        'apiBase': apiBase,
        'wsUrl': wsUrl,
        'endpoints': effectiveEndpoints,
        'translateEnabled': translateEnabled,
        'translateUrl': translateUrl,
        // Anahtarın kendisi dışarı verilmez.
        'translateApiKeySet': translateApiKey.isNotEmpty,
        'languages': languages,
        'paytrKeySet': paytrMerchantKey.isNotEmpty && paytrMerchantSalt.isNotEmpty,
        'publicBaseUrl': publicBaseUrl,
        'mailEnabled': mailEnabled,
        'smtpHost': smtpHost,
        'smtpPort': smtpPort,
        'smtpSecurity': smtpSecurity,
        'smtpUser': smtpUser,
        'smtpPasswordSet': smtpPassword.isNotEmpty,
        'mailFrom': mailFrom,
        'mailFromName': mailFromName,
        'requireEmail': requireEmail,
        'supportEnabled': supportEnabled,
        'supportBotName': supportBotName,
        'supportGreeting': supportGreeting,
        'supportHumanForMembersOnly': supportHumanForMembersOnly,
        'supportLockMinutes': supportLockMinutes,
        'supportSafetyWords': supportSafetyWords,
        'animations': effectiveAnimations,
        'kickCost': kickCost,
        'kickCooldownSec': kickCooldownSec,
        'kickBanMinutes': kickBanMinutes,
        'greetPerMinute': greetPerMinute,
        'autoDelayMs': autoDelayMs,
        'mailOnLogin': mailOnLogin,
        'mailOnLoginFail': mailOnLoginFail,
        'trialEnabled': trialEnabled,
        'trialDays': trialDays,
        'trialFeatures': trialFeatures,
      };

  Map<String, dynamic> toStorageJson() => {
        ...toJson(),
        'texts': texts,
        'popups': popups,
        'endpoints': endpoints,
        'animations': animations,
        'translateApiKey': translateApiKey,
        'paytrMerchantKey': paytrMerchantKey,
        'paytrMerchantSalt': paytrMerchantSalt,
        'smtpPassword': smtpPassword,
        'mailTemplates': mailTemplates,
      };

  /// Yalnızca bilinen ve doğru türdeki alanları uygular.
  void apply(Map<String, dynamic> j) {
    bool? b(String k) => j[k] is bool ? j[k] as bool : null;
    int? i(String k, int min, int max) {
      final v = j[k];
      if (v is! num) return null;
      final n = v.toInt();
      return n < min || n > max ? null : n;
    }

    String? s(String k, int maxLen) {
      final v = j[k];
      if (v is! String) return null;
      return v.length > maxLen ? v.substring(0, maxLen) : v;
    }

    List<String>? l(String k) {
      final v = j[k];
      if (v is! List) return null;
      return v.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).take(500).toList();
    }

    maintenance = b('maintenance') ?? maintenance;
    maintenanceText = s('maintenanceText', 300) ?? maintenanceText;
    registrationOpen = b('registrationOpen') ?? registrationOpen;
    guestLogin = b('guestLogin') ?? guestLogin;
    marketOpen = b('marketOpen') ?? marketOpen;
    maxMessagesPerMinute = i('maxMessagesPerMinute', 1, 600) ?? maxMessagesPerMinute;
    maxGiftsPerMinute = i('maxGiftsPerMinute', 1, 600) ?? maxGiftsPerMinute;
    dailyRewardCoins = i('dailyRewardCoins', 0, 100000) ?? dailyRewardCoins;
    startingCoins = i('startingCoins', 0, 100000) ?? startingCoins;
    blockedWords = l('blockedWords') ?? blockedWords;
    blockedIps = l('blockedIps') ?? blockedIps;
    paytrEnabled = b('paytrEnabled') ?? paytrEnabled;
    paytrTestMode = b('paytrTestMode') ?? paytrTestMode;
    paytrMerchantId = s('paytrMerchantId', 64) ?? paytrMerchantId;
    shopierEnabled = b('shopierEnabled') ?? shopierEnabled;
    manualPayment = b('manualPayment') ?? manualPayment;
    manualPaymentInfo = s('manualPaymentInfo', 1000) ?? manualPaymentInfo;
    final bn = s('brandName', 40);
    if (bn != null && bn.trim().isNotEmpty) brandName = bn.trim();
    tagline = s('tagline', 120) ?? tagline;

    String? color(String k) {
      final v = s(k, 9);
      if (v == null) return null;
      return RegExp(r'^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$').hasMatch(v) ? v.toUpperCase() : null;
    }

    String? url(String k) {
      final v = s(k, 500);
      if (v == null) return null;
      if (v.isEmpty) return '';
      return RegExp(r'^(https?://|wss?://|/)[^\s<>"]*$').hasMatch(v) ? v : null;
    }

    Map<String, String>? strMap(String k, int maxLen, {bool Function(String key, String value)? valid}) {
      final v = j[k];
      if (v is! Map) return null;
      final out = <String, String>{};
      for (final e in v.entries) {
        if (e.key is! String || e.value is! String) continue;
        final key = (e.key as String).trim();
        var val = e.value as String;
        if (key.isEmpty || key.length > 64) continue;
        if (val.length > maxLen) val = val.substring(0, maxLen);
        if (valid != null && !valid(key, val)) continue;
        out[key] = val;
      }
      return out;
    }

    backgroundColor = color('backgroundColor') ?? backgroundColor;
    accentColor = color('accentColor') ?? accentColor;
    backgroundImageUrl = url('backgroundImageUrl') ?? backgroundImageUrl;
    logoUrl = url('logoUrl') ?? logoUrl;
    apiBase = url('apiBase') ?? apiBase;
    wsUrl = url('wsUrl') ?? wsUrl;
    translateUrl = url('translateUrl') ?? translateUrl;
    translateEnabled = b('translateEnabled') ?? translateEnabled;
    final key = s('translateApiKey', 200);
    if (key != null) translateApiKey = key;
    final langs = l('languages');
    if (langs != null) {
      languages = langs.where((e) => RegExp(r'^[a-z]{2,3}$').hasMatch(e)).take(30).toList();
    }
    final pk = s('paytrMerchantKey', 200);
    if (pk != null && pk.isNotEmpty) paytrMerchantKey = pk.trim();
    final ps = s('paytrMerchantSalt', 200);
    if (ps != null && ps.isNotEmpty) paytrMerchantSalt = ps.trim();
    publicBaseUrl = url('publicBaseUrl') ?? publicBaseUrl;
    mailEnabled = b('mailEnabled') ?? mailEnabled;
    smtpHost = s('smtpHost', 200)?.trim() ?? smtpHost;
    smtpPort = i('smtpPort', 1, 65535) ?? smtpPort;
    final sec = s('smtpSecurity', 10);
    if (sec != null && const {'ssl', 'starttls', 'none'}.contains(sec)) smtpSecurity = sec;
    smtpUser = s('smtpUser', 200)?.trim() ?? smtpUser;
    final sp = s('smtpPassword', 200);
    if (sp != null && sp.isNotEmpty) smtpPassword = sp;
    final mf = s('mailFrom', 200)?.trim();
    if (mf != null && (mf.isEmpty || mf.contains('@'))) mailFrom = mf;
    mailFromName = s('mailFromName', 80) ?? mailFromName;
    requireEmail = b('requireEmail') ?? requireEmail;
    final mt = j['mailTemplates'];
    if (mt is Map) {
      final out = <String, Map<String, String>>{};
      for (final e in mt.entries) {
        if (e.value is! Map) continue;
        final v = (e.value as Map);
        final subj = v['subject'], body = v['body'];
        if (subj is String && body is String && subj.length <= 300 && body.length <= 20000) {
          out['${e.key}'] = {'subject': subj, 'body': body};
        }
      }
      mailTemplates = out;
    }
    kickCost = i('kickCost', 0, 100000) ?? kickCost;
    kickCooldownSec = i('kickCooldownSec', 0, 3600) ?? kickCooldownSec;
    kickBanMinutes = i('kickBanMinutes', 0, 1440) ?? kickBanMinutes;
    greetPerMinute = i('greetPerMinute', 1, 60) ?? greetPerMinute;
    autoDelayMs = i('autoDelayMs', 200, 10000) ?? autoDelayMs;
    mailOnLogin = b('mailOnLogin') ?? mailOnLogin;
    trialEnabled = b('trialEnabled') ?? trialEnabled;
    trialDays = i('trialDays', 1, 365) ?? trialDays;
    trialFeatures = l('trialFeatures') ?? trialFeatures;
    mailOnLoginFail = b('mailOnLoginFail') ?? mailOnLoginFail;
    supportEnabled = b('supportEnabled') ?? supportEnabled;
    supportBotName = s('supportBotName', 60) ?? supportBotName;
    supportGreeting = s('supportGreeting', 500) ?? supportGreeting;
    supportHumanForMembersOnly = b('supportHumanForMembersOnly') ?? supportHumanForMembersOnly;
    supportLockMinutes = i('supportLockMinutes', 1, 100000) ?? supportLockMinutes;
    supportSafetyWords = l('supportSafetyWords') ?? supportSafetyWords;
    final an = j['animations'];
    if (an is Map) {
      final out = <String, dynamic>{};
      for (final e in an.entries) {
        final def = kDefaultAnimations[e.key];
        if (def == null) continue;
        final v = e.value;
        if (def is int && v is num) out['${e.key}'] = v.toInt().clamp(0, 20000);
        if (def is bool && v is bool) out['${e.key}'] = v;
        if (def is String && v is String && v.length <= 80) out['${e.key}'] = v;
      }
      animations = out;
    }
    texts = strMap('texts', 400) ?? texts;
    popups = strMap('popups', 2000) ?? popups;
    final eps = strMap('endpoints', 200, valid: (k, v) => kDefaultEndpoints.containsKey(k) && validEndpointPath(v));
    if (eps != null) {
      // Yalnız varsayılandan farklı olanlar saklanır; çakışan yollar reddedilir.
      final merged = {...kDefaultEndpoints, ...eps};
      if (merged.values.toSet().length == merged.length) {
        endpoints = {for (final e in eps.entries) if (kDefaultEndpoints[e.key] != e.value) e.key: e.value};
      }
    }
  }

  static bool validEndpointPath(String v) =>
      RegExp(r'^/[A-Za-z0-9_\-./{}]{1,150}$').hasMatch(v) &&
      !v.startsWith('/admin') &&
      !v.startsWith('/uploads') &&
      !v.contains('..');

  Map<String, dynamic> publicJson() => {
        'brandName': brandName,
        'tagline': tagline,
        'maintenance': maintenance,
        'maintenanceText': maintenanceText,
        'registrationOpen': registrationOpen,
        'guestLogin': guestLogin,
        'marketOpen': marketOpen,
        'dailyRewardCoins': dailyRewardCoins,
        'payment': {
          'paytr': paytrEnabled,
          'shopier': shopierEnabled,
          'manual': manualPayment,
          'manualInfo': manualPaymentInfo,
        },
        'backgroundColor': backgroundColor,
        'backgroundImageUrl': backgroundImageUrl,
        'logoUrl': logoUrl,
        'accentColor': accentColor,
        'texts': effectiveTexts,
        'popups': effectivePopups,
        'apiBase': apiBase,
        'wsUrl': wsUrl,
        'endpoints': effectiveEndpoints,
        'translate': translateEnabled && translateUrl.isNotEmpty,
        'languages': languages,
        'animations': effectiveAnimations,
        'paytrReady': paytrEnabled && paytrMerchantId.isNotEmpty && paytrMerchantKey.isNotEmpty && paytrMerchantSalt.isNotEmpty,
        'mailReady': mailEnabled && smtpHost.isNotEmpty,
        'requireEmail': requireEmail,
        'support': supportEnabled,
        'supportBotName': supportBotName,
        'kickCost': kickCost,
        'kickBanMinutes': kickBanMinutes,
      };
}

class Store {
  Store(this.file);

  final File? file;
  final Map<String, UserRec> users = {};
  final Map<String, AdminRec> admins = {};
  final List<RoomRec> rooms = [];
  final List<PackageRec> packages = [];
  final List<Map<String, dynamic>> gifts = [];
  final List<OrderRec> orders = [];
  final List<LedgerRec> ledger = [];
  final List<LogRec> audit = [];
  final List<LogRec> security = [];
  final List<NoticeRec> notices = [];
  final List<DmRec> dms = [];
  final List<FeatureRec> features = [];
  final List<TokenRec> tokens = [];
  final List<Ticket> tickets = [];
  final List<KbEntry> kb = [];
  final List<Map<String, dynamic>> mailLog = [];

  FeatureRec? feature(String key) => features.where((f) => f.key == key).firstOrNull;
  final Settings settings = Settings();
  Map<String, dynamic> rules = {};
  int seq = 1000;

  bool _dirty = false;

  String nextId(String prefix) => '$prefix${++seq}';

  UserRec? userByName(String username) {
    final u = username.toLowerCase();
    for (final x in users.values) {
      if (x.username.toLowerCase() == u) return x;
    }
    return null;
  }

  void markDirty() => _dirty = true;

  void log(String actor, String action, String target) {
    audit.insert(0, LogRec('info', actor, action, target));
    if (audit.length > 2000) audit.removeLast();
    markDirty();
  }

  void securityEvent(String level, String text, {String actor = 'sistem'}) {
    security.insert(0, LogRec(level, actor, text, ''));
    if (security.length > 2000) security.removeLast();
    markDirty();
  }

  NoticeRec addNotice(String userId, String kind, String text) {
    final n = NoticeRec(id: nextId('n'), userId: userId, kind: kind, text: text);
    notices.add(n);
    if (notices.length > 20000) notices.removeAt(0);
    markDirty();
    return n;
  }

  int unreadNotices(String userId) => notices.where((n) => n.userId == userId && !n.read).length;
  int unreadDms(String userId) => dms.where((d) => d.to == userId && !d.read).length;

  void addLedger(LedgerRec e) {
    ledger.add(e);
    if (ledger.length > 50000) ledger.removeAt(0);
    markDirty();
  }

  Future<void> load() async {
    final f = file;
    if (f == null || !await f.exists()) return;
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    List<Map<String, dynamic>> list(String k) => ((j[k] as List?) ?? const []).cast<Map<String, dynamic>>();
    for (final u in list('users')) {
      final r = UserRec.fromJson(u);
      users[r.id] = r;
    }
    for (final a in list('admins')) {
      final r = AdminRec.fromJson(a);
      admins[r.username.toLowerCase()] = r;
    }
    rooms.addAll(list('rooms').map(RoomRec.fromJson));
    packages.addAll(list('packages').map(PackageRec.fromJson));
    gifts.addAll(list('gifts'));
    orders.addAll(list('orders').map(OrderRec.fromJson));
    ledger.addAll(list('ledger').map(LedgerRec.fromJson));
    audit.addAll(list('audit').map(LogRec.fromJson));
    security.addAll(list('security').map(LogRec.fromJson));
    notices.addAll(list('notices').map(NoticeRec.fromJson));
    dms.addAll(list('dms').map(DmRec.fromJson));
    features.addAll(list('features').map(FeatureRec.fromJson));
    tokens.addAll(list('tokens').map(TokenRec.fromJson));
    tickets.addAll(list('tickets').map(Ticket.fromJson));
    kb.addAll(list('kb').map(KbEntry.fromJson));
    mailLog.addAll(list('mailLog'));
    if (j['kb'] == null) kb.addAll(kDefaultKb);
    settings.apply((j['settings'] as Map?)?.cast<String, dynamic>() ?? const {});
    rules = (j['rules'] as Map?)?.cast<String, dynamic>() ?? {};
    seq = j['seq'] as int? ?? seq;
  }

  Map<String, dynamic> toJson() => {
        'version': 2,
        'seq': seq,
        'settings': settings.toStorageJson(),
        'rules': rules,
        'users': [for (final u in users.values) u.toJson()],
        'admins': [for (final a in admins.values) a.toJson()],
        'rooms': [for (final r in rooms) r.toJson()],
        'packages': [for (final p in packages) p.toJson()],
        'gifts': gifts,
        'orders': [for (final o in orders) o.toJson()],
        'ledger': [for (final e in ledger) e.toJson()],
        'audit': [for (final e in audit) e.toJson()],
        'security': [for (final e in security) e.toJson()],
        'notices': [for (final e in notices) e.toJson()],
        'dms': [for (final e in dms) e.toJson()],
        'features': [for (final e in features) e.toJson()],
        'tokens': [for (final e in tokens) if (DateTime.now().isBefore(e.expires)) e.toJson()],
        'tickets': [for (final e in tickets) e.toJson()],
        'kb': [for (final e in kb) e.toJson()],
        'mailLog': mailLog.length > 300 ? mailLog.sublist(mailLog.length - 300) : mailLog,
      };

  /// Değişiklik varsa dosyaya atomik olarak yazar.
  Future<void> flush({bool force = false}) async {
    final f = file;
    if (f == null || (!_dirty && !force)) return;
    _dirty = false;
    final tmp = File('${f.path}.tmp');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsString(jsonEncode(toJson()), flush: true);
    await tmp.rename(f.path);
  }
}
