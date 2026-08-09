import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../config/tenant_config.dart';
import 'field_definitions.dart';
import 'local_db.dart';
import 'local_session.dart';
import 'evidence_storage.dart';
import 'offline_record_state.dart';

/// Orquesta la sincronización autenticada entre Supabase y la caché local.
///
/// Windows y móvil conservan registros para operación offline. En web se
/// sincronizan configuración, permisos y catálogos, mientras los registros de
/// gran volumen se consultan paginados desde Supabase.
class SyncService {
  final _supabase = Supabase.instance.client;
  final _local = LocalDb.instance;
  final _uuid = const Uuid();

  static const Set<String> _excludedOfflineSourceTables = {
    'appgt_auditoria',
    'appgt_auditoria_peru',
  };

  Future<void> _yieldToUi() async {
    // Permite que Flutter pinte spinners/progreso entre lotes grandes de sync.
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }

  String friendlyError(Object error) {
    final raw = error.toString();
    final msg = raw.toLowerCase();
    if (msg.contains('sin conexión') ||
        msg.contains('sin conexion') ||
        msg.contains('internet') ||
        msg.contains('socketexception') ||
        msg.contains('network')) {
      return 'No hay conexión a internet. El registro quedó pendiente; vuelve a sincronizar cuando tengas señal.';
    }
    if (msg.contains('invalid login') ||
        msg.contains('invalid credentials') ||
        msg.contains('credenciales') ||
        msg.contains('password')) {
      return 'Usuario o contraseña incorrectos.';
    }
    if (msg.contains('jwt') ||
        msg.contains('not authorized') ||
        msg.contains('unauthorized') ||
        msg.contains('permission denied') ||
        msg.contains('row-level security') ||
        msg.contains('rls')) {
      return 'No autorizado. La sesión online venció o el usuario no tiene permiso para enviar este registro.';
    }
    if (msg.contains('storage') ||
        msg.contains('bucket') ||
        msg.contains('upload')) {
      return 'No se pudo subir la foto o firma. Revisa internet y permisos del almacenamiento.';
    }
    if (msg.contains('duplicate key') || msg.contains('unique constraint')) {
      return 'El registro ya existe en la base de datos. Revisa si fue sincronizado antes.';
    }
    if (msg.contains('violates not-null') || msg.contains('null value')) {
      return 'Falta completar un campo obligatorio para poder enviar el registro.';
    }
    if (msg.contains('invalid input syntax') ||
        msg.contains('type') ||
        msg.contains('cast')) {
      return 'Un campo tiene un tipo de dato incorrecto. Revisa números, fechas y textos antes de sincronizar.';
    }
    return raw.replaceFirst('Exception: ', '').trim().isEmpty
        ? 'Ocurrió un problema al procesar la operación.'
        : raw.replaceFirst('Exception: ', '').trim();
  }

  Future<void> _ensureOnlineAuthSession() async {
    // Ruta rápida: si la sesión ya existe en memoria, no hacemos login otra vez.
    // Reautenticar en cada sincronización agregaba segundos incluso para 1 registro.
    if (_supabase.auth.currentUser != null &&
        _supabase.auth.currentSession != null) {
      return;
    }

    final localSession = LocalSession();
    final email = await localSession.cachedEmail();
    final password = await localSession.cachedPasswordForReauth();

    if (email != null &&
        email.trim().isNotEmpty &&
        password != null &&
        password.isNotEmpty) {
      try {
        await _supabase.auth.signInWithPassword(
            email: email.trim().toLowerCase(), password: password);
      } catch (e) {
        throw Exception(friendlyError(e));
      }
    } else {
      throw Exception(
          'No hay sesión online activa. Ingresa una vez con internet y vuelve a sincronizar.');
    }

    if (_supabase.auth.currentUser == null) {
      throw Exception(
          'No se pudo abrir la sesión online. Ingresa con internet y vuelve a sincronizar.');
    }
  }

  Future<bool> hasInternet() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (connectivityIndicatesNetwork(result)) return true;

