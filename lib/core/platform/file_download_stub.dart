import 'dart:typed_data';

Future<void> downloadFileBytes({
  required String fileName,
  required Uint8List bytes,
}) {
  throw UnsupportedError(
    'La descarga directa solo está disponible en la aplicación web.',
  );
}
