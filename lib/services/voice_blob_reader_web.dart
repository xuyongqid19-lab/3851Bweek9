import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<({Uint8List bytes, String mime})?> readBlobBytes(String url) async {
  try {
    final response = await web.window.fetch(url.toJS).toDart;
    final mime = response.headers.get('content-type') ?? 'audio/mp4';
    final buffer = await response.arrayBuffer().toDart;
    return (bytes: buffer.toDart.asUint8List(), mime: mime);
  } catch (_) {
    return null;
  }
}
