import 'configuration_entity_spec.dart';

const supportedFormatTypes = <String>{
  'SIMPLE',
  'CABECERA_DETALLE',
  'MATRIZ',
  'FLUJO',
  'INSPECCION',
  'ENCUESTA',
  'REGISTRO_MASIVO',
  'CONSULTA',
  'REPORTE',
  'ESPECIAL',
};

const supportedMatrixClasses = <String>{
  'DROPDOWN',
  'VALIDACION',
  'CONDICION',
  'FORMULA',
};

final RegExp _technicalCode = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{1,62}$');

List<String> validateFormatStructurePayload(Map<String, dynamic> payload) {
  final errors = <String>[];
  String text(Map<String, dynamic> map, String key) =>
      map[key]?.toString().trim() ?? '';

  if (text(payload, 'nombre').isEmpty) {
    errors.add('El formato necesita un nombre visible.');
  }
  if (!_technicalCode.hasMatch(text(payload, 'codigo'))) {
    errors.add(
        'No se pudo preparar el formato con ese nombre. Pruebe con otro nombre.');
  }
  if (text(payload, 'modulo_id').isEmpty) {
    errors.add('Seleccione el módulo donde se publicará el formato.');
  }
  if (!supportedFormatTypes
      .contains(text(payload, 'tipo_formato').toUpperCase())) {
    errors.add('Seleccione un tipo de formato válido.');
  }

  final rawTables = payload['tablas'];
  if (rawTables is! List || rawTables.isEmpty) {
    errors.add('Agregue al menos una tabla al formato.');
    return errors;
  }

  final tableCodes = <String>{};
  final physicalTables = <String>{};
  final tableNames = <String>{};
  for (var tableIndex = 0; tableIndex < rawTables.length; tableIndex++) {
    final rawTable = rawTables[tableIndex];
    if (rawTable is! Map) {
      errors.add('La tabla ${tableIndex + 1} no tiene una definición válida.');
      continue;
    }
    final table = Map<String, dynamic>.from(rawTable);
    final prefix = 'Tabla ${tableIndex + 1}';
    final code = text(table, 'codigo');
    final physicalName = text(table, 'tabla_destino');
    if (!_technicalCode.hasMatch(code)) {
      errors.add(
          '$prefix: no se pudo generar su identificador. Cambie el nombre.');
    } else if (!tableCodes.add(code.toUpperCase())) {
      errors.add('$prefix: el nombre está repetido, por favor elija otro.');
    }
    final visibleTableName = text(table, 'nombre');
    if (visibleTableName.isEmpty) {
      errors.add('$prefix: indique el nombre visible.');
    } else if (!tableNames.add(visibleTableName.toUpperCase())) {
      errors.add(
          '$prefix: "$visibleTableName" ya existe, por favor elija otro nombre.');
    }
    if (!_technicalCode.hasMatch(physicalName)) {
      errors
          .add('$prefix: no se pudo preparar con ese nombre. Pruebe con otro.');
    } else if (!physicalTables.add(physicalName.toUpperCase())) {
      errors.add('$prefix: el nombre está repetido, por favor elija otro.');
    }
    if (table['es_detalle'] == true &&
        (text(table, 'tabla_padre').isEmpty ||
            text(table, 'campo_fk_hijo').isEmpty)) {
      errors.add('$prefix: una tabla detalle requiere tabla padre y campo FK.');
    }

    final rawFields = table['campos'];
    if (rawFields is! List || rawFields.isEmpty) {
      errors.add('$prefix: agregue al menos un campo.');
      continue;
    }
    final fieldCodes = <String>{};
    final physicalFields = <String>{};
    for (var fieldIndex = 0; fieldIndex < rawFields.length; fieldIndex++) {
      final rawField = rawFields[fieldIndex];
      if (rawField is! Map) {
        errors.add('$prefix, campo ${fieldIndex + 1}: definición inválida.');
        continue;
      }
      final field = Map<String, dynamic>.from(rawField);
      final fieldPrefix = '$prefix, campo ${fieldIndex + 1}';
      final code = text(field, 'codigo');
      final physicalName = text(field, 'campo');
      if (!_technicalCode.hasMatch(code)) {
        errors.add(
            '$fieldPrefix: no se pudo generar su identificador. Cambie el nombre.');
      } else if (!fieldCodes.add(code.toUpperCase())) {
        errors.add(
            '$fieldPrefix: el nombre está repetido, por favor elija otro.');
      }
      if (physicalName.isEmpty || physicalName.length > 63) {
        errors.add('$fieldPrefix: cambie el nombre por uno más corto.');
      } else if (!physicalFields.add(physicalName.toUpperCase())) {
        errors.add(
            '$fieldPrefix: el nombre está repetido, por favor elija otro.');
      }
      if (text(field, 'etiqueta').isEmpty) {
        errors.add('$fieldPrefix: indique la etiqueta visible.');
      }
      final uiType = text(field, 'tipo_ui').toLowerCase();
      if (uiType.isEmpty) {
        errors.add('$fieldPrefix: seleccione el tipo de control.');
      }
      if ((uiType == 'formula' || uiType == 'lookup') &&
          text(field, 'formula_funcion').isEmpty) {
        errors.add('$fieldPrefix: el campo calculado necesita una fórmula.');
      }

      final rawMatrices = field['matrices'];
      final hasDropdownMatrix = rawMatrices is List &&
          rawMatrices.whereType<Map>().any((matrix) =>
              text(Map<String, dynamic>.from(matrix), 'clase_matriz')
                  .toUpperCase() ==
              'DROPDOWN');
      if ((uiType == 'dropdown' || uiType == 'multiselect') &&
          text(field, 'id_campo_dropdown').isEmpty &&
          !hasDropdownMatrix) {
        errors.add(
            '$fieldPrefix: seleccione la tabla y el campo que alimentarán la lista.');
      }
      if (rawMatrices is! List) continue;
      final matrixCodes = <String>{};
      for (var matrixIndex = 0;
          matrixIndex < rawMatrices.length;
          matrixIndex++) {
        final rawMatrix = rawMatrices[matrixIndex];
        if (rawMatrix is! Map) {
          errors.add(
              '$fieldPrefix, matriz ${matrixIndex + 1}: definición inválida.');
          continue;
        }
        final matrix = Map<String, dynamic>.from(rawMatrix);
        final matrixPrefix = '$fieldPrefix, matriz ${matrixIndex + 1}';
        final code = text(matrix, 'codigo');
        final matrixClass = text(matrix, 'clase_matriz').toUpperCase();
        if (!_technicalCode.hasMatch(code)) {
          errors.add('$matrixPrefix: no se pudo preparar con ese nombre.');
        } else if (!matrixCodes.add(code.toUpperCase())) {
          errors.add(
              '$matrixPrefix: el nombre está repetido, por favor elija otro.');
        }
        if (text(matrix, 'nombre').isEmpty) {
          errors.add('$matrixPrefix: indique el nombre visible.');
        }
        if (!supportedMatrixClasses.contains(matrixClass)) {
          errors.add('$matrixPrefix: seleccione una clase válida.');
        }
        if (matrixClass == 'FORMULA' && text(matrix, 'expresion').isEmpty) {
          errors.add('$matrixPrefix: la fórmula necesita una expresión.');
        }
      }
    }
  }
  return errors;
}

