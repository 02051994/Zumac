import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:appgt_offline_subtables/core/services/local_db.dart';
import 'package:appgt_offline_subtables/core/services/zumac_consultant_service.dart';

void main() {
  sqfliteFfiInit();

  late Database database;
  late ZumacConsultantService consultant;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('''
      create table local_form_fields(
        id text primary key,
        tabla_destino text,
        campo text,
        etiqueta text,
        tipo_ui text
      )
    ''');
    await database.execute('''
      create table local_formats(
        id text primary key,
        modulo_id text,
        tabla_destino text,
        nombre text
      )
    ''');
    await database.execute('''
      create table local_format_tables(
        id text primary key,
        formato_id text,
        tabla_destino text
      )
    ''');
    await database.execute('''
      create table local_modules(
        id text primary key,
        nombre text
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
    consultant = ZumacConsultantService(
      localDb: LocalDb.forTesting(database),
      remoteLoader: (_) async => const <Map<String, dynamic>>[],
    );
  });

  tearDown(() => database.close());

  Future<void> configureFormat({
    required String table,
    required String field,
    required String label,
  }) async {
    await database.insert('local_modules', {
      'id': 'quality',
      'nombre': 'Calidad',
    });
    await database.insert('local_formats', {
      'id': 'daily-control',
      'modulo_id': 'quality',
      'tabla_destino': table,
      'nombre': 'Control diario',
    });
    await database.insert('local_format_tables', {
      'id': 'daily-control-table',
      'formato_id': 'daily-control',
      'tabla_destino': table,
    });
    await database.insert('local_form_fields', {
      'id': '$table-$field',
      'tabla_destino': table,
      'campo': field,
      'etiqueta': label,
      'tipo_ui': 'text',
    });
  }

  Future<void> configureCustomFormat({
    required String table,
    required String formatId,
    required String formatName,
    required Map<String, String> fields,
  }) async {
    final existingModule = await database.query(
      'local_modules',
      where: 'id = ?',
      whereArgs: ['operations'],
      limit: 1,
    );
    if (existingModule.isEmpty) {
      await database.insert('local_modules', {
        'id': 'operations',
        'nombre': 'Operaciones',
      });
    }
    await database.insert('local_formats', {
      'id': formatId,
      'modulo_id': 'operations',
      'tabla_destino': table,
      'nombre': formatName,
    });
    await database.insert('local_format_tables', {
      'id': '$formatId-table',
      'formato_id': formatId,
      'tabla_destino': table,
    });
    var index = 0;
    for (final entry in fields.entries) {
      await database.insert('local_form_fields', {
        'id': '$formatId-field-${index++}',
        'tabla_destino': table,
        'campo': entry.key,
        'etiqueta': entry.value,
        'tipo_ui': 'text',
      });
    }
  }

  Future<void> insertMatrixRow(
    String table,
    String key,
    Map<String, dynamic> payload,
  ) {
    return database.insert('local_matrix_rows', {
      'source_table': table,
      'row_key': key,
      'payload_json': jsonEncode(payload),
    });
  }

  test('encuentra pH mayor al límite de hoy y entrega navegación', () async {
    const table = 'control_ph';
    await configureFormat(
      table: table,
      field: 'ph',
      label: 'pH',
    );
    final today = DateTime.now().toIso8601String();
    await insertMatrixRow(table, 'ph-1', {
      'id': 'ph-1',
      'fecha': today,
      'lote': 'Lote 8',
      'ph': 6.4,
    });
    await insertMatrixRow(table, 'ph-2', {
      'id': 'ph-2',
      'fecha': today,
      'lote': 'Lote 2',
      'ph': 5.8,
    });

    final result = await consultant.ask('¿Hay pHs mayores a 6 hoy?');

    expect(result.intent, ZumacConsultantIntent.phThreshold);
    expect(result.findings, hasLength(1));
    expect(result.findings.single.title, contains('6.4'));
    expect(result.findings.single.detail, contains('Lote 8'));
    expect(result.findings.single.moduleId, 'quality');
    expect(result.findings.single.formatId, 'daily-control');
    expect(result.findings.single.recordField, 'id');
    expect(result.findings.single.recordValue, 'ph-1');
  });

  test('lista las inasistencias registradas hoy', () async {
    const table = 'asistencia_personal';
    await configureFormat(
      table: table,
      field: 'estado_asistencia',
      label: 'Estado de asistencia',
    );
    await insertMatrixRow(table, 'worker-1', {
      'id': 'worker-1',
      'fecha': DateTime.now().toIso8601String(),
      'nombre_completo': 'Ana Torres',
      'estado_asistencia': 'Inasistente',
    });

    final result = await consultant.ask('¿Hay inasistencias hoy?');

    expect(result.intent, ZumacConsultantIntent.absences);
    expect(result.findings, hasLength(1));
    expect(result.findings.single.title, 'Ana Torres');
    expect(result.answer, contains('1 inasistencia'));
  });

  test('una pregunta de asistencia consulta dinámicamente tabla y campo',
      () async {
    const table = 'asistencia_personal';
    await configureFormat(
      table: table,
      field: 'estado_asistencia',
      label: 'Estado de asistencia',
    );
    await insertMatrixRow(table, 'worker-today', {
      'id': 'worker-today',
      'fecha': DateTime.now().toIso8601String(),
      'nombre_completo': 'María López',
      'estado_asistencia': 'Presente',
    });
    await insertMatrixRow(table, 'worker-old', {
      'id': 'worker-old',
      'fecha':
          DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
      'nombre_completo': 'José Pérez',
      'estado_asistencia': 'Presente',
    });

    final result = await consultant.ask('¿Hoy hay asistencias?');

    expect(result.intent, ZumacConsultantIntent.attendance);
    expect(result.findings, hasLength(1));
    expect(result.findings.single.title, 'María López');
    expect(result.findings.single.formatId, 'daily-control');
  });

  test('resume asistencias, salidas y presenta una tabla sin ids técnicos',
      () async {
    const table = 'asistencia_personal';
    await configureCustomFormat(
      table: table,
      formatId: 'attendance',
      formatName: 'Asistencia de personal',
      fields: const {
        'fecha': 'Fecha',
        'nombre_completo': 'Persona',
        'hora_ingreso': 'Hora de ingreso',
        'hora_salida': 'Hora de salida',
      },
    );
    final today = DateTime.now().toIso8601String();
    await insertMatrixRow(table, 'attendance-1', {
      'id': 'technical-1',
      'fecha': today,
      'nombre_completo': 'Ana Torres',
      'hora_ingreso': '07:10',
      'hora_salida': '16:05',
    });
    await insertMatrixRow(table, 'attendance-2', {
      'id': 'technical-2',
      'fecha': today,
      'nombre_completo': 'Luis Rojas',
      'hora_ingreso': '07:15',
      'hora_salida': '16:08',
    });
    await insertMatrixRow(table, 'attendance-3', {
      'id': 'technical-3',
      'fecha': today,
      'nombre_completo': 'Rosa Díaz',
      'hora_ingreso': '07:20',
      'hora_salida': '',
    });

    final result =
        await consultant.ask('¿Cuántas personas tienen asistencia hoy?');

    expect(result.answer, contains('3 personas con asistencia'));
    expect(result.answer, contains('2 ya registraron su salida'));
    expect(result.answer, contains('1 aún no tiene salida'));
    expect(result.reportTables, hasLength(1));
    expect(
      result.reportTables.single.columns.map((column) => column.key),
      isNot(contains('id')),
    );
    expect(
      result.reportTables.single.rows
          .map((row) => row['nombre_completo'])
          .whereType<String>(),
      containsAll(<String>['Ana Torres', 'Luis Rojas', 'Rosa Díaz']),
    );
  });

  test('entiende una fecha histórica exacta y solo devuelve ese día', () async {
    const table = 'camara_humeda';
    await configureCustomFormat(
      table: table,
      formatId: 'wet-chamber',
      formatName: 'Cámara húmeda',
      fields: const {
        'fecha': 'Fecha',
        'muestra': 'Muestra',
        'resultado': 'Resultado',
      },
    );
    await insertMatrixRow(table, 'wet-1', {
      'id': 'wet-1',
      'fecha': '2026-07-23',
      'muestra': 'Muestra A',
      'resultado': 'Positivo',
    });
    await insertMatrixRow(table, 'wet-2', {
      'id': 'wet-2',
      'fecha': '2026-07-24',
      'muestra': 'Muestra B',
      'resultado': 'Negativo',
    });

    final result =
        await consultant.ask('¿El 23/07/2026 hubo registro de cámara húmeda?');

    expect(result.answer, contains('23/07/2026'));
    expect(result.findings, hasLength(1));
    expect(result.reportTables.single.rows, hasLength(1));
    expect(
      result.reportTables.single.rows.single['muestra'],
      'Muestra A',
    );
  });

  test('cruza tareo con asistencia y devuelve solo personal faltante',
      () async {
    await configureCustomFormat(
      table: 'tareo_personal',
      formatId: 'work-log',
      formatName: 'Tareo de personal',
      fields: const {
        'fecha': 'Fecha',
        'dni': 'DNI',
        'nombre_completo': 'Persona',
      },
    );
    await configureCustomFormat(
      table: 'asistencia_personal',
      formatId: 'attendance',
      formatName: 'Asistencia de personal',
      fields: const {
        'fecha': 'Fecha',
        'dni': 'DNI',
        'nombre_completo': 'Persona',
        'hora_ingreso': 'Hora de ingreso',
      },
    );
    final today = DateTime.now().toIso8601String();
    await insertMatrixRow('tareo_personal', 'work-1', {
      'id': 'work-1',
      'fecha': today,
      'dni': '11111111',
      'nombre_completo': 'Ana Torres',
    });
    await insertMatrixRow('tareo_personal', 'work-2', {
      'id': 'work-2',
      'fecha': today,
      'dni': '22222222',
      'nombre_completo': 'Luis Rojas',
    });
    await insertMatrixRow('asistencia_personal', 'attendance-1', {
      'id': 'attendance-1',
      'fecha': today,
      'dni': '11111111',
      'nombre_completo': 'Ana Torres',
      'hora_ingreso': '07:10',
    });

    final result = await consultant.ask(
      '¿Qué personas tienen tareo hoy pero no asistencia?',
    );

    expect(result.intent, ZumacConsultantIntent.crossTable);
    expect(result.findings, hasLength(1));
    expect(result.findings.single.title, 'Luis Rojas');
    expect(result.answer, contains('1 persona con tareo'));
    expect(result.reportTables.single.rows.single['nombre_completo'],
        'Luis Rojas');
  });

  test('explica cuando los asistidos todavía no tienen ningún tareo', () async {
    await configureCustomFormat(
      table: 'tareo_personal',
      formatId: 'work-log-empty',
      formatName: 'Tareo de personal',
      fields: const {
        'fecha': 'Fecha',
        'dni': 'DNI',
        'nombre_completo': 'Persona',
      },
    );
    await configureCustomFormat(
      table: 'asistencia_personal',
      formatId: 'attendance-without-work-log',
      formatName: 'Asistencia de personal',
      fields: const {
        'fecha': 'Fecha',
        'dni': 'DNI',
        'nombre_completo': 'Persona',
        'hora_ingreso': 'Hora de ingreso',
      },
    );
    final today = DateTime.now().toIso8601String();
    for (var index = 1; index <= 23; index++) {
      await insertMatrixRow('asistencia_personal', 'attendance-$index', {
        'id': 'attendance-$index',
        'fecha': today,
        'dni': index.toString().padLeft(8, '0'),
        'nombre_completo': 'Persona $index',
        'hora_ingreso': '07:10',
      });
    }

    final result = await consultant.ask(
      '¿Qué personas tienen tareo hoy pero no asistencia?',
    );

    expect(result.intent, ZumacConsultantIntent.crossTable);
    expect(result.findings, isEmpty);
    expect(
      result.answer,
      'Ninguno de los 23 asistidos tiene tareo hoy.',
    );
  });

  test('compara también asistencias que todavía no tienen tareo', () async {
    await configureCustomFormat(
      table: 'tareo_personal',
      formatId: 'work-log-reverse',
      formatName: 'Tareo de personal',
      fields: const {
        'fecha': 'Fecha',
        'dni': 'DNI',
        'nombre_completo': 'Persona',
      },
    );
    await configureCustomFormat(
      table: 'asistencia_personal',
      formatId: 'attendance-reverse',
      formatName: 'Asistencia de personal',
      fields: const {
        'fecha': 'Fecha',
        'dni': 'DNI',
        'nombre_completo': 'Persona',
        'hora_ingreso': 'Hora de ingreso',
      },
    );
    final today = DateTime.now().toIso8601String();
    await insertMatrixRow('asistencia_personal', 'attendance-ana', {
      'id': 'attendance-ana',
      'fecha': today,
      'dni': '11111111',
      'nombre_completo': 'Ana Torres',
      'hora_ingreso': '07:10',
    });
    await insertMatrixRow('asistencia_personal', 'attendance-luis', {
      'id': 'attendance-luis',
      'fecha': today,
      'dni': '22222222',
      'nombre_completo': 'Luis Rojas',
      'hora_ingreso': '07:15',
    });
    await insertMatrixRow('tareo_personal', 'work-ana', {
      'id': 'work-ana',
      'fecha': today,
      'dni': '11111111',
      'nombre_completo': 'Ana Torres',
    });

    final result = await consultant.ask(
      '¿Qué personas tienen asistencia hoy pero no tareo?',
    );

    expect(result.findings, hasLength(1));
    expect(result.findings.single.title, 'Luis Rojas');
    expect(result.answer, contains('Asistidos 2, tareados 1.'));
    expect(result.answer, contains('1 persona con asistencia sin tareo'));
  });

  test('una consulta de plagas por fecha no mezcla otros formatos', () async {
    await configureCustomFormat(
      table: 'registro_plagas_enfermedades',
      formatId: 'pests-by-date',
      formatName: 'Plagas y enfermedades',
      fields: const {
        'fecha': 'Fecha',
        'plaga': 'Plaga o enfermedad',
        'lote': 'Lote',
      },
    );
    await configureCustomFormat(
      table: 'control_riego',
      formatId: 'irrigation-same-date',
      formatName: 'Control de riego',
      fields: const {
        'fecha': 'Fecha',
        'turno': 'Turno',
      },
    );
    await insertMatrixRow('registro_plagas_enfermedades', 'pest-date-1', {
      'id': 'pest-date-1',
      'fecha': '2026-07-23',
      'plaga': 'Oidium',
      'lote': 'Lote Norte',
    });
    await insertMatrixRow('control_riego', 'irrigation-date-1', {
      'id': 'irrigation-date-1',
      'fecha': '2026-07-23',
      'turno': 'Mañana',
    });

    final result = await consultant.ask(
      '¿Cuántos registros de plagas hubo el 23/07/2026?',
    );

    expect(result.findings, hasLength(1));
    expect(result.findings.single.tableName, 'registro_plagas_enfermedades');
    expect(result.reportTables, hasLength(1));
    expect(
      result.reportTables.single.tableName,
      'registro_plagas_enfermedades',
    );
  });

  test('relaciona plagas con lote y productos por objetivo y stock', () async {
    await configureCustomFormat(
      table: 'registro_plagas_enfermedades',
      formatId: 'pests',
      formatName: 'Plagas y enfermedades',
      fields: const {
        'fecha': 'Fecha',
        'plaga': 'Plaga o enfermedad',
        'lote_id': 'Lote',
      },
    );
    await configureCustomFormat(
      table: 'matriz_productos',
      formatId: 'products',
      formatName: 'Matriz de productos',
      fields: const {
        'nombre_producto': 'Producto',
        'objetivo': 'Objetivo',
        'stock': 'Stock',
      },
    );
    await configureCustomFormat(
      table: 'lotes',
      formatId: 'lots',
      formatName: 'Lotes',
      fields: const {
        'lote': 'Lote',
      },
    );
    await insertMatrixRow('lotes', 'lot-42', {
      'id': 'lot-42',
      'lote': 'Lote Norte',
    });
    await insertMatrixRow('registro_plagas_enfermedades', 'pest-1', {
      'id': 'pest-1',
      'fecha': DateTime.now().toIso8601String(),
      'plaga': 'Oidium',
      'lote_id': 'lot-42',
    });
    await insertMatrixRow('matriz_productos', 'product-1', {
      'id': 'product-1',
      'nombre_producto': 'Azufre agrícola',
      'objetivo': 'Oidium',
      'stock': 8,
    });
    await insertMatrixRow('matriz_productos', 'product-2', {
      'id': 'product-2',
      'nombre_producto': 'Producto sin stock',
      'objetivo': 'Oidium',
      'stock': 0,
    });
    await insertMatrixRow('matriz_productos', 'product-3', {
      'id': 'product-3',
      'nombre_producto': 'Producto para botrytis',
      'objetivo': 'Botrytis',
      'stock': 12,
    });

    final result = await consultant.ask(
      '¿Qué plagas se encontraron y en qué lotes, y qué productos en stock tenemos para combatir esas enfermedades?',
    );

    expect(result.intent, ZumacConsultantIntent.crossTable);
    expect(
      result.reportTables.map((report) => report.tableName).toSet(),
      {
        'registro_plagas_enfermedades',
        'matriz_productos',
      },
    );
    final pestReport = result.reportTables.firstWhere(
      (report) => report.tableName == 'registro_plagas_enfermedades',
    );
    final productReport = result.reportTables.firstWhere(
      (report) => report.tableName == 'matriz_productos',
    );
    expect(pestReport.rows.single['lote_id'], 'Lote Norte');
    expect(productReport.rows, hasLength(1));
    expect(
      productReport.rows.single['nombre_producto'],
      'Azufre agrícola',
    );
  });

  test('aplica comparaciones numéricas a cualquier campo configurado',
      () async {
    const table = 'control_temperatura';
    await configureFormat(
      table: table,
      field: 'temperatura',
      label: 'Temperatura',
    );
    final today = DateTime.now().toIso8601String();
    await insertMatrixRow(table, 'temp-high', {
      'id': 'temp-high',
      'fecha': today,
      'lote': 'Lote Norte',
      'temperatura': 28.5,
    });
    await insertMatrixRow(table, 'temp-ok', {
      'id': 'temp-ok',
      'fecha': today,
      'lote': 'Lote Sur',
      'temperatura': 22,
    });

    final result = await consultant.ask('¿Hay temperaturas mayores a 25 hoy?');

    expect(result.intent, ZumacConsultantIntent.generalSearch);
    expect(result.findings, hasLength(1));
    expect(result.findings.single.recordValue, 'temp-high');
    expect(result.findings.single.detail, contains('28.5'));
  });

  test('consulta Supabase antes de responder y no exige actualización manual',
      () async {
    const table = 'asistencia_personal';
    await configureFormat(
      table: table,
      field: 'estado_asistencia',
      label: 'Estado de asistencia',
    );
    consultant = ZumacConsultantService(
      localDb: LocalDb.forTesting(database),
      remoteLoader: (requestedTable) async {
        if (requestedTable != table) return const [];
        return [
          {
            'id': 'remote-worker',
            'fecha': DateTime.now().toIso8601String(),
            'nombre_completo': 'Lucía Ramos',
            'estado_asistencia': 'Presente',
          },
        ];
      },
    );

    final result = await consultant.ask('¿Hoy hay asistencias?');

    expect(result.findings, hasLength(1));
    expect(result.findings.single.title, 'Lucía Ramos');
    final cachedRows = await database.query(
      'local_matrix_rows',
      where: 'source_table = ?',
      whereArgs: [table],
    );
    expect(cachedRows, hasLength(1));
  });
}
