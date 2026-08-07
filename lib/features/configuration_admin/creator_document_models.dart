enum CreatorSourceType { camera, gallery, pdf }

enum CreatorFormLayout { vertical, twoColumns, sections, compact }

enum CreatorRecordLayout { table, cards, list }

extension CreatorFormLayoutValue on CreatorFormLayout {
  String get value => switch (this) {
        CreatorFormLayout.vertical => 'VERTICAL',
        CreatorFormLayout.twoColumns => 'DOS_COLUMNAS',
        CreatorFormLayout.sections => 'SECCIONES',
        CreatorFormLayout.compact => 'COMPACTO',
      };

  String get label => switch (this) {
        CreatorFormLayout.vertical => 'Formulario vertical',
        CreatorFormLayout.twoColumns => 'Dos columnas',
        CreatorFormLayout.sections => 'Por secciones',
        CreatorFormLayout.compact => 'Compacto',
      };
}

extension CreatorRecordLayoutValue on CreatorRecordLayout {
  String get value => switch (this) {
        CreatorRecordLayout.table => 'TABLA',
        CreatorRecordLayout.cards => 'TARJETAS',
        CreatorRecordLayout.list => 'LISTA',
      };

  String get label => switch (this) {
        CreatorRecordLayout.table => 'Tabla',
        CreatorRecordLayout.cards => 'Tarjetas',
        CreatorRecordLayout.list => 'Lista',
      };
}

class CreatorDocumentQuality {
  const CreatorDocumentQuality({
    required this.acceptable,
    required this.summary,
    this.metrics = const <String, double>{},
    this.reasons = const <String>[],
    this.warnings = const <String>[],
    this.requiresServerReview = false,
  });

  final bool acceptable;
  final String summary;
  final Map<String, double> metrics;
  final List<String> reasons;
  final List<String> warnings;
  final bool requiresServerReview;

  CreatorDocumentQuality copyWith({
    bool? acceptable,
    String? summary,
    Map<String, double>? metrics,
    List<String>? reasons,
    List<String>? warnings,
    bool? requiresServerReview,
  }) {
    return CreatorDocumentQuality(
      acceptable: acceptable ?? this.acceptable,
      summary: summary ?? this.summary,
      metrics: metrics ?? this.metrics,
      reasons: reasons ?? this.reasons,
      warnings: warnings ?? this.warnings,
      requiresServerReview: requiresServerReview ?? this.requiresServerReview,
    );
  }

  Map<String, dynamic> toJson() => {
        'aceptable': acceptable,
        'resumen': summary,
        'metricas': metrics,
        'motivos': reasons,
        'advertencias': warnings,
        'requiere_revision_servidor': requiresServerReview,
      };
}

class CreatorDetectedField {
  const CreatorDetectedField({
    required this.originalLabel,
    required this.correctedLabel,
    required this.columnIndex,
    this.tableName = 'Registros',
    this.section = 'Datos generales',
    this.uiType = 'text',
    this.required = false,
    this.visible = true,
    this.visibleInRecords = true,
    this.included = true,
    this.confidence = 1,
    this.options = const <String>[],
    this.notes = '',
  });

  final String originalLabel;
  final String correctedLabel;
  final int columnIndex;
  final String tableName;
  final String section;
  final String uiType;
  final bool required;
  final bool visible;
  final bool visibleInRecords;
  final bool included;
  final double confidence;
  final List<String> options;
  final String notes;

  factory CreatorDetectedField.fromJson(Map<String, dynamic> json) {
    final options = json['options'] is List
        ? (json['options'] as List)
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    return CreatorDetectedField(
      originalLabel: json['original_label']?.toString().trim() ?? '',
      correctedLabel: (json['suggested_label'] ?? json['original_label'])
              ?.toString()
              .trim() ??
          '',
      columnIndex: _intValue(json['column_index']),
      tableName: json['table_name']?.toString().trim().isNotEmpty == true
          ? json['table_name'].toString().trim()
          : 'Registros',
      section: json['section']?.toString().trim().isNotEmpty == true
          ? json['section'].toString().trim()
          : 'Datos generales',
      uiType: normalizeCreatorUiType(json['ui_type']?.toString()),
      required: json['required'] == true,
      confidence: _doubleValue(json['confidence'], fallback: .5),
      options: options,
      notes: json['notes']?.toString().trim() ?? '',
    );
  }

