import 'package:flutter_test/flutter_test.dart';
import 'package:appgt_offline_subtables/features/metrics/metrics_layout.dart';

void main() {
  group('metricsDesktopGeometryWidth', () {
    test('conserva el lienzo completo al abrir el editor', () {
      expect(
        metricsDesktopGeometryWidth(
          availableWidth: 770,
          panelOpen: true,
          lastFullWidth: 1200,
        ),
        1200,
      );
    });

    test('reconstruye el ancho completo si el panel ya estaba abierto', () {
      expect(
        metricsDesktopGeometryWidth(
          availableWidth: 770,
          panelOpen: true,
        ),
        1200,
      );
    });

    test('usa el ancho disponible cuando el editor está cerrado', () {
      expect(
        metricsDesktopGeometryWidth(
          availableWidth: 1200,
          panelOpen: false,
          lastFullWidth: 900,
        ),
        1200,
      );
    });
  });
}
