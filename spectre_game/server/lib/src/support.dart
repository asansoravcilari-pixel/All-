library;

/// Destek robotu: bilgi tabanı + güvenlik kuralları. Saf mantık (test edilebilir).

class KbEntry {
  KbEntry({required this.id, required this.question, required this.keywords, required this.answer});
  final String id;
  String question;
  List<String> keywords;
  String answer;

  Map<String, dynamic> toJson() => {'id': id, 'question': question, 'keywords': keywords, 'answer': answer};
  factory KbEntry.fromJson(Map<String, dynamic> j) => KbEntry(
        id: j['id'] as String,
        question: j['question'] as String? ?? '',
        keywords: [for (final k in (j['keywords'] as List? ?? const [])) '$k'],
        answer: j['answer'] as String? ?? '',
      );
}

final kDefaultKb = <KbEntry>[
  KbEntry(
    id: 'kb1',
    question: 'Nasıl oynanır?',
    keywords: ['nasıl', 'oyna', 'oyun', 'şişe', 'çevir'],
    answer: 'Bir masaya otur; sıra sana gelince ÇEVİR düğmesine bas. Şişe bir oyuncuyu seçer, ikiniz de Kabul derseniz eşleşirsiniz.',
  ),
  KbEntry(
    id: 'kb2',
    question: 'Coin nasıl alırım?',
    keywords: ['coin', 'jeton', 'satın', 'market', 'yükle'],
    answer: 'Market bölümünden paket seçip kartla (sanal POS) ya da havale ile ödeyebilirsin. Ödeme onaylanınca coinler otomatik yüklenir.',
  ),
  KbEntry(
    id: 'kb3',
    question: 'Aboneliğim ne zaman biter?',
    keywords: ['abonelik', 'paket', 'süre', 'bitiyor', 'bitiş', 'hak'],
    answer: 'Aktif paketlerini ve bitiş tarihlerini Profil penceresinde görebilirsin. Süre dolunca özellik otomatik kilitlenir.',
  ),
  KbEntry(
    id: 'kb4',
    question: 'Şifremi unuttum',
    keywords: ['şifre', 'parola', 'unuttum', 'giriş'],
    answer: 'Giriş ekranındaki "Şifremi unuttum" bağlantısıyla e-postana sıfırlama bağlantısı gönderebilirsin.',
  ),
];

/// Basit eşleştirme: anahtar kelime sayısına göre en iyi yanıt.
KbEntry? bestAnswer(List<KbEntry> kb, String text) {
  final low = text.toLowerCase();
  KbEntry? best;
  var bestScore = 0;
  for (final e in kb) {
    var score = 0;
    for (final k in e.keywords) {
      if (k.isNotEmpty && low.contains(k.toLowerCase())) score++;
    }
    if (score > bestScore) {
      bestScore = score;
      best = e;
    }
  }
  return best;
}

bool wantsHuman(String text) {
  final low = text.toLowerCase();
  return ['yetkili', 'insan', 'canlı destek', 'temsilci', 'admin'].any(low.contains);
}

/// Başkasına ait bilgi isteme ya da kural dışı ifade.
String? safetyHit(List<String> words, String text) {
  final low = text.toLowerCase();
  for (final w in words) {
    if (w.isNotEmpty && low.contains(w.toLowerCase())) return w;
  }
  return null;
}

const kDefaultSafetyWords = ['başkasının şifresi', 'şifresini ver', 'hesabını ver', 'kimlik numarası', 'tc kimlik'];

class TicketMsg {
  TicketMsg(this.from, this.text, {DateTime? at}) : at = at ?? DateTime.now();
  final String from; // user | bot | admin:<ad>
  final String text;
  final DateTime at;

  Map<String, dynamic> toJson() => {'from': from, 'text': text, 'at': at.toIso8601String()};
  factory TicketMsg.fromJson(Map<String, dynamic> j) =>
      TicketMsg(j['from'] as String, j['text'] as String, at: DateTime.tryParse(j['at'] as String? ?? ''));
}

class Ticket {
  Ticket({required this.id, required this.userId, this.status = 'bot', DateTime? updatedAt, this.lockedUntil, List<TicketMsg>? messages})
      : updatedAt = updatedAt ?? DateTime.now(),
        messages = messages ?? [];
  final String id;
  final String userId;
  String status; // bot | waiting | answered | closed | locked
  DateTime updatedAt;
  DateTime? lockedUntil;
  final List<TicketMsg> messages;

  bool get locked => lockedUntil != null && DateTime.now().isBefore(lockedUntil!);

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'status': status,
        'updatedAt': updatedAt.toIso8601String(),
        'lockedUntil': lockedUntil?.toIso8601String(),
        'messages': [for (final m in messages) m.toJson()],
      };
  factory Ticket.fromJson(Map<String, dynamic> j) => Ticket(
        id: j['id'] as String,
        userId: j['userId'] as String,
        status: j['status'] as String? ?? 'bot',
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
        lockedUntil: j['lockedUntil'] == null ? null : DateTime.tryParse(j['lockedUntil'] as String),
        messages: [for (final m in (j['messages'] as List? ?? const [])) TicketMsg.fromJson((m as Map).cast<String, dynamic>())],
      );
}
