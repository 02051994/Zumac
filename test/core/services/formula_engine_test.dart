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
}
