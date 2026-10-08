import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide ScaffoldMessenger;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_filex/open_filex.dart';
import 'package:uuid/uuid.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/local_db.dart';
import '../../core/services/evidence_storage.dart';
import '../../core/services/human_resources_rules.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../core/widgets/zumac_scaffold_messenger.dart';
import '../../core/services/dynamic_rules_repository.dart';
import '../../core/services/local_session.dart';
import '../../core/services/formula_engine.dart';
import '../../core/services/soft_delete.dart';
import '../../core/platform/file_download.dart';
import '../../core/platform/app_platform.dart';
import '../../core/platform/network_bytes.dart';
import '../../core/services/sync_service.dart';
import '../modules/modules_page.dart';

class FormRunnerPage extends StatefulWidget {
  final String moduleId;
  final Map<String, dynamic> format;
  final Map<String, dynamic>? initialPayload;
  final String? editIdLocal;
  final String? initialFormatTableId;
  final String? editPrimaryKeyColumn;
  final dynamic editPrimaryKeyValue;
  final VoidCallback? onBack;

  const FormRunnerPage({
    super.key,
    required this.moduleId,
    required this.format,
    this.initialPayload,
    this.editIdLocal,
    this.initialFormatTableId,
    this.editPrimaryKeyColumn,
    this.editPrimaryKeyValue,
    this.onBack,
  });

  @override
  State<FormRunnerPage> createState() => _FormRunnerPageState();
}

class _FormRunnerPageState extends State<FormRunnerPage> {
  final local = LocalDb.instance;
  final uuid = const Uuid();

  List<Map<String, dynamic>> internalTables = [];
  List<Map<String, dynamic>> fields = [];
  List<Map<String, dynamic>> lotesVariedades = [];
  List<Map<String, dynamic>> personnelWorkers = [];
  Map<String, List<String>> catalogValues = {};
  Map<String, Map<String, dynamic>> fieldDefsById = {};
  Map<String, List<Map<String, dynamic>>> matrixRowsByTable = {};
  String? selectedInternalTableId;
  final controllers = <String, TextEditingController>{};
  final focusNodes = <String, FocusNode>{};
  final dropdownValues = <String, int?>{};
  final multiSelectValues = <String, Set<String>>{};
  final signatureValues = <String, Uint8List?>{};
  final photoValues = <String, Uint8List?>{};
  final Map<String, String> documentFileNames = <String, String>{};
  final ImagePicker _imagePicker = ImagePicker();
  Timer? _formulaRecalcDebounce;
  String? _selectedPersonnelDni;
  bool capturingPhoto = false;
  bool savingLocal = false;
  bool loadingFields = true;
  Set<String> restrictedFields = <String>{};
  final Map<String, Map<String, dynamic>> _fieldDefLookup =
      <String, Map<String, dynamic>>{};
  final Map<String, String> _campoLookup = <String, String>{};
  Map<String, dynamic>? _wizardMasterPayload;
  String? _wizardMasterIdLocal;
  int? _wizardCurrentIteration;

  // Cache local por proceso: evita volver a leer matrices/catálogos desde SQLite
  // cada vez que se abre un formato en Android. Se limpia al cerrar la app;
  // al usar "Actualizar datos" y reiniciar la vista se recargan datos locales.
  static List<Map<String, dynamic>>? _cachedAllFormFields;
  static Map<String, List<Map<String, dynamic>>>? _cachedFormFieldsByTable;
  static Map<String, Map<String, dynamic>>? _cachedFieldDefsById;
  static Map<String, List<String>>? _cachedCatalogValues;
  static List<Map<String, dynamic>>? _cachedLotesVariedades;
  static Map<String, List<Map<String, dynamic>>>? _cachedMatrixRowsByTable;

