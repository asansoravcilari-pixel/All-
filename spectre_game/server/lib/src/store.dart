import 'dart:convert';
import 'dart:io';

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
    List<String>? notes,
    List<String>? warnings,
  })  : notes = notes ?? [],
        warnings = warnings ?? [];

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
  final List<String> notes;
  final List<String> warnings;

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
  });
  final String id;
  String name;
  int coins;
  int priceKurus;
  int bonusPercent;
  int vipDays;
  bool active;
  bool featured;

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
      );
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

class Settings {
  bool maintenance = false;
  String maintenanceText = 'Kısa bir bakım yapıyoruz, birazdan döneceğiz.';
  bool registrationOpen = true;
  bool guestLogin = true;
  bool marketOpen = true;
  int maxMessagesPerMinute = 20;
  int maxGiftsPerMinute = 10;
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
  }

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
    settings.apply((j['settings'] as Map?)?.cast<String, dynamic>() ?? const {});
    rules = (j['rules'] as Map?)?.cast<String, dynamic>() ?? {};
    seq = j['seq'] as int? ?? seq;
  }

  Map<String, dynamic> toJson() => {
        'version': 2,
        'seq': seq,
        'settings': settings.toJson(),
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
