import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;

  setUpAll(() {
    migration = File(
      'supabase/migrations/202609160065_company_permission_governance.sql',
    ).readAsStringSync();
  });

  test('ADMIN de empresa solo se asigna mediante service_role', () {
    expect(migration, contains('appgt_supabase_asignar_admin_empresa_v1'));
    expect(
      migration,
      contains('to service_role'),
    );
    expect(
      migration,
      contains("if v_role = 'ADMIN' then"),
    );
    expect(
      migration,
      contains('ADMIN can only be assigned from Supabase'),
    );
  });

  test('la autoridad se resuelve por membresía y empresa activa', () {
    expect(migration, contains('appgt_rol_empresa_actual'));
    expect(migration, contains('ue.empresa_id = p_empresa_id'));
    expect(migration, contains('p.empresa_id = v_empresa_id'));
    expect(migration, contains('fp.empresa_id = v_empresa_id'));
  });

  test('GESTOR no delega fuera de su propio alcance', () {
    expect(
      migration,
      contains('GESTOR cannot delegate permissions outside own scope'),
    );
    expect(
      migration,
      contains("v_existing_role not in ('COLABORADOR','VISUALIZADOR')"),
    );
    expect(migration, contains('v_own.can_import'));
    expect(migration, contains('v_own.can_export'));
  });

  test('los permisos operativos se persisten únicamente por formato', () {
    expect(migration, contains('appgt_guardar_permisos_formatos_v1'));
    expect(migration, contains("v_item->>'formato_id'"));
    expect(migration, contains('active format hierarchy not found'));
    expect(migration, isNot(contains('p_registro_id')));
  });

  test('las decisiones genéricas no elevan automáticamente al GESTOR', () {
    final start =
        migration.indexOf('create or replace function public.appgt_can_table');
    final end = migration.indexOf(
      'create or replace function public.appgt_puede_accion_tabla_v1',
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final functionBody = migration.substring(start, end);
    expect(functionBody, contains('appgt_es_admin_empresa'));
    expect(
        functionBody, isNot(contains('appgt_puede_gestionar_configuracion')));
  });

  test('toda mutación relevante incrementa la revisión de permisos', () {
    expect(migration, contains('APPGT_REVISIONES_PERMISOS_EMPRESA'));
    expect(migration, contains('appgt_incrementar_revision_permisos'));
    expect(migration, contains("'revision_permisos'"));
  });
}
