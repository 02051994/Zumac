import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202610100078_warehouse_receipt_details_and_approval_tracking.sql',
  ).readAsStringSync();
  final approvalCleanup = File(
    'supabase/migrations/202610100079_purchase_request_approval_state_cleanup.sql',
  ).readAsStringSync();
  final workflow = File('lib/features/form_runner/erp_workflow_pages.dart')
      .readAsStringSync();
  final purchaseOrder = File(
    'lib/features/form_runner/erp_purchase_order_page.dart',
  ).readAsStringSync();
  final records = File(
    'lib/features/formats/desktop_format_records_page.dart',
  ).readAsStringSync();

  test('publica ingresos y detalles de almacén y vales con identidad activa',
      () {
    expect(migration, contains("nombre='Ingresos en Almacén'"));
    expect(migration, contains("'Detalle de Ingresos en Almacén'"));
    expect(migration, contains("'Detalle de Vales de Despacho'"));
    expect(migration, contains('appgt_erp_identidad_ingreso_v1'));
    expect(migration, contains("new.usuario:=v_identidad->>'solicitante'"));
    expect(workflow, contains("_textInput(_user, 'Usuario', false"));
  });

  test('mantiene la recepción por documento y por artículo', () {
    expect(migration, contains('appgt_erp_refrescar_cabeceras_v2'));
    expect(migration, contains('appgt_erp_refrescar_trazabilidad_linea_v1'));
    expect(migration, contains("'RECIBIDO PARCIAL'"));
    expect(migration, contains('fecha_aprobacion_oc'));
    expect(migration, contains('fecha_solicitada_usuario'));
    expect(migration, contains('cantidad_recibida=least'));
  });

  test('separa el estado de aprobación del estado de recepción', () {
    expect(
      approvalCleanup,
      contains("estado in ('PENDIENTE','REVISADO','APROBADO','ANULADO')"),
    );
    expect(approvalCleanup, contains("set estado='APROBADO'"));
    expect(
      approvalCleanup,
      isNot(contains("set estado=case when v_completed")),
    );
    expect(approvalCleanup, contains('appgt_erp_refrescar_cabeceras_v2'));
  });

  test('solicitud usa detalle tabular, precio y cierre idempotente', () {
    expect(workflow, contains("DataColumn(label: Text('Precio unitario'))"));
    expect(workflow, contains("DataColumn(label: Text('Total'))"));
    expect(workflow, contains("'p_centro_costo': null"));
    expect(workflow, contains('if (_saving || !_editable'));
    expect(workflow, contains('Navigator.of(context).pop()'));
    expect(migration, contains('generated always as'));
  });

  test('orden muestra cálculos completos y permite quitar filas', () {
    for (final label in const [
      'Cant. solicitada',
      'Precio unitario',
      'Descuento %',
      'Importe',
      'Subtotal',
      'Impuesto',
      'Total',
      'Otros Dctos.',
      'Fecha de entrega programada',
    ]) {
      expect(purchaseOrder, contains(label));
    }
    expect(purchaseOrder, contains('void _removeLine(int index)'));
    expect(purchaseOrder,
        contains('double get discountAmount => grossAmount - amount'));
  });

  test('los scrollbars de detalles usan controladores explícitos', () {
    expect(records, contains('controller: horizontalController'));
    expect(records, contains('controller: verticalController'));
    expect(records, contains('ScrollbarOrientation.bottom'));
    expect(workflow, contains('controller: _detailHorizontalController'));
    expect(purchaseOrder, contains('controller: _detailHorizontalController'));
  });
}
