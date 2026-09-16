import 'dart:io';
import 'package:flutter/foundation.dart';

Future<Uint8List?> fetchUrlBytes(String? url) async {
  if (url == null || !url.toLowerCase().startsWith('http')) return null;
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    return consolidateHttpClientResponseBytes(response);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
