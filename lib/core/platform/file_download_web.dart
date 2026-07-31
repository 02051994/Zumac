// ignore: deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> downloadFileBytes({
  required String fileName,
  required Uint8List bytes,
}) async {
  final extension = fileName.split('.').last.toLowerCase();
  final mimeType = switch (extension) {
    'csv' => 'text/csv;charset=utf-8',
    'pdf' => 'application/pdf',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'xls' => 'application/vnd.ms-excel',
    _ => 'application/octet-stream',
  };
  final blob = html.Blob(<Object>[bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  await Future<void>.delayed(Duration.zero);
  html.Url.revokeObjectUrl(url);
}
