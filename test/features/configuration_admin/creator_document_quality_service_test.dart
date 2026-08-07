import 'dart:typed_data';

import 'package:appgt_offline_subtables/features/configuration_admin/creator_document_quality_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  const service = CreatorDocumentQualityService();

  test('rechaza una imagen uniforme que no contiene texto legible', () {
    final image = img.Image(width: 1200, height: 1600);
    img.fill(image, color: img.ColorRgb8(128, 128, 128));

    final report =
        service.inspectImage(Uint8List.fromList(img.encodeJpg(image)));

    expect(report.acceptable, isFalse);
    expect(report.reasons.join(' '), contains('contraste'));
    expect(report.reasons.join(' '), contains('nítida'));
  });

  test('acepta una imagen grande, contrastada y con bordes definidos', () {
    final image = img.Image(width: 1200, height: 1600);
    img.fill(image, color: img.ColorRgb8(250, 250, 245));
    for (var y = 80; y < 1520; y += 32) {
      for (var x = 80; x < 1120; x++) {
        image.setPixelRgb(x, y, 15, 25, 30);
        if (y + 1 < image.height) image.setPixelRgb(x, y + 1, 15, 25, 30);
      }
    }
    for (var x = 80; x < 1120; x += 80) {
      for (var y = 80; y < 1520; y++) {
        image.setPixelRgb(x, y, 15, 25, 30);
      }
    }

    final report =
        service.inspectImage(Uint8List.fromList(img.encodePng(image)));

    expect(report.acceptable, isTrue, reason: report.reasons.join(' | '));
    expect(report.metrics['ancho'], 1200);
    expect(report.metrics['nitidez'], greaterThan(900));
  });

  test('valida la firma PDF y deja legibilidad para revisión visual', () {
    final valid = service.inspectPdf(
      Uint8List.fromList('%PDF-1.7 contenido'.codeUnits),
    );
    final invalid = service.inspectPdf(Uint8List.fromList('texto'.codeUnits));

    expect(valid.acceptable, isTrue);
    expect(valid.requiresServerReview, isTrue);
    expect(invalid.acceptable, isFalse);
  });
}
