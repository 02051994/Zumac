import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202609240069_contract_status_timeout_and_attendance_guard.sql',
  ).readAsStringSync();
  final attendanceUi = File('lib/features/form_runner/special_form_pages.dart')
      .readAsStringSync();
  final recordsUi = File(
    'lib/features/formats/desktop_format_records_page.dart',
  ).readAsStringSync();
  final formRunner = File(
    'lib/features/form_runner/form_runner_page.dart',
  ).readAsStringSync();
  final syncService =
      File('lib/core/services/sync_service.dart').readAsStringSync();

  test('deriva Activo o pendiente y preserva el Cese manual', () {
    expect(migration, contains("v_status = 'CESE'"));
    expect(migration, contains("then 'pendiente renovación'"));
    expect(migration, contains("else 'Activo'"));
    expect(
      migration,
      contains('appgt_05_normalizar_estado_contractual_zumac_trigger'),
    );
  });

  test('evita recalcular toda la historia al editar un trabajador', () {
    expect(
      migration,
      contains('v_dni, current_date, current_date'),
    );
    expect(migration, isNot(contains('v_desde := v_inicio')));
    expect(migration, contains("set_config('appgt.bulk_import', 'on', true)"));
  });

  test('asistencia valida rango contractual y sanciones bloqueantes', () {
    expect(attendanceUi, contains('contractStart'));
    expect(attendanceUi, contains("'bloquea_asistencia'"));
    expect(migration, contains('GH_SANCIONES_PERSONAL_APPGT'));
    expect(migration, contains("position('bloquea_asistencia'"));
  });

  test('la edición refresca inmediatamente la caché local', () {
    expect(recordsUi, contains('FormRunnerPage'));
    expect(formRunner, contains('editPrimaryKeyColumn'));
    expect(syncService, contains('.select()'));
    expect(syncService, contains('.maybeSingle()'));
    expect(syncService, contains('upsertMatrixRowPayload'));
  });
}
