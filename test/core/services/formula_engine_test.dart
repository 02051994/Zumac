import 'package:appgt_offline_subtables/core/services/formula_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FormulaEngine LISTA', () {
    final engine = FormulaEngine(
      fields: const [],
      matrixRowsByTable: const {
        'labores': [
          {'cultivo': 'Palta', 'activo': 'Sí'},
          {'cultivo': 'Uva', 'activo': 'No'},
          {'cultivo': 'Palta', 'activo': 'Sí'},
        ],
      },
      getValue: (_) => null,
    );

    test('trae valores únicos de una tabla', () {
      expect(
          engine.evaluateToText("LISTA('labores', 'cultivo')"), 'Palta, Uva');
    });

    test('puede filtrar la lista por otra columna', () {
      expect(
        engine.evaluateToText(
          "LISTA('labores', 'cultivo', 'activo', 'Sí')",
        ),
        'Palta',
      );
    });
  });

  test('BUSCAR y LISTA ignoran filas eliminadas lógicamente', () {
    final engine = FormulaEngine(
      fields: const [],
      matrixRowsByTable: const {
        'personal': [
          {'dni': '123', 'nombre': 'Registro eliminado', 'eliminado': true},
          {'dni': '123', 'nombre': 'Registro vigente', 'eliminado': false},
          {'dni': '456', 'nombre': 'Otro vigente', 'eliminado': false},
        ],
      },
      getValue: (_) => null,
    );

    expect(
      engine.evaluateToText("BUSCAR('personal', 'dni', '123', 'nombre')"),
      'Registro vigente',
    );
    expect(
      engine.evaluateToText("LISTA('personal', 'dni')"),
      '123, 456',
    );
  });
}
