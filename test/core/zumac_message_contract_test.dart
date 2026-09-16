import 'dart:io';

import 'package:appgt_offline_subtables/core/widgets/zumac_scaffold_messenger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('los errores tecnicos se convierten a lenguaje natural', () {
    expect(
      naturalizeZumacMessage(
        'No se pudo generar: Unsupported operation: Platform._version',
      ),
      isNot(contains('Platform._version')),
    );
    expect(
      naturalizeZumacMessage('PostgrestException(code: 23505)'),
      isNot(contains('PostgrestException')),
    );
    expect(
      naturalizeZumacMessage(
        "PostgrestException(message: Could not find the 'estado_registro' column of 'GH_PERMISOS_LICENCIAS_APPGT' in the schema cache, code: PGRST204)",
      ),
      allOf(contains('estado_registro'), isNot(contains('PostgrestException'))),
    );
    expect(
      naturalizeZumacMessage(
        'PostgrestException(message: administrator permission required, code: 42501)',
      ),
      contains('administradora'),
    );
  });

  test('todas las llamadas antiguas usan el mensajero modal de ZUMAC', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      if (file.path.endsWith('zumac_scaffold_messenger.dart')) continue;
      final source = file.readAsStringSync();
      if (!source.contains('ScaffoldMessenger.of')) continue;
      expect(
        source,
        contains("hide ScaffoldMessenger"),
        reason: file.path,
      );
      expect(
        source,
        contains("zumac_scaffold_messenger.dart"),
        reason: file.path,
      );
    }
  });
}
