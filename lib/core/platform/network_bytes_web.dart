// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

Future<Uint8List?> fetchUrlBytes(String? url) async {
  if (url == null || !url.toLowerCase().startsWith('http')) return null;
  try {
    final response = await html.HttpRequest.request(
      url,
      method: 'GET',
      responseType: 'arraybuffer',
    );
    if (response.status == null ||
        response.status! < 200 ||
        response.status! >= 300) {
      return null;
    }
    final body = response.response;
    if (body is ByteBuffer) return body.asUint8List();
    if (body is Uint8List) return body;
    return null;
  } catch (_) {
    return null;
  }
}
