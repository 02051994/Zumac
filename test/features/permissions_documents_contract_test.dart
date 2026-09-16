import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la migracion conecta ausencias, PDF privado y campos tecnicos', () {
    final sql = File(
      'supabase/migrations/'
      '202608140046_permissions_documents_and_online_runtime.sql',
    ).readAsStringSync();

    expect(sql, contains('"MATRIZ_TIPOS_AUSENCIA_APPGT"'));
    expect(sql, contains('documento_requerido'));
    expect(sql, contains("MATRIZ_TIPOS_AUSENCIA_APPGT.nombre"));
    expect(sql, contains("'permisos-licencias'"));
    expect(sql, contains('visible=false, visible_tabla=false'));
    expect(sql, contains('Debe adjuntar el documento de sustento'));
  });
}
