import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202610100080_procurement_images_receipt_documents_and_voucher_audit.sql',
  ).readAsStringSync();
  final workflow = File('lib/features/form_runner/erp_workflow_pages.dart')
      .readAsStringSync();
  final purchaseOrder = File(
    'lib/features/form_runner/erp_purchase_order_page.dart',
  ).readAsStringSync();

  test('la migración es atómica y agrega cabecera y foto de solicitud', () {
    expect(RegExp(r'^begin;', multiLine: true).allMatches(migration),
        hasLength(1));
    expect(RegExp(r'^commit;', multiLine: true).allMatches(migration),
        hasLength(1));
    expect(migration.trimRight().endsWith('commit;'), isTrue);
    expect(migration, contains('proveedor_codigo text'));
    expect(migration, contains('almacen_codigo text'));
    expect(migration, contains('foto_url text'));
    expect(migration, contains('erp_guardar_solicitud_pedido_v2'));
    expect(migration, contains("values ('erp-articulos','erp-articulos'"));
  });

  test('el ingreso conserva documento, almacén y saldo de cada parcial', () {
    expect(migration, contains('tipo_documento text'));
    expect(migration,
        contains("tipo_documento in ('GUIA DE REMISION','FACTURA')"));
    expect(migration, contains('erp_registrar_ingreso_compra_v2'));
    expect(migration, contains('cantidad_pendiente numeric(20,6)'));
    expect(
      migration,
      contains('greatest(cantidad_pendiente_antes-cantidad_recibida,0)'),
    );
    expect(migration, contains('fecha_vencimiento,almacen_codigo'));
  });

  test('los actores legibles del vale se completan por transición', () {
    expect(migration, contains('aprobado_por_nombre text'));
    expect(migration, contains('despachado_por_nombre text'));
    expect(migration, contains('anulado_por_nombre text'));
    expect(migration, contains("if new.estado='APROBADO'"));
    expect(migration, contains("if new.estado='DESPACHADO'"));
    expect(migration, contains("if new.estado='ANULADO'"));
    expect(migration, contains("lower(campo)='cantidad_despachada'"));
  });

  test('los formularios muestran cabeceras, foto y resumen simplificado', () {
    expect(workflow, contains("'erp_guardar_solicitud_pedido_v2'"));
    expect(workflow, contains("label: 'Proveedor'"));
    expect(workflow, contains("label: 'Almacén'"));
    expect(workflow, contains("DataColumn(label: Text('Foto'))"));
    expect(workflow, contains("'erp_registrar_ingreso_compra_v2'"));
    expect(workflow, contains("_textInput(_guide, 'Número de documento'"));
    expect(purchaseOrder, contains("line('Descuento total'"));
    expect(purchaseOrder, contains("line('Impuesto (IGV 18%)'"));
    expect(purchaseOrder, isNot(contains("line('Dctos. por ítem'")));
  });
}
