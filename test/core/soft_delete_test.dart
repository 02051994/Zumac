import 'package:appgt_offline_subtables/core/services/soft_delete.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reconoce eliminado con tipos y nombres de columna heredados', () {
    expect(isSoftDeletedAppgtRow({'eliminado': true}), isTrue);
    expect(isSoftDeletedAppgtRow({'ELIMINADO': 1}), isTrue);
    expect(isSoftDeletedAppgtRow({'Eliminado': 'sí'}), isTrue);
    expect(isSoftDeletedAppgtRow({'eliminado': false}), isFalse);
  });

  test('deleted_at no nulo también excluye la fila', () {
    expect(
      isSoftDeletedAppgtRow({'deleted_at': '2026-09-07T10:00:00Z'}),
      isTrue,
    );
    expect(isSoftDeletedAppgtRow({'DELETED AT': null}), isFalse);
    expect(isSoftDeletedAppgtRow({'deleted_at': 'NULL'}), isFalse);
  });

  test('filtra sin alterar el orden de filas vigentes', () {
    final rows = withoutSoftDeletedAppgtRows([
      {'id': 1, 'eliminado': false},
      {'id': 2, 'eliminado': true},
      {'id': 3},
    ]);
    expect(rows.map((row) => row['id']), [1, 3]);
  });
}
