import 'package:flutter_test/flutter_test.dart';

import 'package:appgt_offline_subtables/core/services/login_error_message.dart';

void main() {
  test('no convierte una instruccion de autenticacion en falta de internet',
      () {
    final message = friendlyLoginError(
      Exception(
        'Por seguridad, los datos se actualizan despues de iniciar sesion. Ingresa con internet para continuar.',
      ),
    );

    expect(message, startsWith('Por seguridad'));
    expect(message,
        isNot('Se necesita conexión a internet para actualizar datos.'));
  });

  test('una falla real de transporte identifica a Supabase', () {
    final message = friendlyLoginError(
      Exception('SocketException: Failed host lookup'),
    );

    expect(message, contains('no pudo contactar a Supabase'));
    expect(message, contains('Failed host lookup'));
  });
}