Map<String, dynamic> formatStructureFromTemplate(
  Map<String, dynamic> fullTemplate,
) {
  Map<String, dynamic> map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  List<Map<String, dynamic>> maps(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
      : <Map<String, dynamic>>[];

  final formatRow = map(fullTemplate['formato']);
  final formatDefinition = map(formatRow['definicion']);
  final tableRows = maps(fullTemplate['tablas']);
  final fieldRows = maps(fullTemplate['campos']);
  final matrixRows = maps(fullTemplate['matrices']);

  final tables = <Map<String, dynamic>>[];
  for (var tableIndex = 0; tableIndex < tableRows.length; tableIndex++) {
    final tableRow = tableRows[tableIndex];
    final definition = map(tableRow['definicion']);
    final tableOrigin = tableRow['entidad_origen_id']?.toString();
    final physicalTable = definition['tabla_destino']?.toString();
    final fields = <Map<String, dynamic>>[];
    final relatedFields = fieldRows.where((row) {
      final fieldDefinition = map(row['definicion']);
      const reserved = {
        'id',
        'id_local',
        'empresa_id',
        'created_by',
        'created_at',
        'updated_at',
        'deleted_at',
        'eliminado',
        'estado_sync',
      };
      final belongs = row['padre_origen_id']?.toString() == tableOrigin ||
          (physicalTable != null &&
              fieldDefinition['tabla_destino']?.toString() == physicalTable);
      return belongs &&
          !reserved.contains(
            fieldDefinition['campo']?.toString().toLowerCase(),
          );
    }).toList();

    for (var fieldIndex = 0; fieldIndex < relatedFields.length; fieldIndex++) {
      final fieldRow = relatedFields[fieldIndex];
      final fieldDefinition = map(fieldRow['definicion']);
      final fieldOrigin = fieldRow['entidad_origen_id']?.toString();
      final matrices = matrixRows
          .where((row) => row['padre_origen_id']?.toString() == fieldOrigin)
          .map((row) {
        final definition = map(row['definicion']);
        final rawClass =
            definition['clase_matriz']?.toString().toUpperCase() ?? '';
        final matrixClass = const {
              'DROPDOWNS': 'DROPDOWN',
              'VALIDACIONES': 'VALIDACION',
              'CONDICIONES': 'CONDICION',
              'FORMULAS': 'FORMULA',
            }[rawClass] ??
            rawClass;
        return <String, dynamic>{
          ...definition,
          'codigo':
              'COPIA_M${tableIndex + 1}_${fieldIndex + 1}_${row['codigo']}',
          'nombre': row['nombre']?.toString() ?? 'Matriz',
          'clase_matriz': matrixClass,
        };
      }).toList();
      fields.add({
        ...fieldDefinition,
        'codigo': 'COPIA_F${tableIndex + 1}_${fieldIndex + 1}',
        'nombre': fieldRow['nombre']?.toString() ??
            fieldDefinition['etiqueta']?.toString() ??
            'Campo',
        'matrices': matrices,
      });
    }

    tables.add({
      ...definition,
      'codigo': 'COPIA_T${tableIndex + 1}',
      'nombre': tableRow['nombre']?.toString() ?? 'Tabla ${tableIndex + 1}',
      'tabla_destino': 'COPIA_${physicalTable ?? 'TABLA_${tableIndex + 1}'}',
      'crear_tabla_fisica': true,
      'campos': fields,
    });
  }

  return {
    ...formatDefinition,
    'nombre': 'Copia de ${formatRow['nombre'] ?? 'formato'}',
    'codigo': '',
    'tabla_destino': tables.isEmpty ? '' : tables.first['tabla_destino'],
    'tipo_formato': formatDefinition['tipo_formato'] ?? 'SIMPLE',
    'tablas': tables,
  };
}

Map<String, dynamic> rekeyClonedFormatChildren(
  Map<String, dynamic> payload,
) {
  final root = normalizeConfigurationCode(payload['codigo']?.toString() ?? '');
  if (root.isEmpty) return payload;
  final result = Map<String, dynamic>.from(payload);
  final tables = <Map<String, dynamic>>[];
  final rawTables = payload['tablas'];
  if (rawTables is! List) return result;
  for (var tableIndex = 0; tableIndex < rawTables.length; tableIndex++) {
    final table = Map<String, dynamic>.from(rawTables[tableIndex] as Map);
    if (table['codigo']?.toString().startsWith('COPIA_') == true) {
      table['codigo'] = '${root}_T${tableIndex + 1}';
    }
    if (table['tabla_destino']?.toString().startsWith('COPIA_') == true) {
      table['tabla_destino'] = '${root}_T${tableIndex + 1}';
    }
    final rawFields = table['campos'];
    final fields = <Map<String, dynamic>>[];
    if (rawFields is List) {
      for (var fieldIndex = 0; fieldIndex < rawFields.length; fieldIndex++) {
        final field = Map<String, dynamic>.from(rawFields[fieldIndex] as Map);
        if (field['codigo']?.toString().startsWith('COPIA_') == true) {
          field['codigo'] = '${root}_T${tableIndex + 1}_F${fieldIndex + 1}';
        }
        final rawMatrices = field['matrices'];
        final matrices = <Map<String, dynamic>>[];
        if (rawMatrices is List) {
          for (var matrixIndex = 0;
              matrixIndex < rawMatrices.length;
              matrixIndex++) {
            final matrix =
                Map<String, dynamic>.from(rawMatrices[matrixIndex] as Map);
            if (matrix['codigo']?.toString().startsWith('COPIA_') == true) {
              matrix['codigo'] =
                  '${root}_T${tableIndex + 1}_F${fieldIndex + 1}_M${matrixIndex + 1}';
            }
            matrices.add(matrix);
          }
        }
        field['matrices'] = matrices;
        fields.add(field);
      }
    }
    table['campos'] = fields;
    tables.add(table);
  }
  result['tablas'] = tables;
  if ((result['tabla_destino']?.toString() ?? '').startsWith('COPIA_')) {
    result['tabla_destino'] =
        tables.isEmpty ? '' : tables.first['tabla_destino'];
  }
  return result;
}
