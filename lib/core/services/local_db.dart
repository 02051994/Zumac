import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../config/tenant_config.dart';
import 'offline_record_state.dart';

/// Persistencia local multiempresa para configuración, catálogos, registros
/// operativos y la cola de sincronización.
///
/// La clase centraliza las transacciones SQLite/IndexedDB para que un snapshot
/// incompleto nunca sustituya datos válidos y para que los deltas puedan
/// aplicarse sin borrar filas ajenas al cambio recibido.
class LocalDb {
  static final LocalDb instance = LocalDb._();
  LocalDb._({Database? database}) : _db = database;

  factory LocalDb.forTesting(Database database) =>
      LocalDb._(database: database);

  Database? _db;

  Future<String> _databasePath() async {
    // En Web no existe un directorio del sistema de archivos. La fábrica
    // sqflite_common_ffi_web usa este nombre para persistir la base en
    // IndexedDB mediante SQLite/Wasm.
    if (kIsWeb) return 'appgt_offline_subtables.db';

    // En Windows, sqflite_common_ffi puede devolver una ruta relativa dentro
    // de .dart_tool si se usa getDatabasesPath(). Eso generaba dos bases
    // distintas: una para flutter run y otra para el EXE release.
    // ApplicationSupport es una ruta persistente por usuario y estable para ambas ejecuciones.
    final supportDir = await getApplicationSupportDirectory();
    return join(supportDir.path, 'appgt_offline_subtables.db');
  }

  Future<Database> get db async {
    if (_db != null) return _db!;
    final path = await _databasePath();
    _db = await openDatabase(
      path,
      version: 32,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (database) async {
        await _ensureRuntimeSchema(database);
      },
    );
    return _db!;
  }

  Future<void> _createLocalFormFields(Database db) async {
    await db.execute('''
      create table if not exists local_form_fields(
        id text primary key,
        tabla_destino text,
        campo text,
        etiqueta text,
        tipo text,
        tipo_ui text,
        id_campo_dropdown text,
        formula_funcion text,
        formula_tipo text,
        formula_tabla_origen text,
        formula_campo_valor text,
        formula_campo_condicion text,
        formula_valor_condicion text,
        valor_default text,
        id_generador text,
        editable integer,
        visible integer,
        visible_tabla integer,
        requerido integer,
        orden integer,
        numero_decimales integer,
        grid_fila integer,
        grid_columna integer,
        grid_fila_pendientes integer,
        grid_columna_pendientes integer,
        rango_valor text,
        num_caracteres integer,
        numero_fotos integer,
        photo_depende_de text,
        lista_destino_photo text,
        orden_lista_photo integer,
        formato_condicional_campo text,
        condicion_color_texto text,
        condicion_color_fondo text,
        condicion_color_borde text,
        color_texto text,
        color_fondo text,
        color_borde text,
        tamanio_letra real,
        aplicar_formato_condicional_tabla integer,
        sub_titulo text,
        fila_sub_titulo integer,
        subtitulo_alineacion text,
        subtitulo_tamanio_letra real,
        subtitulo_color text,
        subtitulo_padding text,
        grupo_captura text,
        titulo1 text,
        titulo2 text,
        codigo1 text,
        codigo2 text,
        titulo1_alineacion text,
        titulo1_tamanio_letra real,
        titulo1_color text,
        titulo1_padding text,
        titulo2_alineacion text,
        titulo2_tamanio_letra real,
        titulo2_color text,
        titulo2_padding text,
        activo integer
      )
    ''');
  }

