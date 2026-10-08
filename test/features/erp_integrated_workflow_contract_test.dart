import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202610070075_integrated_erp_workflows.sql',
  ).readAsStringSync();

  test('la migracion es atomica y contiene los documentos integrados', () {
    expect(RegExp(r'^begin;', multiLine: true).allMatches(migration),
        hasLength(1));
    expect(
      RegExp(r'^commit;', multiLine: true).allMatches(migration),
      hasLength(1),
    );
    expect(migration.trimRight().endsWith('commit;'), isTrue);

    for (final table in const [
      'ERP_SOLICITUDES_COMPRA_DETALLE_APPGT',
      'ERP_INGRESOS_ALMACEN_APPGT',
      'ERP_INGRESOS_ALMACEN_DETALLE_APPGT',
      'ERP_VALES_DESPACHO_APPGT',
      'ERP_VALES_DESPACHO_DETALLE_APPGT',
      'ERP_EVENTOS_INTEGRACION_APPGT',
    ]) {
      expect(migration, contains(table));
    }
  });

  test('ingreso por OC controla saldos y estados de despacho', () {
    expect(migration, contains('erp_ordenes_pendientes_ingreso_v1'));
    expect(migration, contains("o.numero||' - '||coalesce(o.proveedor_ruc"));
    expect(migration, contains('erp_registrar_ingreso_compra_v1'));
    expect(migration,
        contains("then 'DESPACHADO' else 'DESPACHADO PARCIALMENTE'"));
    expect(
        migration, contains('cantidad_despachada=cantidad_despachada+v_qty'));
    expect(migration, contains("'INGRESO_COMPRA',1,v_qty"));
  });

  test('vale exige aprobacion y descuenta stock al despachar', () {
    expect(migration, contains('Vale no tiene aprobacion'));
    expect(
      migration,
      contains("old.estado='APROBADO' and new.estado='DESPACHADO'"),
    );
    expect(migration, contains('appgt_erp_aplicar_despacho_vale_v1'));
    expect(migration, contains("'SALIDA_VALE'"));
    expect(migration,
        contains("'PENDIENTE','REVISADO','APROBADO','DESPACHADO','ANULADO'"));
  });

  test('incluye permisos por estado, catalogo y ejemplos solicitados', () {
    expect(migration, contains('permisos_estado jsonb'));
    expect(migration, contains('appgt_guardar_permisos_estado_formatos_v1'));
    expect(migration, contains('generate_series(1,80)'));
    expect(migration, contains('generate_series(1,30)'));
    expect(migration, contains('generate_series(1,10)'));
    expect(migration, contains('SP-DEMO-SANIDAD-001'));
    expect(migration, contains('SP-DEMO-PRODUCCION-001'));
    expect(migration, contains('OC-DEMO-SANIDAD-001'));
    expect(migration, contains('OC-DEMO-PRODUCCION-001'));
  });

  test('los tres formularios compuestos quedan registrados', () {
    expect(migration, contains("'erp_solicitud_pedido'"));
    expect(migration, contains("'erp_ingreso_compra'"));
    expect(migration, contains("'erp_vale_despacho'"));
    expect(migration, contains('erp_guardar_solicitud_pedido_v1'));
    expect(migration, contains('erp_guardar_vale_despacho_v1'));
  });
}
