import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202610130083_approval_execution_and_stock_guards.sql',
  ).readAsStringSync();
  final records = File(
    'lib/features/formats/desktop_format_records_page.dart',
  ).readAsStringSync();

  test('confirmar ingreso valida permisos, detalle y postcondición', () {
    expect(migration, contains("'PENDIENTE','approve'"));
    expect(migration, contains("'PENDIENTE','update'"));
    expect(
      migration,
      contains('No se puede confirmar un ingreso sin artículos o insumos.'),
    );
    expect(migration, contains("'estado','CONFIRMADO'"));
    expect(migration, contains("'movimientos_creados',v_detail_count"));
  });

  test('anular ingreso revierte movimientos y acepta edición o borrado', () {
    expect(migration, contains("v_header.estado,'delete'"));
    expect(migration, contains("v_header.estado,'update'"));
    expect(migration, contains("set estado='ANULADO'"));
    expect(migration, contains('get diagnostics v_movements_reversed'));
    expect(
      migration,
      contains("'movimientos_revertidos',v_movements_reversed"),
    );
  });

  test('los vales validan permisos y transiciones antes de afectar stock', () {
    expect(migration, contains('erp_cambiar_estado_vale_despacho_v1'));
    expect(
      migration,
      contains(
        "v_row.estado='APROBADO' and v_next in ('DESPACHADO','ANULADO')",
      ),
    );
    expect(migration, contains('Transición de vale no permitida'));
    expect(migration, contains("v_row.estado,'update'"));
    expect(migration, contains('no generó movimientos de stock'));
    expect(migration,
        contains('no tiene movimientos de stock activos para revertir'));
    expect(migration, contains('no revirtió todos los movimientos de stock'));
  });

  test('la interfaz verifica que cada transición realmente persistió', () {
    expect(records, contains("result['actualizado'] != true"));
    expect(records, contains("result['confirmado'] != true"));
    expect(records, contains("result['anulado'] != true"));
    expect(records, contains('.select(column)'));
    expect(records, contains('La base de datos no confirmó el estado'));
  });
}