  Future<List<Map<String, dynamic>>> _allFormFieldsCached() async {
    // Windows/desktop puede actualizar MATRIZ_CAMPOS_FORMATO_APPGT con la app abierta.
    // No se debe devolver una copia estática vieja: esa era la causa de que
    // grid_fila, grid_columna e id_campo_dropdown parecieran no obedecer.
    final rows = await local.getAll('local_form_fields', orderBy: 'orden');
    _cachedAllFormFields = rows;
    final grouped = <String, List<Map<String, dynamic>>>{};
    final byId = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final table = row['tabla_destino']?.toString() ?? '';
      final key = _normalizarNombreCampo(table);
      if (key.isNotEmpty && _asBool(row['activo'], defaultValue: true)) {
        grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(row);
      }
      final id = row['id']?.toString().trim() ?? '';
      if (id.isNotEmpty) byId[id] = row;
    }
    _cachedFormFieldsByTable = grouped;
    _cachedFieldDefsById = byId;
    return rows;
  }

  Future<Map<String, List<Map<String, dynamic>>>>
      _formFieldsByTableCached() async {
    final cached = _cachedFormFieldsByTable;
    if (cached != null) return cached;
    await _allFormFieldsCached();
    return _cachedFormFieldsByTable ?? <String, List<Map<String, dynamic>>>{};
  }

  Future<Map<String, Map<String, dynamic>>> _fieldDefsByIdCached() async {
    await _allFormFieldsCached();
    return _cachedFieldDefsById ?? <String, Map<String, dynamic>>{};
  }

  @override
  void initState() {
    super.initState();
    loadInternalTables();
  }

  Future<void> loadInternalTables() async {
    if (mounted) {
      setState(() => loadingFields = true);
    }

    final rowsFuture = local.where(
      'local_format_tables',
      'formato_id = ? and activo = 1',
      [widget.format['id']],
      orderBy: 'orden',
    );

    // Precalienta en paralelo las matrices/catálogos que usa el formulario.
    final preloadFutures = <Future<void>>[
      _loadLotesVariedades(updateState: false),
      _loadCatalogValues(updateState: false),
    ];

    final rows = await rowsFuture;

    final uniqueById = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final id = row['id']?.toString().trim();
      if (id != null && id.isNotEmpty && !uniqueById.containsKey(id)) {
        uniqueById[id] = row;
      }
    }

    final cleanRows = uniqueById.values.toList();
    final currentId = selectedInternalTableId;
    final selectedStillExists = currentId != null &&
        cleanRows.any((row) => row['id']?.toString() == currentId);
    final requestedInitialId = widget.initialFormatTableId?.trim();
    final requestedInitialExists = requestedInitialId != null &&
        requestedInitialId.isNotEmpty &&
        cleanRows.any((row) => row['id']?.toString() == requestedInitialId);

    await Future.wait(preloadFutures);

    if (!mounted) return;
    final preferredInitial = cleanRows.firstWhere(
      (row) => _isHeaderTableRow(row),
      orElse: () =>
          cleanRows.isNotEmpty ? cleanRows.first : <String, dynamic>{},
    );
    final preferredInitialId = preferredInitial['id']?.toString();
    setState(() {
      internalTables = cleanRows;
      selectedInternalTableId = selectedStillExists
          ? currentId
          : (requestedInitialExists
              ? requestedInitialId
              : ((preferredInitialId != null && preferredInitialId.isNotEmpty)
                  ? preferredInitialId
                  : (cleanRows.isNotEmpty
                      ? cleanRows.first['id']?.toString()
                      : null)));
    });

    await loadFieldsForCurrentTable();
  }

  Future<void> _loadLotesVariedades({bool updateState = true}) async {
    final rows = _cachedLotesVariedades ??
        await local.getAll('local_lotes_variedades', orderBy: 'turno');
    _cachedLotesVariedades = rows;
    if (!mounted) return;
    if (updateState) {
      setState(() => lotesVariedades = rows);
    } else {
      lotesVariedades = rows;
    }
  }

  Future<void> _loadFieldDefinitionsIndex({bool updateState = true}) async {
    final byId = await _fieldDefsByIdCached();
    if (!mounted) return;
    if (updateState) {
      setState(() => fieldDefsById = byId);
    } else {
      fieldDefsById = byId;
    }
  }

  Future<List<Map<String, dynamic>>> _loadRemoteMatrixSource(
    String table,
  ) async {
    const pageSize = 1000;
    var from = 0;
    final rows = <Map<String, dynamic>>[];
    while (true) {
      final page = await Supabase.instance.client
          .from(table)
          .select()
          .range(from, from + pageSize - 1)
          .timeout(const Duration(seconds: 15));
      final mapped = List<Map<String, dynamic>>.from(page);
      rows.addAll(mapped.where((row) => !isSoftDeletedAppgtRow(row)));
      if (mapped.length < pageSize) break;
      from += pageSize;
    }
    return rows;
  }

  Future<void> _loadMatrixRows(
      {bool updateState = true, Set<String>? onlyTables}) async {
    final wantedRaw = (onlyTables ?? const <String>{})
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final wantedNorm = wantedRaw
        .map(_normalizarNombreCampo)
        .where((e) => e.isNotEmpty)
        .toSet();

    final grouped = <String, List<Map<String, dynamic>>>{};
    var localWantedRaw = wantedRaw;

    // Web y escritorio trabajan online-first: una respuesta remota vacía también
    // es autoritativa. La caché solo se usa si esa tabla no pudo consultarse.
    if (isOnlineFirstRuntime && wantedRaw.isNotEmpty) {
      final failed = <String>{};
      for (final table in wantedRaw) {
        try {
          grouped[table] = await _loadRemoteMatrixSource(table);
        } catch (_) {
          failed.add(table);
        }
      }
      localWantedRaw = failed;
    }

    // Si no se especifican tablas, conserva el comportamiento anterior.
    // Si se especifican, evita decodificar todo local_matrix_rows; esto era una
    // causa directa del congelamiento al abrir formularios Android.
    if (wantedNorm.isEmpty) {
      var cached = _cachedMatrixRowsByTable;
      if (cached == null) {
        final rows = await local.getAll('local_matrix_rows');
        cached = <String, List<Map<String, dynamic>>>{};
        var i = 0;
        for (final row in rows) {
          final table = row['source_table']?.toString() ?? '';
          final raw = row['payload_json']?.toString() ?? '{}';
          if (table.isEmpty) continue;
          try {
            final decoded = jsonDecode(raw) as Map<String, dynamic>;
            if (_isSoftDeletedMatrixRow(decoded)) continue;
            cached
                .putIfAbsent(table, () => <Map<String, dynamic>>[])
                .add(decoded);
          } catch (_) {}
          i++;
          if (i % 250 == 0) await Future<void>.delayed(Duration.zero);
        }
        _cachedMatrixRowsByTable = cached;
      }
      grouped.addAll(cached);
    } else if (localWantedRaw.isNotEmpty) {
      var decodedCount = 0;
      final foundNorm = <String>{};
      for (final rawTable in localWantedRaw) {
        final rows = await local
            .where('local_matrix_rows', 'source_table = ?', [rawTable]);
        for (final row in rows) {
          final table = row['source_table']?.toString() ?? rawTable;
          final raw = row['payload_json']?.toString() ?? '{}';
          try {
            final decoded = jsonDecode(raw) as Map<String, dynamic>;
            if (_isSoftDeletedMatrixRow(decoded)) continue;
            grouped
                .putIfAbsent(table, () => <Map<String, dynamic>>[])
                .add(decoded);
            foundNorm.add(_normalizarNombreCampo(table));
          } catch (_) {}
          decodedCount++;
          if (decodedCount % 250 == 0)
            await Future<void>.delayed(Duration.zero);
        }
      }

      // Respaldo por nombres normalizados solo para tablas que no matchearon exacto.
      final localWantedNorm =
          localWantedRaw.map(_normalizarNombreCampo).toSet();
      final missingNorm = localWantedNorm.difference(foundNorm);
      if (missingNorm.isNotEmpty) {
        final rows = await local.getAll('local_matrix_rows');
        for (final row in rows) {
          final table = row['source_table']?.toString() ?? '';
          if (!missingNorm.contains(_normalizarNombreCampo(table))) continue;
          final raw = row['payload_json']?.toString() ?? '{}';
          try {
            final decoded = jsonDecode(raw) as Map<String, dynamic>;
            if (_isSoftDeletedMatrixRow(decoded)) continue;
            grouped
                .putIfAbsent(table, () => <Map<String, dynamic>>[])
                .add(decoded);
          } catch (_) {}
          decodedCount++;
          if (decodedCount % 250 == 0)
            await Future<void>.delayed(Duration.zero);
        }
      }
    }
    if (!mounted) return;
    final merged = <String, List<Map<String, dynamic>>>{
      if (wantedNorm.isNotEmpty) ...matrixRowsByTable,
    };
    if (wantedNorm.isNotEmpty) {
      merged.removeWhere(
        (table, _) => wantedNorm.contains(_normalizarNombreCampo(table)),
      );
    }
    merged.addAll(grouped);
    if (updateState) {
      setState(() => matrixRowsByTable = merged);
    } else {
      matrixRowsByTable = merged;
    }
  }

  Future<void> _loadCatalogValues({bool updateState = true}) async {
    // No cachear catálogos en memoria: el botón Actualizar datos puede cambiar
    // id_campo_dropdown y valores fuente mientras la app sigue abierta.
    _cachedCatalogValues = null;
    final rows = await local.getAll('local_catalog_values',
        orderBy: 'catalog_key, value');
    final grouped = <String, List<String>>{};
    for (final row in rows) {
      final key = row['catalog_key']?.toString() ?? '';
      final value = row['value']?.toString().trim() ?? '';
      if (key.isEmpty || value.isEmpty) continue;
      grouped.putIfAbsent(key, () => <String>[]).add(value);
    }
    if (!mounted) return;
    if (updateState) {
      setState(() => catalogValues = grouped);
    } else {
      catalogValues = grouped;
    }
  }

  bool _fieldsNeedMatrixRows(List<Map<String, dynamic>> rows) {
    for (final f in rows) {
      final formula =
          (f['formula_funcion'] ?? f['formula'] ?? '').toString().toUpperCase();
      if (formula.contains('BUSCAR(') ||
          formula.contains('LOOKUP(') ||
          formula.contains('LOOKUPR(') ||
          formula.contains('LOOKUPP(') ||
          formula.contains('LISTA(') ||
          formula.contains('LIST(')) {
        return true;
      }
      final dropdown = (f['id_campo_dropdown'] ?? '').toString().trim();
      // Un dropdown dinámico puede venir como TABLA.COLUMNA, id, [id], CAMPO o [CAMPO].
      // Si el catálogo directo aún no existe, cargamos local_matrix_rows como respaldo.
      if (dropdown.isNotEmpty && !_isLiteralDropdownSource(dropdown)) {
        final sourceField =
            _fieldDefByIdentifier(_unwrapBracketReference(dropdown));
        final catalogKey = sourceField == null
            ? dropdown
            : _catalogKeyForSourceField(sourceField);
        if (!catalogValues.containsKey(catalogKey)) return true;
      }
    }
    return false;
  }

  Set<String> _matrixTablesNeeded(List<Map<String, dynamic>> rows) {
    final out = <String>{};
    for (final f in rows) {
      final formula = (f['formula_funcion'] ?? f['formula'] ?? '').toString();
      for (final m in RegExp(
              r'(?:BUSCAR|LOOKUP|LOOKUPR|LOOKUPP|LISTA|LIST)\s*\(\s*([^,;\)]+)',
              caseSensitive: false)
          .allMatches(formula)) {
        final table =
            (m.group(1) ?? '').trim().replaceAll('"', '').replaceAll("'", '');
        if (table.isNotEmpty) out.add(table);
      }
      final dropdown = (f['id_campo_dropdown'] ?? '').toString().trim();
      if (dropdown.isNotEmpty && !_isLiteralDropdownSource(dropdown)) {
        final cleanDropdown = _unwrapBracketReference(dropdown);
        if (cleanDropdown.contains('.')) {
          final table = cleanDropdown.split('.').first.trim();
          if (table.isNotEmpty) out.add(table);
        } else {
          final sourceField = _fieldDefByIdentifier(cleanDropdown);
          final table = sourceField?['tabla_destino']?.toString().trim() ?? '';
          if (table.isNotEmpty) out.add(table);
        }
      }
    }
    return out;
  }

  String _normalizarNombreCampo(String value) {
    var s = value.trim().toUpperCase();
    const acentos = {
      'Á': 'A',
      'É': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ú': 'U',
      'Ü': 'U',
      'Ñ': 'N',
    };
    acentos.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_');
    return s.replaceAll(RegExp(r'^_|_$'), '');
  }

  String _lookupKey(String table, String identifier) =>
      '${_normalizarNombreCampo(table)}|${_normalizarNombreCampo(identifier)}';

  void _rebuildFieldLookupCache(List<Map<String, dynamic>> rows, String table) {
    _fieldDefLookup.clear();
    _campoLookup.clear();
    for (final field in rows) {
      final campo = field['campo']?.toString().trim() ?? '';
      final etiqueta = field['etiqueta']?.toString().trim() ?? '';
      final id = field['id']?.toString().trim() ?? '';
      for (final raw in <String>[id, campo, etiqueta]) {
        final n = _normalizarNombreCampo(raw);
        if (n.isEmpty) continue;
        final key = _lookupKey(table, raw);
        _fieldDefLookup[key] = field;
        if (campo.isNotEmpty) _campoLookup[key] = campo;
      }
    }
  }

  Map<String, dynamic>? _fieldDefByIdentifier(String identifier,
      {String? table}) {
    final clean = identifier.trim();
    final wanted = _normalizarNombreCampo(clean);
    if (wanted.isEmpty) return null;

    final currentTable = table ?? tableDestino ?? '';
    final cached = _fieldDefLookup[_lookupKey(currentTable, clean)];
    if (cached != null) return cached;

    // Respaldo solo para catálogos o casos externos. En formularios normales manda cache.
    Map<String, dynamic>? fallback;
    for (final field in fieldDefsById.values) {
      final fieldTable = field['tabla_destino']?.toString() ?? '';
      final sameTable = currentTable.trim().isEmpty ||
          _normalizarNombreCampo(fieldTable) ==
              _normalizarNombreCampo(currentTable);
      final matches = [
        field['id'],
        field['campo'],
        field['etiqueta'],
      ].any(
          (value) => _normalizarNombreCampo(value?.toString() ?? '') == wanted);
      if (!matches) continue;
      if (sameTable) return field;
      fallback ??= field;
    }
    return fallback;
  }

  String _campoByIdentifier(String identifier, {String? table}) {
    final clean = identifier.trim();
    final currentTable = table ?? tableDestino ?? '';
    final cached = _campoLookup[_lookupKey(currentTable, clean)];
    if (cached != null && cached.isNotEmpty) return cached;
    final field = _fieldDefByIdentifier(clean, table: currentTable);
    return field?['campo']?.toString().trim() ?? clean;
  }

  bool _isTurnoOrLote(String campo, [String? etiqueta]) {
    final valores = {
      _normalizarNombreCampo(campo),
      if (etiqueta != null) _normalizarNombreCampo(etiqueta),
    };
    return valores.any(
        (c) => c == 'TURNO' || c == 'TURNOS' || c == 'LOTE' || c == 'LOTES');
  }

  bool _isVariedad(String campo, [String? etiqueta]) {
    final valores = {
      _normalizarNombreCampo(campo),
      if (etiqueta != null) _normalizarNombreCampo(etiqueta),
    };
    return valores.any((c) => c == 'VARIEDAD' || c == 'VARIEDADES');
  }

  List<String> _turnosUnicos() {
    final seen = <String>{};
    final out = <String>[];
    for (final row in lotesVariedades) {
      final turno = row['turno']?.toString().trim() ?? '';
      if (turno.isEmpty || seen.contains(turno)) continue;
      seen.add(turno);
      out.add(turno);
    }
    return out;
  }

  String _fieldKey(String table, String campo) =>
      '${_normalizarNombreCampo(table)}_${_normalizarNombreCampo(campo)}';

  static const Map<String, String> _dropdownCatalogByField = {
    'ALM_REGISTRO_CONTROL_GESTION_DE_ENVASES_A_NOMBRE_JEFATURA':
        'MATRIZ_JEFATURAS.JEFATURA',
    'RF_REGISTRO_CALIBRACION_PHMETRO_CODIGO':
        'MATRIZ_EQUIPOS_DE_MEDICION.CODIGO',
    'RF_REGISTRO_CALIBRACION_PHMETRO_C_DIGO':
        'MATRIZ_EQUIPOS_DE_MEDICION.CODIGO',
    'RF_REGISTRO_CALIBRACION_PHMETRO_ESTADO': 'MATRIZ_ESTADO_DE_EQUIPOS.ESTADO',
    'RF_REGISTRO_CALIBRACION_PHMETRO_FRECUENCIA':
        'MATRIZ_FRECUENCIA_DE_ACTIVIDADES.FRECUENCIA',
    'RF_REGISTRO_CALIBRACION_PHMETRO_JEFATURA': 'MATRIZ_JEFATURAS.JEFATURA',
    'RF_REGISTRO_CAUDALIMETROS_CASETA_SUPERVISOR':
        'MATRIZ_SUPERVISORES.SUPERVISOR',
    'RF_REGISTRO_CAUDALIMETROS_CASETA_JEFATURA': 'MATRIZ_JEFATURAS.JEFATURA',
    'RF_REGISTRO_HIDROMETROS_POZO_SUPERVISOR': 'MATRIZ_SUPERVISORES.SUPERVISOR',
    'RF_REGISTRO_HIDROMETROS_POZO_JEFATURA': 'MATRIZ_JEFATURAS.JEFATURA',
    'RF_REGISTRO_HIDROMETROS_USO_OPERACIONES_SUPERVISOR':
        'MATRIZ_SUPERVISORES.SUPERVISOR',
    'RF_REGISTRO_HIDROMETROS_USO_OPERACIONES_JEFATURA':
        'MATRIZ_JEFATURAS.JEFATURA',
    'RF_REGISTRO_LIMPIEZA_TANQUES_DEPOSITOS_AGU_JEFATURA':
        'MATRIZ_JEFATURAS.JEFATURA',
    'RF_REGISTRO_LIMPIEZA_TANQUES_RESERVORIOS_C_SUPERVISADO_POR':
        'MATRIZ_SUPERVISORES.SUPERVISOR',
    'RF_REGISTRO_LIMPIEZA_TANQUES_RESERVORIOS_C_JEFATURA':
        'MATRIZ_JEFATURAS.JEFATURA',
    'RF_REGISTRO_MMTO_CALIBRACION_AREARIEGO_RESPONSABLE_DE_LA_SUPERVISION':
        'MATRIZ_SUPERVISORES.SUPERVISOR',
    'RF_REGISTRO_MMTO_CALIBRACION_AREARIEGO_RESPONSABLE_DE_LA_SUPERVISI_N':
        'MATRIZ_SUPERVISORES.SUPERVISOR',
    'RF_REGISTRO_MMTO_CALIBRACION_AREARIEGO_JEFE_DE_OPERACIONES':
        'MATRIZ_JEFATURAS.JEFATURA',
  };

  static const Map<String, String> _multiCatalogByField = {
    'RF_REGISTRO_CALIBRACION_PHMETRO_MATERIALES':
        'MATRIZ_MATERIALES_CALIBRACION_EQUIPOS_DE_MEDICION.MATERIALES',
    'RF_REGISTRO_LIMPIEZA_TANQUES_DEPOSITOS_AGU_MATERIALES':
        'MATRIZ_MATERIALES_PARA_LIMPIEZA_AMBIENTES.MATERIALES',
  };

  String? _catalogForField(Map<String, dynamic> field, {required bool multi}) {
    final table = tableDestino ?? '';
    final campo = field['campo']?.toString() ?? '';
    final key = _fieldKey(table, campo);
    final source = multi ? _multiCatalogByField : _dropdownCatalogByField;
    return source[key];
  }

  List<String> _optionsForCatalog(String catalogKey) {
    final parts = catalogKey.split('.');
    if (parts.length < 2) {
      return catalogValues[catalogKey] ?? const <String>[];
    }
    final table = parts.first.trim();
    final column = parts.sublist(1).join('.').trim();
    final wantedTable = _normalizarNombreCampo(table);
    MapEntry<String, List<Map<String, dynamic>>>? source;
    for (final entry in matrixRowsByTable.entries) {
      if (_normalizarNombreCampo(entry.key) == wantedTable) {
        source = entry;
        break;
      }
    }
    final rows = source?.value ?? const <Map<String, dynamic>>[];
    final seen = <String>{};
    final out = <String>[];
    final wanted = _normalizarNombreCampo(column);
    for (final row in rows) {
      if (_isSoftDeletedMatrixRow(row)) continue;
      dynamic value = row[column];
      if (value == null) {
        for (final entry in row.entries) {
          if (_normalizarNombreCampo(entry.key) == wanted) {
            value = entry.value;
            break;
          }
        }
      }
      final text = value?.toString().trim() ?? '';
      if (text.isEmpty || text.toUpperCase() == 'NULL' || seen.contains(text))
        continue;
      seen.add(text);
      out.add(text);
    }
    out.sort();
    if (source != null && (isOnlineFirstRuntime || out.isNotEmpty)) return out;
    return catalogValues[catalogKey] ?? out;
  }

  void _recalculateDerivedFields() {
    final table = _normalizarNombreCampo(tableDestino ?? '');
    if (table == 'RF_REGISTRO_CAUDALIMETROS_CASETA') {
      final inicio = double.tryParse(
          (controllers['INICIO']?.text ?? '').replaceAll(',', '.'));
      final fin = double.tryParse(
          (controllers['FINAL']?.text ?? '').replaceAll(',', '.'));
      final target = controllers['M3 TOTALES'];
      if (inicio != null && fin != null && target != null) {
        final result = fin - inicio;
        target.text =
            result.toStringAsFixed(result.truncateToDouble() == result ? 0 : 2);
      }
    }

    if (table == 'RF_REGISTRO_DRENAJE_MACETA_CAMPO') {
      TextEditingController? fechaEvaluacion;
      TextEditingController? fechaRelativa;
      for (final entry in controllers.entries) {
        final name = _normalizarNombreCampo(entry.key);
        if (name == 'FECHA_DE_EVALUACION' || name == 'FECHA_EVALUACION')
          fechaEvaluacion = entry.value;
        if (name == 'FECHA_RELATIVA') fechaRelativa = entry.value;
      }
      if (fechaEvaluacion != null && fechaRelativa != null) {
        final parsed = DateTime.tryParse(fechaEvaluacion.text.trim());
        if (parsed != null) {
          fechaRelativa.text = parsed
              .subtract(const Duration(days: 1))
              .toIso8601String()
              .substring(0, 10);
        }
      }
    }
  }

  void _setVariedadFromTurno(String? turno) {
    if (turno == null || turno.trim().isEmpty) return;
    final t = turno.trim();
    final match = lotesVariedades
        .where((e) => e['turno']?.toString().trim() == t)
        .toList();
    if (match.isEmpty) return;
    final variedad = match.first['variedad']?.toString().trim() ?? '';
    for (final field in fields) {
      final campo = field['campo']?.toString() ?? '';
      final etiqueta = field['etiqueta']?.toString();
      if (_isVariedad(campo, etiqueta) && controllers.containsKey(campo)) {
        controllers[campo]!.text = variedad;
      }
    }
  }

  Future<List<Map<String, dynamic>>> _formFieldsForCandidateTablesFast(
      List<String> candidateTables) async {
    // Leer desde SQLite primero. La matriz puede haber sido reemplazada por
    // Actualizar datos mientras el proceso sigue vivo; usar el cache estático aquí
    // deja campos viejos en memoria.

    // Primera apertura Android: no decodificar/leer toda la matriz de campos.
    // Se consultan solo las tablas candidatas del formato actual; el cache global
    // se precalienta en segundo plano para las siguientes aperturas.
    for (final candidate in candidateTables) {
      final clean = candidate.trim();
      if (clean.isEmpty) continue;
      final rows = await local.where(
        'local_form_fields',
        'tabla_destino = ? and activo = 1',
        [clean],
        orderBy: 'orden',
      );
      if (rows.isNotEmpty) {
        final key = _normalizarNombreCampo(clean);
        _cachedFormFieldsByTable ??= <String, List<Map<String, dynamic>>>{};
        _cachedFormFieldsByTable![key] = rows;
        unawaited(_allFormFieldsCached());
        return rows;
      }
    }

    final wantedNames = candidateTables.map(_normalizarNombreCampo).toSet();
    final allRows = await _allFormFieldsCached();
    return allRows.where((row) {
      final activo = _asBool(row['activo'], defaultValue: true);
      final destino = row['tabla_destino']?.toString() ?? '';
      return activo && wantedNames.contains(_normalizarNombreCampo(destino));
    }).toList();
  }

  bool get _hasReactiveCalculations {
    if (_formulaFields.isNotEmpty) return true;
    final table = _normalizarNombreCampo(tableDestino ?? '');
    return table == 'RF_REGISTRO_CAUDALIMETROS_CASETA' ||
        table == 'RF_REGISTRO_DRENAJE_MACETA_CAMPO';
  }

  void _scheduleRecalculationIfNeeded() {
    if (!_hasReactiveCalculations) return;
    _scheduleFormulaRecalculation();
  }

  Future<void> loadFieldsForCurrentTable() async {
    final table = tableDestino;
    if (table == null || table.isEmpty) {
      if (!mounted) return;
      setState(() {
        fields = [];
        loadingFields = false;
      });
      return;
    }

    if (mounted) {
      setState(() => loadingFields = true);
    }

    final candidateTables = <String>[
      table,
      if (_cleanNullableText(widget.format['tabla_destino']) != null)
        _cleanNullableText(widget.format['tabla_destino'])!,
      ...internalTables
          .map((e) => _cleanNullableText(e['tabla_destino']))
          .whereType<String>(),
    ];

    final legacyRows = await _formFieldsForCandidateTablesFast(candidateTables);
    final rawRows = await DynamicRulesRepository().applyToFields(
      legacyRows,
      empresaId: await LocalSession().cachedEmpresaId(),
    );
    final rows = rawRows.where(_fieldBelongsToCurrentCapture).toList();

    if (_usesPersonnelLookup) {
      await _loadPersonnelWorkers();
    } else {
      personnelWorkers = <Map<String, dynamic>>[];
    }

    // CRÍTICO: id_campo_dropdown puede apuntar a un campo de OTRA tabla mediante
    // el id de MATRIZ_CAMPOS_FORMATO_APPGT. El formulario solo cargaba los campos
    // de la tabla actual y dejaba fieldDefsById vacío; por eso no podía resolver
    // referencias como [uuid] -> SN-PRODUCTOS_FITOSANITARIOS.NOMBRE.
    // Se fuerza la carga del índice global antes de calcular tablas fuente.
    await _loadFieldDefinitionsIndex(updateState: false);

    _rebuildFieldLookupCache(rows, table);

    final neededMatrixTables = _matrixTablesNeeded(rows);
    final missingMatrixTables = neededMatrixTables.where((table) {
      final wanted = _normalizarNombreCampo(table);
      return matrixRowsByTable.keys
          .every((cached) => _normalizarNombreCampo(cached) != wanted);
    }).toSet();
    if (isOnlineFirstRuntime && neededMatrixTables.isNotEmpty) {
      await _loadMatrixRows(
        updateState: false,
        onlyTables: neededMatrixTables,
      );
    } else if (_fieldsNeedMatrixRows(rows) &&
        (matrixRowsByTable.isEmpty || missingMatrixTables.isNotEmpty)) {
      await _loadMatrixRows(
        updateState: false,
        onlyTables: matrixRowsByTable.isEmpty
            ? neededMatrixTables
            : missingMatrixTables,
      );
    }

    for (final c in controllers.values) {
      c.dispose();
    }
    controllers.clear();
    dropdownValues.clear();
    multiSelectValues.clear();
    signatureValues.clear();
    photoValues.clear();
    documentFileNames.clear();

    final initial = widget.initialPayload ?? <String, dynamic>{};
    for (final f in rows) {
      final campo = f['campo']?.toString() ?? '';
      final tipo = _normalizeTipo(f['tipo']?.toString());
      final uiType = _uiType(f);
      if (campo.isEmpty) continue;
      final initialText = _initialValueForField(f, initial);
      final initialValue = initial[campo];
      if (tipo == 'boolean_int' ||
          uiType == 'boolean_int' ||
          uiType == 'checkbox' ||
          uiType == 'switch') {
        dropdownValues[campo] = initialValue == null
            ? (_isAttendanceBlockingField(f) ? 0 : null)
            : (_asBool(initialValue) ? 1 : 0);
      } else if (uiType == 'signature' || tipo == 'signature') {
        signatureValues[campo] = null;
      } else if (uiType == 'photo' || tipo == 'photo') {
        photoValues[campo] = null;
        controllers[campo] = TextEditingController(text: initialText);
      } else if (uiType == 'multiselect') {
        final raw = initialValue?.toString() ?? initialText;
        multiSelectValues[campo] = _parseMultiSelectText(raw);
        controllers[campo] = TextEditingController(text: raw);
        _syncMultiSelectController(campo);
      } else {
        controllers[campo] = TextEditingController(text: initialText);
      }
    }
    _selectedPersonnelDni = null;
    if (_usesPersonnelLookup) {
      for (final entry in controllers.entries) {
        final normalized = _normalizarNombreCampo(entry.key);
        if (normalized == 'DNI' || normalized == 'DOCUMENTO') {
          final initialDni = _onlyDigits(entry.value.text);
          if (initialDni.isNotEmpty) _selectedPersonnelDni = initialDni;
          break;
        }
      }
    }

    final restricted = await _loadRestrictedFieldsForCurrentUser();
    if (!mounted) return;
    restrictedFields = restricted;
    fields = rows;
    _clearCompensationDateWhenNotApplicable();
    _applyMasterDefaultsToDetail();
    _recalculateDerivedFields();
    _recalculateMatrixDrivenFields();
    loadingFields = false;
    setState(() {});
  }

  Map<String, dynamic>? get selectedInternalTable {
    final id = selectedInternalTableId;
    if (id == null) return null;
    for (final row in internalTables) {
      if (row['id']?.toString() == id) return row;
    }
    return null;
  }

  Map<String, dynamic>? _firstInternalTableWhere(
      bool Function(Map<String, dynamic>) test) {
    for (final row in internalTables) {
      if (test(row)) return row;
    }
    return null;
  }

  bool _isHeaderTableRow(Map<String, dynamic>? row) {
    if (row == null) return false;
    final mode = _normalizarNombreCampo(row['modo_captura']?.toString() ?? '');
    final relation =
        _normalizarNombreCampo(row['tipo_relacion']?.toString() ?? '');
    return _asBool(row['es_cabecera']) ||
        mode == 'CABECERA' ||
        relation == 'MAESTRO' ||
        relation == 'CABECERA';
  }

  bool _isDetailTableRow(Map<String, dynamic>? row) {
    if (row == null) return false;
    final mode = _normalizarNombreCampo(row['modo_captura']?.toString() ?? '');
    final relation =
        _normalizarNombreCampo(row['tipo_relacion']?.toString() ?? '');
    return _asBool(row['es_detalle']) ||
        mode == 'WIZARD_ITERADOR' ||
        relation == 'DETALLE';
  }

  Map<String, dynamic>? get _currentFormatTableConfig => selectedInternalTable;

  bool get _hasMasterDetailConfig {
    final hasHeader = internalTables.any(_isHeaderTableRow);
    final hasDetail = internalTables.any(_isDetailTableRow);
    return hasHeader && hasDetail;
  }

  bool _fieldBelongsToCurrentCapture(Map<String, dynamic> field) {
    final group =
        _normalizarNombreCampo(field['grupo_captura']?.toString() ?? '');
    if (group.isEmpty || group == 'NULL') return true;
    final current = _currentFormatTableConfig;
    if (_isHeaderTableRow(current))
      return group == 'CABECERA' || group == 'MAESTRO' || group == 'HEADER';
    if (_isDetailTableRow(current))
      return group == 'DETALLE' || group == 'MUESTRA' || group == 'DETAIL';
    return true;
  }

  dynamic _payloadValueByCampo(Map<String, dynamic> payload, String campo) {
    if (payload.containsKey(campo)) return payload[campo];
    final wanted = _normalizarNombreCampo(campo);
    for (final entry in payload.entries) {
      if (_normalizarNombreCampo(entry.key) == wanted) return entry.value;
    }
    return null;
  }

  Map<String, dynamic>? get _detailTableForCurrentHeader {
    final header = _currentFormatTableConfig;
    if (!_isHeaderTableRow(header)) return null;
    final headerTable = _cleanNullableText(header?['tabla_destino']);
    return _firstInternalTableWhere((row) {
      if (!_isDetailTableRow(row)) return false;
      final parent = _cleanNullableText(row['tabla_padre']);
      return parent == null ||
          headerTable == null ||
          _normalizarNombreCampo(parent) == _normalizarNombreCampo(headerTable);
    });
  }

  List<String> _copyFieldsFromParent(Map<String, dynamic>? detailRow) {
    final raw = detailRow?['copiar_campos_desde_padre']?.toString() ?? '';
    return raw
        .split(RegExp(r'[,;|]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  int? _intFromValue(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  bool _isAutoFilledDetailField(String campo) {
    final detail = _currentFormatTableConfig;
    if (!_isDetailTableRow(detail) || _wizardMasterPayload == null)
      return false;
    final normalized = _normalizarNombreCampo(campo);
    final fk = _cleanNullableText(detail?['campo_fk_hijo']);
    final iter = _cleanNullableText(detail?['campo_iterador']);
    if (fk != null && _normalizarNombreCampo(fk) == normalized) return true;
    if (iter != null && _normalizarNombreCampo(iter) == normalized) return true;
    return _copyFieldsFromParent(detail)
        .any((c) => _normalizarNombreCampo(c) == normalized);
  }

  void _applyMasterDefaultsToDetail() {
    final detail = _currentFormatTableConfig;
    final master = _wizardMasterPayload;
    if (!_isDetailTableRow(detail) || master == null) return;

    for (final campo in _copyFieldsFromParent(detail)) {
      final value = _payloadValueByCampo(master, campo);
      if (value != null && controllers.containsKey(campo)) {
        controllers[campo]!.text = value.toString();
      }
    }

    final iterField = _cleanNullableText(detail?['campo_iterador']);
    if (iterField != null && controllers.containsKey(iterField)) {
      final desde = _intFromValue(detail?['iterador_desde']) ?? 1;
      _wizardCurrentIteration ??= desde;
      controllers[iterField]!.text = _wizardCurrentIteration.toString();
    }

    final fk = _cleanNullableText(detail?['campo_fk_hijo']);
    if (fk != null &&
        controllers.containsKey(fk) &&
        (_wizardMasterIdLocal ?? '').isNotEmpty) {
      controllers[fk]!.text = _wizardMasterIdLocal!;
    }
  }

  void _clearDetailControllersForNextIteration(Map<String, dynamic> detail) {
    final autoFields = <String>{
      ..._copyFieldsFromParent(detail).map(_normalizarNombreCampo),
      if (_cleanNullableText(detail['campo_fk_hijo']) != null)
        _normalizarNombreCampo(_cleanNullableText(detail['campo_fk_hijo'])!),
      if (_cleanNullableText(detail['campo_iterador']) != null)
        _normalizarNombreCampo(_cleanNullableText(detail['campo_iterador'])!),
      'ID_LOCAL',
    };
    for (final entry in controllers.entries) {
      if (!autoFields.contains(_normalizarNombreCampo(entry.key)))
        entry.value.clear();
    }
    dropdownValues.clear();
    multiSelectValues.clear();
    signatureValues.clear();
    photoValues.clear();
    documentFileNames.clear();
    _applyMasterDefaultsToDetail();
  }

  String? _cleanNullableText(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty || s.toUpperCase() == 'NULL' || s.toUpperCase() == 'EMPTY')
      return null;
    return s;
  }

  String? get tableDestino {
    if (internalTables.isNotEmpty) {
      return _cleanNullableText(selectedInternalTable?['tabla_destino']);
    }
    return _cleanNullableText(widget.format['tabla_destino']);
  }

  String _normalizeTipo(String? raw) {
    final value = (raw ?? 'text').trim().toLowerCase();
    switch (value) {
      case 'hidden_id':
      case 'hidden':
        return value;
      case 'boolean_int':
      case 'boolean_01':
      case 'bool':
      case 'boolean':
        return 'boolean_int';
      case 'checkbox':
      case 'check':
        return 'checkbox';
      case 'switch':
      case 'toggle':
        return 'switch';
      case 'rating':
      case 'stars':
        return 'rating';
      case 'slider':
      case 'range':
        return 'slider';
      case 'email':
      case 'phone':
      case 'url':
      case 'percent':
        return value;
      case 'currency':
      case 'money':
      case 'number':
      case 'numeric':
      case 'double':
      case 'decimal':
      case 'float':
      case 'real':
        return 'number';
      case 'integer':
      case 'int':
        return 'integer';
      case 'multiline':
      case 'textarea':
        return 'multiline';
      case 'signature':
      case 'firma':
        return 'signature';
      case 'date':
      case 'datetime':
      case 'timestamp':
      case 'json':
      case 'jsonb':
      case 'dropdown':
      case 'multiselect':
      case 'time':
      case 'photo':
      case 'document':
      case 'documento':
      case 'file':
      case 'pdf':
      case 'calculated':
      case 'readonly':
      case 'formula':
      case 'lookup':
      case 'default':
      case 'text':
        return value;
      default:
        return 'text';
    }
  }

  bool _asBool(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    if (s.isEmpty || s == 'null') return defaultValue;
    return s == 'true' || s == '1' || s == 'si' || s == 'sí' || s == 'yes';
  }

  String _txt(dynamic value) => value?.toString().trim() ?? '';

  List<String> _jsonStringList(dynamic value) {
    if (value == null) return const <String>[];
    if (value is List)
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    final raw = value.toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List)
        return decoded
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
    } catch (_) {}
    var cleaned = raw;
    if (cleaned.startsWith('[') && cleaned.endsWith(']'))
      cleaned = cleaned.substring(1, cleaned.length - 1);
    return cleaned
        .split(RegExp(r'[,;|]'))
        .map((e) => e.trim())
        .map((e) {
          if ((e.startsWith('"') && e.endsWith('"')) ||
              (e.startsWith("'") && e.endsWith("'"))) {
            return e.substring(1, e.length - 1).trim();
          }
          return e;
        })
        .where((e) => e.isNotEmpty)
        .toList();
  }

  bool _sameLoose(dynamic a, dynamic b) =>
      _normalizarNombreCampo(_txt(a)) == _normalizarNombreCampo(_txt(b));

  Future<Set<String>> _loadRestrictedFieldsForCurrentUser() async {
    final userId = Supabase.instance.client.auth.currentUser?.id ??
        await LocalSession().cachedUserId();
    if (userId == null || userId.trim().isEmpty) return <String>{};
    final permissions =
        await local.where('local_permissions', 'user_id = ?', [userId.trim()]);
    final table = tableDestino ?? '';
    final values = <String>{};
    for (final p in permissions) {
      final moduleOk =
          _txt(p['modulo']).isEmpty || _sameLoose(p['modulo'], widget.moduleId);
      final formatOk = _txt(p['formato']).isEmpty ||
          _sameLoose(p['formato'], widget.format['id']);
      if (!moduleOk || !formatOk) continue;
      for (final c in _jsonStringList(p['campos_restringidos'])) {
        final campo = _campoByIdentifier(c, table: table);
        values.add(_normalizarNombreCampo(campo.isEmpty ? c : campo));
      }
    }
    return values;
  }

  bool _isRestrictedField(Map<String, dynamic> field) {
    final campo = field['campo']?.toString() ?? '';
    if (campo.isEmpty) return false;
    return restrictedFields.contains(_normalizarNombreCampo(campo));
  }

  String _uiType(Map<String, dynamic> field) {
    final ui = field['tipo_ui']?.toString().trim();
    if (ui != null && ui.isNotEmpty && ui.toLowerCase() != 'null') {
      return _normalizeTipo(ui);
    }
    return _normalizeTipo(field['tipo']?.toString());
  }

  bool _isEditable(Map<String, dynamic> field) =>
      _asBool(field['editable'], defaultValue: true);
  bool _isVisible(Map<String, dynamic> field) =>
      _asBool(field['visible'], defaultValue: true);

  FocusNode _focusNodeFor(String campo) {
    return focusNodes.putIfAbsent(
        campo, () => FocusNode(debugLabel: 'field_$campo'));
  }

  Color? _parseMatrixColor(dynamic value) {
    if (_isNullLike(value)) return null;
    var text = value.toString().trim().toLowerCase();
    if (text.isEmpty || text == 'null') return null;
    const names = <String, Color>{
      'rojo': Colors.red,
      'red': Colors.red,
      'verde': Colors.green,
      'green': Colors.green,
      'azul': Colors.blue,
      'blue': Colors.blue,
      'amarillo': Colors.yellow,
      'yellow': Colors.yellow,
      'negro': Colors.black,
      'black': Colors.black,
      'blanco': Colors.white,
      'white': Colors.white,
      'gris': Colors.grey,
      'gray': Colors.grey,
      'grey': Colors.grey,
      'naranja': Colors.orange,
      'orange': Colors.orange,
      'morado': Colors.purple,
      'purple': Colors.purple,
      'celeste': Colors.lightBlue,
      'transparente': Colors.transparent,
      'transparent': Colors.transparent,
    };
    if (names.containsKey(text)) return names[text];
    final rgb = RegExp(
            r'^rgba?\s*\(\s*(\d{1,3})\s*[,;]\s*(\d{1,3})\s*[,;]\s*(\d{1,3})(?:\s*[,;]\s*([0-9.]+))?\s*\)$')
        .firstMatch(text);
    if (rgb != null) {
      int clamp(String v) => (int.tryParse(v) ?? 0).clamp(0, 255).toInt();
      final alphaText = rgb.group(4);
      final alpha = alphaText == null
          ? 255
          : ((double.tryParse(alphaText) ?? 1).clamp(0, 1) * 255).round();
      return Color.fromARGB(alpha, clamp(rgb.group(1)!), clamp(rgb.group(2)!),
          clamp(rgb.group(3)!));
    }
    text = text.replaceAll('#', '').replaceAll('0x', '');
    if (RegExp(r'^[0-9a-f]{6}$', caseSensitive: false).hasMatch(text))
      return Color(int.parse('ff$text', radix: 16));
    if (RegExp(r'^[0-9a-f]{8}$', caseSensitive: false).hasMatch(text))
      return Color(int.parse(text, radix: 16));
    return null;
  }

  bool _conditionalFormatApplies(
    Map<String, dynamic> field, {
    dynamic conditionValue,
    bool emptyMeansApply = false,
  }) {
    final raw = conditionValue ??
        _fieldMetaValue(field, [
          'formato_condicional_campo',
          'formato condicional campo',
          'condicion_formato',
          'condición formato',
          'formato_condicional'
        ]);
    if (_isNullLike(raw)) return emptyMeansApply;
    var condition = raw.toString().trim();
    if (condition.isEmpty || condition.toUpperCase() == 'NULL') {
      return emptyMeansApply;
    }

    final campo = field['campo']?.toString().trim() ?? '';
    if (campo.isEmpty) return false;

    // Sintaxis corta en matriz: >0, >=10, =OK, <>0.
    // Se interpreta contra el valor del mismo campo de esa fila.
    if (RegExp(r'^(>=|<=|<>|!=|==|=|>|<)').hasMatch(condition)) {
      condition = '[$campo] $condition';
    }

    return _evalConditionalFormatCondition(condition.replaceAll('<>', '!='));
  }

  bool _evalConditionalFormatCondition(String condition) {
    var expr = condition.trim();
    if (expr.isEmpty) return false;

    final call = _readFormulaCall(expr);
    if (call != null && call.start == 0 && call.end == expr.length) {
      final name = _normalizeFormulaFunctionName(call.name);
      if ((name == 'IF' || name == 'SI') && call.args.length >= 3) {
        final selected = _evalConditionalFormatCondition(call.args[0])
            ? call.args[1]
            : call.args[2];
        final value = _evalLocalFormula(selected);
        if (value is bool) return value;
        final numValue = _tryFormulaDouble(value);
        if (numValue != null) return numValue != 0;
        final text = value?.toString().trim().toUpperCase() ?? '';
        return text == 'TRUE' ||
            text == 'VERDADERO' ||
            text == 'SI' ||
            text == 'SÍ';
      }
    }

    final orIndex = _indexOfTopLevelLogical(expr, ['||', ' OR ', ' O ']);
    if (orIndex != null) {
      return _evalConditionalFormatCondition(
              expr.substring(0, orIndex.start)) ||
          _evalConditionalFormatCondition(expr.substring(orIndex.end));
    }

    final andIndex = _indexOfTopLevelLogical(expr, ['&&', ' AND ', ' Y ']);
    if (andIndex != null) {
      return _evalConditionalFormatCondition(
              expr.substring(0, andIndex.start)) &&
          _evalConditionalFormatCondition(expr.substring(andIndex.end));
    }

    if (expr.startsWith('!'))
      return !_evalConditionalFormatCondition(expr.substring(1));
    if (expr.toUpperCase().startsWith('NOT '))
      return !_evalConditionalFormatCondition(expr.substring(4));
    if (expr.toUpperCase().startsWith('NO '))
      return !_evalConditionalFormatCondition(expr.substring(3));

    return _evalFormulaCondition(expr);
  }

  _LogicalIndex? _indexOfTopLevelLogical(String expr, List<String> tokens) {
    var inString = false;
    String? quote;
    var square = 0;
    var paren = 0;
    for (var i = 0; i < expr.length; i++) {
      final c = expr[i];
      if (c == "'" || c == '"') {
        if (!inString) {
          inString = true;
          quote = c;
        } else if (quote == c) {
          inString = false;
          quote = null;
        }
      }
      if (inString) continue;
      if (c == '[') square++;
      if (c == ']' && square > 0) square--;
      if (c == '(') paren++;
      if (c == ')' && paren > 0) paren--;
      if (square > 0 || paren > 0) continue;
      final tailUpper = expr.substring(i).toUpperCase();
      for (final token in tokens) {
        if (tailUpper.startsWith(token.toUpperCase())) {
          return _LogicalIndex(i, i + token.length);
        }
      }
    }
    return null;
  }

  double? _fieldFontSize(Map<String, dynamic> field) {
    final raw = _fieldMetaValue(field, [
      'tamanio_letra',
      'tamano_letra',
      'tamaño_letra',
      'font_size',
    ]);
    if (_isNullLike(raw)) return null;
    final value = double.tryParse(raw.toString().trim());
    if (value == null || value < 8 || value > 72) return null;
    return value;
  }

  Widget _styledFieldWidget(Map<String, dynamic> field) {
    final child = _fieldWidget(field);

    // No envolver/desenvolver el TextField según la condición. En Android eso puede
    // destruir y recrear el editor nativo mientras se escribe, provocando que el
    // cursor salte a otro campo. Si el campo tiene regla de formato, mantenemos
    // siempre la misma estructura visual y solo cambiamos colores.
    final legacyCondition = _fieldMetaValue(field, [
      'formato_condicional_campo',
      'formato condicional campo',
      'condicion_formato',
      'condición formato',
      'formato_condicional'
    ]);
    dynamic styleCondition(List<String> names) {
      final own = _fieldMetaValue(field, names);
      return _isNullLike(own) ? legacyCondition : own;
    }

    final textColor = _conditionalFormatApplies(
      field,
      conditionValue:
          styleCondition(['condicion_color_texto', 'condicion color texto']),
      emptyMeansApply: true,
    )
        ? _parseMatrixColor(_fieldMetaValue(
            field, ['color_texto', 'color texto', 'texto_color']))
        : null;
    final bgColor = _conditionalFormatApplies(
      field,
      conditionValue:
          styleCondition(['condicion_color_fondo', 'condicion color fondo']),
      emptyMeansApply: true,
    )
        ? _parseMatrixColor(_fieldMetaValue(
            field, ['color_fondo', 'color fondo', 'fondo_color']))
        : null;
    final borderColor = _conditionalFormatApplies(
      field,
      conditionValue:
          styleCondition(['condicion_color_borde', 'condicion color borde']),
      emptyMeansApply: true,
    )
        ? _parseMatrixColor(_fieldMetaValue(
            field, ['color_borde', 'color borde', 'borde_color']))
        : null;
    final fontSize = _fieldFontSize(field);

    if (textColor == null &&
        bgColor == null &&
        borderColor == null &&
        fontSize == null) {
      return child;
    }

    final baseTheme = Theme.of(context);
    final baseBodySize = baseTheme.textTheme.bodyMedium?.fontSize ?? 14;
    final fontSizeFactor =
        fontSize == null ? 1.0 : (fontSize / baseBodySize).clamp(0.5, 4.0);
    final effectiveBorderColor = borderColor ?? baseTheme.colorScheme.outline;
    final border = OutlineInputBorder(
        borderSide: BorderSide(
            color: effectiveBorderColor, width: borderColor == null ? 1 : 1.8));

    final themedChild = Theme(
      data: baseTheme.copyWith(
        textTheme: baseTheme.textTheme.apply(
          bodyColor: textColor,
          displayColor: textColor,
          fontSizeFactor: fontSizeFactor,
        ),
        inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
          filled:
              bgColor != null ? true : baseTheme.inputDecorationTheme.filled,
          fillColor: bgColor ?? baseTheme.inputDecorationTheme.fillColor,
          labelStyle:
              (baseTheme.inputDecorationTheme.labelStyle ?? const TextStyle())
                  .copyWith(color: textColor, fontSize: fontSize),
          floatingLabelStyle:
              (baseTheme.inputDecorationTheme.floatingLabelStyle ??
                      const TextStyle())
                  .copyWith(
                      color: textColor,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w700),
          helperStyle: textColor == null
              ? baseTheme.inputDecorationTheme.helperStyle
              : TextStyle(color: textColor.withOpacity(0.85)),
          enabledBorder: border,
          focusedBorder: border,
          disabledBorder: border,
        ),
        checkboxTheme: textColor == null
            ? baseTheme.checkboxTheme
            : baseTheme.checkboxTheme.copyWith(
                checkColor: MaterialStateProperty.all(
                    bgColor ?? baseTheme.colorScheme.surface),
                fillColor: MaterialStateProperty.resolveWith((states) =>
                    states.contains(MaterialState.selected) ? textColor : null),
              ),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: textColor, fontSize: fontSize),
        child: IconTheme.merge(
          data: IconThemeData(color: textColor),
          child: child,
        ),
      ),
    );

    // Refuerzo visual: algunos TextField/Dropdown definen su propia decoración
    // explícita y Flutter no siempre hereda fillColor/borde desde el Theme.
    // Este contenedor garantiza que la matriz pinte el campo sin tocar formula_funcion.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: borderColor == null
            ? null
            : Border.all(color: borderColor, width: 1.8),
      ),
      child: themedChild,
    );
  }

  Map<int, List<String>> _subtitleRows() {
    final out = <int, List<String>>{};
    final seen = <String>{};
    for (final field in fields) {
      final textRaw = _fieldMetaValue(
          field, ['sub_titulo', 'sub titulo', 'subtítulo', 'subtitulo']);
      final rowRaw = _fieldMetaValue(field, [
        'fila_sub_titulo',
        'fila sub titulo',
        'fila_subtitulo',
        'fila subtitulo'
      ]);
      if (_isNullLike(textRaw) || _isNullLike(rowRaw)) continue;
      final text = textRaw.toString().trim();
      final row = int.tryParse(rowRaw.toString().trim());
      if (text.isEmpty || row == null || row <= 0) continue;
      final key = '$row|$text';
      if (seen.add(key)) out.putIfAbsent(row, () => <String>[]).add(text);
    }
    return out;
  }

  EdgeInsets _matrixPadding(dynamic raw) {
    if (_isNullLike(raw)) {
      return const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    }
    final values = raw
        .toString()
        .split(RegExp(r'[,; ]+'))
        .where((value) => value.trim().isNotEmpty)
        .map((value) => double.tryParse(value.trim()) ?? 0)
        .toList(growable: false);
    if (values.length == 1) return EdgeInsets.all(values.first);
    if (values.length == 2) {
      return EdgeInsets.symmetric(
          horizontal: values.first, vertical: values[1]);
    }
    if (values.length >= 4) {
      return EdgeInsets.fromLTRB(values[0], values[1], values[2], values[3]);
    }
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
  }

  Alignment _matrixTextAlignment(dynamic raw) {
    final normalized = raw?.toString().trim().toLowerCase() ?? '';
    if (normalized == 'derecha' || normalized == 'right') {
      return Alignment.centerRight;
    }
    if (normalized == 'centro' ||
        normalized == 'center' ||
        normalized == 'centrado') {
      return Alignment.center;
    }
    return Alignment.centerLeft;
  }

  Widget _subtitleWidget(String text, [Map<String, dynamic>? field]) {
    final alignment = field == null
        ? Alignment.centerLeft
        : _matrixTextAlignment(_fieldMetaValue(field, [
            'subtitulo_alineacion',
            'subtitulo alineacion',
          ]));
    final fontSize = field == null
        ? null
        : double.tryParse(_fieldMetaValue(field, [
              'subtitulo_tamanio_letra',
              'subtitulo_tamano_letra',
            ])?.toString() ??
            '');
    final textColor = field == null
        ? null
        : _parseMatrixColor(
            _fieldMetaValue(field, ['subtitulo_color', 'subtitulo color']));
    final padding = field == null
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
        : _matrixPadding(
            _fieldMetaValue(field, ['subtitulo_padding', 'subtitulo padding']));
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding,
      alignment: alignment,
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withOpacity(0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: textColor,
              fontSize: fontSize)),
    );
  }

  Widget _fieldWithSubtitle(Map<String, dynamic> field) {
    final raw = _fieldMetaValue(
        field, ['sub_titulo', 'sub titulo', 'subtítulo', 'subtitulo']);
    final legacyRow = _fieldMetaValue(field, [
      'fila_sub_titulo',
      'fila sub titulo',
      'fila_subtitulo',
      'fila subtitulo'
    ]);
    final text = _isNullLike(raw) ? '' : raw.toString().trim();
    if (text.isEmpty || !_isNullLike(legacyRow)) {
      return _styledFieldWidget(field);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _subtitleWidget(text, field),
        _styledFieldWidget(field),
      ],
    );
  }

  int _photoLimitFromMatrix() {
    var total = 0;
    for (final field
        in _photoFieldsForCurrentTable(includeWithoutLimit: false)) {
      total += _photoSlotsForField(field);
    }
    return total;
  }

  bool _isPhotoFieldName(String campo) {
    // Compatibilidad auxiliar para ordenar/nombrar campos históricos.
    // IMPORTANTE: esto NO debe convertir un campo en foto por sí solo.
    // El tipo de foto debe venir desde MATRIZ_CAMPOS_FORMATO_APPGT: tipo_ui=photo o tipo=photo.
    final clean = campo.trim();
    return RegExp(r'^FOTO\s*\d+$', caseSensitive: false).hasMatch(clean) ||
        RegExp(r'^FOTO_?\d+$', caseSensitive: false).hasMatch(clean) ||
        RegExp(r'^PHOTO_?\d+$', caseSensitive: false).hasMatch(clean);
  }

  bool _isConfiguredPhotoField(Map<String, dynamic> field) {
    final tipo = _normalizeTipo(field['tipo']?.toString());
    final uiType = _uiType(field);
    return tipo == 'photo' || uiType == 'photo';
  }

  int _photoFieldOrder(String campo) {
    final match = RegExp(r'(?:FOTO|PHOTO)[^0-9]*([0-9]+)', caseSensitive: false)
        .firstMatch(campo.trim());
    return int.tryParse(match?.group(1) ?? '') ?? 999999;
  }

  int _photoSlotsForField(Map<String, dynamic> field) {
    final campo = field['campo']?.toString() ?? '';
    if (_isPhotoFieldName(campo)) return 1;
    final raw = field['numero_fotos'];
    final value = int.tryParse(raw?.toString().trim() ?? '') ?? 0;
    return value <= 0 ? 1 : value;
  }

  String _photoGroupName(Map<String, dynamic> field) {
    final configured = field['lista_destino_photo']?.toString().trim() ?? '';
    if (configured.isNotEmpty && configured.toLowerCase() != 'null')
      return configured;
    final etiqueta = field['etiqueta']?.toString().trim() ?? '';
    if (etiqueta.isNotEmpty && etiqueta.toLowerCase() != 'null')
      return etiqueta;
    return field['campo']?.toString().trim() ?? 'Foto';
  }

  int _photoListOrder(Map<String, dynamic> field) {
    final raw = field['orden_lista_photo'] ??
        field['orden lista photo'] ??
        field['ordenListaPhoto'];
    final parsed = int.tryParse(raw?.toString().trim() ?? '');
    if (parsed != null) return parsed;
    final orden = int.tryParse(field['orden']?.toString().trim() ?? '');
    if (orden != null && orden > 0) return orden;
    return _photoFieldOrder(field['campo']?.toString() ?? '');
  }

  List<Map<String, dynamic>> _photoFieldsForCurrentTable(
      {bool includeWithoutLimit = true}) {
    final hasNumberedPhotoColumns = fields.any((field) =>
        _isConfiguredPhotoField(field) &&
        _isPhotoFieldName(field['campo']?.toString() ?? ''));
    final list = fields.where((field) {
      final campo = field['campo']?.toString() ?? '';
      final tipo = _normalizeTipo(field['tipo']?.toString());
      final uiType = _uiType(field);
      final nFotos =
          int.tryParse(field['numero_fotos']?.toString().trim() ?? '') ?? 0;
      final isPhoto =
          campo.isNotEmpty && (tipo == 'photo' || uiType == 'photo');
      if (!isPhoto) return false;
      if (hasNumberedPhotoColumns && nFotos > 0 && !_isPhotoFieldName(campo)) {
        return false;
      }
      return includeWithoutLimit ||
          nFotos > 0 ||
          uiType == 'photo' ||
          tipo == 'photo';
    }).toList();
    list.sort((a, b) {
      final oa = _photoListOrder(a);
      final ob = _photoListOrder(b);
      final o = oa.compareTo(ob);
      if (o != 0) return o;
      final ga = _photoGroupName(a).toUpperCase();
      final gb = _photoGroupName(b).toUpperCase();
      final g = ga.compareTo(gb);
      if (g != 0) return g;
      return _photoFieldOrder(a['campo']?.toString() ?? '')
          .compareTo(_photoFieldOrder(b['campo']?.toString() ?? ''));
    });
    return list;
  }

  Map<String, List<Map<String, dynamic>>> _photoGroupsForCurrentTable() {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final field in _photoFieldsForCurrentTable()) {
      final name = _photoGroupName(field);
      groups.putIfAbsent(name, () => <Map<String, dynamic>>[]).add(field);
    }
    final entries = groups.entries.toList()
      ..sort((a, b) {
        final oa = a.value
            .map(_photoListOrder)
            .fold<int>(999999, (prev, v) => v < prev ? v : prev);
        final ob = b.value
            .map(_photoListOrder)
            .fold<int>(999999, (prev, v) => v < prev ? v : prev);
        final o = oa.compareTo(ob);
        if (o != 0) return o;
        return a.key.toUpperCase().compareTo(b.key.toUpperCase());
      });
    return {for (final e in entries) e.key: e.value};
  }

  String _imageDataUrl(Uint8List bytes, {String mimeType = 'image/jpeg'}) {
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  Uint8List? _photoBytesFromController(String campo) {
    final raw = controllers[campo]?.text.trim() ?? '';
    if (raw.isEmpty || !raw.startsWith('data:image/')) return null;
    try {
      final commaIndex = raw.indexOf(',');
      final encoded = commaIndex >= 0 ? raw.substring(commaIndex + 1) : raw;
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }

  bool _hasPhotoInField(String campo) {
    final raw = controllers[campo]?.text.trim() ?? '';
    return photoValues[campo] != null || raw.isNotEmpty;
  }

  int _capturedPhotoCount() {
    return _photoFieldsForCurrentTable().where((f) {
      final campo = f['campo']?.toString() ?? '';
      return _hasPhotoInField(campo);
    }).length;
  }

  List<String> _parseBracketFieldList(String raw) {
    final out = <String>[];
    final text = raw.trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return out;
    for (final m in RegExp(r'\[([^\]]+)\]').allMatches(text)) {
      final token = m.group(1)?.trim() ?? '';
      if (token.isNotEmpty) out.add(token);
    }
    if (out.isNotEmpty) return out;
    for (final part in text.split(',')) {
      final token = part.replaceAll('[', '').replaceAll(']', '').trim();
      if (token.isNotEmpty) out.add(token);
    }
    return out;
  }

  String _fieldLabelByIdentifier(String identifier) {
    final field = _fieldDefByIdentifier(identifier, table: tableDestino);
    return field?['etiqueta']?.toString().trim().isNotEmpty == true
        ? field!['etiqueta'].toString().trim()
        : _campoByIdentifier(identifier, table: tableDestino);
  }

  bool _truthyFormulaResult(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim();
    if (text.isEmpty) return false;
    final upper = text.toUpperCase();
    if (upper == '0' ||
        upper == 'FALSE' ||
        upper == 'FALSO' ||
        upper == 'NO' ||
        upper == 'NULL') return false;
    return true;
  }

  String? _photoBlockedMessage(Map<String, dynamic> field) {
    // Fuente de verdad para bloquear foto:
    // 1) Si formula_funcion tiene valor, se evalúa como condición booleana.
    //    Ejemplo válido: [INICIO] != ''
    //    También válido: SI([INICIO] != '', TRUE, FALSE)
    // 2) Si formula_funcion está vacío, NO se bloquea la cámara.
    // photo_depende_de solo ayuda a construir el mensaje y a mantener el orden/grupo
    // de las fotos; no debe bloquear por sí solo.
    final formula = field['formula_funcion']?.toString().trim() ?? '';
    if (formula.isEmpty || formula.toLowerCase() == 'null') return null;

    final deps =
        _parseBracketFieldList(field['photo_depende_de']?.toString() ?? '');
    final labels = deps
        .map(_fieldLabelByIdentifier)
        .where((e) => e.trim().isNotEmpty)
        .toList();

    try {
      final ok = _evalFormulaCondition(formula);
      if (!ok) {
        if (deps.isNotEmpty) {
          final missing = <String>[];
          for (final dep in deps) {
            final value = _valueByFormulaIdentifier(dep);
            if (value == null || value.toString().trim().isEmpty) {
              missing.add(_fieldLabelByIdentifier(dep));
            }
          }
          if (missing.isNotEmpty)
            return 'Completa los campos: ${missing.join(', ')}';
        }
        return labels.isEmpty
            ? 'No se cumple la condición para tomar esta foto.'
            : 'Completa los campos: ${labels.join(', ')}';
      }
    } catch (_) {
      return labels.isEmpty
          ? 'No se pudo validar la condición de la foto.'
          : 'Completa los campos: ${labels.join(', ')}';
    }
    return null;
  }

  Future<void> _showPhotoBlockedMessage(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Falta completar información'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext, rootNavigator: true).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _capturePhotoForField(String campo) async {
    if (campo.trim().isEmpty || capturingPhoto || savingLocal) return;
    Map<String, dynamic>? field;
    for (final f in fields) {
      if ((f['campo']?.toString() ?? '') == campo) {
        field = f;
        break;
      }
    }
    if (field != null) {
      final blocked = _photoBlockedMessage(field);
      if (blocked != null) {
        await _showPhotoBlockedMessage(blocked);
        return;
      }
    }
    FocusScope.of(context).unfocus();
    setState(() => capturingPhoto = true);
    try {
      final file = await _imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 55,
          maxWidth: 1024,
          maxHeight: 1024);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        photoValues[campo] = bytes;
        controllers.putIfAbsent(campo, () => TextEditingController());
        controllers[campo]!.text = _imageDataUrl(bytes);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir la cámara: $e')));
    } finally {
      if (mounted) setState(() => capturingPhoto = false);
    }
  }

  Future<void> _captureNextPhotoInGroup(
      List<Map<String, dynamic>> photoFields) async {
    if (photoFields.isEmpty) return;
    final targetField = photoFields.firstWhere(
      (f) => !_hasPhotoInField(f['campo']?.toString() ?? ''),
      orElse: () => photoFields.first,
    );
    await _capturePhotoForField(targetField['campo']?.toString() ?? '');
  }

  Widget _photoTile(Map<String, dynamic> field, VoidCallback refreshSheet) {
    final campo = field['campo']?.toString() ?? '';
    final etiqueta = field['etiqueta']?.toString().trim().isNotEmpty == true
        ? field['etiqueta'].toString().trim()
        : campo;
    final bytes = photoValues[campo] ?? _photoBytesFromController(campo);
    final raw = controllers[campo]?.text.trim() ?? '';
    final hasRemoteImage = bytes == null &&
        (raw.startsWith('http') || EvidenceStorage.isStorageUri(raw));
    return SizedBox(
      width: 112,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              await _capturePhotoForField(campo);
              if (mounted) refreshSheet();
            },
            child: Container(
              width: 112,
              height: 78,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(8),
              ),
              child: bytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(bytes, fit: BoxFit.cover))
                  : hasRemoteImage
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: FutureBuilder<String>(
                            future: EvidenceStorage.signedUrlForValue(raw),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData)
                                return const Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2));
                              return Image.network(snapshot.data!,
                                  fit: BoxFit.cover);
                            },
                          ),
                        )
                      : const Icon(Icons.photo_outlined),
            ),
          ),
          const SizedBox(height: 4),
          Text(etiqueta,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11)),
          if (_hasPhotoInField(campo))
            TextButton(
              onPressed: () {
                setState(() {
                  photoValues[campo] = null;
                  controllers[campo]?.clear();
                });
                refreshSheet();
              },
              child: const Text('Quitar', style: TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }

  void _openPhotoGroupSheet(
      String groupName, List<Map<String, dynamic>> photoFields) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (sheetContext, sheetSetState) {
            final completed = photoFields
                .where((f) => _hasPhotoInField(f['campo']?.toString() ?? ''))
                .length;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(groupName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('Fotos capturadas ($completed/${photoFields.length})'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: photoFields
                          .map((field) =>
                              _photoTile(field, () => sheetSetState(() {})))
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              await _captureNextPhotoInGroup(photoFields);
                              if (mounted) sheetSetState(() {});
                            },
                            icon: const Icon(Icons.photo_camera),
                            label: const Text('Capturar otra'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Cancelar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openCapturedPhotosSheet() {
    final groups = _photoGroupsForCurrentTable();
    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Configura campos con tipo_ui=photo en la matriz de campos.')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (sheetContext, sheetSetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Fotos capturadas (${_capturedPhotoCount()}/${_photoLimitFromMatrix()})',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    ...groups.entries.map((entry) {
                      final completed = entry.value
                          .where((f) =>
                              _hasPhotoInField(f['campo']?.toString() ?? ''))
                          .length;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: const BorderSide(color: Colors.black12)),
                          leading: Icon(completed >= entry.value.length
                              ? Icons.check_circle
                              : Icons.photo_camera),
                          title: Text(entry.key),
                          subtitle:
                              Text('$completed/${entry.value.length} foto(s)'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _openPhotoGroupSheet(entry.key, entry.value);
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool _hasNumeroDecimales(Map<String, dynamic> field) {
    final raw = field['numero_decimales'];
    if (raw == null) return false;
    final text = raw.toString().trim();
    if (text.isEmpty || text.toUpperCase() == 'NULL') return false;
    return int.tryParse(text) != null;
  }

  int _numeroDecimales(Map<String, dynamic> field) {
    final raw = field['numero_decimales'];
    if (raw == null) return 0;
    final text = raw.toString().trim();
    if (text.isEmpty || text.toUpperCase() == 'NULL') return 0;
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 0) return 0;
    return parsed;
  }

  bool _isNullLike(dynamic value) {
    if (value == null) return true;
    final text = value.toString().trim();
    return text.isEmpty || text.toUpperCase() == 'NULL';
  }

  bool _isNumberField(Map<String, dynamic> field) {
    final tipo = _normalizeTipo(field['tipo']?.toString());
    final uiType = _uiType(field);
    return tipo == 'number' ||
        tipo == 'numeric' ||
        tipo == 'decimal' ||
        tipo == 'double' ||
        tipo == 'integer' ||
        uiType == 'number' ||
        uiType == 'numeric' ||
        uiType == 'decimal' ||
        uiType == 'double' ||
        uiType == 'integer';
  }

  bool _allowsDecimal(Map<String, dynamic> field) {
    final tipo = _normalizeTipo(field['tipo']?.toString());
    if (tipo == 'integer' || _uiType(field) == 'integer') return false;
    return _numeroDecimales(field) > 0;
  }

  dynamic _fieldMetaValue(Map<String, dynamic> field, List<String> keys) {
    for (final key in keys) {
      if (field.containsKey(key) && !_isNullLike(field[key])) return field[key];
    }
    final normalizedKeys = keys.map(_normalizarNombreCampo).toSet();
    for (final entry in field.entries) {
      if (normalizedKeys.contains(_normalizarNombreCampo(entry.key)) &&
          !_isNullLike(entry.value)) {
        return entry.value;
      }
    }
    return null;
  }

  int? _maxCharacters(Map<String, dynamic> field) {
    final raw = _fieldMetaValue(field, [
      'num_caracteres',
      'num caracteres',
      'max_caracteres',
      'max caracteres'
    ]);
    if (_isNullLike(raw)) return null;
    final parsed = int.tryParse(raw.toString().trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  List<TextInputFormatter> _inputFormattersForField(
      Map<String, dynamic> field) {
    final formatters = <TextInputFormatter>[];
    final maxChars = _maxCharacters(field);

    if (_isNumberField(field)) {
      final decimals = _numeroDecimales(field);
      final decimal = _allowsDecimal(field);
      formatters.add(TextInputFormatter.withFunction((oldValue, newValue) {
        final text = newValue.text;
        if (text.isEmpty || text == '-') return newValue;
        final pattern = decimal
            ? RegExp(r'^-?\d*([.,]\d{0,' + decimals.toString() + r'})?$')
            : RegExp(r'^-?\d*$');
        return pattern.hasMatch(text) ? newValue : oldValue;
      }));
    }

    if (maxChars != null) {
      formatters.add(LengthLimitingTextInputFormatter(maxChars));
    }

    return formatters;
  }

  DateTime _safeDatePickerInitialDate(
      DateTime value, DateTime minDate, DateTime maxDate) {
    final date = DateTime(value.year, value.month, value.day);
    if (date.isBefore(minDate)) return minDate;
    if (date.isAfter(maxDate)) return maxDate;
    return date;
  }

  String? _rangeErrorForField(Map<String, dynamic> field, String rawValue) {
    final tipo =
        _fieldMetaValue(field, ['tipo'])?.toString().trim().toLowerCase() ?? '';
    final uiType = _fieldMetaValue(field, ['tipo_ui', 'tipo ui'])
            ?.toString()
            .trim()
            .toLowerCase() ??
        '';
    if (tipo == 'date' ||
        uiType == 'date' ||
        tipo == 'fecha' ||
        uiType == 'fecha') return null;

    final ruleRaw = _fieldMetaValue(
        field, ['rango_valor', 'rango valor', 'rango', 'validacion_rango']);
    if (_isNullLike(ruleRaw) || rawValue.trim().isEmpty) return null;

    final ruleOriginal = ruleRaw.toString().trim();
    final rule = ruleOriginal.replaceAll(',', '.');
    final value = double.tryParse(rawValue.trim().replaceAll(',', '.'));
    if (value == null) return 'Debe ser un número válido';

    double? parseNum(String text) =>
        double.tryParse(text.trim().replaceAll(',', '.'));

    // Formatos de rango inclusivo admitidos:
    // 10<>20, 10..20, 10:20, [10,20], [10;20], entre 10 y 20
    final betweenPatterns = <RegExp>[
      RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*<>\s*(-?\d+(?:\.\d+)?)\s*$'),
      RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*\.\.\s*(-?\d+(?:\.\d+)?)\s*$'),
      RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*:\s*(-?\d+(?:\.\d+)?)\s*$'),
      RegExp(r'^\s*\[\s*(-?\d+(?:\.\d+)?)\s*[;]\s*(-?\d+(?:\.\d+)?)\s*\]\s*$'),
      RegExp(r'^\s*ENTRE\s+(-?\d+(?:\.\d+)?)\s+Y\s+(-?\d+(?:\.\d+)?)\s*$',
          caseSensitive: false),
    ];

    for (final pattern in betweenPatterns) {
      final match = pattern.firstMatch(rule);
      if (match == null) continue;
      final min = parseNum(match.group(1)!);
      final max = parseNum(match.group(2)!);
      if (min == null || max == null) return null;
      final lo = math.min(min, max);
      final hi = math.max(min, max);
      if (value < lo || value > hi)
        return 'Debe estar entre ${_compactNumberText(lo)} y ${_compactNumberText(hi)}';
      return null;
    }

    // Caso [10,20] necesita leerse antes de reemplazar coma decimal. Se evalúa sobre el texto original.
    final bracketComma = RegExp(
            r'^\s*\[\s*(-?\d+(?:[\.,]\d+)?)\s*,\s*(-?\d+(?:[\.,]\d+)?)\s*\]\s*$')
        .firstMatch(ruleOriginal);
    if (bracketComma != null) {
      final min = parseNum(bracketComma.group(1)!);
      final max = parseNum(bracketComma.group(2)!);
      if (min != null && max != null) {
        final lo = math.min(min, max);
        final hi = math.max(min, max);
        if (value < lo || value > hi)
          return 'Debe estar entre ${_compactNumberText(lo)} y ${_compactNumberText(hi)}';
        return null;
      }
    }

    final cmp = RegExp(r'^\s*(>=|<=|!=|=|>|<)\s*(-?\d+(?:\.\d+)?)\s*$')
        .firstMatch(rule);
    if (cmp != null) {
      final op = cmp.group(1)!;
      final ref = double.parse(cmp.group(2)!);
      var ok = true;
      switch (op) {
        case '>=':
          ok = value >= ref;
          break;
        case '<=':
          ok = value <= ref;
          break;
        case '>':
          ok = value > ref;
          break;
        case '<':
          ok = value < ref;
          break;
        case '=':
          ok = value == ref;
          break;
        case '!=':
          ok = value != ref;
          break;
      }
      return ok ? null : 'Debe cumplir: $ruleOriginal';
    }

    // Lista exacta de valores permitidos: 0|1|2 o IN(0;1;2)
    final inText = ruleOriginal.toUpperCase().startsWith('IN(') &&
            ruleOriginal.endsWith(')')
        ? ruleOriginal.substring(3, ruleOriginal.length - 1)
        : ruleOriginal;
    if (inText.contains('|') || ruleOriginal.toUpperCase().startsWith('IN(')) {
      final allowed = inText
          .split(RegExp(r'[|;]'))
          .map(parseNum)
          .whereType<double>()
          .toList();
      if (allowed.isNotEmpty && !allowed.contains(value)) {
        return 'Debe ser uno de estos valores: ${allowed.map(_compactNumberText).join(', ')}';
      }
    }

    return null;
  }

  String _compactNumberText(double number) {
    if (number.isNaN || number.isInfinite) return '';
    if (number.truncateToDouble() == number) return number.toStringAsFixed(0);
    return number
        .toStringAsFixed(8)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _formatNumberText(dynamic value, Map<String, dynamic> field) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '';
    final number = double.tryParse(raw.replaceAll(',', '.'));
    if (number == null) return raw;
    // numero_decimales NULL se interpreta como 0 decimales para campos numéricos.
    return number.toStringAsFixed(_numeroDecimales(field));
  }

  String _formatFormulaResultForField(
      dynamic value, Map<String, dynamic> field) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '';
    final tipo = _normalizeTipo(field['tipo']?.toString());
    final uiType = _uiType(field);

    // Una fórmula puede devolver texto, hora o fecha. No debe forzarse a número
    // solo porque tipo_ui sea formula. Ejemplo: HORA_ACTUAL() en campos time.
    if (tipo == 'time' || uiType == 'time') {
      // Para campos time calculados, un vacío nunca debe convertirse en 0.
      // Si el motor numérico anterior dejó 0/0.0, se limpia para evitar sync inválido.
      if (raw == '0' || raw == '0.0') return '';
      return raw;
    }
    if (tipo == 'date' || uiType == 'date') return raw;
    if (tipo == 'datetime' ||
        tipo == 'timestamp' ||
        uiType == 'datetime' ||
        uiType == 'timestamp') return raw;
    if (tipo == 'percent' ||
        uiType == 'percent' ||
        tipo == 'number' ||
        uiType == 'number' ||
        tipo == 'integer' ||
        uiType == 'integer' ||
        tipo == 'numeric' ||
        uiType == 'numeric') {
      return _formatNumberText(raw, field);
    }
    return raw;
  }

  String _catalogKeyForSourceField(Map<String, dynamic> sourceField) {
    final sourceTable = sourceField['tabla_destino']?.toString() ?? '';
    final sourceColumn = sourceField['campo']?.toString() ?? '';
    return '$sourceTable.$sourceColumn';
  }

  String _unwrapBracketReference(String value) {
    final text = value.trim();
    if (text.startsWith('[') && text.endsWith(']') && text.length >= 2) {
      return text.substring(1, text.length - 1).trim();
    }
    return text;
  }

  bool _isLiteralDropdownSource(String value) {
    final text = value.trim();
    if (!text.startsWith('[') || !text.endsWith(']')) return false;

    // [a,b,c] o [a;b;c] es una lista manual.
    // [uuid-del-campo] / [CAMPO] / [Etiqueta] debe funcionar como referencia dinámica.
    final content = _unwrapBracketReference(text);
    return content.contains(',') ||
        content.contains(';') ||
        content.contains('|');
  }

  List<String>? _literalDropdownOptions(Map<String, dynamic> field) {
    final raw = field['id_campo_dropdown']?.toString().trim() ?? '';
    if (raw.isEmpty || raw.toUpperCase() == 'NULL') return null;
    if (!_isLiteralDropdownSource(raw)) return null;

    final content = raw.substring(1, raw.length - 1).trim();
    if (content.isEmpty) return <String>[];

    final seen = <String>{};
    final options = <String>[];
    for (final item in content.split(RegExp(r'[,;]'))) {
      final value = item.trim();
      if (value.isEmpty || seen.contains(value)) continue;
      seen.add(value);
      options.add(value);
    }
    return options;
  }

  String? _dynamicDropdownCatalog(Map<String, dynamic> field) {
    final dropdownRaw = field['id_campo_dropdown']?.toString().trim() ?? '';
    if (dropdownRaw.isEmpty || dropdownRaw.toUpperCase() == 'NULL') return null;
    if (_isLiteralDropdownSource(dropdownRaw)) return null;
    final dropdownId = _unwrapBracketReference(dropdownRaw);
    if (dropdownId.contains('.')) return dropdownId;

    // id_campo_dropdown ahora acepta cualquiera de estas referencias:
    // 1) id técnico del campo de la matriz
    // 2) nombre real de columna/campo
    // 3) etiqueta visible
    // Esto evita depender solo del id exacto y permite parametrizar dropdowns
    // usando el mismo criterio que las fórmulas.
    final sourceField = _fieldDefByIdentifier(dropdownId);
    if (sourceField == null) return null;
    return _catalogKeyForSourceField(sourceField);
  }

  String _initialValueForField(
      Map<String, dynamic> field, Map<String, dynamic> initial) {
    final campo = field['campo']?.toString() ?? '';
    final tipo = _normalizeTipo(field['tipo']?.toString());
    final uiType = _uiType(field);
    dynamic existing = initial[campo];
    if (existing == null) {
      final candidates = <String>[
        campo,
        field['etiqueta']?.toString() ?? '',
        field['id']?.toString() ?? '',
      ].where((e) => e.trim().isNotEmpty).map(_normalizarNombreCampo).toSet();
      for (final entry in initial.entries) {
        if (candidates.contains(_normalizarNombreCampo(entry.key.toString()))) {
          existing = entry.value;
          break;
        }
      }
    }
    if (existing != null) {
      if (tipo == 'number' || uiType == 'number')
        return _formatNumberText(existing, field);
      return existing.toString();
    }

    final defaultValue = field['valor_default']?.toString().trim() ?? '';
    if (defaultValue.isNotEmpty && defaultValue.toUpperCase() != 'NULL') {
      if (tipo == 'number' ||
          tipo == 'numeric' ||
          tipo == 'integer' ||
          uiType == 'number' ||
          uiType == 'numeric' ||
          uiType == 'integer') {
        return _formatNumberText(defaultValue, field);
      }
      return defaultValue;
    }

    if (tipo == 'date' || uiType == 'date') {
      return DateTime.now().toIso8601String().substring(0, 10);
    }
    return '';
  }

  String? _campoById(String id) =>
      _fieldDefByIdentifier(id)?['campo']?.toString();

  String _valueTextByFieldId(String id) {
    final campo = _campoByIdentifier(id);
    if (controllers.containsKey(campo))
      return controllers[campo]?.text.trim() ?? '';
    if (dropdownValues.containsKey(campo))
      return dropdownValues[campo]?.toString() ?? '';
    if (multiSelectValues.containsKey(campo))
      return (multiSelectValues[campo] ?? <String>{}).join(', ');
    return '';
  }

  dynamic _valueByColumnName(Map<String, dynamic> row, String column) {
    final wanted = _normalizarNombreCampo(column);
    for (final entry in row.entries) {
      if (_normalizarNombreCampo(entry.key) == wanted) return entry.value;
    }
    return null;
  }

  bool _isSoftDeletedMatrixRow(Map<String, dynamic> row) {
    return isSoftDeletedAppgtRow(row);
  }

  String _runLookupFormula(String formula) {
    final match = RegExp(r'^\s*LOOKU[PR]\s*\((.*)\)\s*$', caseSensitive: false)
        .firstMatch(formula);
    if (match == null) return '';
    final args =
        match.group(1)!.split(RegExp(r'[,;]')).map((e) => e.trim()).toList();
    if (args.length < 4) return '';
    final sourceTable = args[0];
    final searchColumn = _campoByIdentifier(args[1], table: sourceTable);
    final searchToken = args[2];
    final returnColumn = _campoByIdentifier(args[3], table: sourceTable);
    final idMatch = RegExp(r'\{\{([^}]+)\}\}').firstMatch(searchToken);
    final searchValue = idMatch == null
        ? searchToken
        : _valueTextByFieldId(idMatch.group(1)!.trim());
    if (searchValue.trim().isEmpty) return '';

    List<Map<String, dynamic>> rows =
        matrixRowsByTable[sourceTable] ?? const <Map<String, dynamic>>[];
    if (rows.isEmpty) {
      final wanted = _normalizarNombreCampo(sourceTable);
      for (final entry in matrixRowsByTable.entries) {
        if (_normalizarNombreCampo(entry.key) == wanted) {
          rows = entry.value;
          break;
        }
      }
    }
    for (final row in rows) {
      if (_isSoftDeletedMatrixRow(row)) continue;
      final candidate =
          _valueByColumnName(row, searchColumn)?.toString().trim() ?? '';
      if (candidate == searchValue.trim()) {
        return _valueByColumnName(row, returnColumn)?.toString().trim() ?? '';
      }
    }
    return '';
  }

  int _isoWeek(DateTime date) {
    final thursday = date.add(Duration(days: 3 - ((date.weekday + 6) % 7)));
    final firstThursday = DateTime(thursday.year, 1, 4);
    return 1 +
        thursday
                .difference(firstThursday
                    .add(Duration(days: 3 - ((firstThursday.weekday + 6) % 7))))
                .inDays ~/
            7;
  }

  String _runFormula(String formula) {
    final text = formula.trim();
    if (text.isEmpty) return '';

    // Evaluador local estricto para fórmulas de campos del formulario.
    // Motivo: el motor anterior podía resolver restas simples, pero devolvía vacío
    // para multiplicaciones directas como "200 * 100" o "0.20 * NUM([CAMPO])".
    // Este evaluador usa directamente los controladores locales actuales y protege
    // referencias entre corchetes antes de evaluar operadores matemáticos.
    try {
      final direct = _evalLocalFormula(text);
      if (direct != null) return _formulaValueToText(direct);
    } catch (_) {
      // Si esta rama falla, no se rompe el formulario: se usa el motor general.
    }

    final engine = FormulaEngine(
      fields: fields,
      matrixRowsByTable: matrixRowsByTable,
      getValue: (campo) {
        final key = campo.toString().trim();
        final resolvedCampo = _campoByIdentifier(key);
        for (final candidate in [resolvedCampo, key]) {
          if (controllers.containsKey(candidate))
            return controllers[candidate]?.text.trim() ?? '';
          if (dropdownValues.containsKey(candidate))
            return dropdownValues[candidate];
          if (multiSelectValues.containsKey(candidate))
            return (multiSelectValues[candidate] ?? <String>{}).join(', ');
        }
        return _valueTextByFieldId(key);
      },
    );
    return engine.evaluateToText(formula);
  }

  String _formulaValueToText(dynamic value) {
    if (value == null) return '';
    if (value is num) {
      final v = value.toDouble();
      if (v.isNaN || v.isInfinite) return '';
      if (v.truncateToDouble() == v) return v.toStringAsFixed(0);
      return v
          .toStringAsFixed(10)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    return value.toString();
  }

  dynamic _evalLocalFormula(String expression) {
    final expr = expression.trim();
    if (expr.isEmpty) return '';
    if (_isQuotedFormulaText(expr)) return _unquoteFormulaText(expr);
    final upperLiteral = expr.toUpperCase();
    if (upperLiteral == 'TRUE' || upperLiteral == 'VERDADERO') return true;
    if (upperLiteral == 'FALSE' || upperLiteral == 'FALSO') return false;
    if (_isNumericFormulaLiteral(expr)) return _toFormulaDouble(expr);
    if (_isFormulaFieldRef(expr))
      return _valueByFormulaIdentifier(expr.substring(1, expr.length - 1));

    final call = _readFormulaCall(expr);
    if (call != null && call.start == 0 && call.end == expr.length) {
      final name = _normalizeFormulaFunctionName(call.name);
      if (name == 'IF' || name == 'SI') {
        if (call.args.length < 3) return '';
        return _evalFormulaCondition(call.args[0])
            ? _evalLocalFormula(call.args[1])
            : _evalLocalFormula(call.args[2]);
      }
      if (name == 'ES_VACIO' || name == 'VACIO') {
        if (call.args.isEmpty) return true;
        return (_evalLocalFormula(call.args.first)?.toString().trim() ?? '')
            .isEmpty;
      }
      if (name == 'NO_ES_VACIO' || name == 'NOVACIO') {
        if (call.args.isEmpty) return false;
        return (_evalLocalFormula(call.args.first)?.toString().trim() ?? '')
            .isNotEmpty;
      }
      if (name == 'CONTIENE' || name == 'CONTAINS') {
        if (call.args.length < 2) return false;
        final text =
            _evalLocalFormula(call.args[0])?.toString().toUpperCase() ?? '';
        final needle =
            _evalLocalFormula(call.args[1])?.toString().toUpperCase() ?? '';
        return text.contains(needle);
      }
      if (name == 'RESTA') {
        final values = call.args.map((a) => _evalLocalFormula(a)).toList();
        if (values.length >= 2) {
          final firstDate = _tryParseLocalFormulaDate(values[0]);
          final secondDate = _tryParseLocalFormulaDate(values[1]);
          if (firstDate != null && secondDate != null) {
            return _dateOnlyLocal(firstDate)
                .difference(_dateOnlyLocal(secondDate))
                .inDays;
          }
        }
        if (values.isEmpty) return 0.0;
        return values.skip(1).fold<double>(
            _toFormulaDouble(values.first), (a, b) => a - _toFormulaDouble(b));
      }
      if (name == 'RESTA_TIEMPOS') {
        if (call.args.length < 2) return '';
        final start = _formulaTimeMinutes(_evalLocalFormula(call.args[0]),
            fallbackToken: call.args[0]);
        final end = _formulaTimeMinutes(_evalLocalFormula(call.args[1]),
            fallbackToken: call.args[1]);
        if (start == null || end == null) return '';
        var diff = end - start;
        if (diff < 0) diff += 24 * 60;
        return _formatFormulaDuration(diff);
      }
      if (name == 'FECHAS_TRANSCURRIDAS') {
        if (call.args.length < 2) return '';
        final startDate =
            _tryParseLocalFormulaDate(_evalLocalFormula(call.args[0]));
        final endDate =
            _tryParseLocalFormulaDate(_evalLocalFormula(call.args[1]));
        if (startDate == null || endDate == null) return '';
        return _dateOnlyLocal(endDate)
            .difference(_dateOnlyLocal(startDate))
            .inDays;
      }
      if (name == 'SUMAR_DIAS') {
        if (call.args.length < 2) return '';
        final baseDate =
            _tryParseLocalFormulaDate(_evalLocalFormula(call.args[0]));
        if (baseDate == null) return '';
        final days = _toFormulaDouble(_evalLocalFormula(call.args[1])).round();
        return _formatLocalFormulaDate(
            _dateOnlyLocal(baseDate).add(Duration(days: days)));
      }
      if (name == 'HORA_ACTUAL' || name == 'AHORA_HORA') {
        return _formatLocalFormulaTime(DateTime.now());
      }
      if (name == 'FECHA_ACTUAL' || name == 'HOY') {
        return _formatLocalFormulaDate(DateTime.now());
      }
      if (name == 'FECHA_HORA_ACTUAL' ||
          name == 'FECHAHORA_ACTUAL' ||
          name == 'AHORA') {
        return _formatLocalFormulaDateTime(DateTime.now());
      }
      if (name == 'NUM' || name == 'NUMERO' || name == 'VALOR') {
        if (call.args.isEmpty) return 0.0;
        return _toFormulaDouble(_evalLocalFormula(call.args.first));
      }
      if (name == 'ROUND' || name == 'REDONDEAR') {
        if (call.args.isEmpty) return 0.0;
        final value = _toFormulaDouble(_evalLocalFormula(call.args[0]));
        final decimals = call.args.length > 1
            ? _toFormulaDouble(_evalLocalFormula(call.args[1])).round()
            : 0;
        return double.parse(value.toStringAsFixed(decimals));
      }
      if (name == 'ABS' || name == 'ABSOLUTO') {
        if (call.args.isEmpty) return 0.0;
        return _toFormulaDouble(_evalLocalFormula(call.args.first)).abs();
      }
      if (name == 'INT' || name == 'ENTERO') {
        if (call.args.isEmpty) return 0.0;
        return _toFormulaDouble(_evalLocalFormula(call.args.first))
            .floorToDouble();
      }
      if (name == 'BUSCAR' ||
          name == 'LOOKUP' ||
          name == 'LOOKUPR' ||
          name == 'LOOKUPP' ||
          name == 'LISTA') {
        return null; // usa FormulaEngine, que ya maneja BUSCAR con matrices externas.
      }
      return null;
    }

    if (_looksLikeLocalMath(expr)) {
      final replaced = _replaceLocalFormulaRefsAndNums(expr);
      final parsed = _StrictMathParser(replaced).parse();
      if (parsed.isNaN || parsed.isInfinite) return null;
      return parsed;
    }

    return null;
  }

  bool _evalFormulaCondition(String condition) {
    const ops = ['>=', '<=', '==', '!=', '=', '>', '<'];
    for (final op in ops) {
      final idx = _indexOfFormulaOperator(condition, op);
      if (idx < 0) continue;
      final left = _evalLocalFormula(condition.substring(0, idx));
      final right = _evalLocalFormula(condition.substring(idx + op.length));
      final leftNum = _tryFormulaDouble(left);
      final rightNum = _tryFormulaDouble(right);
      if (leftNum != null && rightNum != null) {
        switch (op) {
          case '>':
            return leftNum > rightNum;
          case '<':
            return leftNum < rightNum;
          case '>=':
            return leftNum >= rightNum;
          case '<=':
            return leftNum <= rightNum;
          case '==':
          case '=':
            return leftNum == rightNum;
          case '!=':
            return leftNum != rightNum;
        }
      }
      final a = _normalizarNombreCampo(left?.toString() ?? '');
      final b = _normalizarNombreCampo(right?.toString() ?? '');
      switch (op) {
        case '==':
        case '=':
          return a == b;
        case '!=':
          return a != b;
        case '>':
          return a.compareTo(b) > 0;
        case '<':
          return a.compareTo(b) < 0;
        case '>=':
          return a.compareTo(b) >= 0;
        case '<=':
          return a.compareTo(b) <= 0;
      }
    }
    final value = _evalLocalFormula(condition);
    if (value is bool) return value;
    final asNum = _tryFormulaDouble(value);
    if (asNum != null) return asNum != 0;
    return value?.toString().trim().isNotEmpty == true;
  }

  String _replaceLocalFormulaRefsAndNums(String expr) {
    var out = expr;
    while (true) {
      final call = _findFirstLocalFormulaCall(out);
      if (call == null) break;
      final name = _normalizeFormulaFunctionName(call.name);
      if (name == 'BUSCAR' ||
          name == 'LOOKUP' ||
          name == 'LOOKUPR' ||
          name == 'LOOKUPP' ||
          name == 'LISTA') {
        return out;
      }
      final value = _evalLocalFormula(out.substring(call.start, call.end));
      final numeric = _tryFormulaDouble(value);
      if (numeric == null) return out;
      out = out.substring(0, call.start) +
          numeric.toString() +
          out.substring(call.end);
    }
    out = out.replaceAllMapped(RegExp(r'\[([^\]]+)\]'), (m) {
      return _toFormulaDouble(_valueByFormulaIdentifier(m.group(1) ?? ''))
          .toString();
    });
    out = out.replaceAllMapped(RegExp(r'\{\{([^}]+)\}\}'), (m) {
      return _toFormulaDouble(_valueByFormulaIdentifier(m.group(1) ?? ''))
          .toString();
    });
    return out;
  }

  dynamic _valueByFormulaIdentifier(String identifier) {
    final key = identifier.trim();
    final currentTable = tableDestino;
    final campo = _campoByIdentifier(key, table: currentTable);
    final candidates = <String>{campo, key};
    final def = _fieldDefByIdentifier(key, table: currentTable);
    final etiqueta = def?['etiqueta']?.toString().trim() ?? '';
    if (etiqueta.isNotEmpty) candidates.add(etiqueta);
    for (final candidate in candidates) {
      if (controllers.containsKey(candidate))
        return controllers[candidate]?.text.trim() ?? '';
      if (dropdownValues.containsKey(candidate))
        return dropdownValues[candidate]?.toString() ?? '';
      if (multiSelectValues.containsKey(candidate))
        return (multiSelectValues[candidate] ?? <String>{}).join(', ');
    }
    return _valueTextByFieldId(key);
  }

  bool _isFormulaFieldRef(String expr) =>
      expr.startsWith('[') && expr.endsWith(']') && expr.indexOf('[', 1) == -1;

  bool _isQuotedFormulaText(String expr) {
    return expr.length >= 2 &&
        ((expr.startsWith("'") && expr.endsWith("'")) ||
            (expr.startsWith('"') && expr.endsWith('"')));
  }

  String _unquoteFormulaText(String expr) => expr.substring(1, expr.length - 1);

  bool _isNumericFormulaLiteral(String expr) {
    return RegExp(r'^-?\d+(?:[\.,]\d+)?$').hasMatch(expr.trim());
  }

  double _toFormulaDouble(dynamic value) => _tryFormulaDouble(value) ?? 0.0;

  double? _tryFormulaDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    var text = value.toString().trim();
    if (text.isEmpty || text.toUpperCase() == 'NULL') return null;
    text = text.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^-?\d{1,3}(,\d{3})+(\.\d+)?$').hasMatch(text)) {
      text = text.replaceAll(',', '');
    } else {
      text = text.replaceAll(',', '.');
    }
    return double.tryParse(text);
  }

  DateTime? _tryParseLocalFormulaDate(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toUpperCase() == 'NULL') return null;
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(text);
    if (iso != null) {
      return DateTime.tryParse(
          '${iso.group(1)!}-${iso.group(2)!.padLeft(2, '0')}-${iso.group(3)!.padLeft(2, '0')}');
    }
    final slash =
        RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(text);
    if (slash != null) {
      final d = int.tryParse(slash.group(1)!);
      final m = int.tryParse(slash.group(2)!);
      final y = int.tryParse(slash.group(3)!);
      if (d == null || m == null || y == null) return null;
      final dt = DateTime(y, m, d);
      return dt.year == y && dt.month == m && dt.day == d ? dt : null;
    }
    return DateTime.tryParse(text);
  }

  DateTime _dateOnlyLocal(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  String _formatLocalFormulaDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatLocalFormulaTime(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatLocalFormulaDateTime(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    final s = date.second.toString().padLeft(2, '0');
    return '${_formatLocalFormulaDate(date)} $h:$m:$s';
  }

  bool _looksLikeLocalMath(String expr) {
    var inString = false;
    String? quote;
    var square = 0;
    for (var i = 0; i < expr.length; i++) {
      final c = expr[i];
      if (c == "'" || c == '"') {
        if (!inString) {
          inString = true;
          quote = c;
        } else if (quote == c) {
          inString = false;
          quote = null;
        }
        continue;
      }
      if (inString) continue;
      if (c == '[') {
        square++;
        continue;
      }
      if (c == ']' && square > 0) {
        square--;
        continue;
      }
      if (square > 0) continue;
      if ('*/+'.contains(c)) return true;
      if (c == '-') {
        final prev = i > 0 ? expr[i - 1] : '';
        if (i > 0 &&
            prev.trim().isNotEmpty &&
            prev != '(' &&
            prev != ';' &&
            prev != ',') return true;
      }
    }
    return _findFirstLocalFormulaCall(expr) != null;
  }

  int? _formulaTimeMinutes(dynamic value, {String? fallbackToken}) {
    final candidates = <String>[
      value?.toString() ?? '',
      if (fallbackToken != null) fallbackToken,
    ];
    for (var text in candidates) {
      text = text.trim();
      if (text.isEmpty || text.toUpperCase() == 'NULL') continue;
      if ((text.startsWith('[') && text.endsWith(']')) ||
          (text.startsWith('{{') && text.endsWith('}}'))) {
        text = text.startsWith('{{')
            ? text.substring(2, text.length - 2)
            : text.substring(1, text.length - 1);
      }
      text = text.trim();
      final match =
          RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$', caseSensitive: false)
              .firstMatch(text);
      if (match == null) continue;
      final h = int.tryParse(match.group(1)!);
      final m = int.tryParse(match.group(2)!);
      if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59)
        continue;
      return h * 60 + m;
    }
    return null;
  }

  String _formatFormulaDuration(int totalMinutes) {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (minutes == 0) return hours == 1 ? '1 hora' : '$hours horas';
    if (hours == 0) return minutes == 1 ? '1 minuto' : '$minutes minutos';
    final hText = hours == 1 ? '1 hora' : '$hours horas';
    final mText = minutes == 1 ? '1 minuto' : '$minutes minutos';
    return '$hText $mText';
  }

  String _normalizeFormulaFunctionName(String raw) {
    final s = _normalizarNombreCampo(raw).replaceAll('_', '');
    switch (s) {
      case 'SI':
        return 'SI';
      case 'IF':
        return 'IF';
      case 'ESVACIO':
        return 'ES_VACIO';
      case 'ES_VACIO':
        return 'ES_VACIO';
      case 'VACIO':
        return 'VACIO';
      case 'NOESVACIO':
        return 'NO_ES_VACIO';
      case 'NO_ES_VACIO':
        return 'NO_ES_VACIO';
      case 'NOVACIO':
        return 'NOVACIO';
      case 'CONTIENE':
        return 'CONTIENE';
      case 'CONTAINS':
        return 'CONTAINS';
      case 'NUMERO':
        return 'NUMERO';
      case 'VALOR':
        return 'VALOR';
      case 'REDONDEAR':
        return 'REDONDEAR';
      case 'ABSOLUTO':
        return 'ABSOLUTO';
      case 'ENTERO':
        return 'ENTERO';
      case 'BUSCAR':
        return 'BUSCAR';
      case 'LISTA':
      case 'LIST':
        return 'LISTA';
      case 'RESTA':
        return 'RESTA';
      case 'RESTATIEMPO':
        return 'RESTA_TIEMPOS';
      case 'RESTATIEMPOS':
        return 'RESTA_TIEMPOS';
      case 'RESTA_TIEMPO':
        return 'RESTA_TIEMPOS';
      case 'RESTA_TIEMPOS':
        return 'RESTA_TIEMPOS';
      case 'FECHASTRANSCURRIDAS':
        return 'FECHAS_TRANSCURRIDAS';
      case 'DIAS_TRANSCURRIDOS':
        return 'FECHAS_TRANSCURRIDAS';
      case 'DIASTRANSCURRIDOS':
        return 'FECHAS_TRANSCURRIDAS';
      case 'SUMARDIAS':
        return 'SUMAR_DIAS';
      case 'SUMAR_DIAS':
        return 'SUMAR_DIAS';
      case 'HORAACTUAL':
        return 'HORA_ACTUAL';
      case 'HORA_ACTUAL':
        return 'HORA_ACTUAL';
      case 'AHORAHORA':
        return 'AHORA_HORA';
      case 'AHORA_HORA':
        return 'AHORA_HORA';
      case 'FECHAACTUAL':
        return 'FECHA_ACTUAL';
      case 'FECHA_ACTUAL':
        return 'FECHA_ACTUAL';
      case 'FECHAHORAACTUAL':
        return 'FECHA_HORA_ACTUAL';
      case 'FECHAHORA_ACTUAL':
        return 'FECHA_HORA_ACTUAL';
      case 'FECHA_HORA_ACTUAL':
        return 'FECHA_HORA_ACTUAL';
      case 'CONCAT':
        return 'CONCAT';
      case 'CONCATENAR':
        return 'CONCATENAR';
      case 'CONTATENAR':
        return 'CONCATENAR';
      case 'EXTRAER':
        return 'EXTRAER';
      case 'MID':
        return 'EXTRAER';
      default:
        return s;
    }
  }

  _LocalFormulaCall? _readFormulaCall(String expr) {
    final match =
        RegExp(r'^\s*([A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9_.]+)\s*\(').firstMatch(expr);
    if (match == null) return null;
    final open = expr.indexOf('(', match.end - 1);
    final close = _findFormulaClosingParen(expr, open);
    if (close < 0) return null;
    return _LocalFormulaCall(
      name: match.group(1) ?? '',
      args: _splitFormulaArgs(expr.substring(open + 1, close)),
      start: match.start,
      end: close + 1,
    );
  }

  _LocalFormulaCall? _findFirstLocalFormulaCall(String expr) {
    var inString = false;
    String? quote;
    var square = 0;
    for (var i = 0; i < expr.length; i++) {
      final c = expr[i];
      if (c == "'" || c == '"') {
        if (!inString) {
          inString = true;
          quote = c;
        } else if (quote == c) {
          inString = false;
          quote = null;
        }
        continue;
      }
      if (inString) continue;
      if (c == '[') {
        square++;
        continue;
      }
      if (c == ']' && square > 0) {
        square--;
        continue;
      }
      if (square > 0 || c != '(') continue;
      var j = i - 1;
      while (j >= 0 && RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9_.]').hasMatch(expr[j]))
        j--;
      final name = expr.substring(j + 1, i).trim();
      if (name.isEmpty) continue;
      final close = _findFormulaClosingParen(expr, i);
      if (close < 0) continue;
      return _LocalFormulaCall(
          name: name,
          args: _splitFormulaArgs(expr.substring(i + 1, close)),
          start: j + 1,
          end: close + 1);
    }
    return null;
  }

  int _findFormulaClosingParen(String expr, int openIndex) {
    var level = 0;
    var inString = false;
    String? quote;
    var square = 0;
    for (var i = openIndex; i < expr.length; i++) {
      final c = expr[i];
      if (c == "'" || c == '"') {
        if (!inString) {
          inString = true;
          quote = c;
        } else if (quote == c) {
          inString = false;
          quote = null;
        }
        continue;
      }
      if (inString) continue;
      if (c == '[') {
        square++;
        continue;
      }
      if (c == ']' && square > 0) {
        square--;
        continue;
      }
      if (square > 0) continue;
      if (c == '(') level++;
      if (c == ')') {
        level--;
        if (level == 0) return i;
      }
    }
    return -1;
  }

  List<String> _splitFormulaArgs(String raw) {
    final args = <String>[];
    var level = 0;
    var square = 0;
    var inString = false;
    String? quote;
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final c = raw[i];
      if (c == "'" || c == '"') {
        if (!inString) {
          inString = true;
          quote = c;
        } else if (quote == c) {
          inString = false;
          quote = null;
        }
      }
      if (!inString) {
        if (c == '[') square++;
        if (c == ']' && square > 0) square--;
        if (square == 0) {
          if (c == '(') level++;
          if (c == ')') level--;
          if ((c == ';' || c == ',') && level == 0) {
            args.add(buffer.toString().trim());
            buffer.clear();
            continue;
          }
        }
      }
      buffer.write(c);
    }
    final last = buffer.toString().trim();
    if (last.isNotEmpty) args.add(last);
    return args;
  }

  int _indexOfFormulaOperator(String text, String op) {
    var level = 0;
    var square = 0;
    var inString = false;
    String? quote;
    for (var i = 0; i <= text.length - op.length; i++) {
      final c = text[i];
      if (c == "'" || c == '"') {
        if (!inString) {
          inString = true;
          quote = c;
        } else if (quote == c) {
          inString = false;
          quote = null;
        }
      }
      if (inString) continue;
      if (c == '[') square++;
      if (c == ']' && square > 0) square--;
      if (square > 0) continue;
      if (c == '(') level++;
      if (c == ')' && level > 0) level--;
      if (level == 0 && text.substring(i).startsWith(op)) return i;
    }
    return -1;
  }

  bool _isListFormulaField(Map<String, dynamic> field) {
    final kind = field['formula_tipo']?.toString().trim().toUpperCase() ?? '';
    final formula =
        field['formula_funcion']?.toString().trim().toUpperCase() ?? '';
    return kind == 'LISTA' ||
        formula.startsWith('LISTA(') ||
        formula.startsWith('LIST(');
  }

  String _formulaListToken(dynamic raw) {
    final text = raw?.toString().trim() ?? '';
    if (_isQuotedFormulaText(text)) return _unquoteFormulaText(text);
    return text;
  }

  List<String> _formulaListOptions(Map<String, dynamic> field) {
    var sourceTable = field['formula_tabla_origen']?.toString().trim() ?? '';
    var valueField = field['formula_campo_valor']?.toString().trim() ?? '';
    var filterField = field['formula_campo_condicion']?.toString().trim() ?? '';
    var filterValue = field['formula_valor_condicion']?.toString().trim() ?? '';
    final formula = field['formula_funcion']?.toString().trim() ?? '';
    final call = _readFormulaCall(formula);
    if (call != null && call.args.length >= 2) {
      if (sourceTable.isEmpty) sourceTable = _formulaListToken(call.args[0]);
      if (valueField.isEmpty) valueField = _formulaListToken(call.args[1]);
      if (filterField.isEmpty && call.args.length >= 3) {
        filterField = _formulaListToken(call.args[2]);
      }
      if (filterValue.isEmpty && call.args.length >= 4) {
        filterValue = call.args[3].trim();
      }
    }
    if (sourceTable.isEmpty || valueField.isEmpty) {
      return const <String>[];
    }

    List<Map<String, dynamic>> rows =
        matrixRowsByTable[sourceTable] ?? const <Map<String, dynamic>>[];
    if (rows.isEmpty) {
      final wanted = _normalizarNombreCampo(sourceTable);
      for (final entry in matrixRowsByTable.entries) {
        if (_normalizarNombreCampo(entry.key) == wanted) {
          rows = entry.value;
          break;
        }
      }
    }

    dynamic expected;
    if (filterValue.startsWith('[') && filterValue.endsWith(']')) {
      expected = _valueByFormulaIdentifier(
          filterValue.substring(1, filterValue.length - 1));
    } else {
      final reference = RegExp(r'^\{\{([^}]+)\}\}$').firstMatch(filterValue);
      expected = reference == null
          ? _formulaListToken(filterValue)
          : _valueTextByFieldId(reference.group(1)!.trim());
    }
    final expectedText = expected?.toString().trim() ?? '';
    final actualValueField = _campoByIdentifier(valueField, table: sourceTable);
    final actualFilterField = filterField.isEmpty
        ? ''
        : _campoByIdentifier(filterField, table: sourceTable);
    final seen = <String>{};
    final options = <String>[];
    for (final row in rows) {
      if (_isSoftDeletedMatrixRow(row)) continue;
      if (actualFilterField.isNotEmpty) {
        final candidate =
            _valueByColumnName(row, actualFilterField)?.toString().trim() ?? '';
        if (candidate.toUpperCase() != expectedText.toUpperCase()) continue;
      }
      final value =
          _valueByColumnName(row, actualValueField)?.toString().trim() ?? '';
      if (value.isEmpty || value.toUpperCase() == 'NULL' || !seen.add(value)) {
        continue;
      }
      options.add(value);
    }
    options.sort();
    return options;
  }

  List<Map<String, dynamic>> get _formulaFields => fields.where((field) {
        final uiType = _uiType(field);
        final formula = field['formula_funcion']?.toString().trim() ?? '';
        return (uiType == 'formula' || uiType == 'lookup') &&
            formula.isNotEmpty &&
            !_isListFormulaField(field);
      }).toList(growable: false);

  void _recalculateMatrixDrivenFields() {
    final formulas = _formulaFields;
    if (formulas.isEmpty) return;

    // Máximo 2 pasadas: suficiente para fórmulas dependientes sin castigar cada tecla.
    // Si una tabla requiere cadenas largas de fórmulas, se estabiliza al siguiente cambio/guardado.
    final passes = formulas.length <= 1 ? 1 : 2;
    for (var pass = 0; pass < passes; pass++) {
      var changed = false;
      for (final field in formulas) {
        final campo = field['campo']?.toString() ?? '';
        final formula = field['formula_funcion']?.toString() ?? '';
        final controller = controllers[campo];
        if (campo.isEmpty || controller == null) continue;
        final result = _runFormula(formula);
        final formatted = _formatFormulaResultForField(result, field);
        if (controller.text != formatted) {
          controller.text = formatted;
          changed = true;
        }
      }
      if (!changed) break;
    }
  }

  void _scheduleFormulaRecalculation() {
    _formulaRecalcDebounce?.cancel();
    _formulaRecalcDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      // No usar setState por cada tecla: eso reconstruía todo el formulario y hacía lento
      // RF-REGISTRO_HIDROMETROS_POZO cuando tenía fotos/firmas/condiciones.
      _recalculateDerivedFields();
      _recalculateMatrixDrivenFields();
    });
  }

  String _signatureDataUrl(Uint8List bytes) {
    return 'data:image/png;base64,${base64Encode(bytes)}';
  }

  String _generateHiddenIdValue(Map<String, dynamic> field, String idLocal) {
    final campo = (field['campo']?.toString() ?? '').trim();
    final normalizedCampo = campo.toLowerCase();
    if (normalizedCampo == 'id_local') return idLocal;

    final configuredPrefix =
        (field['id_generador']?.toString() ?? '').trim().toUpperCase();
    final prefix = configuredPrefix.isEmpty ? 'REGI' : configuredPrefix;
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = math.Random.secure();
    final suffix =
        List.generate(16, (_) => chars[rnd.nextInt(chars.length)]).join();
    return '$prefix$suffix';
  }

  dynamic _valueForField(Map<String, dynamic> field, String idLocal) {
    final campo = field['campo']?.toString() ?? '';
    if (_isSanctionDocumentField(field) ||
        (_isPermissionDocumentField(field) &&
            !_selectedAbsenceRequiresDocument)) {
      return null;
    }
    final declaredTipo = field['tipo']?.toString().trim().toLowerCase() ?? '';
    final tipo = _normalizeTipo(field['tipo']?.toString());
    final uiType = _uiType(field);
    final isFormulaControl = uiType == 'formula' || uiType == 'lookup';

    if (tipo == 'hidden_id' || uiType == 'hidden_id') {
      final existing = controllers[campo]?.text.trim() ?? '';
      return existing.isNotEmpty
          ? existing
          : _generateHiddenIdValue(field, idLocal);
    }
    if (tipo == 'hidden' || uiType == 'hidden') {
      final existing = controllers[campo]?.text.trim() ?? '';
      return existing.isNotEmpty ? existing : null;
    }
    if (!isFormulaControl &&
        (tipo == 'boolean_int' ||
            uiType == 'boolean_int' ||
            uiType == 'checkbox' ||
            uiType == 'switch')) return dropdownValues[campo] ?? 0;
    if (tipo == 'signature' || uiType == 'signature') {
      final bytes = signatureValues[campo];
      return bytes == null ? null : _signatureDataUrl(bytes);
    }
    if (tipo == 'photo' || uiType == 'photo') {
      // La cámara ya dejó el data:image en el controller al capturar.
      // No volver a base64-encodear en Guardar; eso hacía lento el guardado local.
      final existing = controllers[campo]?.text.trim() ?? '';
      if (existing.isNotEmpty) return existing;
      final bytes = photoValues[campo];
      return bytes == null ? null : _imageDataUrl(bytes);
    }
    if (uiType == 'multiselect') {
      final values = (multiSelectValues[campo] ?? <String>{}).toList()..sort();
      return values.isEmpty ? null : values.join('|');
    }

    final raw = controllers[campo]?.text.trim() ?? '';
    if (raw.isEmpty) return null;

    if (tipo == 'boolean_int') {
      final boolValue = _asBool(raw);
      return isFormulaControl &&
              (declaredTipo == 'bool' || declaredTipo == 'boolean')
          ? boolValue
          : (boolValue ? 1 : 0);
    }
    if (tipo == 'json' || tipo == 'jsonb') {
      try {
        return jsonDecode(raw);
      } catch (_) {
        return raw;
      }
    }

    if (tipo == 'date') return raw;
    if (tipo == 'time') {
      if (uiType == 'formula' && (raw == '0' || raw == '0.0')) return null;
      return raw;
    }
    if (tipo == 'datetime' || tipo == 'timestamp') return raw;

    // IMPORTANTE: tipo_ui=formula NO significa que el resultado sea numérico.
    // El tipo real manda. Ejemplo: tipo=time + tipo_ui=formula + HORA_ACTUAL()
    // debe guardar HH:mm, no 0.
    final shouldParseAsNumber = tipo == 'number' ||
        tipo == 'numeric' ||
        tipo == 'decimal' ||
        tipo == 'integer' ||
        tipo == 'int' ||
        tipo == 'percent' ||
        uiType == 'number' ||
        uiType == 'slider' ||
        uiType == 'rating' ||
        uiType == 'percent';

    if (shouldParseAsNumber) {
      final number = double.tryParse(raw.replaceAll(',', '.'));
      if (number == null) return null;
      if (tipo == 'integer' || tipo == 'int') return number.round();
      if (!_hasNumeroDecimales(field)) {
        return number.truncateToDouble() == number ? number.toInt() : number;
      }
      final decimals = _numeroDecimales(field);
      final fixed = double.parse(number.toStringAsFixed(decimals));
      return decimals == 0 ? fixed.toInt() : fixed;
    }
    return raw;
  }

  bool _valuePresentForCampo(Map<String, dynamic> payload, String campo) {
    final value = payload[campo];
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    return true;
  }

  bool _formatCapabilityEnabled(String capability) {
    final normalized = capability.trim().toLowerCase();
    final aliases = <String>{
      normalized,
      if (normalized == 'geolocation') 'geolocalizacion',
      if (normalized == 'approvals') 'aprobaciones',
      if (normalized == 'workflow') 'flujo',
    };
    final direct = widget.format['${normalized}_enabled'];
    if (direct != null && _asBool(direct)) return true;
    dynamic raw = widget.format['capacidades'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {}
    }
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (aliases.contains(entry.key.toString().trim().toLowerCase())) {
          return _asBool(entry.value);
        }
      }
    }
    return false;
  }

  String _gpsPayloadKey(List<String> candidates, String fallback) {
    final wanted = candidates.map(_normalizarNombreCampo).toSet();
    for (final field in fields) {
      final campo = field['campo']?.toString().trim() ?? '';
      if (campo.isNotEmpty && wanted.contains(_normalizarNombreCampo(campo))) {
        return campo;
      }
    }
    return fallback;
  }

  Future<bool> _captureRequiredGeolocation(Map<String, dynamic> payload) async {
    if (!_formatCapabilityEnabled('geolocation')) return true;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Activa la ubicación del equipo para guardar este registro.'),
        ));
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Este formato requiere permiso de ubicación para guardar el registro.'),
        ));
        return false;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      payload[_gpsPayloadKey(['LATITUD', 'LATITUDE'], 'LATITUD')] =
          position.latitude;
      payload[_gpsPayloadKey(['LONGITUD', 'LONGITUDE'], 'LONGITUD')] =
          position.longitude;
      payload[_gpsPayloadKey(['PRECISION_GPS', 'PRECISION GPS', 'ACCURACY'],
          'PRECISION_GPS')] = position.accuracy;
      payload[_gpsPayloadKey(
              ['FECHA_GPS', 'FECHA GPS', 'GPS_AT'], 'FECHA_GPS')] =
          position.timestamp.toIso8601String();
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'No se pudo obtener la ubicación. Revisa el GPS e inténtalo nuevamente: $error'),
      ));
      return false;
    }
  }

  List<String> _configuredWorkflowStates() {
    dynamic raw = widget.format['flujo_estados'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {}
    }
    if (raw is! List) return const <String>[];
    return raw
        .map((state) => state is Map
            ? (state['codigo'] ?? state['nombre'])?.toString().trim() ?? ''
            : state?.toString().trim() ?? '')
        .where((state) => state.isNotEmpty)
        .toList(growable: false);
  }

  String _estadoRegistroForPayload(Map<String, dynamic> payload) {
    if (_formatCapabilityEnabled('workflow')) {
      final states = _configuredWorkflowStates();
      return states.isEmpty ? 'BORRADOR' : states.first;
    }
    if (restrictedFields.isNotEmpty) return 'PENDIENTE';

    var hasRequiredMissing = false;
    var hasSignature = false;
    var signaturesComplete = true;

    for (final f in fields) {
      final campo = f['campo']?.toString() ?? '';
      if (campo.isEmpty || _isRestrictedField(f)) continue;
      final tipo = _normalizeTipo(f['tipo']?.toString());
      final uiType = _uiType(f);
      final isPhoto = tipo == 'photo' || uiType == 'photo';
      if (_isCompensationWorkedDateField(f) &&
          !_selectedPermissionIsCompensation) {
        continue;
      }
      if (_isPermissionHourField(f) && !_selectedPermissionIsHourly) continue;
      if (_isSanctionPeriodField(f) && _selectedSanctionIsDismissal) continue;
      if (_isDismissalDateField(f) && !_selectedSanctionIsDismissal) continue;
      if (!_isVisible(f) && !isPhoto) continue;
      if (tipo == 'hidden_id' || tipo == 'hidden') continue;
      final isSignature = tipo == 'signature' || uiType == 'signature';
      final required = _isEffectivelyRequiredField(f);
      if (required && !_valuePresentForCampo(payload, campo))
        hasRequiredMissing = true;
      if (isSignature) {
        hasSignature = true;
        if (!_valuePresentForCampo(payload, campo)) signaturesComplete = false;
      }
    }

    if (hasRequiredMissing) return 'PENDIENTE';
    if (hasSignature && signaturesComplete) return 'APROBADO';
    return 'COMPLETO';
  }

  bool get _isPersonalPlanillaForm =>
      (tableDestino ?? '').trim().toUpperCase() ==
      'GH-REGISTRO_PERSONAL_PLANILLA';

  bool get _isPermissionLeaveForm =>
      (tableDestino ?? '').trim().toUpperCase() ==
      'GH_PERMISOS_LICENCIAS_APPGT';

  bool get _isSanctionForm =>
      (tableDestino ?? '').trim().toUpperCase() ==
      'GH_SANCIONES_PERSONAL_APPGT';

  bool get _usesPersonnelLookup => _isPermissionLeaveForm || _isSanctionForm;

  bool _isPersonnelDniField(Map<String, dynamic> field) {
    if (!_usesPersonnelLookup) return false;
    final campo = _normalizarNombreCampo(field['campo']?.toString() ?? '');
    return campo == 'DNI' || campo == 'DOCUMENTO';
  }

  bool _isPersonnelWorkerField(Map<String, dynamic> field) {
    if (!_usesPersonnelLookup) return false;
    return _normalizarNombreCampo(field['campo']?.toString() ?? '') ==
        'TRABAJADOR';
  }

  bool _isPermissionDocumentField(Map<String, dynamic> field) {
    return _isPermissionLeaveForm &&
        _normalizarNombreCampo(field['campo']?.toString() ?? '') ==
            'DOCUMENTO_SUSTENTO';
  }

  bool _isSanctionDocumentField(Map<String, dynamic> field) {
    return _isSanctionForm &&
        _normalizarNombreCampo(field['campo']?.toString() ?? '') ==
            'DOCUMENTO_SUSTENTO';
  }

  String _permissionTypeValue() {
    for (final entry in controllers.entries) {
      if (_normalizarNombreCampo(entry.key) == 'TIPO_PERMISO') {
        return entry.value.text.trim();
      }
    }
    return '';
  }

  bool get _selectedAbsenceRequiresDocument {
    return _isPermissionLeaveForm &&
        permissionRequiresSupportingDocument(_permissionTypeValue());
  }

  bool get _selectedPermissionIsCompensation =>
      _isPermissionLeaveForm &&
      permissionIsCompensation(_permissionTypeValue());

  bool get _selectedPermissionIsHourly =>
      _isPermissionLeaveForm && permissionIsHourly(_permissionTypeValue());

  bool _isPermissionHourField(Map<String, dynamic> field) {
    if (!_isPermissionLeaveForm) return false;
    final campo = _normalizarNombreCampo(field['campo']?.toString() ?? '');
    return campo == 'HORA_INICIO' || campo == 'HORA_FIN';
  }

  String _sanctionTypeValue() {
    for (final entry in controllers.entries) {
      if (_normalizarNombreCampo(entry.key) == 'TIPO_SANCION') {
        return entry.value.text.trim();
      }
    }
    return '';
  }

  bool get _selectedSanctionIsDismissal =>
      _isSanctionForm && sanctionIsDismissal(_sanctionTypeValue());

  bool _isSanctionPeriodField(Map<String, dynamic> field) {
    if (!_isSanctionForm) return false;
    final campo = _normalizarNombreCampo(field['campo']?.toString() ?? '');
    return campo == 'FECHA_INICIO' || campo == 'FECHA_FIN';
  }

  bool _isDismissalDateField(Map<String, dynamic> field) =>
      _isSanctionForm &&
      _normalizarNombreCampo(field['campo']?.toString() ?? '') ==
          'FECHA_DESPIDO';

  bool _isAttendanceBlockingField(Map<String, dynamic> field) {
    if (!_usesPersonnelLookup) return false;
    final campo = _normalizarNombreCampo(field['campo']?.toString() ?? '');
    final etiqueta =
        _normalizarNombreCampo(field['etiqueta']?.toString() ?? '');
    return campo == 'BLOQUEA_ASISTENCIA' ||
        campo == 'BLOQUEAR_ASISTENCIA' ||
        etiqueta == 'BLOQUEA_ASISTENCIA' ||
        etiqueta == 'BLOQUEAR_ASISTENCIA';
  }

  bool _isEffectivelyRequiredField(Map<String, dynamic> field) {
    if (_isAttendanceBlockingField(field)) return false;
    if (_isPermissionDocumentField(field)) {
      return _selectedAbsenceRequiresDocument;
    }
    if (_isPermissionHourField(field)) return _selectedPermissionIsHourly;
    if (_isSanctionPeriodField(field)) return !_selectedSanctionIsDismissal;
    if (_isDismissalDateField(field)) return _selectedSanctionIsDismissal;
    return _asBool(field['requerido']);
  }

  bool _isCompensationWorkedDateField(Map<String, dynamic> field) {
    if (!_isPermissionLeaveForm) return false;
    final campo = _normalizarNombreCampo(field['campo']?.toString() ?? '');
    final etiqueta =
        _normalizarNombreCampo(field['etiqueta']?.toString() ?? '');
    return campo == 'FECHA_ORIGEN_COMPENSACION' ||
        campo == 'FECHA_TRABAJADA_A_COMPENSAR' ||
        etiqueta == 'FECHA_TRABAJADA_A_COMPENSAR';
  }

  void _clearPermissionDocumentWhenNotRequired() {
    if (!_isPermissionLeaveForm || _selectedAbsenceRequiresDocument) return;
    for (final field in fields) {
      if (!_isPermissionDocumentField(field)) continue;
      final campo = field['campo']?.toString() ?? '';
      controllers[campo]?.clear();
      documentFileNames.remove(campo);
    }
  }

  void _clearCompensationDateWhenNotApplicable() {
    if (!_isPermissionLeaveForm || _selectedPermissionIsCompensation) return;
    for (final field in fields) {
      if (!_isCompensationWorkedDateField(field)) continue;
      final campo = field['campo']?.toString() ?? '';
      controllers[campo]?.clear();
    }
  }

  void _clearPermissionHoursWhenNotApplicable() {
    if (!_isPermissionLeaveForm || _selectedPermissionIsHourly) return;
    for (final field in fields) {
      if (!_isPermissionHourField(field)) continue;
      controllers[field['campo']?.toString() ?? '']?.clear();
    }
  }

  void _clearSanctionDatesForType() {
    if (!_isSanctionForm) return;
    for (final field in fields) {
      final shouldClear = _selectedSanctionIsDismissal
          ? _isSanctionPeriodField(field)
          : _isDismissalDateField(field);
      if (shouldClear) controllers[field['campo']?.toString() ?? '']?.clear();
    }
  }

  void _handlePermissionTypeChanged() {
    _clearPermissionDocumentWhenNotRequired();
    _clearCompensationDateWhenNotApplicable();
    _clearPermissionHoursWhenNotApplicable();
  }

  void _handleHumanResourcesTypeChanged(String campo) {
    final normalized = _normalizarNombreCampo(campo);
    if (normalized == 'TIPO_PERMISO') _handlePermissionTypeChanged();
    if (normalized == 'TIPO_SANCION') _clearSanctionDatesForType();
  }

  Future<void> _setPdfDocument(
    String campo,
    String fileName,
    Uint8List bytes,
  ) async {
    if (!fileName.toLowerCase().endsWith('.pdf') ||
        bytes.length < 5 ||
        String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione un archivo PDF valido.')),
      );
      return;
    }
    if (bytes.length > 15 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El PDF no debe superar los 15 MB.')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      controllers.putIfAbsent(campo, () => TextEditingController()).text =
          'data:application/pdf;base64,${base64Encode(bytes)}';
      documentFileNames[campo] = fileName;
    });
  }

  Future<void> _pickPdfDocument(String campo) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null && !kIsWeb) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No se pudo leer el archivo seleccionado.')),
      );
      return;
    }
    await _setPdfDocument(campo, file.name, bytes);
  }

  Widget _permissionDocumentWidget(Map<String, dynamic> field) {
    final campo = field['campo']?.toString() ?? '';
    final etiqueta = field['etiqueta']?.toString() ?? 'Documento de sustento';
    final raw = controllers[campo]?.text.trim() ?? '';
    final selectedName = documentFileNames[campo];
    final hasDocument = raw.isNotEmpty;
    final content = InputDecorator(
      decoration: InputDecoration(
        labelText: '$etiqueta *',
        border: const OutlineInputBorder(),
        helperText:
            'Obligatorio para este tipo de ausencia. Solo PDF, maximo 15 MB.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: hasDocument
                  ? const Color(0xFFE8F5F2)
                  : const Color(0xFFF4F8F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasDocument
                    ? const Color(0xFF17806D)
                    : const Color(0xFFB8CDD2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasDocument
                      ? Icons.picture_as_pdf_rounded
                      : Icons.upload_file_rounded,
                  color: hasDocument
                      ? const Color(0xFF17806D)
                      : const Color(0xFF0D5F78),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasDocument
                        ? (selectedName ?? 'PDF guardado anteriormente')
                        : 'Haga clic para seleccionar o arrastre el PDF',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (hasDocument)
                  IconButton(
                    tooltip: 'Quitar documento',
                    onPressed: () => setState(() {
                      controllers[campo]?.clear();
                      documentFileNames.remove(campo);
                    }),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _pickPdfDocument(campo),
            icon: const Icon(Icons.attach_file_rounded),
            label: Text(hasDocument ? 'Cambiar PDF' : 'Seleccionar PDF'),
          ),
        ],
      ),
    );

    if (!(kIsWeb || isDesktopRuntime)) return content;
    return DropTarget(
      onDragDone: (details) async {
        if (details.files.isEmpty) return;
        final file = details.files.first;
        await _setPdfDocument(campo, file.name, await file.readAsBytes());
      },
      child: content,
    );
  }

  String _payloadText(Map<String, dynamic> payload, List<String> keys) {
    for (final k in keys) {
      for (final e in payload.entries) {
        if (_normalizarNombreCampo(e.key) == _normalizarNombreCampo(k)) {
          final v = e.value?.toString().trim() ?? '';
          if (v.isNotEmpty && v.toUpperCase() != 'NULL') return v;
        }
      }
    }
    return '';
  }

  Future<Uint8List?> _photocheckPhotoBytes(String source) async {
    final clean = source.trim();
    if (clean.isEmpty || clean.toUpperCase() == 'NULL') return null;
    if (clean.startsWith('data:image/') && clean.contains(',')) {
      try {
        return base64Decode(clean.substring(clean.indexOf(',') + 1));
      } catch (_) {
        return null;
      }
    }
    if (!kIsWeb) {
      try {
        final file = File(clean);
        if (await file.exists()) return file.readAsBytes();
      } catch (_) {}
    }

    try {
      final resolved = await EvidenceStorage.signedUrlForValue(clean);
      final bytes = await fetchUrlBytes(resolved);
      if (bytes != null) return bytes;
    } catch (_) {}

    final isExplicitSource = clean.toLowerCase().startsWith('http') ||
        clean.startsWith('storage://') ||
        clean.contains('storage/v1/');
    if (!isExplicitSource) {
      final path = clean.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
      for (final bucket in ['appgt-evidencias', 'migracion-appsheets']) {
        try {
          final url = await Supabase.instance.client.storage
              .from(bucket)
              .createSignedUrl(path, EvidenceStorage.signedUrlTtlSeconds);
          final bytes = await fetchUrlBytes(url);
          if (bytes != null) return bytes;
        } catch (_) {}
      }
    }
    return null;
  }

  Future<void> _generateLocalPhotocheckFromPayload(
      Map<String, dynamic> payload) async {
    final dni = _payloadText(payload, ['DNI', 'DOCUMENTO']);
    final nombre = _payloadText(payload,
        ['APELLIDOS Y NOMBRES', 'APELLIDOS_NOMBRES', 'NOMBRE', 'NOMBRES']);
    final puesto = _payloadText(payload, ['PUESTO', 'CARGO']);
    final area = _payloadText(payload, ['AREA', 'ÁREA']);
    final fotoData = _payloadText(
        payload, ['FOTO1', 'FOTO 1', 'FOTO_1', 'FOTO', 'PHOTO_URL']);
    final fotoBytes = await _photocheckPhotoBytes(fotoData);
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Center(
        child: pw.Container(
          width: 170,
          height: 255,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey700),
              borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('ZUMAC',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Container(
                  width: 74,
                  height: 82,
                  decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey500)),
                  child: fotoBytes != null
                      ? pw.Image(pw.MemoryImage(fotoBytes),
                          fit: pw.BoxFit.cover)
                      : pw.Center(
                          child: pw.Text('SIN FOTO',
                              style: const pw.TextStyle(fontSize: 8)))),
              pw.Text(nombre.isEmpty ? 'SIN NOMBRE' : nombre,
                  textAlign: pw.TextAlign.center,
                  maxLines: 3,
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text('DNI: $dni', style: const pw.TextStyle(fontSize: 8)),
              if (puesto.isNotEmpty)
                pw.Text(puesto,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 7)),
              if (area.isNotEmpty)
                pw.Text(area,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 7)),
              pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: dni.isNotEmpty
                      ? dni
                      : (payload['id_local']?.toString() ?? ''),
                  width: 54,
                  height: 54),
            ],
          ),
        ),
      ),
    ));
    final stamp =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:\\.]'), '-');
    final fileName = 'photocheck_${dni.isEmpty ? stamp : dni}_$stamp.pdf';
    final bytes = await pdf.save();
    if (kIsWeb) {
      await downloadFileBytes(fileName: fileName, bytes: bytes);
      return;
    }
    final dir = Directory(
        '${Platform.environment['USERPROFILE'] ?? Directory.current.path}\\Downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}\\$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await OpenFilex.open(file.path);
  }

  String _permissionDocumentFileName(Map<String, dynamic> payload) {
    final request = _payloadText(
      payload,
      ['numero_solicitud', 'NÚMERO DE SOLICITUD'],
    );
    final dni = _payloadText(payload, ['dni', 'DNI', 'DOCUMENTO']);
    final safeId = (request.isNotEmpty ? request : dni)
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final stamp =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:\.]'), '-');
    return 'permiso_licencia_${safeId.isEmpty ? stamp : safeId}.pdf';
  }

  Future<void> _generatePermissionDocumentFromPayload(
      Map<String, dynamic> payload) async {
    final number = _payloadText(
      payload,
      ['numero_solicitud', 'NÚMERO DE SOLICITUD'],
    );
    final worker = _payloadText(
      payload,
      ['trabajador', 'APELLIDOS Y NOMBRES', 'NOMBRE COMPLETO'],
    );
    final dni = _payloadText(payload, ['dni', 'DNI', 'DOCUMENTO']);
    final position = _payloadText(payload, ['puesto', 'PUESTO', 'CARGO']);
    final area = _payloadText(payload, ['area', 'ÁREA', 'AREA']);
    final type = _payloadText(
      payload,
      ['tipo_permiso', 'TIPO DE PERMISO', 'TIPO'],
    ).replaceAll('_', ' ');
    final start = _payloadText(payload, ['fecha_inicio', 'FECHA INICIO']);
    final end = _payloadText(payload, ['fecha_fin', 'FECHA FIN']);
    final reason = _payloadText(payload, ['motivo', 'MOTIVO']);
    final observations =
        _payloadText(payload, ['observaciones', 'OBSERVACIONES']);
    final approvalState = _payloadText(
      payload,
      ['ESTADO_APROBACION', 'estado'],
    ).toUpperCase();
    final approved = approvalState == 'APROBADO';
    final isMedicalLeave = _normalizarNombreCampo(type) == 'DESCANSO_MEDICO';
    final company = _payloadText(
      payload,
      ['empresa_nombre', 'EMPRESA', 'RAZON_SOCIAL'],
    );
    final companyRuc = _payloadText(payload, ['empresa_ruc', 'RUC']);
    final representative = _payloadText(
      payload,
      ['representante_nombre', 'REPRESENTANTE'],
    );
    final representativeRole = _payloadText(
      payload,
      ['representante_cargo', 'CARGO_REPRESENTANTE'],
    );
    final issuePlace = _payloadText(
      payload,
      ['lugar_emision', 'LUGAR_EMISION'],
    );
    final returnDate = _payloadText(
      payload,
      ['fecha_reincorporacion', 'FECHA_REINCORPORACION'],
    );
    final requestedDays = _payloadText(
      payload,
      ['dias_solicitados', 'DIAS_SOLICITADOS'],
    );
    final signatureData =
        _payloadText(payload, ['firma_trabajador', 'FIRMA DEL TRABAJADOR']);
    Uint8List? signatureBytes;
    if (signatureData.startsWith('data:image/') &&
        signatureData.contains(',')) {
      try {
        signatureBytes = base64Decode(
          signatureData.substring(signatureData.indexOf(',') + 1),
        );
      } catch (_) {}
    }

    pw.Widget detailRow(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 118,
                child: pw.Text(
                  label,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Expanded(child: pw.Text(value.isEmpty ? '—' : value)),
            ],
          ),
        );

    DateTime? parseDate(String value) {
      final clean = value.trim();
      if (clean.isEmpty) return null;
      final iso = DateTime.tryParse(
          clean.length >= 10 ? clean.substring(0, 10) : clean);
      if (iso != null) return iso;
      final parts = clean.split('/');
      if (parts.length != 3) return null;
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day == null || month == null || year == null) return null;
      return DateTime(year, month, day);
    }

    const months = <String>[
      'ENERO',
      'FEBRERO',
      'MARZO',
      'ABRIL',
      'MAYO',
      'JUNIO',
      'JULIO',
      'AGOSTO',
      'SEPTIEMBRE',
      'OCTUBRE',
      'NOVIEMBRE',
      'DICIEMBRE'
    ];
    String longDate(DateTime? date) => date == null
        ? 'FECHA NO REGISTRADA'
        : '${date.day.toString().padLeft(2, '0')} de '
            '${months[date.month - 1]} de ${date.year}';
    String shortDate(DateTime? date, String fallback) => date == null
        ? fallback
        : '${date.day.toString().padLeft(2, '0')}/'
            '${date.month.toString().padLeft(2, '0')}/${date.year}';

    final startDate = parseDate(start);
    final endDate = parseDate(end);
    final rejoinDate =
        parseDate(returnDate) ?? endDate?.add(const Duration(days: 1));
    final days = int.tryParse(requestedDays) ??
        (startDate != null && endDate != null
            ? endDate.difference(startDate).inDays + 1
            : 1);
    final emissionDate = DateTime.now();
    final resolvedCompany = company.isEmpty ? 'EMPRESA' : company;
    final resolvedPlace = issuePlace.isEmpty ? 'CHICLAYO' : issuePlace;

    pw.Widget signatures() => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(children: [
              pw.SizedBox(width: 190, height: 62),
              pw.Container(width: 190, height: 1, color: PdfColors.black),
              pw.SizedBox(height: 5),
              pw.Text('REPRESENTANTE',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
              if (representative.isNotEmpty)
                pw.Text('NOMBRE: ${representative.toUpperCase()}',
                    style: const pw.TextStyle(fontSize: 8)),
              if (representativeRole.isNotEmpty)
                pw.Text('CARGO: ${representativeRole.toUpperCase()}',
                    style: const pw.TextStyle(fontSize: 8)),
            ]),
            pw.Column(children: [
              pw.Container(
                width: 190,
                height: 62,
                alignment: pw.Alignment.bottomCenter,
                child: signatureBytes == null
                    ? null
                    : pw.Image(pw.MemoryImage(signatureBytes),
                        fit: pw.BoxFit.contain),
              ),
              pw.Container(width: 190, height: 1, color: PdfColors.black),
              pw.SizedBox(height: 5),
              pw.Text('TRABAJADOR',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text('NOMBRE: ${worker.toUpperCase()}',
                  style: const pw.TextStyle(fontSize: 8)),
              pw.Text('DNI N.° $dni', style: const pw.TextStyle(fontSize: 8)),
            ]),
          ],
        );

    final pdf = pw.Document();
    if (approved && isMedicalLeave) {
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(42),
        build: (_) => [
          pw.Text(
            'CONSTANCIA DE PERMISO CON GOCE DE HABER POR DESCANSO MÉDICO',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          if (number.isNotEmpty)
            pw.Text('N.° $number',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 22),
          pw.Text(
            'Por medio del presente documento, la empresa $resolvedCompany, '
            '${companyRuc.isEmpty ? '' : 'identificada con RUC N.° $companyRuc, '}'
            'deja constancia de que se otorga al trabajador(a):',
            textAlign: pw.TextAlign.justify,
            style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 3),
          ),
          pw.SizedBox(height: 12),
          detailRow('Apellidos y nombres:', worker),
          detailRow('DNI:', dni),
          detailRow('Cargo:', position),
          detailRow('Área:', area),
          pw.SizedBox(height: 12),
          pw.Text(
            'PERMISO CON GOCE DE HABER POR MOTIVO DE DESCANSO MÉDICO, '
            'debidamente sustentado mediante el certificado médico y/o '
            'Certificado de Incapacidad Temporal para el Trabajo correspondiente.',
            textAlign: pw.TextAlign.justify,
            style: pw.TextStyle(
                fontSize: 10.5, lineSpacing: 3, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.Text('El período otorgado comprende:',
              style: const pw.TextStyle(fontSize: 10.5)),
          pw.SizedBox(height: 6),
          detailRow('Fecha de inicio:', shortDate(startDate, start)),
          detailRow('Fecha de término:', shortDate(endDate, end)),
          detailRow('Total:', '$days día${days == 1 ? '' : 's'} calendario'),
          pw.SizedBox(height: 12),
          pw.Text(
            'Durante dicho período, el trabajador queda exonerado de prestar '
            'servicios debido a la incapacidad temporal acreditada mediante la '
            'documentación médica presentada.',
            textAlign: pw.TextAlign.justify,
            style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 3),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'El trabajador declara haber tomado conocimiento del período de '
            'descanso médico y se compromete a reincorporarse a sus labores el '
            'día ${shortDate(rejoinDate, returnDate)}, salvo ampliación '
            'debidamente sustentada.',
            textAlign: pw.TextAlign.justify,
            style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 3),
          ),
          if (reason.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            detailRow('Motivo registrado:', reason),
          ],
          if (observations.isNotEmpty)
            detailRow('Observaciones:', observations),
          pw.SizedBox(height: 16),
          pw.Text(
            'Se firma la presente constancia en señal de conocimiento y recepción.',
            textAlign: pw.TextAlign.justify,
            style: const pw.TextStyle(fontSize: 10.5),
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            '${resolvedPlace.toUpperCase()}, ${longDate(emissionDate)}.',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 54),
          signatures(),
        ],
      ));
    } else {
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(42),
        build: (_) => [
          pw.Text('SOLICITUD DE PERMISO / LICENCIA',
              textAlign: pw.TextAlign.center,
              style:
                  pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 5),
          pw.Text(number.isEmpty ? 'Documento laboral' : 'N.° $number',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 24),
          detailRow('Trabajador:', worker),
          detailRow('DNI:', dni),
          detailRow('Puesto:', position),
          detailRow('Área:', area),
          pw.Divider(height: 22),
          detailRow('Tipo:', type),
          detailRow('Desde:', start),
          detailRow('Hasta:', end),
          detailRow('Motivo:', reason),
          if (observations.isNotEmpty)
            detailRow('Observaciones:', observations),
          pw.SizedBox(height: 24),
          pw.Text(
            'Declaro que la información consignada es correcta y solicito la '
            'autorización del permiso o licencia indicado.',
            textAlign: pw.TextAlign.justify,
            style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 3),
          ),
          pw.SizedBox(height: 60),
          signatures(),
        ],
      ));
    }
    final bytes = await pdf.save();
    final fileName =
        payload['documento_generado']?.toString().trim().isNotEmpty == true
            ? payload['documento_generado'].toString().trim()
            : _permissionDocumentFileName(payload);
    if (kIsWeb) {
      await downloadFileBytes(fileName: fileName, bytes: bytes);
      return;
    }
    final dir = Directory(
        '${Platform.environment['USERPROFILE'] ?? Directory.current.path}\\Downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}\\$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await OpenFilex.open(file.path);
  }

  Future<void> saveLocal({
    bool generarPhotocheck = false,
  }) async {
    if (savingLocal || capturingPhoto) return;
    FocusScope.of(context).unfocus();
    final cachedUserId = await LocalSession().cachedUserId();
    final userId =
        Supabase.instance.client.auth.currentUser?.id ?? cachedUserId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'No hay usuario local disponible. Ingresa una vez con internet.')),
      );
      return;
    }

    final table = tableDestino;
    if (table == null || table.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Este formato no tiene tabla destino configurada.')),
      );
      return;
    }

    if (fields.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'No hay campos configurados para esta tabla. Actualiza matrices.')),
      );
      return;
    }

    // El usuario puede pulsar Guardar antes de que venza el debounce de 180 ms.
    // Recalcular aquí garantiza que fórmulas requeridas y payload usen el valor
    // actual, también cuando BUSCAR devuelve texto.
    _formulaRecalcDebounce?.cancel();
    _recalculateDerivedFields();
    _recalculateMatrixDrivenFields();

    if (_isPersonalPlanillaForm && !generarPhotocheck) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Guardar personal'),
          content: const Text('Desea guardar sin generar photochek?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Aceptar')),
          ],
        ),
      );
      if (ok != true) return;
    }

    for (final f in fields) {
      final requerido = _isEffectivelyRequiredField(f);
      final tipo = _normalizeTipo(f['tipo']?.toString());
      final uiType = _uiType(f);
      final campo = f['campo']?.toString() ?? '';
      final isPhotoRequiredField = tipo == 'photo' || uiType == 'photo';
      if (_isCompensationWorkedDateField(f) &&
          !_selectedPermissionIsCompensation) {
        continue;
      }
      if (_isPermissionHourField(f) && !_selectedPermissionIsHourly) continue;
      if (_isSanctionPeriodField(f) && _selectedSanctionIsDismissal) continue;
      if (_isDismissalDateField(f) && !_selectedSanctionIsDismissal) continue;

      // Para fotos, requerido=true debe cumplirse aunque el campo no se pinte como
      // TextField normal. En APPGT las fotos suelen mostrarse por el botón/cámara
      // agrupada, por eso antes se omitían al depender de _isVisible().
      if (!requerido ||
          tipo == 'hidden_id' ||
          tipo == 'hidden' ||
          _isRestrictedField(f) ||
          _isAutoFilledDetailField(campo)) continue;
      if (!_isVisible(f) && !isPhotoRequiredField) continue;

      if (tipo == 'boolean_int' ||
          uiType == 'boolean_int' ||
          uiType == 'checkbox' ||
          uiType == 'switch') {
        if (dropdownValues[campo] == null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Falta completar: ${f['etiqueta'] ?? campo}')));
          return;
        }
      } else if (tipo == 'signature' || uiType == 'signature') {
        if (signatureValues[campo] == null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Falta firmar: ${f['etiqueta'] ?? campo}')));
          return;
        }
      } else if (isPhotoRequiredField) {
        if (photoValues[campo] == null &&
            (controllers[campo]?.text.trim() ?? '').isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Falta foto: ${f['etiqueta'] ?? campo}')));
          return;
        }
      } else if (uiType == 'multiselect') {
        if ((multiSelectValues[campo] ?? <String>{}).isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Falta seleccionar: ${f['etiqueta'] ?? campo}')));
          return;
        }
      } else if ((controllers[campo]?.text.trim() ?? '').isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Falta completar: ${f['etiqueta'] ?? campo}')));
        return;
      }
    }

    for (final f in fields) {
      final campo = f['campo']?.toString() ?? '';
      if (campo.isEmpty || !_shouldRenderField(f) || _isRestrictedField(f)) {
        continue;
      }
      final tipo = _normalizeTipo(f['tipo']?.toString());
      final uiType = _uiType(f);
      if (tipo == 'photo' || uiType == 'photo') continue;
      final error =
          _rangeErrorForField(f, controllers[campo]?.text.trim() ?? '');
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${f['etiqueta'] ?? campo}: $error')),
        );
        return;
      }
    }

    final idLocal = widget.editIdLocal ?? uuid.v4();
    for (final field in fields) {
      final campo = field['campo']?.toString().trim() ?? '';
      final tipo = _normalizeTipo(field['tipo']?.toString());
      final uiType = _uiType(field);
      final prefix = field['id_generador']?.toString().trim() ?? '';
      if (campo.isEmpty ||
          prefix.isEmpty ||
          (tipo != 'hidden_id' && uiType != 'hidden_id')) {
        continue;
      }
      final controller =
          controllers.putIfAbsent(campo, () => TextEditingController());
      if (controller.text.trim().isEmpty) {
        controller.text = await local.nextIncrementalIdentifier(
          table: table,
          field: campo,
          prefix: prefix,
        );
      }
    }
    final payload = <String, dynamic>{
      'id_local': idLocal,
    };
    for (final field in fields) {
      final campo = field['campo']?.toString();
      if (campo == null || campo.isEmpty || _isRestrictedField(field)) continue;
      if (_isCompensationWorkedDateField(field) &&
          !_selectedPermissionIsCompensation) {
        payload[campo] = null;
        continue;
      }
      if (_isPermissionHourField(field) && !_selectedPermissionIsHourly) {
        payload[campo] = null;
        continue;
      }
      if ((_isSanctionPeriodField(field) && _selectedSanctionIsDismissal) ||
          (_isDismissalDateField(field) && !_selectedSanctionIsDismissal)) {
        payload[campo] = null;
        continue;
      }
      final value = _valueForField(field, idLocal);
      if (value != null) payload[campo] = value;
    }
    final currentConfig = _currentFormatTableConfig;
    if (_isDetailTableRow(currentConfig) && _wizardMasterPayload != null) {
      final fk = _cleanNullableText(currentConfig?['campo_fk_hijo']);
      if (fk != null && (_wizardMasterIdLocal ?? '').isNotEmpty) {
        payload[fk] = _wizardMasterIdLocal;
      }
      for (final campo in _copyFieldsFromParent(currentConfig)) {
        final value = _payloadValueByCampo(_wizardMasterPayload!, campo);
        if (value != null) payload[campo] = value;
      }
      final iterField = _cleanNullableText(currentConfig?['campo_iterador']);
      if (iterField != null) {
        payload[iterField] = _wizardCurrentIteration ??
            _intFromValue(payload[iterField]) ??
            _intFromValue(currentConfig?['iterador_desde']) ??
            1;
      }
    }

    if (!await _captureRequiredGeolocation(payload)) return;
    if (_formatCapabilityEnabled('approvals')) {
      payload[_gpsPayloadKey(['ESTADO_APROBACION', 'ESTADO APROBACION'],
          'ESTADO_APROBACION')] ??= 'PENDIENTE';
    }
    for (final field in fields) {
      final campo = field['campo']?.toString().trim() ?? '';
      if (_normalizarNombreCampo(campo) == 'ESTADO_REGISTRO') {
        payload[campo] = _estadoRegistroForPayload(payload);
        break;
      }
    }

    setState(() => savingLocal = true);
    try {
      if (isOnlineFirstRuntime) {
        final saved = await SyncService().saveRecordOnline(
          table: table,
          payload: payload,
          moduleId: widget.moduleId,
          formatId: widget.format['id']?.toString() ?? '',
          formatTableId: selectedInternalTableId,
          editPrimaryKeyColumn: widget.editPrimaryKeyColumn,
          editPrimaryKeyValue: widget.editPrimaryKeyValue,
        );
        payload
          ..clear()
          ..addAll(saved);
      } else {
        await local.insertPending({
          'id_local': idLocal,
          'user_id': userId,
          'modulo_id': widget.moduleId,
          'formato_id': widget.format['id'],
          'formato_tabla_id': selectedInternalTableId,
          'tabla_destino': table,
          'payload_json': jsonEncode(payload),
          'estado': 'pendiente',
          'intentos': 0,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => savingLocal = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isOnlineFirstRuntime
              ? SyncService().friendlyError(e)
              : 'No se pudo guardar localmente: ${SyncService().friendlyError(e)}'),
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => savingLocal = false);

    final detailForHeader = _detailTableForCurrentHeader;
    if (_isHeaderTableRow(currentConfig) && detailForHeader != null) {
      _wizardMasterPayload = Map<String, dynamic>.from(payload);
      _wizardMasterIdLocal = idLocal;
      _wizardCurrentIteration =
          _intFromValue(detailForHeader['iterador_desde']) ?? 1;
      final nextId = detailForHeader['id']?.toString();
      if (nextId != null && nextId.isNotEmpty) {
        setState(() => selectedInternalTableId = nextId);
        await loadFieldsForCurrentTable();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cabecera guardada. Ahora registra las muestras.')),
      );
      return;
    }

    if (_isDetailTableRow(currentConfig) && _wizardMasterPayload != null) {
      final hasta = _intFromValue(currentConfig?['iterador_hasta']);
      final actual = _wizardCurrentIteration ??
          _intFromValue(currentConfig?['iterador_desde']) ??
          1;
      if (hasta != null && actual < hasta) {
        setState(() {
          _wizardCurrentIteration = actual + 1;
          _clearDetailControllersForNextIteration(currentConfig!);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Muestra $actual guardada. Continúa con muestra ${actual + 1}.')),
        );
        return;
      }
    }

    if (_isPersonalPlanillaForm && generarPhotocheck) {
      await _generateLocalPhotocheckFromPayload(payload);
    }

    await ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isOnlineFirstRuntime
            ? 'Registro guardado correctamente.'
            : 'Registro guardado en el celular. Queda pendiente de envio.'),
      ),
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ModulesPage()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _formulaRecalcDebounce?.cancel();
    for (final c in controllers.values) {
      c.dispose();
    }
    for (final f in focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _captureSignature(String campo) async {
    final bytes = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SignatureDialog(),
    );
    if (bytes == null) return;
    setState(() => signatureValues[campo] = bytes);
  }

  bool _isMultiSelectField(Map<String, dynamic> field) {
    return _uiType(field) == 'multiselect';
  }

  Set<String> _parseMultiSelectText(String raw) {
    if (raw.trim().isEmpty) return <String>{};
    return raw
        .split(RegExp(r'[|,;]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  void _syncMultiSelectController(String campo) {
    final values = (multiSelectValues[campo] ?? <String>{}).toList()..sort();
    controllers.putIfAbsent(campo, () => TextEditingController());
    controllers[campo]!.text = values.join('|');
  }

  Future<String?> _showSearchableDropdownPicker({
    required String title,
    required List<String> options,
    String? currentValue,
  }) async {
    final uniqueOptions = <String>[];
    final seen = <String>{};
    for (final option in options) {
      final value = option.trim();
      if (value.isEmpty) continue;
      final key = value.toLowerCase();
      if (seen.add(key)) uniqueOptions.add(value);
    }
    uniqueOptions.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final searchController = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          var filtered = List<String>.from(uniqueOptions);
          void applyFilter(
              String query, void Function(void Function()) setLocalState) {
            final q = query.trim().toLowerCase();
            setLocalState(() {
              filtered = q.isEmpty
                  ? List<String>.from(uniqueOptions)
                  : uniqueOptions
                      .where((e) => e.toLowerCase().contains(q))
                      .toList();
            });
          }

          return AlertDialog(
            backgroundColor: const Color(0xFFF4F8F7),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFE2F1F4),
                  foregroundColor: Color(0xFF0D5F78),
                  child: Icon(Icons.list_alt_outlined),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF0D5F78),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: StatefulBuilder(
                builder: (context, setLocalState) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      autofocus: false,
                      decoration: const InputDecoration(
                        labelText: 'Buscar en la lista',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) => applyFilter(value, setLocalState),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: filtered.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No hay coincidencias.'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final option = filtered[index];
                                final selected = option == currentValue;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: ListTile(
                                    dense: true,
                                    tileColor: selected
                                        ? const Color(0xFFDDF1F4)
                                        : Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: selected
                                            ? const Color(0xFF176B87)
                                            : const Color(0xFFD6E4E8),
                                      ),
                                    ),
                                    leading: Icon(
                                      selected
                                          ? Icons.check_circle
                                          : Icons.circle_outlined,
                                      color: const Color(0xFF176B87),
                                    ),
                                    title: Text(
                                      option,
                                      style: TextStyle(
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                    onTap: () =>
                                        Navigator.pop(dialogContext, option),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar')),
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, ''),
                  child: const Text('Limpiar')),
            ],
          );
        },
      );
    } finally {
      searchController.dispose();
    }
  }

  Widget _buildSearchableDropdownField({
    required Map<String, dynamic> field,
    required List<String> options,
  }) {
    final campo = field['campo']?.toString() ?? '';
    final etiqueta = field['etiqueta']?.toString() ?? campo;
    final requerido = _isEffectivelyRequiredField(field);
    final editable = _isEditable(field);
    final current = controllers[campo]?.text.trim() ?? '';
    final hasValidValue = current.isNotEmpty && options.contains(current);

    return InkWell(
      onTap: editable
          ? () async {
              final selected = await _showSearchableDropdownPicker(
                title: requerido ? '$etiqueta *' : etiqueta,
                options: options,
                currentValue: hasValidValue ? current : null,
              );
              if (selected == null) return;
              setState(() {
                controllers[campo]?.text = selected;
                _handleHumanResourcesTypeChanged(campo);
                _recalculateDerivedFields();
                _recalculateMatrixDrivenFields();
              });
            }
          : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: requerido ? '$etiqueta *' : etiqueta,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.list_alt_outlined),
          suffixIcon:
              Icon(editable ? Icons.unfold_more_rounded : Icons.lock_outline),
          helperText: options.isEmpty
              ? 'Sin opciones configuradas o descargadas.'
              : null,
        ),
        child: Row(
          children: [
            if (hasValidValue) ...[
              const Icon(Icons.check_circle,
                  size: 17, color: Color(0xFF17806D)),
              const SizedBox(width: 7),
            ],
            Expanded(
              child: Text(
                hasValidValue ? current : 'Seleccione o busque...',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(color: hasValidValue ? null : Colors.grey[600]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMultiSelectField({
    required Map<String, dynamic> field,
    required List<String> options,
    String? helperText,
  }) {
    final campo = field['campo']?.toString() ?? '';
    final etiqueta = field['etiqueta']?.toString() ?? campo;
    final requerido = _isEffectivelyRequiredField(field);
    final editable = _isEditable(field);

    final selected = multiSelectValues.putIfAbsent(campo, () {
      final raw = controllers[campo]?.text.trim() ?? '';
      return _parseMultiSelectText(raw);
    });

    Future<void> openPicker() async {
      if (!editable || options.isEmpty) return;
      final temp = Set<String>.from(selected);
      final result = await showDialog<Set<String>>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFFF4F8F7),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFE2F1F4),
                foregroundColor: Color(0xFF0D5F78),
                child: Icon(Icons.checklist_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  requerido ? '$etiqueta *' : etiqueta,
                  style: const TextStyle(
                    color: Color(0xFF0D5F78),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: StatefulBuilder(
                builder: (context, setDialogState) => ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options[index];
                    final checked = temp.contains(option);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: CheckboxListTile(
                        activeColor: const Color(0xFF0D5F78),
                        tileColor:
                            checked ? const Color(0xFFDDF1F4) : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: checked
                                ? const Color(0xFF176B87)
                                : const Color(0xFFD6E4E8),
                          ),
                        ),
                        value: checked,
                        title: Text(
                          option,
                          style: TextStyle(
                            fontWeight:
                                checked ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              temp.add(option);
                            } else {
                              temp.remove(option);
                            }
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            TextButton(
                onPressed: () => Navigator.pop(context, <String>{}),
                child: const Text('Limpiar')),
            FilledButton(
                onPressed: () => Navigator.pop(context, temp),
                child: const Text('Aplicar')),
          ],
        ),
      );
      if (result == null) return;
      setState(() {
        selected
          ..clear()
          ..addAll(result);
        _syncMultiSelectController(campo);
        _recalculateDerivedFields();
        _recalculateMatrixDrivenFields();
      });
    }

    final orderedSelected = selected.toList()..sort();

    return InkWell(
      onTap: openPicker,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: requerido ? '$etiqueta *' : etiqueta,
          border: const OutlineInputBorder(),
          helperText: helperText ??
              (options.isEmpty
                  ? 'No hay valores disponibles.'
                  : 'Toca para seleccionar uno o varios valores'),
          prefixIcon: const Icon(Icons.checklist_rounded),
          suffixIcon:
              Icon(editable ? Icons.unfold_more_rounded : Icons.lock_outline),
        ),
        child: orderedSelected.isEmpty
            ? Text('Seleccionar...', style: TextStyle(color: Colors.grey[600]))
            : Wrap(
                spacing: 6,
                runSpacing: 5,
                children: orderedSelected
                    .map(
                      (value) => Chip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: const Color(0xFFDDF1F4),
                        side: const BorderSide(color: Color(0xFF86B9C5)),
                        label: Text(
                          value,
                          style: const TextStyle(
                            color: Color(0xFF0D5F78),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
      ),
    );
  }

  int? _gridNumber(Map<String, dynamic> field, String key) {
    final raw = key == 'grid_fila'
        ? _fieldMetaValue(
            field, ['grid_fila', 'grid fila', 'fila', 'fila_grid'])
        : _fieldMetaValue(
            field, ['grid_columna', 'grid columna', 'columna', 'columna_grid']);
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty || text.toUpperCase() == 'NULL') return null;
    final parsed = int.tryParse(text);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  bool _shouldRenderField(Map<String, dynamic> field) {
    final tipo = _normalizeTipo(field['tipo']?.toString());
    final uiType = _uiType(field);
    final campo = field['campo']?.toString() ?? '';
    if (_isSanctionDocumentField(field)) return false;
    if (_isPermissionDocumentField(field) &&
        !_selectedAbsenceRequiresDocument) {
      return false;
    }
    if (_isCompensationWorkedDateField(field) &&
        !_selectedPermissionIsCompensation) {
      return false;
    }
    if (_isPermissionHourField(field) && !_selectedPermissionIsHourly) {
      return false;
    }
    if (_isSanctionPeriodField(field) && _selectedSanctionIsDismissal) {
      return false;
    }
    if (_isDismissalDateField(field) && !_selectedSanctionIsDismissal) {
      return false;
    }
    return _isVisible(field) &&
        !_isAutoFilledDetailField(campo) &&
        tipo != 'hidden_id' &&
        tipo != 'hidden' &&
        uiType != 'hidden_id' &&
        uiType != 'hidden';
  }

  int _fieldOrderNumber(Map<String, dynamic> field) {
    final parsed = int.tryParse(field['orden']?.toString() ?? '');
    if (parsed == null || parsed <= 0) return 999999;
    return parsed;
  }

  List<Widget> _buildFieldRows() {
    final visibleFields = fields.where(_shouldRenderField).toList();

    // Regla correcta de matriz:
    // - grid_fila define la fila visual real.
    // - si grid_fila es NULL, el campo conserva su fila natural por orden.
    // Antes se pintaban primero todas las filas con grid y recién después los campos
    // sin grid; por eso T1..T4 con grid_fila=6 aparecían arriba del formulario.
    final rowBuckets = <int, List<Map<String, dynamic>>>{};
    for (final field in visibleFields) {
      final fila = _gridNumber(field, 'grid_fila') ?? _fieldOrderNumber(field);
      rowBuckets.putIfAbsent(fila, () => <Map<String, dynamic>>[]).add(field);
    }

    final subtitles = _subtitleRows();
    final rows = <Widget>[];
    for (final entry in rowBuckets.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      final rowSubtitles = subtitles[entry.key] ?? const <String>[];
      for (final subtitle in rowSubtitles) {
        rows.add(_subtitleWidget(subtitle));
      }
      final rowFields = entry.value;
      rowFields.sort((a, b) {
        final ca = _gridNumber(a, 'grid_columna') ?? _fieldOrderNumber(a);
        final cb = _gridNumber(b, 'grid_columna') ?? _fieldOrderNumber(b);
        if (ca != cb) return ca.compareTo(cb);
        return _fieldOrderNumber(a).compareTo(_fieldOrderNumber(b));
      });

      rows.add(
        LayoutBuilder(
          builder: (context, constraints) {
            // La matriz decide qué campos comparten fila, pero el ancho real
            // decide cuántas columnas caben. Así se conserva la configuración
            // dinámica sin comprimir cuatro controles dentro de un teléfono.
            const minimumFieldWidth = 220.0;
            const spacing = 12.0;
            final availableColumns = math.max(
              1,
              ((constraints.maxWidth + spacing) / (minimumFieldWidth + spacing))
                  .floor(),
            );
            final columnCount = math.min(rowFields.length, availableColumns);

            if (columnCount == 1) {
              return Column(
                children: [
                  for (final field in rowFields) ...[
                    KeyedSubtree(
                        key: ValueKey("field_${field['campo']}"),
                        child: _fieldWithSubtitle(field)),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            }

            final fieldWidth =
                (constraints.maxWidth - (spacing * (columnCount - 1))) /
                    columnCount;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final field in rowFields)
                  SizedBox(
                    width: fieldWidth,
                    child: KeyedSubtree(
                      key: ValueKey("field_${field['campo']}"),
                      child: _fieldWithSubtitle(field),
                    ),
                  ),
              ],
            );
          },
        ),
      );
      rows.add(const SizedBox(height: 12));
    }

    return rows;
  }

  bool _isScannerUi(String uiType) {
    final t = uiType.trim().toLowerCase();
    return t == 'qr_scan' ||
        t == 'barcode_scan' ||
        t == 'dni_scan' ||
        t == 'scanner' ||
        t == 'scan';
  }

  String _onlyDigits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  String _normalizeScannedCode(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';

    // Si el QR viene como JSON simple, intenta extraer dni/codigo/id sin romper.
    if (value.startsWith('{') && value.endsWith('}')) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          for (final key in [
            'dni',
            'DNI',
            'documento',
            'DOCUMENTO',
            'codigo',
            'CODIGO',
            'codigo_personal',
            'CODIGO_PERSONAL',
            'qr_personal',
            'QR_PERSONAL',
            'id_local'
          ]) {
            final v = decoded[key]?.toString().trim() ?? '';
            if (v.isNotEmpty) return v;
          }
        }
      } catch (_) {}
    }

    // Para código de barras de DNI peruano, normalmente basta con 8 dígitos.
    final digits = _onlyDigits(value);
    if (digits.length == 8) return digits;
    if (digits.length > 8) {
      final dniLike = RegExp(r'(?<!\d)\d{8}(?!\d)').firstMatch(value)?.group(0);
      if (dniLike != null) return dniLike;
      return digits.substring(0, 8);
    }
    return value;
  }

  dynamic _rowValueByCandidates(
      Map<String, dynamic> row, List<String> candidates) {
    final normalized = candidates.map(_normalizarNombreCampo).toSet();
    for (final entry in row.entries) {
      if (normalized.contains(_normalizarNombreCampo(entry.key)))
        return entry.value;
    }
    return null;
  }

  String _personnelWorkerName(Map<String, dynamic> worker) {
    final full = (_rowValueByCandidates(worker, const [
              'APELLIDOS Y NOMBRES',
              'APELLIDOS_NOMBRES',
              'NOMBRE COMPLETO',
              'NOMBRE_COMPLETO',
            ]) ??
            '')
        .toString()
        .trim();
    if (full.isNotEmpty) return full;
    return [
      _rowValueByCandidates(
          worker, const ['APELLIDO_PATERNO', 'APELLIDO PATERNO']),
      _rowValueByCandidates(
          worker, const ['APELLIDO_MATERNO', 'APELLIDO MATERNO']),
      _rowValueByCandidates(worker, const ['NOMBRES', 'NOMBRE']),
    ]
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .join(' ');
  }

  Future<void> _loadPersonnelWorkers() async {
    final byDni = <String, Map<String, dynamic>>{};

    void addWorker(Map<String, dynamic> payload) {
      if (isSoftDeletedAppgtRow(payload)) return;
      final dni = (_rowValueByCandidates(
                  payload, const ['DNI', 'DOCUMENTO', 'NRO_DOCUMENTO']) ??
              '')
          .toString()
          .trim();
      final digits = _onlyDigits(dni);
      if (digits.isEmpty) return;
      byDni[digits] = payload;
    }

    for (final source in const [
      'GH-REGISTRO_PERSONAL_PLANILLA',
      'GH_REGISTRO_PERSONAL_PLANILLA',
      'PERSONAL_PLANILLA',
    ]) {
      final cached = await local.where(
        'local_matrix_rows',
        'source_table = ?',
        [source],
      );
      for (final row in cached) {
        try {
          addWorker(jsonDecode(row['payload_json']?.toString() ?? '{}')
              as Map<String, dynamic>);
        } catch (_) {}
      }
    }

    for (final source in const [
      'GH-REGISTRO_PERSONAL_PLANILLA',
      'GH_REGISTRO_PERSONAL_PLANILLA',
    ]) {
      for (final row in await local.allRecords(table: source)) {
        try {
          addWorker(jsonDecode(row['payload_json']?.toString() ?? '{}')
              as Map<String, dynamic>);
        } catch (_) {}
      }
    }
    personnelWorkers = byDni.values.toList(growable: false)
      ..sort(
          (a, b) => _personnelWorkerName(a).compareTo(_personnelWorkerName(b)));
  }

  List<Map<String, dynamic>> _personnelMatches(String query) {
    final digits = _onlyDigits(query);
    if (digits.isEmpty) return const <Map<String, dynamic>>[];
    if (_selectedPersonnelDni == digits) {
      return const <Map<String, dynamic>>[];
    }
    return personnelWorkers
        .where((worker) {
          final dni = (_rowValueByCandidates(
                      worker, const ['DNI', 'DOCUMENTO', 'NRO_DOCUMENTO']) ??
                  '')
              .toString();
          return _onlyDigits(dni).contains(digits);
        })
        .take(8)
        .toList(growable: false);
  }

  void _selectPersonnelWorker(Map<String, dynamic> worker) {
    final dni = _rowValueByCandidates(
        worker, const ['DNI', 'DOCUMENTO', 'NRO_DOCUMENTO']);
    final name = _personnelWorkerName(worker);
    final position = _rowValueByCandidates(worker, const ['PUESTO', 'CARGO']);
    final area = _rowValueByCandidates(worker, const ['AREA', 'ÁREA']);
    setState(() {
      _selectedPersonnelDni = _onlyDigits(dni?.toString() ?? '');
      _setFirstExistingController(
          const ['DNI', 'DOCUMENTO', 'NRO_DOCUMENTO'], dni);
      _setFirstExistingController(const ['TRABAJADOR'], name);
      _setFirstExistingController(const ['PUESTO', 'CARGO'], position);
      _setFirstExistingController(const ['AREA', 'ÁREA'], area);
    });
    _recalculateDerivedFields();
    _recalculateMatrixDrivenFields();
  }

  Widget _personnelDniFieldWidget(Map<String, dynamic> field) {
    final campo = field['campo']?.toString() ?? '';
    final etiqueta = field['etiqueta']?.toString() ?? campo;
    final requerido = _isEffectivelyRequiredField(field);
    final editable = _isEditable(field);
    final matches = _personnelMatches(controllers[campo]?.text ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controllers[campo],
          focusNode: _focusNodeFor(campo),
          readOnly: !editable,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          decoration: InputDecoration(
            labelText: requerido ? '$etiqueta *' : etiqueta,
            helperText: personnelWorkers.isEmpty
                ? 'Sin personal local. Actualiza datos con internet.'
                : 'Escribe el DNI y selecciona al trabajador.',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.badge_outlined),
          ),
          onChanged: (value) => setState(() {
            if (_selectedPersonnelDni != _onlyDigits(value)) {
              _selectedPersonnelDni = null;
              for (final entry in controllers.entries) {
                final normalized = _normalizarNombreCampo(entry.key);
                if (normalized == 'TRABAJADOR' ||
                    normalized == 'PUESTO' ||
                    normalized == 'CARGO' ||
                    normalized == 'AREA') {
                  entry.value.clear();
                }
              }
            }
          }),
          onSubmitted: (value) {
            final exact = _onlyDigits(value);
            for (final worker in personnelWorkers) {
              final dni = (_rowValueByCandidates(worker,
                          const ['DNI', 'DOCUMENTO', 'NRO_DOCUMENTO']) ??
                      '')
                  .toString();
              if (_onlyDigits(dni) == exact) {
                _selectPersonnelWorker(worker);
                return;
              }
            }
          },
        ),
        if (matches.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            constraints: const BoxConstraints(maxHeight: 190),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FCFA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD8E5DD)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: matches.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final worker = matches[index];
                final dni = (_rowValueByCandidates(worker,
                            const ['DNI', 'DOCUMENTO', 'NRO_DOCUMENTO']) ??
                        '')
                    .toString();
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.badge_outlined,
                      color: Color(0xFF176B87)),
                  title: Text('$dni - ${_personnelWorkerName(worker)}'),
                  onTap: () => _selectPersonnelWorker(worker),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _personnelWorkerFieldWidget(Map<String, dynamic> field) {
    final campo = field['campo']?.toString() ?? '';
    final etiqueta = field['etiqueta']?.toString() ?? campo;
    final requerido = _isEffectivelyRequiredField(field);
    return TextField(
      controller: controllers[campo],
      focusNode: _focusNodeFor(campo),
      readOnly: true,
      decoration: InputDecoration(
        labelText: requerido ? '$etiqueta *' : etiqueta,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.person_outline),
      ),
    );
  }

  Future<Map<String, dynamic>?> _findWorkerByScan(String scannedRaw) async {
    final code = _normalizeScannedCode(scannedRaw);
    if (code.isEmpty) return null;

    for (final worker in personnelWorkers) {
      final dni = (_rowValueByCandidates(
                  worker, const ['DNI', 'DOCUMENTO', 'NRO_DOCUMENTO']) ??
              '')
          .toString();
      if (_onlyDigits(dni) == _onlyDigits(code)) return worker;
    }

    final tableNames = <String>[
      'GH-REGISTRO_PERSONAL_PLANILLA',
      'GH_REGISTRO_PERSONAL_PLANILLA',
      'PERSONAL_PLANILLA',
    ];

    for (final tableName in tableNames) {
      final rows = await local
          .where('local_matrix_rows', 'source_table = ?', [tableName]);
      for (final row in rows) {
        try {
          final payload = jsonDecode(row['payload_json']?.toString() ?? '{}')
              as Map<String, dynamic>;
          final eliminado =
              (_rowValueByCandidates(payload, ['eliminado', 'ELIMINADO'])
                          ?.toString()
                          .toLowerCase() ??
                      '') ==
                  'true';
          final activoRaw =
              _rowValueByCandidates(payload, ['activo', 'ACTIVO']);
          final activo = activoRaw == null ||
              activoRaw.toString().toLowerCase() != 'false';
          if (eliminado || !activo) continue;

          final candidates = [
            _rowValueByCandidates(payload, ['QR_PERSONAL', 'qr_personal']),
            _rowValueByCandidates(
                payload, ['CODIGO_PERSONAL', 'codigo_personal']),
            _rowValueByCandidates(payload,
                ['DNI', 'DOCUMENTO', 'NRO_DOCUMENTO', 'NUMERO_DOCUMENTO']),
            _rowValueByCandidates(payload, ['id_local', 'ID_LOCAL']),
          ]
              .map((e) => e?.toString().trim() ?? '')
              .where((e) => e.isNotEmpty)
              .toList();

          for (final candidate in candidates) {
            if (candidate == code ||
                candidate == scannedRaw.trim() ||
                _onlyDigits(candidate) == _onlyDigits(code)) {
              return payload;
            }
          }
        } catch (_) {}
      }
    }
    return null;
  }

  void _setFirstExistingController(List<String> candidates, dynamic value,
      {bool overwrite = true}) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return;
    final wanted = candidates.map(_normalizarNombreCampo).toSet();
    for (final entry in controllers.entries) {
      if (!wanted.contains(_normalizarNombreCampo(entry.key))) continue;
      if (!overwrite && entry.value.text.trim().isNotEmpty) return;
      entry.value.text = text;
      return;
    }
  }

  Future<void> _applyWorkerScan(String campo, String scannedRaw) async {
    final code = _normalizeScannedCode(scannedRaw);
    if (code.isEmpty) return;

    controllers[campo]?.text = code;
    final worker = await _findWorkerByScan(code);

    if (!mounted) return;
    if (worker == null) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Código escaneado: $code. Trabajador no encontrado en el registro de personal.')),
      );
      _scheduleRecalculationIfNeeded();
      return;
    }

    final dni = _rowValueByCandidates(
        worker, ['DNI', 'DOCUMENTO', 'NRO_DOCUMENTO', 'NUMERO_DOCUMENTO']);
    final nombre = _rowValueByCandidates(worker, [
      'APELLIDOS Y NOMBRES',
      'APELLIDOS_NOMBRES',
      'NOMBRE COMPLETO',
      'NOMBRE_COMPLETO',
      'NOMBRE',
      'NOMBRES',
    ]);
    final puesto = _rowValueByCandidates(worker, ['PUESTO', 'CARGO']);
    final area = _rowValueByCandidates(worker, ['AREA', 'ÁREA']);
    final empresa = _rowValueByCandidates(worker, ['EMPRESA', 'PLANILLA']);
    final foto =
        _rowValueByCandidates(worker, ['FOTO', 'PHOTO_URL', 'FOTO_URL']);

    setState(() {
      _setFirstExistingController(
          ['DNI', 'DOCUMENTO', 'NRO_DOCUMENTO', 'NUMERO_DOCUMENTO'],
          dni ?? code);
      _setFirstExistingController([
        'APELLIDOS Y NOMBRES',
        'APELLIDOS_NOMBRES',
        'NOMBRE COMPLETO',
        'NOMBRE_COMPLETO',
        'NOMBRE',
        'NOMBRES'
      ], nombre);
      _setFirstExistingController(['PUESTO', 'CARGO'], puesto);
      _setFirstExistingController(['AREA', 'ÁREA'], area);
      _setFirstExistingController(['EMPRESA', 'PLANILLA'], empresa);
      _setFirstExistingController(['FOTO', 'PHOTO_URL', 'FOTO_URL'], foto,
          overwrite: false);

      final now = DateTime.now();
      final yyyy = now.year.toString().padLeft(4, '0');
      final mm = now.month.toString().padLeft(2, '0');
      final dd = now.day.toString().padLeft(2, '0');
      final hh = now.hour.toString().padLeft(2, '0');
      final mi = now.minute.toString().padLeft(2, '0');
      _setFirstExistingController(['FECHA', 'FECHA_INGRESO'], '$yyyy-$mm-$dd',
          overwrite: false);
      _setFirstExistingController(['HORA', 'HORA_INGRESO'], '$hh:$mi',
          overwrite: false);
    });

    _recalculateDerivedFields();
    _recalculateMatrixDrivenFields();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Trabajador cargado: ${(nombre ?? dni ?? code).toString()}')),
    );
  }

  Future<void> _openCameraScanner(String campo) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _AppGtScannerPage()),
    );
    if (code == null || code.trim().isEmpty) return;
    await _applyWorkerScan(campo, code);
  }

  Widget _scannerFieldWidget(Map<String, dynamic> field) {
    final campo = field['campo']?.toString() ?? '';
    final etiqueta = field['etiqueta']?.toString() ?? campo;
    final requerido = _isEffectivelyRequiredField(field);
    final editable = _isEditable(field);
    final controller = controllers[campo];

    return TextField(
      controller: controller,
      focusNode: _focusNodeFor(campo),
      readOnly: !editable,
      autofocus: false,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: requerido ? '$etiqueta *' : etiqueta,
        border: const OutlineInputBorder(),
        helperText:
            'Escanea con cámara o con el botón físico del PDA. El lector HID escribe aquí y confirma con Enter.',
        suffixIcon: IconButton(
          tooltip: 'Escanear QR / código de barras',
          onPressed: editable ? () => _openCameraScanner(campo) : null,
          icon: const Icon(Icons.qr_code_scanner),
        ),
      ),
      onSubmitted: editable ? (value) => _applyWorkerScan(campo, value) : null,
      onChanged: (value) {
        // Muchos PDA trabajan como teclado HID y envían ENTER al final. Si el equipo
        // no envía ENTER, igual dejamos el valor en el campo sin forzar búsquedas por cada tecla.
        if (value.endsWith('\n') || value.endsWith('\r')) {
          _applyWorkerScan(campo, value.trim());
        }
      },
    );
  }

  Widget _fieldWidget(Map<String, dynamic> field) {
    final campo = field['campo']?.toString() ?? '';
    final etiqueta = field['etiqueta']?.toString() ?? campo;
    final tipo = _normalizeTipo(field['tipo']?.toString());
    final uiType = _uiType(field);
    final requerido = _isEffectivelyRequiredField(field);
    final editable = _isEditable(field);

    if (!_isVisible(field) ||
        tipo == 'hidden_id' ||
        tipo == 'hidden' ||
        _isRestrictedField(field)) return const SizedBox.shrink();

    if (_isPermissionDocumentField(field) || uiType == 'pdf') {
      return _permissionDocumentWidget(field);
    }

    if (_isPersonnelDniField(field)) return _personnelDniFieldWidget(field);
    if (_isPersonnelWorkerField(field)) {
      return _personnelWorkerFieldWidget(field);
    }

    if (_isScannerUi(uiType)) return _scannerFieldWidget(field);

    if (uiType == 'formula' && _isListFormulaField(field)) {
      final options = _formulaListOptions(field);
      if (options.isEmpty) {
        return TextField(
          controller: controllers[campo],
          focusNode: _focusNodeFor(campo),
          readOnly: true,
          decoration: InputDecoration(
            labelText: requerido ? '$etiqueta *' : etiqueta,
            border: const OutlineInputBorder(),
            helperText:
                'Sin valores disponibles para la condición configurada.',
          ),
        );
      }
      return _buildSearchableDropdownField(field: field, options: options);
    }

    if (uiType == 'multiselect') {
      final literalOptions = _literalDropdownOptions(field);
      if (literalOptions != null) {
        return _buildMultiSelectField(
          field: field,
          options: literalOptions,
          helperText: literalOptions.isEmpty
              ? 'Lista manual vacía en id_campo_dropdown.'
              : null,
        );
      }

      final dynamicCatalog = _dynamicDropdownCatalog(field);
      if (dynamicCatalog != null) {
        final options = _optionsForCatalog(dynamicCatalog);
        return _buildMultiSelectField(
          field: field,
          options: options,
          helperText: options.isEmpty
              ? 'Sin valores locales. Presiona Actualizar con internet.'
              : null,
        );
      }
    }

    final literalDropdownOptions =
        uiType == 'dropdown' ? _literalDropdownOptions(field) : null;
    if (literalDropdownOptions != null) {
      if (literalDropdownOptions.isEmpty) {
        return TextField(
          controller: controllers[campo],
          focusNode: _focusNodeFor(campo),
          readOnly: !editable,
          onChanged: const {'TIPO_PERMISO', 'TIPO_SANCION'}
                  .contains(_normalizarNombreCampo(campo))
              ? (_) => setState(() => _handleHumanResourcesTypeChanged(campo))
              : null,
          decoration: InputDecoration(
            labelText: requerido ? '$etiqueta *' : etiqueta,
            border: const OutlineInputBorder(),
            helperText: 'Lista manual vacía en id_campo_dropdown.',
          ),
        );
      }
      return _buildSearchableDropdownField(
          field: field, options: literalDropdownOptions);
    }

    final dynamicDropdownCatalog =
        uiType == 'dropdown' ? _dynamicDropdownCatalog(field) : null;
    if (dynamicDropdownCatalog != null) {
      final options = _optionsForCatalog(dynamicDropdownCatalog);
      if (options.isEmpty) {
        return TextField(
          controller: controllers[campo],
          focusNode: _focusNodeFor(campo),
          readOnly: !editable,
          onChanged: const {'TIPO_PERMISO', 'TIPO_SANCION'}
                  .contains(_normalizarNombreCampo(campo))
              ? (_) => setState(() => _handleHumanResourcesTypeChanged(campo))
              : null,
          decoration: InputDecoration(
            labelText: requerido ? '$etiqueta *' : etiqueta,
            border: const OutlineInputBorder(),
            helperText:
                'Sin valores locales. Presiona Actualizar con internet.',
          ),
        );
      }
      return _buildSearchableDropdownField(field: field, options: options);
    }

    final turnosDisponibles = _turnosUnicos();
    if (_isTurnoOrLote(campo, etiqueta) && turnosDisponibles.isNotEmpty) {
      final value = controllers[campo]?.text.trim();
      return DropdownButtonFormField<String>(
        value: (value != null &&
                value.isNotEmpty &&
                turnosDisponibles.contains(value))
            ? value
            : null,
        decoration: InputDecoration(
          labelText: requerido ? '$etiqueta *' : etiqueta,
          border: const OutlineInputBorder(),
        ),
        items: turnosDisponibles.map((turno) {
          return DropdownMenuItem<String>(
            value: turno,
            child: Text(turno),
          );
        }).toList(),
        onChanged: editable
            ? (value) {
                setState(() {
                  controllers[campo]?.text = value ?? '';
                  _setVariedadFromTurno(value);
                  _recalculateMatrixDrivenFields();
                });
              }
            : null,
      );
    }

    if (_isVariedad(campo)) {
      return TextField(
        controller: controllers[campo],
        focusNode: _focusNodeFor(campo),
        readOnly: true,
        decoration: InputDecoration(
          labelText: requerido ? '$etiqueta *' : etiqueta,
          border: const OutlineInputBorder(),
        ),
      );
    }

    if (uiType == 'checkbox' || tipo == 'checkbox') {
      final checked = (dropdownValues[campo] ?? 0) == 1;
      return InkWell(
        onTap: editable
            ? () => setState(() {
                  dropdownValues[campo] = checked ? 0 : 1;
                  _recalculateDerivedFields();
                  _recalculateMatrixDrivenFields();
                })
            : null,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: requerido ? '$etiqueta *' : etiqueta,
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: checked,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                onChanged: editable
                    ? (value) => setState(() {
                          dropdownValues[campo] = value == true ? 1 : 0;
                          _recalculateDerivedFields();
                          _recalculateMatrixDrivenFields();
                        })
                    : null,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  checked ? 'Marcado' : 'Sin marcar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (uiType == 'switch') {
      final checked = (dropdownValues[campo] ?? 0) == 1;
      return SwitchListTile(
        value: checked,
        title: Text(requerido ? '$etiqueta *' : etiqueta),
        subtitle: Text(checked ? 'Sí / 1' : 'No / 0'),
        contentPadding: EdgeInsets.zero,
        onChanged: editable
            ? (value) => setState(() {
                  dropdownValues[campo] = value ? 1 : 0;
                  _recalculateDerivedFields();
                  _recalculateMatrixDrivenFields();
                })
            : null,
      );
    }

    if (uiType == 'rating') {
      final raw = controllers[campo]?.text.trim() ?? '';
      final value = (double.tryParse(raw.replaceAll(',', '.')) ?? 0)
          .clamp(0, 5)
          .toDouble();
      return InputDecorator(
        decoration: InputDecoration(
          labelText: requerido ? '$etiqueta *' : etiqueta,
          border: const OutlineInputBorder(),
        ),
        child: Row(
          children: List.generate(5, (index) {
            final selected = value >= index + 1;
            return IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: editable
                  ? () => setState(() {
                        controllers[campo]?.text = '${index + 1}';
                        _recalculateDerivedFields();
                        _recalculateMatrixDrivenFields();
                      })
                  : null,
              icon: Icon(selected ? Icons.star : Icons.star_border),
            );
          }),
        ),
      );
    }

    if (uiType == 'slider') {
      final minValue = 0.0;
      final maxValue = 100.0;
      final raw = controllers[campo]?.text.trim() ?? '';
      final value = (double.tryParse(raw.replaceAll(',', '.')) ?? minValue)
          .clamp(minValue, maxValue)
          .toDouble();
      return InputDecorator(
        decoration: InputDecoration(
          labelText: requerido ? '$etiqueta *' : etiqueta,
          border: const OutlineInputBorder(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_formatNumberText(value, field)),
            Slider(
              value: value,
              min: minValue,
              max: maxValue,
              divisions: 100,
              label: _formatNumberText(value, field),
              onChanged: editable
                  ? (v) => setState(() {
                        controllers[campo]?.text = _formatNumberText(v, field);
                        _recalculateDerivedFields();
                        _recalculateMatrixDrivenFields();
                      })
                  : null,
            ),
          ],
        ),
      );
    }

    if (tipo == 'photo' || uiType == 'photo') {
      final bytes = photoValues[campo] ?? _photoBytesFromController(campo);
      final raw = controllers[campo]?.text.trim() ?? '';
      final hasRemoteImage = bytes == null &&
          (raw.startsWith('http') || EvidenceStorage.isStorageUri(raw));
      return InputDecorator(
        decoration: InputDecoration(
          labelText: requerido ? '$etiqueta *' : etiqueta,
          border: const OutlineInputBorder(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 110,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(8),
              ),
              child: bytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(bytes, fit: BoxFit.cover))
                  : Center(
                      child: Text(hasRemoteImage
                          ? 'Foto existente guardada'
                          : 'Sin foto capturada')),
            ),
            OutlinedButton.icon(
              onPressed: editable ? () => _capturePhotoForField(campo) : null,
              icon: const Icon(Icons.photo_camera),
              label: Text(_hasPhotoInField(campo)
                  ? 'Volver a tomar foto'
                  : 'Tomar foto'),
            ),
          ],
        ),
      );
    }

    if (tipo == 'boolean_int' || uiType == 'boolean_int') {
      return DropdownButtonFormField<int>(
        value: dropdownValues[campo],
        decoration: InputDecoration(
          labelText: requerido ? '$etiqueta *' : etiqueta,
          border: const OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(value: 1, child: Text('Cumple / Sí / 1')),
          DropdownMenuItem(value: 0, child: Text('No cumple / No / 0')),
        ],
        onChanged: editable
            ? (value) => setState(() {
                  dropdownValues[campo] = value;
                  _recalculateMatrixDrivenFields();
                })
            : null,
      );
    }

    if (tipo == 'signature' || uiType == 'signature') {
      final signed = signatureValues[campo] != null;
      return InputDecorator(
        decoration: InputDecoration(
          labelText: requerido ? '$etiqueta *' : etiqueta,
          border: const OutlineInputBorder(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (signed)
              Container(
                height: 96,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    Image.memory(signatureValues[campo]!, fit: BoxFit.contain),
              )
            else
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Sin firma capturada'),
              ),
            OutlinedButton.icon(
              onPressed: editable ? () => _captureSignature(campo) : null,
              icon: const Icon(Icons.draw),
              label: Text(signed ? 'Volver a firmar' : 'Firmar'),
            ),
          ],
        ),
      );
    }

    if (tipo == 'calculated' ||
        tipo == 'readonly' ||
        uiType == 'formula' ||
        uiType == 'lookup') {
      return TextField(
        controller: controllers[campo],
        focusNode: _focusNodeFor(campo),
        readOnly: true,
        decoration: InputDecoration(
          labelText: requerido ? '$etiqueta *' : etiqueta,
          border: const OutlineInputBorder(),
        ),
      );
    }

    return TextField(
      controller: controllers[campo],
      focusNode: _focusNodeFor(campo),
      readOnly: !editable ||
          tipo == 'date' ||
          uiType == 'date' ||
          tipo == 'time' ||
          uiType == 'time',
      minLines: (tipo == 'multiline' || uiType == 'multiline') ? 3 : 1,
      maxLines: (tipo == 'multiline' || uiType == 'multiline') ? 5 : 1,
      keyboardType: _isNumberField(field) || uiType == 'percent'
          ? TextInputType.numberWithOptions(
              decimal: _allowsDecimal(field), signed: true)
          : uiType == 'email'
              ? TextInputType.emailAddress
              : uiType == 'phone'
                  ? TextInputType.phone
                  : uiType == 'url'
                      ? TextInputType.url
                      : TextInputType.text,
      inputFormatters: _inputFormattersForField(field),
      decoration: InputDecoration(
        labelText: requerido ? '$etiqueta *' : etiqueta,
        border: const OutlineInputBorder(),
        suffixIcon: (tipo == 'date' || uiType == 'date')
            ? const Icon(Icons.calendar_month)
            : ((tipo == 'time' || uiType == 'time')
                ? const Icon(Icons.schedule)
                : null),
        errorText:
            _rangeErrorForField(field, controllers[campo]?.text.trim() ?? ''),
      ),
      onChanged: (_) {
        _scheduleRecalculationIfNeeded();
        // El formato_condicional_campo debe reaccionar mientras se escribe.
        if (fields.any(_isListFormulaField) ||
            fields.any((f) => !_isNullLike(_fieldMetaValue(f, [
                  'formato_condicional_campo',
                  'formato condicional campo',
                  'condicion_formato',
                  'condición formato',
                  'formato_condicional'
                ])))) {
          setState(() {});
        }
      },
      onTap: (tipo == 'date' || uiType == 'date')
          ? () async {
              final now = DateTime.now();
              final minDate = DateTime(1900);
              final maxDate = DateTime(now.year + 20);
              final current =
                  DateTime.tryParse(controllers[campo]?.text.trim() ?? '');
              final safeInitialDate =
                  _safeDatePickerInitialDate(current ?? now, minDate, maxDate);
              final picked = await showDatePicker(
                context: context,
                firstDate: minDate,
                lastDate: maxDate,
                initialDate: safeInitialDate,
              );
              if (picked != null) {
                setState(() {
                  controllers[campo]?.text =
                      picked.toIso8601String().substring(0, 10);
                  _recalculateDerivedFields();
                  _recalculateMatrixDrivenFields();
                });
              }
            }
          : (tipo == 'time' || uiType == 'time')
              ? () async {
                  final picked = await showTimePicker(
                      context: context, initialTime: TimeOfDay.now());
                  if (picked != null) {
                    setState(() {
                      final hh = picked.hour.toString().padLeft(2, '0');
                      final mm = picked.minute.toString().padLeft(2, '0');
                      controllers[campo]?.text = '$hh:$mm';
                    });
                  }
                }
              : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatName = widget.format['nombre'] ?? widget.format['id'];
    final hasManyTables = internalTables.length > 1;
    final useWizard = _hasMasterDetailConfig;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFF4F8F7),
      appBar: AppBar(
        toolbarHeight: 52,
        backgroundColor: const Color(0xFF0F5265),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 2,
        leading: widget.onBack != null
            ? IconButton(
                tooltip: 'Volver',
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        title: Text(
          '$formatName',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_photoLimitFromMatrix() > 0)
            IconButton(
              tooltip: 'Fotos',
              onPressed: _openCapturedPhotosSheet,
              icon: Badge(
                label: Text('${_capturedPhotoCount()}'),
                child: const Icon(Icons.photo_camera),
              ),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = math.min(
            ZumacResponsiveLimits.form,
            constraints.maxWidth,
          );
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: contentWidth,
              height: constraints.maxHeight,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                children: [
                  if (useWizard) ...[
                    Card(
                      child: ListTile(
                        leading: Icon(
                            _isHeaderTableRow(_currentFormatTableConfig)
                                ? Icons.assignment_outlined
                                : Icons.format_list_numbered),
                        title: Text(_isHeaderTableRow(_currentFormatTableConfig)
                            ? 'Datos generales'
                            : 'Registro de muestra'),
                        subtitle: Text(_isHeaderTableRow(
                                _currentFormatTableConfig)
                            ? 'Guarda la cabecera para continuar con las muestras.'
                            : 'Muestra ${_wizardCurrentIteration ?? _intFromValue(_currentFormatTableConfig?["iterador_desde"]) ?? 1} de ${_intFromValue(_currentFormatTableConfig?["iterador_hasta"]) ?? "?"}'),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ] else if (hasManyTables) ...[
                    DropdownButtonFormField<String>(
                      value: selectedInternalTableId,
                      decoration: const InputDecoration(
                        labelText: 'Seleccione proceso',
                        border: OutlineInputBorder(),
                      ),
                      items: internalTables.map((row) {
                        final id = row['id']?.toString() ?? '';
                        final name = row['nombre']?.toString() ?? id;
                        return DropdownMenuItem<String>(
                          value: id,
                          child: Text(name),
                        );
                      }).toList(),
                      onChanged: (value) async {
                        setState(() => selectedInternalTableId = value);
                        await loadFieldsForCurrentTable();
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (!useWizard &&
                      _isDetailTableRow(_currentFormatTableConfig) &&
                      _wizardCurrentIteration != null) ...[
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.format_list_numbered),
                        title: Text('Muestra ${_wizardCurrentIteration}'),
                        subtitle: const Text(
                            'Los datos de cabecera se copiarán automáticamente.'),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (loadingFields)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (fields.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                          'No hay campos configurados para esta tabla. Presiona Actualizar matrices.'),
                    )
                  else
                    ..._buildFieldRows(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isPersonalPlanillaForm) ...[
            FloatingActionButton.extended(
              heroTag: 'photocheck_${tableDestino ?? ''}',
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Photocheck'),
                    content: const Text('Generar photochek?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancelar')),
                      FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Aceptar')),
                    ],
                  ),
                );
                if (ok == true) await saveLocal(generarPhotocheck: true);
              },
              tooltip: 'Generar photochek',
              icon: const Icon(Icons.qr_code_2),
              label: const Text('PHOTOCHEK'),
            ),
            const SizedBox(width: 12),
          ],
          FloatingActionButton(
            heroTag: 'save_${tableDestino ?? ''}',
            onPressed: savingLocal ? null : saveLocal,
            tooltip: _isPermissionLeaveForm
                ? 'Guardar solicitud para aprobación en la web'
                : (isOnlineFirstRuntime
                    ? 'Guardar en el sistema'
                    : 'Guardar en el celular'),
            child: savingLocal
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
          ),
        ],
      ),
    );
  }
}

