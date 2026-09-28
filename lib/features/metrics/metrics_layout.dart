import 'dart:convert';
import 'dart:math' as math;

/// Ancho estable usado para guardar y representar la geometría libre.
///
/// Al abrir el editor, [availableWidth] disminuye, pero los gráficos deben
/// conservar el ancho completo que tenía el lienzo antes de abrirlo.
double metricsDesktopGeometryWidth({
  required double availableWidth,
  required bool panelOpen,
  double? lastFullWidth,
  double editorWidth = 430,
}) {
  if (!panelOpen) return availableWidth;
  return math.max(
      lastFullWidth ?? availableWidth + editorWidth, availableWidth);
}

/// Escala visual que permite mostrar la geometría completa en el espacio que
/// queda junto al panel, sin modificar las coordenadas guardadas.
double metricsDesktopCanvasScale({
  required double viewportWidth,
  required double geometryWidth,
  double? viewportHeight,
  double? geometryHeight,
}) {
  if (geometryWidth <= 0) return 1;
  final widthScale = math.max(0, viewportWidth) / geometryWidth;
  final heightScale =
      viewportHeight == null || geometryHeight == null || geometryHeight <= 0
          ? 1.0
          : math.max(0, viewportHeight) / geometryHeight;
  return math.min(1, math.min(widthScale, heightScale));
}

/// Convierte un desplazamiento medido en pantalla a coordenadas del lienzo.
///
/// Los gestos siguen siendo precisos aunque el panel lateral reduzca el
/// lienzo visualmente mediante [metricsDesktopCanvasScale].
double metricsCanvasGestureDelta({
  required double screenDelta,
  required double canvasScale,
}) {
  if (canvasScale <= 0) return 0;
  return screenDelta / canvasScale;
}

/// Convierte una medida visual a coordenadas del lienzo sin permitir que el
/// área interactiva consuma una tarjeta pequeña completa.
///
/// Al reducir el lienzo, dividir siempre entre la escala puede producir zonas
/// de agarre más grandes que el propio gráfico. El límite proporcional mantiene
/// disponibles tanto el contenido como todos sus bordes.
double metricsCanvasHitTarget({
  required double screenPixels,
  required double canvasScale,
  required double maximumCanvasPixels,
}) {
  if (screenPixels <= 0 || maximumCanvasPixels <= 0) return 0;
  final safeScale = math.max(.1, canvasScale);
  return math.min(screenPixels / safeScale, maximumCanvasPixels);
}

/// Tamaño responsive del título sin perder el valor configurado por el usuario.
double metricsResponsiveDashboardTitleSize({
  required double configuredSize,
  required double availableWidth,
}) {
  final safeConfigured = configuredSize.clamp(14.0, 72.0).toDouble();
  if (availableWidth >= 900) return safeConfigured;
  final factor = (availableWidth / 900).clamp(.58, 1.0).toDouble();
  return (safeConfigured * factor).clamp(16.0, safeConfigured).toDouble();
}

/// Valida que una lectura independiente de Supabase conserve exactamente la
/// secuencia solicitada y órdenes consecutivos desde cero.
List<Map<String, dynamic>> metricsVerifiedDashboardOrder(
  List<Map<String, dynamic>> dashboards,
  List<String> expectedIds,
) {
  if (dashboards.length != expectedIds.length) {
    throw StateError(
      'Supabase devolvió una cantidad distinta de dashboards al verificar.',
    );
  }
  for (var index = 0; index < dashboards.length; index++) {
    final id = dashboards[index]['id']?.toString() ?? '';
    final order = (dashboards[index]['orden'] as num?)?.toInt();
    if (id != expectedIds[index] || order != index) {
      throw StateError(
        'Supabase no conservó el orden solicitado al volver a leerlo.',
      );
    }
  }
  return dashboards;
}

/// El cambio de geometría solo está habilitado mientras se edita un gráfico
/// existente. Crear un gráfico o abrir filtros nunca activa sus bordes.
bool metricsCanResizeWidget({
  required bool canManage,
  required bool filterPanelOpen,
  required String? editingWidgetId,
  required String widgetId,
}) {
  final selectedId = editingWidgetId?.trim() ?? '';
  final candidateId = widgetId.trim();
  return canManage &&
      !filterPanelOpen &&
      selectedId.isNotEmpty &&
      candidateId.isNotEmpty &&
      selectedId == candidateId;
}

