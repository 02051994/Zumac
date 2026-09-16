/// Devuelve el valor de una columna sin depender de mayúsculas, espacios o
/// guiones. Las tablas heredadas de APPGT no usan una convención única.
dynamic appgtRowValue(
  Map<String, dynamic> row,
  String column,
) {
  final wanted = _normalizeAppgtColumn(column);
  for (final entry in row.entries) {
    if (_normalizeAppgtColumn(entry.key) == wanted) return entry.value;
  }
  return null;
}

bool appgtBooleanValue(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().trim().toLowerCase();
  if (const {'true', 't', '1', 'si', 'sí', 'yes', 'x'}.contains(text)) {
    return true;
  }
  if (const {'false', 'f', '0', 'no', ''}.contains(text)) return false;
  return fallback;
}

/// Regla única de borrado lógico para datos de formularios y catálogos.
///
/// Algunas tablas antiguas solo tienen `eliminado`; otras registran además
/// `deleted_at`. Cualquiera de los dos indicadores impide mostrar la fila.
bool isSoftDeletedAppgtRow(Map<String, dynamic> row) {
  if (appgtBooleanValue(appgtRowValue(row, 'eliminado'))) return true;
  final deletedAt = appgtRowValue(row, 'deleted_at')?.toString().trim() ?? '';
  return deletedAt.isNotEmpty && deletedAt.toLowerCase() != 'null';
}

List<Map<String, dynamic>> withoutSoftDeletedAppgtRows(
  Iterable<Map<String, dynamic>> rows,
) =>
    rows.where((row) => !isSoftDeletedAppgtRow(row)).toList(growable: false);

String _normalizeAppgtColumn(String value) => value
    .trim()
    .toUpperCase()
    .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
    .replaceAll(RegExp(r'_+'), '_')
    .replaceAll(RegExp(r'^_|_$'), '');