class _LocalFormulaCall {
  final String name;
  final List<String> args;
  final int start;
  final int end;

  _LocalFormulaCall(
      {required this.name,
      required this.args,
      required this.start,
      required this.end});
}

class _StrictMathParser {
  final String input;
  int _pos = 0;

  _StrictMathParser(this.input);

  double parse() {
    final value = _parseExpression();
    _skipSpaces();
    if (_pos < input.length) return double.nan;
    return value;
  }

  double _parseExpression() {
    var value = _parseTerm();
    while (true) {
      _skipSpaces();
      if (_match('+')) {
        value += _parseTerm();
      } else if (_match('-')) {
        value -= _parseTerm();
      } else {
        return value;
      }
    }
  }

  double _parseTerm() {
    var value = _parsePower();
    while (true) {
      _skipSpaces();
      if (_peek('**')) return value;
      if (_match('*')) {
        value *= _parsePower();
      } else if (_match('/')) {
        final divisor = _parsePower();
        value = divisor == 0 ? double.nan : value / divisor;
      } else {
        return value;
      }
    }
  }

  double _parsePower() {
    var value = _parseFactor();
    _skipSpaces();
    if (_matchString('**')) {
      final exponent = _parsePower();
      value = math.pow(value, exponent).toDouble();
    }
    return value;
  }

