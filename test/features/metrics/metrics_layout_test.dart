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

  group('metricsDesktopCanvasScale', () {
    test('reduce todo el lienzo cuando el panel ocupa parte del ancho', () {
      expect(
        metricsDesktopCanvasScale(
          viewportWidth: 770,
          geometryWidth: 1200,
        ),
        closeTo(0.641666, 0.000001),
      );
    });

    test('no agranda el lienzo por encima de su tamaño guardado', () {
      expect(
        metricsDesktopCanvasScale(
          viewportWidth: 1400,
          geometryWidth: 1200,
        ),
        1,
      );
    });
  });

  group('metricsCanvasGestureDelta', () {
    test('mantiene el desplazamiento real con el lienzo reducido', () {
      expect(
        metricsCanvasGestureDelta(screenDelta: 64, canvasScale: .64),
        100,
      );
    });
  });

  group('metricsResponsiveDashboardTitleSize', () {
    test('reduce el título en pantallas pequeñas', () {
      expect(
        metricsResponsiveDashboardTitleSize(
          configuredSize: 48,
          availableWidth: 450,
        ),
        closeTo(27.84, 0.000001),
      );
    });

    test('respeta el tamaño configurado en un lienzo amplio', () {
      expect(
        metricsResponsiveDashboardTitleSize(
          configuredSize: 48,
          availableWidth: 1200,
        ),
        48,
      );
    });
  });

  group('metricsVerifiedDashboardOrder', () {
    test('acepta una relectura idéntica y consecutiva', () {
      final rows = <Map<String, dynamic>>[
        {'id': 'b', 'orden': 0},
        {'id': 'a', 'orden': 1},
      ];
      expect(
        metricsVerifiedDashboardOrder(rows, ['b', 'a']),
        same(rows),
      );
    });

    test('rechaza el orden optimista si Supabase devuelve el anterior', () {
      final rows = <Map<String, dynamic>>[
        {'id': 'a', 'orden': 0},
        {'id': 'b', 'orden': 1},
      ];
      expect(
        () => metricsVerifiedDashboardOrder(rows, ['b', 'a']),
        throwsStateError,
      );
    });

    test('rechaza órdenes duplicados aunque la secuencia coincida', () {
      final rows = <Map<String, dynamic>>[
        {'id': 'b', 'orden': 0},
        {'id': 'a', 'orden': 0},
      ];
      expect(
        () => metricsVerifiedDashboardOrder(rows, ['b', 'a']),
        throwsStateError,
      );
    });
  });
}
