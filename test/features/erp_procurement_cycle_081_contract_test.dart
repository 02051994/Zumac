import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202610120081_procurement_receipts_tax_status_and_numbering.sql',
  ).readAsStringSync();
  final receiptContextMigration = File(
    'supabase/migrations/202610120082_purchase_receipt_internal_context.sql',
  ).readAsStringSync();
  final purchaseOrder = File(
    'lib/features/form_runner/erp_purchase_order_page.dart',
  ).readAsStringSync();
  final workflow = File(
    'lib/features/form_runner/erp_workflow_pages.dart',
  ).readAsStringSync();

  test('normaliza correlativos empresariales desde 100001', () {
    for (final prefix in const [
      'PRV-',
      'SP-',
      'OC-',
      'VD-',
      'I-',
      'CL-',
      'PV-',
      'EX-',
    ]) {
      expect(migration, contains("'$prefix'"));
    }
    expect(migration, contains('greatest(100001'));
  });

  test('OC persiste IGV configurable y descuento monetario por línea', () {
    expect(migration, contains('add column if not exists igv_porcentaje'));
    expect(migration, contains('add column if not exists importe'));
    expect(migration, contains('add column if not exists descuento'));
    expect(migration, contains('new.impuesto:=case when'));
    expect(purchaseOrder, contains("'p_igv_porcentaje': _igvPercentage"));
    expect(purchaseOrder, contains("label: 'Descuento'"));
    expect(purchaseOrder, contains("label: '%IGV'"));
    expect(purchaseOrder, contains('IGV incluido'));
  });

  test('consolida recepción en estado y habilita SIN OC pendiente', () {
    expect(migration, contains('drop column if exists estado_de_recibido'));
    expect(migration, contains("'RECIBIDO PARCIAL','RECIBIDO'"));
    expect(migration, contains('erp_confirmar_ingreso_almacen_v1'));
    expect(migration, contains("then 'PENDIENTE' else 'CONFIRMADO'"));
    expect(receiptContextMigration,
        contains("set_config('appgt.erp_receipt_context','1',true)"));
    expect(workflow, contains("value: 'SIN OC'"));
    expect(workflow, contains('_addReceiptArticle'));
  });

  test('los cuatro formatos usan la tabla con encabezado y guías fijas', () {
    expect(purchaseOrder, contains('ErpStickyDetailTable<_PurchaseOrderLine>'));
    expect(
      RegExp(r'ErpStickyDetailTable<').allMatches(workflow).length,
      greaterThanOrEqualTo(3),
    );
  });
}
