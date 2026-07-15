import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:appgt_offline_subtables/core/services/local_db.dart';

void main() {
  sqfliteFfiInit();

  late Database database;
  late LocalDb local;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('''
      create table sync_items(
        id text primary key,
        name text not null
      )
    ''');
    local = LocalDb.forTesting(database);
  });

  tearDown(() => database.close());

  test('un delta actualiza y elimina sin borrar filas no incluidas', () async {
    await local.replaceTable('sync_items', [
      {'id': 'a', 'name': 'A'},
      {'id': 'b', 'name': 'B'},
      {'id': 'c', 'name': 'C'},
    ]);

    await local.applyTableDelta(
      'sync_items',
      [
        {'id': 'b', 'name': 'B2'},
      ],
      deletedIds: const ['c'],
    );

    final rows = await database.query('sync_items', orderBy: 'id');
    expect(rows, [
      {'id': 'a', 'name': 'A'},
      {'id': 'b', 'name': 'B2'},
    ]);
  });

  test('un snapshot fallido conserva la fotografia anterior', () async {
    await local.replaceTable('sync_items', [
      {'id': 'estable', 'name': 'Configuracion valida'},
    ]);

    await expectLater(
      local.replaceTable('sync_items', [
        {'id': 'invalido'},
      ]),
      throwsA(anything),
    );

    final rows = await database.query('sync_items');
    expect(rows, [
      {'id': 'estable', 'name': 'Configuracion valida'},
    ]);
  });
}