/// Los gráficos históricos conservan su radio anterior. Los nuevos guardan
/// explícitamente cero y por eso nacen con esquinas cuadradas.
double metricsChartBorderRadius(
  Map<String, dynamic> configuration, {
  double legacyDefault = 18,
}) =>
    ((configuration['border_radius'] as num?)?.toDouble() ?? legacyDefault)
        .clamp(0.0, 48.0)
        .toDouble();

String metricsAxisFieldAlias(
  Map<String, dynamic> configuration,
  String axis,
  String field,
) {
  final aliases = configuration['axis_aliases'];
  if (aliases is! Map) return '';
  final scoped = aliases[axis];
  if (scoped is! Map) return '';
  return scoped[field]?.toString().trim() ?? '';
}

String metricsAxisTitle({
  required Map<String, dynamic> configuration,
  required String axis,
  required List<String> fields,
  String explicitTitle = '',
}) {
  final explicit = explicitTitle.trim();
  if (explicit.isNotEmpty) return explicit;
  return fields
      .map((field) => metricsAxisFieldAlias(configuration, axis, field))
      .where((alias) => alias.isNotEmpty)
      .join(' · ');
}

bool metricsLegendTitleIsInline(String position) =>
    position == 'top' || position == 'bottom';

bool metricsChartHasTitle(dynamic title) =>
    title?.toString().trim().isNotEmpty == true;

/// Firma inmutable de los campos que definen los datos de un gráfico. No
/// incluye geometría ni apariencia, por lo que sirve para comprobar que
/// guardar un gráfico no cambió los ejes de ningún otro.
String metricsWidgetDataSignature(Map<String, dynamic> widget) {
  final configuration = widget['configuracion'];
  final config = configuration is Map
      ? Map<String, dynamic>.from(configuration)
      : <String, dynamic>{};
  List<String> values(String key) => (config[key] as List? ?? const [])
      .map((value) => value.toString())
      .toList(growable: false);
  final aggregations = config['value_aggregations'];
  final normalizedAggregations = aggregations is Map
      ? Map<String, String>.fromEntries(
          aggregations.entries
              .map((entry) => MapEntry('${entry.key}', '${entry.value}'))
              .toList()
            ..sort((left, right) => left.key.compareTo(right.key)),
        )
      : const <String, String>{};
  return jsonEncode({
    'table': widget['tabla_origen']?.toString() ?? '',
    'dimension': widget['campo_dimension']?.toString() ?? '',
    'value': widget['campo_valor']?.toString() ?? '',
    'series': widget['campo_serie']?.toString() ?? '',
    'aggregation': widget['agregacion']?.toString() ?? '',
    'dimensions': values('dimensions'),
    'values': values('values'),
    'values_y2': values('values_y2'),
    'value_aggregations': normalizedAggregations,
  });
}

Map<String, dynamic> metricsVerifiedWidgetSave({
  required List<Map<String, dynamic>> before,
  required List<Map<String, dynamic>> after,
  required Map<String, dynamic> expected,
  required String savedId,
}) {
  final requestedId = expected['id']?.toString();
  if (requestedId != null && requestedId.isNotEmpty && requestedId != savedId) {
    throw StateError('Supabase guardó un gráfico distinto del solicitado.');
  }
  final saved = after.where((row) => '${row['id']}' == savedId).toList();
  if (saved.length != 1) {
    throw StateError('No se pudo verificar el gráfico guardado por su ID.');
  }
  if (metricsWidgetDataSignature(saved.single) !=
      metricsWidgetDataSignature(expected)) {
    throw StateError('Supabase no conservó los ejes del gráfico editado.');
  }
  final beforeById = {
    for (final row in before) '${row['id']}': metricsWidgetDataSignature(row),
  };
  for (final row in after) {
    final id = '${row['id']}';
    if (id == savedId || !beforeById.containsKey(id)) continue;
    if (beforeById[id] != metricsWidgetDataSignature(row)) {
      throw StateError('La edición modificó los ejes de otro gráfico ($id).');
    }
  }
  return saved.single;
}
