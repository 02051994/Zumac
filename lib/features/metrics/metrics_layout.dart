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
