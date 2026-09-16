import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/'
    '202609070047_formula_types_soft_delete_and_profile_membership.sql',
  ).readAsStringSync();

  test('el tipo físico de una fórmula depende de tipo y no de tipo_ui', () {
    expect(migration, contains("v_tipo text := lower"));
    expect(migration, contains("when v_tipo in ("));
    expect(migration, contains("then 'numeric'"));
    expect(migration, contains("when v_tipo = 'date' then 'date'"));
    expect(migration, contains("when v_tipo in ('boolean', 'bool')"));
    expect(migration, contains("when v_tipo in ('json', 'jsonb')"));
  });

  test('limpia valores vacíos no textuales antes de jsonb_populate_record', () {
    expect(migration, contains("v_type_category <> 'S'"));
    expect(migration, contains('jsonb_populate_record'));
  });

  test('crea y repara membresías sin reemplazar roles existentes', () {
    expect(
      migration,
      contains('appgt_sincronizar_membresia_desde_perfil'),
    );
    expect(migration, contains('join auth.users u on u.id = p.id'));
    expect(migration, isNot(contains('set rol = excluded.rol')));
  });
}
