import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide ScaffoldMessenger;

import '../../core/widgets/zumac_scaffold_messenger.dart';
import 'package:image_picker/image_picker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/local_db.dart';
import '../../core/services/formula_engine.dart';
import '../../core/services/local_session.dart';

class DynamicViewsPage extends StatefulWidget {
  final Map<String, dynamic> section;
  final Map<String, dynamic>? view;
  final bool embedded;
  final VoidCallback? onPendingChanged;

  const DynamicViewsPage({
    super.key,
    required this.section,
    this.view,
    this.embedded = false,
    this.onPendingChanged,
  });

  @override
  State<DynamicViewsPage> createState() => _DynamicViewsPageState();
}

class _DynamicViewsPageState extends State<DynamicViewsPage> {
  final local = LocalDb.instance;
  final supabase = Supabase.instance.client;
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> views = [];
  Map<String, dynamic>? selectedView;
  List<Map<String, dynamic>> rows = [];
  List<Map<String, dynamic>> flowRules = [];
  final Map<String, String> _fieldAliasToCampo = {};
  String? sortColumn;
  bool sortAscending = true;
  final Map<String, String> filters = {};
  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScroll = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  int currentPage = 0;
  static const int pageSize = 100;


  Future<String?> _activeUserId() async {
    final onlineId = supabase.auth.currentUser?.id;
    if (onlineId != null && onlineId.trim().isNotEmpty) return onlineId;
    final cachedId = await LocalSession().cachedUserId();
    if (cachedId != null && cachedId.trim().isNotEmpty) return cachedId;
    return null;
  }

  List<Map<String, dynamic>> _matrixRowsForLocalCache(String table, List<Map<String, dynamic>> sourceRows) {
    final output = <Map<String, dynamic>>[];
    var index = 0;
    for (final row in sourceRows) {
      final id = (_value(row, 'id') ?? _value(row, 'ID') ?? _value(row, 'id_local') ?? _value(row, 'ID_LOCAL') ?? _value(row, 'codigo') ?? _value(row, 'CODIGO'))?.toString().trim();
      output.add({
        'source_table': table,
        'row_key': (id == null || id.isEmpty) ? '${table}_$index' : id,
        'payload_json': jsonEncode(row),
      });
      index++;
    }
    return output;
  }

  Future<void> _cacheSourceTableRows(String table, List<Map<String, dynamic>> sourceRows) async {
    if (table.trim().isEmpty || sourceRows.isEmpty) return;
    try {
      await local.upsertTable('local_matrix_rows', _matrixRowsForLocalCache(table, sourceRows));
    } catch (_) {
      // El cache offline no debe bloquear la vista online.
    }
  }

  @override
  void initState() {
    super.initState();
    _loadViews();
  }

  @override
  void dispose() {
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  String _txt(dynamic value) => value?.toString().trim() ?? '';

  String _id(dynamic value) => _txt(value).toLowerCase();

  bool _sameId(dynamic a, dynamic b) => _id(a) == _id(b);

  bool _asBool(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'si' || s == 'sí' || s == 'yes';
  }

  bool _rowIsActiveForDynamicView(Map<String, dynamic> row) {
    final eliminado = _value(row, 'eliminado');
    if (_asBool(eliminado, fallback: false)) return false;

    final deletedAt = _txt(_value(row, 'deleted_at'));
    if (deletedAt.isNotEmpty && deletedAt.toLowerCase() != 'null') return false;

    final activo = _value(row, 'activo');
    if (activo != null && !_asBool(activo, fallback: true)) return false;

    return true;
  }

  List<String> _jsonList(dynamic value) {
    if (value == null) return const [];
    if (value is List) return value.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    final raw = value.toString().trim();
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    } catch (_) {}
    var cleaned = raw;
    if (cleaned.startsWith('[') && cleaned.endsWith(']')) cleaned = cleaned.substring(1, cleaned.length - 1);
    return cleaned
        .split(RegExp(r'[,;|]'))
        .map((e) => e.trim())
        .map((e) {
          if ((e.startsWith('"') && e.endsWith('"')) || (e.startsWith("'") && e.endsWith("'"))) {
            return e.substring(1, e.length - 1).trim();
          }
          return e;
        })
        .where((e) => e.isNotEmpty)
        .toList();
  }


  bool _listContainsLoose(dynamic raw, String value) {
    final wanted = _id(value);
    if (wanted.isEmpty) return false;
    return _jsonList(raw).any((e) => _id(e) == wanted);
  }

  Map<String, dynamic>? _flowForRow(Map<String, dynamic> view, Map<String, dynamic> row) {
    final table = _txt(view['tabla_destino']);
    final state = _txt(_value(row, _stateColumn(view))).isEmpty
        ? _txt(view['estado_origen'])
        : _txt(_value(row, _stateColumn(view)));
    for (final f in flowRules) {
      if (_sameId(f['tabla_destino'], table) && _sameId(f['estado_origen'], state) && _asBool(f['activo'], fallback: true)) {
        return f;
      }
    }
    return null;
  }


  Set<String> _allFlowStatesForView(Map<String, dynamic> view) {
    final table = _txt(view['tabla_destino']);
    final states = <String>{};
    for (final f in flowRules) {
      if (!_asBool(f['activo'], fallback: true)) continue;
      if (!_sameId(f['tabla_destino'], table)) continue;
      final origin = _txt(f['estado_origen']);
      final dest = _txt(f['estado_destino']);
      if (origin.isNotEmpty) states.add(_id(origin));
      if (dest.isNotEmpty) states.add(_id(dest));
    }
    final viewOrigin = _txt(view['estado_origen']);
    if (states.isEmpty && viewOrigin.isNotEmpty) states.add(_id(viewOrigin));
    return states;
  }

  Set<String> _actionableOriginStatesForView(Map<String, dynamic> view, List<Map<String, dynamic>> permissions) {
    final table = _txt(view['tabla_destino']);
    final module = _txt(view['modulo']);
    final userFlowPerms = <String>{};
    var canComplete = false;

    for (final p in permissions) {
      if (!_asBool(p['can_complete_pending'])) continue;
      final permModule = _txt(p['modulo']);
      if (!_sameId(_txt(view['seccion']), 'registros_pendientes') &&
          permModule.isNotEmpty && module.isNotEmpty && !_sameId(permModule, module)) continue;
      canComplete = true;
      for (final fp in _jsonList(p['permisos_flujo'])) {
        final normalized = _id(fp);
        if (normalized.isNotEmpty) userFlowPerms.add(normalized);
      }
    }

    if (!canComplete) return <String>{};

    final states = <String>{};
    for (final f in flowRules) {
      if (!_asBool(f['activo'], fallback: true)) continue;
      if (!_sameId(f['tabla_destino'], table)) continue;
      final origin = _txt(f['estado_origen']);
      if (origin.isEmpty) continue;
      final required = _txt(f['permiso_requerido']);
      if (required.isEmpty || userFlowPerms.contains(_id(required))) {
        states.add(_id(origin));
      }
    }

    final viewOrigin = _txt(view['estado_origen']);
    if (states.isEmpty && viewOrigin.isNotEmpty) states.add(_id(viewOrigin));
    return states;
  }

  Set<String> _visibleStatesForView(Map<String, dynamic> view, List<Map<String, dynamic>> permissions) {
    // Para bandejas operativas: mostrar solo los estados que el usuario puede atender.
    // Ejemplo: si tiene revision_supervisor, ve COMPLETO; al pasar a REVISADO desaparece
    // de su bandeja y queda para quien tenga aprobar_jefatura.
    final actionable = _actionableOriginStatesForView(view, permissions);
    if (actionable.isNotEmpty) return actionable;

    // Para usuarios de solo seguimiento, sin can_complete_pending/permisos_flujo:
    // pueden ver todos los estados del proceso siempre que tengan can_view_pending.
    return _allFlowStatesForView(view);
  }

