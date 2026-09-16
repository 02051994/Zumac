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
}
