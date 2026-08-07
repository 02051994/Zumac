import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'creator_document_models.dart';

class CreatorDocumentQualityService {
  const CreatorDocumentQualityService();

  CreatorDocumentQuality inspectImage(Uint8List bytes) {
    final source = img.decodeImage(bytes);
    if (source == null) {
      return const CreatorDocumentQuality(
        acceptable: false,
        summary: 'No se pudo leer la imagen.',
        reasons: ['El archivo está dañado o no es una imagen compatible.'],
      );
    }

    final shortestSide = math.min(source.width, source.height);
    final longestSide = math.max(source.width, source.height);
    final scale = longestSide > 1200 ? 1200 / longestSide : 1.0;
    final sample = scale < 1
        ? img.copyResize(
            source,
            width: math.max(1, (source.width * scale).round()),
            height: math.max(1, (source.height * scale).round()),
            interpolation: img.Interpolation.average,
          )
        : source;

    var count = 0;
    var sum = 0.0;
    var sumSquares = 0.0;
    var edgeCount = 0;
    var edgeSum = 0.0;
    var edgeSquares = 0.0;
    const stride = 2;
    for (var y = 1; y < sample.height - 1; y += stride) {
      for (var x = 1; x < sample.width - 1; x += stride) {
        final center = _luminance(sample.getPixel(x, y));
        sum += center;
        sumSquares += center * center;
        count++;
        final gx = _luminance(sample.getPixel(x + 1, y)) -
            _luminance(sample.getPixel(x - 1, y));
        final gy = _luminance(sample.getPixel(x, y + 1)) -
            _luminance(sample.getPixel(x, y - 1));
        final energy = gx * gx + gy * gy;
        edgeSum += energy;
        edgeSquares += energy * energy;
        edgeCount++;
      }
    }
    final brightness = count == 0 ? 0.0 : sum / count;
    final variance = count == 0
        ? 0.0
        : math.max(0, (sumSquares / count) - brightness * brightness);
    final contrast = math.sqrt(variance);
    final edgeMean = edgeCount == 0 ? 0.0 : edgeSum / edgeCount;
    final edgeVariance = edgeCount == 0
        ? 0.0
        : math.max(0, (edgeSquares / edgeCount) - edgeMean * edgeMean);
    final focusScore = math.sqrt(edgeVariance);

    final reasons = <String>[];
    final warnings = <String>[];
    if (shortestSide < 900) {
      reasons.add(
        'La resolución es baja (${source.width} × ${source.height}). Use al menos 900 px en el lado corto.',
      );
    }
    if (brightness < 38) {
      reasons.add('La foto está demasiado oscura. Use más iluminación.');
    } else if (brightness > 235) {
      reasons
          .add('La foto está sobreexpuesta. Evite reflejos y flash directo.');
    }
    if (contrast < 18) {
      reasons.add('El texto tiene muy poco contraste con el fondo.');
    }
    if (focusScore < 900) {
      reasons.add('La imagen no es nítida. Tome otra foto sin movimiento.');
    } else if (focusScore < 1500) {
      warnings.add(
          'La nitidez es aceptable, pero conviene revisar textos pequeños.');
    }
    if (shortestSide < 1200 && shortestSide >= 900) {
      warnings.add('Una foto de mayor resolución mejorará el reconocimiento.');
    }

    return CreatorDocumentQuality(
      acceptable: reasons.isEmpty,
      summary: reasons.isEmpty
          ? 'La imagen tiene calidad suficiente para analizarla.'
          : 'La imagen no es nítida o legible. Suba o tome otra.',
      reasons: reasons,
      warnings: warnings,
      metrics: {
        'ancho': source.width.toDouble(),
        'alto': source.height.toDouble(),
        'brillo': brightness,
        'contraste': contrast,
        'nitidez': focusScore,
      },
    );
  }

  CreatorDocumentQuality inspectPdf(Uint8List bytes) {
    final signature =
        bytes.length >= 5 ? String.fromCharCodes(bytes.sublist(0, 5)) : '';
    if (signature != '%PDF-') {
      return const CreatorDocumentQuality(
        acceptable: false,
        summary: 'El archivo no es un PDF válido.',
        reasons: ['Seleccione un PDF sin daños y vuelva a intentarlo.'],
      );
    }
    return const CreatorDocumentQuality(
      acceptable: true,
      summary:
          'El PDF es válido. Zumac verificará la legibilidad de sus páginas.',
      requiresServerReview: true,
      warnings: [
        'Los PDF escaneados todavía deben superar la revisión visual de la IA.',
      ],
    );
  }

  double _luminance(img.Pixel pixel) =>
      .2126 * pixel.r.toDouble() +
      .7152 * pixel.g.toDouble() +
      .0722 * pixel.b.toDouble();
}
