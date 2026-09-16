import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lectura e importación requieren acción explícita por formato', () {
    final sql = File(
      'supabase/migrations/202609160066_format_operation_permission_guard.sql',
    ).readAsStringSync();
    expect(sql, contains('appgt_select_format_records_internal_v1'));
    expect(sql, contains('fn_importar_registros_sin_duplicados_internal_v1'));
    expect(sql, contains('coalesce(p.can_view,false)'));
    expect(sql, contains('coalesce(p.can_import,false)'));
    expect(sql, contains('p.empresa_id=v_empresa_id'));
    expect(sql, contains('p.formato=p_format_id'));
    expect(sql, isNot(contains('appgt_puede_gestionar_configuracion')));
  });

  test('Gestor solicita cambios Metrics y Admin los resuelve', () {
    final sql = File(
      'supabase/migrations/202609160067_metrics_approval_workflow.sql',
    ).readAsStringSync();
    expect(sql, contains('SOLICITUDES_METRICS_APPGT'));
    expect(sql, contains("v_rol='ADMIN'"));
    expect(sql, contains("'solicitado',true"));
    expect(sql, contains('appgt_listar_solicitudes_metrics_v1'));
    expect(sql, contains('appgt_resolver_solicitud_metrics_v1'));
    expect(sql, contains("estado='SOLICITADO'"));
    expect(sql, contains("then 'APROBADO' else 'RECHAZADO'"));
  });

  test('las implementaciones internas no son ejecutables por clientes', () {
    final sql = File(
      'supabase/migrations/202609160067_metrics_approval_workflow.sql',
    ).readAsStringSync();
    expect(
      sql,
      contains('from public,anon,authenticated,service_role'),
    );
    expect(sql, contains('appgt_ejecutar_mutacion_metrics_internal_v1'));
    expect(sql, contains('appgt_mutar_o_solicitar_metrics_v1'));
  });
}
