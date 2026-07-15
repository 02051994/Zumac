import 'package:appgt_offline_subtables/features/configuration_admin/format_structure_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> validPayload() => {
        'codigo': 'INSPECCION_CAMPO',
        'nombre': 'Inspección de campo',
        'modulo_id': 'MODULO_INSPECCIONES',
        'tipo_formato': 'SIMPLE',
        'tablas': [
          {
            'codigo': 'INSPECCION_TABLA',
            'nombre': 'Inspecciones',
            'tabla_destino': 'INSPECCION_REGISTROS',
            'campos': [
              {
                'codigo': 'INSPECCION_ALTURA',
                'campo': 'ALTURA',
                'etiqueta': 'Altura',
                'tipo_ui': 'number',
                'matrices': [
                  {
                    'codigo': 'FORMULA_ALTURA',
                    'nombre': 'Fórmula de altura',
                    'clase_matriz': 'FORMULA',
                    'expresion': '1+1',
                  }
                ],
              }
            ],
          }
        ],
      };

  test('acepta una estructura completa con tabla, campo y fórmula', () {
    expect(validateFormatStructurePayload(validPayload()), isEmpty);
  });

  test('rechaza tablas sin campos y relaciones detalle incompletas', () {
    final payload = validPayload();
    payload['tablas'] = [
      {
        'codigo': 'DETALLE_TABLA',
        'nombre': 'Detalle',
        'tabla_destino': 'DETALLE_REGISTROS',
        'es_detalle': true,
        'campos': <dynamic>[],
      }
    ];

    final errors = validateFormatStructurePayload(payload).join(' ');
    expect(errors, contains('tabla padre'));
    expect(errors, contains('al menos un campo'));
  });

  test('rechaza códigos duplicados y fórmulas vacías', () {
    final payload = validPayload();
    final table = (payload['tablas'] as List).first as Map<String, dynamic>;
    final fields = table['campos'] as List;
    fields.add({
      'codigo': 'INSPECCION_ALTURA',
      'campo': 'ALTURA_2',
      'etiqueta': 'Altura 2',
      'tipo_ui': 'formula',
      'formula_funcion': '',
      'matrices': <dynamic>[],
    });

    final errors = validateFormatStructurePayload(payload).join(' ');
    expect(errors, contains('código técnico está repetido'));
    expect(errors, contains('necesita una fórmula'));
  });

  test('la copia de plantilla genera tabla independiente y conserva reglas',
      () {
    final structure = formatStructureFromTemplate({
      'formato': {
        'nombre': 'Original',
        'definicion': {
          'modulo_id': 'MODULO_A',
          'tabla_destino': 'TABLA_ORIGINAL',
        },
      },
      'tablas': [
        {
          'codigo': 'TABLA_DEF',
          'entidad_origen_id': 'TABLA_DEF',
          'nombre': 'Tabla original',
          'definicion': {'tabla_destino': 'TABLA_ORIGINAL'},
        }
      ],
      'campos': [
        {
          'codigo': 'CAMPO_DEF',
          'entidad_origen_id': 'CAMPO_DEF',
          'padre_origen_id': 'TABLA_DEF',
          'nombre': 'Valor',
          'definicion': {
            'tabla_destino': 'TABLA_ORIGINAL',
            'campo': 'VALOR',
            'etiqueta': 'Valor',
            'tipo_ui': 'number',
          },
        }
      ],
      'matrices': [
        {
          'codigo': 'MATRIZ_DEF',
          'padre_origen_id': 'CAMPO_DEF',
          'nombre': 'Regla',
          'definicion': {
            'clase_matriz': 'FORMULA',
            'expresion': '2+2',
          },
        }
      ],
    });

    final table = (structure['tablas'] as List).first as Map;
    final field = (table['campos'] as List).first as Map;
    expect(table['tabla_destino'], 'COPIA_TABLA_ORIGINAL');
    expect((field['matrices'] as List), hasLength(1));
  });

  test('normaliza clases plurales de matrices heredadas', () {
    final structure = formatStructureFromTemplate({
      'formato': {
        'nombre': 'Original',
        'definicion': {'modulo_id': 'MODULO_A'},
      },
      'tablas': [
        {
          'entidad_origen_id': 'TABLA_A',
          'nombre': 'Tabla A',
          'definicion': {'tabla_destino': 'TABLA_A'},
        }
      ],
      'campos': [
        {
          'entidad_origen_id': 'CAMPO_A',
          'padre_origen_id': 'TABLA_A',
          'nombre': 'Campo A',
          'definicion': {
            'tabla_destino': 'TABLA_A',
            'campo': 'VALOR',
            'etiqueta': 'Valor',
            'tipo_ui': 'formula',
            'formula_funcion': '1+1',
          },
        }
      ],
      'matrices': [
        {
          'codigo': 'FORMULA_A',
          'padre_origen_id': 'CAMPO_A',
          'nombre': 'Fórmula A',
          'definicion': {
            'clase_matriz': 'FORMULAS',
            'expresion': '1+1',
          },
        }
      ],
    });

    final table = (structure['tablas'] as List).first as Map;
    final field = (table['campos'] as List).first as Map;
    final matrix = (field['matrices'] as List).first as Map;
    expect(matrix['clase_matriz'], 'FORMULA');
  });
}
