import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la migracion aplica sustento exacto y aprobacion en dos pasos', () {
    final sql = File(
      'supabase/migrations/'
      '202609290070_hr_two_step_approval_and_documents.sql',
    ).readAsStringSync();

    for (final type in const [
      'DESCANSOMEDICO',
      'LICENCIADEMATERNIDAD',
      'LICENCIADEPATERNIDAD',
      'LICENCIAPORFALLECIMIENTO',
    ]) {
      expect(sql, contains("'$type'"));
    }
    expect(sql, contains('new.documento_sustento := null'));
    expect(sql, contains('GH_SANCIONES_PERSONAL_APPGT'));
    expect(sql, contains('documento_generado'));
    expect(sql, contains("new.estado := 'BORRADOR'"));
    expect(sql, contains("else 'VIGENTE'"));
    expect(sql, contains('ESTADO_APROBACION'));
    expect(sql, contains('activo=false, eliminado=true'));
    expect(sql, contains("'documentos-laborales'"));
    expect(sql, contains('public=false'));
    expect(sql, contains("'APROBAR'"));
    expect(sql, contains("'GH_PERMISOS_LICENCIAS_APPGT','APROBAR'"));
    expect(sql, contains("'GH_SANCIONES_PERSONAL_APPGT','APROBAR'"));
    expect(sql, contains('appgt_documento_laboral_guard_v1'));
  });

  test('planilla solo contabiliza permisos formalmente aprobados', () {
    final sql = File(
      'supabase/migrations/'
      '202609100063_payroll_slip_v2_weekly_rest_and_compensation.sql',
    ).readAsStringSync();

    expect(
      sql,
      contains("q.estado='APROBADO' and q.\"ESTADO_APROBACION\"='APROBADO'"),
    );
    expect(sql, contains('coalesce(q.con_goce_haber, false)'));
  });

  test('el flujo nuevo exige revision y aplica el despido al contrato', () {
    final sql = File(
      'supabase/migrations/'
      '202610070074_hr_tareo_scanner_workflow.sql',
    ).readAsStringSync();

    expect(sql, contains("old.\"ESTADO_APROBACION\" <> 'PENDIENTE'"));
    expect(sql, contains("old.\"ESTADO_APROBACION\" <> 'REVISADO'"));
    expect(sql, contains("'REVISAR'"));
    expect(sql, contains("'APROBAR'"));
    expect(sql, contains('Sanciones/Despido de Personal'));
    expect(sql, contains('"Fecha fin de contrato" = new.fecha_despido'));
    expect(sql, contains('cel_representante_legal'));
    expect(sql, contains('domicilio_fiscal'));
  });
}
