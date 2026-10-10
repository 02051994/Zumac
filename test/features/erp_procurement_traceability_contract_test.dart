import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202610100077_procurement_traceability_and_identity.sql',
  ).readAsStringSync();

  test('usa RUC canónico y correlativos requeridos', () {
    expect(migration, contains('add column if not exists ruc text'));
    expect(
        migration, contains("new.codigo:=v_next::text||'-'||btrim(new.ruc)"));
    expect(migration, contains("new.numero:='SP-'||v_next::text"));
    expect(migration, contains("new.numero:='OC-'||v_next::text"));
    expect(migration, contains('greatest(10001'));
    expect(migration, isNot(contains('p.numero_documento')));
  });

  test('identidad de solicitud y vale proviene del usuario autenticado', () {
    expect(migration, contains('erp_identidad_usuario_actual_v1'));
    expect(migration, contains('where p.id=auth.uid()'));
    expect(migration, contains("'solicitante',concat_ws('-'"));
    expect(migration, contains("'usuario_nombre',concat_ws('-'"));
    expect(migration, contains('new.solicitante:=old.solicitante'));
    expect(migration, contains('new.usuario_dni:=old.usuario_dni'));
  });

  test('trazabilidad enlaza solicitud, orden e ingresos por línea', () {
    for (final field in const [
      'almacen_destino_codigo',
      'cantidad_recibida',
      'fecha_solicitada',
      'fecha_oc_aprobada',
      'fecha_recibida',
    ]) {
      expect(migration, contains(field));
    }
    expect(migration, contains('appgt_erp_refrescar_trazabilidad_linea_v1'));
    expect(migration, contains("i.estado='CONFIRMADO'"));
    expect(migration, contains('cantidad_recibida=least'));
  });

  test('centro de costo del vale se conserva por artículo', () {
    expect(
      migration,
      contains(
        'ERP_VALES_DESPACHO_DETALLE_APPGT"\n  add column if not exists centro_costo',
      ),
    );
    expect(migration, contains("v_item->>'centro_costo'"));
    expect(
      migration,
      contains(
          "case when new.tipo_destino='DIRECTO' then v_center else null end"),
    );
  });
}