  Future<bool> _canViewPendingForView(Map<String, dynamic> view) async {
    final userId = await _activeUserId();
    if (userId == null || userId.isEmpty) return false;
    final perms = await _localUserPermissions();
    final section = _txt(view['seccion']);
    final module = _txt(view['modulo']);
    return perms.any((p) {
      final canSee = _asBool(p['can_view_pending']) || _asBool(p['can_view']) || _asBool(p['can_complete_pending']);
      if (!canSee) return false;
      if (!_permissionIncludesSection(p, section) && !_sameId(section, 'registros_pendientes')) return false;
      if (_sameId(section, 'registros_pendientes')) return true;
      if (_txt(p['modulo']).isNotEmpty && !_sameId(p['modulo'], module)) return false;
      return true;
    });
  }



  List<String> _permissionSectionIds(dynamic raw) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return const <String>[];

    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      decoded = null;
    }

    Iterable<dynamic> values;
    if (decoded is List) {
      values = decoded;
    } else {
      var cleaned = text;
      if (cleaned.startsWith('[') && cleaned.endsWith(']')) {
        cleaned = cleaned.substring(1, cleaned.length - 1);
      }
      values = cleaned.split(RegExp(r'[,;|]'));
    }

    return values
        .map((e) => e.toString().trim())
        .map((e) {
          var v = e;
          if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
            v = v.substring(1, v.length - 1);
          }
          return v.trim();
        })
        .where((e) => e.isNotEmpty && e.toLowerCase() != 'null')
        .toSet()
        .toList();
  }

  bool _permissionIncludesSection(Map<String, dynamic> permission, String sectionId) {
    final sections = _permissionSectionIds(permission['seccion']);
    return sections.isEmpty || sections.any((s) => _sameId(s, sectionId));
  }

  Future<List<Map<String, dynamic>>> _userPermissions() async {
    final userId = await _activeUserId();
    if (userId == null || userId.isEmpty) return const <Map<String, dynamic>>[];

    final localRows = await local.where('local_permissions', 'user_id = ?', [userId]);

    // Las vistas dinámicas son online, pero los permisos NO pueden depender solo
    // de una consulta remota: con RLS restrictivo Supabase puede devolver 0 filas
    // sin lanzar error. En ese caso usamos el cache local actualizado desde
    // "Actualizar datos". Esto evita falsos "No tienes permiso".
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) return localRows;

    try {
      final rows = await supabase
          .from('PERMISOS_DE_USUARIOS_APPGT')
          .select()
          .eq('user_id', userId)
          .timeout(const Duration(seconds: 5));
      final remoteRows = List<Map<String, dynamic>>.from(rows);
      if (remoteRows.isEmpty) return localRows;

      final merged = <String, Map<String, dynamic>>{};
      for (final row in localRows) {
        final key = _txt(row['id']).isNotEmpty
            ? _txt(row['id'])
            : '${_txt(row['modulo'])}|${_txt(row['formato'])}|${_txt(row['tabla'])}';
        merged[key] = row;
      }
      for (final row in remoteRows) {
        final key = _txt(row['id']).isNotEmpty
            ? _txt(row['id'])
            : '${_txt(row['modulo'])}|${_txt(row['formato'])}|${_txt(row['tabla'])}';
        merged[key] = row;
      }
      return merged.values.toList();
    } on TimeoutException {
      return localRows;
    } catch (_) {
      return localRows;
    }
  }

  Future<List<Map<String, dynamic>>> _localUserPermissions() async {
    final userId = await _activeUserId();
    if (userId == null || userId.isEmpty) return const <Map<String, dynamic>>[];
    return local.where('local_permissions', 'user_id = ?', [userId]);
  }

  bool _canSeeDynamicView(Map<String, dynamic> view, List<Map<String, dynamic>> permissions) {
    final section = _txt(view['seccion']);
    final module = _txt(view['modulo']);
    return permissions.any((permission) {
      final canSee = _asBool(permission['can_view_pending']) ||
          _asBool(permission['can_view']) ||
          _asBool(permission['can_complete_pending']);
      if (!canSee) return false;
      final permModule = _txt(permission['modulo']);
      if (!_permissionIncludesSection(permission, section) && !_sameId(section, 'registros_pendientes')) return false;
      if (_sameId(section, 'registros_pendientes')) return true;
      return permModule.isEmpty || _sameId(permModule, module);
    });
  }

  String _norm(String value) {
    var s = value.trim().toUpperCase();
    const map = {'Á':'A','É':'E','Í':'I','Ó':'O','Ú':'U','Ü':'U','Ñ':'N'};
    map.forEach((k, v) => s = s.replaceAll(k, v));
    return s.replaceAll(RegExp(r'[^A-Z0-9]+'), '_').replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  }

  dynamic _value(Map<String, dynamic> row, String column) {
    final wanted = _norm(column);
    for (final e in row.entries) {
      if (_norm(e.key) == wanted) return e.value;
    }

    // Las vistas dinámicas pueden traer en campos_visibles la etiqueta visible
    // de MATRIZ_CAMPOS_FORMATO_APPGT, mientras que el payload se guarda con el
    // nombre real del campo. Ejemplo: columna 'SUPERVISOR DE INICIO' y payload
    // 'SUPERVISOR INICIO'. Se resuelve por alias antes de pintar la tabla.
    final campoReal = _fieldAliasToCampo[wanted];
    if (campoReal != null && campoReal.trim().isNotEmpty) {
      final realWanted = _norm(campoReal);
      for (final e in row.entries) {
        if (_norm(e.key) == realWanted) return e.value;
      }
    }
    return null;
  }

  String _stateColumn(Map<String, dynamic> view) {
    final configured = _txt(view['filtro_estado']);
    return configured.isEmpty ? 'estado_registro' : configured;
  }

  Future<List<Map<String, dynamic>>> _pendingLocalPayloadsForTable(String table) async {
    final session = LocalSession();
    final pending = await local.pendingRecords(
      userId: await session.cachedUserId(),
      empresaId: await session.cachedEmpresaId(),
    );
    final out = <Map<String, dynamic>>[];
    for (final record in pending) {
      if (!_sameTableName(record['tabla_destino'], table)) continue;
      try {
        final decoded = jsonDecode(record['payload_json']?.toString() ?? '{}');
        if (decoded is Map) {
          final payload = Map<String, dynamic>.from(decoded);
          payload['__pending_local__'] = true;
          out.add(payload);
        }
      } catch (_) {}
    }
    return out;
  }

  String? _originStateForUnsyncedPayload(Map<String, dynamic> view, Map<String, dynamic> payload, List<Map<String, dynamic>> permissions) {
    final table = _txt(view['tabla_destino']);
    final currentState = _txt(_value(payload, _stateColumn(view)));
    if (currentState.isEmpty) return null;

    final userFlowPerms = <String>{};
    var canComplete = false;
    final module = _txt(view['modulo']);
    for (final p in permissions) {
      if (!_asBool(p['can_complete_pending'])) continue;
      final permModule = _txt(p['modulo']);
      if (permModule.isNotEmpty && module.isNotEmpty && !_sameId(permModule, module)) continue;
      canComplete = true;
      for (final fp in _jsonList(p['permisos_flujo'])) {
        final normalized = _id(fp);
        if (normalized.isNotEmpty) userFlowPerms.add(normalized);
      }
    }
    if (!canComplete) return null;

    for (final f in flowRules) {
      if (!_asBool(f['activo'], fallback: true)) continue;
      if (!_sameId(f['tabla_destino'], table)) continue;
      if (!_sameId(f['estado_destino'], currentState)) continue;
      final required = _txt(f['permiso_requerido']);
      if (required.isNotEmpty && !userFlowPerms.contains(_id(required))) continue;
      final origin = _txt(f['estado_origen']);
      if (origin.isNotEmpty) return origin;
    }
    return null;
  }

  Map<String, dynamic> _displayPayloadForUnsyncedRow(Map<String, dynamic> view, Map<String, dynamic> payload, List<Map<String, dynamic>> permissions) {
    final display = Map<String, dynamic>.from(payload);
    final origin = _originStateForUnsyncedPayload(view, display, permissions);
    if (origin != null && origin.isNotEmpty) {
      // El payload pendiente se sincroniza con estado_destino, pero en la bandeja
      // se mantiene como etapa actual hasta que el usuario sincronice. Así puede
      // corregir el dato antes de subirlo.
      display[_stateColumn(view)] = origin;
      display['__pending_local__'] = true;
    }
    return display;
  }


  Map<String, dynamic> _dynamicViewFromLocalRow(Map<String, dynamic> row) {
    final raw = row['payload_json']?.toString().trim() ?? '';
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          // Prioridad al payload completo, pero se rellenan columnas locales por compatibilidad.
          for (final entry in row.entries) {
            map.putIfAbsent(entry.key, () => entry.value);
          }
          return map;
        }
      } catch (_) {}
    }
    return Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> _localDynamicViewsForSection(String sectionId) async {
    final localRows = await local.getAll('local_dynamic_views', orderBy: 'orden');
    return localRows
        .map(_dynamicViewFromLocalRow)
        .where((v) => _sameId(v['seccion'], sectionId) && _asBool(v['activo'], fallback: true))
        .toList();
  }

  Future<List<Map<String, dynamic>>> _localFlowRules() async {
    final matrixRows = await local.where(
      'local_matrix_rows',
      'source_table = ?',
      ['MATRIZ_ESTADOS_FLUJO_APPGT'],
    );
    final out = <Map<String, dynamic>>[];
    for (final row in matrixRows) {
      final raw = row['payload_json']?.toString() ?? '{}';
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) out.add(Map<String, dynamic>.from(decoded));
      } catch (_) {}
    }
    out.sort((a, b) => _asInt(a['orden']).compareTo(_asInt(b['orden'])));
    return out;
  }

  Future<List<Map<String, dynamic>>> _localRowsForSourceTable(String table) async {
    final localRows = await local.where('local_matrix_rows', 'source_table = ?', [table]);
    final out = <Map<String, dynamic>>[];
    for (final row in localRows) {
      final raw = row['payload_json']?.toString() ?? '{}';
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) out.add(Map<String, dynamic>.from(decoded));
      } catch (_) {}
    }
    return out;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  Future<void> _loadViews() async {
    if (mounted) setState(() { loading = true; error = null; });
    final sectionId = _txt(widget.section['id']);

    List<Map<String, dynamic>> localViews = const <Map<String, dynamic>>[];
    List<Map<String, dynamic>> localRules = const <Map<String, dynamic>>[];
    try {
      localViews = await _localDynamicViewsForSection(sectionId);
      localRules = await _localFlowRules();
    } catch (_) {
      localViews = const <Map<String, dynamic>>[];
      localRules = const <Map<String, dynamic>>[];
    }

    // Modo operativo correcto: Registros Pendientes debe abrir con cache local.
    // No se consulta Supabase aquí si ya hay cache, porque en campo/offline eso provoca
    // timeout, pantalla vacía o retrasos. Para traer cambios nuevos se usa Actualizar datos.
    if (localViews.isEmpty || localRules.isEmpty) {
      try {
        final remoteViewsFuture = supabase
            .from('MATRIZ_VISTAS_DINAMICAS_APPGT')
            .select()
            .eq('seccion', sectionId)
            .eq('activo', true)
            .order('orden')
            .timeout(const Duration(seconds: 2));
        final remoteRulesFuture = supabase
            .from('MATRIZ_ESTADOS_FLUJO_APPGT')
            .select()
            .eq('activo', true)
            .order('orden')
            .timeout(const Duration(seconds: 2));

        final remoteViews = List<Map<String, dynamic>>.from(await remoteViewsFuture);
        final remoteRules = List<Map<String, dynamic>>.from(await remoteRulesFuture);
        if (remoteViews.isNotEmpty) localViews = remoteViews;
        if (remoteRules.isNotEmpty) localRules = remoteRules;
      } catch (_) {
        // Offline/timeout/RLS: se usa cache local sin mostrar error bloqueante.
      }
    }

    final permissions = await _localUserPermissions();
    final loadedViews = localViews.where((view) => _canSeeDynamicView(view, permissions)).toList();

    views = loadedViews;
    flowRules = localRules;
    if (widget.view != null) {
      final viewId = _txt(widget.view!['id']);
      selectedView = views.firstWhere(
        (v) => _sameId(v['id'], viewId),
        orElse: () => widget.view!,
      );
    } else {
      selectedView = views.isEmpty ? null : views.first;
    }

    currentPage = 0;
    await _loadRows();
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadRows() async {
    final view = selectedView;
    if (view == null) {
      rows = [];
      return;
    }
    final table = _txt(view['tabla_destino']);
    if (table.isEmpty) {
      rows = [];
      return;
    }

    // Modelo APPGT:
    // La vista dinámica define la bandeja/proceso una sola vez.
    // Los estados que se muestran salen de MATRIZ_ESTADOS_FLUJO_APPGT.
    // Si no hay reglas de flujo, se usa estado_origen de la vista como compatibilidad.
    final canSee = await _canViewPendingForView(view);
    if (!canSee) {
      rows = [];
      return;
    }

    final stateCol = _stateColumn(view);
    final fields = await _fieldsForTable(table);
    _refreshFieldAliases(fields);

    final permissions = await _localUserPermissions();
    final allowedStates = _visibleStatesForView(view, permissions);
    // Local-first: si Actualizar datos ya cacheó la bandeja, abrir pendiente es inmediato
    // y funciona sin internet. Solo se intenta Supabase si no hay cache local para esa tabla.
    List<Map<String, dynamic>> loaded =
        (await _localRowsForSourceTable(table)).where(_rowIsActiveForDynamicView).toList();
    if (loaded.isEmpty) {
      try {
        final connectivity = await Connectivity().checkConnectivity();
        if (connectivity.contains(ConnectivityResult.none)) {
          loaded = const <Map<String, dynamic>>[];
        } else {
          final data = await supabase.from(table).select().limit(1000).timeout(const Duration(seconds: 2));
          final remoteRows = List<Map<String, dynamic>>.from(data);
          await _cacheSourceTableRows(table, remoteRows);
          loaded = remoteRows.where(_rowIsActiveForDynamicView).toList();
        }
      } catch (_) {
        loaded = const <Map<String, dynamic>>[];
      }
    }

    final visibleRemote = allowedStates.isEmpty
        ? loaded
        : loaded.where((row) {
            if (!_rowIsActiveForDynamicView(row)) return false;
            final state = _txt(_value(row, stateCol));
            if (state.isEmpty) return false;
            return allowedStates.contains(_id(state));
          }).toList();

    // Superponer cambios locales pendientes. Importante: si el usuario completó
    // su etapa pero aún no sincronizó, el registro debe seguir visible y editable
    // hasta que la sincronización confirme el cambio en Supabase.
    final pendingLocal = await _pendingLocalPayloadsForTable(table);
    final mergedByIdLocal = <String, Map<String, dynamic>>{};
    for (final row in visibleRemote) {
      final idLocal = _value(row, 'id_local')?.toString() ?? '';
      if (idLocal.isNotEmpty) mergedByIdLocal[idLocal] = row;
    }
    for (final payload in pendingLocal) {
      final idLocal = _value(payload, 'id_local')?.toString() ?? '';
      if (idLocal.isEmpty) continue;
      if (!_rowIsActiveForDynamicView(payload)) continue;
      // Si el pendiente es una edición de flujo, el payload local puede traer solo
      // cambios parciales. Se fusiona con la fila base para no mostrar columnas en blanco.
      final base = mergedByIdLocal[idLocal];
      final mergedPayload = base == null
          ? Map<String, dynamic>.from(payload)
          : (Map<String, dynamic>.from(base)..addAll(payload));
      final display = _displayPayloadForUnsyncedRow(view, mergedPayload, permissions);
      if (!_rowIsActiveForDynamicView(display)) continue;
      final state = _txt(_value(display, stateCol));
      if (allowedStates.isNotEmpty && state.isNotEmpty && !allowedStates.contains(_id(state))) continue;
      mergedByIdLocal[idLocal] = display;
    }

    rows = mergedByIdLocal.values.toList();
  }

  List<String> _columns() {
    final view = selectedView;
    if (view == null) return const [];
    final visible = _jsonList(view['campos_visibles']);
    if (visible.isNotEmpty) return visible;
    final out = <String>{};
    for (final row in rows) {
      out.addAll(row.keys.where((k) => !_norm(k).startsWith('HIDDEN')));
    }
    return out.toList();
  }

  List<Map<String, dynamic>> _visibleRows() {
    final out = rows.where((row) {
      for (final f in filters.entries) {
        final value = _value(row, f.key)?.toString().toLowerCase() ?? '';
        if (!value.contains(f.value.toLowerCase())) return false;
      }
      return true;
    }).toList();
    final col = sortColumn;
    if (col != null) {
      out.sort((a, b) {
        final av = _value(a, col);
        final bv = _value(b, col);
        final an = num.tryParse(av?.toString() ?? '');
        final bn = num.tryParse(bv?.toString() ?? '');
        int result;
        if (an != null && bn != null) {
          result = an.compareTo(bn);
        } else {
          final ad = DateTime.tryParse(av?.toString() ?? '');
          final bd = DateTime.tryParse(bv?.toString() ?? '');
          if (ad != null && bd != null) {
            result = ad.compareTo(bd);
          } else {
            result = (av?.toString() ?? '').toLowerCase().compareTo((bv?.toString() ?? '').toLowerCase());
          }
        }
        return sortAscending ? result : -result;
      });
    }
    return out;
  }

  Future<bool> _canComplete(Map<String, dynamic> view, Map<String, dynamic>? flow) async {
    final userId = await _activeUserId();
    if (userId == null || userId.isEmpty) return false;
    // Offline-first, pero sin quedar amarrado solo a permisos locales si hay sesión online.
    // Esto evita el falso "No tienes permiso" al abrir registros pendientes sin internet
    // después de haber ejecutado Actualizar datos.
    final perms = await _userPermissions();
    final module = _txt(view['modulo']);
    final required = _txt(flow?['permiso_requerido']);

    return perms.any((p) {
      if (!_asBool(p['can_complete_pending'])) return false;

      // La sección decide visibilidad de menú/vista. Para ejecutar una etapa,
      // el permiso fuerte es permisos_flujo + can_complete_pending. No volvemos
      // a bloquear por seccion aquí, porque hay permisos antiguos con seccion
      // null y porque la vista ya fue filtrada antes.
      final permModule = _txt(p['modulo']);
      if (!_sameId(_txt(view['seccion']), 'registros_pendientes') &&
          permModule.isNotEmpty && module.isNotEmpty && !_sameId(permModule, module)) return false;

      if (required.isEmpty) return true;
      return _listContainsLoose(p['permisos_flujo'], required);
    });
  }


  bool _sameTableName(dynamic a, dynamic b) => _norm(_txt(a)) == _norm(_txt(b));

  Future<List<Map<String, dynamic>>> _fieldsForTable(String table) async {
    final all = await local.getAll('local_form_fields', orderBy: 'orden');
    return all.where((f) {
      final destino = _txt(f['tabla_destino']);
      if (destino.isEmpty) return false;
      final active = _asBool(f['activo'], fallback: true);
      return active && _sameTableName(destino, table);
    }).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  void _refreshFieldAliases(List<Map<String, dynamic>> fields) {
    _fieldAliasToCampo.clear();
    for (final f in fields) {
      final campo = _txt(f['campo']);
      if (campo.isEmpty) continue;
      for (final raw in <String>[_txt(f['campo']), _txt(f['etiqueta']), _txt(f['id'])]) {
        final key = _norm(raw);
        if (key.isNotEmpty) _fieldAliasToCampo[key] = campo;
      }
    }
  }

  dynamic _payloadValueByIdentifier(Map<String, dynamic> payload, List<Map<String, dynamic>> fields, String identifier) {
    final wanted = _norm(identifier);
    for (final e in payload.entries) {
      if (_norm(e.key) == wanted) return e.value;
    }
    for (final f in fields) {
      final campo = _txt(f['campo']);
      final etiqueta = _txt(f['etiqueta']);
      final id = _txt(f['id']);
      if (_norm(campo) == wanted || _norm(etiqueta) == wanted || _norm(id) == wanted) {
        return _value(payload, campo);
      }
    }
    return null;
  }

  String _formatFormulaResult(dynamic value) {
    if (value == null) return '';
    if (value is num) {
      final v = value.toDouble();
      if (v.isNaN || v.isInfinite) return '';
      if (v.truncateToDouble() == v) return v.toStringAsFixed(0);
      return v.toStringAsFixed(10).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return value.toString();
  }

  Future<Map<String, dynamic>> _withRecalculatedFormulaFields(Map<String, dynamic> view, Map<String, dynamic> basePayload) async {
    final table = _txt(view['tabla_destino']);
    if (table.isEmpty) return basePayload;
    final fields = await _fieldsForTable(table);
    if (fields.isEmpty) return basePayload;
    final payload = Map<String, dynamic>.from(basePayload);

    // Varias pasadas: cubre fórmulas que dependen de otras fórmulas.
    for (var pass = 0; pass < 3; pass++) {
      for (final field in fields) {
        final uiType = _id(field['tipo_ui']);
        final tipo = _id(field['tipo']);
        if (uiType != 'formula' && uiType != 'lookup' && tipo != 'formula' && tipo != 'calculated') continue;
        final campo = _txt(field['campo']);
        final formula = _txt(field['formula_funcion']);
        if (campo.isEmpty || formula.isEmpty) continue;
        try {
          final engine = FormulaEngine(
            fields: fields,
            matrixRowsByTable: const <String, List<Map<String, dynamic>>>{},
            getValue: (identifier) => _payloadValueByIdentifier(payload, fields, identifier.toString()),
          );
          payload[campo] = _formatFormulaResult(engine.evaluate(formula));
        } catch (_) {
          // No romper el flujo por una fórmula mal configurada.
        }
      }
    }
    return payload;
  }

  Map<String, dynamic> _payloadForLocalQueue(Map<String, dynamic> payload) {
    final cleaned = Map<String, dynamic>.from(payload);
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
      return localOnlyKeys.contains(keyText) || keyText.startsWith('__');
    }).toList();
    for (final key in keysToRemove) {
      cleaned.remove(key);
    }
    return cleaned;
  }

  Future<Map<String, dynamic>> _queuePendingWorkflowUpdate(Map<String, dynamic> view, Map<String, dynamic> row, Map<String, dynamic> changes) async {
    final userId = await _activeUserId();
    if (userId == null || userId.isEmpty) throw Exception('No hay usuario autenticado localmente. Ingresa una vez con internet y actualiza datos.');
    final table = _txt(view['tabla_destino']);
    final idLocal = _value(row, 'id_local')?.toString();
    if (idLocal == null || idLocal.trim().isEmpty) {
      throw Exception('El registro no tiene id_local. No se puede guardar edición offline segura.');
    }
    final base = Map<String, dynamic>.from(row);
    base.addAll(changes);
    base['id_local'] = idLocal;
    final payload = await _withRecalculatedFormulaFields(view, base);
    await local.insertPending({
      'id_local': idLocal,
      'user_id': userId,
      'modulo_id': _txt(view['modulo']),
      'formato_id': _txt(view['nombre_vista']),
      'formato_tabla_id': _txt(view['id']),
      'tabla_destino': table,
      'payload_json': jsonEncode(_payloadForLocalQueue(payload)),
      'estado': 'pendiente',
      'intentos': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    return payload;
  }

  Map<String, dynamic>? _fieldForEditableIdentifier(List<Map<String, dynamic>> fields, String identifier) {
    final wanted = _norm(identifier);
    for (final f in fields) {
      final campo = _txt(f['campo']);
      final etiqueta = _txt(f['etiqueta']);
      final id = _txt(f['id']);
      if (_norm(campo) == wanted || _norm(etiqueta) == wanted || _norm(id) == wanted) {
        return f;
      }
    }
    return null;
  }

  String _campoFromEditable(List<Map<String, dynamic>> fields, String identifier) {
    final field = _fieldForEditableIdentifier(fields, identifier);
    return _txt(field?['campo']).isNotEmpty ? _txt(field?['campo']) : identifier;
  }

  String _labelForField(Map<String, dynamic>? field, String fallback) {
    final etiqueta = _txt(field?['etiqueta']);
    if (etiqueta.isNotEmpty) return etiqueta;
    final campo = _txt(field?['campo']);
    return campo.isNotEmpty ? campo : fallback;
  }

  bool _isSignatureField(Map<String, dynamic>? field) {
    final tipo = _id(field?['tipo']);
    final uiType = _id(field?['tipo_ui']);
    return tipo == 'signature' || uiType == 'signature';
  }

  bool _isFormulaField(Map<String, dynamic>? field) {
    final tipo = _id(field?['tipo']);
    final uiType = _id(field?['tipo_ui']);
    return uiType == 'formula' || uiType == 'lookup' || tipo == 'formula' || tipo == 'calculated';
  }

  bool _isPhotoField(Map<String, dynamic>? field, String fallbackCampo) {
    final tipo = _id(field?['tipo']);
    final uiType = _id(field?['tipo_ui']);
    final campo = _txt(field?['campo']).isNotEmpty ? _txt(field?['campo']) : fallbackCampo;
    final clean = campo.trim();
    return tipo == 'photo' ||
        uiType == 'photo' ||
        RegExp(r'^FOTO\s*\d+$', caseSensitive: false).hasMatch(clean) ||
        RegExp(r'^FOTO_?\d+$', caseSensitive: false).hasMatch(clean) ||
        RegExp(r'^PHOTO_?\d+$', caseSensitive: false).hasMatch(clean);
  }

  String _imageDataUrl(Uint8List bytes) => 'data:image/jpeg;base64,${base64Encode(bytes)}';

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

  bool _truthyFormulaResult(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim();
    if (text.isEmpty) return false;
    final upper = text.toUpperCase();
    return !(upper == '0' || upper == 'FALSE' || upper == 'FALSO' || upper == 'NO' || upper == 'NULL');
  }

  String _fieldLabelByIdentifier(List<Map<String, dynamic>> fields, String identifier) {
    final field = _fieldForEditableIdentifier(fields, identifier);
    return _labelForField(field, identifier);
  }

  String? _photoBlockedMessageForWorkflow(
    Map<String, dynamic>? field,
    List<Map<String, dynamic>> fields,
    Map<String, dynamic> payload,
  ) {
    if (field == null) return null;
    // Regla correcta: photo_depende_de NO bloquea por sí solo.
    // Solo sirve para mostrar un mensaje amigable cuando formula_funcion no permite tomar foto.
    // Si formula_funcion está vacío, la cámara debe abrir normalmente.
    final deps = _parseBracketFieldList(_txt(field['photo_depende_de']));
    final formula = _txt(field['formula_funcion']);
    if (formula.isEmpty) return null;

    final labels = deps.map((e) => _fieldLabelByIdentifier(fields, e)).where((e) => e.trim().isNotEmpty).toList();
    try {
      final engine = FormulaEngine(
        fields: fields,
        matrixRowsByTable: const <String, List<Map<String, dynamic>>>{},
        getValue: (identifier) => _payloadValueByIdentifier(payload, fields, identifier.toString()),
      );
      final ok = engine.evaluateCondition(formula);
      if (!ok) {
        return labels.isEmpty ? 'No se cumple la condición para tomar esta foto.' : 'Completa los campos: ${labels.join(', ')}';
      }
    } catch (_) {
      return labels.isEmpty ? 'No se pudo validar la condición de la foto.' : 'Completa los campos: ${labels.join(', ')}';
    }
    return null;
  }

  Future<void> _showWorkflowPhotoBlockedMessage(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Falta completar información'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  String _signatureDataUrl(Uint8List bytes) => 'data:image/png;base64,${base64Encode(bytes)}';

  Future<Uint8List?> _captureWorkflowSignature() {
    return showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _WorkflowSignatureDialog(),
    );
  }

  Future<Map<String, dynamic>> _recalculateWorkflowPreview(
    Map<String, dynamic> view,
    List<Map<String, dynamic>> fields,
    Map<String, TextEditingController> controllers,
    Map<String, dynamic> basePayload,
  ) async {
    final payload = Map<String, dynamic>.from(basePayload);
    for (final entry in controllers.entries) {
      payload[entry.key] = entry.value.text.trim();
    }
    // Múltiples pasadas para fórmulas dependientes de otras fórmulas.
    for (var pass = 0; pass < 3; pass++) {
      for (final field in fields) {
        if (!_isFormulaField(field)) continue;
        final campo = _txt(field['campo']);
        final formula = _txt(field['formula_funcion']);
        if (campo.isEmpty || formula.isEmpty) continue;
        try {
          final engine = FormulaEngine(
            fields: fields,
            matrixRowsByTable: const <String, List<Map<String, dynamic>>>{},
            getValue: (identifier) => _payloadValueByIdentifier(payload, fields, identifier.toString()),
          );
          payload[campo] = _formatFormulaResult(engine.evaluate(formula));
        } catch (_) {}
      }
    }
    return payload;
  }

  Future<void> _openEditDialog(Map<String, dynamic> row) async {
    final view = selectedView;
    if (view == null) return;
    final flow = _flowForRow(view, row);
    final editableRaw = _jsonList(flow?['campos_editables']).isNotEmpty
        ? _jsonList(flow?['campos_editables'])
        : _jsonList(view['campos_editables']);
    final pendingRaw = _jsonList(flow?['campos_obligatorios']).isNotEmpty
        ? _jsonList(flow?['campos_obligatorios'])
        : _jsonList(view['campos_pendientes']);
    final canComplete = await _canComplete(view, flow);
    if (editableRaw.isEmpty || !canComplete) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No tienes permiso para completar esta etapa.')));
      }
      return;
    }

    final fields = await _fieldsForTable(_txt(view['tabla_destino']));
    final editableCampos = editableRaw.map((e) => _campoFromEditable(fields, e)).toList();
    final pendingCampos = pendingRaw.map((e) => _campoFromEditable(fields, e)).toList();
    final controllers = <String, TextEditingController>{};
    final signatureValues = <String, Uint8List?>{};
    final signatureExisting = <String, String>{};
    final photoValues = <String, Uint8List?>{};
    final photoExisting = <String, String>{};

    for (final c in editableCampos) {
      final field = _fieldForEditableIdentifier(fields, c);
      if (_isSignatureField(field)) {
        final existing = _value(row, c)?.toString() ?? '';
        if (existing.trim().isNotEmpty) signatureExisting[c] = existing;
      } else if (_isPhotoField(field, c)) {
        final existing = _value(row, c)?.toString() ?? '';
        if (existing.trim().isNotEmpty) photoExisting[c] = existing;
      } else {
        controllers[c] = TextEditingController(text: _value(row, c)?.toString() ?? '');
      }
    }

    Future<void> recalcPreview(StateSetter setDialogState) async {
      final preview = await _recalculateWorkflowPreview(view, fields, controllers, row);
      if (!mounted) return;
      setDialogState(() {
        for (final c in editableCampos) {
          final field = _fieldForEditableIdentifier(fields, c);
          if (!_isFormulaField(field)) continue;
          final controller = controllers[c];
          if (controller == null) continue;
          final newText = _value(preview, c)?.toString() ?? '';
          if (controller.text != newText) {
            controller.value = TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: newText.length),
            );
          }
        }
      });
    }

    String photoGroupName(Map<String, dynamic>? field, String fallbackCampo) {
      final raw = _txt(field?['lista_destino_photo']);
      if (raw.isNotEmpty) return raw;
      return _labelForField(field, fallbackCampo);
    }

    int photoGroupOrder(Map<String, dynamic>? field, String fallbackCampo) {
      final raw = field?['orden_lista_photo'] ?? field?['orden lista photo'] ?? field?['ordenListaPhoto'];
      final parsed = int.tryParse(raw?.toString() ?? '');
      if (parsed != null) return parsed;
      final idx = editableCampos.indexOf(fallbackCampo);
      return idx < 0 ? 999999 : idx;
    }

    // PENDIENTES: aquí manda exclusivamente MATRIZ_ESTADOS_FLUJO_APPGT.campos_editables.
    // No se deben mostrar otros campos foto de la matriz general, porque cada etapa del flujo
    // define qué campos se habilitan. Ejemplo: si la etapa trae solo FOTO2, no debe aparecer FOTO1.
    final photoEditableCampos = editableCampos
        .where((c) => _isPhotoField(_fieldForEditableIdentifier(fields, c), c))
        .toList();
    final photoGroups = <String, List<String>>{};
    for (final c in photoEditableCampos) {
      final field = _fieldForEditableIdentifier(fields, c);
      final groupName = photoGroupName(field, c);
      photoGroups.putIfAbsent(groupName, () => <String>[]).add(c);
    }
    final orderedPhotoGroups = photoGroups.entries.toList()
      ..sort((a, b) {
        final oa = a.value
            .map((c) => photoGroupOrder(_fieldForEditableIdentifier(fields, c), c))
            .fold<int>(999999, (prev, v) => v < prev ? v : prev);
        final ob = b.value
            .map((c) => photoGroupOrder(_fieldForEditableIdentifier(fields, c), c))
            .fold<int>(999999, (prev, v) => v < prev ? v : prev);
        if (oa != ob) return oa.compareTo(ob);
        return a.key.toUpperCase().compareTo(b.key.toUpperCase());
      });

    Future<void> captureWorkflowPhoto(String c, StateSetter setDialogState) async {
      final field = _fieldForEditableIdentifier(fields, c);
      final payload = Map<String, dynamic>.from(row);
      for (final e in controllers.entries) {
        payload[e.key] = e.value.text.trim();
      }
      for (final e in photoExisting.entries) {
        if (e.value.trim().isNotEmpty) payload[e.key] = e.value;
      }
      for (final e in photoValues.entries) {
        if (e.value != null) payload[e.key] = _imageDataUrl(e.value!);
      }
      final blocked = _photoBlockedMessageForWorkflow(field, fields, payload);
      if (blocked != null) {
        await _showWorkflowPhotoBlockedMessage(blocked);
        return;
      }
      final file = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 55, maxWidth: 1024, maxHeight: 1024);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setDialogState(() => photoValues[c] = bytes);
    }

    Future<void> openWorkflowPhotoGroupDialog(String groupName, List<String> groupCampos, StateSetter parentSetState) async {
      await showDialog<void>(
        context: context,
        builder: (photoContext) => StatefulBuilder(
          builder: (photoContext, photoSetState) {
            final completed = groupCampos.where((c) => photoValues[c] != null || (photoExisting[c]?.trim().isNotEmpty == true)).length;
            return AlertDialog(
              title: Text(groupName),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Fotos capturadas ($completed/${groupCampos.length})'),
                    const SizedBox(height: 10),
                    for (final c in groupCampos)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Builder(builder: (_) {
                          final field = _fieldForEditableIdentifier(fields, c);
                          final label = _labelForField(field, c);
                          final bytes = photoValues[c];
                          final existing = photoExisting[c]?.trim() ?? '';
                          final hasExisting = existing.isNotEmpty;
                          return InputDecorator(
                            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (bytes != null)
                                  Container(
                                    height: 110,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(8)),
                                    child: Image.memory(bytes, fit: BoxFit.contain),
                                  )
                                else
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(hasExisting ? 'Foto existente guardada' : 'Sin foto capturada'),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await captureWorkflowPhoto(c, (fn) {
                                      photoSetState(fn);
                                      parentSetState(() {});
                                    });
                                  },
                                  icon: const Icon(Icons.photo_camera),
                                  label: Text(bytes != null || hasExisting ? 'Reemplazar foto' : 'Tomar foto'),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                  ],
                ),
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(photoContext), child: const Text('Cerrar'))],
            );
          },
        ),
      );
    }

    Widget buildPendingInput(String c, StateSetter setDialogState) {
      final field = _fieldForEditableIdentifier(fields, c);
      final label = _labelForField(field, c);
      if (_isSignatureField(field)) {
        final bytes = signatureValues[c];
        final hasExisting = signatureExisting[c]?.trim().isNotEmpty == true;
        return InputDecorator(
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (bytes != null)
                Container(
                  height: 76,
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(8)),
                  child: Image.memory(bytes, fit: BoxFit.contain),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(hasExisting ? 'Firma existente guardada' : 'Sin firma capturada'),
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  final bytes = await _captureWorkflowSignature();
                  if (bytes == null) return;
                  setDialogState(() => signatureValues[c] = bytes);
                },
                icon: const Icon(Icons.draw),
                label: Text(bytes != null || hasExisting ? 'Volver a firmar' : 'Firmar'),
              ),
            ],
          ),
        );
      }
      final readOnly = _isFormulaField(field);
      return TextField(
        controller: controllers[c],
        readOnly: readOnly,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        keyboardType: _id(field?['tipo']) == 'numeric' || _id(field?['tipo']) == 'integer'
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        onChanged: (_) => recalcPreview(setDialogState),
      );
    }

    int? pendingGridRow(String c) {
      final f = _fieldForEditableIdentifier(fields, c);
      final raw = f?['grid_fila_pendientes'] ?? f?['grid fila pendientes'] ?? f?['gridFilaPendientes'];
      final n = int.tryParse(raw?.toString().trim() ?? '');
      return n != null && n > 0 ? n : null;
    }

    int? pendingGridCol(String c) {
      final f = _fieldForEditableIdentifier(fields, c);
      final raw = f?['grid_columna_pendientes'] ?? f?['grid columna pendientes'] ?? f?['gridColumnaPendientes'];
      final n = int.tryParse(raw?.toString().trim() ?? '');
      return n != null && n > 0 ? n : null;
    }

    List<Widget> buildPendingFormWidgets(StateSetter setDialogState) {
      final normalCampos = editableCampos
          .where((c) => !_isPhotoField(_fieldForEditableIdentifier(fields, c), c))
          .toList();
      final anyGrid = normalCampos.any((c) => pendingGridRow(c) != null && pendingGridCol(c) != null);
      if (!anyGrid) {
        return normalCampos
            .map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: buildPendingInput(c, setDialogState),
                ))
            .toList();
      }

      final result = <Widget>[];
      final placed = <String>{};
      final rowsMap = <int, List<String>>{};
      for (final c in normalCampos) {
        final r = pendingGridRow(c);
        final col = pendingGridCol(c);
        if (r == null || col == null) continue;
        rowsMap.putIfAbsent(r, () => <String>[]).add(c);
        placed.add(c);
      }
      final sortedRows = rowsMap.keys.toList()..sort();
      for (final r in sortedRows) {
        final rowCampos = rowsMap[r]!..sort((a, b) => (pendingGridCol(a) ?? 999).compareTo(pendingGridCol(b) ?? 999));
        result.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Si la matriz define grid_fila_pendientes/grid_columna_pendientes, se respeta también en móvil.
              if (rowCampos.length == 1) {
                return Column(
                  children: rowCampos
                      .map((c) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: buildPendingInput(c, setDialogState),
                          ))
                      .toList(),
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < rowCampos.length; i++) ...[
                    Expanded(child: buildPendingInput(rowCampos[i], setDialogState)),
                    if (i < rowCampos.length - 1) const SizedBox(width: 8),
                  ],
                ],
              );
            },
          ),
        ));
      }
      for (final c in normalCampos.where((c) => !placed.contains(c))) {
        result.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: buildPendingInput(c, setDialogState),
        ));
      }
      return result;
    }

    Future<void> openWorkflowPhotoGroupsListDialog(StateSetter parentSetState) async {
      if (orderedPhotoGroups.isEmpty) return;
      if (orderedPhotoGroups.length == 1) {
        await openWorkflowPhotoGroupDialog(orderedPhotoGroups.first.key, orderedPhotoGroups.first.value, parentSetState);
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (photoContext) => AlertDialog(
          title: const Text('Fotos'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in orderedPhotoGroups)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Colors.black12)),
                      leading: const Icon(Icons.photo_camera),
                      title: Text(entry.key),
                      subtitle: Text('${entry.value.where((c) => photoValues[c] != null || (photoExisting[c]?.trim().isNotEmpty == true)).length}/${entry.value.length} foto(s)'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        Navigator.pop(photoContext);
                        await openWorkflowPhotoGroupDialog(entry.key, entry.value, parentSetState);
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(photoContext), child: const Text('Cerrar'))],
        ),
      );
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final media = MediaQuery.of(context);
          final maxDialogHeight = media.size.height * 0.78;
          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            titlePadding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
            contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            title: Row(
              children: [
                Expanded(child: Text(_txt(view['nombre_vista']).isEmpty ? 'Editar pendiente' : _txt(view['nombre_vista']))),
                if (orderedPhotoGroups.isNotEmpty)
                  IconButton(
                    tooltip: 'Fotos',
                    onPressed: () => openWorkflowPhotoGroupsListDialog(setDialogState),
                    icon: Badge(
                      label: Text('${photoEditableCampos.where((c) => photoValues[c] != null || (photoExisting[c]?.trim().isNotEmpty == true)).length}'),
                      child: const Icon(Icons.photo_camera),
                    ),
                  ),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: maxDialogHeight,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: buildPendingFormWidgets(setDialogState),
                ),
              ),
            ),
            actions: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () async {
                      final payload = <String, dynamic>{};
                      for (final e in controllers.entries) {
                        payload[e.key] = e.value.text.trim().isEmpty ? null : e.value.text.trim();
                      }
                      for (final c in editableCampos) {
                        final field = _fieldForEditableIdentifier(fields, c);
                        if (!_isSignatureField(field)) continue;
                        final bytes = signatureValues[c];
                        if (bytes != null) {
                          payload[c] = _signatureDataUrl(bytes);
                        } else if (signatureExisting[c]?.trim().isNotEmpty == true) {
                          payload[c] = signatureExisting[c];
                        } else {
                          payload[c] = null;
                        }
                      }
                      for (final c in editableCampos) {
                        final field = _fieldForEditableIdentifier(fields, c);
                        if (!_isPhotoField(field, c)) continue;
                        final bytes = photoValues[c];
                        if (bytes != null) {
                          payload[c] = _imageDataUrl(bytes);
                        } else if (photoExisting[c]?.trim().isNotEmpty == true) {
                          payload[c] = photoExisting[c];
                        } else {
                          payload[c] = null;
                        }
                      }
                      final recalculated = await _recalculateWorkflowPreview(view, fields, controllers, {...row, ...payload});
                      for (final c in editableCampos) {
                        final field = _fieldForEditableIdentifier(fields, c);
                        if (_isFormulaField(field)) payload[c] = _value(recalculated, c);
                      }

                      // MATRIZ_ESTADOS_FLUJO_APPGT.campos_obligatorios manda en pendientes.
                      // No depende de requiere_todos_campos: si el flujo declara obligatorios,
                      // no se permite guardar hasta que todos tengan valor, incluidas fotos y firmas.
                      final missingRequired = <String>[];
                      for (final c in pendingCampos) {
                        final field = _fieldForEditableIdentifier(fields, c);
                        dynamic val;
                        if (_isPhotoField(field, c)) {
                          val = photoValues[c] != null
                              ? '__photo_bytes__'
                              : (payload.containsKey(c) ? payload[c] : (_value(row, c) ?? photoExisting[c]));
                        } else if (_isSignatureField(field)) {
                          val = signatureValues[c] != null
                              ? '__signature_bytes__'
                              : (payload.containsKey(c) ? payload[c] : (_value(row, c) ?? signatureExisting[c]));
                        } else {
                          val = payload.containsKey(c) ? payload[c] : _value(row, c);
                        }
                        if (val == null || val.toString().trim().isEmpty) {
                          missingRequired.add(_labelForField(field, c));
                        }
                      }
                      if (missingRequired.isNotEmpty) {
                        await showDialog<void>(
                          context: context,
                          useRootNavigator: true,
                          barrierDismissible: true,
                          builder: (alertContext) => AlertDialog(
                            title: const Text('Falta completar información'),
                            content: SingleChildScrollView(
                              child: Text(
                                'Para guardar este pendiente, primero completa estos campos:\n\n'
                                '${missingRequired.map((e) => '• $e').join('\n')}',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(alertContext, rootNavigator: true).pop(),
                                child: const Text('Entendido'),
                              ),
                            ],
                          ),
                        );
                        return;
                      }

                      if (canComplete) payload['__complete__'] = true;
                      Navigator.pop(context, payload);
                    },
                    tooltip: 'Guardar',
                    icon: const Icon(Icons.save),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    for (final c in controllers.values) { c.dispose(); }
    if (result == null) return;
    final complete = result.remove('__complete__') == true;
    // La validación de campos_obligatorios se ejecuta dentro del modal antes de cerrar,
    // para que el usuario no pierda contexto ni se refresque la vista si falta completar algo.
    if (complete) result[_stateColumn(view)] = _txt(flow?['estado_destino']).isNotEmpty ? _txt(flow?['estado_destino']) : _txt(view['estado_destino']);
    try {
      final updatedPayload = await _queuePendingWorkflowUpdate(view, row, result);
      final updatedIdLocal = _value(updatedPayload, 'id_local')?.toString();
      if (updatedIdLocal != null && updatedIdLocal.isNotEmpty) {
        final permissions = await _userPermissions();
        final displayPayload = _displayPayloadForUnsyncedRow(view, updatedPayload, permissions);
        final index = rows.indexWhere((r) => _value(r, 'id_local')?.toString() == updatedIdLocal);
        if (index >= 0) {
          rows[index] = displayPayload;
        } else {
          rows.add(displayPayload);
        }
      }
      widget.onPendingChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cambio guardado localmente. Sincroniza con internet para subirlo.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      return;
    }
    if (mounted) setState(() {});
  }

  Widget _buildViewTabs() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final v in views) {
      grouped.putIfAbsent(_txt(v['modulo']).isEmpty ? 'General' : _txt(v['modulo']), () => []).add(v);
    }
    return SizedBox(
      width: 260,
      child: ListView(
        children: [
          for (final entry in grouped.entries)
            ExpansionTile(
              initiallyExpanded: true,
              title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700)),
              children: entry.value.map((v) => ListTile(
                dense: true,
                selected: selectedView?['id']?.toString() == v['id']?.toString(),
                title: Text(_txt(v['nombre_vista']).isEmpty ? _txt(v['id']) : _txt(v['nombre_vista'])),
                onTap: () async {
                  setState(() { selectedView = v; loading = true; filters.clear(); sortColumn = null; currentPage = 0; });
                  try { await _loadRows(); } finally { if (mounted) setState(() => loading = false); }
                },
              )).toList(),
            ),
        ],
      ),
    );
  }


  String _viewType() => _id(selectedView?['tipo_vista']).isEmpty ? 'tabla' : _id(selectedView?['tipo_vista']);

  List<Map<String, dynamic>> _pagedRows(List<Map<String, dynamic>> source) {
    final start = currentPage * pageSize;
    if (start >= source.length) return const <Map<String, dynamic>>[];
    final end = (start + pageSize) > source.length ? source.length : start + pageSize;
    return source.sublist(start, end);
  }

  num _numericValue(dynamic value) => num.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;

  String _firstNumericColumn(List<String> columns, List<Map<String, dynamic>> data) {
    for (final c in columns) {
      if (data.any((r) => num.tryParse(_value(r, c)?.toString().replaceAll(',', '.') ?? '') != null)) return c;
    }
    return columns.isEmpty ? '' : columns.first;
  }

  Widget _summaryCard(String title, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 32),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          ]),
        ]),
      ),
    );
  }

  Widget _cardsView(List<String> columns, List<Map<String, dynamic>> data) {
    final paged = _pagedRows(data);
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: paged.length,
      itemBuilder: (_, index) {
        final row = paged[index];
        return Card(
          child: ListTile(
            title: Text(columns.isEmpty ? 'Registro' : (_value(row, columns.first)?.toString() ?? 'Registro')),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: columns.skip(1).take(6).map((c) => Text('$c: ${_value(row, c) ?? ''}')).toList(),
            ),
            onTap: () => _openEditDialog(row),
          ),
        );
      },
    );
  }

  Widget _metricView(List<String> columns, List<Map<String, dynamic>> data) {
    final type = _viewType();
    final col = _firstNumericColumn(columns, data);
    final nums = data.map((r) => _numericValue(_value(r, col))).toList();
    num value;
    IconData icon;
    String title;
    switch (type) {
      case 'suma':
      case 'sum':
        value = nums.fold<num>(0, (a, b) => a + b); title = 'Suma ${col.isEmpty ? '' : col}'; icon = Icons.functions; break;
      case 'promedio':
      case 'average':
        value = nums.isEmpty ? 0 : nums.fold<num>(0, (a, b) => a + b) / nums.length; title = 'Promedio ${col.isEmpty ? '' : col}'; icon = Icons.stacked_line_chart; break;
      case 'maximo':
      case 'max':
        value = nums.isEmpty ? 0 : nums.reduce((a, b) => a > b ? a : b); title = 'Máximo ${col.isEmpty ? '' : col}'; icon = Icons.arrow_upward; break;
      case 'minimo':
      case 'min':
        value = nums.isEmpty ? 0 : nums.reduce((a, b) => a < b ? a : b); title = 'Mínimo ${col.isEmpty ? '' : col}'; icon = Icons.arrow_downward; break;
      default:
        value = data.length; title = 'Registros'; icon = Icons.countertops_outlined; break;
    }
    final text = value is int || value == value.truncateToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
    return Center(child: _summaryCard(title, text, icon));
  }

  Widget _unsupportedView(List<String> columns, List<Map<String, dynamic>> data) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text('Tipo de vista "${_txt(selectedView?['tipo_vista'])}" reconocido como vista tabular por ahora.'),
      ),
      Expanded(child: _tableBody(columns, data)),
    ]);
  }

  Widget _paginationBar(int total) {
    final pages = total == 0 ? 1 : ((total - 1) ~/ pageSize) + 1;
    final start = total == 0 ? 0 : currentPage * pageSize + 1;
    final end = (currentPage * pageSize + pageSize) > total ? total : currentPage * pageSize + pageSize;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        Text('Mostrando $start-$end de $total'),
        const Spacer(),
        IconButton(onPressed: currentPage <= 0 ? null : () => setState(() => currentPage--), icon: const Icon(Icons.chevron_left)),
        Text('${currentPage + 1} / $pages'),
        IconButton(onPressed: currentPage >= pages - 1 ? null : () => setState(() => currentPage++), icon: const Icon(Icons.chevron_right)),
      ]),
    );
  }

  Widget _tableBody(List<String> columns, List<Map<String, dynamic>> data) {
    final paged = _pagedRows(data);
    return Scrollbar(
      controller: _horizontalScroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _horizontalScroll,
        scrollDirection: Axis.horizontal,
        child: Scrollbar(
          controller: _verticalScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _verticalScroll,
            child: DataTable(
              columns: columns.map((c) => DataColumn(label: Row(mainAxisSize: MainAxisSize.min, children: [
                InkWell(onTap: () => setState(() { if (sortColumn == c) { sortAscending = !sortAscending; } else { sortColumn = c; sortAscending = true; } currentPage = 0; }), child: Text(c, style: const TextStyle(fontWeight: FontWeight.bold))),
                IconButton(icon: const Icon(Icons.filter_alt_outlined, size: 16), onPressed: () => _filterColumn(c)),
              ]))).toList(),
              rows: paged.map((r) => DataRow(
                onSelectChanged: (_) => _openEditDialog(r),
                cells: columns.map((c) => DataCell(SizedBox(width: 150, child: Text(_value(r, c)?.toString() ?? '', overflow: TextOverflow.ellipsis)))).toList(),
              )).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _table() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Text(error!, style: const TextStyle(color: Colors.red)));
    if (selectedView == null) return const Center(child: Text('No hay vistas dinámicas para esta sección.'));
    final columns = _columns();
    final data = _visibleRows();
    if (columns.isEmpty) return const Center(child: Text('La vista no tiene columnas visibles.'));

    final type = _viewType();
    Widget content;
    switch (type) {
      case 'tabla':
      case 'table':
        content = _tableBody(columns, data);
        break;
      case 'lista':
      case 'list':
      case 'cards':
      case 'tarjetas':
        content = _cardsView(columns, data);
        break;
      case 'indicador':
      case 'indicadores':
      case 'kpi':
      case 'kpis':
      case 'conteo':
      case 'count':
      case 'suma':
      case 'sum':
      case 'promedio':
      case 'average':
      case 'maximo':
      case 'max':
      case 'minimo':
      case 'min':
        content = _metricView(columns, data);
        break;
      case 'detalle':
      case 'detail':
      case 'formulario':
      case 'form':
      case 'kanban':
      case 'timeline':
      case 'calendario':
      case 'calendar':
        content = _unsupportedView(columns, data);
        break;
      default:
        content = _tableBody(columns, data);
        break;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Expanded(child: Text(_txt(selectedView!['nombre_vista']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
            IconButton(onPressed: () async { setState(() => loading = true); await _loadRows(); if (mounted) setState(() => loading = false); }, icon: const Icon(Icons.refresh)),
          ]),
        ),
        Expanded(child: content),
        _paginationBar(data.length),
      ],
    );
  }

  Future<void> _filterColumn(String column) async {
    final ctrl = TextEditingController(text: filters[column] ?? '');
    final value = await showDialog<String?>(context: context, builder: (_) => AlertDialog(
      title: Text('Filtrar $column'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Texto a buscar')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Limpiar')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Aplicar')),
      ],
    ));
    ctrl.dispose();
    if (value == null) return;
    setState(() {
      if (value.isEmpty) filters.remove(column); else filters[column] = value;
      currentPage = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    // El menú lateral principal ya muestra las vistas dinámicas.
    // No se debe crear un segundo panel interno de módulos/vistas.
    final body = _table();
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: Text(_txt(widget.section['nombre']).isEmpty ? _txt(widget.section['id']) : _txt(widget.section['nombre']))), body: body);
  }
}

