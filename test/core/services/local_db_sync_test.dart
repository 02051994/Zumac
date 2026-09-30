import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:appgt_offline_subtables/config/tenant_config.dart';
import 'package:appgt_offline_subtables/core/services/local_db.dart';
import 'package:appgt_offline_subtables/core/services/offline_record_state.dart';

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
    await database.execute('''
      create table pending_records(
        id_local text primary key,
        user_id text,
        empresa_id text,
        modulo_id text,
        formato_id text,
        formato_tabla_id text,
        tabla_destino text,
        payload_json text,
        estado text,
        intentos integer default 0,
        error_mensaje text,
        created_at text,
        synced_at text,
        created_by text,
        updated_at_local text,
        base_updated_at text,
        version_local integer default 1,
        version_remota text,
        conflict_json text,
        last_attempt_at text,
        evidence_json text
      )
    ''');
    await database.execute('''
      create table local_matrix_rows(
        source_table text,
        row_key text,
        payload_json text,
        primary key(source_table, row_key)
      )
    ''');
    await database.execute('''
      create table local_catalog_values(
        catalog_key text,
        value text,
        primary key(catalog_key, value)
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

  test('reemplaza solo el dropdown cambiado y elimina opciones antiguas',
      () async {
    await database.insert('local_catalog_values', {
      'catalog_key': 'LOTES.NOMBRE',
      'value': 'Lote antiguo',
    });
    await database.insert('local_catalog_values', {
      'catalog_key': 'VARIEDADES.NOMBRE',
      'value': 'Arándano',
    });

    await local.replaceCatalogValuesForKeys(
      const ['LOTES.NOMBRE'],
      const [
        {'catalog_key': 'LOTES.NOMBRE', 'value': 'Lote nuevo'},
      ],
    );

    final rows = await database.query(
      'local_catalog_values',
      orderBy: 'catalog_key, value',
    );
    expect(rows, [
      {'catalog_key': 'LOTES.NOMBRE', 'value': 'Lote nuevo'},
      {'catalog_key': 'VARIEDADES.NOMBRE', 'value': 'Arándano'},
    ]);
  });

  test('los pendientes se aislan por usuario y empresa', () async {
    await local.insertPending({
      'id_local': 'propio',
      'user_id': 'usuario-a',
      'estado': 'pendiente',
    });
    await database.insert('pending_records', {
      'id_local': 'otro-usuario',
      'user_id': 'usuario-b',
      'empresa_id': TenantConfig.defaultEmpresaId,
      'estado': 'pendiente',
    });
    await database.insert('pending_records', {
      'id_local': 'otra-empresa',
      'user_id': 'usuario-a',
      'empresa_id': 'empresa-b',
      'estado': 'pendiente',
    });

    final rows = await local.pendingRecords(
      userId: 'usuario-a',
      empresaId: TenantConfig.defaultEmpresaId,
    );

    expect(rows.map((row) => row['id_local']), ['propio']);
  });

  test('la cola local versiona y conserva la base remota', () async {
    await local.insertPending({
      'id_local': 'registro-versionado',
      'user_id': 'usuario-a',
      'payload_json': jsonEncode({
        'updated_at': '2026-07-15T10:00:00Z',
        'valor': 1,
      }),
    });

    var row = (await database.query(
      'pending_records',
      where: 'id_local = ?',
      whereArgs: ['registro-versionado'],
    ))
        .single;
    expect(row['estado'], OfflineRecordState.pending.storageValue);
    expect(row['version_local'], 1);
    expect(row['base_updated_at'], '2026-07-15T10:00:00Z');

    await local.insertPending({
      'id_local': 'registro-versionado',
      'user_id': 'usuario-a',
      'payload_json': jsonEncode({'valor': 2}),
    });
    row = (await database.query(
      'pending_records',
      where: 'id_local = ?',
      whereArgs: ['registro-versionado'],
    ))
        .single;
    expect(row['version_local'], 2);
    expect(row['base_updated_at'], '2026-07-15T10:00:00Z');
  });

  test('los estados de reintento y conflicto quedan trazables', () async {
    await local.insertPending({
      'id_local': 'registro-conflicto',
      'user_id': 'usuario-a',
      'payload_json': '{}',
    });

    await local.markSyncing('registro-conflicto');
    var row = (await database.query('pending_records')).single;
    expect(row['estado'], OfflineRecordState.syncing.storageValue);

    await local.markError('registro-conflicto', 'fallo temporal');
    row = (await database.query('pending_records')).single;
    expect(row['estado'], OfflineRecordState.error.storageValue);
    expect(row['intentos'], 1);

    await local.markConflict(
      'registro-conflicto',
      {'remote_updated_at': '2026-07-15T11:00:00Z'},
      remoteVersion: '2026-07-15T11:00:00Z',
    );
    row = (await database.query('pending_records')).single;
    expect(row['estado'], OfflineRecordState.conflict.storageValue);
    expect(row['conflict_json'], contains('remote_updated_at'));

    await local.retryConflict('registro-conflicto');
    row = (await database.query('pending_records')).single;
    expect(row['estado'], OfflineRecordState.pending.storageValue);
    expect(row['conflict_json'], isNull);
  });

  test('una sincronizacion interrumpida vuelve a la cola sin perder datos',
      () async {
    await local.insertPending({
      'id_local': 'registro-interrumpido',
      'user_id': 'usuario-a',
      'empresa_id': TenantConfig.defaultEmpresaId,
      'payload_json': jsonEncode({'CONDUCTOR': 'Nombre editado'}),
    });
    await local.markSyncing('registro-interrumpido');

    final recovered = await local.recoverInterruptedSyncRecords(
      userId: 'usuario-a',
      empresaId: TenantConfig.defaultEmpresaId,
    );
    final pending = await local.pendingRecords(
      userId: 'usuario-a',
      empresaId: TenantConfig.defaultEmpresaId,
    );

    expect(recovered, 1);
    expect(pending, hasLength(1));
    expect(pending.single['estado'], OfflineRecordState.error.storageValue);
    expect(pending.single['payload_json'], contains('Nombre editado'));
  });

  test('un reemplazo relacionado fallido revierte los borrados', () async {
    await local.insertPending({
      'id_local': 'grupo_0',
      'user_id': 'usuario-a',
      'formato_id': 'formato-a',
      'tabla_destino': 'REGISTROS',
      'payload_json': jsonEncode({'ID_REGISTRO': 'grupo', 'valor': 'anterior'}),
    });

    await expectLater(
      local.replacePendingRecordsAtomically(
        idLocalPrefix: 'grupo_',
        formatoId: 'formato-a',
        tablaDestino: 'REGISTROS',
        logicalId: 'grupo',
        rows: [
          {
            'id_local': 'grupo_0',
            'user_id': 'usuario-a',
            'payload_json':
                jsonEncode({'ID_REGISTRO': 'grupo', 'valor': 'nuevo'}),
          },
          {
            'id_local': 'grupo_1',
            'columna_inexistente': 'fuerza rollback',
          },
        ],
      ),
      throwsA(anything),
    );

    final row = (await database.query(
      'pending_records',
      where: 'id_local = ?',
      whereArgs: ['grupo_0'],
    ))
        .single;
    expect(row['payload_json'], contains('anterior'));
  });

  test('la politica optimista detecta cambios remotos posteriores', () {
    expect(
      OfflineConflictPolicy.hasRemoteChange(
        baseUpdatedAt: '2026-07-15T10:00:00Z',
        remoteUpdatedAt: '2026-07-15T10:00:01Z',
      ),
      isTrue,
    );
    expect(
      OfflineConflictPolicy.hasRemoteChange(
        baseUpdatedAt: '2026-07-15T10:00:00Z',
        remoteUpdatedAt: '2026-07-15T10:00:00Z',
      ),
      isFalse,
    );
  });

  test('el identificador con prefijo continúa la secuencia local y remota',
      () async {
    await database.insert('local_matrix_rows', {
      'source_table': 'REGISTROS',
      'row_key': 'remoto-4',
      'payload_json': jsonEncode({'CODIGO': 'GT-GB-G4'}),
    });
    await local.insertPending({
      'id_local': 'pendiente-7',
      'user_id': 'usuario-a',
      'tabla_destino': 'REGISTROS',
      'payload_json': jsonEncode({'CODIGO': 'GT-GB-G7'}),
    });

    expect(
      await local.nextIncrementalIdentifier(
        table: 'REGISTROS',
        field: 'CODIGO',
        prefix: 'GT-GB-G',
      ),
      'GT-GB-G8',
    );
    expect(
      await local.nextIncrementalIdentifier(
        table: 'REGISTROS',
        field: 'CODIGO',
        prefix: 'GT-GB-G',
      ),
      'GT-GB-G9',
    );
  });
}