  double _parseFactor() {
    _skipSpaces();
    if (_match('+')) return _parseFactor();
    if (_match('-')) return -_parseFactor();
    if (_match('(')) {
      final value = _parseExpression();
      if (!_match(')')) return double.nan;
      return value;
    }
    return _parseNumber();
  }

  double _parseNumber() {
    _skipSpaces();
    final start = _pos;
    var dotCount = 0;
    while (_pos < input.length) {
      final c = input[_pos];
      if (RegExp(r'[0-9]').hasMatch(c)) {
        _pos++;
      } else if (c == '.') {
        dotCount++;
        if (dotCount > 1) return double.nan;
        _pos++;
      } else {
        break;
      }
    }
    if (start == _pos) return double.nan;
    return double.tryParse(input.substring(start, _pos)) ?? double.nan;
  }

  bool _match(String char) {
    _skipSpaces();
    if (_pos < input.length && input[_pos] == char) {
      _pos++;
      return true;
    }
    return false;
  }

  bool _matchString(String text) {
    _skipSpaces();
    if (_peek(text)) {
      _pos += text.length;
      return true;
    }
    return false;
  }

  bool _peek(String text) {
    _skipSpaces();
    return input.substring(_pos).startsWith(text);
  }

  void _skipSpaces() {
    while (_pos < input.length && input[_pos].trim().isEmpty) _pos++;
  }
}

