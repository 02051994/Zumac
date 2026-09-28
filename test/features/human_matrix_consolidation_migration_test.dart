import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/'
    '202609240068_consolidate_human_matrices.sql',
  ).readAsStringSync();

  test('fusiona los dos módulos de matrices de Gestión Humana', () {
    expect(migration, contains("'MATRIZ GESTION HUMANA'"));
    expect(migration, contains("'GESTION HUMANA'"));
    expect(migration, contains('source_module_id'));
    expect(migration, contains('target_module_id'));
    expect(migration, contains("nombre = 'Matriz Gestión Humana'"));
  });

  test('traslada formatos, pantallas especiales y permisos', () {
    expect(migration, contains('"MATRIZ_FORMATOS_APPGT"'));
    expect(migration, contains('"MATRIZ_FORMATOS_ESPECIALES_APPGT"'));
    expect(migration, contains('"PERMISOS_DE_USUARIOS_APPGT"'));
    expect(migration, contains('"MATRIZ_VISTAS_DINAMICAS_APPGT"'));
    expect(migration, contains("f.tabla_destino = 'MATRIZ-PHOTOCHEK'"));
  });

  test('desactiva el duplicado y verifica que quede solo uno', () {
    expect(migration, contains('duplicate'));
    expect(migration, contains('having count(*) > 1'));
    expect(
      migration,
      contains('Persisten módulos duplicados de matrices de Gestión Humana'),
    );
  });
}
