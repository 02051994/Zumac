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
}) {
  if (geometryWidth <= 0) return 1;
  return math.min(1, math.max(0, viewportWidth) / geometryWidth);
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
