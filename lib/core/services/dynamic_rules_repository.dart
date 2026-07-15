import 'local_db.dart';

class DynamicRulesRepository {
  DynamicRulesRepository({LocalDb? localDb})
      : _local = localDb ?? LocalDb.instance;

  final LocalDb _local;

  static const dropdownSource = 'MATRIZ_DROPDOWNS_APPGT';
  static const validationSource = 'MATRIZ_VALIDACIONES_APPGT';
  static const conditionSource = 'MATRIZ_CONDICIONES_APPGT';
  static const formulaSource = 'MATRIZ_FORMULAS_APPGT';

  Future<List<Map<String, dynamic>>> applyToFields(
    List<Map<String, dynamic>> fields, {
    String? empresaId,
  }) async {
    final sources = await Future.wait([
      _local.matrixPayloads(dropdownSource, empresaId: empresaId),
      _local.matrixPayloads(validationSource, empresaId: empresaId),
      _local.matrixPayloads(conditionSource, empresaId: empresaId),
      _local.matrixPayloads(formulaSource, empresaId: empresaId),
    ]);
    return overlayFields(
      fields,
      dropdowns: sources[0],
      validations: sources[1],
      conditions: sources[2],
      formulas: sources[3],
    );
  }

  static List<Map<String, dynamic>> overlayFields(
    List<Map<String, dynamic>> fields, {
    List<Map<String, dynamic>> dropdowns = const [],
    List<Map<String, dynamic>> validations = const [],
    List<Map<String, dynamic>> conditions = const [],
    List<Map<String, dynamic>> formulas = const [],
  }) {
    final dropdownByField = _groupActiveByField(dropdowns);
    final validationsByField = _groupActiveByField(validations);
    final conditionsByField = _groupActiveByField(conditions);
    final formulasByField = _groupActiveByField(formulas);

    return fields.map((source) {
      final field = Map<String, dynamic>.from(source);
      final id = field['id']?.toString().trim() ?? '';
      if (id.isEmpty) return field;

      final dropdown = _firstOrdered(dropdownByField[id]);
      final dropdownFieldId = dropdown?['campo_origen_id']?.toString().trim();
      if (dropdownFieldId != null && dropdownFieldId.isNotEmpty) {
        field['id_campo_dropdown'] = dropdownFieldId;
      }

      final formula = _firstOrdered(formulasByField[id]);
      final expression = formula?['expresion']?.toString().trim();
      if (expression != null && expression.isNotEmpty) {
        field['formula_funcion'] = expression;
      }

      for (final validation in validationsByField[id] ?? const []) {
        final type =
            validation['tipo_validacion']?.toString().trim().toUpperCase() ??
                '';
        final rule = validation['expresion']?.toString().trim() ?? '';
        if (type == 'REQUERIDO') field['requerido'] = true;
        if (type == 'RANGO' && rule.isNotEmpty) field['rango_valor'] = rule;
      }

      final condition = _firstOrdered(conditionsByField[id]);
      final conditionExpression = condition?['expresion']?.toString().trim();
      if (conditionExpression != null && conditionExpression.isNotEmpty) {
        field['formato_condicional_campo'] = conditionExpression;
      }
      return field;
    }).toList();
  }

  static Map<String, List<Map<String, dynamic>>> _groupActiveByField(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      if (!_active(row['activo']) || _deleted(row['deleted_at'])) continue;
      final fieldId = row['campo_id']?.toString().trim() ?? '';
      if (fieldId.isEmpty) continue;
      grouped.putIfAbsent(fieldId, () => []).add(row);
    }
    return grouped;
  }

  static Map<String, dynamic>? _firstOrdered(
    List<Map<String, dynamic>>? rows,
  ) {
    if (rows == null || rows.isEmpty) return null;
    final ordered = List<Map<String, dynamic>>.from(rows)
      ..sort((a, b) => _asInt(a['orden']).compareTo(_asInt(b['orden'])));
    return ordered.first;
  }

  static int _asInt(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;

  static bool _active(dynamic value) {
    if (value == null) return true;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == 't' || normalized == '1';
  }

  static bool _deleted(dynamic value) {
    if (value == null) return false;
    final normalized = value.toString().trim();
    return normalized.isNotEmpty && normalized.toLowerCase() != 'null';
  }
}
