/// Decide si un refresco silencioso puede reemplazar las filas visibles.
///
/// Una respuesta vacía en segundo plano no es suficiente para concluir que la
/// tabla quedó sin registros: también puede ser el resultado de una sesión aún
/// no restaurada, RLS o una consulta remota incompatible. La carga explícita de
/// la pantalla sigue siendo la fuente autoritativa para mostrar una tabla vacía.
bool shouldApplySilentRecordRefresh({
  required int visibleRowCount,
  required int refreshedRowCount,
}) {
  return visibleRowCount == 0 || refreshedRowCount > 0;
}