  Future<void> _ensureColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((c) => c['name']?.toString() == column);
    if (!exists) {
      await db.execute('alter table $table add column $column $definition');
    }
  }

  Future<void> _upgradePendingRecords(Database db) async {
    if (await _tableExists(db, 'pending_records')) {
      await _ensureColumn(db, 'pending_records', 'created_by', 'text');
      await _ensureColumn(db, 'pending_records', 'updated_at_local', 'text');
      await _ensureColumn(db, 'pending_records', 'base_updated_at', 'text');
      await _ensureColumn(
          db, 'pending_records', 'version_local', 'integer default 1');
      await _ensureColumn(db, 'pending_records', 'version_remota', 'text');
      await _ensureColumn(db, 'pending_records', 'conflict_json', 'text');
      await _ensureColumn(db, 'pending_records', 'last_attempt_at', 'text');
      await _ensureColumn(db, 'pending_records', 'evidence_json', 'text');
      await _safeCreateIndex(
        db,
        'pending_records',
        'create index if not exists idx_pending_retry on pending_records(estado, last_attempt_at)',
      );
      // Si la aplicación se cerró durante un envío, la operación no quedó
      // confirmada. Recuperarla como error reintentable evita colas bloqueadas.
      await db.rawUpdate('''
        update pending_records
        set estado = ?,
            error_mensaje = coalesce(error_mensaje, 'Sincronización interrumpida')
        where estado = ?
      ''', [
        OfflineRecordState.error.storageValue,
        OfflineRecordState.syncing.storageValue,
      ]);
    }
  }

  Future<void> _upgradeTenantColumns(Database db) async {
    const tables = <String>[
      'local_modules',
      'local_formats',
      'local_format_tables',
      'local_permissions',
      'local_profile',
      'local_form_fields',
      'local_special_formats',
      'local_sections',
      'local_section_permissions',
      'local_dynamic_views',
      'local_catalog_values',
      'local_matrix_rows',
      'pending_records',
    ];
    for (final table in tables) {
      if (await _tableExists(db, table)) {
        await _ensureColumn(
          db,
          table,
          'empresa_id',
          "text not null default '${TenantConfig.defaultEmpresaId}'",
        );
      }
    }
    await _safeCreateIndex(
      db,
      'pending_records',
      'create index if not exists idx_pending_user_empresa_estado on pending_records(user_id, empresa_id, estado)',
    );
  }

  Future<void> _upgradeNavigationMetadata(Database db) async {
    if (!await _tableExists(db, 'local_sections')) return;
    await _ensureColumn(db, 'local_sections', 'rubro_id', 'text');
    await _ensureColumn(db, 'local_sections', 'color', 'text');
    await _ensureColumn(
      db,
      'local_sections',
      'tipo_contenido',
      "text not null default 'GENERICO'",
    );
    await _ensureColumn(db, 'local_sections', 'ruta_flutter', 'text');
    await _ensureColumn(db, 'local_modules', 'rubro_id', 'text');
    await _ensureColumn(db, 'local_modules', 'icono', 'text');
    await _ensureColumn(db, 'local_modules', 'color', 'text');
    await _ensureColumn(db, 'local_formats', 'rubro_id', 'text');
    await _ensureColumn(db, 'local_format_tables', 'rubro_id', 'text');
  }

  Future<bool> _tableExists(Database db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    return rows.isNotEmpty;
  }

  Future<void> _safeCreateIndex(Database db, String table, String sql) async {
    if (await _tableExists(db, table)) {
      await db.execute(sql);
    }
  }

  Future<void> _upgradeLocalFormFields(Database db) async {
    await _ensureColumn(db, 'local_form_fields', 'tipo_ui', 'text');
    await _ensureColumn(db, 'local_form_fields', 'id_campo_dropdown', 'text');
    await _ensureColumn(db, 'local_form_fields', 'formula_funcion', 'text');
    await _ensureColumn(db, 'local_form_fields', 'formula_tipo', 'text');
    await _ensureColumn(
        db, 'local_form_fields', 'formula_tabla_origen', 'text');
    await _ensureColumn(db, 'local_form_fields', 'formula_campo_valor', 'text');
    await _ensureColumn(
        db, 'local_form_fields', 'formula_campo_condicion', 'text');
    await _ensureColumn(
        db, 'local_form_fields', 'formula_valor_condicion', 'text');
    await _ensureColumn(db, 'local_form_fields', 'valor_default', 'text');
    await _ensureColumn(db, 'local_form_fields', 'id_generador', 'text');
    await _ensureColumn(db, 'local_form_fields', 'editable', 'integer');
    await _ensureColumn(db, 'local_form_fields', 'visible', 'integer');
    await _ensureColumn(db, 'local_form_fields', 'visible_tabla', 'integer');
    await _ensureColumn(db, 'local_form_fields', 'requerido', 'integer');
    await _ensureColumn(db, 'local_form_fields', 'orden', 'integer');
    await _ensureColumn(db, 'local_form_fields', 'numero_decimales', 'integer');
    await _ensureColumn(db, 'local_form_fields', 'grid_fila', 'integer');
    await _ensureColumn(db, 'local_form_fields', 'grid_columna', 'integer');
    await _ensureColumn(
        db, 'local_form_fields', 'grid_fila_pendientes', 'integer');
    await _ensureColumn(
        db, 'local_form_fields', 'grid_columna_pendientes', 'integer');
    await _ensureColumn(db, 'local_form_fields', 'rango_valor', 'text');
    await _ensureColumn(db, 'local_form_fields', 'num_caracteres', 'integer');
    await _ensureColumn(db, 'local_form_fields', 'numero_fotos', 'integer');
    await _ensureColumn(db, 'local_form_fields', 'photo_depende_de', 'text');
    await _ensureColumn(db, 'local_form_fields', 'lista_destino_photo', 'text');
    await _ensureColumn(
        db, 'local_form_fields', 'orden_lista_photo', 'integer');
    await _ensureColumn(
        db, 'local_form_fields', 'formato_condicional_campo', 'text');
    await _ensureColumn(
        db, 'local_form_fields', 'condicion_color_texto', 'text');
    await _ensureColumn(
        db, 'local_form_fields', 'condicion_color_fondo', 'text');
    await _ensureColumn(
        db, 'local_form_fields', 'condicion_color_borde', 'text');
    await _ensureColumn(db, 'local_form_fields', 'color_texto', 'text');
    await _ensureColumn(db, 'local_form_fields', 'color_fondo', 'text');
    await _ensureColumn(db, 'local_form_fields', 'color_borde', 'text');
    await _ensureColumn(db, 'local_form_fields', 'tamanio_letra', 'real');
    await _ensureColumn(db, 'local_form_fields',
        'aplicar_formato_condicional_tabla', 'integer');
    await _ensureColumn(db, 'local_form_fields', 'sub_titulo', 'text');
    await _ensureColumn(db, 'local_form_fields', 'fila_sub_titulo', 'integer');
    await _ensureColumn(
        db, 'local_form_fields', 'subtitulo_alineacion', 'text');
    await _ensureColumn(
        db, 'local_form_fields', 'subtitulo_tamanio_letra', 'real');
    await _ensureColumn(db, 'local_form_fields', 'subtitulo_color', 'text');
    await _ensureColumn(db, 'local_form_fields', 'subtitulo_padding', 'text');
    await _ensureColumn(db, 'local_form_fields', 'grupo_captura', 'text');
    await _ensureColumn(db, 'local_form_fields', 'titulo1', 'text');
    await _ensureColumn(db, 'local_form_fields', 'titulo2', 'text');
    await _ensureColumn(db, 'local_form_fields', 'codigo1', 'text');
    await _ensureColumn(db, 'local_form_fields', 'codigo2', 'text');
    await _ensureColumn(db, 'local_form_fields', 'titulo1_alineacion', 'text');
    await _ensureColumn(
        db, 'local_form_fields', 'titulo1_tamanio_letra', 'real');
    await _ensureColumn(db, 'local_form_fields', 'titulo1_color', 'text');
    await _ensureColumn(db, 'local_form_fields', 'titulo1_padding', 'text');
    await _ensureColumn(db, 'local_form_fields', 'titulo2_alineacion', 'text');
    await _ensureColumn(
        db, 'local_form_fields', 'titulo2_tamanio_letra', 'real');
    await _ensureColumn(db, 'local_form_fields', 'titulo2_color', 'text');
    await _ensureColumn(db, 'local_form_fields', 'titulo2_padding', 'text');
    await _ensureColumn(db, 'local_form_fields', 'activo', 'integer');
  }

  Future<void> _createLocalSpecialFormats(Database db) async {
    await db.execute('''
      create table if not exists local_special_formats(
        id text primary key,
        modulo_id text,
        formato_id text,
        tipo_pantalla text,
        descripcion text,
        activo integer,
        orden integer
      )
    ''');
  }

  Future<void> _createLocalLotesVariedades(Database db) async {
    await db.execute('''
      create table if not exists local_lotes_variedades(
        turno text primary key,
        variedad text,
        latitud real,
        longitud real,
        precision_gps real,
        fecha_gps text
      )
    ''');
    await _ensureColumn(db, 'local_lotes_variedades', 'latitud', 'real');
    await _ensureColumn(db, 'local_lotes_variedades', 'longitud', 'real');
    await _ensureColumn(db, 'local_lotes_variedades', 'precision_gps', 'real');
    await _ensureColumn(db, 'local_lotes_variedades', 'fecha_gps', 'text');
  }

  Future<void> _createLocalPlagasConceptos(Database db) async {
    await db.execute("""
      create table if not exists local_plagas_conceptos(
        id text primary key,
        concepto text,
        estadio text,
        formula text
      )
    """);
    await _ensureColumn(db, 'local_plagas_conceptos', 'formula', 'text');
  }

  Future<void> _createLocalFenologias(Database db) async {
    await db.execute("""
      create table if not exists local_fenologias(
        etapa_fenologica text primary key
      )
    """);
  }

  Future<void> _createLocalConteoEstadios(Database db) async {
    await db.execute("""
      create table if not exists local_conteo_estadios(
        estadio text primary key,
        formula text
      )
    """);
  }

  Future<void> _createLocalCatalogValues(Database db) async {
    await db.execute("""
      create table if not exists local_catalog_values(
        catalog_key text,
        value text,
        primary key(catalog_key, value)
      )
    """);
  }

  Future<void> _createLocalMatrixRows(Database db) async {
    await db.execute("""
      create table if not exists local_matrix_rows(
        source_table text,
        row_key text,
        payload_json text,
        primary key(source_table, row_key)
      )
    """);
  }

  Future<void> _ensureIndexes(Database db) async {
    // Índices seguros: no cambian lógica ni datos; solo aceleran búsquedas frecuentes.
    // IMPORTANTE: en una instalación limpia, algunos índices podían ejecutarse antes
    // de que la tabla local exista. Eso rompía el login/actualización con:
    // "no such table: main.local_dynamic_views".
    await _safeCreateIndex(db, 'local_matrix_rows',
        'create index if not exists idx_local_matrix_rows_source_table on local_matrix_rows(source_table)');
    await _safeCreateIndex(db, 'local_form_fields',
        'create index if not exists idx_local_form_fields_table_active_order on local_form_fields(tabla_destino, activo, orden)');
    await _safeCreateIndex(db, 'local_catalog_values',
        'create index if not exists idx_local_catalog_values_key_value on local_catalog_values(catalog_key, value)');
    await _safeCreateIndex(db, 'local_format_tables',
        'create index if not exists idx_local_format_tables_formato_active_order on local_format_tables(formato_id, activo, orden)');
    await _safeCreateIndex(db, 'local_dynamic_views',
        'create index if not exists idx_local_dynamic_views_section_table on local_dynamic_views(seccion, tabla_destino, activo)');
    await _safeCreateIndex(db, 'local_permissions',
        'create index if not exists idx_local_permissions_user_format on local_permissions(user_id, formato)');
    await _safeCreateIndex(db, 'local_table_cache',
        'create index if not exists idx_local_table_cache_updated on local_table_cache(source_table, updated_at)');
  }

  Future<void> _createLocalSyncMeta(Database db) async {
    await db.execute("""
      create table if not exists local_sync_meta(
        key text primary key,
        value text
      )
    """);
  }

  Future<void> _createLocalIdSequences(Database db) async {
    await db.execute("""
      create table if not exists local_id_sequences(
        scope_key text primary key,
        last_value integer not null default 0
      )
    """);
  }

  Future<void> _createLocalTableCache(Database db) async {
    await db.execute("""
      create table if not exists local_table_cache(
        source_table text primary key,
        row_count integer,
        last_opened_at text,
        last_checked_at text,
        last_changed_at text,
        last_page integer,
        last_filter_key text,
        last_sort_column text,
        last_sort_ascending integer,
        updated_at text
      )
    """);
  }

  Future<void> _createLocalDynamicViews(Database db) async {
    await db.execute('''
      create table if not exists local_dynamic_views(
        id text primary key,
        seccion text,
        modulo text,
        tipo_vista text,
        tabla_destino text,
        nombre_vista text,
        estado_origen text,
        estado_destino text,
        filtro_estado text,
        campos_pendientes text,
        campos_editables text,
        campos_visibles text,
        requiere_todos_campos integer,
        activo integer,
        orden integer,
        payload_json text
      )
    ''');
  }

  Future<void> _createLocalSections(Database db) async {
    await db.execute('''
      create table if not exists local_sections(
        id text primary key,
        nombre text,
        seccion text,
        icono text,
        color text,
        orden integer,
        numero_decimales integer,
        grid_fila integer,
        grid_columna integer,
        grid_fila_pendientes integer,
        grid_columna_pendientes integer,
        rango_valor text,
        num_caracteres integer,
        activo integer
      )
    ''');
    await db.execute('''
      create table if not exists local_section_permissions(
        id text primary key,
        user_id text,
        seccion_id text,
        can_view integer,
        can_insert integer,
        can_update integer,
        can_delete integer
      )
    ''');
  }

  Future<void> _upgradeLocalFormatTables(Database db) async {
    await _ensureColumn(db, 'local_format_tables', 'auditable', 'integer');
    await _ensureColumn(db, 'local_format_tables', 'icono', 'text');
    await _ensureColumn(db, 'local_format_tables', 'imagen_encabezado', 'text');
    await _ensureColumn(db, 'local_format_tables', 'tipo_relacion', 'text');
    await _ensureColumn(db, 'local_format_tables', 'tabla_padre', 'text');
    await _ensureColumn(db, 'local_format_tables', 'campo_pk_padre', 'text');
    await _ensureColumn(db, 'local_format_tables', 'campo_fk_hijo', 'text');
    await _ensureColumn(db, 'local_format_tables', 'es_cabecera', 'integer');
    await _ensureColumn(db, 'local_format_tables', 'es_detalle', 'integer');
    await _ensureColumn(db, 'local_format_tables', 'campo_iterador', 'text');
    await _ensureColumn(db, 'local_format_tables', 'iterador_desde', 'integer');
    await _ensureColumn(db, 'local_format_tables', 'iterador_hasta', 'integer');
    await _ensureColumn(
        db, 'local_format_tables', 'copiar_campos_desde_padre', 'text');
    await _ensureColumn(db, 'local_format_tables', 'modo_captura', 'text');
  }

  Future<void> _upgradeLocalPermissions(Database db) async {
    await _ensureColumn(db, 'local_permissions', 'empresa_id', 'text');
    await _ensureColumn(db, 'local_permissions', 'can_export', 'integer');
    await _ensureColumn(db, 'local_permissions', 'can_import', 'integer');
    await _ensureColumn(db, 'local_permissions', 'can_review', 'integer');
    await _ensureColumn(db, 'local_permissions', 'can_approve', 'integer');
    await _ensureColumn(db, 'local_permissions', 'can_view_pending', 'integer');
    await _ensureColumn(
        db, 'local_permissions', 'can_complete_pending', 'integer');
    await _ensureColumn(db, 'local_permissions', 'seccion', 'text');
    await _ensureColumn(db, 'local_permissions', 'campos_restringidos', 'text');
    await _ensureColumn(db, 'local_permissions', 'permisos_flujo', 'text');
  }

  Future<void> _ensureRuntimeSchema(Database db) async {
    await _ensureColumn(db, 'local_profile', 'dni', 'text');
    await _ensureColumn(db, 'local_profile', 'email', 'text');
    await _createLocalFormFields(db);
    await _upgradeLocalFormFields(db);
    await _createLocalSpecialFormats(db);
    await _upgradeLocalFormatTables(db);
    await _ensureColumn(db, 'local_formats', 'tabla_visible_app', 'integer');
    await _ensureColumn(db, 'local_formats', 'capacidades', 'text');
    await _ensureColumn(db, 'local_formats', 'flujo_estados', 'text');
    await _ensureColumn(db, 'local_formats', 'workflow_enabled', 'integer');
    await _ensureColumn(db, 'local_formats', 'geolocation_enabled', 'integer');
    await _ensureColumn(db, 'local_formats', 'approvals_enabled', 'integer');
    await _ensureColumn(db, 'local_formats', 'layout_formulario', 'text');
    await _ensureColumn(db, 'local_formats', 'layout_registros', 'text');
    await _ensureColumn(db, 'local_formats', 'estado_revision_ia', 'text');
    await _ensureColumn(db, 'local_formats', 'auditable', 'integer');
    await _ensureColumn(db, 'local_formats', 'icono', 'text');
    await _ensureColumn(db, 'local_formats', 'imagen_encabezado', 'text');
    await _createLocalSections(db);
    await _upgradeLocalPermissions(db);
    await _createLocalLotesVariedades(db);
    await _createLocalPlagasConceptos(db);
    await _createLocalFenologias(db);
    await _createLocalConteoEstadios(db);
    await _createLocalCatalogValues(db);
    await _createLocalMatrixRows(db);
    await _createLocalTableCache(db);
    await _createLocalDynamicViews(db);
    await _createLocalSyncMeta(db);
    await _createLocalIdSequences(db);
    await _ensureIndexes(db);
    await _upgradePendingRecords(db);
    await _upgradeTenantColumns(db);
    await _upgradeNavigationMetadata(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _ensureColumn(db, 'local_profile', 'dni', 'text');
      await _ensureColumn(db, 'local_profile', 'email', 'text');
      await _createLocalFormFields(db);
    }
    if (oldVersion < 3) {
      await _createLocalSpecialFormats(db);
    }
    if (oldVersion < 4) {
      await _createLocalSections(db);
    }
    if (oldVersion < 5) {
      await _createLocalLotesVariedades(db);
    }
    if (oldVersion < 6) {
      await _createLocalPlagasConceptos(db);
    }
    if (oldVersion < 7) {
      await _createLocalPlagasConceptos(db);
      await _createLocalFenologias(db);
    }
    if (oldVersion < 8) {
      await _createLocalCatalogValues(db);
      await _createLocalMatrixRows(db);
    }
    if (oldVersion < 9) {
      await _ensureColumn(db, 'local_profile', 'dni', 'text');
      await _ensureColumn(db, 'local_profile', 'email', 'text');
      await _createLocalFormFields(db);
      await _upgradeLocalFormFields(db);
      await _createLocalMatrixRows(db);
    }
    if (oldVersion < 10) {
      await _ensureColumn(db, 'local_profile', 'dni', 'text');
      await _ensureColumn(db, 'local_profile', 'email', 'text');
      await _createLocalFormFields(db);
      await _upgradeLocalFormFields(db);
      await _createLocalMatrixRows(db);
    }
    if (oldVersion < 11) {
      await _ensureColumn(db, 'local_profile', 'dni', 'text');
      await _ensureColumn(db, 'local_profile', 'email', 'text');
      await _createLocalFormFields(db);
      await _upgradeLocalFormFields(db);
      await _createLocalMatrixRows(db);
    }
    if (oldVersion < 22) {
      await _createLocalSyncMeta(db);
    }
    if (oldVersion < 23) {
      await _createLocalTableCache(db);
    }
    if (oldVersion < 24) {
      await _upgradePendingRecords(db);
    }
    if (oldVersion < 31) {
      await _createLocalIdSequences(db);
    }
    if (oldVersion < 32) {
      await _ensureColumn(db, 'local_formats', 'auditable', 'integer');
      await _ensureColumn(db, 'local_formats', 'icono', 'text');
      await _ensureColumn(db, 'local_formats', 'imagen_encabezado', 'text');
      await _upgradeLocalFormatTables(db);
    }
    await _ensureColumn(db, 'local_modules', 'seccion', 'text');
    await _ensureColumn(db, 'local_formats', 'tabla_visible_app', 'integer');
    await _ensureColumn(db, 'local_formats', 'layout_formulario', 'text');
    await _ensureColumn(db, 'local_formats', 'layout_registros', 'text');
    await _ensureColumn(db, 'local_formats', 'estado_revision_ia', 'text');
    await _upgradeLocalPermissions(db);
    await _upgradeLocalFormatTables(db);
    await _createLocalSyncMeta(db);
    await _createLocalIdSequences(db);
    await _createLocalDynamicViews(db);
    await _ensureIndexes(db);
    await _upgradePendingRecords(db);
    await _upgradeTenantColumns(db);
    await _upgradeNavigationMetadata(db);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      create table local_modules(
        id text primary key,
        nombre text,
        icono text,
        color text,
        rubro_id text,
        orden integer,
        numero_decimales integer,
        grid_fila integer,
        grid_columna integer,
        grid_fila_pendientes integer,
        grid_columna_pendientes integer,
        rango_valor text,
        num_caracteres integer,
        activo integer,
        seccion text
      )
    ''');
    await db.execute('''
      create table local_formats(
        id text primary key,
        modulo_id text,
        nombre text,
        rubro_id text,
        tabla_destino text,
        ruta_flutter text,
        tabla_visible_app integer,
        capacidades text,
        flujo_estados text,
        workflow_enabled integer,
        geolocation_enabled integer,
        approvals_enabled integer,
        layout_formulario text,
        layout_registros text,
        estado_revision_ia text,
        auditable integer,
        icono text,
        imagen_encabezado text,
        orden integer,
        numero_decimales integer,
        grid_fila integer,
        grid_columna integer,
        grid_fila_pendientes integer,
        grid_columna_pendientes integer,
        rango_valor text,
        num_caracteres integer,
        activo integer
      )
    ''');
    await db.execute('''
      create table local_format_tables(
        id text primary key,
        formato_id text,
        nombre text,
        rubro_id text,
        tabla_destino text,
        orden integer,
        numero_decimales integer,
        grid_fila integer,
        grid_columna integer,
        grid_fila_pendientes integer,
        grid_columna_pendientes integer,
        rango_valor text,
        num_caracteres integer,
        tipo_relacion text,
        tabla_padre text,
        campo_pk_padre text,
        campo_fk_hijo text,
        es_cabecera integer,
        es_detalle integer,
        campo_iterador text,
        iterador_desde integer,
        iterador_hasta integer,
        copiar_campos_desde_padre text,
        modo_captura text,
        auditable integer,
        icono text,
        imagen_encabezado text,
        activo integer
      )
    ''');
    await db.execute('''
      create table local_permissions(
        id text primary key,
        empresa_id text,
        user_id text,
        modulo text,
        formato text,
        can_view integer,
        can_insert integer,
        can_update integer,
        can_delete integer,
        can_export integer,
        can_import integer,
        can_review integer,
        can_approve integer,
        can_view_pending integer,
        can_complete_pending integer,
        seccion text,
        campos_restringidos text,
        permisos_flujo text
      )
    ''');
    await db.execute('''
      create table local_profile(
        id text primary key,
        nombres text,
        cargo text,
        area text,
        dni text,
        email text,
        activo integer
      )
    ''');
    await _ensureColumn(db, 'local_profile', 'dni', 'text');
    await _ensureColumn(db, 'local_profile', 'email', 'text');
    await _createLocalFormFields(db);
    await _upgradeLocalFormFields(db);
    await _createLocalSpecialFormats(db);
    await _upgradeLocalFormatTables(db);
    await _ensureColumn(db, 'local_formats', 'tabla_visible_app', 'integer');
    await _ensureColumn(db, 'local_formats', 'layout_formulario', 'text');
    await _ensureColumn(db, 'local_formats', 'layout_registros', 'text');
    await _ensureColumn(db, 'local_formats', 'estado_revision_ia', 'text');
    await _createLocalSections(db);
    await _upgradeLocalPermissions(db);
    await _createLocalLotesVariedades(db);
    await _createLocalPlagasConceptos(db);
    await _createLocalFenologias(db);
    await _createLocalConteoEstadios(db);
    await _createLocalCatalogValues(db);
    await _createLocalMatrixRows(db);
    await _createLocalTableCache(db);
    await _createLocalDynamicViews(db);
    await _createLocalSyncMeta(db);
    await _ensureIndexes(db);
    await db.execute('''
      create table pending_records(
        id_local text primary key,
        user_id text,
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
    await _upgradePendingRecords(db);
    await _upgradeTenantColumns(db);
    await _upgradeNavigationMetadata(db);
  }

  Map<String, dynamic> _cleanForTable(
      Map<String, dynamic> row, Set<String> validColumns) {
    final cleanRow = <String, dynamic>{};
    for (final entry in row.entries) {
      if (validColumns.contains(entry.key)) cleanRow[entry.key] = entry.value;
    }
    return cleanRow;
  }

  Future<void> _insertRowsChunkedWithExecutor(
    DatabaseExecutor executor,
    String table,
    List<Map<String, dynamic>> rows,
    Set<String> validColumns,
  ) async {
    const chunkSize = 250;
    for (var start = 0; start < rows.length; start += chunkSize) {
      final end =
          (start + chunkSize > rows.length) ? rows.length : start + chunkSize;
      final batch = executor.batch();
      for (final row in rows.sublist(start, end)) {
        final cleanRow = _cleanForTable(row, validColumns);
        if (cleanRow.isNotEmpty) {
          batch.insert(table, cleanRow,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await batch.commit(noResult: true);
    }
  }

  Future<void> _insertRowsChunked(
    Database database,
    String table,
    List<Map<String, dynamic>> rows,
    Set<String> validColumns,
  ) async {
    const chunkSize = 250;
    for (var start = 0; start < rows.length; start += chunkSize) {
      final end =
          (start + chunkSize > rows.length) ? rows.length : start + chunkSize;
      await database.transaction((txn) async {
        await _insertRowsChunkedWithExecutor(
          txn,
          table,
          rows.sublist(start, end),
          validColumns,
        );
      });
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  Future<void> replaceTable(
      String table, List<Map<String, dynamic>> rows) async {
    final database = await db;
    final columnsInfo = await database.rawQuery('PRAGMA table_info($table)');
    final validColumns = columnsInfo
        .map((c) => c['name']?.toString())
        .whereType<String>()
        .toSet();

    await database.transaction((txn) async {
      await txn.delete(table);
      if (rows.isNotEmpty) {
        await _insertRowsChunkedWithExecutor(txn, table, rows, validColumns);
      }
    });
  }

  Future<void> upsertTable(
      String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final database = await db;
    final columnsInfo = await database.rawQuery('PRAGMA table_info($table)');
    final validColumns = columnsInfo
        .map((c) => c['name']?.toString())
        .whereType<String>()
        .toSet();

    await _insertRowsChunked(database, table, rows, validColumns);
  }

  /// Reemplaza de forma atómica solamente los catálogos indicados.
  ///
  /// Un `upsert` no elimina opciones que fueron borradas en Supabase. Esta
  /// operación evita dropdowns obsoletos sin vaciar los demás catálogos que
  /// no participaron en una sincronización incremental.
  Future<void> replaceCatalogValuesForKeys(
    Iterable<String> catalogKeys,
    List<Map<String, dynamic>> rows,
  ) async {
    final keys = catalogKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toSet()
        .toList();
    if (keys.isEmpty) return;

    final database = await db;
    await database.transaction((txn) async {
      const deleteChunkSize = 300;
      for (var start = 0; start < keys.length; start += deleteChunkSize) {
        final end = (start + deleteChunkSize < keys.length)
            ? start + deleteChunkSize
            : keys.length;
        final chunk = keys.sublist(start, end);
        await txn.delete(
          'local_catalog_values',
          where: 'catalog_key in (${List.filled(chunk.length, '?').join(',')})',
          whereArgs: chunk,
        );
      }

      final selectedRows = rows.where((row) {
        final key = row['catalog_key']?.toString().trim() ?? '';
        return keys.contains(key);
      }).toList();
      if (selectedRows.isNotEmpty) {
        await _insertRowsChunkedWithExecutor(
          txn,
          'local_catalog_values',
          selectedRows,
          const {'catalog_key', 'value'},
        );
      }
    });
  }

  Future<void> applyTableDelta(
    String table,
    List<Map<String, dynamic>> rows, {
    Iterable<String> deletedIds = const <String>[],
    String keyColumn = 'id',
  }) async {
    final safeIdentifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    if (!safeIdentifier.hasMatch(table) ||
        !safeIdentifier.hasMatch(keyColumn)) {
      throw ArgumentError('Identificador SQLite no valido.');
    }

    final database = await db;
    final columnsInfo = await database.rawQuery('PRAGMA table_info($table)');
    final validColumns = columnsInfo
        .map((c) => c['name']?.toString())
        .whereType<String>()
        .toSet();
    if (!validColumns.contains(keyColumn)) {
      throw ArgumentError('La tabla $table no contiene la clave $keyColumn.');
    }

    final ids = deletedIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    await database.transaction((txn) async {
      const deleteChunkSize = 400;
      for (var start = 0; start < ids.length; start += deleteChunkSize) {
        final end = (start + deleteChunkSize > ids.length)
            ? ids.length
            : start + deleteChunkSize;
        final chunk = ids.sublist(start, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        await txn.delete(
          table,
          where: '$keyColumn in ($placeholders)',
          whereArgs: chunk,
        );
      }
      if (rows.isNotEmpty) {
        await _insertRowsChunkedWithExecutor(txn, table, rows, validColumns);
      }
    });
  }

  Future<void> replaceRowsWhere(
    String table,
    List<Map<String, dynamic>> rows, {
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final safeIdentifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    if (!safeIdentifier.hasMatch(table)) {
      throw ArgumentError('Identificador SQLite no valido.');
    }
    final database = await db;
    final columnsInfo = await database.rawQuery('PRAGMA table_info($table)');
    final validColumns = columnsInfo
        .map((c) => c['name']?.toString())
        .whereType<String>()
        .toSet();
    await database.transaction((txn) async {
      await txn.delete(table, where: where, whereArgs: whereArgs);
      if (rows.isNotEmpty) {
        await _insertRowsChunkedWithExecutor(txn, table, rows, validColumns);
      }
    });
  }

  bool _payloadBool(dynamic value) {
    if (value == true) return true;
    if (value == false || value == null) return false;
    final s = value.toString().trim().toLowerCase();
    return s == 'true' ||
        s == 't' ||
        s == '1' ||
        s == 'si' ||
        s == 'sí' ||
        s == 's' ||
        s == 'yes';
  }

  bool _payloadIsDeleted(Map<String, dynamic> payload) {
    if (_payloadBool(_payloadValue(
        payload, ['eliminado', 'ELIMINADO', 'deleted', 'DELETED'])))
      return true;
    final estado =
        (_payloadValue(payload, ['estado_sync', 'ESTADO_SYNC']) ?? '')
            .toString()
            .trim()
            .toLowerCase();
    if (estado == 'eliminado' || estado == 'deleted' || estado == 'delete')
      return true;
    final deletedAt =
        (_payloadValue(payload, ['deleted_at', 'DELETED_AT']) ?? '')
            .toString()
            .trim();
    return deletedAt.isNotEmpty && deletedAt.toUpperCase() != 'NULL';
  }

  String _matrixRowKeyForPayload(
      String table, Map<String, dynamic> payload, int index) {
    final idLocal =
        _payloadValue(payload, ['id_local', 'ID_LOCAL'])?.toString().trim() ??
            '';
    final idValue = _payloadValue(payload, ['id', 'ID', 'codigo', 'CODIGO'])
            ?.toString()
            .trim() ??
        '';
    if (idLocal.isNotEmpty) return idLocal;
    if (idValue.isNotEmpty) return idValue;
    return '${table}_$index';
  }

  Future<void> _yieldToRenderer() async {
    // SQLite ejecuta fuera del raster, pero preparar mapas, decodificar y
    // serializar JSON sí consume el isolate principal. Esta pausa permite que
    // Flutter entregue un frame entre lotes y mantiene fluida la animación.
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }

  Future<void> applyMatrixRowsFromPayloads(
    Map<String, List<Map<String, dynamic>>> sourceRows, {
    bool replaceSources = false,
  }) async {
    if (sourceRows.isEmpty) return;
    final database = await db;
    const chunkSize = 80;

    for (final entry in sourceRows.entries) {
      final table = entry.key.trim();
      if (table.isEmpty) continue;
      final payloads = entry.value;

      if (replaceSources) {
        await database.transaction((txn) async {
          await txn.delete(
            'local_matrix_rows',
            where: 'source_table = ?',
            whereArgs: [table],
          );
          for (var offset = 0; offset < payloads.length; offset += chunkSize) {
            final limit = (offset + chunkSize < payloads.length)
                ? offset + chunkSize
                : payloads.length;
            final batch = txn.batch();
            for (var index = offset; index < limit; index++) {
              final payload = payloads[index];
              if (_payloadIsDeleted(payload)) continue;
              batch.insert(
                'local_matrix_rows',
                {
                  'source_table': table,
                  'row_key': _matrixRowKeyForPayload(table, payload, index),
                  'payload_json': jsonEncode(payload),
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
            await batch.commit(noResult: true);
          }
        });
        await _yieldToRenderer();
        continue;
      }

      final existingRows = await database.query(
        'local_matrix_rows',
        columns: ['row_key', 'payload_json'],
        where: 'source_table = ?',
        whereArgs: [table],
      );

      final byIdLocal = <String, String>{};
      final byIdValue = <String, String>{};
      for (var i = 0; i < existingRows.length; i++) {
        final row = existingRows[i];
        final rowKey = row['row_key']?.toString() ?? '';
        if (rowKey.isNotEmpty) {
          try {
            final decoded = jsonDecode(row['payload_json']?.toString() ?? '{}')
                as Map<String, dynamic>;
            final cachedIdLocal =
                _payloadValue(decoded, ['id_local', 'ID_LOCAL'])
                        ?.toString()
                        .trim() ??
                    '';
            final cachedId =
                _payloadValue(decoded, ['id', 'ID', 'codigo', 'CODIGO'])
                        ?.toString()
                        .trim() ??
                    '';
            if (cachedIdLocal.isNotEmpty) byIdLocal[cachedIdLocal] = rowKey;
            if (cachedId.isNotEmpty) byIdValue[cachedId] = rowKey;
          } catch (_) {}
        }
        if (i > 0 && i % chunkSize == 0) await _yieldToRenderer();
      }

      for (var offset = 0; offset < payloads.length; offset += chunkSize) {
        final limit = (offset + chunkSize < payloads.length)
            ? offset + chunkSize
            : payloads.length;
        await database.transaction((txn) async {
          final batch = txn.batch();
          for (var index = offset; index < limit; index++) {
            final payload = payloads[index];
            final idLocal = _payloadValue(payload, ['id_local', 'ID_LOCAL'])
                    ?.toString()
                    .trim() ??
                '';
            final idValue =
                _payloadValue(payload, ['id', 'ID', 'codigo', 'CODIGO'])
                        ?.toString()
                        .trim() ??
                    '';
            final existingKey = idLocal.isNotEmpty ? byIdLocal[idLocal] : null;
            final rowKey =
                (existingKey != null && existingKey.trim().isNotEmpty)
                    ? existingKey
                    : (idValue.isNotEmpty && byIdValue[idValue] != null)
                        ? byIdValue[idValue]!
                        : _matrixRowKeyForPayload(table, payload, index);

            if (_payloadIsDeleted(payload)) {
              batch.delete(
                'local_matrix_rows',
                where: 'source_table = ? AND row_key = ?',
                whereArgs: [table, rowKey],
              );
              continue;
            }

            batch.insert(
              'local_matrix_rows',
              {
                'source_table': table,
                'row_key': rowKey,
                'payload_json': jsonEncode(payload),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          await batch.commit(noResult: true);
        });
        await _yieldToRenderer();
      }
    }
  }

  Future<void> upsertMatrixRowPayloads(
      String sourceTable, List<Map<String, dynamic>> payloads) async {
    final table = sourceTable.trim();
    if (table.isEmpty || payloads.isEmpty) return;
    final database = await db;

    // Leer una sola vez las claves existentes de esa tabla. El método anterior
    // hacía un SELECT completo por cada registro sincronizado.
    final existingRows = await database.query(
      'local_matrix_rows',
      columns: ['row_key', 'payload_json'],
      where: 'source_table = ?',
      whereArgs: [table],
    );

    final byIdLocal = <String, String>{};
    final byIdValue = <String, String>{};
    for (final row in existingRows) {
      final rowKey = row['row_key']?.toString() ?? '';
      if (rowKey.isEmpty) continue;
      try {
        final decoded = jsonDecode(row['payload_json']?.toString() ?? '{}')
            as Map<String, dynamic>;
        final cachedIdLocal = _payloadValue(decoded, ['id_local', 'ID_LOCAL'])
                ?.toString()
                .trim() ??
            '';
        final cachedId =
            _payloadValue(decoded, ['id', 'ID', 'codigo', 'CODIGO'])
                    ?.toString()
                    .trim() ??
                '';
        if (cachedIdLocal.isNotEmpty) byIdLocal[cachedIdLocal] = rowKey;
        if (cachedId.isNotEmpty) byIdValue[cachedId] = rowKey;
      } catch (_) {}
    }

    await database.transaction((txn) async {
      final batch = txn.batch();
      for (final payload in payloads) {
        final idLocal = _payloadValue(payload, ['id_local', 'ID_LOCAL'])
                ?.toString()
                .trim() ??
            '';
        final idValue = _payloadValue(payload, ['id', 'ID', 'codigo', 'CODIGO'])
                ?.toString()
                .trim() ??
            '';
        final existingKey = idLocal.isNotEmpty ? byIdLocal[idLocal] : null;
        final rowKey = (existingKey != null && existingKey.trim().isNotEmpty)
            ? existingKey
            : (idValue.isNotEmpty && byIdValue[idValue] != null)
                ? byIdValue[idValue]!
                : (idLocal.isNotEmpty
                    ? idLocal
                    : (idValue.isNotEmpty
                        ? idValue
                        : '${table}_${DateTime.now().microsecondsSinceEpoch}'));
        if (_payloadIsDeleted(payload)) {
          batch.delete(
            'local_matrix_rows',
            where: 'source_table = ? AND row_key = ?',
            whereArgs: [table, rowKey],
          );
          continue;
        }
        batch.insert(
          'local_matrix_rows',
          {
            'source_table': table,
            'row_key': rowKey,
            'payload_json': jsonEncode(payload),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> upsertMatrixRowPayload(
      String sourceTable, Map<String, dynamic> payload) async {
    final table = sourceTable.trim();
    if (table.isEmpty) return;
    final database = await db;
    final idLocal =
        _payloadValue(payload, ['id_local', 'ID_LOCAL'])?.toString().trim() ??
            '';
    final idValue = _payloadValue(payload, ['id', 'ID', 'codigo', 'CODIGO'])
            ?.toString()
            .trim() ??
        '';
    String? existingKey;

    if (idLocal.isNotEmpty || idValue.isNotEmpty) {
      final rows = await database.query(
        'local_matrix_rows',
        columns: ['row_key', 'payload_json'],
        where: 'source_table = ?',
        whereArgs: [table],
      );
      for (final row in rows) {
        try {
          final decoded = jsonDecode(row['payload_json']?.toString() ?? '{}')
              as Map<String, dynamic>;
          final cachedIdLocal = _payloadValue(decoded, ['id_local', 'ID_LOCAL'])
                  ?.toString()
                  .trim() ??
              '';
          final cachedId =
              _payloadValue(decoded, ['id', 'ID', 'codigo', 'CODIGO'])
                      ?.toString()
                      .trim() ??
                  '';
          if ((idLocal.isNotEmpty && cachedIdLocal == idLocal) ||
              (idValue.isNotEmpty && cachedId == idValue)) {
            existingKey = row['row_key']?.toString();
            break;
          }
        } catch (_) {}
      }
    }

    final rowKey = (existingKey != null && existingKey!.trim().isNotEmpty)
        ? existingKey!
        : (idLocal.isNotEmpty
            ? idLocal
            : (idValue.isNotEmpty
                ? idValue
                : '${table}_${DateTime.now().microsecondsSinceEpoch}'));

    if (_payloadIsDeleted(payload)) {
      await database.delete(
        'local_matrix_rows',
        where: 'source_table = ? AND row_key = ?',
        whereArgs: [table, rowKey],
      );
      return;
    }

    await database.insert(
      'local_matrix_rows',
      {
        'source_table': table,
        'row_key': rowKey,
        'payload_json': jsonEncode(payload),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getMetaValue(String key) async {
    final database = await db;
    await _createLocalSyncMeta(database);
    final rows = await database.query('local_sync_meta',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value']?.toString();
  }

  Future<void> setMetaValue(String key, String value) async {
    final database = await db;
    await _createLocalSyncMeta(database);
    await database.insert(
      'local_sync_meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> setMetaValues(Map<String, String> values) async {
    if (values.isEmpty) return;
    final database = await db;
    await _createLocalSyncMeta(database);
    await database.transaction((txn) async {
      final batch = txn.batch();
      for (final entry in values.entries) {
        batch.insert(
          'local_sync_meta',
          {'key': entry.key, 'value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<int> countMatrixRowsForTable(String sourceTable) async {
    final table = sourceTable.trim();
    if (table.isEmpty) return 0;
    final database = await db;
    final result = await database.rawQuery(
      'select count(*) as total from local_matrix_rows where source_table = ?',
      [table],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> matrixPayloads(
    String sourceTable, {
    String? empresaId,
  }) async {
    final table = sourceTable.trim();
    if (table.isEmpty) return const <Map<String, dynamic>>[];
    final database = await db;
    final rows = await database.query(
      'local_matrix_rows',
      columns: ['payload_json'],
      where: 'source_table = ?',
      whereArgs: [table],
    );
    final decoded = <Map<String, dynamic>>[];
    for (final row in rows) {
      try {
        final payload = Map<String, dynamic>.from(
          jsonDecode(row['payload_json']?.toString() ?? '{}') as Map,
        );
        final payloadEmpresa = payload['empresa_id']?.toString().trim() ?? '';
        if (empresaId != null &&
            empresaId.trim().isNotEmpty &&
            payloadEmpresa.isNotEmpty &&
            payloadEmpresa != empresaId.trim()) {
          continue;
        }
        decoded.add(payload);
      } catch (_) {
        // Una fila de cache corrupta no debe impedir abrir el formulario.
      }
    }
    return decoded;
  }

  Future<List<String>> matrixSourceTables() async {
    final database = await db;
    final rows = await database.rawQuery(
      'select distinct source_table from local_matrix_rows '
      'where source_table is not null and trim(source_table) <> ? '
      'order by source_table',
      [''],
    );
    return rows
        .map((row) => row['source_table']?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> getTableCacheInfo(String sourceTable) async {
    final cleanTable = sourceTable.trim();
    if (cleanTable.isEmpty) return null;
    final database = await db;
    await _createLocalTableCache(database);
    final rows = await database.query(
      'local_table_cache',
      where: 'source_table = ?',
      whereArgs: [cleanTable],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<void> upsertTableCacheInfo(
    String sourceTable, {
    int? rowCount,
    DateTime? lastOpenedAt,
    DateTime? lastCheckedAt,
    DateTime? lastChangedAt,
    int? lastPage,
    String? lastFilterKey,
    String? lastSortColumn,
    bool? lastSortAscending,
  }) async {
    final cleanTable = sourceTable.trim();
    if (cleanTable.isEmpty) return;
    final database = await db;
    await _createLocalTableCache(database);

    final existing = await getTableCacheInfo(cleanTable) ?? <String, dynamic>{};
    String? iso(DateTime? value) => value?.toUtc().toIso8601String();

    await database.insert(
      'local_table_cache',
      {
        'source_table': cleanTable,
        'row_count': rowCount ?? existing['row_count'],
        'last_opened_at': iso(lastOpenedAt) ?? existing['last_opened_at'],
        'last_checked_at': iso(lastCheckedAt) ?? existing['last_checked_at'],
        'last_changed_at': iso(lastChangedAt) ?? existing['last_changed_at'],
        'last_page': lastPage ?? existing['last_page'],
        'last_filter_key': lastFilterKey ?? existing['last_filter_key'],
        'last_sort_column': lastSortColumn ?? existing['last_sort_column'],
        'last_sort_ascending': lastSortAscending == null
            ? existing['last_sort_ascending']
            : (lastSortAscending ? 1 : 0),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> hasOfflineBootstrapCache() async {
    final database = await db;
    try {
      final result = await database.rawQuery("""
        select
          (select count(*) from local_modules) as modules,
          (select count(*) from local_formats) as formats,
          (select count(*) from local_form_fields) as fields
      """);
      final row = result.first;
      return ((row['modules'] as int? ?? 0) > 0) &&
          ((row['formats'] as int? ?? 0) > 0) &&
          ((row['fields'] as int? ?? 0) > 0);
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getAll(String table,
      {String? orderBy}) async {
    final database = await db;
    return database.query(table, orderBy: orderBy);
  }

  Future<List<Map<String, dynamic>>> where(
    String table,
    String where,
    List<Object?> args, {
    String? orderBy,
  }) async {
    final database = await db;
    return database.query(table,
        where: where, whereArgs: args, orderBy: orderBy);
  }

  static const int maxSyncedLocalRecords = 150;

  Future<void> insertPending(Map<String, dynamic> row) async {
    final database = await db;
    // Guardado local debe ser mínimo: solo persistir la cola pendiente.
    // No depurar, no recargar matrices y no ejecutar trabajos secundarios aquí.
    final scopedRow = Map<String, dynamic>.from(row);
    final idLocal = scopedRow['id_local']?.toString().trim() ?? '';
    final now = DateTime.now().toUtc().toIso8601String();
    if (idLocal.isNotEmpty) {
      final existing = await database.query(
        'pending_records',
        columns: ['version_local', 'created_at', 'base_updated_at'],
        where: 'id_local = ?',
        whereArgs: [idLocal],
        limit: 1,
      );
      final currentVersion = existing.isEmpty
          ? 0
          : (existing.first['version_local'] as num?)?.toInt() ?? 0;
      scopedRow['version_local'] = currentVersion + 1;
      if (existing.isNotEmpty &&
          (scopedRow['created_at']?.toString().trim().isEmpty ?? true)) {
        scopedRow['created_at'] = existing.first['created_at'];
      }
      if (existing.isNotEmpty &&
          (scopedRow['base_updated_at']?.toString().trim().isEmpty ?? true)) {
        scopedRow['base_updated_at'] = existing.first['base_updated_at'];
      }
    }
    scopedRow.putIfAbsent(
      'estado',
      () => OfflineRecordState.pending.storageValue,
    );
    scopedRow['updated_at_local'] = now;
    scopedRow.putIfAbsent('created_at', () => now);
    scopedRow.putIfAbsent('base_updated_at', () {
      try {
        final payload = jsonDecode(scopedRow['payload_json']?.toString() ?? '')
            as Map<String, dynamic>;
        return _payloadValue(payload, ['updated_at', 'UPDATED_AT'])
            ?.toString()
            .trim();
      } catch (_) {
        return null;
      }
    });
    scopedRow.putIfAbsent('empresa_id', () => TenantConfig.defaultEmpresaId);
    await database.insert('pending_records', scopedRow,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String> nextIncrementalIdentifier({
    required String table,
    required String field,
    required String prefix,
  }) async {
    final database = await db;
    await _createLocalIdSequences(database);
    final cleanPrefix = prefix.trim();
    final scope =
        '${table.trim().toUpperCase()}|${field.trim().toUpperCase()}|$cleanPrefix';
    return database.transaction((txn) async {
      var maximum = 0;
      final sequence = await txn.query(
        'local_id_sequences',
        columns: ['last_value'],
        where: 'scope_key = ?',
        whereArgs: [scope],
        limit: 1,
      );
      if (sequence.isNotEmpty) {
        maximum = (sequence.first['last_value'] as num?)?.toInt() ?? 0;
      }

      final expression = RegExp(
        '^${RegExp.escape(cleanPrefix)}([0-9]+)\$',
        caseSensitive: false,
      );
      void inspectRows(List<Map<String, Object?>> rows) {
        for (final row in rows) {
          try {
            final payload = jsonDecode(
              row['payload_json']?.toString() ?? '{}',
            ) as Map<String, dynamic>;
            dynamic value;
            for (final entry in payload.entries) {
              if (entry.key.toUpperCase() == field.trim().toUpperCase()) {
                value = entry.value;
                break;
              }
            }
            final match = expression.firstMatch(value?.toString().trim() ?? '');
            final number = int.tryParse(match?.group(1) ?? '') ?? 0;
            if (number > maximum) maximum = number;
          } catch (_) {}
        }
      }

      inspectRows(await txn.query(
        'local_matrix_rows',
        columns: ['payload_json'],
        where: 'source_table = ?',
        whereArgs: [table],
      ));
      inspectRows(await txn.query(
        'pending_records',
        columns: ['payload_json'],
        where: 'tabla_destino = ?',
        whereArgs: [table],
      ));

      final next = maximum + 1;
      await txn.insert(
        'local_id_sequences',
        {'scope_key': scope, 'last_value': next},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return '$cleanPrefix$next';
    });
  }

  Future<void> _pruneLocalRecords(Database database) async {
    // Mantener siempre los registros no sincronizados o con error.
    // Solo se depuran los registros ya sincronizados, conservando los últimos 150.
    await database.rawDelete('''
      delete from pending_records
      where estado = 'sincronizado'
        and id_local not in (
          select id_local
          from pending_records
          where estado = 'sincronizado'
          order by datetime(coalesce(synced_at, created_at, '1970-01-01T00:00:00')) desc
          limit $maxSyncedLocalRecords
        )
    ''');
  }

  Future<List<Map<String, dynamic>>> pendingRecords({
    String? userId,
    String? empresaId,
  }) async {
    final database = await db;
    final where = <String>['estado in (?, ?)'];
    final args = <Object?>[
      OfflineRecordState.pending.storageValue,
      OfflineRecordState.error.storageValue,
    ];
    if (userId != null && userId.trim().isNotEmpty) {
      where.add('user_id = ?');
      args.add(userId.trim());
    }
    if (empresaId != null && empresaId.trim().isNotEmpty) {
      where.add('empresa_id = ?');
      args.add(empresaId.trim());
    }
    return database.query(
      'pending_records',
      where: where.join(' and '),
      whereArgs: args,
    );
  }

  Future<List<Map<String, dynamic>>> allRecords({
    String? estado,
    String? userId,
    String? empresaId,
  }) async {
    final database = await db;
    await _pruneLocalRecords(database);
    final where = <String>[];
    final args = <Object?>[];
    if (estado != null) {
      if (estado == OfflineRecordState.pending.storageValue) {
        where.add('estado <> ?');
        args.add(OfflineRecordState.synced.storageValue);
      } else {
        where.add('estado = ?');
        args.add(estado);
      }
    }
    if (userId != null && userId.trim().isNotEmpty) {
      where.add('user_id = ?');
      args.add(userId.trim());
    }
    if (empresaId != null && empresaId.trim().isNotEmpty) {
      where.add('empresa_id = ?');
      args.add(empresaId.trim());
    }
    return database.query(
      'pending_records',
      where: where.isEmpty ? null : where.join(' and '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: estado == 'sincronizado'
          ? 'coalesce(synced_at, created_at) desc'
          : 'created_at desc',
      limit: estado == 'sincronizado' ? maxSyncedLocalRecords : null,
    );
  }

  Future<void> deleteRecord(String idLocal) async {
    final database = await db;
    await database
        .delete('pending_records', where: 'id_local = ?', whereArgs: [idLocal]);
  }

  Future<void> deletePendingRecordsByPrefix(String idLocalPrefix) async {
    final database = await db;
    await database.delete(
      'pending_records',
      where: 'estado <> ? and id_local like ?',
      whereArgs: [OfflineRecordState.synced.storageValue, '$idLocalPrefix%'],
    );
  }

  String _normKey(String value) {
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
        .replaceAll(RegExp(r'^_|_\$'), '');
  }

  dynamic _payloadValue(Map<String, dynamic> payload, List<String> candidates) {
    final wanted = candidates.map(_normKey).toSet();
    for (final entry in payload.entries) {
      if (wanted.contains(_normKey(entry.key))) return entry.value;
    }
    return null;
  }

  Future<void> deletePendingRecordsByLogicalId({
    required String formatoId,
    required String tablaDestino,
    required String idRegistro,
  }) async {
    final id = idRegistro.trim();
    if (id.isEmpty) return;
    final database = await db;
    final rows = await database.query(
      'pending_records',
      where: 'estado <> ? and formato_id = ? and tabla_destino = ?',
      whereArgs: [
        OfflineRecordState.synced.storageValue,
        formatoId,
        tablaDestino,
      ],
    );
    final idsToDelete = <String>[];
    for (final row in rows) {
      try {
        final payload = jsonDecode(row['payload_json']?.toString() ?? '{}')
            as Map<String, dynamic>;
        final candidateId =
            _payloadValue(payload, ['ID_REGISTRO', 'ID'])?.toString().trim() ??
                '';
        if (candidateId == id) {
          final idLocal = row['id_local']?.toString() ?? '';
          if (idLocal.isNotEmpty) idsToDelete.add(idLocal);
        }
      } catch (_) {}
    }
    for (final idLocal in idsToDelete) {
      await database.delete('pending_records',
          where: 'id_local = ?', whereArgs: [idLocal]);
    }
  }

  Future<int> pendingCount() async {
    final database = await db;
    final result = await database.rawQuery(
      'select count(*) as total from pending_records where estado <> ?',
      [OfflineRecordState.synced.storageValue],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  Future<void> markSynced(String idLocal) async {
    final database = await db;
    await database.update(
      'pending_records',
      {
        'estado': OfflineRecordState.synced.storageValue,
        'synced_at': DateTime.now().toUtc().toIso8601String(),
        'error_mensaje': null,
        'conflict_json': null,
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<void> markSyncedBatch(List<String> idLocals) async {
    if (idLocals.isEmpty) return;
    final database = await db;
    final now = DateTime.now().toUtc().toIso8601String();
    await database.transaction((txn) async {
      final batch = txn.batch();
      for (final idLocal in idLocals) {
        if (idLocal.trim().isEmpty) continue;
        batch.update(
          'pending_records',
          {
            'estado': OfflineRecordState.synced.storageValue,
            'synced_at': now,
            'error_mensaje': null,
            'conflict_json': null,
          },
          where: 'id_local = ?',
          whereArgs: [idLocal],
        );
      }
      await batch.commit(noResult: true);
    });
    // Una sola limpieza al final del lote, no por cada registro.
    await _pruneLocalRecords(database);
  }

  Future<void> markError(String idLocal, String error) async {
    final database = await db;
    await database.rawUpdate('''
      update pending_records
      set estado = ?,
          intentos = intentos + 1,
          error_mensaje = ?,
          last_attempt_at = ?
      where id_local = ?
    ''', [
      OfflineRecordState.error.storageValue,
      error,
      DateTime.now().toUtc().toIso8601String(),
      idLocal,
    ]);
  }

  Future<void> markSyncing(String idLocal) async {
    final database = await db;
    await database.update(
      'pending_records',
      {
        'estado': OfflineRecordState.syncing.storageValue,
        'last_attempt_at': DateTime.now().toUtc().toIso8601String(),
        'error_mensaje': null,
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<void> markConflict(
    String idLocal,
    Map<String, dynamic> conflict, {
    String? remoteVersion,
  }) async {
    final database = await db;
    await database.update(
      'pending_records',
      {
        'estado': OfflineRecordState.conflict.storageValue,
        'conflict_json': jsonEncode(conflict),
        'version_remota': remoteVersion,
        'error_mensaje': 'El registro remoto cambió desde la última descarga.',
        'last_attempt_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<void> retryConflict(String idLocal) async {
    final database = await db;
    await database.update(
      'pending_records',
      {
        'estado': OfflineRecordState.pending.storageValue,
        'conflict_json': null,
        'error_mensaje': null,
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Map<String, dynamic> decodePayload(Map<String, dynamic> row) {
    return jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
  }
}
