import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/evidence_storage.dart';

class ErpPendingImage {
  final String name;
  final Uint8List bytes;

  const ErpPendingImage({required this.name, required this.bytes});
}

class ErpImageAttachment {
  static const bucket = 'erp-articulos';
  static const _uuid = Uuid();

  static Future<ErpPendingImage?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (file.bytes == null) return null;
    if (file.bytes!.lengthInBytes > 10 * 1024 * 1024) {
      throw StateError('La imagen no puede superar 10 MB.');
    }
    return ErpPendingImage(name: file.name, bytes: file.bytes!);
  }

  static Future<String> upload({
    required SupabaseClient client,
    required String companyId,
    required String userId,
    required ErpPendingImage image,
  }) async {
    if (companyId.trim().isEmpty || userId.trim().isEmpty) {
      throw StateError('No se pudo identificar la empresa o el usuario.');
    }
    final extension = _extension(image.name);
    final path = '${companyId.trim()}/solicitudes/${userId.trim()}/'
        '${_uuid.v4()}.$extension';
    await client.storage.from(bucket).uploadBinary(
          path,
          image.bytes,
          fileOptions: FileOptions(
            contentType: _contentType(extension),
            upsert: false,
          ),
        );
    return EvidenceStorage.toStorageUri(path, bucketName: bucket);
  }

  static Future<void> show(
    BuildContext context, {
    Uint8List? bytes,
    String? storageUrl,
  }) async {
    final normalized = storageUrl?.trim() ?? '';
    if (bytes == null && normalized.isEmpty) return;
    String? signedUrl;
    Object? error;
    if (bytes == null) {
      try {
        signedUrl = await EvidenceStorage.signedUrlForValue(normalized);
      } catch (caught) {
        error = caught;
      }
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                automaticallyImplyLeading: false,
                title: const Text('Foto del artículo'),
                actions: [
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: error != null
                      ? Text('No se pudo abrir la imagen: $error')
                      : InteractiveViewer(
                          minScale: .5,
                          maxScale: 5,
                          child: bytes != null
                              ? Image.memory(bytes, fit: BoxFit.contain)
                              : Image.network(
                                  signedUrl!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, imageError, __) => Text(
                                    'No se pudo abrir la imagen: $imageError',
                                  ),
                                ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _extension(String name) {
    final value = name.split('.').last.toLowerCase();
    return const {'jpg', 'jpeg', 'png', 'webp'}.contains(value) ? value : 'jpg';
  }

  static String _contentType(String extension) => switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}
