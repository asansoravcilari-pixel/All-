import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

/// Varsayılan mail şablonları ({{alan}} yer tutucuları).
const Map<String, Map<String, String>> kDefaultMailTemplates = {
  'welcome': {
    'name': 'Hoş geldin',
    'subject': '{{brand}} ailesine hoş geldin, {{name}}!',
    'body': '<h2>Merhaba {{name}},</h2><p>{{brand}} hesabın oluşturuldu. Kullanıcı adın: <b>{{username}}</b></p>'
        '<p>E-posta adresini doğrulamak için: <a href="{{link}}">{{link}}</a></p><p>İyi eğlenceler!</p>',
  },
  'verify': {
    'name': 'E-posta doğrulama',
    'subject': '{{brand}} — e-posta adresini doğrula',
    'body': '<p>Merhaba {{name}},</p><p>E-posta adresini doğrulamak için bağlantıya tıkla:</p>'
        '<p><a href="{{link}}">{{link}}</a></p><p>Bağlantı 48 saat geçerlidir.</p>',
  },
  'reset': {
    'name': 'Şifremi unuttum',
    'subject': '{{brand}} — şifre sıfırlama',
    'body': '<p>Merhaba {{name}},</p><p>Şifreni sıfırlamak için bağlantıya tıkla (1 saat geçerli):</p>'
        '<p><a href="{{link}}">{{link}}</a></p><p>Bu isteği sen yapmadıysan bu e-postayı yok sayabilirsin.</p>',
  },
  'purchase': {
    'name': 'Satın alma bilgisi',
    'subject': '{{brand}} — siparişin onaylandı ({{order}})',
    'body': '<p>Merhaba {{name}},</p><p><b>{{package}}</b> siparişin onaylandı.</p>'
        '<p>Tutar: {{amount}}<br>Eklenen coin: {{coins}}<br>Tanımlanan haklar: {{features}}<br>Bitiş: {{expires}}</p>'
        '<p>Teşekkür ederiz!</p>',
  },
  'expiring': {
    'name': 'Abonelik bitmek üzere',
    'subject': '{{brand}} — {{feature}} {{days}} gün içinde bitiyor',
    'body': '<p>Merhaba {{name}},</p><p><b>{{feature}}</b> hakkın {{expires}} tarihinde bitecek.</p>'
        '<p>Kesintisiz devam etmek için marketten yenileyebilirsin.</p>',
  },
  'expired': {
    'name': 'Abonelik bitti',
    'subject': '{{brand}} — {{feature}} süren doldu',
    'body': '<p>Merhaba {{name}},</p><p><b>{{feature}}</b> hakkının süresi doldu ve özellik kilitlendi.</p>'
        '<p>Yeniden açmak için marketi ziyaret et.</p>',
  },
  'paymentSuccess': {
    'name': 'Ödeme başarılı',
    'subject': '{{brand}} — ödemen alındı ({{order}})',
    'body': '<p>Merhaba {{name}},</p><p><b>{{package}}</b> için {{amount}} tutarındaki ödemen başarıyla alındı.</p>'
        '<p>Sipariş no: {{order}}</p>',
  },
  'paymentFailed': {
    'name': 'Ödeme başarısız',
    'subject': '{{brand}} — ödeme tamamlanamadı ({{order}})',
    'body': '<p>Merhaba {{name}},</p><p><b>{{package}}</b> için ödemen tamamlanamadı.</p>'
        '<p>Neden: {{reason}}</p><p>Marketten tekrar deneyebilirsin.</p>',
  },
  'loginSuccess': {
    'name': 'Oturum açıldı',
    'subject': '{{brand}} — hesabına yeni giriş',
    'body': '<p>Merhaba {{name}},</p><p>Hesabına {{time}} tarihinde {{ip}} adresinden giriş yapıldı.</p>'
        '<p>Bu sen değilsen hemen şifreni değiştir: <a href="{{link}}">{{link}}</a></p>',
  },
  'loginFailed': {
    'name': 'Başarısız giriş denemesi',
    'subject': '{{brand}} — hesabına başarısız giriş denemeleri',
    'body': '<p>Merhaba {{name}},</p><p>Hesabına {{ip}} adresinden {{count}} başarısız giriş denemesi yapıldı ({{time}}).</p>'
        '<p>Bu sen değilsen şifreni sıfırla: <a href="{{link}}">{{link}}</a></p>',
  },
  'supportReply': {
    'name': 'Destek yanıtı',
    'subject': '{{brand}} destek — yeni yanıt',
    'body': '<p>Merhaba {{name}},</p><p>Destek talebine yanıt verildi:</p><blockquote>{{message}}</blockquote>',
  },
};

String renderTemplate(String tpl, Map<String, String> vars, {bool html = false}) =>
    tpl.replaceAllMapped(RegExp(r'\{\{\s*(\w+)\s*\}\}'), (m) {
      final v = vars[m.group(1)] ?? '';
      if (!html) return v;
      return v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
    });

class MailConfig {
  MailConfig({
    required this.host,
    required this.port,
    required this.security,
    required this.user,
    required this.password,
    required this.from,
    required this.fromName,
  });
  final String host;
  final int port;
  final String security; // ssl | starttls | none
  final String user;
  final String password;
  final String from;
  final String fromName;

  bool get configured => host.isNotEmpty && from.contains('@');
}

/// SMTP üzerinden gönderim.
Future<void> sendMail(MailConfig c, {required String to, required String subject, required String html}) async {
  if (!c.configured) throw StateError('SMTP ayarları eksik');
  final server = SmtpServer(
    c.host,
    port: c.port,
    ssl: c.security == 'ssl',
    allowInsecure: c.security == 'none',
    ignoreBadCertificate: false,
    username: c.user.isEmpty ? null : c.user,
    password: c.password.isEmpty ? null : c.password,
  );
  final msg = Message()
    ..from = Address(c.from, c.fromName)
    ..recipients.add(to)
    ..subject = subject
    ..html = html
    ..text = html.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  await send(msg, server, timeout: const Duration(seconds: 20));
}
