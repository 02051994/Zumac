import 'package:flutter_test/flutter_test.dart';
import 'package:appgt_offline_subtables/core/services/dynamic_rules_repository.dart';

void main() {
  test('las matrices declarativas prevalecen sobre metadatos heredados', () {
    final result = DynamicRulesRepository.overlayFields(
      [
        {
          'id': 'campo_1',
          'campo': 'TOTAL',
          'requerido': false,
          'formula_funcion': 'FORMULA_ANTIGUA',
          'rango_valor': null,
        },
      ],
      dropdowns: [
        {
          'id': 'dropdown_1',
          'campo_id': 'campo_1',
          'campo_origen_id': 'campo_catalogo',
          'activo': true,
        },
      ],
      validations: [
        {
          'id': 'required_1',
          'campo_id': 'campo_1',
          'tipo_validacion': 'REQUERIDO',
          'activo': true,
        },
        {
          'id': 'range_1',
          'campo_id': 'campo_1',
          'tipo_validacion': 'RANGO',
          'expresion': '0..100',
          'activo': true,
        },
      ],
      conditions: [
        {
          'id': 'condition_1',
          'campo_id': 'campo_1',
          'expresion': '[TOTAL] > 80',
          'activo': true,
        },
      ],
      formulas: [
        {
          'id': 'formula_1',
          'campo_id': 'campo_1',
          'expresion': '[CANTIDAD] * [PRECIO]',
          'activo': true,
        },
      ],
    );

    expect(result.single['id_campo_dropdown'], 'campo_catalogo');
    expect(result.single['requerido'], isTrue);
    expect(result.single['rango_valor'], '0..100');
    expect(result.single['formula_funcion'], '[CANTIDAD] * [PRECIO]');
    expect(result.single['formato_condicional_campo'], '[TOTAL] > 80');
  });

  test('ignora reglas inactivas o eliminadas', () {
    final result = DynamicRulesRepository.overlayFields(
      [
        {'id': 'campo_1', 'requerido': false},
      ],
      validations: [
        {
          'campo_id': 'campo_1',
          'tipo_validacion': 'REQUERIDO',
          'activo': false,
        },
        {
          'campo_id': 'campo_1',
          'tipo_validacion': 'REQUERIDO',
          'activo': true,
          'deleted_at': '2026-07-15T00:00:00Z',
        },
      ],
    );

    expect(result.single['requerido'], isFalse);
  });
}
