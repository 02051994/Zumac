import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('los cuatro flujos ERP usan estado como fuente operativa', () {
    final source = File(
      'lib/features/formats/desktop_format_records_page.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/202610130084_erp_estado_single_source_of_truth.sql',
    ).readAsStringSync();

    for (final table in const [
      'ERP_SOLICITUDES_COMPRA_APPGT',
      'ERP_ORDENES_COMPRA_APPGT',
      'ERP_INGRESOS_ALMACEN_APPGT',
      'ERP_VALES_DESPACHO_APPGT',
    ]) {
      expect(source, contains(table));
      expect(migration, contains(table));
    }
    expect(source, contains("const ['ESTADO', 'ESTADO_APROBACION']"));
    expect(migration, contains('appgt_erp_estado_unico_v1'));
    expect(migration, contains('before insert or update of estado'));
  });
}