      // Algunos dispositivos Android informan `none` brevemente al volver a
      // primer plano aunque los datos moviles ya esten activos.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final retry = await Connectivity().checkConnectivity();
      if (connectivityIndicatesNetwork(retry)) return true;
    } catch (_) {
      // Si el plugin no responde, la consulta real de abajo decide el estado.
    }

    // Connectivity indica transporte, no acceso real a internet. Una respuesta
    // HTTP de Supabase (incluso un rechazo RLS) confirma conectividad.
    try {
      await _supabase
          .from('EMPRESAS_APPGT')
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 6));
      return true;
    } on PostgrestException {
      return true;
    } on AuthException {
      return true;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static bool connectivityIndicatesNetwork(
    Iterable<ConnectivityResult> results,
  ) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  bool _isPureUuid(String value) {
    return RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(value.trim());
  }

  String _norm(String value) {
    var s = value.trim().toUpperCase();
    const map = {
      'Á': 'A',
      'É': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ú': 'U',
      'Ü': 'U',
      'Ñ': 'N'
    };
    map.forEach((k, v) => s = s.replaceAll(k, v));
    return s
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  dynamic _valueByColumn(Map<String, dynamic> row, List<String> candidates) {
    final wanted = candidates.map(_norm).toSet();
    for (final entry in row.entries) {
      if (wanted.contains(_norm(entry.key))) return entry.value;
    }
    return null;
  }

  bool _boolValue(dynamic value) {
    if (value == true) return true;
    if (value == false || value == null) return false;
    final s = value.toString().trim().toUpperCase();
    return s == 'TRUE' ||
        s == 'T' ||
        s == '1' ||
        s == 'SI' ||
        s == 'SÍ' ||
        s == 'S' ||
        s == 'YES';
  }

  bool _boolValueOrDefault(dynamic value, bool defaultValue) {
    if (value == null) return defaultValue;
    return _boolValue(value);
  }

  List<Map<String, dynamic>> _fallbackFenologiaRows() {
    const etapas = <String>[
      'PODA',
      'BROTACION',
      'FLORACION',
      'CUAJADO',
      'FRUTO VERDE',
      'FRUTO GUINDA',
      'FRUTO ROSADO',
      'FRUTO AZUL',
    ];
    return etapas.map((e) => {'etapa_fenologica': e}).toList();
  }

  Future<List<dynamic>> _safeSelect(String table, String select) async {
    try {
      final rows = await _supabase.from(table).select();
      if (List<dynamic>.from(rows).isNotEmpty) return rows;
    } catch (_) {}

    try {
      return await _supabase.from(table).select(select);
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<List<dynamic>> _selectAllFieldsPaged() async {
    const pageSize = 1000;
    var from = 0;
    final output = <dynamic>[];

    while (true) {
      final page = await _supabase
          .from('MATRIZ_CAMPOS_FORMATO_APPGT')
          .select()
          .order('tabla_destino')
          .order('orden')
          .range(from, from + pageSize - 1);

      final rows = List<dynamic>.from(page);
      output.addAll(rows);
      if (rows.length < pageSize) break;
      from += pageSize;
    }

    return output;
  }

  Future<List<Map<String, dynamic>>> _selectAllRowsPaged(String table) async {
    const pageSize = 1000;
    var from = 0;
    final output = <Map<String, dynamic>>[];

    while (true) {
      final page =
          await _supabase.from(table).select().range(from, from + pageSize - 1);

      final rows = List<Map<String, dynamic>>.from(page);
      output.addAll(rows);
      if (rows.length < pageSize) break;
      from += pageSize;
    }

    return output;
  }

  static const List<Map<String, String>> _catalogSpecs = [
    {
      'key': 'MATRIZ_JEFATURAS.JEFATURA',
      'table': 'MATRIZ_JEFATURAS',
      'column': 'JEFATURA'
    },
    {
      'key': 'MATRIZ_SUPERVISORES.SUPERVISOR',
      'table': 'MATRIZ_SUPERVISORES',
      'column': 'SUPERVISOR'
    },
    {
      'key': 'MATRIZ_EQUIPOS_DE_MEDICION.CODIGO',
      'table': 'MATRIZ_EQUIPOS_DE_MEDICION',
      'column': 'CODIGO'
    },
    {
      'key': 'MATRIZ_ESTADO_DE_EQUIPOS.ESTADO',
      'table': 'MATRIZ_ESTADO_DE_EQUIPOS',
      'column': 'ESTADO'
    },
    {
      'key': 'MATRIZ_MATERIALES_CALIBRACION_EQUIPOS_DE_MEDICION.MATERIALES',
      'table': 'MATRIZ_MATERIALES_CALIBRACION_EQUIPOS_DE_MEDICION',
      'column': 'MATERIALES'
    },
    {
      'key': 'MATRIZ_FRECUENCIA_DE_ACTIVIDADES.FRECUENCIA',
      'table': 'MATRIZ_FRECUENCIA_DE_ACTIVIDADES',
      'column': 'FRECUENCIA'
    },
    {
      'key': 'MATRIZ_MATERIALES_PARA_LIMPIEZA_AMBIENTES.MATERIALES',
      'table': 'MATRIZ_MATERIALES_PARA_LIMPIEZA_AMBIENTES',
      'column': 'MATERIALES'
    },
  ];

  Future<List<Map<String, dynamic>>> _downloadCatalogValues({
    Set<String>? changedTables,
    bool forceAll = true,
  }) async {
    final output = <Map<String, dynamic>>[];
    for (final spec in _catalogSpecs) {
      try {
        final table = spec['table']!;
        if (!forceAll && !_tableChanged(changedTables, table)) continue;
        final column = spec['column']!;
        final key = spec['key']!;
        final rows = await _supabase.from(table).select(column).order(column);
        final seen = <String>{};
        for (final row in List<Map<String, dynamic>>.from(rows)) {
          final value = _valueByColumn(row, [column])?.toString().trim() ?? '';
          if (value.isEmpty || seen.contains(value)) continue;
          seen.add(value);
          output.add({'catalog_key': key, 'value': value});
        }
      } catch (_) {}
    }
    return output;
  }

  String _cleanNullable(dynamic value) {
    if (value == null) return '';
    final s = value.toString().trim();
    if (s.isEmpty || s.toUpperCase() == 'NULL') return '';
    return s;
  }

  String _unwrapBracketReference(String value) {
    final text = value.trim();
    if (text.startsWith('[') && text.endsWith(']') && text.length >= 2) {
      return text.substring(1, text.length - 1).trim();
    }
    return text;
  }

  bool _isManualDropdownLiteral(String value) {
    final text = value.trim();
    if (!text.startsWith('[') || !text.endsWith(']')) return false;
    final content = _unwrapBracketReference(text);
    return content.contains(',') ||
        content.contains(';') ||
        content.contains('|');
  }

  Map<String, dynamic>? _fieldByIdentifier(
      List<Map<String, dynamic>> fields, String identifier) {
    final wanted = _norm(_unwrapBracketReference(_cleanNullable(identifier)));
    if (wanted.isEmpty) return null;
    for (final f in fields) {
      final matches = [f['id'], f['campo'], f['etiqueta']]
          .any((value) => _norm(_cleanNullable(value)) == wanted);
      if (matches) return f;
    }
    return null;
  }

  Future<Map<String, List<Map<String, dynamic>>>> _downloadDynamicSourceTables(
    List<Map<String, dynamic>> fields, {
    Set<String>? changedTables,
    String? since,
    bool forceAllSources = false,
  }) async {
    final sourceTables = <String>{};
    for (final f in fields) {
      final dropdownId = _cleanNullable(f['id_campo_dropdown']);
      if (_isManualDropdownLiteral(dropdownId)) continue;
      final cleanDropdownId = _unwrapBracketReference(dropdownId);
      if (cleanDropdownId.contains('.')) {
        final sourceTable = cleanDropdownId.split('.').first.trim();
        if (sourceTable.isNotEmpty &&
            !_excludedOfflineSourceTables.contains(sourceTable))
          sourceTables.add(sourceTable);
      } else {
        final sourceField = _fieldByIdentifier(fields, cleanDropdownId);
        final sourceTable = _cleanNullable(sourceField?['tabla_destino']);
        if (sourceTable.isNotEmpty &&
            !_excludedOfflineSourceTables.contains(sourceTable))
          sourceTables.add(sourceTable);
      }

      final formula = _cleanNullable(f['formula_funcion']);
      final lookupMatch = RegExp(
              r'(?:LOOKU[PR]|LOOKUP|BUSCAR|LISTA|LIST)\s*\(\s*([^,;\)]+)',
              caseSensitive: false)
          .firstMatch(formula);
      final lookupTable = (lookupMatch?.group(1)?.trim() ?? '')
          .replaceAll('"', '')
          .replaceAll("'", '');
      if (lookupTable.isNotEmpty &&
          !_excludedOfflineSourceTables.contains(lookupTable))
        sourceTables.add(lookupTable);
    }

    final output = <String, List<Map<String, dynamic>>>{};
    for (final table in sourceTables) {
      if (_excludedOfflineSourceTables.contains(table)) continue;
      final tableChanged = _tableChanged(changedTables, table);
      final mustRefreshFully = forceAllSources || tableChanged;
      if (!mustRefreshFully) continue;
      await _yieldToUi();
      try {
        // Un dropdown es un snapshot, no un historial. Se descarga completo
        // cuando cambia para eliminar también opciones borradas en Supabase.
        output[table] = await _selectAllRowsPaged(table);
      } catch (_) {}
    }
    return output;
  }

  Future<Map<String, List<Map<String, dynamic>>>> _downloadFormatRecordTables(
    List<Map<String, dynamic>> formats,
    List<Map<String, dynamic>> formatTables, {
    Set<String>? changedTables,
    String? since,
    bool forceAllTables = false,
  }) async {
    final tables = <String>{};

    void addTable(dynamic value) {
      final table = _cleanNullable(value);
      if (table.isEmpty) return;
      if (_excludedOfflineSourceTables.contains(table)) return;
      tables.add(table);
    }

    for (final f in formats) {
      addTable(_valueByColumn(f, ['tabla_destino', 'tabla destino']));
    }
    for (final ft in formatTables) {
      addTable(_valueByColumn(ft, ['tabla_destino', 'tabla destino']));
    }

    final output = <String, List<Map<String, dynamic>>>{};
    for (final table in tables) {
      if (!forceAllTables && !_tableChanged(changedTables, table)) continue;
      await _yieldToUi();
      try {
        output[table] = forceAllTables
            ? await _selectAllRowsPaged(table)
            : await _selectRowsPagedSince(table, since);
      } catch (_) {}
    }
    return output;
  }

  Future<Map<String, List<Map<String, dynamic>>>>
      _downloadDynamicViewDataTables(
    List<Map<String, dynamic>> dynamicViews, {
    Set<String>? changedTables,
    String? since,
    bool forceAllTables = false,
  }) async {
    final tables = <String>{};
    for (final v in dynamicViews) {
      final table =
          _cleanNullable(_valueByColumn(v, ['tabla_destino', 'tabla destino']));
      if (table.isEmpty) continue;
      if (_excludedOfflineSourceTables.contains(table)) continue;
      tables.add(table);
    }

    final output = <String, List<Map<String, dynamic>>>{};
    for (final table in tables) {
      if (!forceAllTables && !_tableChanged(changedTables, table)) continue;
      await _yieldToUi();
      try {
        output[table] = forceAllTables
            ? await _selectAllRowsPaged(table)
            : await _selectRowsPagedSince(table, since);
      } catch (_) {
        // No romper Actualizar datos si una vista apunta a una tabla sin permiso/RLS.
      }
    }
    return output;
  }

  Future<List<Map<String, dynamic>>> _downloadFlowRules() async {
    try {
      final rows = await _supabase
          .from('MATRIZ_ESTADOS_FLUJO_APPGT')
          .select()
          .eq('activo', true)
          .order('orden');
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  List<Map<String, dynamic>> _dynamicCatalogValues(
    List<Map<String, dynamic>> fields,
    Map<String, List<Map<String, dynamic>>> sourceRows,
  ) {
    final output = <Map<String, dynamic>>[];
    for (final f in fields) {
      final dropdownId = _cleanNullable(f['id_campo_dropdown']);
      if (dropdownId.isEmpty || _isManualDropdownLiteral(dropdownId)) continue;
      final cleanDropdownId = _unwrapBracketReference(dropdownId);
      String sourceTable = '';
      String sourceColumn = '';
      if (cleanDropdownId.contains('.')) {
        final parts = cleanDropdownId.split('.');
        sourceTable = parts.first.trim();
        sourceColumn = parts.sublist(1).join('.').trim();
      } else {
        final sourceField = _fieldByIdentifier(fields, cleanDropdownId);
        if (sourceField == null) continue;
        sourceTable = _cleanNullable(sourceField['tabla_destino']);
        sourceColumn = _cleanNullable(sourceField['campo']);
      }
      if (sourceTable.isEmpty || sourceColumn.isEmpty) continue;
      final key = '$sourceTable.$sourceColumn';
      final seen = <String>{};
      for (final row
          in sourceRows[sourceTable] ?? const <Map<String, dynamic>>[]) {
        final value =
            _valueByColumn(row, [sourceColumn])?.toString().trim() ?? '';
        if (value.isEmpty || seen.contains(value)) continue;
        seen.add(value);
        output.add({'catalog_key': key, 'value': value});
      }
    }
    return output;
  }

  Set<String> _dynamicCatalogKeysForTables(
    List<Map<String, dynamic>> fields,
    Iterable<String> sourceTables,
  ) {
    final wantedTables = sourceTables.map(_norm).toSet();
    final keys = <String>{};
    for (final field in fields) {
      final dropdownId = _cleanNullable(field['id_campo_dropdown']);
      if (dropdownId.isEmpty || _isManualDropdownLiteral(dropdownId)) continue;
      final cleanDropdownId = _unwrapBracketReference(dropdownId);
      String sourceTable = '';
      String sourceColumn = '';
      if (cleanDropdownId.contains('.')) {
        final parts = cleanDropdownId.split('.');
        sourceTable = parts.first.trim();
        sourceColumn = parts.sublist(1).join('.').trim();
      } else {
        final sourceField = _fieldByIdentifier(fields, cleanDropdownId);
        sourceTable = _cleanNullable(sourceField?['tabla_destino']);
        sourceColumn = _cleanNullable(sourceField?['campo']);
      }
      if (sourceTable.isNotEmpty &&
          sourceColumn.isNotEmpty &&
          wantedTables.contains(_norm(sourceTable))) {
        keys.add('$sourceTable.$sourceColumn');
      }
    }
    return keys;
  }

  List<Map<String, dynamic>> _matrixRowsForLocalCache(
    Map<String, List<Map<String, dynamic>>> sourceRows,
  ) {
    final output = <Map<String, dynamic>>[];
    for (final entry in sourceRows.entries) {
      var index = 0;
      for (final row in entry.value) {
        final id = _valueByColumn(row, ['id', 'ID', 'codigo', 'CODIGO'])
            ?.toString()
            .trim();
        output.add({
          'source_table': entry.key,
          'row_key': (id == null || id.isEmpty) ? '${entry.key}_$index' : id,
          'payload_json': jsonEncode(row),
        });
        index++;
      }
    }
    return output;
  }

  List<Map<String, dynamic>> _rowsFromBootstrap(
      Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is List) {
      return value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  Future<Set<String>?> _changedTablesSince(String? since) async {
    if (since == null || since.trim().isEmpty) return null;
    try {
      final result = await _supabase.rpc(
        'appgt_tablas_cambiadas_desde',
        params: {'p_since': since},
      );
      if (result is! List) return <String>{};
      return result
          .whereType<Map>()
          .map((e) =>
              (e['tabla_nombre'] ?? e['table_name'] ?? '').toString().trim())
          .where((name) => name.isNotEmpty)
          .toSet();
    } catch (_) {
      // Si la tabla/rpc de cambios aún no existe o falla por permisos,
      // no se rompe Actualizar datos: se usa el flujo incremental anterior.
      return null;
    }
  }

  bool _tableChanged(Set<String>? changedTables, String table) {
    if (changedTables == null) return true; // fallback: comportamiento anterior
    final wanted = _norm(table);
    return changedTables.any((candidate) => _norm(candidate) == wanted);
  }

  int _activeInt(Map<String, dynamic> row, {bool defaultValue = true}) {
    return _boolValueOrDefault(
            _valueByColumn(row, ['activo', 'active']), defaultValue)
        ? 1
        : 0;
  }

  bool _isDeletedRow(Map<String, dynamic> row) {
    if (_boolValue(_valueByColumn(row, ['eliminado', 'deleted']))) return true;
    final deletedAt =
        _valueByColumn(row, ['deleted_at', 'deleted at'])?.toString().trim() ??
            '';
    return deletedAt.isNotEmpty && deletedAt.toUpperCase() != 'NULL';
  }

  bool _isRemovedRow(
    Map<String, dynamic> row, {
    bool inactiveRemoves = true,
  }) {
    return _isDeletedRow(row) || (inactiveRemoves && _activeInt(row) != 1);
  }

  List<String> _removedIds(
    List<Map<String, dynamic>> rows, {
    bool inactiveRemoves = true,
  }) {
    return rows
        .where((row) => _isRemovedRow(row, inactiveRemoves: inactiveRemoves))
        .map((row) => _valueByColumn(row, ['id'])?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  Future<List<Map<String, dynamic>>?> _trySelectAllRowsSnapshot(
    String table,
  ) async {
    try {
      return await _selectAllRowsPaged(table);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> _trySelectAllFieldsSnapshot() async {
    try {
      final rows = await _selectAllFieldsPaged();
      return rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (_) {
      return null;
    }
  }

  String _tableRefreshMetaKey(String table) {
    final clean = table.trim().replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    return 'table_last_silent_refresh_at_$clean';
  }

  /// Fase 3A: refresco silencioso por tabla.
  ///
  /// Se usa al abrir una tabla Windows: muestra la caché local inmediatamente y,
  /// en segundo plano, consulta APPGT_TABLAS_CAMBIADAS. Si la tabla cambió,
  /// descarga solo filas modificadas por updated_at y actualiza local_matrix_rows.
  /// No toca matrices, dropdowns, grid, formularios ni sincronización general.
  Future<bool> refreshFormatTableSilently(String table) async {
    final cleanTable = table.trim();
    if (cleanTable.isEmpty) return false;

    final localCount = await _local.countMatrixRowsForTable(cleanTable);
    final tableMetaKey = _tableRefreshMetaKey(cleanTable);
    final tableLastRefresh = await _local.getMetaValue(tableMetaKey);
    final bootstrapLastSync =
        await _local.getMetaValue('bootstrap_last_sync_at');
    final since =
        (tableLastRefresh != null && tableLastRefresh.trim().isNotEmpty)
            ? tableLastRefresh
            : bootstrapLastSync;

    final checkpoint = DateTime.now().toUtc().toIso8601String();

    // Si no hay caché local de esa tabla, hacemos una carga completa segura una sola vez.
    if (localCount <= 0) {
      final rows = await _selectAllRowsPaged(cleanTable);
      await _local.applyMatrixRowsFromPayloads({cleanTable: rows},
          replaceSources: true);
      final refreshedCount = await _local.countMatrixRowsForTable(cleanTable);
      await _local.upsertTableCacheInfo(
        cleanTable,
        rowCount: refreshedCount,
        lastCheckedAt: DateTime.parse(checkpoint),
        lastChangedAt: DateTime.parse(checkpoint),
      );
      await _local.setMetaValue(tableMetaKey, checkpoint);
      return rows.isNotEmpty;
    }

    final changedTables = await _changedTablesSince(since);
    if (changedTables != null && !_tableChanged(changedTables, cleanTable)) {
      final cachedCount = await _local.countMatrixRowsForTable(cleanTable);
      await _local.upsertTableCacheInfo(
        cleanTable,
        rowCount: cachedCount,
        lastCheckedAt: DateTime.parse(checkpoint),
      );
      await _local.setMetaValue(tableMetaKey, checkpoint);
      return false;
    }

    final rows = await _selectRowsPagedSince(cleanTable, since);
    if (rows.isEmpty) {
      final cachedCount = await _local.countMatrixRowsForTable(cleanTable);
      await _local.upsertTableCacheInfo(
        cleanTable,
        rowCount: cachedCount,
        lastCheckedAt: DateTime.parse(checkpoint),
      );
      await _local.setMetaValue(tableMetaKey, checkpoint);
      return false;
    }

    await _local
        .applyMatrixRowsFromPayloads({cleanTable: rows}, replaceSources: false);
    final refreshedCount = await _local.countMatrixRowsForTable(cleanTable);
    await _local.upsertTableCacheInfo(
      cleanTable,
      rowCount: refreshedCount,
      lastCheckedAt: DateTime.parse(checkpoint),
      lastChangedAt: DateTime.parse(checkpoint),
    );
    await _local.setMetaValue(tableMetaKey, checkpoint);
    return true;
  }

  Future<List<Map<String, dynamic>>>
      _cachedLocalFieldsForSourceDetection() async {
    try {
      final rows = await _local.getAll('local_form_fields');
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _selectRowsPagedSince(
      String table, String? since) async {
    if (since == null || since.trim().isEmpty)
      return _selectAllRowsPaged(table);

    const pageSize = 1000;
    var from = 0;
    final output = <Map<String, dynamic>>[];

    try {
      while (true) {
        final page = await _supabase
            .from(table)
            .select()
            .gt('updated_at', since)
            .range(from, from + pageSize - 1);

        final rows = List<Map<String, dynamic>>.from(page);
        output.addAll(rows);
        if (rows.length < pageSize) break;
        from += pageSize;
      }
      return output;
    } catch (_) {
      // Algunas matrices/tablas antiguas podrían no exponer updated_at o tener RLS distinto.
      // Para no perder datos, si esa tabla fue marcada como cambiada, se descarga completa.
      return _selectAllRowsPaged(table);
    }
  }

  Future<Map<String, dynamic>?> _tryBootstrapRpc({
    String? since,
    bool allowFullFallback = true,
  }) async {
    try {
      final result = await _supabase.rpc(
        'appgt_bootstrap_offline_data_v2',
        params: {'p_since': since},
      );
      if (result is Map) {
        return Map<String, dynamic>.from(result)
          ..['__incremental__'] = since != null && since.trim().isNotEmpty;
      }
    } catch (_) {
      // Compatibilidad temporal durante el despliegue de la migracion v2.
    }

    if (since != null && since.trim().isNotEmpty) {
      try {
        final result = await _supabase.rpc(
          'appgt_bootstrap_offline_data',
          params: {'p_since': since},
        );
        if (result is Map) {
          return Map<String, dynamic>.from(result)..['__incremental__'] = true;
        }
      } catch (_) {
        // Si Supabase todavía tiene la versión antigua del RPC, no rompemos el login.
      }
    }

    if (!allowFullFallback) return null;

    try {
      final result = await _supabase.rpc('appgt_bootstrap_offline_data');
      if (result is Map) {
        return Map<String, dynamic>.from(result)..['__incremental__'] = false;
      }
    } catch (_) {
      // Si la función RPC aún no existe o Supabase la bloquea por RLS, se usa
      // el flujo autenticado anterior como respaldo.
    }
    return null;
  }

  /// Descarga el bootstrap inicial o un delta desde el último checkpoint.
  ///
  /// [forceConfigurationRefresh] omite la detección de cambios y obtiene una
  /// fotografía autoritativa de la configuración; lo usan los botones explícitos
  /// de "Actualizar datos". [cacheOperationalRecords] permite sobrescribir la
  /// política por plataforma; por defecto es `false` en web y `true` fuera de
  /// web. Los dropdowns y permisos siempre se mantienen disponibles localmente.
  Future<void> downloadAllForOffline(
      {bool allowFullFallback = true,
      bool forceConfigurationRefresh = false,
      bool? cacheOperationalRecords,
      void Function(String message)? onProgress}) async {
    void progress(String message) => onProgress?.call(message);
    progress('Consultando cambios...');
    await _yieldToUi();
    final syncCheckpoint = DateTime.now().toUtc().toIso8601String();
    final legacyCheckpoint =
        await _local.getMetaValue('bootstrap_last_sync_at');
    final previousConfigSync =
        await _local.getMetaValue('sync_checkpoint_config_at') ??
            legacyCheckpoint;
    final previousDataSync =
        await _local.getMetaValue('sync_checkpoint_data_at') ??
            legacyCheckpoint;
    final previousMatricesSync =
        await _local.getMetaValue('sync_checkpoint_matrices_at') ??
            legacyCheckpoint;
    final previousPermissionsSync =
        await _local.getMetaValue('sync_checkpoint_permissions_at') ??
            legacyCheckpoint;

    String? oldestCheckpoint(Iterable<String?> values) {
      final dates = values
          .whereType<String>()
          .map(DateTime.tryParse)
          .whereType<DateTime>()
          .toList();
      if (dates.isEmpty) return null;
      dates.sort();
      return dates.first.toUtc().toIso8601String();
    }

    final previousSync = oldestCheckpoint([
      previousConfigSync,
      previousDataSync,
      previousMatricesSync,
      previousPermissionsSync,
    ]);
    final hasCache = await _local.hasOfflineBootstrapCache();
    final shouldCacheOperationalRecords = cacheOperationalRecords ?? !kIsWeb;
    final lastConfigFullRefresh =
        await _local.getMetaValue('config_full_refresh_at');
    final lastConfigDate = DateTime.tryParse(lastConfigFullRefresh ?? '');
    final periodicSafetyRefresh = lastConfigDate == null ||
        DateTime.now().toUtc().difference(lastConfigDate.toUtc()) >=
            const Duration(hours: 24);

    // Primera vez: descarga completa. Si cualquiera de los dos botones ya hizo
    // esa primera descarga, el otro botón entra por incremental usando la misma
    // marca local bootstrap_last_sync_at.
    final changedTables =
        hasCache ? await _changedTablesSince(previousSync) : null;
    if (hasCache &&
        changedTables != null &&
        changedTables.isEmpty &&
        !forceConfigurationRefresh &&
        !periodicSafetyRefresh) {
      progress('Los datos ya están al día. Verificando permisos...');
      await _yieldToUi();
      await refreshLoginPermissionsOnly();
      await _local.setMetaValues({
        'bootstrap_last_sync_at': syncCheckpoint,
        'sync_checkpoint_config_at': syncCheckpoint,
        'sync_checkpoint_data_at': syncCheckpoint,
        'sync_checkpoint_permissions_at': syncCheckpoint,
        'sync_checkpoint_matrices_at': syncCheckpoint,
      });
      progress('No hay cambios nuevos.');
      await _yieldToUi();
      return;
    }
    progress('Descargando paquete incremental...');
    await _yieldToUi();
    final bootstrap = await _tryBootstrapRpc(
      since: hasCache ? previousSync : null,
      allowFullFallback: allowFullFallback || !hasCache,
    );
    if (bootstrap == null) {
      // Nunca salimos silenciosamente: si el incremental no está disponible,
      // hacemos fallback seguro. Es preferible tardar más a dejar la app desactualizada.
      // Si ya hay sesión autenticada, usamos el flujo clásico protegido por RLS.
      // El botón de la pantalla de login sin contraseña sí depende del RPC público
      // appgt_bootstrap_offline_data con GRANT EXECUTE para anon.
      if (_supabase.auth.currentUser != null) {
        await downloadCatalogs(onProgress: onProgress);
        progress('Finalizando actualización...');
        await _yieldToUi();
        await _local.setMetaValue('bootstrap_last_sync_at', syncCheckpoint);
        return;
      }
      throw Exception(
        'No se pudo actualizar datos sin credenciales. Falta habilitar en Supabase la función appgt_bootstrap_offline_data para anon/authenticated.',
      );
    }

    var activeEmpresaId = await LocalSession().cachedEmpresaId();
    final empresaPayload = bootstrap['empresa'];
    if (empresaPayload is Map) {
      final remoteEmpresaId = empresaPayload['id']?.toString().trim() ?? '';
      if (remoteEmpresaId.isNotEmpty) {
        activeEmpresaId = remoteEmpresaId;
        await LocalSession().saveActiveEmpresaId(remoteEmpresaId);
      }
    }
    if (activeEmpresaId.isEmpty) {
      activeEmpresaId = TenantConfig.defaultEmpresaId;
    }

    final configurationVersion = bootstrap['configuration_version'];
    final offlinePolicy = bootstrap['offline_policy'];

    final incremental = bootstrap.remove('__incremental__') == true;
    Future<void> saveLocal(
      String table,
      List<Map<String, dynamic>> rows, {
      bool snapshot = false,
      Iterable<String> deletedIds = const <String>[],
      String? keyColumn = 'id',
    }) async {
      await _yieldToUi();
      if (snapshot) {
        await _local.replaceTable(table, rows);
      } else if (keyColumn != null) {
        await _local.applyTableDelta(
          table,
          rows,
          deletedIds: deletedIds,
          keyColumn: keyColumn,
        );
      } else if (rows.isNotEmpty) {
        await _local.upsertTable(table, rows);
      }
      await _yieldToUi();
    }

    var modules = _rowsFromBootstrap(bootstrap, 'modules');
    var formats = _rowsFromBootstrap(bootstrap, 'formats');
    var formatTables = _rowsFromBootstrap(bootstrap, 'format_tables');
    var permissions = _rowsFromBootstrap(bootstrap, 'permissions');
    var profiles = _rowsFromBootstrap(bootstrap, 'profiles');
    var sections = _rowsFromBootstrap(bootstrap, 'sections');
    var sectionPermissions =
        _rowsFromBootstrap(bootstrap, 'section_permissions');
    var specialFormats = _rowsFromBootstrap(bootstrap, 'special_formats');
    var fields = _rowsFromBootstrap(bootstrap, 'fields');
    final lotesVariedades = _rowsFromBootstrap(bootstrap, 'lotes_variedades');
    final plagasConceptos = _rowsFromBootstrap(bootstrap, 'plagas_conceptos');
    final etapasFenologicas =
        _rowsFromBootstrap(bootstrap, 'etapas_fenologicas');
    final conteoEstadios = _rowsFromBootstrap(bootstrap, 'conteo_estadios');
    var rubros = _rowsFromBootstrap(bootstrap, 'rubros');
    var dropdownRules = _rowsFromBootstrap(bootstrap, 'dropdowns');
    var validationRules = _rowsFromBootstrap(bootstrap, 'validations');
    var conditionRules = _rowsFromBootstrap(bootstrap, 'conditions');
    var formulaRules = _rowsFromBootstrap(bootstrap, 'formulas');
    var dynamicViews = _rowsFromBootstrap(bootstrap, 'dynamic_views');
    bool bootstrapSnapshot(String key) =>
        !incremental && bootstrap[key] is List;
    var modulesSnapshot = bootstrapSnapshot('modules');
    var formatsSnapshot = bootstrapSnapshot('formats');
    var formatTablesSnapshot = bootstrapSnapshot('format_tables');
    var permissionsSnapshot = bootstrapSnapshot('permissions');
    var profilesSnapshot = bootstrapSnapshot('profiles');
    var sectionsSnapshot = bootstrapSnapshot('sections');
    var sectionPermissionsSnapshot = bootstrapSnapshot('section_permissions');
    var specialFormatsSnapshot = bootstrapSnapshot('special_formats');
    var fieldsSnapshot = bootstrapSnapshot('fields');
    var dynamicViewsSnapshot = bootstrapSnapshot('dynamic_views');
    final lotesSnapshot = bootstrapSnapshot('lotes_variedades');
    final plagasSnapshot = bootstrapSnapshot('plagas_conceptos');
    final fenologiasSnapshot = bootstrapSnapshot('etapas_fenologicas');
    final conteoSnapshot = bootstrapSnapshot('conteo_estadios');
    var rubrosSnapshot = bootstrapSnapshot('rubros');
    var dropdownRulesSnapshot = bootstrapSnapshot('dropdowns');
    var validationRulesSnapshot = bootstrapSnapshot('validations');
    var conditionRulesSnapshot = bootstrapSnapshot('conditions');
    var formulaRulesSnapshot = bootstrapSnapshot('formulas');
    var flowRules = <Map<String, dynamic>>[
      ..._rowsFromBootstrap(bootstrap, 'flow_rules'),
      ..._rowsFromBootstrap(bootstrap, 'estados_flujo'),
      ..._rowsFromBootstrap(bootstrap, 'matriz_estados_flujo'),
    ];
    var flowRulesSnapshot = !incremental &&
        (bootstrap['flow_rules'] is List ||
            bootstrap['estados_flujo'] is List ||
            bootstrap['matriz_estados_flujo'] is List);

    // Las matrices base se descargan completas solo cuando realmente cambiaron.
    // Como red de seguridad, se hace una verificación completa cada 24 horas por si
    // una edición manual no fue registrada por APPGT_TABLAS_CAMBIADAS.
    const configTables = <String>{
      'MATRIZ_CAMPOS_FORMATO_APPGT',
      'MATRIZ_FORMATOS_APPGT',
      'MATRIZ_FORMATO_TABLAS_APPGT',
      'MATRIZ_MODULOS_APPGT',
      'MATRIZ_SECCIONES_APPGT',
      'MATRIZ_VISTAS_DINAMICAS_APPGT',
      'MATRIZ_FORMATOS_ESPECIALES_APPGT',
      'RUBROS_APPGT',
      'MATRIZ_DROPDOWNS_APPGT',
      'MATRIZ_VALIDACIONES_APPGT',
      'MATRIZ_CONDICIONES_APPGT',
      'MATRIZ_FORMULAS_APPGT',
      'MATRIZ_ESTADOS_FLUJO_APPGT',
    };
    final configChanged = changedTables == null ||
        configTables.any((table) => _tableChanged(changedTables, table));
    final refreshFullConfig = forceConfigurationRefresh ||
        !incremental ||
        configChanged ||
        periodicSafetyRefresh;

    if (refreshFullConfig) {
      progress('Actualizando configuración...');
      await _yieldToUi();
      final results = await Future.wait<List<Map<String, dynamic>>?>([
        _trySelectAllFieldsSnapshot(),
        _trySelectAllRowsSnapshot('MATRIZ_FORMATOS_APPGT'),
        _trySelectAllRowsSnapshot('MATRIZ_FORMATO_TABLAS_APPGT'),
        _trySelectAllRowsSnapshot('MATRIZ_MODULOS_APPGT'),
        _trySelectAllRowsSnapshot('MATRIZ_SECCIONES_APPGT'),
        _trySelectAllRowsSnapshot('MATRIZ_VISTAS_DINAMICAS_APPGT'),
        _trySelectAllRowsSnapshot('MATRIZ_FORMATOS_ESPECIALES_APPGT'),
        _trySelectAllRowsSnapshot('RUBROS_APPGT'),
        _trySelectAllRowsSnapshot('MATRIZ_DROPDOWNS_APPGT'),
        _trySelectAllRowsSnapshot('MATRIZ_VALIDACIONES_APPGT'),
        _trySelectAllRowsSnapshot('MATRIZ_CONDICIONES_APPGT'),
        _trySelectAllRowsSnapshot('MATRIZ_FORMULAS_APPGT'),
        _trySelectAllRowsSnapshot('MATRIZ_ESTADOS_FLUJO_APPGT'),
      ]);
      if (forceConfigurationRefresh && results.any((rows) => rows == null)) {
        throw Exception(
          'No se pudo descargar la configuración completa desde Supabase.',
        );
      }
      final forcedFields = results[0];
      if (forcedFields != null) {
        fields = forcedFields;
        fieldsSnapshot = true;
      }
      final forcedFormats = results[1];
      if (forcedFormats != null) {
        formats = forcedFormats;
        formatsSnapshot = true;
      }
      final forcedFormatTables = results[2];
      if (forcedFormatTables != null) {
        formatTables = forcedFormatTables;
        formatTablesSnapshot = true;
      }
      final forcedModules = results[3];
      if (forcedModules != null) {
        modules = forcedModules;
        modulesSnapshot = true;
      }
      final forcedSections = results[4];
      if (forcedSections != null) {
        sections = forcedSections;
        sectionsSnapshot = true;
      }
      final forcedDynamicViews = results[5];
      if (forcedDynamicViews != null) {
        dynamicViews = forcedDynamicViews;
        dynamicViewsSnapshot = true;
      }
      final forcedSpecialFormats = results[6];
      if (forcedSpecialFormats != null) {
        specialFormats = forcedSpecialFormats;
        specialFormatsSnapshot = true;
      }
      final forcedRubros = results[7];
      if (forcedRubros != null) {
        rubros = forcedRubros;
        rubrosSnapshot = true;
      }
      final forcedDropdownRules = results[8];
      if (forcedDropdownRules != null) {
        dropdownRules = forcedDropdownRules;
        dropdownRulesSnapshot = true;
      }
      final forcedValidationRules = results[9];
      if (forcedValidationRules != null) {
        validationRules = forcedValidationRules;
        validationRulesSnapshot = true;
      }
      final forcedConditionRules = results[10];
      if (forcedConditionRules != null) {
        conditionRules = forcedConditionRules;
        conditionRulesSnapshot = true;
      }
      final forcedFormulaRules = results[11];
      if (forcedFormulaRules != null) {
        formulaRules = forcedFormulaRules;
        formulaRulesSnapshot = true;
      }
      final forcedFlowRules = results[12];
      if (forcedFlowRules != null) {
        flowRules = forcedFlowRules;
        flowRulesSnapshot = true;
      }
    }

    // Los permisos del usuario son pequeños y sí deben comprobarse en cada ingreso/actualización.
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId != null && currentUserId.isNotEmpty) {
      try {
        final permissionResults = await Future.wait<dynamic>([
          _supabase
              .from('PERMISOS_DE_USUARIOS_APPGT')
              .select()
              .eq('user_id', currentUserId),
          _supabase
              .from('PERMISOS_SECCIONES_APPGT')
              .select()
              .eq('user_id', currentUserId),
        ]);
        permissions =
            List<Map<String, dynamic>>.from(permissionResults[0] as List);
        sectionPermissions =
            List<Map<String, dynamic>>.from(permissionResults[1] as List);
        permissionsSnapshot = true;
        sectionPermissionsSnapshot = true;
      } catch (_) {
        if (forceConfigurationRefresh) rethrow;
      }
    }

    final removedModuleIds = _removedIds(modules);
    final removedFormatIds = _removedIds(formats);
    final removedFormatTableIds = _removedIds(formatTables);
    final removedPermissionIds = _removedIds(permissions);
    final removedProfileIds = _removedIds(profiles);
    final removedSectionIds = _removedIds(sections);
    final removedSectionPermissionIds = _removedIds(sectionPermissions);
    final removedSpecialFormatIds = _removedIds(specialFormats);
    final removedFieldIds = _removedIds(fields);
    final removedDynamicViewIds = _removedIds(dynamicViews);

    modules.removeWhere(_isRemovedRow);
    formats.removeWhere(_isRemovedRow);
    formatTables.removeWhere(_isRemovedRow);
    permissions.removeWhere(_isRemovedRow);
    profiles.removeWhere(_isRemovedRow);
    sections.removeWhere(_isRemovedRow);
    sectionPermissions.removeWhere(_isRemovedRow);
    specialFormats.removeWhere(_isRemovedRow);
    fields.removeWhere(_isRemovedRow);
    dynamicViews.removeWhere(_isRemovedRow);

    await _yieldToUi();
    progress('Detectando catálogos necesarios...');
    await _yieldToUi();
    final dynamicFields = List<Map<String, dynamic>>.from(fields);
    final fieldsForSourceDetection = dynamicFields.isNotEmpty
        ? dynamicFields
        : (incremental
            ? await _cachedLocalFieldsForSourceDetection()
            : dynamicFields);
    // Los dropdowns dependen de snapshots completos de sus tablas fuente. Solo
    // se descargan las fuentes marcadas como cambiadas, pero esas fuentes se
    // reemplazan completas para reflejar altas, ediciones y eliminaciones.
    final forceAllSourceTables =
        forceConfigurationRefresh || !incremental || changedTables == null;
    progress('Actualizando catálogos y fuentes de dropdown...');
    await _yieldToUi();
    final dropdownSourceRows = fieldsForSourceDetection.isEmpty
        ? <String, List<Map<String, dynamic>>>{}
        : await _downloadDynamicSourceTables(
            fieldsForSourceDetection,
            changedTables: changedTables,
            since: incremental ? previousMatricesSync : null,
            forceAllSources: forceAllSourceTables,
          );
    final dynamicSourceRows = <String, List<Map<String, dynamic>>>{
      ...dropdownSourceRows,
    };
    dynamicSourceRows['SN-MATRIZ_ESTADIOS_CONTEO_FRUTA'] = conteoEstadios;
    dynamicSourceRows['SN-MATRIZ_CONCEPTOS_ESTADIOS_PLAGAS'] = plagasConceptos;
    dynamicSourceRows['SN-MATRIZ_ETAPAS_FENOLOGICAS'] = etapasFenologicas;
    dynamicSourceRows['LOTES_VARIEDADES_GT'] = lotesVariedades;
    dynamicSourceRows['RUBROS_APPGT'] = rubros;
    dynamicSourceRows['MATRIZ_DROPDOWNS_APPGT'] = dropdownRules;
    dynamicSourceRows['MATRIZ_VALIDACIONES_APPGT'] = validationRules;
    dynamicSourceRows['MATRIZ_CONDICIONES_APPGT'] = conditionRules;
    dynamicSourceRows['MATRIZ_FORMULAS_APPGT'] = formulaRules;
    final flowRulesForCache = flowRules.isNotEmpty || flowRulesSnapshot
        ? flowRules
        : ((!incremental ||
                changedTables == null ||
                _tableChanged(changedTables, 'MATRIZ_ESTADOS_FLUJO_APPGT'))
            ? await _downloadFlowRules()
            : <Map<String, dynamic>>[]);
    if (flowRulesForCache.isNotEmpty || flowRulesSnapshot) {
      dynamicSourceRows['MATRIZ_ESTADOS_FLUJO_APPGT'] = flowRulesForCache;
    }

    // Registros Pendientes debe funcionar offline después de Actualizar datos.
    // En modo incremental puede que MATRIZ_VISTAS_DINAMICAS_APPGT no venga porque
    // no cambió; aun así las tablas destino sí pueden tener registros nuevos.
    // Por eso usamos las vistas recibidas o, si no vinieron, las vistas ya cacheadas.
    if (shouldCacheOperationalRecords) {
      final dynamicViewsForDataTables = dynamicViews.isNotEmpty
          ? dynamicViews
          : await _local.getAll('local_dynamic_views');
      dynamicSourceRows.addAll(await _downloadDynamicViewDataTables(
        dynamicViewsForDataTables,
        changedTables: changedTables,
        since: incremental ? previousDataSync : null,
        forceAllTables: !incremental || changedTables == null,
      ));
    }

    // Cachear tablas reales de formatos con estrategia incremental inteligente.
    // Primera descarga: completo. Siguientes actualizaciones: solo tablas marcadas
    // en APPGT_TABLAS_CAMBIADAS. La vista Windows ya no depende de esta caché para
    // abrir rápido; exportación/auditoría hacen carga completa bajo demanda.
    if (shouldCacheOperationalRecords) {
      progress('Actualizando registros modificados...');
      await _yieldToUi();
      dynamicSourceRows.addAll(await _downloadFormatRecordTables(
        formats,
        formatTables,
        changedTables: changedTables,
        since: incremental ? previousDataSync : null,
        forceAllTables: !incremental || changedTables == null,
      ));
    } else {
      progress('Web listo: los registros se consultarán por páginas...');
      await _yieldToUi();
    }

    await _yieldToUi();
    final catalogValues = <Map<String, dynamic>>[
      ...await _downloadCatalogValues(
        changedTables: changedTables,
        forceAll:
            forceConfigurationRefresh || !incremental || changedTables == null,
      ),
      ..._dynamicCatalogValues(fieldsForSourceDetection, dropdownSourceRows),
    ];
    final refreshedCatalogKeys = <String>{
      ..._dynamicCatalogKeysForTables(
        fieldsForSourceDetection,
        dropdownSourceRows.keys,
      ),
      for (final spec in _catalogSpecs)
        if (forceConfigurationRefresh ||
            !incremental ||
            changedTables == null ||
            _tableChanged(changedTables, spec['table']!))
          spec['key']!,
    };

    progress('Guardando módulos, permisos y formatos...');
    await _yieldToUi();
    await saveLocal(
      'local_modules',
      modules
          .map((e) => {
                'id': e['id'],
                'empresa_id': e['empresa_id']?.toString() ?? activeEmpresaId,
                'nombre': e['nombre'],
                'seccion': e['seccion']?.toString().trim() ?? '',
                'icono': e['icono']?.toString() ?? 'apps',
                'color': e['color']?.toString(),
                'rubro_id': e['rubro_id']?.toString(),
                'orden': e['orden'] ?? 0,
                'activo': _activeInt(e),
              })
          .where((e) => (e['activo'] as int) == 1)
          .toList(),
      snapshot: modulesSnapshot,
      deletedIds: removedModuleIds,
    );

    await saveLocal(
      'local_formats',
      formats
          .map((e) => {
                'id': e['id'],
                'empresa_id': e['empresa_id']?.toString() ?? activeEmpresaId,
                'modulo_id': e['modulo_id'],
                'nombre': e['nombre'],
                'rubro_id': e['rubro_id']?.toString(),
                'tabla_destino': e['tabla_destino'],
                'ruta_flutter': e['ruta_flutter'],
                'tabla_visible_app': _boolValue(e['tabla_visible_app']) ? 1 : 0,
                'capacidades': e['capacidades'] is Map
                    ? jsonEncode(e['capacidades'])
                    : (e['capacidades']?.toString() ?? '{}'),
                'flujo_estados': e['flujo_estados'] is List
                    ? jsonEncode(e['flujo_estados'])
                    : (e['flujo_estados']?.toString() ?? '[]'),
                'workflow_enabled': _boolValue(e['workflow_enabled']) ? 1 : 0,
                'geolocation_enabled':
                    _boolValue(e['geolocation_enabled']) ? 1 : 0,
                'approvals_enabled': _boolValue(e['approvals_enabled']) ? 1 : 0,
                'layout_formulario':
                    e['layout_formulario']?.toString() ?? 'VERTICAL',
                'layout_registros':
                    e['layout_registros']?.toString() ?? 'TABLA',
                'estado_revision_ia':
                    e['estado_revision_ia']?.toString() ?? 'APROBADA',
                'auditable': _boolValueOrDefault(e['auditable'], true) ? 1 : 0,
                'icono': e['icono']?.toString() ?? 'assignment',
                'imagen_encabezado': e['imagen_encabezado']?.toString(),
                'orden': e['orden'] ?? 0,
                'activo': _activeInt(e),
              })
          .where((e) => (e['activo'] as int) == 1)
          .toList(),
      snapshot: formatsSnapshot,
      deletedIds: removedFormatIds,
    );

    await saveLocal(
      'local_format_tables',
      formatTables
          .map((e) => {
                'id': e['id'],
                'empresa_id': e['empresa_id']?.toString() ?? activeEmpresaId,
                'formato_id': e['formato_id'],
                'nombre': e['nombre'],
                'rubro_id': e['rubro_id']?.toString(),
                'tabla_destino': e['tabla_destino'],
                'orden': e['orden'] ?? 0,
                'tipo_relacion':
                    _valueByColumn(e, ['tipo_relacion', 'tipo relacion'])
                        ?.toString(),
                'tabla_padre': _valueByColumn(e, ['tabla_padre', 'tabla padre'])
                    ?.toString(),
                'campo_pk_padre': _valueByColumn(
                        e, ['campo_pk_padre', 'campo pk padre', 'pk_padre'])
                    ?.toString(),
                'campo_fk_hijo': _valueByColumn(
                        e, ['campo_fk_hijo', 'campo fk hijo', 'fk_hijo'])
                    ?.toString(),
                'es_cabecera': _boolValueOrDefault(
                        _valueByColumn(e, ['es_cabecera', 'es cabecera']),
                        false)
                    ? 1
                    : 0,
                'es_detalle': _boolValueOrDefault(
                        _valueByColumn(e, ['es_detalle', 'es detalle']), false)
                    ? 1
                    : 0,
                'campo_iterador':
                    _valueByColumn(e, ['campo_iterador', 'campo iterador'])
                        ?.toString(),
                'iterador_desde':
                    _valueByColumn(e, ['iterador_desde', 'iterador desde']),
                'iterador_hasta':
                    _valueByColumn(e, ['iterador_hasta', 'iterador hasta']),
                'copiar_campos_desde_padre': _valueByColumn(e, [
                  'copiar_campos_desde_padre',
                  'copiar campos desde padre'
                ])?.toString(),
                'modo_captura':
                    _valueByColumn(e, ['modo_captura', 'modo captura'])
                        ?.toString(),
                'auditable':
                    _boolValueOrDefault(_valueByColumn(e, ['auditable']), true)
                        ? 1
                        : 0,
                'icono':
                    _valueByColumn(e, ['icono'])?.toString() ?? 'assignment',
                'imagen_encabezado':
                    _valueByColumn(e, ['imagen_encabezado'])?.toString(),
                'activo': _activeInt(e),
              })
          .where((e) => (e['activo'] as int) == 1)
          .toList(),
      snapshot: formatTablesSnapshot,
      deletedIds: removedFormatTableIds,
    );

    await saveLocal(
      'local_permissions',
      permissions
          .map((e) => {
                'id': e['id'],
                'empresa_id': e['empresa_id']?.toString() ?? activeEmpresaId,
                'user_id': e['user_id'],
                'modulo': e['modulo'],
                'formato': e['formato'],
                'can_view': _boolValue(e['can_view']) ? 1 : 0,
                'can_insert': _boolValue(e['can_insert']) ? 1 : 0,
                'can_update': _boolValue(e['can_update']) ? 1 : 0,
                'can_delete': _boolValue(e['can_delete']) ? 1 : 0,
                'can_export': _boolValue(e['can_export']) ? 1 : 0,
                'can_import': _boolValue(e['can_import']) ? 1 : 0,
                'can_review': _boolValue(e['can_review']) ? 1 : 0,
                'can_approve': _boolValue(e['can_approve']) ? 1 : 0,
                'can_view_pending': _boolValue(e['can_view_pending']) ? 1 : 0,
                'can_complete_pending':
                    _boolValue(e['can_complete_pending']) ? 1 : 0,
                'seccion': e['seccion']?.toString() ?? '',
                'campos_restringidos': e['campos_restringidos'] is List
                    ? jsonEncode(e['campos_restringidos'])
                    : (e['campos_restringidos']?.toString() ?? '[]'),
                'permisos_flujo': e['permisos_flujo'] is List
                    ? jsonEncode(e['permisos_flujo'])
                    : (e['permisos_flujo']?.toString() ?? '[]'),
              })
          .toList(),
      snapshot: permissionsSnapshot,
      deletedIds: removedPermissionIds,
    );

    await saveLocal(
      'local_dynamic_views',
      List<Map<String, dynamic>>.from(dynamicViews)
          .map((e) => {
                'id': e['id']?.toString() ??
                    '${e['seccion']}_${e['modulo']}_${e['nombre_vista']}',
                'empresa_id': e['empresa_id']?.toString() ?? activeEmpresaId,
                'seccion': e['seccion']?.toString() ?? '',
                'modulo': e['modulo']?.toString() ?? '',
                'tipo_vista': e['tipo_vista']?.toString() ?? 'tabla',
                'tabla_destino': e['tabla_destino']?.toString() ?? '',
                'nombre_vista': e['nombre_vista']?.toString() ?? '',
                'estado_origen': e['estado_origen']?.toString() ?? '',
                'estado_destino': e['estado_destino']?.toString() ?? '',
                'filtro_estado': e['filtro_estado']?.toString() ?? '',
                'campos_pendientes': e['campos_pendientes']?.toString() ?? '',
                'campos_editables': e['campos_editables']?.toString() ?? '',
                'campos_visibles': e['campos_visibles']?.toString() ?? '',
                'requiere_todos_campos':
                    _boolValue(e['requiere_todos_campos']) ? 1 : 0,
                'activo': _activeInt(e),
                'orden': e['orden'] ?? 0,
                'payload_json': jsonEncode(e),
              })
          .where((e) =>
              (e['seccion'] as String).isNotEmpty &&
              (e['tabla_destino'] as String).isNotEmpty &&
              (e['activo'] as int) == 1)
          .toList(),
      snapshot: dynamicViewsSnapshot,
      deletedIds: removedDynamicViewIds,
    );

    await saveLocal(
      'local_profile',
      profiles
          .map((e) => {
                'id': e['id']?.toString() ?? '',
                'empresa_id': e['empresa_id']?.toString() ?? activeEmpresaId,
                'nombres': (e['nombres'] ?? e['Nombres'] ?? e['NOMBRES'])
                        ?.toString() ??
                    '',
                'cargo': e['cargo']?.toString() ?? '',
                'area': e['area']?.toString() ?? '',
                'dni': (e['dni'] ??
                            e['DNI'] ??
                            e['documento'] ??
                            e['DOCUMENTO'] ??
                            e['numero_documento'] ??
                            e['NUMERO_DOCUMENTO'])
                        ?.toString() ??
                    '',
                'email':
                    (e['email'] ?? e['correo'] ?? e['CORREO'])?.toString() ??
                        '',
                'activo': 1,
              })
          .where((e) => (e['id'] as String).isNotEmpty)
          .toList(),
      snapshot: profilesSnapshot,
      deletedIds: removedProfileIds,
    );

    await saveLocal(
      'local_sections',
      sections
          .map((e) {
            final id = e['id']?.toString() ?? '';
            return {
              'id': id,
              'empresa_id': e['empresa_id']?.toString() ?? activeEmpresaId,
              'nombre': e['nombre']?.toString() ?? id,
              'icono': e['icono']?.toString() ?? 'apps',
              'color': e['color']?.toString(),
              'rubro_id': e['rubro_id']?.toString(),
              'tipo_contenido': e['tipo_contenido']?.toString() ?? 'GENERICO',
              'ruta_flutter': e['ruta_flutter']?.toString(),
              'orden': e['orden'] ?? 0,
              'numero_decimales': e['numero_decimales'],
              'grid_fila': e['grid_fila'],
              'grid_columna': e['grid_columna'] ?? e['grid columna'],
              'activo': _activeInt(e),
            };
          })
          .where((e) =>
              (e['id'] as String).isNotEmpty && (e['activo'] as int) == 1)
          .toList(),
      snapshot: sectionsSnapshot,
      deletedIds: removedSectionIds,
    );

    await saveLocal(
      'local_section_permissions',
      sectionPermissions
          .map((e) {
            final sectionId = e['seccion']?.toString().trim().isNotEmpty == true
                ? e['seccion'].toString().trim()
                : (e['seccion_id']?.toString().trim() ?? '');
            final userId = e['user_id']?.toString() ?? '';
            return {
              'id': e['id']?.toString() ?? '${userId}_$sectionId',
              'empresa_id': e['empresa_id']?.toString() ?? activeEmpresaId,
              'user_id': userId,
              'seccion_id': sectionId,
              'can_view': (!_isDeletedRow(e) && _activeInt(e) == 1) ? 1 : 0,
              'can_insert': _boolValue(e['can_insert']) ? 1 : 0,
              'can_update': _boolValue(e['can_update']) ? 1 : 0,
              'can_delete': _boolValue(e['can_delete']) ? 1 : 0,
            };
          })
          .where((e) => (e['seccion_id'] as String).isNotEmpty)
          .toList(),
      snapshot: sectionPermissionsSnapshot,
      deletedIds: removedSectionPermissionIds,
    );

    await saveLocal(
      'local_special_formats',
      specialFormats
          .map((e) => {
                'id': e['id'],
                'empresa_id': e['empresa_id']?.toString() ?? activeEmpresaId,
                'modulo_id': e['modulo_id'],
                'formato_id': e['formato_id'],
                'tipo_pantalla': e['tipo_pantalla'],
                'descripcion': e['descripcion'],
                'activo': _activeInt(e),
                'orden': e['orden'] ?? 0,
              })
          .where((e) => (e['activo'] as int) == 1)
          .toList(),
      snapshot: specialFormatsSnapshot,
      deletedIds: removedSpecialFormatIds,
    );

    progress('Guardando matriz de campos...');
    await _yieldToUi();
    final fieldRows = <Map<String, dynamic>>[];
    for (final e in fields) {
      if (_isDeletedRow(e)) continue;
      fieldRows.add({
        'id': e['id']?.toString() ?? '${e['tabla_destino']}_${e['campo']}',
        'empresa_id': e['empresa_id']?.toString() ?? activeEmpresaId,
        'tabla_destino': e['tabla_destino'],
        'campo': e['campo'],
        'etiqueta': e['etiqueta'] ?? e['campo'],
        'tipo': e['tipo_control'] ?? e['tipo'] ?? 'text',
        'tipo_ui': e['tipo_ui'] ?? e['tipo_control'] ?? e['tipo'] ?? 'text',
        'id_campo_dropdown': e['id_campo_dropdown']?.toString(),
        'formula_funcion': (e['formula_funcion'] ?? e['formula'])?.toString(),
        'formula_tipo': e['formula_tipo']?.toString(),
        'formula_tabla_origen': e['formula_tabla_origen']?.toString(),
        'formula_campo_valor': e['formula_campo_valor']?.toString(),
        'formula_campo_condicion': e['formula_campo_condicion']?.toString(),
        'formula_valor_condicion': e['formula_valor_condicion']?.toString(),
        'valor_default': e['valor_default']?.toString(),
        'id_generador': e['id_generador']?.toString(),
        'editable': e['editable'] == false ? 0 : 1,
        'visible': e['visible'] == false ? 0 : 1,
        'visible_tabla': (_boolValueOrDefault(
                _valueByColumn(e, [
                  'visible_tabla',
                  'visible tabla',
                  'visible_en_tabla',
                  'visible en tabla'
                ]),
                e['visible'] == false ? false : true)
            ? 1
            : 0),
        'requerido': _boolValue(e['requerido']) ? 1 : 0,
        'orden': e['orden'] ?? 0,
        'numero_decimales': _valueByColumn(
            e, ['numero_decimales', 'numero decimales', 'decimales']),
        'grid_fila':
            _valueByColumn(e, ['grid_fila', 'grid fila', 'fila', 'fila_grid']),
        'grid_columna': _valueByColumn(
            e, ['grid_columna', 'grid columna', 'columna', 'columna_grid']),
        'grid_fila_pendientes': _valueByColumn(e, [
          'grid_fila_pendientes',
          'grid fila pendientes',
          'fila_pendientes',
          'fila pendientes'
        ]),
        'grid_columna_pendientes': _valueByColumn(e, [
          'grid_columna_pendientes',
          'grid columna pendientes',
          'columna_pendientes',
          'columna pendientes'
        ]),
        'rango_valor': _valueByColumn(
                e, ['rango_valor', 'rango valor', 'rango', 'validacion_rango'])
            ?.toString(),
        'num_caracteres': _valueByColumn(e, [
          'num_caracteres',
          'num caracteres',
          'max_caracteres',
          'max caracteres'
        ]),
        'numero_fotos': _valueByColumn(e, [
          'numero_fotos',
          'numero fotos',
          'fotos',
          'max_fotos',
          'max fotos'
        ]),
        'photo_depende_de': _valueByColumn(e, [
          'photo_depende_de',
          'photo depende de',
          'depende_de_photo',
          'depende de photo',
          'depende_de'
        ])?.toString(),
        'lista_destino_photo': _valueByColumn(e, [
          'lista_destino_photo',
          'lista destino photo',
          'grupo_photo',
          'grupo photo',
          'lista_photo',
          'lista photo'
        ])?.toString(),
        'orden_lista_photo': _valueByColumn(e, [
          'orden_lista_photo',
          'orden lista photo',
          'orden_photo',
          'orden photo',
          'orden_lista'
        ]),
        'formato_condicional_campo': _valueByColumn(e, [
          'formato_condicional_campo',
          'formato condicional campo',
          'condicion_formato',
          'condición formato',
          'formato_condicional'
        ])?.toString(),
        'condicion_color_texto':
            _valueByColumn(e, ['condicion_color_texto'])?.toString(),
        'condicion_color_fondo':
            _valueByColumn(e, ['condicion_color_fondo'])?.toString(),
        'condicion_color_borde':
            _valueByColumn(e, ['condicion_color_borde'])?.toString(),
        'color_texto':
            _valueByColumn(e, ['color_texto', 'color texto', 'texto_color'])
                ?.toString(),
        'color_fondo':
            _valueByColumn(e, ['color_fondo', 'color fondo', 'fondo_color'])
                ?.toString(),
        'color_borde':
            _valueByColumn(e, ['color_borde', 'color borde', 'borde_color'])
                ?.toString(),
        'tamanio_letra': _valueByColumn(e, ['tamanio_letra', 'tamano_letra']),
        'aplicar_formato_condicional_tabla': _boolValueOrDefault(
                _valueByColumn(e, [
                  'aplicar_formato_condicional_tabla',
                  'aplicar formato condicional tabla',
                  'aplicar_condicional_tabla',
                  'formato_condicional_tabla'
                ]),
                false)
            ? 1
            : 0,
        'sub_titulo': _valueByColumn(
                e, ['sub_titulo', 'sub titulo', 'subtítulo', 'subtitulo'])
            ?.toString(),
        'fila_sub_titulo': _valueByColumn(e, [
          'fila_sub_titulo',
          'fila sub titulo',
          'fila_subtitulo',
          'fila subtitulo'
        ]),
        'subtitulo_alineacion':
            _valueByColumn(e, ['subtitulo_alineacion'])?.toString(),
        'subtitulo_tamanio_letra':
            _valueByColumn(e, ['subtitulo_tamanio_letra']),
        'subtitulo_color': _valueByColumn(e, ['subtitulo_color'])?.toString(),
        'subtitulo_padding':
            _valueByColumn(e, ['subtitulo_padding'])?.toString(),
        'grupo_captura':
            _valueByColumn(e, ['grupo_captura', 'grupo captura'])?.toString(),
        'titulo1':
            _valueByColumn(e, ['titulo1', 'titulo_1', 'titulo v1', 'titulo_v1'])
                ?.toString(),
        'titulo2':
            _valueByColumn(e, ['titulo2', 'titulo_2', 'titulo v2', 'titulo_v2'])
                ?.toString(),
        'codigo1':
            _valueByColumn(e, ['codigo1', 'codigo_1', 'codigo v1', 'codigo_v1'])
                ?.toString(),
        'codigo2':
            _valueByColumn(e, ['codigo2', 'codigo_2', 'codigo v2', 'codigo_v2'])
                ?.toString(),
        'titulo1_alineacion':
            _valueByColumn(e, ['titulo1_alineacion'])?.toString(),
        'titulo1_tamanio_letra': _valueByColumn(e, ['titulo1_tamanio_letra']),
        'titulo1_color': _valueByColumn(e, ['titulo1_color'])?.toString(),
        'titulo1_padding': _valueByColumn(e, ['titulo1_padding'])?.toString(),
        'titulo2_alineacion':
            _valueByColumn(e, ['titulo2_alineacion'])?.toString(),
        'titulo2_tamanio_letra': _valueByColumn(e, ['titulo2_tamanio_letra']),
        'titulo2_color': _valueByColumn(e, ['titulo2_color'])?.toString(),
        'titulo2_padding': _valueByColumn(e, ['titulo2_padding'])?.toString(),
        'activo': _activeInt(e),
      });
    }
    fieldRows.removeWhere((e) => (e['activo'] as int? ?? 1) != 1);
    await saveLocal(
      'local_form_fields',
      fieldRows,
      snapshot: fieldsSnapshot,
      deletedIds: removedFieldIds,
    );

    final lotesRows = <String, Map<String, dynamic>>{};
    for (final e in lotesVariedades) {
      final turno = e['TURNO']?.toString().trim() ?? '';
      if (turno.isEmpty) continue;
      lotesRows[turno] = {
        'turno': turno,
        'variedad': e['VARIEDAD']?.toString().trim() ?? '',
        'latitud': _valueByColumn(e, ['LATITUD', 'LATITUDE']),
        'longitud': _valueByColumn(e, ['LONGITUD', 'LONGITUDE']),
        'precision_gps':
            _valueByColumn(e, ['PRECISION_GPS', 'PRECISION GPS', 'ACCURACY']),
        'fecha_gps':
            _valueByColumn(e, ['FECHA_GPS', 'FECHA GPS', 'GPS_AT'])?.toString(),
      };
    }
    await saveLocal(
      'local_lotes_variedades',
      lotesRows.values.toList(),
      snapshot: lotesSnapshot,
      keyColumn: null,
    );
    if (incremental) {
      await _local.replaceCatalogValuesForKeys(
        refreshedCatalogKeys,
        catalogValues,
      );
    } else {
      await saveLocal(
        'local_catalog_values',
        catalogValues,
        snapshot: true,
        keyColumn: null,
      );
    }
    await _yieldToUi();
    progress('Guardando caché local de registros...');
    await _yieldToUi();
    final snapshotSourceNames = <String>{
      ...dropdownSourceRows.keys,
      if (rubrosSnapshot) 'RUBROS_APPGT',
      if (dropdownRulesSnapshot) 'MATRIZ_DROPDOWNS_APPGT',
      if (validationRulesSnapshot) 'MATRIZ_VALIDACIONES_APPGT',
      if (conditionRulesSnapshot) 'MATRIZ_CONDICIONES_APPGT',
      if (formulaRulesSnapshot) 'MATRIZ_FORMULAS_APPGT',
      if (flowRulesSnapshot) 'MATRIZ_ESTADOS_FLUJO_APPGT',
    };
    final snapshotSourceRows = <String, List<Map<String, dynamic>>>{
      for (final table in snapshotSourceNames)
        if (dynamicSourceRows.containsKey(table))
          table: dynamicSourceRows[table]!,
    };
    if (snapshotSourceRows.isNotEmpty) {
      await _local.applyMatrixRowsFromPayloads(
        snapshotSourceRows,
        replaceSources: true,
      );
    }
    final remainingSourceRows = snapshotSourceRows.isNotEmpty
        ? (Map<String, List<Map<String, dynamic>>>.from(dynamicSourceRows)
          ..removeWhere((table, _) => snapshotSourceNames.contains(table)))
        : dynamicSourceRows;
    await _local.applyMatrixRowsFromPayloads(
      remainingSourceRows,
      replaceSources: !incremental,
    );
    await _yieldToUi();

    final conceptoRows = <String, Map<String, dynamic>>{};
    for (final e in plagasConceptos) {
      final concepto = _valueByColumn(e, ['CONCEPTO'])?.toString().trim() ?? '';
      final estadio = _valueByColumn(e, [
            'ESTADIO O TIPO',
            'ESTADIOS O TIPOS',
            'ESTADIOS O TIPO',
            'ESTADIO_O_TIPO',
            'ESTADIOS_O_TIPOS',
            'ESTADIO',
            'TIPO'
          ])?.toString().trim() ??
          '';
      if (concepto.isEmpty || estadio.isEmpty) continue;
      final id = '$concepto$estadio';
      conceptoRows[id] = {
        'id': id,
        'concepto': concepto,
        'estadio': estadio,
        'formula': _valueByColumn(e, ['FORMULA'])?.toString().trim() ?? ''
      };
    }
    await saveLocal(
      'local_plagas_conceptos',
      conceptoRows.values.toList(),
      snapshot: plagasSnapshot,
    );

    final fenologiaRows = <String, Map<String, dynamic>>{};
    for (final e in etapasFenologicas) {
      final etapa = _valueByColumn(e, [
            'ETAPA_FENOLOGICA',
            'ETAPA FENOLOGICA',
            'ETAPA FENOLÓGICA',
            'FENOLOGIA',
            'FENOLOGÍA',
            'FENOLOGICA',
            'FENOLÓGICA',
            'ETAPA'
          ])?.toString().trim() ??
          '';
      if (etapa.isEmpty) continue;
      fenologiaRows[etapa] = {'etapa_fenologica': etapa};
    }
    await saveLocal(
      'local_fenologias',
      fenologiaRows.isNotEmpty
          ? fenologiaRows.values.toList()
          : (fenologiasSnapshot
              ? _fallbackFenologiaRows()
              : <Map<String, dynamic>>[]),
      snapshot: fenologiasSnapshot,
      keyColumn: 'etapa_fenologica',
    );

    final conteoRows = <String, Map<String, dynamic>>{};
    for (final e in conteoEstadios) {
      final estadio = _valueByColumn(e, [
            'ESTADIO O TIPO',
            'ESTADIOS O TIPOS',
            'ESTADIOS O TIPO',
            'ESTADIO_O_TIPO',
            'ESTADIOS_O_TIPOS',
            'ESTADIO',
            'TIPO'
          ])?.toString().trim() ??
          '';
      if (estadio.isEmpty) continue;
      conteoRows[estadio] = {
        'estadio': estadio,
        'formula': _valueByColumn(e, ['FORMULA'])?.toString().trim() ?? ''
      };
    }
    await saveLocal(
      'local_conteo_estadios',
      conteoRows.values.toList(),
      snapshot: conteoSnapshot,
      keyColumn: 'estadio',
    );
    progress('Finalizando actualización...');
    await _yieldToUi();
    final fullConfigSnapshotReady = modulesSnapshot &&
        formatsSnapshot &&
        formatTablesSnapshot &&
        sectionsSnapshot &&
        specialFormatsSnapshot &&
        fieldsSnapshot &&
        dynamicViewsSnapshot &&
        rubrosSnapshot &&
        dropdownRulesSnapshot &&
        validationRulesSnapshot &&
        conditionRulesSnapshot &&
        formulaRulesSnapshot &&
        flowRulesSnapshot;
    final checkpoints = <String, String>{
      'bootstrap_last_sync_at': syncCheckpoint,
      'sync_checkpoint_config_at': syncCheckpoint,
      'sync_checkpoint_data_at': syncCheckpoint,
      'sync_checkpoint_permissions_at': syncCheckpoint,
      'sync_checkpoint_matrices_at': syncCheckpoint,
      'sync_schema_version': '29',
    };
    if (configurationVersion is Map) {
      final normalized = Map<String, dynamic>.from(configurationVersion);
      checkpoints['configuration_version_json'] = jsonEncode(normalized);
      final number = normalized['numero_version']?.toString().trim() ?? '';
      final version = normalized['version']?.toString().trim() ?? '';
      final publishedAt = normalized['published_at']?.toString().trim() ?? '';
      if (number.isNotEmpty)
        checkpoints['configuration_version_number'] = number;
      if (version.isNotEmpty) checkpoints['configuration_version'] = version;
      if (publishedAt.isNotEmpty) {
        checkpoints['configuration_published_at'] = publishedAt;
      }
    }
    if (offlinePolicy is Map) {
      checkpoints['offline_policy_json'] =
          jsonEncode(Map<String, dynamic>.from(offlinePolicy));
    }
    if (refreshFullConfig && fullConfigSnapshotReady) {
      checkpoints['config_full_refresh_at'] = syncCheckpoint;
    }
    await _local.setMetaValues(checkpoints);
  }

  Future<void> refreshLoginPermissionsOnly() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final activeEmpresaId = await LocalSession().cachedEmpresaId();

    final results = await Future.wait<dynamic>([
      _supabase.from('PERFILES_DE_USUARIOS_APPGT').select().eq('id', user.id),
      _supabase
          .from('PERMISOS_DE_USUARIOS_APPGT')
          .select()
          .eq('user_id', user.id),
      _supabase
          .from('PERMISOS_SECCIONES_APPGT')
          .select()
          .eq('user_id', user.id),
    ]);

    final profiles = List<Map<String, dynamic>>.from(results[0] as List);
    final permissions = List<Map<String, dynamic>>.from(results[1] as List);
    final sectionPermissions =
        List<Map<String, dynamic>>.from(results[2] as List);

    await _local.upsertTable(
      'local_profile',
      profiles
          .map((e) => {
                'id': e['id']?.toString() ?? '',
                'empresa_id': e['empresa_id']?.toString() ?? activeEmpresaId,
                'nombres': (e['nombres'] ?? e['Nombres'] ?? e['NOMBRES'])
                        ?.toString() ??
                    '',
                'cargo': e['cargo']?.toString() ?? '',
                'area': e['area']?.toString() ?? '',
                'dni': (e['dni'] ??
                            e['DNI'] ??
                            e['documento'] ??
                            e['DOCUMENTO'] ??
                            e['numero_documento'] ??
                            e['NUMERO_DOCUMENTO'])
                        ?.toString() ??
                    '',
                'email':
                    (e['email'] ?? e['correo'] ?? e['CORREO'])?.toString() ??
                        '',
                'activo': 1,
              })
          .where((e) => (e['id'] as String).isNotEmpty)
          .toList(),
    );

    await _local.replaceRowsWhere(
      'local_permissions',
      permissions
          .map((e) => {
                'id': e['id'],
                'empresa_id': e['empresa_id']?.toString() ?? activeEmpresaId,
                'user_id': e['user_id'],
                'modulo': e['modulo'],
                'formato': e['formato'],
                'can_view': _boolValue(e['can_view']) ? 1 : 0,
                'can_insert': _boolValue(e['can_insert']) ? 1 : 0,
                'can_update': _boolValue(e['can_update']) ? 1 : 0,
                'can_delete': _boolValue(e['can_delete']) ? 1 : 0,
                'can_export': _boolValue(e['can_export']) ? 1 : 0,
                'can_import': _boolValue(e['can_import']) ? 1 : 0,
                'can_view_pending': _boolValue(e['can_view_pending']) ? 1 : 0,
                'can_complete_pending':
                    _boolValue(e['can_complete_pending']) ? 1 : 0,
                'seccion': e['seccion']?.toString() ?? '',
                'campos_restringidos': e['campos_restringidos'] is List
                    ? jsonEncode(e['campos_restringidos'])
                    : (e['campos_restringidos']?.toString() ?? '[]'),
                'permisos_flujo': e['permisos_flujo'] is List
                    ? jsonEncode(e['permisos_flujo'])
                    : (e['permisos_flujo']?.toString() ?? '[]'),
              })
          .where((e) => e['id'] != null)
          .toList(),
      where: 'user_id = ? and empresa_id = ?',
      whereArgs: [user.id, activeEmpresaId],
    );

    await _local.replaceRowsWhere(
      'local_section_permissions',
      sectionPermissions
          .map((e) {
            final sectionId = e['seccion']?.toString().trim().isNotEmpty == true
                ? e['seccion'].toString().trim()
                : (e['seccion_id']?.toString().trim() ?? '');
            final userId = e['user_id']?.toString() ?? '';
            return {
              'id': e['id']?.toString() ?? '${userId}_$sectionId',
              'empresa_id': e['empresa_id']?.toString() ?? activeEmpresaId,
              'user_id': userId,
              'seccion_id': sectionId,
              'can_view': (!_isDeletedRow(e) && _activeInt(e) == 1) ? 1 : 0,
              'can_insert': _boolValue(e['can_insert']) ? 1 : 0,
              'can_update': _boolValue(e['can_update']) ? 1 : 0,
              'can_delete': _boolValue(e['can_delete']) ? 1 : 0,
            };
          })
          .where((e) => (e['seccion_id'] as String).isNotEmpty)
          .toList(),
      where: 'user_id = ? and empresa_id = ?',
      whereArgs: [user.id, activeEmpresaId],
    );

    final checkpoint = DateTime.now().toUtc().toIso8601String();
    await _local.setMetaValues({
      'permissions_last_check_at': checkpoint,
      'sync_checkpoint_permissions_at': checkpoint,
    });
  }

  Future<void> downloadCatalogs(
      {void Function(String message)? onProgress}) async {
    void progress(String message) => onProgress?.call(message);
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');

    final modules = await _supabase
        .from('MATRIZ_MODULOS_APPGT')
        .select()
        .eq('activo', true)
        .order('orden');

    final formats =
        await _supabase.from('MATRIZ_FORMATOS_APPGT').select().order('orden');

    final formatTables = await _supabase
        .from('MATRIZ_FORMATO_TABLAS_APPGT')
        .select()
        .eq('activo', true)
        .order('orden');

    final permissions = await _supabase
        .from('PERMISOS_DE_USUARIOS_APPGT')
        .select()
        .eq('user_id', user.id);

    final profiles = await _supabase
        .from('PERFILES_DE_USUARIOS_APPGT')
        .select()
        .eq('id', user.id);

    List<dynamic> sections = [];
    try {
      sections = await _supabase
          .from('MATRIZ_SECCIONES_APPGT')
          .select()
          .eq('activo', true)
          .order('orden');
    } catch (_) {
      sections = [];
    }

    List<dynamic> sectionPermissions = [];
    try {
      sectionPermissions = await _supabase
          .from('PERMISOS_SECCIONES_APPGT')
          .select()
          .eq('user_id', user.id);
    } catch (_) {
      sectionPermissions = [];
    }

    List<dynamic> specialFormats = [];
    try {
      specialFormats = await _supabase
          .from('MATRIZ_FORMATOS_ESPECIALES_APPGT')
          .select()
          .eq('activo', true)
          .order('orden');
    } catch (_) {
      specialFormats = [];
    }

    List<dynamic> dynamicViews = [];
    try {
      dynamicViews = await _supabase
          .from('MATRIZ_VISTAS_DINAMICAS_APPGT')
          .select()
          .eq('activo', true)
          .order('orden');
    } catch (_) {
      dynamicViews = [];
    }

    final flowRulesForCache = await _downloadFlowRules();

    List<dynamic> fields = [];
    try {
      fields = await _selectAllFieldsPaged();
    } catch (_) {
      fields = [];
    }

    progress('Detectando catálogos necesarios...');
    await _yieldToUi();
    final dynamicFields = List<Map<String, dynamic>>.from(fields);
    final dynamicSourceRows = await _downloadDynamicSourceTables(dynamicFields);

    List<dynamic> lotesVariedades = [];
    try {
      lotesVariedades = await _supabase
          .from('LOTES_VARIEDADES_GT')
          .select('TURNO, VARIEDAD')
          .order('TURNO');
    } catch (_) {
      lotesVariedades = [];
    }

    final plagasConceptos = await _safeSelect(
      'SN-MATRIZ_CONCEPTOS_ESTADIOS_PLAGAS',
      'CONCEPTO,"ESTADIO O TIPO",FORMULA',
    );

    final etapasFenologicas = await _safeSelect(
      'SN-MATRIZ_ETAPAS_FENOLOGICAS',
      'ETAPA_FENOLOGICA,CULTIVO,ID',
    );

    List<dynamic> conteoEstadios = [];
    try {
      // Se descarga paginado y con select completo para no depender de nombres de columnas con espacios/comillas.
      conteoEstadios =
          await _selectAllRowsPaged('SN-MATRIZ_ESTADIOS_CONTEO_FRUTA');
    } catch (_) {
      conteoEstadios = await _safeSelect(
        'SN-MATRIZ_ESTADIOS_CONTEO_FRUTA',
        '"ESTADIO O TIPO",FORMULA,ID',
      );
    }

    dynamicSourceRows['SN-MATRIZ_ESTADIOS_CONTEO_FRUTA'] =
        List<Map<String, dynamic>>.from(conteoEstadios);
    dynamicSourceRows['SN-MATRIZ_CONCEPTOS_ESTADIOS_PLAGAS'] =
        List<Map<String, dynamic>>.from(plagasConceptos);
    dynamicSourceRows['SN-MATRIZ_ETAPAS_FENOLOGICAS'] =
        List<Map<String, dynamic>>.from(etapasFenologicas);
    dynamicSourceRows['LOTES_VARIEDADES_GT'] =
        List<Map<String, dynamic>>.from(lotesVariedades);
    for (final matrixTable in const <String>[
      'RUBROS_APPGT',
      'MATRIZ_DROPDOWNS_APPGT',
      'MATRIZ_VALIDACIONES_APPGT',
      'MATRIZ_CONDICIONES_APPGT',
      'MATRIZ_FORMULAS_APPGT',
    ]) {
      try {
        dynamicSourceRows[matrixTable] = await _selectAllRowsPaged(matrixTable);
      } catch (_) {
        // Compatibilidad temporal con proyectos que aun no aplicaron la matriz.
      }
    }
    if (flowRulesForCache.isNotEmpty) {
      dynamicSourceRows['MATRIZ_ESTADOS_FLUJO_APPGT'] = flowRulesForCache;
    }

    // Registros Pendientes debe funcionar offline después de Actualizar datos.
    final dynamicViewsForDataTables = dynamicViews.isNotEmpty
        ? List<Map<String, dynamic>>.from(dynamicViews)
        : await _local.getAll('local_dynamic_views');
    dynamicSourceRows.addAll(
        await _downloadDynamicViewDataTables(dynamicViewsForDataTables));

    await _yieldToUi();
    final catalogValues = <Map<String, dynamic>>[
      ...await _downloadCatalogValues(),
      ..._dynamicCatalogValues(dynamicFields, dynamicSourceRows),
    ];

    await _local.replaceTable(
      'local_modules',
      List<Map<String, dynamic>>.from(modules)
          .map((e) => {
                'id': e['id'],
                'nombre': e['nombre'],
                'seccion': e['seccion']?.toString().trim() ?? '',
                'icono': e['icono']?.toString() ?? 'apps',
                'color': e['color']?.toString(),
                'rubro_id': e['rubro_id']?.toString(),
                'orden': e['orden'] ?? 0,
                'activo': _activeInt(e),
              })
          .toList(),
    );

    await _local.replaceTable(
      'local_formats',
      List<Map<String, dynamic>>.from(formats)
          .map((e) => {
                'id': e['id'],
                'modulo_id': e['modulo_id'],
                'nombre': e['nombre'],
                'rubro_id': e['rubro_id']?.toString(),
                'tabla_destino': e['tabla_destino'],
                'ruta_flutter': e['ruta_flutter'],
                'tabla_visible_app': _boolValue(e['tabla_visible_app']) ? 1 : 0,
                'capacidades': e['capacidades'] is Map
                    ? jsonEncode(e['capacidades'])
                    : (e['capacidades']?.toString() ?? '{}'),
                'flujo_estados': e['flujo_estados'] is List
                    ? jsonEncode(e['flujo_estados'])
                    : (e['flujo_estados']?.toString() ?? '[]'),
                'workflow_enabled': _boolValue(e['workflow_enabled']) ? 1 : 0,
                'geolocation_enabled':
                    _boolValue(e['geolocation_enabled']) ? 1 : 0,
                'approvals_enabled': _boolValue(e['approvals_enabled']) ? 1 : 0,
                'layout_formulario':
                    e['layout_formulario']?.toString() ?? 'VERTICAL',
                'layout_registros':
                    e['layout_registros']?.toString() ?? 'TABLA',
                'estado_revision_ia':
                    e['estado_revision_ia']?.toString() ?? 'APROBADA',
                'auditable': _boolValueOrDefault(e['auditable'], true) ? 1 : 0,
                'icono': e['icono']?.toString() ?? 'assignment',
                'imagen_encabezado': e['imagen_encabezado']?.toString(),
                'orden': e['orden'] ?? 0,
                'activo': 1,
              })
          .toList(),
    );

    await _local.replaceTable(
      'local_format_tables',
      List<Map<String, dynamic>>.from(formatTables)
          .map((e) => {
                'id': e['id'],
                'formato_id': e['formato_id'],
                'nombre': e['nombre'],
                'rubro_id': e['rubro_id']?.toString(),
                'tabla_destino': e['tabla_destino'],
                'orden': e['orden'] ?? 0,
                'tipo_relacion':
                    _valueByColumn(e, ['tipo_relacion', 'tipo relacion'])
                        ?.toString(),
                'tabla_padre': _valueByColumn(e, ['tabla_padre', 'tabla padre'])
                    ?.toString(),
                'campo_pk_padre': _valueByColumn(
                        e, ['campo_pk_padre', 'campo pk padre', 'pk_padre'])
                    ?.toString(),
                'campo_fk_hijo': _valueByColumn(
                        e, ['campo_fk_hijo', 'campo fk hijo', 'fk_hijo'])
                    ?.toString(),
                'es_cabecera': _boolValueOrDefault(
                        _valueByColumn(e, ['es_cabecera', 'es cabecera']),
                        false)
                    ? 1
                    : 0,
                'es_detalle': _boolValueOrDefault(
                        _valueByColumn(e, ['es_detalle', 'es detalle']), false)
                    ? 1
                    : 0,
                'campo_iterador':
                    _valueByColumn(e, ['campo_iterador', 'campo iterador'])
                        ?.toString(),
                'iterador_desde':
                    _valueByColumn(e, ['iterador_desde', 'iterador desde']),
                'iterador_hasta':
                    _valueByColumn(e, ['iterador_hasta', 'iterador hasta']),
                'copiar_campos_desde_padre': _valueByColumn(e, [
                  'copiar_campos_desde_padre',
                  'copiar campos desde padre'
                ])?.toString(),
                'modo_captura':
                    _valueByColumn(e, ['modo_captura', 'modo captura'])
                        ?.toString(),
                'auditable':
                    _boolValueOrDefault(_valueByColumn(e, ['auditable']), true)
                        ? 1
                        : 0,
                'icono':
                    _valueByColumn(e, ['icono'])?.toString() ?? 'assignment',
                'imagen_encabezado':
                    _valueByColumn(e, ['imagen_encabezado'])?.toString(),
                'activo': _activeInt(e),
              })
          .toList(),
    );

    await _local.replaceTable(
      'local_permissions',
      List<Map<String, dynamic>>.from(permissions)
          .map((e) => {
                'id': e['id'],
                'empresa_id': e['empresa_id']?.toString() ?? '',
                'user_id': e['user_id'],
                'modulo': e['modulo'],
                'formato': e['formato'],
                'can_view': _boolValue(e['can_view']) ? 1 : 0,
                'can_insert': _boolValue(e['can_insert']) ? 1 : 0,
                'can_update': _boolValue(e['can_update']) ? 1 : 0,
                'can_delete': _boolValue(e['can_delete']) ? 1 : 0,
                'can_export': _boolValue(e['can_export']) ? 1 : 0,
                'can_import': _boolValue(e['can_import']) ? 1 : 0,
                'can_review': _boolValue(e['can_review']) ? 1 : 0,
                'can_approve': _boolValue(e['can_approve']) ? 1 : 0,
                'can_view_pending': _boolValue(e['can_view_pending']) ? 1 : 0,
                'can_complete_pending':
                    _boolValue(e['can_complete_pending']) ? 1 : 0,
                'seccion': e['seccion']?.toString() ?? '',
                'campos_restringidos': e['campos_restringidos'] is List
                    ? jsonEncode(e['campos_restringidos'])
                    : (e['campos_restringidos']?.toString() ?? '[]'),
                'permisos_flujo': e['permisos_flujo'] is List
                    ? jsonEncode(e['permisos_flujo'])
                    : (e['permisos_flujo']?.toString() ?? '[]'),
              })
          .toList(),
    );

    await _local.replaceTable(
      'local_dynamic_views',
      List<Map<String, dynamic>>.from(dynamicViews)
          .map((e) => {
                'id': e['id']?.toString() ??
                    '${e['seccion']}_${e['modulo']}_${e['nombre_vista']}',
                'seccion': e['seccion']?.toString() ?? '',
                'modulo': e['modulo']?.toString() ?? '',
                'tipo_vista': e['tipo_vista']?.toString() ?? 'tabla',
                'tabla_destino': e['tabla_destino']?.toString() ?? '',
                'nombre_vista': e['nombre_vista']?.toString() ?? '',
                'estado_origen': e['estado_origen']?.toString() ?? '',
                'estado_destino': e['estado_destino']?.toString() ?? '',
                'filtro_estado': e['filtro_estado']?.toString() ?? '',
                'campos_pendientes': e['campos_pendientes']?.toString() ?? '',
                'campos_editables': e['campos_editables']?.toString() ?? '',
                'campos_visibles': e['campos_visibles']?.toString() ?? '',
                'requiere_todos_campos':
                    _boolValue(e['requiere_todos_campos']) ? 1 : 0,
                'activo': (e['activo'] == false ? false : true) ? 1 : 0,
                'orden': e['orden'] ?? 0,
                'payload_json': jsonEncode(e),
              })
          .where((e) =>
              (e['seccion'] as String).isNotEmpty &&
              (e['tabla_destino'] as String).isNotEmpty)
          .toList(),
    );

    await _local.replaceTable(
      'local_profile',
      List<Map<String, dynamic>>.from(profiles)
          .map((e) => {
                'id': e['id']?.toString() ?? user.id,
                'nombres': (e['nombres'] ?? e['Nombres'] ?? e['NOMBRES'])
                        ?.toString() ??
                    '',
                'cargo': e['cargo']?.toString() ?? '',
                'area': e['area']?.toString() ?? '',
                'dni': (e['dni'] ??
                            e['DNI'] ??
                            e['documento'] ??
                            e['DOCUMENTO'] ??
                            e['numero_documento'] ??
                            e['NUMERO_DOCUMENTO'])
                        ?.toString() ??
                    '',
                'email':
                    (e['email'] ?? e['correo'] ?? e['CORREO'])?.toString() ??
                        '',
                'activo': 1,
              })
          .toList(),
    );

    await _local.replaceTable(
      'local_sections',
      List<Map<String, dynamic>>.from(sections)
          .map((e) {
            final id = e['id']?.toString() ?? '';
            return {
              'id': id,
              'nombre': e['nombre']?.toString() ?? id,
              'icono': e['icono']?.toString() ?? 'apps',
              'color': e['color']?.toString(),
              'rubro_id': e['rubro_id']?.toString(),
              'tipo_contenido': e['tipo_contenido']?.toString() ?? 'GENERICO',
              'ruta_flutter': e['ruta_flutter']?.toString(),
              'orden': e['orden'] ?? 0,
              'numero_decimales': e['numero_decimales'],
              'grid_fila': e['grid_fila'],
              'grid_columna': e['grid_columna'] ?? e['grid columna'],
              'activo': 1,
            };
          })
          .where((e) => (e['id'] as String).isNotEmpty)
          .toList(),
    );

    await _local.replaceTable(
      'local_section_permissions',
      List<Map<String, dynamic>>.from(sectionPermissions)
          .map((e) {
            final sectionId = e['seccion']?.toString().trim().isNotEmpty == true
                ? e['seccion'].toString().trim()
                : (e['seccion_id']?.toString().trim() ?? '');
            final userId = e['user_id']?.toString() ?? '';
            return {
              'id': e['id']?.toString() ?? '${userId}_$sectionId',
              'user_id': userId,
              'seccion_id': sectionId,
              'can_view': (!_isDeletedRow(e) && _activeInt(e) == 1) ? 1 : 0,
              'can_insert': e['can_insert'] == true ? 1 : 0,
              'can_update': e['can_update'] == true ? 1 : 0,
              'can_delete': e['can_delete'] == true ? 1 : 0,
            };
          })
          .where((e) => (e['seccion_id'] as String).isNotEmpty)
          .toList(),
    );

    await _local.replaceTable(
      'local_special_formats',
      List<Map<String, dynamic>>.from(specialFormats)
          .map((e) => {
                'id': e['id'],
                'modulo_id': e['modulo_id'],
                'formato_id': e['formato_id'],
                'tipo_pantalla': e['tipo_pantalla'],
                'descripcion': e['descripcion'],
                'activo': 1,
                'orden': e['orden'] ?? 0,
              })
          .toList(),
    );

    progress('Guardando matriz de campos...');
    await _yieldToUi();
    final fieldRows = <Map<String, dynamic>>[];
    if (fields.isNotEmpty) {
      for (final e in List<Map<String, dynamic>>.from(fields)) {
        fieldRows.add({
          'id': e['id']?.toString() ?? '${e['tabla_destino']}_${e['campo']}',
          'tabla_destino': e['tabla_destino'],
          'campo': e['campo'],
          'etiqueta': e['etiqueta'] ?? e['campo'],
          'tipo': e['tipo_control'] ?? e['tipo'] ?? 'text',
          'tipo_ui': e['tipo_ui'] ?? e['tipo_control'] ?? e['tipo'] ?? 'text',
          'id_campo_dropdown': e['id_campo_dropdown']?.toString(),
          'formula_funcion': (e['formula_funcion'] ?? e['formula'])?.toString(),
          'formula_tipo': e['formula_tipo']?.toString(),
          'formula_tabla_origen': e['formula_tabla_origen']?.toString(),
          'formula_campo_valor': e['formula_campo_valor']?.toString(),
          'formula_campo_condicion': e['formula_campo_condicion']?.toString(),
          'formula_valor_condicion': e['formula_valor_condicion']?.toString(),
          'valor_default': e['valor_default']?.toString(),
          'id_generador': e['id_generador']?.toString(),
          'editable': e['editable'] == false ? 0 : 1,
          'visible': e['visible'] == false ? 0 : 1,
          'visible_tabla': (_boolValueOrDefault(
                  _valueByColumn(e, [
                    'visible_tabla',
                    'visible tabla',
                    'visible_en_tabla',
                    'visible en tabla'
                  ]),
                  e['visible'] == false ? false : true)
              ? 1
              : 0),
          'requerido':
              e['requerido'] == true ? 1 : (e['requerido'] == 1 ? 1 : 0),
          'orden': e['orden'] ?? 0,
          'numero_decimales': _valueByColumn(
              e, ['numero_decimales', 'numero decimales', 'decimales']),
          'grid_fila': _valueByColumn(
              e, ['grid_fila', 'grid fila', 'fila', 'fila_grid']),
          'grid_columna': _valueByColumn(
              e, ['grid_columna', 'grid columna', 'columna', 'columna_grid']),
          'rango_valor': _valueByColumn(e, [
            'rango_valor',
            'rango valor',
            'rango',
            'validacion_rango'
          ])?.toString(),
          'num_caracteres': _valueByColumn(e, [
            'num_caracteres',
            'num caracteres',
            'max_caracteres',
            'max caracteres'
          ]),
          'numero_fotos': _valueByColumn(e, [
            'numero_fotos',
            'numero fotos',
            'fotos',
            'max_fotos',
            'max fotos'
          ]),
          'photo_depende_de': _valueByColumn(e, [
            'photo_depende_de',
            'photo depende de',
            'depende_de_photo',
            'depende de photo',
            'depende_de'
          ])?.toString(),
          'lista_destino_photo': _valueByColumn(e, [
            'lista_destino_photo',
            'lista destino photo',
            'grupo_photo',
            'grupo photo',
            'lista_photo',
            'lista photo'
          ])?.toString(),
          'orden_lista_photo': _valueByColumn(e, [
            'orden_lista_photo',
            'orden lista photo',
            'orden_photo',
            'orden photo',
            'orden_lista'
          ]),
          'formato_condicional_campo': _valueByColumn(e, [
            'formato_condicional_campo',
            'formato condicional campo',
            'condicion_formato',
            'condición formato',
            'formato_condicional'
          ])?.toString(),
          'condicion_color_texto':
              _valueByColumn(e, ['condicion_color_texto'])?.toString(),
          'condicion_color_fondo':
              _valueByColumn(e, ['condicion_color_fondo'])?.toString(),
          'condicion_color_borde':
              _valueByColumn(e, ['condicion_color_borde'])?.toString(),
          'color_texto':
              _valueByColumn(e, ['color_texto', 'color texto', 'texto_color'])
                  ?.toString(),
          'color_fondo':
              _valueByColumn(e, ['color_fondo', 'color fondo', 'fondo_color'])
                  ?.toString(),
          'color_borde':
              _valueByColumn(e, ['color_borde', 'color borde', 'borde_color'])
                  ?.toString(),
          'tamanio_letra': _valueByColumn(e, ['tamanio_letra', 'tamano_letra']),
          'aplicar_formato_condicional_tabla': _boolValueOrDefault(
                  _valueByColumn(e, [
                    'aplicar_formato_condicional_tabla',
                    'aplicar formato condicional tabla',
                    'aplicar_condicional_tabla',
                    'formato_condicional_tabla'
                  ]),
                  false)
              ? 1
              : 0,
          'sub_titulo': _valueByColumn(
                  e, ['sub_titulo', 'sub titulo', 'subtítulo', 'subtitulo'])
              ?.toString(),
          'fila_sub_titulo': _valueByColumn(e, [
            'fila_sub_titulo',
            'fila sub titulo',
            'fila_subtitulo',
            'fila subtitulo'
          ]),
          'subtitulo_alineacion':
              _valueByColumn(e, ['subtitulo_alineacion'])?.toString(),
          'subtitulo_tamanio_letra':
              _valueByColumn(e, ['subtitulo_tamanio_letra']),
          'subtitulo_color': _valueByColumn(e, ['subtitulo_color'])?.toString(),
          'subtitulo_padding':
              _valueByColumn(e, ['subtitulo_padding'])?.toString(),
          'grupo_captura':
              _valueByColumn(e, ['grupo_captura', 'grupo captura'])?.toString(),
          'titulo1': _valueByColumn(
              e, ['titulo1', 'titulo_1', 'titulo v1', 'titulo_v1'])?.toString(),
          'titulo2': _valueByColumn(
              e, ['titulo2', 'titulo_2', 'titulo v2', 'titulo_v2'])?.toString(),
          'codigo1': _valueByColumn(
              e, ['codigo1', 'codigo_1', 'codigo v1', 'codigo_v1'])?.toString(),
          'codigo2': _valueByColumn(
              e, ['codigo2', 'codigo_2', 'codigo v2', 'codigo_v2'])?.toString(),
          'titulo1_alineacion':
              _valueByColumn(e, ['titulo1_alineacion'])?.toString(),
          'titulo1_tamanio_letra': _valueByColumn(e, ['titulo1_tamanio_letra']),
          'titulo1_color': _valueByColumn(e, ['titulo1_color'])?.toString(),
          'titulo1_padding': _valueByColumn(e, ['titulo1_padding'])?.toString(),
          'titulo2_alineacion':
              _valueByColumn(e, ['titulo2_alineacion'])?.toString(),
          'titulo2_tamanio_letra': _valueByColumn(e, ['titulo2_tamanio_letra']),
          'titulo2_color': _valueByColumn(e, ['titulo2_color'])?.toString(),
          'titulo2_padding': _valueByColumn(e, ['titulo2_padding'])?.toString(),
          'activo': 1,
        });
      }
    } else {
      final tables = List<Map<String, dynamic>>.from(formatTables);
      for (final table in tables) {
        final tableName = table['tabla_destino']?.toString();
        if (tableName == null || tableName.trim().isEmpty) continue;
        for (final field in FieldDefinitions.fallbackFor(tableName)) {
          fieldRows.add({
            'id': '${tableName}_${field['campo']}',
            'tabla_destino': tableName,
            'campo': field['campo'],
            'etiqueta': field['etiqueta'] ?? field['campo'],
            'tipo': field['tipo'] ?? 'text',
            'tipo_ui': field['tipo'] ?? 'text',
            'id_campo_dropdown': null,
            'formula_funcion': null,
            'valor_default': null,
            'id_generador': null,
            'editable': 1,
            'visible': 1,
            'visible_tabla': 1,
            'requerido': field['requerido'] ?? 0,
            'orden': field['orden'] ?? 0,
            'numero_decimales': _valueByColumn(
                field, ['numero_decimales', 'numero decimales', 'decimales']),
            'grid_fila': _valueByColumn(
                field, ['grid_fila', 'grid fila', 'fila', 'fila_grid']),
            'grid_columna': _valueByColumn(field,
                ['grid_columna', 'grid columna', 'columna', 'columna_grid']),
            'rango_valor': _valueByColumn(field,
                ['rango_valor', 'rango valor', 'rango', 'validacion_rango']),
            'num_caracteres': _valueByColumn(field, [
              'num_caracteres',
              'num caracteres',
              'max_caracteres',
              'max caracteres'
            ]),
            'numero_fotos': _valueByColumn(field, [
              'numero_fotos',
              'numero fotos',
              'fotos',
              'max_fotos',
              'max fotos'
            ]),
            'photo_depende_de': null,
            'lista_destino_photo': null,
            'orden_lista_photo': null,
            'formato_condicional_campo': null,
            'color_texto': null,
            'color_fondo': null,
            'color_borde': null,
            'aplicar_formato_condicional_tabla': 0,
            'sub_titulo': null,
            'fila_sub_titulo': null,
            'grupo_captura': null,
            'titulo1': null,
            'titulo2': null,
            'codigo1': null,
            'codigo2': null,
            'activo': 1,
          });
        }
      }
    }
    if (fieldRows.isNotEmpty) {
      await _local.replaceTable('local_form_fields', fieldRows);
    }

    final lotesRows = <String, Map<String, dynamic>>{};
    for (final e in List<Map<String, dynamic>>.from(lotesVariedades)) {
      final turno = e['TURNO']?.toString().trim() ?? '';
      if (turno.isEmpty) continue;
      lotesRows[turno] = {
        'turno': turno,
        'variedad': e['VARIEDAD']?.toString().trim() ?? '',
        'latitud': _valueByColumn(e, ['LATITUD', 'LATITUDE']),
        'longitud': _valueByColumn(e, ['LONGITUD', 'LONGITUDE']),
        'precision_gps':
            _valueByColumn(e, ['PRECISION_GPS', 'PRECISION GPS', 'ACCURACY']),
        'fecha_gps':
            _valueByColumn(e, ['FECHA_GPS', 'FECHA GPS', 'GPS_AT'])?.toString(),
      };
    }
    await _local.replaceTable(
        'local_lotes_variedades', lotesRows.values.toList());
    await _local.replaceTable('local_catalog_values', catalogValues);
    await _yieldToUi();
    await _local.applyMatrixRowsFromPayloads(dynamicSourceRows,
        replaceSources: true);
    await _yieldToUi();

    final conceptoRows = <String, Map<String, dynamic>>{};
    for (final e in List<Map<String, dynamic>>.from(plagasConceptos)) {
      final concepto = _valueByColumn(e, ['CONCEPTO'])?.toString().trim() ?? '';
      final estadio = _valueByColumn(e, [
            'ESTADIO O TIPO',
            'ESTADIOS O TIPOS',
            'ESTADIOS O TIPO',
            'ESTADIO_O_TIPO',
            'ESTADIOS_O_TIPOS',
            'ESTADIO',
            'TIPO'
          ])?.toString().trim() ??
          '';
      if (concepto.isEmpty || estadio.isEmpty) continue;
      final id = '$concepto$estadio';
      conceptoRows[id] = {
        'id': id,
        'concepto': concepto,
        'estadio': estadio,
        'formula': _valueByColumn(e, ['FORMULA'])?.toString().trim() ?? '',
      };
    }
    await _local.replaceTable(
        'local_plagas_conceptos', conceptoRows.values.toList());

    final fenologiaRows = <String, Map<String, dynamic>>{};
    for (final e in List<Map<String, dynamic>>.from(etapasFenologicas)) {
      final etapa = _valueByColumn(e, [
            'ETAPA_FENOLOGICA',
            'ETAPA FENOLOGICA',
            'ETAPA FENOLÓGICA',
            'FENOLOGIA',
            'FENOLOGÍA',
            'FENOLOGICA',
            'FENOLÓGICA',
            'ETAPA'
          ])?.toString().trim() ??
          '';
      if (etapa.isEmpty) continue;
      fenologiaRows[etapa] = {'etapa_fenologica': etapa};
    }
    await _local.replaceTable(
      'local_fenologias',
      fenologiaRows.isNotEmpty
          ? fenologiaRows.values.toList()
          : _fallbackFenologiaRows(),
    );

    final conteoRows = <String, Map<String, dynamic>>{};
    for (final e in List<Map<String, dynamic>>.from(conteoEstadios)) {
      final estadio = _valueByColumn(e, [
            'ESTADIO O TIPO',
            'ESTADIOS O TIPOS',
            'ESTADIOS O TIPO',
            'ESTADIO_O_TIPO',
            'ESTADIOS_O_TIPOS',
            'ESTADIO',
            'TIPO'
          ])?.toString().trim() ??
          '';
      if (estadio.isEmpty) continue;
      conteoRows[estadio] = {
        'estadio': estadio,
        'formula': _valueByColumn(e, ['FORMULA'])?.toString().trim() ?? '',
      };
    }
    await _local.replaceTable(
        'local_conteo_estadios', conteoRows.values.toList());
  }

  String _sanitizePathPart(String value) {
    return value
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
  }

  bool _isBase64Image(dynamic value) {
    return value is String &&
        (value.startsWith('data:image/png;base64,') ||
            value.startsWith('data:image/jpeg;base64,') ||
            value.startsWith('data:image/jpg;base64,'));
  }

  String _contentType(String value) {
    if (value.startsWith('data:image/jpeg') ||
        value.startsWith('data:image/jpg')) {
      return 'image/jpeg';
    }
    return 'image/png';
  }

  String _extension(String value) {
    if (value.startsWith('data:image/jpeg') ||
        value.startsWith('data:image/jpg')) {
      return 'jpg';
    }
    return 'png';
  }

  Uint8List _decodeBase64Image(String value) {
    final commaIndex = value.indexOf(',');
    final raw = commaIndex >= 0 ? value.substring(commaIndex + 1) : value;
    return base64Decode(raw);
  }

  Future<Map<String, dynamic>> _uploadEvidenceFiles({
    required Map<String, dynamic> payload,
    required Map<String, dynamic> queueRow,
  }) async {
    final cleaned = Map<String, dynamic>.from(payload);
    final rawTable = queueRow['tabla_destino']?.toString() ?? 'tabla';
    final table = _sanitizePathPart(rawTable);
    final modulo =
        _sanitizePathPart(queueRow['modulo_id']?.toString() ?? 'modulo');
    final formato =
        _sanitizePathPart(queueRow['formato_id']?.toString() ?? 'formato');
    final subtabla = _sanitizePathPart(
        queueRow['formato_tabla_id']?.toString() ?? 'subtabla');
    final idLocal = _sanitizePathPart(payload['ID_REGISTRO']?.toString() ??
        queueRow['id_local']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString());

    final uploads = <Future<void>>[];
    for (final entry in payload.entries) {
      if (!_isBase64Image(entry.value)) continue;
      final field = _sanitizePathPart(entry.key);
      final rawValue = entry.value as String;
      final bytes = _decodeBase64Image(rawValue);
      final ext = _extension(rawValue);
      final folder = field.toUpperCase().contains('FOTO') ? 'fotos' : 'firmas';
      final path =
          '$folder/$modulo/$formato/$subtabla/$table/$idLocal/$field.$ext';

      uploads.add(() async {
        await _supabase.storage.from(EvidenceStorage.bucket).uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                contentType: _contentType(rawValue),
                upsert: true,
              ),
            );
        // Bucket privado: en BD se guarda la ruta, no una URL firmada larga.
        // La URL corta se genera solo al visualizar la evidencia.
        cleaned[entry.key] = EvidenceStorage.toStorageUri(path);
        try {
          final empresaId = queueRow['empresa_id']?.toString().trim() ?? '';
          final userId = _supabase.auth.currentUser?.id ?? '';
          final storedId = queueRow['id_local']?.toString().trim() ?? '';
          if (empresaId.isNotEmpty &&
              userId.isNotEmpty &&
              storedId.isNotEmpty) {
            await _supabase.from('ARCHIVOS_EVIDENCIA_APPGT').upsert(
              {
                'empresa_id': empresaId,
                'user_id': userId,
                'tabla_destino': rawTable,
                'registro_id_local': storedId,
                'campo': entry.key,
                'bucket': EvidenceStorage.bucket,
                'object_path': path,
                'mime_type': _contentType(rawValue),
                'tamano_bytes': bytes.length,
                'estado': 'PENDIENTE_VINCULAR',
              },
              onConflict: 'empresa_id,bucket,object_path',
            );
          }
        } catch (_) {
          // El manifiesto mejora la trazabilidad, pero una falla al registrarlo
          // no debe invalidar un archivo que Storage ya recibió correctamente.
        }
      }());
    }
    if (uploads.isNotEmpty) await Future.wait(uploads);
    return cleaned;
  }

  Future<void> _markEvidenceLinked(
    List<String> storedIds,
    String empresaId,
  ) async {
    if (storedIds.isEmpty) return;
    try {
      await _supabase
          .from('ARCHIVOS_EVIDENCIA_APPGT')
          .update({
            'estado': 'VINCULADO',
            'linked_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('empresa_id', empresaId)
          .inFilter('registro_id_local', storedIds);
    } catch (_) {
      // La evidencia permanece PENDIENTE_VINCULAR y puede auditarse/repararse.
    }
  }

  Future<Map<String, dynamic>?> _remoteConflictFor({
    required String table,
    required Map<String, dynamic> payload,
    required Map<String, dynamic> queueRow,
  }) async {
    final idLocal = payload['id_local']?.toString().trim() ?? '';
    final baseUpdatedAt = queueRow['base_updated_at']?.toString().trim() ?? '';
    if (idLocal.isEmpty || baseUpdatedAt.isEmpty) return null;

    try {
      final rows =
          await _supabase.from(table).select().eq('id_local', idLocal).limit(1);
      if (rows.isEmpty) return null;
      final remote = Map<String, dynamic>.from(rows.first);
      final remoteUpdatedAt =
          _valueByColumn(remote, ['updated_at', 'UPDATED_AT'])
                  ?.toString()
                  .trim() ??
              '';
      if (!OfflineConflictPolicy.hasRemoteChange(
        baseUpdatedAt: baseUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt,
      )) {
        return null;
      }
      return {
        'tabla_destino': table,
        'registro_id_local': queueRow['id_local'],
        'base_updated_at': baseUpdatedAt,
        'remote_updated_at': remoteUpdatedAt,
        'payload_local': payload,
        'payload_remoto': remote,
      };
    } catch (_) {
      // Tablas antiguas sin updated_at siguen usando la estrategia last-write.
      return null;
    }
  }

  Future<void> _recordRemoteConflict({
    required Map<String, dynamic> conflict,
    required String empresaId,
    required String userId,
    required String syncRunId,
  }) async {
    try {
      await _supabase.from('CONFLICTOS_SYNC_APPGT').insert({
        'empresa_id': empresaId,
        'user_id': userId,
        'sincronizacion_id': syncRunId,
        'tabla_destino': conflict['tabla_destino'],
        'registro_id_local': conflict['registro_id_local'],
        'payload_local': conflict['payload_local'],
        'payload_remoto': conflict['payload_remoto'],
        'base_updated_at': conflict['base_updated_at'],
        'remote_updated_at': conflict['remote_updated_at'],
      });
    } catch (_) {
      // El conflicto queda también en SQLite aunque falle su telemetría remota.
    }
  }

  Future<void> _startRemoteSyncRun({
    required String syncRunId,
    required String empresaId,
    required String userId,
    required int pendingCount,
  }) async {
    try {
      await _supabase.from('SINCRONIZACIONES_APPGT').insert({
        'id': syncRunId,
        'empresa_id': empresaId,
        'user_id': userId,
        'estado': 'EJECUTANDO',
        'pendientes_iniciales': pendingCount,
      });
    } catch (_) {}
  }

  Future<void> _finishRemoteSyncRun({
    required String syncRunId,
    required int synced,
    required int conflicts,
    required int errors,
  }) async {
    final state = errors > 0
        ? (synced > 0 || conflicts > 0 ? 'PARCIAL' : 'ERROR')
        : (conflicts > 0 ? 'PARCIAL' : 'COMPLETADA');
    try {
      await _supabase.from('SINCRONIZACIONES_APPGT').update({
        'estado': state,
        'sincronizados': synced,
        'conflictos': conflicts,
        'errores': errors,
        'finished_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', syncRunId);
    } catch (_) {}
  }

  Map<String, dynamic> _cleanPayloadForInsert(Map<String, dynamic> payload) {
    final cleaned = Map<String, dynamic>.from(payload);

    // IMPORTANTE:
    // Estas marcas son solo de control local/offline y nunca deben viajar a Supabase.
    // Si llegan al upsert, PostgREST falla porque esas columnas no existen en la tabla real.
    const localOnlyKeys = {
      '_pending_local_',
      '__pending_local__',
      '_pending_sync_',
      '__pending_sync__',
      '_local_dirty_',
      '__local_dirty__',
      '__complete__',
    };

    final keysToRemove = cleaned.keys.where((key) {
      final keyText = key.toString();
      final normalized = _norm(keyText);

      if (localOnlyKeys.contains(keyText) ||
          localOnlyKeys.contains(normalized.toLowerCase())) {
        return true;
      }

      // Cualquier clave interna con doble guion bajo es metadata de Flutter, no columna real.
      if (keyText.startsWith('__')) return true;

      if (normalized == 'ID_FILA_SERIAL') {
        final value = cleaned[key];
        return value == null || value.toString().trim().isEmpty;
      }

      return false;
    }).toList();

    for (final key in keysToRemove) {
      cleaned.remove(key);
    }
    return cleaned;
  }

  String _generateHiddenIdValue(String prefix) {
    final safePrefix = prefix.trim().toUpperCase().isEmpty
        ? 'REGI'
        : prefix.trim().toUpperCase();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final seed =
        DateTime.now().microsecondsSinceEpoch.toRadixString(36).toUpperCase();
    final uuidPart = _uuid.v4().replaceAll('-', '').toUpperCase();
    final raw = '$seed$uuidPart';
    final suffix = raw
        .split('')
        .where((c) => chars.contains(c))
        .join()
        .padRight(16, '0')
        .substring(0, 16);
    return '$safePrefix$suffix';
  }

  Future<Map<String, dynamic>> _filterPayloadToKnownFields(
      String table, Map<String, dynamic> payload) async {
    final fieldRows = await _local.where(
        'local_form_fields', 'tabla_destino = ? and activo = 1', [table]);
    final allowed = <String>{
      'ID_LOCAL',
      'CREATED_AT',
      'UPDATED_AT',
      'DELETED_AT',
      'ESTADO_SYNC',
      'ACTIVO',
      'ELIMINADO',
      'ESTADO_REGISTRO',
      'ID_REGISTRO',
      'HASH_FILA_SIN_IDS',
      'ID_FILA_SERIAL',
      'HIDDEN_ID',
    };
    for (final f in fieldRows) {
      final campo = f['campo']?.toString().trim() ?? '';
      if (campo.isNotEmpty) allowed.add(_norm(campo));
    }
    if (fieldRows.isEmpty) return payload;
    final canonicalByNorm = <String, String>{};
    for (final f in fieldRows) {
      final campo = f['campo']?.toString().trim() ?? '';
      if (campo.isNotEmpty) canonicalByNorm[_norm(campo)] = campo;
    }
    if (table == 'GT-TAREO_PERSONAL') {
      canonicalByNorm.addAll({
        'ID_LOCAL': 'id_local',
        'FECHA': 'FECHA',
        'LOTE': 'LOTE',
        'TURNO': 'TURNO',
        'VARIEDAD': 'VARIEDAD',
        'AREA': 'AREA',
        'LABOR': 'LABOR',
        'CENTRO_COSTO': 'CENTRO_COSTO',
        'CENTRO_DE_COSTO': 'CENTRO_DE_COSTO',
        'HORA_INICIO': 'HORA_INICIO',
        'HORA_FIN': 'HORA_FIN',
        'HORAS_TRABAJADAS': 'HORAS_TRABAJADAS',
        'TAREADOR': 'TAREADOR',
        'DNI': 'DNI',
        'APELLIDOS_NOMBRES': 'APELLIDOS Y NOMBRES',
        'OBSERVACIONES': 'OBSERVACIONES',
        'ESTADO_REGISTRO': 'estado_registro',
      });
      allowed.addAll(canonicalByNorm.keys);
    }
    final out = <String, dynamic>{};
    for (final entry in payload.entries) {
      final key = entry.key.toString();
      final norm = _norm(key);
      if (table == 'GT-ASISTENCIA_PERSONAL' && norm == 'TIPO_MOVIMIENTO')
        continue;
      if (allowed.contains(norm))
        out[canonicalByNorm[norm] ?? key] = entry.value;
    }
    return out;
  }

  Future<Map<String, dynamic>> _ensureHiddenIdsForSync({
    required String table,
    required Map<String, dynamic> payload,
  }) async {
    final output = Map<String, dynamic>.from(payload);
    final fieldRows = await _local.where(
      'local_form_fields',
      'tabla_destino = ? and activo = 1',
      [table],
      orderBy: 'orden',
    );

    const technical = {'ID_LOCAL', 'ID', 'PK_ID', 'ID_PK'};

    for (final f in fieldRows) {
      final campo = f['campo']?.toString().trim() ?? '';
      final tipo = f['tipo']?.toString().trim().toLowerCase() ?? '';
      final tipoUi = f['tipo_ui']?.toString().trim().toLowerCase() ?? '';
      if (campo.isEmpty) continue;
      if (technical.contains(_norm(campo))) continue;
      if (tipo != 'hidden_id' && tipoUi != 'hidden_id') continue;

      final existing = output[campo]?.toString().trim() ?? '';
      if (existing.isNotEmpty) continue;

      final prefix = f['id_generador']?.toString().trim() ?? '';
      output[campo] = _generateHiddenIdValue(prefix);
    }

    return output;
  }

  Future<int> syncPending() async {
    final online = await hasInternet();
    if (!online)
      throw Exception(
          'No hay conexión a internet. Tus registros siguen guardados como pendientes.');

    await _ensureOnlineAuthSession();

    final activeUserId = _supabase.auth.currentUser?.id;
    if (activeUserId == null || activeUserId.isEmpty) {
      throw Exception('No hay un usuario autenticado para sincronizar.');
    }
    final activeEmpresaId = await LocalSession().cachedEmpresaId();
    final pending = await _local.pendingRecords(
      userId: activeUserId,
      empresaId: activeEmpresaId,
    );
    var tareosSinHoraFin = 0;
    for (var pendingIndex = 0; pendingIndex < pending.length; pendingIndex++) {
      final row = pending[pendingIndex];
      if (pendingIndex > 0 && pendingIndex % 40 == 0) await _yieldToUi();
      final table = row['tabla_destino']?.toString() ?? '';
      if (table != 'GT-TAREO_PERSONAL') continue;
      try {
        final payload =
            jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
        final horaFin = (payload['HORA_FIN'] ?? payload['HORA FIN'] ?? '')
            .toString()
            .trim();
        if (horaFin.isEmpty || horaFin.toLowerCase() == 'null') {
          tareosSinHoraFin++;
          await _local.markError(row['id_local'] as String,
              'Todos los tareos deben tener hora fin');
        }
      } catch (_) {}
    }
    if (tareosSinHoraFin > 0) {
      throw Exception('Todos los tareos deben tener hora fin');
    }
    int synced = 0;
    int conflicts = 0;
    int errors = 0;
    final syncRunId = _uuid.v4();
    await _startRemoteSyncRun(
      syncRunId: syncRunId,
      empresaId: activeEmpresaId,
      userId: activeUserId,
      pendingCount: pending.length,
    );

    final byTable = <String, List<Map<String, dynamic>>>{};

    for (var pendingIndex = 0; pendingIndex < pending.length; pendingIndex++) {
      final row = pending[pendingIndex];
      if (pendingIndex > 0 && pendingIndex % 20 == 0) await _yieldToUi();
      final storedIdLocal = row['id_local'] as String;
      await _local.markSyncing(storedIdLocal);
      try {
        final idLocal = _isPureUuid(storedIdLocal) ? storedIdLocal : _uuid.v4();
        final table = row['tabla_destino'] as String;
        final payload =
            jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
        payload['id_local'] = idLocal;
        payload.putIfAbsent('empresa_id', () => activeEmpresaId);
        final withHiddenIds =
            await _ensureHiddenIdsForSync(table: table, payload: payload);
        final cleanedPayload = _cleanPayloadForInsert(withHiddenIds);
        final knownPayload =
            await _filterPayloadToKnownFields(table, cleanedPayload);
        final conflict = await _remoteConflictFor(
          table: table,
          payload: knownPayload,
          queueRow: row,
        );
        if (conflict != null) {
          await _local.markConflict(
            storedIdLocal,
            conflict,
            remoteVersion: conflict['remote_updated_at']?.toString(),
          );
          await _recordRemoteConflict(
            conflict: conflict,
            empresaId: activeEmpresaId,
            userId: activeUserId,
            syncRunId: syncRunId,
          );
          conflicts++;
          continue;
        }
        final finalPayload =
            await _uploadEvidenceFiles(payload: knownPayload, queueRow: row);
        finalPayload['__stored_id_local__'] = storedIdLocal;
        byTable
            .putIfAbsent(table, () => <Map<String, dynamic>>[])
            .add(finalPayload);
      } catch (e) {
        await _local.markError(storedIdLocal, friendlyError(e));
        errors++;
      }
    }

    for (final entry in byTable.entries) {
      final table = entry.key;
      final rows = entry.value;
      const chunkSize = 100;
      for (var i = 0; i < rows.length; i += chunkSize) {
        await _yieldToUi();
        final chunk = rows.skip(i).take(chunkSize).toList();
        final payloadChunk = chunk.map((r) {
          final clean = Map<String, dynamic>.from(r);
          clean.remove('__stored_id_local__');
          return clean;
        }).toList();

        try {
          await _supabase
              .from(table)
              .upsert(payloadChunk, onConflict: 'id_local');
          final syncedIds = <String>[];
          final cachePayloads = <Map<String, dynamic>>[];
          for (final row in chunk) {
            final storedIdLocal = row['__stored_id_local__']?.toString() ?? '';
            if (storedIdLocal.isEmpty) continue;
            final cachePayload = Map<String, dynamic>.from(row)
              ..remove('__stored_id_local__');
            syncedIds.add(storedIdLocal);
            cachePayloads.add(cachePayload);
          }
          await _local.markSyncedBatch(syncedIds);
          await _local.upsertMatrixRowPayloads(table, cachePayloads);
          await _markEvidenceLinked(syncedIds, activeEmpresaId);
          synced += syncedIds.length;
        } catch (_) {
          // Respaldo fino: si un lote falla por una fila defectuosa, no bloquea a las demás.
          for (final row in chunk) {
            final storedIdLocal = row['__stored_id_local__']?.toString() ?? '';
            final clean = Map<String, dynamic>.from(row)
              ..remove('__stored_id_local__');
            try {
              await _supabase.from(table).upsert(clean, onConflict: 'id_local');
              await _local.markSynced(storedIdLocal);
              await _local.upsertMatrixRowPayload(table, clean);
              await _markEvidenceLinked([storedIdLocal], activeEmpresaId);
              synced++;
            } catch (e) {
              await _local.markError(storedIdLocal, friendlyError(e));
              errors++;
            }
          }
        }
      }
    }

    await _finishRemoteSyncRun(
      syncRunId: syncRunId,
      synced: synced,
      conflicts: conflicts,
      errors: errors,
    );
    return synced;
  }
}
