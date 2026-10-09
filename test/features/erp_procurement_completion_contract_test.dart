import 'dart:io';

import 'package:appgt_offline_subtables/features/form_runner/erp_purchase_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202610090076_procurement_documents_completion.sql',
  ).readAsStringSync();

  test('la migración completa códigos, documentos y detalle embebido', () {
    expect(migration, contains("new.codigo:='Prov-'||v_next::text"));
    expect(migration, contains("new.numero:='Comp-'||v_next::text"));
    expect(migration, contains('ERP_ORDENES_COMPRA_SOLICITUDES_APPGT'));
    expect(migration, contains("'erp_orden_compra'"));
    expect(migration, contains("'pdf_url','PDF generado'"));
    expect(migration, contains('tabla_visible_app=false'));
  });

  test('el ingreso conserva trazabilidad y actualiza fecha y estados', () {
    expect(migration, contains('orden_numero,solicitud_numero,orden_linea'));
    expect(
        migration,
        contains(
            'estado=v_new_state,fecha_despachada=coalesce(p_fecha,current_date)'));
    expect(migration, contains('appgt_erp_refrescar_solicitudes_orden_v1'));
    expect(
        migration,
        contains(
            "estado in ('PENDIENTE','REVISADO','APROBADO','DESPACHADO','ANULADO')"));
  });

  test('los PDFs ERP son privados y respetan el estado real', () {
    expect(migration, contains("'documentos-erp','documentos-erp',false"));
    expect(migration, contains('erp_registrar_pdf_documento_v1'));
    expect(
        migration,
        contains(
            "v_state not in ('APROBADO','DESPACHADO PARCIALMENTE','DESPACHADO')"));
  });

  test('totales sin IGV calculan impuesto adicional', () {
    final result = ErpPurchaseTotals.calculate(
      itemAmount: 1000,
      discount: 100,
      includesIgv: false,
    );
    expect(result.importeBruto, 1000);
    expect(result.subtotal, 900);
    expect(result.impuesto, 162);
    expect(result.total, 1062);
  });

  test('totales con IGV desagregan el total usando 1.18', () {
    final result = ErpPurchaseTotals.calculate(
      itemAmount: 1180,
      discount: 0,
      includesIgv: true,
    );
    expect(result.subtotal, closeTo(1000, .000001));
    expect(result.impuesto, closeTo(180, .000001));
    expect(result.total, 1180);
    expect(result.importeBruto, closeTo(1000, .000001));
  });
}
