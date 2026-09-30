import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final platform =
      File('lib/core/platform/app_platform.dart').readAsStringSync();
  final modules =
      File('lib/features/modules/modules_page.dart').readAsStringSync();
  final specialForms = File(
    'lib/features/form_runner/special_form_pages.dart',
  ).readAsStringSync();
  final desktopRecords = File(
    'lib/features/formats/desktop_format_records_page.dart',
  ).readAsStringSync();
  final syncService =
      File('lib/core/services/sync_service.dart').readAsStringSync();
  final permissions = File(
    'lib/features/users/governed_permissions_page.dart',
  ).readAsStringSync();
  final toolMigration = File(
    'supabase/migrations/202609300071_workspace_tool_permissions_and_attendance_roster.sql',
  ).readAsStringSync();

  test('la web conserva el layout de escritorio aunque reduzca su ancho', () {
    expect(platform, contains('if (kIsWeb) return true;'));
    expect(
      platform,
      contains(
        'return isDesktopRuntime && MediaQuery.sizeOf(context).width >= 900;',
      ),
    );
  });

  test('el APK no limita sus secciones a un listado fijo', () {
    expect(modules, isNot(contains("fingerprint.contains('OPERACIONES')")));
    expect(
      modules,
      contains('el catálogo y los permisos cacheados del usuario'),
    );
  });

  test('la asistencia solo se captura en móvil y usa vista de trabajadores',
      () {
    expect(specialForms, contains('if (!isMobileCaptureRuntime)'));
    expect(
      specialForms,
      contains('Marcación disponible solo en el APK'),
    );
    expect(desktopRecords, contains('_attendanceCaptureBlocked'));
    expect(
      desktopRecords,
      contains('canInsert = insertAllowed && !attendanceCaptureBlocked;'),
    );
    expect(
      desktopRecords,
      contains('canImport = importAllowed && !attendanceCaptureBlocked;'),
    );
    expect(
      desktopRecords,
      contains('canDelete = deleteAllowed && !attendanceCaptureBlocked;'),
    );
    expect(specialForms, contains("'Ver Trabajadores'"));
    expect(specialForms, contains("'Buscar trabajador'"));
    expect(specialForms, contains("text: 'DNI'"));
    expect(specialForms, contains('ScrollbarOrientation.bottom'));
    expect(specialForms, contains("table == 'GT_ASISTENCIA_PERSONAL'"));
    expect(modules, contains('appGtSpecialFormatFallback(format)'));
    expect(specialForms, contains('appgt_personal_asistencia_v1'));
    expect(specialForms, contains('_workerName(w)'));
    expect(specialForms, isNot(contains("substring(2)}'")));
    expect(specialForms, contains('Widget _attendanceForm()'));
    expect(specialForms, isNot(contains('Widget _headerCard()')));
  });

  test('las herramientas de inicio usan permisos gobernados', () {
    expect(modules, contains('loadCurrentToolAccess()'));
    expect(modules, contains('_canUseWorkspaceTool'));
    expect(permissions, contains('Herramientas de la pantalla principal'));
    expect(permissions, contains('saveToolPermissions'));
    expect(toolMigration, contains('appgt_guardar_permisos_herramientas_v1'));
    expect(toolMigration, contains("v_actor_role = 'GESTOR'"));
  });

  test('la cola conserva ediciones y recupera sincronizaciones interrumpidas',
      () {
    expect(syncService, contains("'CONDUCTOR': 'CONDUCTOR'"));
    expect(syncService, contains("'DNI_CONDUCTOR': 'DNI_CONDUCTOR'"));
    expect(syncService, contains('recoverInterruptedSyncRecords'));
    expect(specialForms, contains("'CONDUCTOR',"));
    expect(modules, contains('Quedan \${outstandingRows.length} pendientes'));
  });

  test('el tareo integra horas, observación y trabajadores en una vista', () {
    expect(specialForms, isNot(contains("label: const Text('Continuar')")));
    expect(
        specialForms, isNot(contains("label: const Text('Guardar borrador')")));
    expect(specialForms, isNot(contains("label: const Text('Cerrar tareo')")));
    expect(specialForms, contains("tooltip: 'Horas del tareo'"));
    expect(specialForms, contains("tooltip: 'Observación'"));
    expect(specialForms, contains("tooltip: 'Trabajadores agregados'"));
    expect(specialForms, contains("ValueKey('tareo-save-icon')"));
    expect(specialForms, contains("ValueKey('tareo-workers-fixed-dni')"));
    expect(specialForms, contains("child: const Text('Horas totales')"));
    expect(specialForms, isNot(contains("'Abrir tareo'")));
    expect(
      specialForms,
      contains('if (closeTareo && isOnlineFirstRuntime)'),
    );
    expect(specialForms, contains('await syncService.syncPending();'));
    expect(specialForms, contains("? 'Enviado'"));
    expect(
      specialForms,
      contains('Tareo cerrado. Sincronízalo para enviarlo.'),
    );
  });

  test('el formato móvil usa una sola cabecera azul con su título', () {
    expect(modules, contains('desktopSelectedFormat != null'));
    expect(specialForms, contains('const Color _zumacFormatBlue'));
    expect(specialForms, contains('backgroundColor: _zumacFormatBlue'));
  });
}
