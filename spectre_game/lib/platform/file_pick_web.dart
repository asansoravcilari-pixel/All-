import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<Uint8List?> pickImageBytes() {
  final done = Completer<Uint8List?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/png,image/jpeg,image/webp,image/gif';
  input.onchange = ((web.Event _) {
    final file = input.files?.item(0);
    if (file == null) {
      done.complete(null);
      return;
    }
    file.arrayBuffer().toDart.then((buf) => done.complete(buf.toDart.asUint8List()), onError: (_) => done.complete(null));
  }).toJS;
  input.click();
  return done.future;
}
