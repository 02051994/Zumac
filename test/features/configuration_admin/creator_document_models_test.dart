import 'package:appgt_offline_subtables/features/configuration_admin/creator_document_models.dart';
import 'package:appgt_offline_subtables/features/configuration_admin/format_structure_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CreatorDocumentAnalysis', () {
    test('interpreta campos, filas y calidad estructurada', () {
      final analysis = CreatorDocumentAnalysis.fromJson({
        'document_quality': {
          'acceptable': true,
          'message': 'Legible',
          'issues': <String>[],
        },
        'title': 'Registro de drenaje',
        'description': 'Control de drenaje por sector',
        'document_type': 'FORMATO',
        'recommended_header_row': 3,
        'preview_rows': [
          ['Registro de drenaje'],
          ['Campaña 2026'],
          ['Fecha', 'Vareidad', 'Drenaje %'],
        ],
        'fields': [
          {
            'original_label': 'Vareidad',
            'suggested_label': 'Variedad',
            'column_index': 1,
            'table_name': 'Drenaje',
            'section': 'Cultivo',
            'ui_type': 'dropdown',
            'required': true,
            'confidence': .72,
            'options': ['Arra 15', 'Sweet Globe'],
            'notes': 'Corrección ortográfica sugerida',
          },
        ],
        'relationships': <Map<String, dynamic>>[],
        'warnings': ['Confirmar variedad'],
        'questions_for_user': ['¿Vareidad significa Variedad?'],
      });

      expect(analysis.headerRow, 3);
      expect(analysis.fields.single.originalLabel, 'Vareidad');
      expect(analysis.fields.single.correctedLabel, 'Variedad');
      expect(analysis.fields.single.uiType, 'dropdown');
      expect(analysis.qualityAcceptable, isTrue);
    });
  });

  group('CreatorFormatPayloadBuilder', () {
    test('crea un borrador válido y conserva revisión, fila y layouts', () {
      final payload = const CreatorFormatPayloadBuilder().build(
        title: 'Registro de drenaje',
        description: 'Seguimiento técnico',
        rubroId: 'agroexportacion',
        moduleId: 'riego_modulo',
        fields: const [
          CreatorDetectedField(
            originalLabel: 'Vareidad',
            correctedLabel: 'Variedad',
            columnIndex: 1,
            tableName: 'Drenaje',
            section: 'Cultivo',
            uiType: 'dropdown',
            required: true,
            confidence: .72,
            options: ['Arra 15', 'Sweet Globe'],
          ),
          CreatorDetectedField(
            originalLabel: 'Drenaje %',
            correctedLabel: 'Porcentaje de drenaje',
            columnIndex: 2,
            tableName: 'Drenaje',
            section: 'Mediciones',
            uiType: 'percent',
          ),
        ],
        formLayout: CreatorFormLayout.sections,
        recordLayout: CreatorRecordLayout.cards,
        headerRow: 3,
        sourceName: 'drenaje.pdf',
        importId: 'import-1',
      );

      expect(validateFormatStructurePayload(payload), isEmpty);
      expect(payload['estado_revision_ia'], 'GENERADA_IA');
      expect(payload['layout_formulario'], 'SECCIONES');
      expect(payload['layout_registros'], 'TARJETAS');
      expect(
        (payload['origen_creador'] as Map)['fila_encabezados'],
        3,
      );
      final table = (payload['tablas'] as List).single as Map;
      final fields = table['campos'] as List;
      expect((fields.first as Map)['etiqueta'], 'Variedad');
      expect(((fields.first as Map)['matrices'] as List), isNotEmpty);
    });

    test('genera relaciones cabecera detalle para varias tablas', () {
      final payload = const CreatorFormatPayloadBuilder().build(
        title: 'Inspección de campo',
        description: '',
        rubroId: 'agro',
        moduleId: 'calidad',
        fields: const [
          CreatorDetectedField(
            originalLabel: 'Fecha',
            correctedLabel: 'Fecha',
            columnIndex: 0,
            tableName: 'Inspección',
            uiType: 'date',
          ),
          CreatorDetectedField(
            originalLabel: 'Defecto',
            correctedLabel: 'Defecto',
            columnIndex: 1,
            tableName: 'Detalle de defectos',
          ),
        ],
        formLayout: CreatorFormLayout.vertical,
        recordLayout: CreatorRecordLayout.table,
        headerRow: 1,
        sourceName: 'inspeccion.jpg',
      );

      final tables = payload['tablas'] as List;
      expect(tables, hasLength(2));
      expect((tables.first as Map)['es_cabecera'], isTrue);
      expect((tables.last as Map)['es_detalle'], isTrue);
      expect((tables.last as Map)['tabla_padre'],
          (tables.first as Map)['tabla_destino']);
      expect(validateFormatStructurePayload(payload), isEmpty);
    });
  });
}
