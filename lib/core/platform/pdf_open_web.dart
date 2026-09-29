// ignore: deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

Future<bool> openPdfBytes({
  required String fileName,
  required Uint8List bytes,
}) async {
  final blob = html.Blob(<Object>[bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..target = '_blank'
    ..title = fileName
    ..rel = 'noopener'
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  Future<void>.delayed(const Duration(minutes: 1), () {
    html.Url.revokeObjectUrl(url);
  });
  return true;
}
