import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202610130085_erp_approval_detail_transition_context.sql',
  ).readAsStringSync();

  test('la propagación de aprobación usa un contexto interno acotado', () {
    expect(
      migration,
      contains("set_config('appgt.erp_approval_transition_context','1',true)"),
    );
    expect(migration, contains('v_previous_context'));
    expect(migration, contains('appgt_erp_propagar_estado_detalle_v1'));
    expect(migration, contains('pg_trigger_depth()>1'));
  });

  test('el bloqueo manual continúa activo después de aprobar', () {
    expect(migration, contains('v_approval_transition'));
    expect(
      migration,
      contains("v_estado not in ('PENDIENTE','REVISADO')"),
    );
    expect(
      migration,
      contains('No se pueden modificar detalles cuando el documento está'),
    );
  });

  test('solicitudes, órdenes y vales verifican la transición completa', () {
    for (final table in const [
      'ERP_SOLICITUDES_COMPRA_APPGT',
      'ERP_ORDENES_COMPRA_APPGT',
      'ERP_VALES_DESPACHO_APPGT',
    ]) {
      expect(migration, contains(table));
    }
    expect(migration, contains('savepoint appgt_approval_transition_test'));
    expect(migration, contains("set estado='APROBADO'"));
    expect(
      migration,
      contains('rollback to savepoint appgt_approval_transition_test'),
    );
  });
}