  CreatorDetectedField copyWith({
    String? originalLabel,
    String? correctedLabel,
    int? columnIndex,
    String? tableName,
    String? section,
    String? uiType,
    bool? required,
    bool? visible,
    bool? visibleInRecords,
    bool? included,
    double? confidence,
    List<String>? options,
    String? notes,
  }) {
    return CreatorDetectedField(
      originalLabel: originalLabel ?? this.originalLabel,
      correctedLabel: correctedLabel ?? this.correctedLabel,
      columnIndex: columnIndex ?? this.columnIndex,
      tableName: tableName ?? this.tableName,
      section: section ?? this.section,
      uiType: uiType ?? this.uiType,
      required: required ?? this.required,
      visible: visible ?? this.visible,
      visibleInRecords: visibleInRecords ?? this.visibleInRecords,
      included: included ?? this.included,
      confidence: confidence ?? this.confidence,
      options: options ?? this.options,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'original_label': originalLabel,
        'suggested_label': correctedLabel,
        'column_index': columnIndex,
        'table_name': tableName,
        'section': section,
        'ui_type': uiType,
        'required': required,
        'visible': visible,
        'visible_in_records': visibleInRecords,
        'included': included,
        'confidence': confidence,
        'options': options,
        'notes': notes,
      };
}

class CreatorDocumentAnalysis {
  const CreatorDocumentAnalysis({
    required this.title,
    required this.description,
    required this.headerRow,
    required this.rows,
    required this.fields,
    this.documentType = 'FORMATO',
    this.qualityAcceptable = true,
    this.qualityMessage = '',
    this.warnings = const <String>[],
    this.questions = const <String>[],
    this.relationships = const <Map<String, dynamic>>[],
  });

  final String title;
  final String description;
  final int headerRow;
  final List<List<String>> rows;
  final List<CreatorDetectedField> fields;
  final String documentType;
  final bool qualityAcceptable;
  final String qualityMessage;
  final List<String> warnings;
  final List<String> questions;
  final List<Map<String, dynamic>> relationships;

  factory CreatorDocumentAnalysis.fromJson(Map<String, dynamic> json) {
    final quality = _map(json['document_quality']);
    final rows = <List<String>>[];
    if (json['preview_rows'] is List) {
      for (final rawRow in (json['preview_rows'] as List)) {
        if (rawRow is List) {
          rows.add(rawRow.map((value) => value?.toString() ?? '').toList());
        }
      }
    }
    final fields = json['fields'] is List
        ? (json['fields'] as List)
            .whereType<Map>()
            .map((field) => CreatorDetectedField.fromJson(
                  Map<String, dynamic>.from(field),
                ))
            .toList(growable: false)
        : const <CreatorDetectedField>[];
    return CreatorDocumentAnalysis(
      title: json['title']?.toString().trim().isNotEmpty == true
          ? json['title'].toString().trim()
          : 'Formato importado',
      description: json['description']?.toString().trim() ?? '',
      documentType: json['document_type']?.toString().trim() ?? 'FORMATO',
      headerRow: _intValue(json['recommended_header_row'], fallback: 1),
      rows: rows,
      fields: fields,
      qualityAcceptable: quality['acceptable'] != false,
      qualityMessage: quality['message']?.toString().trim() ?? '',
      warnings: _strings(json['warnings']),
      questions: _strings(json['questions_for_user']),
      relationships: json['relationships'] is List
          ? (json['relationships'] as List)
              .whereType<Map>()
              .map((value) => Map<String, dynamic>.from(value))
              .toList(growable: false)
          : const <Map<String, dynamic>>[],
    );
  }
}

class CreatorFormatPayloadBuilder {
  const CreatorFormatPayloadBuilder();

