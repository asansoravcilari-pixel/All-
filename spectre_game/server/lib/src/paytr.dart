import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// PayTR iFrame API (sanal POS).
/// Belgeler: https://dev.paytr.com/iframe-api
class Paytr {
  Paytr({required this.merchantId, required this.merchantKey, required this.merchantSalt, this.testMode = true});

  final String merchantId;
  final String merchantKey;
  final String merchantSalt;
  final bool testMode;

  bool get configured => merchantId.isNotEmpty && merchantKey.isNotEmpty && merchantSalt.isNotEmpty;

  String _hmac(String data) => base64.encode(Hmac(sha256, utf8.encode(merchantKey)).convert(utf8.encode(data)).bytes);

  /// Sepet: [[ad, "29.99", adet], ...] → base64(JSON)
  static String basket(String name, int priceKurus) =>
      base64.encode(utf8.encode(jsonEncode([
        [name, (priceKurus / 100).toStringAsFixed(2), 1]
      ])));

  /// Token isteği için imza.
  String tokenHash({
    required String userIp,
    required String merchantOid,
    required String email,
    required int paymentAmount,
    required String userBasket,
    int noInstallment = 1,
    int maxInstallment = 0,
    String currency = 'TL',
  }) =>
      _hmac('$merchantId$userIp$merchantOid$email$paymentAmount$userBasket$noInstallment$maxInstallment$currency'
          '${testMode ? 1 : 0}$merchantSalt');

  /// Bildirim (callback) imzasını doğrular.
  bool verifyCallback({required String merchantOid, required String status, required String totalAmount, required String hash}) {
    final expected = _hmac('$merchantOid$merchantSalt$status$totalAmount');
    if (expected.length != hash.length) return false;
    var r = 0;
    for (var i = 0; i < expected.length; i++) {
      r |= expected.codeUnitAt(i) ^ hash.codeUnitAt(i);
    }
    return r == 0;
  }

  /// PayTR'dan ödeme sayfası token'ı alır. Başarılıysa iFrame adresini döner.
  Future<String> createPayment({
    required String userIp,
    required String merchantOid,
    required String email,
    required String userName,
    required String productName,
    required int amountKurus,
    required String okUrl,
    required String failUrl,
  }) async {
    final b = basket(productName, amountKurus);
    final token = tokenHash(
        userIp: userIp, merchantOid: merchantOid, email: email, paymentAmount: amountKurus, userBasket: b);
    final form = {
      'merchant_id': merchantId,
      'user_ip': userIp,
      'merchant_oid': merchantOid,
      'email': email,
      'payment_amount': '$amountKurus',
      'paytr_token': token,
      'user_basket': b,
      'debug_on': testMode ? '1' : '0',
      'no_installment': '1',
      'max_installment': '0',
      'user_name': userName,
      'user_address': 'Dijital ürün',
      'user_phone': '0000000000',
      'merchant_ok_url': okUrl,
      'merchant_fail_url': failUrl,
      'timeout_limit': '30',
      'currency': 'TL',
      'test_mode': testMode ? '1' : '0',
      'lang': 'tr',
    };
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(Uri.parse('https://www.paytr.com/odeme/api/get-token'));
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.write(Uri(queryParameters: form).query);
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await utf8.decoder.bind(res).join();
      final j = jsonDecode(body);
      if (j is Map && j['status'] == 'success' && j['token'] is String) {
        return 'https://www.paytr.com/odeme/guvenli/${j['token']}';
      }
      throw StateError(j is Map ? '${j['reason'] ?? 'PayTR hatası'}' : 'PayTR hatası');
    } finally {
      client.close(force: true);
    }
  }
}
