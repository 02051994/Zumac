import 'package:appgt_offline_subtables/features/users/permission_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ADMIN delega roles no administrativos', () {
    expect(
      delegableRoles('ADMIN'),
      ['GESTOR', 'COLABORADOR', 'VISUALIZADOR'],
    );
    expect(canManageTargetRole('ADMIN', 'ADMIN'), isFalse);
    expect(canManageTargetRole('ADMIN', 'GESTOR'), isTrue);
  });

  test('GESTOR solo administra colaboradores y visualizadores', () {
    expect(delegableRoles('GESTOR'), ['COLABORADOR', 'VISUALIZADOR']);
    expect(canManageTargetRole('GESTOR', 'GESTOR'), isFalse);
    expect(canManageTargetRole('GESTOR', 'COLABORADOR'), isTrue);
    expect(canManageTargetRole('GESTOR', null), isTrue);
  });

  test('VISUALIZADOR queda limitado a lectura', () {
    const requested = PermissionActions(
      view: true,
      insert: true,
      update: true,
      delete: true,
      export: true,
      import: true,
      review: true,
      approve: true,
    );
    final result = requested.normalizedForRole('VISUALIZADOR');
    expect(result.view, isTrue);
    expect(result.enabledCount, 1);
  });

  test('COLABORADOR no recibe revisión ni aprobación', () {
    const requested = PermissionActions(review: true, approve: true);
    final result = requested.normalizedForRole('COLABORADOR');
    expect(result.review, isFalse);
    expect(result.approve, isFalse);
  });

  test('una delegación no excede el alcance del gestor', () {
    const requested = PermissionActions(
      view: true,
      insert: true,
      update: true,
      export: true,
    );
    const ceiling = PermissionActions(view: true, insert: true);
    final result = requested.boundedBy(ceiling);
    expect(result.view, isTrue);
    expect(result.insert, isTrue);
    expect(result.update, isFalse);
    expect(result.export, isFalse);
  });

  test('serializa y recupera acciones independientes por estado', () {
    final permissions = PermissionActions.fromMap({
      'permisos_estado': '''{
        "PENDIENTE":{"view":true,"create":true,"update":true,"delete":false},
        "DESPACHADO":{"view":true,"create":false,"update":false,"delete":false}
      }''',
    });

    expect(permissions.workflowStates['PENDIENTE']!.create, isTrue);
    expect(permissions.workflowStates['PENDIENTE']!.delete, isFalse);
    expect(permissions.workflowStates['DESPACHADO']!.view, isTrue);

    final payload = permissions.toMap(formatId: 'vale_despacho');
    expect(payload['can_insert'], isTrue);
    expect(
      (payload['permisos_estado'] as Map)['DESPACHADO']['update'],
      isFalse,
    );
  });

  test('el techo global limita cada acción de los estados', () {
    const requested = PermissionActions(
      workflowStates: {
        'APROBADO': WorkflowStateActions(
          view: true,
          create: true,
          update: true,
          delete: true,
        ),
      },
    );
    const ceiling = PermissionActions(view: true, update: true);

    final result = requested.boundedBy(ceiling).workflowStates['APROBADO']!;
    expect(result.view, isTrue);
    expect(result.update, isTrue);
    expect(result.create, isFalse);
    expect(result.delete, isFalse);
  });
}