  Map<String, dynamic> build({
    required String title,
    required String description,
    required String rubroId,
    required String moduleId,
    required List<CreatorDetectedField> fields,
    required CreatorFormLayout formLayout,
    required CreatorRecordLayout recordLayout,
    required int headerRow,
    required String sourceName,
    String? importId,
    List<Map<String, dynamic>> relationships = const <Map<String, dynamic>>[],
  }) {
    final included = fields.where((field) => field.included).toList();
    final formatSlug =
        creatorSlug(title).isEmpty ? 'formato_importado' : creatorSlug(title);
    final modulePrefix = _prefix(moduleId);
    final formatCode = _bounded('${modulePrefix}_id_$formatSlug');
    final grouped = <String, List<CreatorDetectedField>>{};
    for (final field in included) {
      final table =
          field.tableName.trim().isEmpty ? 'Registros' : field.tableName.trim();
      grouped.putIfAbsent(table, () => <CreatorDetectedField>[]).add(field);
    }
    if (grouped.isEmpty) grouped['Registros'] = <CreatorDetectedField>[];

    final usedTables = <String>{};
    final tables = <Map<String, dynamic>>[];
    var tableOrder = 0;
    String? firstPhysicalTable;
    for (final entry in grouped.entries) {
      tableOrder++;
      final tableSlug = _uniqueSlug(entry.key, usedTables, 'tabla_$tableOrder');
      final tableCode = _bounded('${modulePrefix}_tabla_$tableSlug');
      final physicalTable = _bounded('$modulePrefix-tabla_$tableSlug');
      firstPhysicalTable ??= physicalTable;
      final usedFields = <String>{};
      final tableFields = <Map<String, dynamic>>[];
      final seenSections = <String>{};
      for (var index = 0; index < entry.value.length; index++) {
        final field = entry.value[index];
        final visibleName = field.correctedLabel.trim();
        final fieldSlug = _uniqueSlug(
          visibleName,
          usedFields,
          'campo_${index + 1}',
        );
        final uiType = normalizeCreatorUiType(field.uiType);
        final matrixCode = _bounded('${tableCode}_campo_${fieldSlug}_opciones');
        final columns = switch (formLayout) {
          CreatorFormLayout.twoColumns => 2,
          CreatorFormLayout.compact => 3,
          _ => 1,
        };
        final gridRow = (index ~/ columns) + 1;
        final gridColumn = (index % columns) + 1;
        final section = field.section.trim().isEmpty
            ? 'Datos generales'
            : field.section.trim();
        final firstInSection = seenSections.add(section);
        tableFields.add({
          'nombre': visibleName,
          'etiqueta': visibleName,
          'codigo': _bounded('${tableCode}_campo_$fieldSlug'),
          'campo': _physicalFieldName(fieldSlug),
          'tipo': creatorDataTypeForUi(uiType),
          'tipo_ui': uiType,
          'orden': index + 1,
          'valor_default': '',
          'formula_funcion': '',
          'id_campo_dropdown': '',
          'requerido': field.required,
          'editable': true,
          'visible': field.visible,
          'visible_tabla': field.visibleInRecords,
          'activo': true,
          'seccion': section,
          'grid_fila': gridRow,
          'grid_columna': gridColumn,
          'sub_titulo':
              formLayout == CreatorFormLayout.sections && firstInSection
                  ? section
                  : '',
          'fila_sub_titulo':
              formLayout == CreatorFormLayout.sections && firstInSection
                  ? gridRow
                  : '',
          'subtitulo_alineacion': 'left',
          'subtitulo_padding': '12,10,12,10',
          'origen_ia': {
            'etiqueta_detectada': field.originalLabel,
            'confianza': field.confidence,
            'columna': field.columnIndex,
            'notas': field.notes,
          },
          'matrices': (uiType == 'dropdown' || uiType == 'multiselect') &&
                  field.options.isNotEmpty
              ? [
                  {
                    'codigo': matrixCode,
                    'nombre': 'Opciones de $visibleName',
                    'clase_matriz': 'DROPDOWN',
                    'expresion': '',
                    'valores': field.options,
                    'activo': true,
                  }
                ]
              : <Map<String, dynamic>>[],
        });
      }
      tables.add({
        'nombre': entry.key,
        'codigo': tableCode,
        'tabla_destino': physicalTable,
        'orden': tableOrder,
        'crear_tabla_fisica': true,
        'auditable': true,
        'activo': true,
        'es_cabecera': tableOrder == 1 && grouped.length > 1,
        'es_detalle': tableOrder > 1,
        'tipo_relacion': tableOrder > 1 ? 'UNO_MUCHOS' : null,
        'tabla_padre': tableOrder > 1 ? firstPhysicalTable : null,
        'campo_pk_padre': tableOrder > 1 ? 'id_local' : null,
        'campo_fk_hijo':
            tableOrder > 1 ? '${creatorSlug(firstPhysicalTable)}_id' : null,
        'modo_captura': 'FORMULARIO',
        'campos': tableFields,
      });
    }

    return {
      'codigo': formatCode,
      'nombre': title.trim(),
      'descripcion': description.trim(),
      'rubro_id': rubroId,
      'modulo_id': moduleId,
      'tipo_formato': tables.length > 1 ? 'CABECERA_DETALLE' : 'SIMPLE',
      'tabla_destino': tables.first['tabla_destino'],
      'auditable': true,
      'tabla_visible_app': true,
      'orden': 0,
      'activo': true,
      'estado_revision_ia': 'GENERADA_IA',
      'layout_formulario': formLayout.value,
      'layout_registros': recordLayout.value,
      'configuracion_layout': {
        'formulario': formLayout.value,
        'registros': recordLayout.value,
      },
      'origen_creador': {
        'tipo': 'DOCUMENTO',
        'estado': 'GENERADA_IA',
        'importacion_id': importId,
        'archivo': sourceName,
        'fila_encabezados': headerRow,
      },
      'relaciones_sugeridas_ia': relationships,
      'capacidades': {
        'offline': true,
        'workflow': false,
        'fotos': included.any((field) => field.uiType == 'photo'),
        'firma': included.any((field) => field.uiType == 'signature'),
        'geolocalizacion': false,
        'qr': included.any((field) => field.uiType == 'qr_scan'),
        'aprobaciones': false,
      },
      'flujo_estados': <String>[],
      'tablas': tables,
    };
  }
}

String normalizeCreatorUiType(String? value) {
  final normalized = value?.trim().toLowerCase() ?? '';
  const allowed = <String>{
    'text',
    'multiline',
    'number',
    'integer',
    'date',
    'time',
    'datetime',
    'checkbox',
    'switch',
    'dropdown',
    'multiselect',
    'photo',
    'signature',
    'qr_scan',
    'barcode_scan',
    'email',
    'phone',
    'url',
    'percent',
  };
  return allowed.contains(normalized) ? normalized : 'text';
}

String creatorDataTypeForUi(String uiType) => switch (uiType) {
      'number' || 'percent' => 'numeric',
      'integer' => 'integer',
      'date' => 'date',
      'time' => 'time',
      'datetime' => 'timestamptz',
      'checkbox' || 'switch' => 'boolean',
      'multiselect' => 'jsonb',
      _ => 'text',
    };

String creatorSlug(String value) {
  var result = value.trim().toLowerCase();
  const replacements = <String, String>{
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  for (final entry in replacements.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  result = result.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  result = result.replaceAll(RegExp(r'_+'), '_');
  return result.replaceAll(RegExp(r'^_+|_+$'), '');
}

String _prefix(String moduleId) {
  final slug = creatorSlug(moduleId);
  if (slug.length >= 2) return slug.substring(0, 2);
  if (slug.length == 1) return '${slug}x';
  return 'fm';
}

String _uniqueSlug(String value, Set<String> used, String fallback) {
  final base = creatorSlug(value).isEmpty ? fallback : creatorSlug(value);
  var candidate = base;
  var suffix = 2;
  while (!used.add(candidate)) {
    candidate = '${base}_${suffix++}';
  }
  return candidate;
}

String _physicalFieldName(String slug) {
  if (slug.isEmpty) return 'Campo';
  final name = '${slug[0].toUpperCase()}${slug.substring(1)}';
  return _bounded(name);
}

String _bounded(String value, [int max = 63]) =>
    value.length <= max ? value : value.substring(0, max);

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<String> _strings(dynamic value) => value is List
    ? value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false)
    : const <String>[];

int _intValue(dynamic value, {int fallback = 0}) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

double _doubleValue(dynamic value, {double fallback = 0}) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;
