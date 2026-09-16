import 'package:supabase_flutter/supabase_flutter.dart';

class EvidenceStorage {
  static const bucket = 'appgt-evidencias';
  static const permissionDocumentsBucket = 'permisos-licencias';
  static const uriPrefix = 'storage://$bucket/';
  static const signedUrlTtlSeconds = 60 * 60; // 1 hora. Se regenera al visualizar.

  static String toStorageUri(String path, {String bucketName = bucket}) =>
      'storage://$bucketName/$path';

  static bool isStorageUri(String value) {
    return value.trim().toLowerCase().startsWith('storage://');
  }

  static String? extractPath(String value) {
    final parsed = extractBucketAndPath(value);
    if (parsed == null) return null;
    return parsed.path;
  }

  static ({String bucket, String path})? extractBucketAndPath(String value) {
    final trimmed = value.trim();
    final lower = trimmed.toLowerCase();
    if (!lower.startsWith('storage://')) return null;
    final rest = trimmed.substring('storage://'.length);
    final slash = rest.indexOf('/');
    if (slash <= 0 || slash >= rest.length - 1) return null;
    return (bucket: rest.substring(0, slash), path: rest.substring(slash + 1));
  }

  static Future<String> signedUrlForValue(String value) async {
    final trimmed = value.trim();
    final parsed = extractBucketAndPath(trimmed);
    if (parsed != null && parsed.path.trim().isNotEmpty) {
      return Supabase.instance.client.storage
          .from(parsed.bucket)
          .createSignedUrl(parsed.path, signedUrlTtlSeconds);
    }
    if (!trimmed.toLowerCase().startsWith('http') && trimmed.contains('/')) {
      final candidates = <String>[bucket, 'migracion-appsheets'];
      for (final candidateBucket in candidates) {
        try {
          return await Supabase.instance.client.storage
              .from(candidateBucket)
              .createSignedUrl(trimmed, signedUrlTtlSeconds);
        } catch (_) {}
      }
      return trimmed;
    }
    return trimmed;
  }
}
