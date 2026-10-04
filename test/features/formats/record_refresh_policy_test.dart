import 'package:flutter_test/flutter_test.dart';

import 'package:appgt_offline_subtables/features/formats/record_refresh_policy.dart';

void main() {
  test('un refresco silencioso vacío no borra registros visibles', () {
    expect(
      shouldApplySilentRecordRefresh(
        visibleRowCount: 16,
        refreshedRowCount: 0,
      ),
      isFalse,
    );
  });

  test('un refresco silencioso con filas sí actualiza la grilla', () {
    expect(
      shouldApplySilentRecordRefresh(
        visibleRowCount: 16,
        refreshedRowCount: 18,
      ),
      isTrue,
    );
  });

  test('una grilla inicialmente vacía puede aceptar una respuesta vacía', () {
    expect(
      shouldApplySilentRecordRefresh(
        visibleRowCount: 0,
        refreshedRowCount: 0,
      ),
      isTrue,
    );
  });
}
