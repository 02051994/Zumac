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

    test('ajusta también la altura y evita scroll vertical', () {
      expect(
        metricsDesktopCanvasScale(
          viewportWidth: 1200,
          geometryWidth: 1200,
          viewportHeight: 540,
          geometryHeight: 900,
        ),
        .6,
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

  group('metricsCanvasHitTarget', () {
    test('conserva el tamaño visual cuando hay espacio suficiente', () {
      expect(
        metricsCanvasHitTarget(
          screenPixels: 10,
          canvasScale: .5,
          maximumCanvasPixels: 65,
        ),
        20,
      );
    });

    test('no consume una tarjeta pequeña con una escala extrema', () {
      expect(
        metricsCanvasHitTarget(
          screenPixels: 12,
          canvasScale: .1,
          maximumCanvasPixels: 38,
        ),
        38,
      );
    });

    test('devuelve cero ante un área disponible inválida', () {
      expect(
        metricsCanvasHitTarget(
          screenPixels: 10,
          canvasScale: .5,
          maximumCanvasPixels: 0,
        ),
        0,
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

  group('edición de geometría', () {
    test('solo habilita bordes para el gráfico existente editado', () {
      expect(
        metricsCanResizeWidget(
          canManage: true,
          filterPanelOpen: false,
          editingWidgetId: 'grafico-ce',
          widgetId: 'grafico-ce',
        ),
        isTrue,
      );
      expect(
        metricsCanResizeWidget(
          canManage: true,
          filterPanelOpen: false,
          editingWidgetId: null,
          widgetId: 'grafico-ce',
        ),
        isFalse,
        reason: 'crear un gráfico no debe habilitar el resize',
      );
      expect(
        metricsCanResizeWidget(
          canManage: true,
          filterPanelOpen: true,
          editingWidgetId: 'grafico-ce',
          widgetId: 'grafico-ce',
        ),
        isFalse,
        reason: 'los filtros no deben habilitar el resize',
      );
      expect(
        metricsCanResizeWidget(
          canManage: true,
          filterPanelOpen: false,
          editingWidgetId: 'grafico-ph',
          widgetId: 'grafico-ce',
        ),
        isFalse,
      );
      expect(
        metricsCanResizeWidget(
          canManage: true,
          filterPanelOpen: false,
          editingWidgetId: ' grafico-ce ',
          widgetId: 'grafico-ce',
        ),
        isTrue,
        reason: 'la selección debe sobrevivir a espacios del origen remoto',
      );
    });
  });

  group('apariencia y nombres visuales', () {
    test('un gráfico nuevo nace cuadrado y el radio queda acotado', () {
      expect(metricsChartBorderRadius({}, legacyDefault: 0), 0);
      expect(metricsChartBorderRadius({'border_radius': 24}), 24);
      expect(metricsChartBorderRadius({'border_radius': 80}), 48);
    });

    test('los alias solo cambian la presentación del eje', () {
      final config = <String, dynamic>{
        'axis_aliases': {
          'x': {'FECHA_EVALUACION': 'FECHA'},
          'y': {'promedio_ce': 'CE'},
        },
      };
      expect(metricsAxisFieldAlias(config, 'x', 'FECHA_EVALUACION'), 'FECHA');
      expect(
        metricsAxisTitle(
          configuration: config,
          axis: 'y',
          fields: const ['promedio_ce'],
        ),
        'CE',
      );
      expect(
        metricsAxisTitle(
          configuration: config,
          axis: 'y',
          fields: const ['promedio_ce'],
          explicitTitle: 'Calidad',
        ),
        'Calidad',
      );
    });

    test('el título de leyenda es horizontal solo arriba o abajo', () {
      expect(metricsLegendTitleIsInline('top'), isTrue);
      expect(metricsLegendTitleIsInline('bottom'), isTrue);
      expect(metricsLegendTitleIsInline('left'), isFalse);
      expect(metricsLegendTitleIsInline('right'), isFalse);
    });

    test('un título vacío no reserva espacio en el gráfico', () {
      expect(metricsChartHasTitle(null), isFalse);
      expect(metricsChartHasTitle('   '), isFalse);
      expect(metricsChartHasTitle('Promedio de CE'), isTrue);
    });
  });

  group('aislamiento de datos entre gráficos', () {
    Map<String, dynamic> graph(String id, String valueField) => {
          'id': id,
          'tabla_origen': 'evaluaciones',
          'campo_dimension': 'fecha_evaluacion',
          'campo_valor': valueField,
          'agregacion': 'AVG',
          'configuracion': {
            'dimensions': ['fecha_evaluacion'],
            'values': [valueField],
            'values_y2': <String>[],
            'value_aggregations': {valueField: 'AVG'},
          },
        };

    test('editar promedio_ce conserva promedio_ph en el otro gráfico', () {
      final before = [
        graph('grafico-ce', 'promedio_ce'),
        graph('grafico-ph', 'promedio_ph'),
      ];
      final expected = graph('grafico-ce', 'promedio_ce');
      final after = [
        graph('grafico-ce', 'promedio_ce'),
        graph('grafico-ph', 'promedio_ph'),
      ];
      expect(
        metricsVerifiedWidgetSave(
          before: before,
          after: after,
          expected: expected,
          savedId: 'grafico-ce',
        )['id'],
        'grafico-ce',
      );
    });

    test('rechaza que otro gráfico adopte promedio_ce', () {
      final before = [
        graph('grafico-ce', 'promedio_ce'),
        graph('grafico-ph', 'promedio_ph'),
      ];
      final after = [
        graph('grafico-ce', 'promedio_ce'),
        graph('grafico-ph', 'promedio_ce'),
      ];
      expect(
        () => metricsVerifiedWidgetSave(
          before: before,
          after: after,
          expected: graph('grafico-ce', 'promedio_ce'),
          savedId: 'grafico-ce',
        ),
        throwsStateError,
      );
    });
  });
}
