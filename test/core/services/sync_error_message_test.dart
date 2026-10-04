import 'package:flutter_test/flutter_test.dart';

import 'package:appgt_offline_subtables/core/services/sync_error_message.dart';

void main() {
  test('sesion ausente no se presenta como usuario incorrecto', () {
    final message = friendlySyncError(
      Exception('No se pudo actualizar datos sin credenciales.'),
    );

    expect(message, contains('sesión en línea venció'));
    expect(message, isNot(contains('Usuario o contraseña incorrectos')));
  });

  test('solo una falla real de login se presenta como credenciales incorrectas',
      () {
    expect(
      friendlySyncError(Exception('Invalid login credentials')),
      'Usuario o contraseña incorrectos.',
    );
  });

  test('un error técnico que menciona password conserva su detalle', () {
    final message = friendlySyncError(
      Exception("Could not find the 'password' column in the schema cache"),
    );

    expect(message, contains('campo «password»'));
    expect(message, isNot(contains('Usuario o contraseña incorrectos')));
  });
}