class _ExpressionParser {
  final String input;
  int _pos = 0;

  _ExpressionParser(this.input);

  double parse() {
    final value = _parseExpression();
    _skipSpaces();
    return value;
  }

  double _parseExpression() {
    var value = _parseTerm();
    while (true) {
      _skipSpaces();
      if (_match('+')) {
        value += _parseTerm();
      } else if (_match('-')) {
        value -= _parseTerm();
      } else {
        return value;
      }
    }
  }

  double _parseTerm() {
    var value = _parseFactor();
    while (true) {
      _skipSpaces();
      if (_match('*')) {
        value *= _parseFactor();
      } else if (_match('/')) {
        final divisor = _parseFactor();
        value = divisor == 0 ? double.nan : value / divisor;
      } else {
        return value;
      }
    }
  }

  double _parseFactor() {
    _skipSpaces();
    if (_match('+')) return _parseFactor();
    if (_match('-')) return -_parseFactor();
    if (_match('(')) {
      final value = _parseExpression();
      _match(')');
      return value;
    }
    return _parseNumber();
  }

  double _parseNumber() {
    _skipSpaces();
    final start = _pos;
    while (_pos < input.length && RegExp(r'[0-9.]').hasMatch(input[_pos])) {
      _pos++;
    }
    if (start == _pos) return 0;
    return double.tryParse(input.substring(start, _pos)) ?? 0;
  }