class _WorkflowSignatureDialog extends StatefulWidget {
  const _WorkflowSignatureDialog();

  @override
  State<_WorkflowSignatureDialog> createState() => _WorkflowSignatureDialogState();
}

class _WorkflowSignatureDialogState extends State<_WorkflowSignatureDialog> {
  final List<Offset?> points = [];

  void _clear() => setState(points.clear);

  Future<Uint8List?> _exportPng() async {
    if (points.whereType<Offset>().isEmpty) return null;

    const width = 900.0;
    const height = 360.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.white);

    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      if (p1 != null && p2 != null) canvas.drawLine(p1, p2, paint);
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debe firmar antes de aceptar.')));
      return;
    }
    Navigator.pop(context, png);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Firma'),
      content: SizedBox(
        width: double.maxFinite,
        height: 260,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black26),
            borderRadius: BorderRadius.circular(8),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scaleX = 900.0 / constraints.maxWidth;
              final scaleY = 360.0 / constraints.maxHeight;
              return GestureDetector(
                onPanStart: (details) {
                  final box = context.findRenderObject() as RenderBox;
                  final local = box.globalToLocal(details.globalPosition);
                  setState(() => points.add(Offset(local.dx * scaleX, local.dy * scaleY)));
                },
                onPanUpdate: (details) {
                  final box = context.findRenderObject() as RenderBox;
                  final local = box.globalToLocal(details.globalPosition);
                  setState(() => points.add(Offset(local.dx * scaleX, local.dy * scaleY)));
                },
                onPanEnd: (_) => setState(() => points.add(null)),
                child: CustomPaint(
                  painter: _WorkflowSignaturePainter(points, scaleX: constraints.maxWidth / 900.0, scaleY: constraints.maxHeight / 360.0),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _clear, child: const Text('Limpiar')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _accept, child: const Text('Aceptar')),
      ],
    );
  }
}

class _WorkflowSignaturePainter extends CustomPainter {
  final List<Offset?> points;
  final double scaleX;
  final double scaleY;

  _WorkflowSignaturePainter(this.points, {required this.scaleX, required this.scaleY});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      if (p1 != null && p2 != null) {
        canvas.drawLine(Offset(p1.dx * scaleX, p1.dy * scaleY), Offset(p2.dx * scaleX, p2.dy * scaleY), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WorkflowSignaturePainter oldDelegate) => true;
}
