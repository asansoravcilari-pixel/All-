import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final _rnd = Random.secure();

String randomToken([int bytes = 32]) {
  final b = List<int>.generate(bytes, (_) => _rnd.nextInt(256));
  return base64Url.encode(b).replaceAll('=', '');
}

const _iterations = 60000;

/// PBKDF2-HMAC-SHA256. Biçim: `pbkdf2$<iter>$<salt>$<hash>`
String hashPassword(String password, {String? salt, int iterations = _iterations}) {
  salt ??= randomToken(16);
  final dk = _pbkdf2(utf8.encode(password), utf8.encode(salt), iterations, 32);
  return 'pbkdf2\$$iterations\$$salt\$${base64.encode(dk)}';
}

bool verifyPassword(String password, String stored) {
  final parts = stored.split(r'$');
  if (parts.length != 4 || parts[0] != 'pbkdf2') return false;
  final iter = int.tryParse(parts[1]) ?? 0;
  if (iter <= 0) return false;
  final expected = hashPassword(password, salt: parts[2], iterations: iter);
  return _constantTimeEquals(expected, stored);
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var r = 0;
  for (var i = 0; i < a.length; i++) {
    r |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return r == 0;
}

Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations, int length) {
  final hmac = Hmac(sha256, password);
  final out = BytesBuilder();
  var block = 1;
  while (out.length < length) {
    final s = [...salt, (block >> 24) & 0xff, (block >> 16) & 0xff, (block >> 8) & 0xff, block & 0xff];
    var u = hmac.convert(s).bytes;
    final t = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
    block++;
  }
  return Uint8List.fromList(out.toBytes().sublist(0, length));
}

/// Kullanıcı adı kuralı: 3–20 karakter, harf/rakam/._-
final usernamePattern = RegExp(r'^[A-Za-z0-9._\-çğıöşüÇĞİÖŞÜ]{3,20}$');

String? validatePassword(String p) {
  if (p.length < 8) return 'Şifre en az 8 karakter olmalı';
  if (p.length > 128) return 'Şifre çok uzun';
  return null;
}