  bool _match(String char) {
    _skipSpaces();
    if (_pos < input.length && input[_pos] == char) {
      _pos++;
      return true;
    }
    return false;
  }

  void _skipSpaces() {
    while (_pos < input.length && input[_pos].trim().isEmpty) {
      _pos++;
    }
  }
}

class SignatureDialog extends StatefulWidget {
  const SignatureDialog({super.key});

  @override
  State<SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<SignatureDialog> {
  final List<Offset?> points = [];
  final GlobalKey _paintKey = GlobalKey();

  void _clear() {
    setState(points.clear);
  }

  Future<Uint8List?> _exportPng() async {
    if (points.whereType<Offset>().isEmpty) return null;

    const width = 900.0;
    const height = 360.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), bgPaint);

    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      if (p1 != null && p2 != null) {
        canvas.drawLine(p1, p2, paint);
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _accept() async {
    final png = await _exportPng();
    if (!mounted) return;
    if (png == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe firmar antes de aceptar.')),
      );
      return;
    }
    Navigator.pop(context, png);
  }

  @override
  Widget build(BuildContext context) {
    final hasSignature = points.whereType<Offset>().isNotEmpty;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(24, 6, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5F2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.draw_outlined, color: Color(0xFF147A6E)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Registrar firma',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                SizedBox(height: 2),
                Text('Dibuja dentro del recuadro con el mouse o el dedo.',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF64748B))),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: AspectRatio(
          aspectRatio: 2.5,
          child: Container(
            key: _paintKey,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: hasSignature
                    ? const Color(0xFF62B8A9)
                    : const Color(0xFFCBD5E1),
                width: 1.4,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scaleX = 900.0 / constraints.maxWidth;
                final scaleY = 360.0 / constraints.maxHeight;
                void addPoint(Offset local) {
                  final clamped = Offset(
                    local.dx.clamp(0, constraints.maxWidth),
                    local.dy.clamp(0, constraints.maxHeight),
                  );
                  setState(() => points
                      .add(Offset(clamped.dx * scaleX, clamped.dy * scaleY)));
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) => addPoint(details.localPosition),
                  onPanUpdate: (details) => addPoint(details.localPosition),
                  onPanEnd: (_) => setState(() => points.add(null)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (!hasSignature)
                        const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.gesture,
                                  size: 38, color: Color(0xFFCBD5E1)),
                              SizedBox(height: 8),
                              Text('Firma aquí',
                                  style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      Positioned(
                        left: 32,
                        right: 32,
                        bottom: constraints.maxHeight * .20,
                        child:
                            const Divider(height: 1, color: Color(0xFFD9E2EA)),
                      ),
                      CustomPaint(
                        painter: _SignaturePainter(
                          points,
                          scaleX: constraints.maxWidth / 900.0,
                          scaleY: constraints.maxHeight / 360.0,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
      actions: [
        SizedBox(
          width: double.maxFinite,
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: hasSignature ? _clear : null,
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                label: const Text('Limpiar'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _accept,
                tooltip: 'Guardar firma',
                icon: const Icon(Icons.save, size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  final double scaleX;
  final double scaleY;

  _SignaturePainter(this.points, {required this.scaleX, required this.scaleY});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      if (p1 != null && p2 != null) {
        canvas.drawLine(Offset(p1.dx * scaleX, p1.dy * scaleY),
            Offset(p2.dx * scaleX, p2.dy * scaleY), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}

class _LogicalIndex {
  final int start;
  final int end;
  const _LogicalIndex(this.start, this.end);
}

class _AppGtScannerPage extends StatefulWidget {
  const _AppGtScannerPage();

  @override
  State<_AppGtScannerPage> createState() => _AppGtScannerPageState();
}

class _AppGtScannerPageState extends State<_AppGtScannerPage> {
  bool _returned = false;

  void _returnCode(String code) {
    final clean = code.trim();
    if (_returned || clean.isEmpty) return;
    _returned = true;
    Navigator.of(context).pop(clean);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR / código de barras')),
      body: MobileScanner(
        onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            final raw = barcode.rawValue?.trim() ?? '';
            if (raw.isNotEmpty) {
              _returnCode(raw);
              break;
            }
          }
        },
      ),
    );
  }
}
