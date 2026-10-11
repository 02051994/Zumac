import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xlsx;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ScaffoldMessenger;
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_filex/open_filex.dart';
import 'package:uuid/uuid.dart';

import '../../config/supabase_config.dart';
import '../../core/platform/file_download.dart';
import '../../core/platform/network_bytes.dart';
import '../../core/platform/app_platform.dart';
import '../../core/platform/pdf_open.dart';
import '../../core/services/app_experience_service.dart';
import '../../core/services/local_db.dart';
import '../../core/services/evidence_storage.dart';
import '../../core/services/formula_engine.dart';
import '../../core/services/human_resources_rules.dart';
import '../../core/services/local_session.dart';
import '../../core/services/sync_service.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../core/widgets/configuration_icon_catalog.dart';
import '../../core/widgets/zumac_scaffold_messenger.dart';
import '../configuration_admin/configuration_admin_repository.dart';
import '../form_runner/form_runner_page.dart';
import '../form_runner/erp_document_pdf.dart';
import '../form_runner/erp_image_attachment.dart';
import '../form_runner/special_form_pages.dart';
import 'hr_record_document_pdf.dart';
import 'payroll_slip_pdf.dart';
import 'record_import_utils.dart';
import 'record_refresh_policy.dart';
import 'widgets/mobile_records_list.dart';

class _TableCellFormat {
  final Color? textColor;
  final Color? bgColor;
  final Color? borderColor;
  final double? fontSize;

  const _TableCellFormat(
      {this.textColor, this.bgColor, this.borderColor, this.fontSize});
}

class _DesktopRecordsResult {
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final int? totalRows;

  const _DesktopRecordsResult(
      {required this.columns, required this.rows, this.totalRows});
}

enum _ImportMessageKind { success, warning, error, info }

class DesktopFormatRecordsPage extends StatefulWidget {
  final Map<String, dynamic> module;
  final Map<String, dynamic> format;
  final bool embedded;
  final Future<void> Function()? onLocalRecordsChanged;
  final bool mobileMode;
  final String? initialTableName;
  final String? initialRecordField;
  final String? initialRecordValue;

  const DesktopFormatRecordsPage({
    super.key,
    required this.module,
    required this.format,
    this.embedded = false,
    this.onLocalRecordsChanged,
    this.mobileMode = false,
    this.initialTableName,
    this.initialRecordField,
    this.initialRecordValue,
  });

  @override
  State<DesktopFormatRecordsPage> createState() =>
      _DesktopFormatRecordsPageState();
}

class _DesktopFormatRecordsPageState extends State<DesktopFormatRecordsPage> {
  static const Color _appgtHeaderColor = Color(0xFF42576B);
  static const Color _appgtHeaderBorderColor = Color(0xFF314457);
  final local = LocalDb.instance;
  final supabase = Supabase.instance.client;
  final experience = AppExperienceService();
  final ScrollController _horizontalTableController = ScrollController();
  final ScrollController _horizontalHeaderController = ScrollController();
  final ScrollController _verticalTableController = ScrollController();
  final ScrollController _fixedVerticalTableController = ScrollController();
  bool _syncingVerticalTableScroll = false;
  final Set<String> _highlightedRemoteRowKeys = <String>{};
  final Map<String, Future<String>> _signedMediaUrlFutures =
      <String, Future<String>>{};
  final Map<String, ImageProvider> _mediaImageProviders =
      <String, ImageProvider>{};
  final Map<String, Uint8List> _decodedMediaBytes = <String, Uint8List>{};
  final Expando<String> _rowKeyCache = Expando<String>('appgt-row-key');
  final Map<String, Map<String, dynamic>?> _fieldDefColumnCache =
      <String, Map<String, dynamic>?>{};
  final Map<String, List<String>> _matrixColumnsCache =
      <String, List<String>>{};
  Timer? _renderRowsTimer;
  Timer? _columnWidthDebounce;
  Timer? _viewPersistenceTimer;
  String? _recordViewFingerprint;
  double? _restoredVerticalOffset;
  double? _restoredHorizontalOffset;
  final Set<String> _restoredSelectedRowKeys = <String>{};

  bool loading = true;
  String _loadingMessage = 'Cargando tabla...';
  bool offline = false;
  bool canExport = false;
  bool canImport = false;
  bool canInsert = false;
  bool canUpdate = false;
  bool canDelete = false;
  bool canReview = false;
  bool canApprove = false;
  Map<String, Map<String, bool>> _workflowStatePermissions =
      <String, Map<String, bool>>{};
  bool _importingFile = false;
  final Set<String> _selectedDeleteRowKeys = <String>{};
  final Map<String, Map<String, dynamic>> _selectedDeleteRows =
      <String, Map<String, dynamic>>{};
  final ValueNotifier<int> _deleteSelectionVersion = ValueNotifier<int>(0);
  final ValueNotifier<int> _tableRenderVersion = ValueNotifier<int>(0);
  final ValueNotifier<int> _filterControlsVersion = ValueNotifier<int>(0);
  final Set<String> _pinnedColumns = <String>{};
  int _headerVersion = 1;
  int _loadSerial = 0;
  int _renderRowLimit = _pageSize;
  List<Map<String, dynamic>>? _filteredCache;
  String? _filteredCacheKey;
  static Map<String, List<String>>? _sharedCatalogValues;
  static Map<String, Map<String, dynamic>>? _sharedFieldDefsById;
  static List<Map<String, dynamic>>? _sharedAllLocalFormFields;
  static Map<String, List<Map<String, dynamic>>>? _sharedMatrixRowsByTable;
  static Future<void>? _sharedCacheLoader;
  static final Map<String, bool> _adminTransferPermissionCache = {};
  String? error;
  String? tableName;
  List<Map<String, dynamic>> records = [];
  List<String> displayColumns = [];
  List<Map<String, dynamic>> special = [];
  List<Map<String, dynamic>> internalTableRows = [];
  String? selectedTableName;
  Map<String, List<String>> catalogValues = {};
  Map<String, Map<String, dynamic>> fieldDefsById = {};
  List<Map<String, dynamic>> allLocalFormFields = [];
  Map<String, List<Map<String, dynamic>>> matrixRowsByTable = {};
  final Map<String, double> _columnWidths = {};
  final Map<String, String> _columnFilters = {};
  final Set<String> _visibleFilterFields = <String>{};
  final Set<String> _periodFilterKeys = <String>{};
  final Map<String, String?> _periodFilterValues = <String, String?>{};
  final TextEditingController _mobileSearchController = TextEditingController();
  String? _sortColumn;
  bool _sortAscending = true;

  static const int _pageSize = 200;
  static const double _virtualRowHeight = 46.0;
  static const double _virtualCacheExtent =
      276.0; // 6 filas extra aprox.; suficiente sin inflar widgets.
  int _currentPage = 0;
  bool _hasNextPage = false;
  int? _knownTotalRows;
  bool _silentTableRefreshRunning = false;
  bool _contractLifecycleChecked = false;
  bool _contractRenewalDialogScheduled = false;
  int _pendingContractRenewals = 0;
  bool _payrollDailyRefreshChecked = false;

  String? yearFilter;
  String? weekFilter;
  String? monthFilter;
  String? dateFilter;
  DateTime? startDateFilter;
  DateTime? endDateFilter;
  String? varietyFilter;
  String? loteFilter;
  String? turnoFilter;

  @override
  void dispose() {
    _renderRowsTimer?.cancel();
    _columnWidthDebounce?.cancel();
    _viewPersistenceTimer?.cancel();
    unawaited(_persistRecordView());
    _horizontalTableController.removeListener(_syncHeaderScroll);
    _verticalTableController.removeListener(_syncFixedVerticalScroll);
    _fixedVerticalTableController.removeListener(_syncMainVerticalScroll);
    _horizontalTableController.dispose();
    _horizontalHeaderController.dispose();
    _verticalTableController.dispose();
    _fixedVerticalTableController.dispose();
    _deleteSelectionVersion.dispose();
    _tableRenderVersion.dispose();
    _filterControlsVersion.dispose();
    _mobileSearchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _horizontalTableController.addListener(_syncHeaderScroll);
    _verticalTableController.addListener(_syncFixedVerticalScroll);
    _fixedVerticalTableController.addListener(_syncMainVerticalScroll);
    unawaited(_initializeRecordView());
  }

  String get _recordViewKey {
    final moduleId = widget.module['id']?.toString().trim() ?? '';
    final formatId = widget.format['id']?.toString().trim() ?? '';
    return '${moduleId.isEmpty ? 'modulo' : moduleId}_'
        '${formatId.isEmpty ? 'formato' : formatId}';
  }

  Future<void> _initializeRecordView() async {
    await _restoreRecordView();
    _applyRequestedRecordFocus();
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    _highlightRequestedRecord();
    _restoreRecordSelectionAndScroll();
    _viewPersistenceTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_persistRecordView()),
    );
  }

  void _applyRequestedRecordFocus() {
    final requestedTable = widget.initialTableName?.trim() ?? '';
    final requestedField = widget.initialRecordField?.trim() ?? '';
    final requestedValue = widget.initialRecordValue?.trim() ?? '';
    if (requestedTable.isNotEmpty) selectedTableName = requestedTable;
    if (requestedField.isNotEmpty && requestedValue.isNotEmpty) {
      _columnFilters[requestedField] = jsonEncode({
        'mode': 'equals',
        'value': requestedValue,
      });
      _mobileSearchController.text = requestedValue;
    }
  }

  void _highlightRequestedRecord() {
    final requestedField = widget.initialRecordField?.trim() ?? '';
    final requestedValue = widget.initialRecordValue?.trim() ?? '';
    if (requestedField.isEmpty || requestedValue.isEmpty) return;
    final normalizedField = _norm(requestedField);
    final index = records.indexWhere((row) {
      for (final entry in row.entries) {
        if (_norm(entry.key) == normalizedField &&
            entry.value?.toString().trim() == requestedValue) {
          return true;
        }
      }
      return false;
    });
    if (index < 0) return;
    _highlightedRemoteRowKeys.add(
      _remoteRowHighlightKey(records[index], index),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_verticalTableController.hasClients) return;
      final target = (index * _virtualRowHeight).clamp(
        0.0,
        _verticalTableController.position.maxScrollExtent,
      );
      _verticalTableController.animateTo(
        target,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _restoreRecordView() async {
    final saved = await experience.loadRecordView(_recordViewKey);
    if (saved.isEmpty) return;
    selectedTableName = _clean(saved['selected_table']);
    final rawColumnFilters = saved['column_filters'];
    if (rawColumnFilters is Map) {
      _columnFilters
        ..clear()
        ..addAll(
          rawColumnFilters.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ),
        );
      _visibleFilterFields.addAll(_columnFilters.keys);
    }
    final rawPeriodFilters = saved['period_filters'];
    if (rawPeriodFilters is Map) {
      for (final entry in rawPeriodFilters.entries) {
        final key = entry.key.toString();
        if (key.trim().isEmpty) continue;
        _periodFilterKeys.add(key);
        _periodFilterValues[key] = _clean(entry.value);
      }
    }
    _sortColumn = _clean(saved['sort_column']);
    _sortAscending = saved['sort_ascending'] != false;
    _currentPage = int.tryParse('${saved['page'] ?? 0}') ?? 0;
    _mobileSearchController.text = _clean(saved['search']) ?? '';
    _restoredVerticalOffset =
        double.tryParse('${saved['vertical_offset'] ?? ''}');
    _restoredHorizontalOffset =
        double.tryParse('${saved['horizontal_offset'] ?? ''}');
    final pinned = saved['pinned_columns'];
    if (pinned is List) {
      _pinnedColumns.addAll(pinned.map((value) => value.toString()));
    }
    final selectedRows = saved['selected_row_keys'];
    if (selectedRows is List) {
      _restoredSelectedRowKeys
          .addAll(selectedRows.map((value) => value.toString()));
    }
  }

  Future<void> _persistRecordView() async {
    final value = <String, dynamic>{
      'selected_table': selectedTableName,
      'column_filters': Map<String, String>.from(_columnFilters),
      'period_filters': {
        for (final key in _periodFilterKeys) key: _periodFilterValues[key],
      },
      'sort_column': _sortColumn,
      'sort_ascending': _sortAscending,
      'page': _currentPage,
      'search': _mobileSearchController.text,
      'vertical_offset': _verticalTableController.hasClients
          ? _verticalTableController.offset
          : _restoredVerticalOffset,
      'horizontal_offset': _horizontalTableController.hasClients
          ? _horizontalTableController.offset
          : _restoredHorizontalOffset,
      'pinned_columns': _pinnedColumns.toList(growable: false),
      'selected_row_keys': _selectedDeleteRowKeys.toList(growable: false),
    };
    final fingerprint = jsonEncode(value);
    if (fingerprint == _recordViewFingerprint) return;
    _recordViewFingerprint = fingerprint;
    await experience.saveRecordView(_recordViewKey, value);
  }

  void _restoreRecordSelectionAndScroll() {
    if (_restoredSelectedRowKeys.isNotEmpty) {
      for (var index = 0; index < records.length; index++) {
        final row = records[index];
        final key = _remoteRowHighlightKey(row, index);
        if (_restoredSelectedRowKeys.contains(key)) {
          _selectedDeleteRowKeys.add(key);
          _selectedDeleteRows[key] = row;
        }
      }
      _notifyDeleteSelectionChanged();
      _restoredSelectedRowKeys.clear();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final verticalOffset = _restoredVerticalOffset;
      if (verticalOffset != null && _verticalTableController.hasClients) {
        _verticalTableController.jumpTo(
          verticalOffset
              .clamp(0.0, _verticalTableController.position.maxScrollExtent)
              .toDouble(),
        );
      }
      final horizontalOffset = _restoredHorizontalOffset;
      if (horizontalOffset != null && _horizontalTableController.hasClients) {
        _horizontalTableController.jumpTo(
          horizontalOffset
              .clamp(0.0, _horizontalTableController.position.maxScrollExtent)
              .toDouble(),
        );
      }
      _restoredVerticalOffset = null;
      _restoredHorizontalOffset = null;
    });
  }

  void _syncHeaderScroll() {
    if (!_horizontalTableController.hasClients ||
        !_horizontalHeaderController.hasClients) return;
    final max = _horizontalHeaderController.position.maxScrollExtent;
    final offset = _horizontalTableController.offset.clamp(0.0, max).toDouble();
    if ((_horizontalHeaderController.offset - offset).abs() > 0.5) {
      _horizontalHeaderController.jumpTo(offset);
    }
  }

  void _syncFixedVerticalScroll() {
    if (_syncingVerticalTableScroll) return;
    if (!_verticalTableController.hasClients ||
        !_fixedVerticalTableController.hasClients) return;
    _syncingVerticalTableScroll = true;
    final max = _fixedVerticalTableController.position.maxScrollExtent;
    final offset = _verticalTableController.offset.clamp(0.0, max).toDouble();
    if ((_fixedVerticalTableController.offset - offset).abs() > 0.5) {
      _fixedVerticalTableController.jumpTo(offset);
    }
    _syncingVerticalTableScroll = false;
  }

  void _syncMainVerticalScroll() {
    if (_syncingVerticalTableScroll) return;
    if (!_verticalTableController.hasClients ||
        !_fixedVerticalTableController.hasClients) return;
    _syncingVerticalTableScroll = true;
    final max = _verticalTableController.position.maxScrollExtent;
    final offset =
        _fixedVerticalTableController.offset.clamp(0.0, max).toDouble();
    if ((_verticalTableController.offset - offset).abs() > 0.5) {
      _verticalTableController.jumpTo(offset);
    }
    _syncingVerticalTableScroll = false;
  }

  String? _clean(dynamic value) {
    final s = value?.toString().trim() ?? '';
    if (s.isEmpty || s.toUpperCase() == 'NULL') return null;
    return s;
  }

  String _tableVisualName([String? physicalName]) {
    final wanted = (physicalName ?? tableName ?? '').trim().toUpperCase();
    for (final row in internalTableRows) {
      final candidate = _clean(row['tabla_destino'])?.toUpperCase() ?? '';
      if (wanted.isNotEmpty && candidate != wanted) continue;
      final label = _clean(row['nombre_tabla']) ??
          _clean(row['nombre']) ??
          _clean(row['etiqueta']);
      if (label != null) return label;
    }
    return _clean(widget.format['nombre']) ?? 'Registros';
  }

  bool _boolValue(dynamic value) {
    if (value == true) return true;
    if (value == false || value == null) return false;
    final s = value.toString().trim().toUpperCase();
    return s == 'TRUE' || s == '1' || s == 'SI' || s == 'SÍ' || s == 'YES';
  }

  bool get _approvalsEnabled {
    if (_boolValue(widget.format['approvals_enabled'])) return true;
    dynamic raw = widget.format['capacidades'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {}
    }
    if (raw is Map) {
      return _boolValue(raw['aprobaciones']) || _boolValue(raw['approvals']);
    }
    return false;
  }

  bool get _canSelectRows =>
      canDelete ||
      (_approvalsEnabled && (canReview || canApprove || canUpdate)) ||
      _isTareoTable ||
      _isPayrollPeriodTable;

  bool _isDeletedRecord(Map<String, dynamic> row) {
    // Regla de producción para tablas operativas:
    // La visibilidad en Windows depende de la columna eliminado.
    // estado_sync puede ser sincronizado/importado/nuevo/etc. y NO debe ocultar filas.
    // Si la fila trae eliminado, se respeta exclusivamente ese valor.
    if (row.containsKey('eliminado')) {
      return _boolValue(row['eliminado']);
    }

    // Fallback solo para tablas antiguas o payloads incompletos sin columna eliminado.
    final deletedAt = row['deleted_at']?.toString().trim() ?? '';
    if (deletedAt.isNotEmpty && deletedAt.toUpperCase() != 'NULL') return true;
    final estadoSync =
        row['estado_sync']?.toString().trim().toLowerCase() ?? '';
    if (estadoSync == 'eliminado' || estadoSync == 'deleted') return true;
    return false;
  }

  List<Map<String, dynamic>> _withoutDeletedRecords(
      List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return rows;
    return rows.where((row) => !_isDeletedRecord(row)).toList();
  }

  Future<Map<String, dynamic>> _currentUserPermissionsForFormat(
      String formatId) async {
    final authUserId = supabase.auth.currentUser?.id.trim() ?? '';
    final cachedUserId = (await LocalSession().cachedUserId())?.trim() ?? '';
    final activeUserId = authUserId.isNotEmpty ? authUserId : cachedUserId;
    final activeEmpresaId = (await LocalSession().cachedEmpresaId()).trim();
    final candidateKeys = <String>{
      _norm(formatId),
      _norm(widget.format['id']?.toString() ?? ''),
      _norm(widget.format['tabla_destino']?.toString() ?? ''),
      _norm(selectedTableName ?? ''),
      _norm(tableName ?? ''),
    }..removeWhere((value) => value.isEmpty);
    final rows = (await local.getAll('local_permissions')).where((row) {
      final rowUserId = row['user_id']?.toString().trim() ?? '';
      final rowEmpresaId = row['empresa_id']?.toString().trim() ?? '';
      if (activeUserId.isNotEmpty && rowUserId != activeUserId) return false;
      if (activeEmpresaId.isNotEmpty &&
          rowEmpresaId.isNotEmpty &&
          rowEmpresaId != activeEmpresaId) return false;
      return candidateKeys.contains(_norm(row['formato']?.toString() ?? ''));
    });
    var export = false;
    var import = false;
    var insert = false;
    var update = false;
    var delete = false;
    var review = false;
    var approve = false;
    final statePermissions = <String, Map<String, bool>>{};
    for (final row in rows) {
      export =
          export || _boolValue(row['can_export']) || row['can_export'] == 1;
      import =
          import || _boolValue(row['can_import']) || row['can_import'] == 1;
      insert =
          insert || _boolValue(row['can_insert']) || row['can_insert'] == 1;
      update =
          update || _boolValue(row['can_update']) || row['can_update'] == 1;
      delete =
          delete || _boolValue(row['can_delete']) || row['can_delete'] == 1;
      review =
          review || _boolValue(row['can_review']) || row['can_review'] == 1;
      approve =
          approve || _boolValue(row['can_approve']) || row['can_approve'] == 1;
      dynamic rawStates = row['permisos_estado'];
      if (rawStates is String && rawStates.trim().isNotEmpty) {
        try {
          rawStates = jsonDecode(rawStates);
        } catch (_) {
          rawStates = null;
        }
      }
      if (rawStates is Map) {
        for (final entry in rawStates.entries) {
          if (entry.value is! Map) continue;
          final state = entry.key.toString().trim().toUpperCase();
          final actions = Map<String, dynamic>.from(entry.value as Map);
          final current =
              statePermissions.putIfAbsent(state, () => <String, bool>{});
          for (final action in const ['view', 'create', 'update', 'delete']) {
            current[action] = (current[action] ?? false) ||
                _boolValue(actions[action]) ||
                (action == 'create' && _boolValue(actions['insert'])) ||
                (action == 'update' && _boolValue(actions['edit']));
          }
        }
      }
    }
    // Los administradores de empresa conservan las herramientas operativas
    // aunque todavía no exista una fila de permiso granular para el formato.
    // El contexto remoto es autoritativo y se cachea por usuario/empresa para
    // no añadir una llamada en cada cambio de página o filtro.
    if ((!export || !import) && activeUserId.isNotEmpty) {
      final adminKey = '$activeEmpresaId::$activeUserId';
      var isCompanyAdmin = _adminTransferPermissionCache[adminKey];
      if (isCompanyAdmin == null) {
        try {
          final context = await ConfigurationAdminRepository()
              .loadContext()
              .timeout(const Duration(seconds: 5));
          isCompanyAdmin = context['es_admin_empresa'] == true;
          _adminTransferPermissionCache[adminKey] = isCompanyAdmin;
        } catch (_) {
          isCompanyAdmin = false;
        }
      }
      if (isCompanyAdmin) {
        export = true;
        import = true;
      }
    }
    return <String, dynamic>{
      'export': export,
      'import': import,
      'insert': insert,
      'update': update,
      'delete': delete,
      'review': review,
      'approve': approve,
      'state_permissions': statePermissions,
    };
  }

  void _setLoadingMessage(String message) {
    if (!mounted) return;
    setState(() => _loadingMessage = message);
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

  bool _isNamedTable(String? table, String expected) =>
      _norm(table ?? '') == _norm(expected);

  bool _attendanceCaptureBlocked(String? table) =>
      !isMobileCaptureRuntime && _isNamedTable(table, 'GT-ASISTENCIA_PERSONAL');

  Future<void> _preparePayrollLifecycle(String resolvedTable) async {
    if (_isNamedTable(resolvedTable, 'GH-REGISTRO_PERSONAL_PLANILLA') &&
        !_contractLifecycleChecked) {
      _contractLifecycleChecked = true;
      try {
        final result =
            await supabase.rpc('appgt_marcar_contratos_vencidos_zumac');
        _pendingContractRenewals =
            result is num ? result.toInt() : int.tryParse('$result') ?? 0;
      } catch (error) {
        // La tabla debe seguir abriendo si el RPC aun no se ha sincronizado.
        debugPrint('No se pudo revisar contratos vencidos: $error');
      }
    }

    if (_isNamedTable(resolvedTable, 'PLANILLA_TRABAJADORES_ZUMAC') &&
        !_payrollDailyRefreshChecked) {
      _payrollDailyRefreshChecked = true;
      try {
        await supabase.rpc('appgt_refrescar_planilla_zumac');
      } catch (error) {
        debugPrint('No se pudo refrescar la planilla diaria: $error');
      }
    }
  }

  String? _personalStatusColumn() {
    const candidates = ['Status', 'ESTADO', 'ESTADO_PERSONAL'];
    final wanted = candidates.map(_norm).toSet();
    for (final column in displayColumns) {
      if (wanted.contains(_norm(column))) return column;
    }
    for (final row in records) {
      for (final column in row.keys) {
        if (wanted.contains(_norm(column))) return column;
      }
    }
    for (final field in allLocalFormFields) {
      if (!_isNamedTable(
          field['tabla_destino']?.toString(), 'GH-REGISTRO_PERSONAL_PLANILLA'))
        continue;
      final column = field['campo']?.toString().trim() ?? '';
      if (wanted.contains(_norm(column))) return column;
    }
    return null;
  }

  void _scheduleContractRenewalDialog() {
    if (_pendingContractRenewals <= 0 ||
        _contractRenewalDialogScheduled ||
        !_isPersonalPlanillaTable) return;
    _contractRenewalDialogScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_showContractRenewalDialog());
    });
  }

  Future<void> _showContractRenewalDialog() async {
    final count = _pendingContractRenewals;
    if (!mounted || count <= 0) return;
    final renew = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Contratos pendientes de renovación'),
        content: Text(
          '$count trabajador${count == 1 ? '' : 'es'} '
          '${count == 1 ? 'tiene' : 'tienen'} el contrato vencido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Omitir'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.event_repeat_outlined),
            label: const Text('Renovar'),
          ),
        ],
      ),
    );
    if (renew != true || !mounted) return;

    final statusColumn = _personalStatusColumn();
    if (statusColumn == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('No se encontró el campo Status para aplicar el filtro.'),
        ),
      );
      return;
    }
    _columnFilters[statusColumn] = jsonEncode({
      'mode': 'equals',
      'value': 'pendiente renovación',
    });
    _visibleFilterFields.add(statusColumn);
    _currentPage = 0;
    _invalidateFilteredCache();
    _notifyTableRenderChanged(filtersChanged: true);
    await _load();
  }

  dynamic _value(Map<String, dynamic> row, List<String> candidates) {
    final wanted = candidates.map(_norm).toSet();
    for (final entry in row.entries) {
      if (wanted.contains(_norm(entry.key))) return entry.value;
    }
    return null;
  }

  dynamic _valueByColumn(Map<String, dynamic> row, String column) {
    final wanted = _norm(column);
    for (final entry in row.entries) {
      if (_norm(entry.key) == wanted) return entry.value;
    }
    return null;
  }

  String? _firstDateColumn() {
    for (final column in displayColumns) {
      if (_norm(column).contains('FECHA')) return column;
    }
    for (final row in records) {
      for (final key in row.keys) {
        if (_norm(key).contains('FECHA')) return key;
      }
    }
    return null;
  }

  DateTime? _dateValue(Map<String, dynamic> row) {
    final dateColumn = _firstDateColumn();
    if (dateColumn == null) return null;
    return _parseDate(_valueByColumn(row, dateColumn));
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso;

    final datePart = raw.split(RegExp(r'\s+')).first.trim();
    final sep =
        datePart.contains('/') ? '/' : (datePart.contains('-') ? '-' : null);
    if (sep == null) return null;
    final parts = datePart.split(sep).map((e) => int.tryParse(e)).toList();
    if (parts.length != 3 || parts.any((e) => e == null)) return null;

    int a = parts[0]!;
    int b = parts[1]!;
    int c = parts[2]!;
    if (c < 100) c += 2000;

    try {
      if (a > 31) return DateTime(a, b, c);
      if (b > 12) return DateTime(c, b, a);
      return DateTime(c, b, a);
    } catch (_) {
      return null;
    }
  }

  int _isoWeek(DateTime date) {
    final thursday = date.add(Duration(days: 3 - ((date.weekday + 6) % 7)));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final week = 1 +
        ((thursday.difference(firstThursday).inDays +
                ((firstThursday.weekday + 6) % 7)) ~/
            7);
    return week;
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  dynamic _decodeJsonLike(dynamic data) {
    if (data == null) return null;
    if (data is String) {
      final raw = data.trim();
      if (raw.isEmpty) return null;
      return jsonDecode(raw);
    }
    return data;
  }

  List<Map<String, dynamic>> _normalizeRows(dynamic data) {
    final decoded = _decodeJsonLike(data);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  List<String> _columnsFromRows(List<Map<String, dynamic>> rows) {
    final columns = <String>[];
    final seen = <String>{};
    for (final row in rows) {
      for (final key in row.keys) {
        final normalized = _norm(key);
        if (seen.add(normalized)) columns.add(key);
      }
    }
    return columns;
  }

  List<String> _normalizeColumns(
      dynamic data, List<Map<String, dynamic>> rows) {
    final decoded = _decodeJsonLike(data);
    if (decoded is Map) {
      final rawColumns = decoded['columns'];
      if (rawColumns is List) {
        final columns = rawColumns
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
        if (columns.isNotEmpty) return columns;
      }
    }
    return _columnsFromRows(rows);
  }

  _DesktopRecordsResult _normalizeDesktopResult(dynamic data) {
    final decoded = _decodeJsonLike(data);
    if (decoded is Map) {
      final rows = _withoutDeletedRecords(_normalizeRows(decoded['rows']));
      final columns = _normalizeColumns(decoded, rows);
      return _DesktopRecordsResult(
          columns: columns, rows: rows, totalRows: rows.length);
    }
    final rows = _normalizeRows(decoded);
    final cleanRows = _withoutDeletedRecords(rows);
    return _DesktopRecordsResult(
        columns: _columnsFromRows(cleanRows),
        rows: cleanRows,
        totalRows: cleanRows.length);
  }

  String? _remoteDateColumn() {
    final first = _firstDateColumn();
    if (first != null && first.trim().isNotEmpty) return first;
    for (final def in fieldDefsById.values) {
      final tipo = def['tipo']?.toString().trim().toLowerCase() ?? '';
      final campo = def['campo']?.toString().trim() ?? '';
      if (campo.isNotEmpty &&
          (tipo == 'date' || tipo == 'datetime' || tipo == 'timestamp'))
        return campo;
    }
    return null;
  }

  String? _dateFilterValue(dynamic value) {
    final d = _parseDate(value);
    return d == null ? null : _dateKey(d);
  }

  dynamic _applyRemoteFilters(dynamic query) {
    query = query.eq('eliminado', false);
    final dateColumn = _remoteDateColumn();
    if (dateColumn != null) {
      if (yearFilter != null) {
        query = query
            .gte(dateColumn, '$yearFilter-01-01')
            .lte(dateColumn, '$yearFilter-12-31');
      }
      if (monthFilter != null) {
        final year = yearFilter ?? DateTime.now().year.toString();
        final month = int.tryParse(monthFilter ?? '');
        if (month != null) {
          final start = DateTime(int.parse(year), month, 1);
          final end = DateTime(start.year, start.month + 1, 1)
              .subtract(const Duration(days: 1));
          query = query
              .gte(dateColumn, _dateKey(start))
              .lte(dateColumn, _dateKey(end));
        }
      }
      if (dateFilter != null) query = query.eq(dateColumn, dateFilter);
      if (startDateFilter != null)
        query = query.gte(dateColumn, _dateKey(startDateFilter!));
      if (endDateFilter != null)
        query = query.lte(dateColumn, _dateKey(endDateFilter!));
    }

    void applyEqualsFromCandidates(List<String> candidates, String? value) {
      if (value == null || value.trim().isEmpty) return;
      for (final c in displayColumns) {
        if (candidates.map(_norm).contains(_norm(c))) {
          query = query.eq(c, value.trim());
          return;
        }
      }
    }

    applyEqualsFromCandidates(['VARIEDAD', 'VARIEDADES'], varietyFilter);
    applyEqualsFromCandidates(['LOTE', 'LOTES'], loteFilter);
    applyEqualsFromCandidates(
        ['TURNO', 'TURNOS', 'FECHA O TURNO', 'FECHA_O_TURNO'], turnoFilter);

    for (final entry in _columnFilters.entries) {
      final column = entry.key;
      final filter = _decodeColumnFilter(entry.value);
      final mode = filter['mode'] ?? 'contains';
      final value = (filter['value'] ?? '').trim();
      final start = (filter['start'] ?? '').trim();
      final end = (filter['end'] ?? '').trim();
      if (value.isEmpty && start.isEmpty && end.isEmpty) continue;

      if (mode == 'equals') {
        final type = _columnType(column);
        if (type == 'date') {
          final d = _dateFilterValue(value);
          if (d != null) query = query.eq(column, d);
        } else {
          query = query.eq(column, value);
        }
      } else if (mode == 'contains' && _columnType(column) == 'text') {
        query = query.ilike(column, '%${value.replaceAll('%', '\%')}%');
      } else if (mode == 'multiple') {
        final values = value
            .split(RegExp(r'[;|,]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (values.isNotEmpty) query = query.inFilter(column, values);
      } else if (mode == 'between_date') {
        final startDate = _dateFilterValue(start);
        final endDate = _dateFilterValue(end);
        if (startDate != null) query = query.gte(column, startDate);
        if (endDate != null) query = query.lte(column, endDate);
      } else if (mode == 'between_numeric') {
        final startNum = num.tryParse(start.replaceAll(',', '.'));
        final endNum = num.tryParse(end.replaceAll(',', '.'));
        if (startNum != null) query = query.gte(column, startNum);
        if (endNum != null) query = query.lte(column, endNum);
      }
    }
    return query;
  }

  Future<int> _localMatrixRowCount(String table) async {
    final database = await local.db;
    final result = await database.rawQuery(
      'select count(*) as total from local_matrix_rows where source_table = ?',
      [table.trim()],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  Future<_DesktopRecordsResult> _fetchLocalMatrixRecords(String table) async {
    final localRows = await local.where(
      'local_matrix_rows',
      'source_table = ?',
      [table.trim()],
    );
    final rows = <Map<String, dynamic>>[];
    for (final row in localRows) {
      final raw = row['payload_json']?.toString() ?? '{}';
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (!_isDeletedRecord(decoded)) rows.add(decoded);
      } catch (_) {}
    }
    return _DesktopRecordsResult(
        columns: _columnsFromRows(rows), rows: rows, totalRows: rows.length);
  }

  Future<_DesktopRecordsResult> _fetchLocalMatrixRecordsPaged(
    String table, {
    int page = 0,
    int pageSize = _pageSize,
  }) async {
    final cleanTable = table.trim();
    final total = await _localMatrixRowCount(cleanTable);
    if (total <= 0) {
      return const _DesktopRecordsResult(
          columns: <String>[], rows: <Map<String, dynamic>>[], totalRows: 0);
    }
    final database = await local.db;
    final localRows = await database.query(
      'local_matrix_rows',
      where: 'source_table = ?',
      whereArgs: [cleanTable],
      orderBy: 'row_key',
      limit: pageSize + 1,
      offset: page * pageSize,
    );
    final rows = <Map<String, dynamic>>[];
    for (final row in localRows) {
      final raw = row['payload_json']?.toString() ?? '{}';
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (!_isDeletedRecord(decoded)) rows.add(decoded);
      } catch (_) {}
    }
    return _DesktopRecordsResult(
        columns: _columnsFromRows(rows), rows: rows, totalRows: total);
  }

  Future<_DesktopRecordsResult> _fetchDirectDesktopRecordsPaged(
    String table, {
    int page = 0,
    int pageSize = _pageSize,
    bool fetchAll = false,
  }) async {
    final cleanTable = table.trim();
    final rows = <Map<String, dynamic>>[];
    var from = fetchAll ? 0 : page * pageSize;

    while (true) {
      final to = fetchAll ? from + pageSize - 1 : from + pageSize;
      dynamic query = supabase.from(cleanTable).select();
      final pageData = await query.range(from, to);
      final pageRows = _normalizeRows(pageData);
      rows.addAll(pageRows);
      if (!fetchAll) break;
      if (pageRows.length < pageSize) break;
      from += pageSize;
    }

    final cleanRows = _withoutDeletedRecords(rows);
    return _DesktopRecordsResult(
        columns: _columnsFromRows(cleanRows),
        rows: cleanRows,
        totalRows: fetchAll ? cleanRows.length : null);
  }

  _DesktopRecordsResult _largestDesktopResult(
      List<_DesktopRecordsResult> candidates) {
    final valid = candidates.where((e) => e.rows.isNotEmpty).toList();
    if (valid.isEmpty) {
      return candidates.isEmpty
          ? const _DesktopRecordsResult(
              columns: <String>[], rows: <Map<String, dynamic>>[])
          : candidates.first;
    }
    valid.sort((a, b) => b.rows.length.compareTo(a.rows.length));
    return valid.first;
  }

  Future<_DesktopRecordsResult> _fetchDesktopRecords({
    required String table,
    required String formatId,
    required int page,
    int pageSize = _pageSize,
    bool fetchAll = false,
    bool preferRemote = false,
  }) async {
    final cleanTable = table.trim();
    final cleanFormat = formatId.trim();
    // Los filtros de la tabla Windows se aplican sobre el dataset ya cargado.
    // No se reconsulta Supabase al aplicar/limpiar filtros porque eso congela la UI
    // y puede devolver 0 filas si alguna tabla no tiene columnas técnicas como activo/eliminado.

    // Para carga completa en Windows no se puede confiar ciegamente en una sola fuente.
    // Si el RPC SQL está viejo/capado, puede devolver 56 filas aunque Supabase tenga miles.
    // Aquí consultamos RPC nuevo, RPC antiguo, caché local y SELECT directo, y usamos
    // la fuente con más registros válidos no eliminados.
    if (fetchAll) {
      final candidates = <_DesktopRecordsResult>[];
      try {
        final rpcData = await supabase.rpc(
          'appgt_select_format_records',
          params: {
            'p_format_id': cleanFormat,
            'p_table_name': cleanTable,
            'p_limit': 1000000,
            'p_offset': 0,
          },
        );
        candidates.add(_normalizeDesktopResult(rpcData));
      } catch (_) {}
      try {
        final rpcData = await supabase.rpc(
          'appgt_select_format_records',
          params: {
            'p_format_id': cleanFormat,
            'p_table_name': cleanTable,
            'p_limit': 1000000,
          },
        );
        candidates.add(_normalizeDesktopResult(rpcData));
      } catch (_) {}
      try {
        candidates.add(await _fetchLocalMatrixRecords(cleanTable));
      } catch (_) {}
      try {
        candidates.add(
            await _fetchDirectDesktopRecordsPaged(cleanTable, fetchAll: true));
      } catch (_) {}
      if (candidates.isNotEmpty) return _largestDesktopResult(candidates);
    }

    // Para abrir tablas Windows usamos paginado rápido.
    // Primero intentamos la caché local completa generada por "Actualizar datos":
    // evita el caso observado donde SELECT directo devolvía solo 56/59 filas,
    // mientras la exportación completa sí tenía miles de registros.
    // Si no hay caché local para la tabla, se usa el RPC con orden estable.
    // El SELECT directo queda como último respaldo porque PostgREST no puede
    // ordenar por una columna genérica que no existe en todas las tablas.
    if (!fetchAll && !preferRemote) {
      try {
        final localPaged = await _fetchLocalMatrixRecordsPaged(
          cleanTable,
          page: page,
          pageSize: pageSize,
        );
        if (localPaged.rows.isNotEmpty) return localPaged;
      } catch (_) {}
    }

    // Ruta remota principal: el RPC valida el formato y aplica ORDER BY estable
    // antes de LIMIT/OFFSET, evitando que las filas cambien entre páginas.
    try {
      final rpcData = await supabase.rpc(
        'appgt_select_format_records',
        params: {
          'p_format_id': cleanFormat,
          'p_table_name': cleanTable,
          'p_limit': fetchAll ? 1000000 : pageSize + 1,
          'p_offset': fetchAll ? 0 : page * pageSize,
        },
      );
      final result = _normalizeDesktopResult(rpcData);
      if (result.rows.isNotEmpty) {
        if (fetchAll) {
          final localResult = await _fetchLocalMatrixRecords(cleanTable);
          if (localResult.rows.length > result.rows.length) return localResult;
        }
        return result;
      }
    } catch (_) {
      // Compatibilidad con la versión anterior de la función SQL, si aún no tiene p_offset.
      try {
        final oldLimit = fetchAll ? 1000000 : ((page + 1) * pageSize) + 1;
        final rpcData = await supabase.rpc(
          'appgt_select_format_records',
          params: {
            'p_format_id': cleanFormat,
            'p_table_name': cleanTable,
            'p_limit': oldLimit,
          },
        );
        final result = _normalizeDesktopResult(rpcData);
        if (fetchAll) {
          final localResult = await _fetchLocalMatrixRecords(cleanTable);
          if (localResult.rows.length > result.rows.length) return localResult;
          return result;
        }
        final fromIndex = page * pageSize;
        final pageRows =
            result.rows.skip(fromIndex).take(pageSize + 1).toList();
        if (pageRows.isNotEmpty) {
          return _DesktopRecordsResult(columns: result.columns, rows: pageRows);
        }
      } catch (_) {}
    }

    // Último respaldo: SELECT directo o caché local. En exportación/impresión completa
    // se mantiene la comparación de fuentes para no volver al problema de 56 filas.
    final directResult = await _fetchDirectDesktopRecordsPaged(
      cleanTable,
      page: page,
      pageSize: pageSize,
      fetchAll: fetchAll,
    );
    if (fetchAll) {
      final localResult = await _fetchLocalMatrixRecords(cleanTable);
      if (localResult.rows.length > directResult.rows.length)
        return localResult;
    }
    if (directResult.rows.isNotEmpty || !fetchAll) return directResult;
    return _fetchLocalMatrixRecords(cleanTable);
  }

  void _invalidateFilteredCache() {
    _filteredCache = null;
    _filteredCacheKey = null;
  }

  String _currentFilterCacheKey() {
    return jsonEncode({
      'records': records.length,
      'cols': displayColumns.join('|'),
      'sort': _sortColumn,
      'asc': _sortAscending,
      'year': yearFilter,
      'week': weekFilter,
      'month': monthFilter,
      'date': dateFilter,
      'start': startDateFilter?.toIso8601String(),
      'end': endDateFilter?.toIso8601String(),
      'variety': varietyFilter,
      'lote': loteFilter,
      'turno': turnoFilter,
      'colFilters': _columnFilters,
      'periodFilters': {
        for (final key in _periodFilterKeys) key: _periodFilterValues[key],
      },
    });
  }

  void _scheduleProgressiveRender(int serial) {
    // Desactivado para Windows: el paginador ya limita la carga a 200 filas.
    // Hacer aumentos progresivos volvía a reconstruir la tabla varias veces y
    // se notaba lento al abrir/cambiar tablas o manipular el sidebar.
  }

  String _unwrapCacheReference(String value) {
    final text = value.trim();
    if (text.startsWith('[') && text.endsWith(']') && text.length >= 2) {
      return text.substring(1, text.length - 1).trim();
    }
    return text;
  }

  bool _isManualCacheDropdownLiteral(String value) {
    final text = value.trim();
    if (!text.startsWith('[') || !text.endsWith(']')) return false;
    final content = _unwrapCacheReference(text);
    return content.contains(',') ||
        content.contains(';') ||
        content.contains('|');
  }

  Map<String, dynamic>? _cacheFieldByIdentifier(
      List<Map<String, dynamic>> fields, String identifier) {
    final wanted = _norm(_unwrapCacheReference(identifier));
    if (wanted.isEmpty) return null;
    for (final field in fields) {
      final matches = [
        field['id'],
        field['campo'],
        field['etiqueta'],
        field['nombre_campo']
      ].any((value) => _norm(value?.toString() ?? '') == wanted);
      if (matches) return field;
    }
    return null;
  }

  Set<String> _neededMatrixTablesForActiveTable({
    required String? activeTable,
    required List<Map<String, dynamic>> allFields,
  }) {
    final needed = <String>{};
    final cleanActive = activeTable?.trim() ?? '';
    final activeNorm = _norm(cleanActive);

    for (final field in allFields) {
      final fieldTable = field['tabla_destino']?.toString().trim() ?? '';
      if (activeNorm.isNotEmpty && _norm(fieldTable) != activeNorm) continue;

      final dropdownRaw = _value(field, [
            'id_campo_dropdown',
            'id campo dropdown',
            'id_dropdown',
            'campo_dropdown',
            'dropdown'
          ])?.toString().trim() ??
          '';
      if (dropdownRaw.isNotEmpty &&
          dropdownRaw.toUpperCase() != 'NULL' &&
          !_isManualCacheDropdownLiteral(dropdownRaw)) {
        final cleanDropdown = _unwrapCacheReference(dropdownRaw);
        if (cleanDropdown.contains('.')) {
          final table = cleanDropdown.split('.').first.trim();
          if (table.isNotEmpty) needed.add(table);
        } else {
          final sourceField = _cacheFieldByIdentifier(allFields, cleanDropdown);
          final sourceTable =
              sourceField?['tabla_destino']?.toString().trim() ?? '';
          if (sourceTable.isNotEmpty) needed.add(sourceTable);
        }
      }

      final formula = _value(field, [
            'formula_funcion',
            'formula funcion',
            'formula',
            'funcion_formula'
          ])?.toString().trim() ??
          '';
      if (formula.isNotEmpty && formula.toUpperCase() != 'NULL') {
        final lookup = RegExp(r'(?:LOOKU[PR]|LOOKUP|BUSCAR)\s*\(\s*([^,;\)]+)',
                caseSensitive: false)
            .firstMatch(formula);
        final lookupTable = lookup?.group(1)?.trim() ?? '';
        if (lookupTable.isNotEmpty && !lookupTable.startsWith('['))
          needed.add(lookupTable);
      }
    }
    return needed;
  }

  Future<void> _loadDynamicFormCaches({String? activeTable}) async {
    // Importante: no usar caché estática aquí. Después de tocar MATRIZ_CAMPOS_FORMATO_APPGT
    // y presionar Actualizar datos, Windows debe leer inmediatamente los catálogos/campos
    // recién guardados en SQLite. La caché vieja era una causa directa de dropdowns que
    // seguían sin obedecer id_campo_dropdown hasta reiniciar la app.
    // Optimización segura: local_matrix_rows puede contener miles de filas por muchas tablas.
    // Para abrir una tabla Windows solo se decodifica la tabla abierta y sus fuentes directas
    // de dropdown/lookup. Exportación/caché completa se mantienen por sus propias rutas.
    _sharedCatalogValues = null;
    _sharedFieldDefsById = null;
    _sharedAllLocalFormFields = null;
    _sharedMatrixRowsByTable = null;
    _sharedCacheLoader = null;

    await Future<void>.delayed(Duration.zero);
    final catalogRows = await local.getAll('local_catalog_values',
        orderBy: 'catalog_key, value');
    final groupedCatalog = <String, List<String>>{};
    for (final row in catalogRows) {
      final key = row['catalog_key']?.toString() ?? '';
      final value = row['value']?.toString().trim() ?? '';
      if (key.isEmpty || value.isEmpty) continue;
      groupedCatalog.putIfAbsent(key, () => <String>[]).add(value);
    }

    await Future<void>.delayed(Duration.zero);
    final allFields = await local.getAll('local_form_fields', orderBy: 'orden');
    final defs = <String, Map<String, dynamic>>{};
    for (final field in allFields) {
      for (final candidate in [
        field['id'],
        field['campo'],
        field['etiqueta'],
        field['nombre_campo'],
      ]) {
        final key = candidate?.toString().trim();
        if (key == null || key.isEmpty || key.toUpperCase() == 'NULL') continue;
        defs.putIfAbsent(_norm(key), () => field);
      }
    }

    await Future<void>.delayed(Duration.zero);
    final neededTables = _neededMatrixTablesForActiveTable(
        activeTable: activeTable, allFields: allFields);
    final groupedMatrix = <String, List<Map<String, dynamic>>>{};
    var decodedMatrixCount = 0;
    for (final table in neededTables) {
      final localRows =
          await local.where('local_matrix_rows', 'source_table = ?', [table]);
      for (final row in localRows) {
        final raw = row['payload_json']?.toString() ?? '{}';
        try {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          if (!_isDeletedRecord(decoded)) {
            groupedMatrix
                .putIfAbsent(table, () => <Map<String, dynamic>>[])
                .add(decoded);
          }
        } catch (_) {}
        decodedMatrixCount++;
        if (decodedMatrixCount % 200 == 0)
          await Future<void>.delayed(Duration.zero);
      }
    }

    catalogValues = groupedCatalog;
    fieldDefsById = defs;
    allLocalFormFields = allFields;
    matrixRowsByTable = groupedMatrix;
  }

  Future<void> _refreshTableSilentlyAfterLoad(
      String table, String formatId, int sourceSerial) async {
    if (_silentTableRefreshRunning) return;
    _silentTableRefreshRunning = true;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) return;

      // Una sesión offline puede mantener abierta la aplicación después de
      // recargar el navegador. En ese estado RLS responde con cero filas; no
      // debemos interpretar esa respuesta anónima como una tabla vacía.
      if (supabase.auth.currentUser == null ||
          supabase.auth.currentSession == null) {
        return;
      }

      if (!mounted || sourceSerial != _loadSerial || tableName != table) return;

      final needsFullDatasetForView =
          _hasAnyActiveFilters || _sortColumn != null;
      final data = needsFullDatasetForView
          ? await _fetchDesktopRecords(
              table: table,
              formatId: formatId,
              page: 0,
              fetchAll: true,
              preferRemote: true,
            )
          : await _fetchDesktopRecords(
              table: table,
              formatId: formatId,
              page: _currentPage,
              fetchAll: false,
              preferRemote: true,
            );
      if (!mounted || sourceSerial != _loadSerial || tableName != table) return;

      late final List<Map<String, dynamic>> loadedRows;
      late final int? totalRowsForView;
      late final bool hasNextPageForView;

      if (needsFullDatasetForView) {
        final filteredAll = _filterAndSortRows(data.rows);
        totalRowsForView = filteredAll.length;
        final startIndex = _currentPage * _pageSize;
        final pageRows = startIndex >= filteredAll.length
            ? <Map<String, dynamic>>[]
            : filteredAll.skip(startIndex).take(_pageSize + 1).toList();
        hasNextPageForView = pageRows.length > _pageSize;
        loadedRows = pageRows.take(_pageSize).toList();
      } else {
        loadedRows = data.rows.take(_pageSize).toList();
        totalRowsForView = data.totalRows;
        hasNextPageForView = data.rows.length > _pageSize ||
            (data.totalRows != null &&
                ((_currentPage + 1) * _pageSize) < data.totalRows!);
      }

      final applyRefresh = shouldApplySilentRecordRefresh(
        visibleRowCount: records.length,
        refreshedRowCount: loadedRows.length,
      );
      if (applyRefresh) {
        setState(() {
          records = loadedRows;
          _knownTotalRows = totalRowsForView;
          _hasNextPage = hasNextPageForView;
          _renderRowLimit = loadedRows.length;
          _invalidateFilteredCache();
          displayColumns = _matrixColumnsForTable(table, data.columns);
        });
        unawaited(local.upsertTableCacheInfo(
          table,
          rowCount: totalRowsForView,
          lastCheckedAt: DateTime.now().toUtc(),
          lastChangedAt: DateTime.now().toUtc(),
          lastPage: _currentPage,
          lastFilterKey: _currentFilterCacheKey(),
          lastSortColumn: _sortColumn,
          lastSortAscending: _sortAscending,
        ));
      }
      unawaited(SyncService().refreshFormatTableSilently(table));
    } catch (_) {
      // Refresco silencioso: nunca debe interrumpir la operación normal de la tabla.
    } finally {
      _silentTableRefreshRunning = false;
    }
  }

  Future<void> _load() async {
    final serial = ++_loadSerial;
    setState(() {
      loading = true;
      _loadingMessage = 'Preparando tabla...';
      _renderRowLimit = _pageSize;
      _signedMediaUrlFutures.clear();
      _mediaImageProviders.clear();
      _decodedMediaBytes.clear();
      _fieldDefColumnCache.clear();
      _matrixColumnsCache.clear();
      _invalidateFilteredCache();
      offline = false;
      error = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 16));

    try {
      final formatId = widget.format['id']?.toString() ?? '';
      _setLoadingMessage('Leyendo permisos locales...');
      await Future<void>.delayed(Duration.zero);
      final permissions = await _currentUserPermissionsForFormat(formatId);
      final exportAllowed = permissions['export'] ?? false;
      final importAllowed = permissions['import'] ?? false;
      final insertAllowed = permissions['insert'] ?? false;
      final updateAllowed = permissions['update'] ?? false;
      final deleteAllowed = permissions['delete'] ?? false;
      var reviewAllowed = permissions['review'] ?? false;
      var approveAllowed = permissions['approve'] ?? false;
      _workflowStatePermissions = Map<String, Map<String, bool>>.from(
        permissions['state_permissions'] as Map? ??
            const <String, Map<String, bool>>{},
      );
      reviewAllowed = reviewAllowed ||
          (_workflowStatePermissions['PENDIENTE']?['update'] ?? false);
      approveAllowed = approveAllowed ||
          (_workflowStatePermissions['REVISADO']?['update'] ?? false);
      _setLoadingMessage('Leyendo configuración del formato...');
      await Future<void>.delayed(Duration.zero);
      final internalTables = await local.where(
        'local_format_tables',
        'formato_id = ? and activo = 1',
        [formatId],
        orderBy: 'orden',
      );
      special = await local.where(
        'local_special_formats',
        'formato_id = ? and activo = 1',
        [formatId],
      );
      if (special.isEmpty) {
        final fallback = appGtSpecialFormatFallback(widget.format);
        if (fallback != null) special = [fallback];
      }

      const embeddedErpDetails = {
        'ERP_SOLICITUDES_COMPRA_DETALLE_APPGT',
        'ERP_ORDENES_COMPRA_DETALLE_APPGT',
        'ERP_INGRESOS_ALMACEN_DETALLE_APPGT',
        'ERP_VALES_DESPACHO_DETALLE_APPGT',
      };
      final validInternalTables = internalTables.where((entry) {
        final destination = _clean(entry['tabla_destino']);
        if (destination == null) return false;
        return !(_boolValue(entry['es_detalle']) &&
            embeddedErpDetails.contains(destination.toUpperCase()));
      }).toList();
      final selectedStillExists = selectedTableName != null &&
          validInternalTables
              .any((e) => _clean(e['tabla_destino']) == selectedTableName);
      final resolvedTable = selectedStillExists
          ? selectedTableName
          : (validInternalTables.isNotEmpty
              ? _clean(validInternalTables.first['tabla_destino'])
              : _clean(widget.format['tabla_destino']));
      internalTableRows = validInternalTables;
      selectedTableName = resolvedTable;
      final attendanceCaptureBlocked = _attendanceCaptureBlocked(resolvedTable);

      if (resolvedTable == null) {
        setState(() {
          tableName = null;
          records = [];
          displayColumns = [];
          _knownTotalRows = null;
          loading = false;
          canExport = exportAllowed;
          canImport = importAllowed && !attendanceCaptureBlocked;
          canInsert = insertAllowed && !attendanceCaptureBlocked;
          canUpdate = updateAllowed && !attendanceCaptureBlocked;
          canDelete = deleteAllowed && !attendanceCaptureBlocked;
          canReview = reviewAllowed && !attendanceCaptureBlocked;
          canApprove = approveAllowed && !attendanceCaptureBlocked;
          error = 'Este formato no tiene tabla destino configurada.';
        });
        return;
      }

      _setLoadingMessage('Cargando columnas y catálogos...');
      await Future<void>.delayed(Duration.zero);
      await _loadDynamicFormCaches(activeTable: resolvedTable);

      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        final needsFullLocalDataset =
            _hasAnyActiveFilters || _sortColumn != null;
        final cachedData = needsFullLocalDataset
            ? await _fetchLocalMatrixRecords(resolvedTable)
            : await _fetchLocalMatrixRecordsPaged(
                resolvedTable,
                page: _currentPage,
                pageSize: _pageSize,
              );
        final filteredCachedRows = needsFullLocalDataset
            ? _filterAndSortRows(cachedData.rows)
            : cachedData.rows;
        final cachedRows = needsFullLocalDataset
            ? filteredCachedRows
                .skip(_currentPage * _pageSize)
                .take(_pageSize)
                .toList()
            : filteredCachedRows.take(_pageSize).toList();
        if (!mounted) return;
        setState(() {
          tableName = resolvedTable;
          records = cachedRows;
          displayColumns =
              _matrixColumnsForTable(resolvedTable, cachedData.columns);
          _knownTotalRows = needsFullLocalDataset
              ? filteredCachedRows.length
              : cachedData.totalRows;
          _hasNextPage = _knownTotalRows != null &&
              ((_currentPage + 1) * _pageSize) < _knownTotalRows!;
          _renderRowLimit = cachedRows.length;
          _invalidateFilteredCache();
          loading = false;
          offline = true;
          canExport = exportAllowed;
          canImport = importAllowed && !attendanceCaptureBlocked;
          canInsert = insertAllowed && !attendanceCaptureBlocked;
          canUpdate = updateAllowed && !attendanceCaptureBlocked;
          canDelete = deleteAllowed && !attendanceCaptureBlocked;
          canReview = reviewAllowed && !attendanceCaptureBlocked;
          canApprove = approveAllowed && !attendanceCaptureBlocked;
        });
        return;
      }

      _setLoadingMessage('Cargando página de registros...');
      await Future<void>.delayed(Duration.zero);

      // Regla crítica de grilla Windows:
      // 1) Sin filtros/orden: cargar solo la página remota/local para velocidad.
      // 2) Con filtros/orden: filtrar/ordenar sobre el dataset completo y recién luego paginar.
      //    Antes se paginaba primero y se filtraba después; por eso un rango con 142 filas
      //    aparecía repartido en decenas de páginas con 3-5 filas por página.
      await _preparePayrollLifecycle(resolvedTable);

      final needsFullDatasetForView =
          _hasAnyActiveFilters || _sortColumn != null;
      final data = needsFullDatasetForView
          ? await _fetchDesktopRecords(
              table: resolvedTable,
              formatId: formatId,
              page: 0,
              fetchAll: true,
            )
          : await _fetchDesktopRecords(
              table: resolvedTable,
              formatId: formatId,
              page: _currentPage,
              fetchAll: false,
            );
      if (!mounted || serial != _loadSerial) return;

      late final List<Map<String, dynamic>> loadedRows;
      late final int initialRows;
      late final int? totalRowsForView;
      late final bool hasNextPageForView;

      if (needsFullDatasetForView) {
        final filteredAll = _filterAndSortRows(data.rows);
        totalRowsForView = filteredAll.length;
        final startIndex = _currentPage * _pageSize;
        final pageRows = startIndex >= filteredAll.length
            ? <Map<String, dynamic>>[]
            : filteredAll.skip(startIndex).take(_pageSize + 1).toList();
        hasNextPageForView = pageRows.length > _pageSize;
        loadedRows = pageRows.take(_pageSize).toList();
        initialRows = loadedRows.length;
      } else {
        loadedRows = data.rows.take(_pageSize).toList();
        initialRows = loadedRows.length;
        totalRowsForView = data.totalRows;
        hasNextPageForView = data.rows.length > _pageSize ||
            (data.totalRows != null &&
                ((_currentPage + 1) * _pageSize) < data.totalRows!);
      }

      setState(() {
        tableName = resolvedTable;
        _hasNextPage = hasNextPageForView;
        _knownTotalRows = totalRowsForView;
        records = loadedRows;
        _renderRowLimit = initialRows;
        _invalidateFilteredCache();
        _loadingMessage = 'Cargando tabla...';
        displayColumns = _matrixColumnsForTable(resolvedTable, data.columns);
        loading = false;
        offline = false;
        canExport = exportAllowed;
        canImport = importAllowed && !attendanceCaptureBlocked;
        canInsert = insertAllowed && !attendanceCaptureBlocked;
        canUpdate = updateAllowed && !attendanceCaptureBlocked;
        canDelete = deleteAllowed && !attendanceCaptureBlocked;
        canReview = reviewAllowed && !attendanceCaptureBlocked;
        canApprove = approveAllowed && !attendanceCaptureBlocked;
        _selectedDeleteRowKeys.clear();
        _selectedDeleteRows.clear();
      });
      _notifyDeleteSelectionChanged();
      _scheduleContractRenewalDialog();
      // Fase 3B: caché inteligente por tabla.
      // Guarda metadata liviana de la tabla abierta sin cambiar la fuente de datos.
      // Esto permite saber cuándo se abrió, cuántas filas conoce, página/filtros/sort
      // y deja preparado el terreno para refrescos más finos sin depender de memoria global.
      unawaited(local.upsertTableCacheInfo(
        resolvedTable,
        rowCount: totalRowsForView,
        lastOpenedAt: DateTime.now().toUtc(),
        lastPage: _currentPage,
        lastFilterKey: _currentFilterCacheKey(),
        lastSortColumn: _sortColumn,
        lastSortAscending: _sortAscending,
      ));
      // Fase 3A: después de mostrar la tabla local/paginada, revisar cambios
      // de esa tabla en segundo plano. No bloquea la apertura ni reemplaza
      // el botón Actualizar datos.
      unawaited(
          _refreshTableSilentlyAfterLoad(resolvedTable, formatId, serial));
      // No render progresivo: evita reconstrucciones repetidas al abrir/cambiar tablas.
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      setState(() {
        loading = false;
        if (msg.contains('socket') ||
            msg.contains('network') ||
            msg.contains('failed host') ||
            msg.contains('connection')) {
          offline = true;
        } else {
          error = e.toString();
        }
      });
    }
  }

  List<String> _dateColumns() {
    final output = <String>[];
    final seen = <String>{};
    for (final column in displayColumns) {
      final type = _columnType(column);
      final normalized = _norm(column);
      if ((type == 'date' || normalized.contains('FECHA')) &&
          seen.add(normalized)) {
        output.add(column);
      }
    }
    final currentTable = _norm(tableName ?? selectedTableName ?? '');
    for (final field in allLocalFormFields) {
      if (currentTable.isNotEmpty &&
          _norm(field['tabla_destino']?.toString() ?? '') != currentTable) {
        continue;
      }
      final type = field['tipo']?.toString().trim().toLowerCase() ?? '';
      final uiType = field['tipo_ui']?.toString().trim().toLowerCase() ?? '';
      final column = field['campo']?.toString().trim() ?? '';
      if (column.isEmpty) continue;
      if ((type == 'date' ||
              type == 'datetime' ||
              type == 'timestamp' ||
              uiType == 'date' ||
              uiType == 'datetime') &&
          seen.add(_norm(column))) {
        output.add(column);
      }
    }
    return output;
  }

  static const Map<String, String> _periodLabels = {
    'year': 'Año',
    'month_name': 'Nombre del mes',
    'month_number': 'Número de mes',
    'week': 'Semana del año',
    'weekday_number': 'Día de semana',
    'weekday_name': 'Nombre del día',
  };

  String _periodValue(DateTime date, String dimension) {
    const monthNames = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    const weekdayNames = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];
    switch (dimension) {
      case 'month_name':
        return monthNames[date.month - 1];
      case 'month_number':
        return date.month.toString().padLeft(2, '0');
      case 'week':
        return _isoWeek(date).toString().padLeft(2, '0');
      case 'weekday_number':
        return date.weekday.toString();
      case 'weekday_name':
        return weekdayNames[date.weekday - 1];
      default:
        return date.year.toString();
    }
  }

  List<String> _periodValues(String key) {
    final parts = key.split('::');
    if (parts.length != 2) return const [];
    final values = <String>{};
    for (final row in records) {
      final date = _parseDate(_valueByColumn(row, parts.first));
      if (date != null) values.add(_periodValue(date, parts.last));
    }
    final output = values.toList()..sort();
    return output;
  }

  Future<void> _showAddFilterDialog() async {
    final mode = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Agregar filtro'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.view_column_outlined),
                ),
                title: const Text('Seleccionar campo(s)'),
                subtitle: const Text(
                  'Agrega uno o varios campos disponibles en esta tabla.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(dialogContext, 'fields'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.calendar_month_outlined),
                ),
                title: const Text('Crear periodo'),
                subtitle: const Text(
                  'Usa una fecha base para filtrar por año, mes, semana o día.',
                ),
                trailing: const Icon(Icons.chevron_right),
                enabled: _dateColumns().isNotEmpty,
                onTap: _dateColumns().isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, 'period'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (!mounted || mode == null) return;
    if (mode == 'fields') {
      await _selectFilterFields();
    } else {
      await _selectPeriodFilters();
    }
  }

  Future<void> _selectFilterFields() async {
    final available = _visibleWindowsColumns(displayColumns);
    final selected = Set<String>.from(_visibleFilterFields);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Seleccionar campo(s)'),
          content: SizedBox(
            width: 520,
            height: 430,
            child: available.isEmpty
                ? const Center(child: Text('No hay campos disponibles.'))
                : ListView.builder(
                    itemCount: available.length,
                    itemBuilder: (_, index) {
                      final column = available[index];
                      return CheckboxListTile(
                        value: selected.contains(column),
                        title: Text(_tableHeaderLabel(column)),
                        subtitle: Text(column),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (value) => setDialogState(() {
                          if (value == true) {
                            selected.add(column);
                          } else {
                            selected.remove(column);
                          }
                        }),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _visibleFilterFields
        ..clear()
        ..addAll(result);
      _columnFilters.removeWhere((column, _) => !result.contains(column));
    });
  }

  Future<void> _selectPeriodFilters() async {
    final dateColumns = _dateColumns();
    if (dateColumns.isEmpty) return;
    var baseDate = dateColumns.first;
    final dimensions = <String>{};
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Crear periodo'),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: baseDate,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Fecha base',
                    helperText:
                        'Sólo se muestran campos de fecha o fecha y hora.',
                    border: OutlineInputBorder(),
                  ),
                  items: dateColumns
                      .map((column) => DropdownMenuItem(
                            value: column,
                            child: Text(_tableHeaderLabel(column)),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => baseDate = value ?? baseDate),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Periodos disponibles',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _periodLabels.entries
                      .map((entry) => FilterChip(
                            selected: dimensions.contains(entry.key),
                            label: Text(entry.value),
                            onSelected: (selected) => setDialogState(() {
                              if (selected) {
                                dimensions.add(entry.key);
                              } else {
                                dimensions.remove(entry.key);
                              }
                            }),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: dimensions.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, {
                        'field': baseDate,
                        'dimensions': dimensions.toList(),
                      }),
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    final field = result['field']?.toString() ?? '';
    final selectedDimensions = (result['dimensions'] as List? ?? const [])
        .map((value) => value.toString());
    setState(() {
      for (final dimension in selectedDimensions) {
        final key = '$field::$dimension';
        _periodFilterKeys.add(key);
        _periodFilterValues.putIfAbsent(key, () => null);
      }
    });
  }

  String _columnFilterSummary(String encoded) {
    final filter = _decodeColumnFilter(encoded);
    final mode = filter['mode'] ?? 'contains';
    if (mode.startsWith('between')) {
      final start = filter['start']?.trim() ?? '';
      final end = filter['end']?.trim() ?? '';
      return [start, end].where((value) => value.isNotEmpty).join(' – ');
    }
    final value = filter['value']?.trim() ?? '';
    if (mode == 'multiple' && value.isNotEmpty) {
      final count = value
          .split(RegExp(r'[;|,]'))
          .where((item) => item.trim().isNotEmpty)
          .length;
      return count == 1 ? value : '$count valores';
    }
    return value.isNotEmpty ? value : 'Todos';
  }

  Widget _fieldFilterControl(String column) {
    final encoded = _columnFilters[column];
    return SizedBox(
      height: 44,
      width: 218,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: const BorderSide(color: Color(0xFFC8D4DF)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showColumnValueFilterDialog(column),
          child: Row(
            children: [
              const SizedBox(width: 10),
              const Icon(Icons.filter_alt_outlined,
                  size: 17, color: Color(0xFF147A6E)),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tableHeaderLabel(column),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF4A6075),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      encoded == null ? 'Todos' : _columnFilterSummary(encoded),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF17324D),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Quitar filtro',
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  setState(() {
                    _visibleFilterFields.remove(column);
                    _columnFilters.remove(column);
                    _invalidateFilteredCache();
                  });
                  unawaited(_load());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _periodFilterControl(String key) {
    final parts = key.split('::');
    final field = parts.first;
    final dimension = parts.length > 1 ? parts.last : 'year';
    final values = _periodValues(key);
    return Container(
      height: 44,
      width: 218,
      padding: const EdgeInsets.only(left: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFC8D4DF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _periodFilterValues[key],
                isExpanded: true,
                hint: Text(
                  '${_periodLabels[dimension]} · ${_tableHeaderLabel(field)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('Todos'),
                  ),
                  ...values.map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(value, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (value) => _applyTopFilter(
                  () => _periodFilterValues[key] = value,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Quitar filtro',
            icon: const Icon(Icons.close, size: 16),
            onPressed: () {
              setState(() {
                _periodFilterKeys.remove(key);
                _periodFilterValues.remove(key);
                _invalidateFilteredCache();
              });
              unawaited(_load());
            },
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filterAndSortRows(
      List<Map<String, dynamic>> sourceRows) {
    final filtered = sourceRows.where((row) {
      if (_isDeletedRecord(row)) return false;
      final fecha = _dateValue(row);
      final variedad =
          _value(row, ['VARIEDAD', 'VARIEDADES'])?.toString().trim() ?? '';
      final lote = _value(row, ['LOTE', 'LOTES'])?.toString().trim() ?? '';
      final turno =
          _value(row, ['TURNO', 'TURNOS', 'FECHA O TURNO', 'FECHA_O_TURNO'])
                  ?.toString()
                  .trim() ??
              '';

      if (yearFilter != null && fecha?.year.toString() != yearFilter)
        return false;
      if (weekFilter != null &&
          fecha != null &&
          _isoWeek(fecha).toString().padLeft(2, '0') != weekFilter)
        return false;
      if (monthFilter != null &&
          fecha?.month.toString().padLeft(2, '0') != monthFilter) return false;
      if (dateFilter != null &&
          (fecha == null || _dateKey(fecha) != dateFilter)) return false;
      if (startDateFilter != null) {
        if (fecha == null) return false;
        final start = DateTime(startDateFilter!.year, startDateFilter!.month,
            startDateFilter!.day);
        final current = DateTime(fecha.year, fecha.month, fecha.day);
        if (current.isBefore(start)) return false;
      }
      if (endDateFilter != null) {
        if (fecha == null) return false;
        final end = DateTime(
            endDateFilter!.year, endDateFilter!.month, endDateFilter!.day);
        final current = DateTime(fecha.year, fecha.month, fecha.day);
        if (current.isAfter(end)) return false;
      }
      if (varietyFilter != null && variedad != varietyFilter) return false;
      if (loteFilter != null && lote != loteFilter) return false;
      if (turnoFilter != null && turno != turnoFilter) return false;
      for (final entry in _columnFilters.entries) {
        if (!_matchesColumnFilter(row, entry.key, entry.value)) return false;
      }
      for (final key in _periodFilterKeys) {
        final selected = _periodFilterValues[key];
        if (selected == null || selected.isEmpty) continue;
        final parts = key.split('::');
        if (parts.length != 2) continue;
        final date = _parseDate(_valueByColumn(row, parts.first));
        if (date == null || _periodValue(date, parts.last) != selected) {
          return false;
        }
      }
      return true;
    }).toList();
    String stableRowKey(Map<String, dynamic> row) {
      for (final candidate in const [
        'id_local',
        'ID_LOCAL',
        'id',
        'ID',
        'ID_REGISTRO',
        'id_registro',
        'Dni',
        'DNI',
      ]) {
        final value = _valueByColumn(row, candidate)?.toString().trim() ?? '';
        if (value.isNotEmpty) return '$candidate:$value';
      }
      final keys = row.keys.toList()..sort();
      return jsonEncode({for (final key in keys) key: row[key]});
    }

    final sortColumn = _sortColumn;
    filtered.sort((a, b) {
      var result = 0;
      if (sortColumn != null) {
        final av = _valueByColumn(a, sortColumn);
        final bv = _valueByColumn(b, sortColumn);
        final an = num.tryParse(av?.toString() ?? '');
        final bn = num.tryParse(bv?.toString() ?? '');
        if (an != null && bn != null) {
          result = an.compareTo(bn);
        } else {
          final ad = _parseDate(av);
          final bd = _parseDate(bv);
          if (ad != null && bd != null) {
            result = ad.compareTo(bd);
          } else {
            result = (av?.toString() ?? '')
                .toLowerCase()
                .compareTo((bv?.toString() ?? '').toLowerCase());
          }
        }
        if (!_sortAscending) result = -result;
      }
      if (result != 0) return result;
      return stableRowKey(a).compareTo(stableRowKey(b));
    });
    return filtered;
  }

  List<Map<String, dynamic>> get filteredRecords {
    final cacheKey = _currentFilterCacheKey();
    if (_filteredCacheKey == cacheKey && _filteredCache != null)
      return _filteredCache!;
    final filtered = _filterAndSortRows(records);
    _filteredCacheKey = cacheKey;
    _filteredCache = filtered;
    return filtered;
  }

  bool get _hasAnyActiveFilters =>
      yearFilter != null ||
      weekFilter != null ||
      monthFilter != null ||
      dateFilter != null ||
      startDateFilter != null ||
      endDateFilter != null ||
      varietyFilter != null ||
      loteFilter != null ||
      turnoFilter != null ||
      _columnFilters.isNotEmpty ||
      _periodFilterValues.values.any((value) => value?.isNotEmpty == true);

  void _clearAllFilters() {
    if (!_hasAnyActiveFilters) return;
    yearFilter = null;
    weekFilter = null;
    monthFilter = null;
    dateFilter = null;
    startDateFilter = null;
    endDateFilter = null;
    varietyFilter = null;
    loteFilter = null;
    turnoFilter = null;
    _columnFilters.clear();
    for (final key in _periodFilterKeys) {
      _periodFilterValues[key] = null;
    }
    _currentPage = 0;
    _invalidateFilteredCache();
    // Al limpiar filtros volvemos a cargar paginado normal.
    unawaited(_load());
  }

  void _applyTopFilter(VoidCallback update) {
    update();
    _currentPage = 0;
    _invalidateFilteredCache();
    // Los filtros deben aplicarse antes de paginar. Recargamos la vista para
    // calcular el total filtrado y mostrar páginas completas del subconjunto.
    unawaited(_load());
  }

  String _columnType(String column) {
    // La tabla Windows debe clasificar el filtro por el TIPO REAL del campo
    // configurado en MATRIZ_CAMPOS_FORMATO_APPGT, no por tipo_ui.
    // Antes se buscaba en fieldDefsById global; si había campos repetidos en
    // otras tablas podía resolver otra definición y tratar un numeric como text.
    final def = _fieldDefForCurrentTableColumn(column);
    final tipo = def?['tipo']?.toString().trim().toLowerCase() ?? '';
    final tipoUi = def?['tipo_ui']?.toString().trim().toLowerCase() ?? '';
    if (_isNumericImportType(tipo)) return 'numeric';
    if (tipo == 'date' || tipo == 'datetime' || tipo == 'timestamp')
      return 'date';
    if (tipo == 'time') return 'time';

    // Respaldo defensivo: si tipo vino vacío/incorrecto pero tipo_ui indica número
    // o fórmula numérica, mantener filtros numéricos.
    if (tipoUi == 'number' ||
        tipoUi == 'numeric' ||
        tipoUi == 'decimal' ||
        tipoUi == 'integer') return 'numeric';
    if (tipoUi == 'date') return 'date';
    return 'text';
  }

  Map<String, String> _decodeColumnFilter(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
            (key, value) => MapEntry(key.toString(), value?.toString() ?? ''));
      }
    } catch (_) {}
    return {'mode': 'contains', 'value': raw};
  }

  bool _matchesColumnFilter(
      Map<String, dynamic> row, String column, String rawFilter) {
    final filter = _decodeColumnFilter(rawFilter);
    final mode = filter['mode'] ?? 'contains';
    final value = filter['value'] ?? '';
    final cell = _valueByColumn(row, column);
    final text = cell?.toString().trim() ?? '';
    if (value.trim().isEmpty &&
        (filter['start'] ?? '').isEmpty &&
        (filter['end'] ?? '').isEmpty) return true;

    if (mode == 'equals')
      return text.toLowerCase() == value.toLowerCase().trim();
    if (mode == 'contains')
      return text.toLowerCase().contains(value.toLowerCase().trim());
    if (mode == 'multiple') {
      final options = value
          .split(RegExp(r'[;|,]'))
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
      return options.contains(text.toLowerCase());
    }
    if (mode == 'between_date') {
      final d = _parseDate(cell);
      if (d == null) return false;
      final start = _parseDate(filter['start']);
      final end = _parseDate(filter['end']);
      final current = DateTime(d.year, d.month, d.day);
      if (start != null &&
          current.isBefore(DateTime(start.year, start.month, start.day)))
        return false;
      if (end != null &&
          current.isAfter(DateTime(end.year, end.month, end.day))) return false;
      return true;
    }
    if (mode == 'between_numeric') {
      final n = num.tryParse(text.replaceAll(',', '.'));
      if (n == null) return false;
      final start = num.tryParse((filter['start'] ?? '').replaceAll(',', '.'));
      final end = num.tryParse((filter['end'] ?? '').replaceAll(',', '.'));
      if (start != null && n < start) return false;
      if (end != null && n > end) return false;
      return true;
    }
    return text.toLowerCase().contains(value.toLowerCase().trim());
  }

  List<String> _distinctColumnValues(String column) {
    final values = <String>{};
    for (final row in records) {
      final value = _valueByColumn(row, column)?.toString().trim() ?? '';
      if (value.isNotEmpty) values.add(value);
    }
    final ordered = values.toList();
    ordered.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ordered;
  }

  Future<void> _showColumnValueFilterDialog(String column) async {
    final values = _distinctColumnValues(column);
    final current = _columnFilters[column] == null
        ? <String, String>{}
        : _decodeColumnFilter(_columnFilters[column]!);
    final selected = <String>{};
    if (current['mode'] == 'multiple') {
      selected.addAll((current['value'] ?? '')
          .split(RegExp(r'[;|,]'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty));
    } else if (current['mode'] == 'equals' &&
        (current['value'] ?? '').trim().isNotEmpty) {
      selected.add(current['value']!.trim());
    }
    for (final value in selected) {
      if (!values.contains(value)) values.add(value);
    }
    var search = '';
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final visible = values
              .where((value) =>
                  value.toLowerCase().contains(search.trim().toLowerCase()))
              .toList(growable: false);
          return AlertDialog(
            title: Text('Filtrar ${_tableHeaderLabel(column)}'),
            content: SizedBox(
              width: 480,
              height: 480,
              child: Column(
                children: [
                  TextField(
                    autofocus: values.length > 12,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Buscar valor…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) => setDialogState(() => search = value),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => setDialogState(() {
                          selected
                            ..clear()
                            ..addAll(visible);
                        }),
                        icon: const Icon(Icons.done_all_rounded, size: 18),
                        label: const Text('Seleccionar visibles'),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setDialogState(() => selected.clear()),
                        child: const Text('Limpiar'),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: values.isEmpty
                        ? const Center(
                            child: Text('Esta columna no contiene valores.'))
                        : visible.isEmpty
                            ? const Center(child: Text('No hay coincidencias.'))
                            : ListView.builder(
                                itemCount: visible.length,
                                itemBuilder: (_, index) {
                                  final value = visible[index];
                                  return CheckboxListTile(
                                    dense: true,
                                    value: selected.contains(value),
                                    title: Text(value),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    onChanged: (checked) => setDialogState(() {
                                      if (checked == true) {
                                        selected.add(value);
                                      } else {
                                        selected.remove(value);
                                      }
                                    }),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.pop(dialogContext, Set<String>.from(selected)),
                icon: const Icon(Icons.filter_alt_rounded, size: 18),
                label: const Text('Aplicar'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.isEmpty || result.length == values.length) {
        _columnFilters.remove(column);
      } else {
        _columnFilters[column] = jsonEncode({
          'mode': 'multiple',
          'value': result.join(';'),
        });
      }
      _visibleFilterFields.add(column);
      _currentPage = 0;
      _renderRowLimit = _pageSize;
      _invalidateFilteredCache();
      _filterControlsVersion.value++;
    });
    await _load();
  }

  Future<void> _showColumnFilterDialog(String column) async {
    final columnType = _columnType(column);
    final storedFilter = _columnFilters[column];
    final current = storedFilter == null
        ? <String, String>{}
        : _decodeColumnFilter(storedFilter);
    var mode = current['mode'] ??
        (columnType == 'date' || columnType == 'numeric'
            ? 'between_${columnType == 'date' ? 'date' : 'numeric'}'
            : 'contains');
    final valueController = TextEditingController(text: current['value'] ?? '');
    final startController = TextEditingController(text: current['start'] ?? '');
    final endController = TextEditingController(text: current['end'] ?? '');

    List<DropdownMenuItem<String>> modes() {
      if (columnType == 'date') {
        return const [
          DropdownMenuItem(value: 'between_date', child: Text('Entre')),
          DropdownMenuItem(value: 'equals', child: Text('Igual a')),
        ];
      }
      if (columnType == 'numeric') {
        return const [
          DropdownMenuItem(value: 'between_numeric', child: Text('Entre')),
          DropdownMenuItem(value: 'equals', child: Text('Igual a')),
          DropdownMenuItem(value: 'contains', child: Text('Contiene')),
        ];
      }
      return const [
        DropdownMenuItem(value: 'equals', child: Text('Igual a')),
        DropdownMenuItem(value: 'contains', child: Text('Contiene')),
        DropdownMenuItem(value: 'multiple', child: Text('Múltiple')),
      ];
    }

    final result = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
          final isBetween = mode == 'between_date' || mode == 'between_numeric';
          final hint = mode == 'multiple'
              ? 'Ejemplo: T1;T2;T3'
              : mode == 'equals'
                  ? (columnType == 'date'
                      ? 'Ejemplo: 08/06/2026'
                      : 'Ejemplo: valor exacto')
                  : columnType == 'numeric'
                      ? 'Ejemplo: 12.5'
                      : 'Ejemplo: sanidad';
          return AlertDialog(
            title: Text('Filtrar $column'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: mode,
                    decoration: const InputDecoration(
                        labelText: 'Modo de filtro',
                        border: OutlineInputBorder()),
                    items: modes(),
                    onChanged: (v) => setLocalState(() => mode = v ?? mode),
                  ),
                  const SizedBox(height: 12),
                  if (isBetween) ...[
                    TextField(
                      controller: startController,
                      decoration: InputDecoration(
                        labelText: 'Inicio',
                        hintText:
                            columnType == 'date' ? 'dd/mm/yyyy' : 'Ejemplo: 10',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: endController,
                      decoration: InputDecoration(
                        labelText: 'Fin',
                        hintText:
                            columnType == 'date' ? 'dd/mm/yyyy' : 'Ejemplo: 20',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ] else
                    TextField(
                      controller: valueController,
                      decoration: InputDecoration(
                        labelText: 'Valor',
                        hintText: hint,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, ''),
                  child: const Text('Limpiar')),
              FilledButton(
                onPressed: () {
                  final payload = jsonEncode({
                    'mode': mode,
                    'value': valueController.text.trim(),
                    'start': startController.text.trim(),
                    'end': endController.text.trim(),
                  });
                  Navigator.pop(context, payload);
                },
                child: const Text('Aplicar'),
              ),
            ],
          );
        },
      ),
    );
    valueController.dispose();
    startController.dispose();
    endController.dispose();
    if (result == null) return;
    final previous = _columnFilters[column];
    if ((result.isEmpty && previous == null) || result == previous) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    if (result.isEmpty) {
      _columnFilters.remove(column);
    } else {
      _columnFilters[column] = result;
    }
    _visibleFilterFields.add(column);
    _currentPage = 0;
    _renderRowLimit = _pageSize;
    _invalidateFilteredCache();
    // Igual que filtros superiores: primero se filtra el conjunto completo y
    // recién después se pagina. No se debe filtrar solo la página visible.
    await _load();
  }

  double _autoWidthForColumn(
      String column, List<Map<String, dynamic>> sourceRows) {
    var maxLen = column.length;
    for (final row in sourceRows.take(80)) {
      final len = _displayCellValue(_valueByColumn(row, column)).length;
      if (len > maxLen) maxLen = len;
    }
    return (maxLen * 8.5 + 36).clamp(110.0, 420.0);
  }

  String _safeFileName(String value) {
    final clean = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return clean.isEmpty ? 'exportacion' : clean;
  }

  Directory _downloadsDirectory() {
    final userProfile = Platform.environment['USERPROFILE'];
    if (Platform.isWindows &&
        userProfile != null &&
        userProfile.trim().isNotEmpty) {
      final dir = Directory('$userProfile\\Downloads');
      if (dir.existsSync()) return dir;
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) {
      final dir = Directory('$home/Downloads');
      if (dir.existsSync()) return dir;
    }
    return Directory.current;
  }

  String _exportText(dynamic value) {
    if (value == null) return '';
    if (value is List || value is Map) return jsonEncode(value);
    return value.toString();
  }

  List<String> _exportHeadersForColumns(List<String> columns) {
    return columns.map(_tableHeaderLabel).toList();
  }

  String _exportCellText(String column, Map<String, dynamic> row) {
    final value = _valueByColumn(row, column);
    final text = _exportText(value);
    if (text.trim().isEmpty) return '';

    // En exportación, fotos y firmas se escriben como ruta/link/texto,
    // nunca como imagen incrustada ni marcador [IMAGEN]/[FIRMA].
    return text;
  }

  Future<String> _exportHtmlCell(
      String column, Map<String, dynamic> row) async {
    String htmlEscape(String value) => const HtmlEscape().convert(value);
    final value = _valueByColumn(row, column);
    final text = _exportText(value);
    if (text.trim().isEmpty) return '';

    // Exportación liviana: en fotos y firmas NO se incrusta imagen.
    // Se deja el valor/ruta/link en la celda para que el archivo pese poco
    // y para que importación pueda leer nuevamente el mismo valor.
    if (_isMediaColumn(column)) return htmlEscape(text);

    return htmlEscape(text);
  }

  String _csvEscape(String value) {
    final needsQuotes = value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r') ||
        value.contains(';');
    final escaped = value.replaceAll('"', '""');
    return needsQuotes ? '"$escaped"' : escaped;
  }

  String _exportFileName(String extension) {
    final table = tableName ??
        widget.format['tabla_destino']?.toString() ??
        widget.format['id']?.toString() ??
        'tabla';
    final stamp =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:\.]'), '-');
    return '${_safeFileName(table)}_$stamp.$extension';
  }

  Future<String> _writeExportFile(String extension, Uint8List bytes) async {
    final fileName = _exportFileName(extension);
    if (kIsWeb) {
      await downloadFileBytes(
        fileName: fileName,
        bytes: bytes,
      );
      return fileName;
    }
    final file = File('${_downloadsDirectory().path}\\$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _exportCsv(
      List<String> columns, List<Map<String, dynamic>> rows) async {
    final buffer = StringBuffer();
    buffer.writeln(_exportHeadersForColumns(columns).map(_csvEscape).join(','));
    for (final row in rows) {
      buffer.writeln(
          columns.map((c) => _csvEscape(_exportCellText(c, row))).join(','));
    }
    final bytes = Uint8List.fromList(utf8.encode('\uFEFF${buffer.toString()}'));
    final file = await _writeExportFile('csv', bytes);
    _showExportDone(file);
  }

  Future<void> _exportExcel(
      List<String> columns, List<Map<String, dynamic>> rows) async {
    String htmlEscape(String value) => const HtmlEscape().convert(value);
    final buffer = StringBuffer();
    buffer.writeln(
        '<html><head><meta charset="utf-8"></head><body><table border="1">');
    buffer.writeln(
        '<tr>${_exportHeadersForColumns(columns).map((c) => '<th>${htmlEscape(c)}</th>').join()}</tr>');
    for (final row in rows) {
      final cells = <String>[];
      for (final c in columns) {
        cells.add('<td>${await _exportHtmlCell(c, row)}</td>');
      }
      buffer.writeln('<tr>${cells.join()}</tr>');
    }
    buffer.writeln('</table></body></html>');
    final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
    final file = await _writeExportFile('xls', bytes);
    _showExportDone(file);
  }

  Future<void> _exportPdf(
      List<String> columns, List<Map<String, dynamic>> rows) async {
    final pdf = pw.Document();
    final title = '${widget.format['nombre'] ?? widget.format['id']}';
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(18),
        build: (_) => [
          pw.Text(title,
              style:
                  pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.Text('${_tableVisualName()} · Registros: ${rows.length}',
              style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 10),
          pw.Table.fromTextArray(
            headers: _exportHeadersForColumns(columns),
            data: rows
                .map((row) =>
                    columns.map((c) => _exportCellText(c, row)).toList())
                .toList(),
            headerStyle:
                pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 5),
            cellAlignment: pw.Alignment.centerLeft,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            border: pw.TableBorder.all(width: 0.25, color: PdfColors.grey600),
          ),
        ],
      ),
    );
    final file = await _writeExportFile('pdf', await pdf.save());
    _showExportDone(file);
  }

  void _showExportDone(String path) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          kIsWeb ? 'Descarga preparada: $path' : 'Archivo exportado: $path',
        ),
      ),
    );
  }

  Future<void> _exportRecords(String type) async {
    var rows = filteredRecords;
    var exportColumns = displayColumns;
    if (tableName != null) {
      final allData = await _fetchDesktopRecords(
        table: tableName!,
        formatId: widget.format['id']?.toString() ?? '',
        page: 0,
        fetchAll: true,
      );
      final oldRecords = records;
      records = allData.rows;
      _invalidateFilteredCache();
      rows = filteredRecords;
      records = oldRecords;
      _invalidateFilteredCache();
      exportColumns = _matrixColumnsForTable(tableName!, allData.columns);
    }
    final columns = _matrixColumnsForTable(
        tableName ?? widget.format['tabla_destino']?.toString() ?? '',
        exportColumns.isNotEmpty ? exportColumns : _columnsFromRows(rows));
    if (rows.isEmpty || columns.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay registros para exportar.')),
      );
      return;
    }
    try {
      if (type == 'excel') await _exportExcel(columns, rows);
      if (type == 'pdf') await _exportPdf(columns, rows);
      if (type == 'csv') await _exportCsv(columns, rows);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar: $e')),
      );
    }
  }

  Future<void> _printRecords() async {
    var rows = filteredRecords;
    var printColumns = displayColumns;
    if (tableName != null) {
      final allData = await _fetchDesktopRecords(
        table: tableName!,
        formatId: widget.format['id']?.toString() ?? '',
        page: 0,
        fetchAll: true,
      );
      final oldRecords = records;
      records = allData.rows;
      _invalidateFilteredCache();
      rows = filteredRecords;
      records = oldRecords;
      _invalidateFilteredCache();
      printColumns = _matrixColumnsForTable(tableName!, allData.columns);
    }
    final columns = _matrixColumnsForTable(
        tableName ?? widget.format['tabla_destino']?.toString() ?? '',
        printColumns.isNotEmpty ? printColumns : _columnsFromRows(rows));
    if (rows.isEmpty || columns.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay registros para imprimir.')),
      );
      return;
    }
    try {
      final pdf = pw.Document();
      final title = '${widget.format['nombre'] ?? widget.format['id']}';
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(18),
          build: (_) => [
            pw.Text(title,
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Text('${_tableVisualName()} · Registros: ${rows.length}',
                style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              headers: _exportHeadersForColumns(columns),
              data: rows
                  .map((row) =>
                      columns.map((c) => _exportCellText(c, row)).toList())
                  .toList(),
              headerStyle:
                  pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 5),
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              border: pw.TableBorder.all(width: 0.25, color: PdfColors.grey600),
            ),
          ],
        ),
      );
      final filePath = await _writeExportFile('pdf', await pdf.save());
      if (!kIsWeb) await OpenFilex.open(filePath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF listo para imprimir: $filePath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo preparar impresión: $e')),
      );
    }
  }

  Widget _printButton() {
    return SizedBox(
      height: 44,
      width: 48,
      child: OutlinedButton(
        onPressed: (!loading && !offline && error == null && records.isNotEmpty)
            ? _printRecords
            : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF147A6E),
          side: const BorderSide(color: Color(0xFF147A6E)),
          shape: const RoundedRectangleBorder(),
          padding: EdgeInsets.zero,
        ),
        child: const Icon(Icons.print),
      ),
    );
  }

  bool _fieldVisibleInWindowsTable(Map<String, dynamic> field) {
    final campo = field['campo']?.toString().trim() ?? '';
    final tipoUi = field['tipo_ui']?.toString().trim().toLowerCase() ?? '';
    if (campo.isEmpty || RecordImportUtils.isAutomaticField(field)) {
      return false;
    }
    final visibleTabla = _editBool(field['visible_tabla'] ?? field['visible'],
        defaultValue: true);
    if (!visibleTabla) return false;
    if (tipoUi == 'hidden' || tipoUi == 'hidden_id') return false;
    if (_isHiddenWindowsColumn(campo)) return false;
    return true;
  }

  Future<List<Map<String, dynamic>>> _templateFieldRows() async {
    final table = tableName ?? widget.format['tabla_destino']?.toString();
    if (table == null || table.trim().isEmpty) return const [];

    final fieldRows = await local.where(
      'local_form_fields',
      'tabla_destino = ? and activo = 1',
      [table],
      orderBy: 'orden',
    );

    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final raw in fieldRows) {
      final f = Map<String, dynamic>.from(raw);
      if (!_fieldVisibleInWindowsTable(f)) continue;
      final campo = f['campo']?.toString().trim() ?? '';
      if (seen.add(_norm(campo))) out.add(f);
    }
    return out;
  }

  Future<List<String>> _templateColumns() async {
    final fields = await _templateFieldRows();
    if (fields.isNotEmpty) {
      return fields
          .map((f) => f['campo']?.toString().trim() ?? '')
          .where((campo) => campo.isNotEmpty && campo.toUpperCase() != 'NULL')
          .toList();
    }
    final fallbackColumns =
        displayColumns.isNotEmpty ? displayColumns : _columnsFromRows(records);
    return _visibleWindowsColumns(fallbackColumns)
        .where((column) => !RecordImportUtils.isTechnicalIdentifierName(column))
        .map(_tableHeaderLabel)
        .toList();
  }

  Future<void> _downloadImportTemplate() async {
    try {
      final columns = await _templateColumns();
      if (columns.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('No se encontraron columnas para generar plantilla.')),
        );
        return;
      }

      // Plantilla real XLSX. Mantiene exactamente los nombres de columnas,
      // incluyendo ñ y tildes, sin depender de separadores CSV ni codificación ANSI.
      final book = xlsx.Excel.createExcel();
      final sheet = book['Plantilla'];
      final defaultSheet = book.getDefaultSheet();
      if (defaultSheet != null && defaultSheet != 'Plantilla') {
        book.delete(defaultSheet);
      }

      for (var i = 0; i < columns.length; i++) {
        final cell = sheet
            .cell(xlsx.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = xlsx.TextCellValue(columns[i]);
      }

      final encoded = book.encode();
      if (encoded == null) {
        throw Exception('No se pudo codificar el archivo XLSX.');
      }

      final file = await _writeExportFile('xlsx', Uint8List.fromList(encoded));
      _showExportDone(file);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar la plantilla: $e')),
      );
    }
  }

  String _decodeHtmlEntities(String text) {
    var value = text;
    final numeric = RegExp(r'&#(x?[0-9A-Fa-f]+);');
    value = value.replaceAllMapped(numeric, (m) {
      final raw = m.group(1) ?? '';
      final code = raw.toLowerCase().startsWith('x')
          ? int.tryParse(raw.substring(1), radix: 16)
          : int.tryParse(raw);
      if (code == null) return m.group(0) ?? '';
      try {
        return String.fromCharCode(code);
      } catch (_) {
        return '';
      }
    });
    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  String _cleanImportText(String text) {
    var value = _decodeHtmlEntities(text);
    value = value
        .replaceAll('\uFEFF', '')
        .replaceAll('ï»¿', '')
        .replaceAll('Â»Â¿', '')
        .replaceAll('»¿', '')
        .replaceAll('¿', '')
        .replaceAll('ð»', '')
        .replaceAll('ð', '')
        .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
        .replaceAll(RegExp(r'[\u200B-\u200D\u2060]'), '')
        .trim();
    // Si un archivo de Excel dejó basura antes del primer encabezado, se elimina.
    value =
        value.replaceFirst(RegExp(r'^[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9_]+'), '').trim();
    return value;
  }

  String _decodeImportBytes(Uint8List bytes) {
    // Primero UTF-8 real. Si Excel/Windows guardó como Latin1/ANSI, caemos a latin1.
    // No limpiamos todo el documento aquí porque podríamos romper HTML válido (<table>, <tr>, <th>).
    try {
      return utf8.decode(bytes, allowMalformed: false).replaceAll('\uFEFF', '');
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true).replaceAll('\uFEFF', '');
    }
  }

  String _cleanImportHeader(String value) {
    var h = _stripHtml(value);
    h = _cleanImportText(h);
    h = h
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[\u200B-\u200D\u2060]'), '')
        .trim();
    // Cuando algún conversor deja restos visibles del BOM al inicio.
    h = h.replaceFirst(RegExp(r'^(ï»¿|»¿|¿)+'), '').trim();
    return h;
  }

  String _headerKey(String value) {
    return _norm(_cleanImportHeader(value))
        .replaceAll(RegExp(r'[^A-Z0-9ÑÁÉÍÓÚÜ]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String? _resolveImportColumn(
      String rawHeader, Map<String, String> columnByKey) {
    final key = _headerKey(rawHeader);
    final exact = columnByKey[key];
    if (exact != null) return exact;

    // Casos clásicos: BOM mal leído o símbolos basura pegados al primer encabezado.
    for (final entry in columnByKey.entries) {
      final validKey = entry.key;
      if (validKey.isEmpty) continue;
      if (key.endsWith(validKey) && key.length <= validKey.length + 12)
        return entry.value;
    }
    return null;
  }

  ({int index, List<String?> headers, List<String> rawHeaders})?
      _detectImportHeaderRow(
    List<List<String>> grid,
    Map<String, String> columnByKey,
  ) {
    int bestIndex = -1;
    int bestMatches = 0;
    List<String?> bestHeaders = const [];
    List<String> bestRawHeaders = const [];

    for (var rowIndex = 0;
        rowIndex < grid.length && rowIndex < 25;
        rowIndex++) {
      final rawHeaders = grid[rowIndex].map(_cleanImportHeader).toList();
      if (rawHeaders.every((h) => h.trim().isEmpty)) continue;

      final headers =
          rawHeaders.map((h) => _resolveImportColumn(h, columnByKey)).toList();
      final matches = headers.whereType<String>().length;
      if (matches > bestMatches) {
        bestIndex = rowIndex;
        bestMatches = matches;
        bestHeaders = headers;
        bestRawHeaders = rawHeaders;
      }
    }

    if (bestIndex < 0 || bestMatches == 0) return null;
    return (index: bestIndex, headers: bestHeaders, rawHeaders: bestRawHeaders);
  }

  Future<List<String>> _importableColumns() async {
    final cols = await _templateColumns();
    if (cols.isNotEmpty) return cols;
    return displayColumns.isNotEmpty
        ? displayColumns
        : _columnsFromRows(records);
  }

  String _generateImportCode(String? prefix) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = math.Random.secure();
    final cleanPrefix = (prefix ?? '').trim().toUpperCase();
    final safePrefix = cleanPrefix.isEmpty ? 'REGI' : cleanPrefix;
    final suffix =
        List.generate(16, (_) => chars[rnd.nextInt(chars.length)]).join();
    return '$safePrefix$suffix';
  }

  Future<List<Map<String, dynamic>>> _importFieldRows() async {
    final table = tableName ?? widget.format['tabla_destino']?.toString();
    if (table == null || table.trim().isEmpty) return const [];
    return await local.where(
      'local_form_fields',
      'tabla_destino = ? and activo = 1',
      [table],
      orderBy: 'orden',
    );
  }

  String _fieldLabel(Map<String, dynamic> field, String campo) {
    final label = field['etiqueta']?.toString().trim();
    return (label == null || label.isEmpty) ? campo : label;
  }

  bool _isRequiredField(Map<String, dynamic> field) {
    final v = field['requerido'];
    return v == true || v == 1 || v?.toString().toLowerCase() == 'true';
  }

  bool _isNumericImportType(String type) {
    final t = type.trim().toLowerCase();
    return t == 'number' ||
        t == 'numeric' ||
        t == 'double' ||
        t == 'decimal' ||
        t == 'integer' ||
        t == 'int';
  }

  bool _isDateImportType(String type) {
    final t = type.trim().toLowerCase();
    return t == 'date' || t == 'datetime' || t == 'timestamp';
  }

  bool _isTimeImportType(String type) {
    final t = type.trim().toLowerCase();
    return t == 'time';
  }

  String? _normalizeImportTime(String value) {
    final s = value.trim().toLowerCase().replaceAll(' ', '');
    final m24 = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(s);
    if (m24 != null) {
      final h = int.tryParse(m24.group(1)!);
      final mi = int.tryParse(m24.group(2)!);
      final se = int.tryParse(m24.group(3) ?? '0') ?? 0;
      if (h != null &&
          mi != null &&
          h >= 0 &&
          h <= 23 &&
          mi >= 0 &&
          mi <= 59 &&
          se >= 0 &&
          se <= 59) {
        return '${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}:${se.toString().padLeft(2, '0')}';
      }
    }
    final mampm =
        RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?(am|pm)$').firstMatch(s);
    if (mampm != null) {
      var h = int.tryParse(mampm.group(1)!);
      final mi = int.tryParse(mampm.group(2)!);
      final se = int.tryParse(mampm.group(3) ?? '0') ?? 0;
      final ap = mampm.group(4)!;
      if (h != null &&
          mi != null &&
          h >= 1 &&
          h <= 12 &&
          mi >= 0 &&
          mi <= 59 &&
          se >= 0 &&
          se <= 59) {
        if (ap == 'pm' && h != 12) h += 12;
        if (ap == 'am' && h == 12) h = 0;
        return '${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}:${se.toString().padLeft(2, '0')}';
      }
    }
    return null;
  }

  String _generateImportLocalId() {
    // id_local es la llave técnica local/remota y en Supabase está como uuid.
    // En importación no debe generarse con prefijos tipo imp_, porque rompe
    // las tablas donde id_local es uuid.
    return const Uuid().v4();
  }

  dynamic _formatImportValue({
    required String rawValue,
    required String campo,
    required Map<String, dynamic>? field,
    required int rowNumber,
  }) {
    final value = _cleanImportText(rawValue).trim();
    if (value.isEmpty || value.toUpperCase() == 'NULL') return null;

    final tipo = field?['tipo']?.toString().trim().toLowerCase() ?? 'text';
    final tipoUi = field?['tipo_ui']?.toString().trim().toLowerCase() ?? tipo;
    final label = field == null ? campo : _fieldLabel(field, campo);

    if (_isNumericImportType(tipo) &&
        tipoUi != 'dropdown' &&
        tipoUi != 'multiselect') {
      final isPercent = value.contains('%');
      var numericText = value.replaceAll(' ', '').replaceAll(',', '.');
      if (numericText.endsWith('%'))
        numericText = numericText.substring(0, numericText.length - 1);
      final parsed = num.tryParse(numericText);
      if (parsed == null) {
        throw Exception(
            'Fila $rowNumber: el campo "$label" debe ser numérico. Valor recibido: "$value".');
      }
      final finalValue = isPercent ? parsed / 100 : parsed;
      final decimals = field == null ? 0 : _editNumeroDecimales(field);
      final decimalAllowed = field != null &&
          tipo != 'integer' &&
          tipo != 'int' &&
          tipoUi != 'integer' &&
          tipoUi != 'int' &&
          decimals > 0;
      final decimalPart =
          RegExp(r'[.,](\d+)').firstMatch(numericText)?.group(1) ?? '';
      if (!decimalAllowed &&
          decimalPart.isNotEmpty &&
          int.tryParse(decimalPart) != 0) {
        throw Exception(
            'Fila $rowNumber: el campo "$label" no acepta decimales según su configuración.');
      }
      if (decimalAllowed && decimalPart.length > decimals) {
        throw Exception(
            'Fila $rowNumber: el campo "$label" solo acepta $decimals decimal(es).');
      }
      return finalValue;
    }

    if (_isTimeImportType(tipo)) {
      final parsedTime = _normalizeImportTime(value);
      if (parsedTime == null) {
        throw Exception(
            'Fila $rowNumber: el campo "$label" debe ser hora. Usa formato HH:mm, HH:mm:ss, 7:00am o 7:00 pm. Valor recibido: "$value".');
      }
      return parsedTime;
    }

    if (_isDateImportType(tipo)) {
      final normalized = RecordImportUtils.normalizeDate(
        value,
        dateOnly: tipo == 'date',
      );
      if (normalized == null) {
        throw Exception(
            'Fila $rowNumber: el campo "$label" debe ser fecha. Usa formato YYYY-MM-DD o DD/MM/YYYY. Valor recibido: "$value".');
      }
      return normalized;
    }

    return value;
  }

  String _friendlyImportError(Object error) {
    final msg = error.toString();
    final missingColumn =
        RegExp(r"Could not find the '([^']+)' column").firstMatch(msg);
    if (missingColumn != null) {
      return 'El campo "${missingColumn.group(1)}" no existe en el almacenamiento de esta vista. Revise la configuración del campo.';
    }

    final notNull = RegExp(r'null value in column "([^"]+)"').firstMatch(msg);
    if (notNull != null) {
      final column = notNull.group(1) ?? '';
      if (RecordImportUtils.isTechnicalIdentifierName(column)) {
        return 'No se pudo crear automáticamente el identificador técnico "$column". Revise que la columna tenga un generador o valor predeterminado en la base de datos.';
      }
      return 'El campo "${notNull.group(1)}" está marcado como obligatorio y llegó vacío. Revise su configuración antes de importar.';
    }

    final invalidDouble =
        RegExp(r'invalid input syntax for type double precision: "([^"]+)"')
            .firstMatch(msg);
    if (invalidDouble != null) {
      return 'Un campo numérico recibió el valor "${invalidDouble.group(1)}". Guarde 7.50 como número y muestre el símbolo % solo en la aplicación.';
    }

    if (msg.contains('duplicate key value violates unique constraint')) {
      return 'El archivo contiene registros que ya existen o se intentaron importar dos veces. Revise los datos duplicados antes de continuar.';
    }

    if (msg.contains('statement timeout') || msg.contains('code: 57014')) {
      return 'La importación tardó más de lo permitido y no se completó. Inténtelo nuevamente; si el problema continúa, comuníquelo al administrador.';
    }

    return msg.replaceFirst('Exception: ', '');
  }

  Future<Map<String, String>> _importHiddenGeneratedFields() async {
    final table = tableName ?? widget.format['tabla_destino']?.toString();
    if (table == null || table.trim().isEmpty) return const {};

    final fieldRows = await local.where(
      'local_form_fields',
      'tabla_destino = ? and activo = 1',
      [table],
      orderBy: 'orden',
    );

    final result = <String, String>{};
    const technical = {'ID', 'ID_LOCAL', 'ID_FILA_SERIAL', 'PK_ID', 'ID_PK'};

    for (final f in fieldRows) {
      final campo = f['campo']?.toString().trim() ?? '';
      final tipo = f['tipo']?.toString().trim().toLowerCase() ?? '';
      final tipoUi = f['tipo_ui']?.toString().trim().toLowerCase() ?? '';
      if (campo.isEmpty) continue;
      if (technical.contains(_norm(campo))) continue;
      if (tipo != 'hidden_id' && tipoUi != 'hidden_id') continue;

      result[campo] = f['id_generador']?.toString().trim() ?? '';
    }

    return result;
  }

  List<List<String>> _parseCsv(String text) {
    final rows = <List<String>>[];
    final current = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if ((ch == ',' || ch == ';') && !inQuotes) {
        current.add(cell.toString().trim());
        cell.clear();
      } else if ((ch == '\n' || ch == '\r') && !inQuotes) {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        current.add(cell.toString().trim());
        cell.clear();
        if (current.any((e) => e.trim().isNotEmpty))
          rows.add(List<String>.from(current));
        current.clear();
      } else {
        cell.write(ch);
      }
    }
    current.add(cell.toString().trim());
    if (current.any((e) => e.trim().isNotEmpty)) rows.add(current);
    return rows;
  }

  String _stripHtml(String value) {
    final withoutTags = value
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    return _decodeHtmlEntities(withoutTags).trim();
  }

  List<List<String>> _parseHtmlTable(String html) {
    final rows = <List<String>>[];
    final rowRegex =
        RegExp(r'<tr[^>]*>(.*?)</tr>', caseSensitive: false, dotAll: true);
    final cellRegex = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>',
        caseSensitive: false, dotAll: true);
    for (final rowMatch in rowRegex.allMatches(html)) {
      final rawRow = rowMatch.group(1) ?? '';
      final cells = cellRegex
          .allMatches(rawRow)
          .map((m) => _stripHtml(m.group(1) ?? ''))
          .toList();
      if (cells.any((e) => e.trim().isNotEmpty)) rows.add(cells);
    }
    return rows;
  }

  String _excelCellToText(dynamic cellValue) {
    return RecordImportUtils.excelCellToText(cellValue as xlsx.CellValue?);
  }

  List<List<String>> _parseXlsx(Uint8List bytes) {
    final book = xlsx.Excel.decodeBytes(bytes);
    final rows = <List<String>>[];
    for (final tableName in book.tables.keys) {
      final sheet = book.tables[tableName];
      if (sheet == null) continue;
      for (final row in sheet.rows) {
        final cells = row
            .map((cell) => _cleanImportText(_excelCellToText(cell?.value)))
            .toList();
        if (cells.any((e) => e.trim().isNotEmpty)) rows.add(cells);
      }
      if (rows.isNotEmpty) break;
    }
    return rows;
  }

  Future<void> _showImportMessage({
    required String title,
    required String message,
    required _ImportMessageKind kind,
  }) async {
    if (!mounted) return;
    final (color, icon) = switch (kind) {
      _ImportMessageKind.success => (
          const Color(0xFF14866D),
          Icons.check_circle_rounded
        ),
      _ImportMessageKind.warning => (
          const Color(0xFFE09A23),
          Icons.warning_amber_rounded
        ),
      _ImportMessageKind.error => (
          const Color(0xFFC34A4A),
          Icons.error_outline_rounded
        ),
      _ImportMessageKind.info => (
          const Color(0xFF17677F),
          Icons.info_outline_rounded
        ),
    };

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 470),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30, 30, 30, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 38),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF243B53),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: SingleChildScrollView(
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF526576),
                          fontSize: 15,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Aceptar',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmImportFile({
    required String fileName,
    required int rowCount,
    required int ignoredColumnCount,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final ignoredNote = ignoredColumnCount == 0
            ? ''
            : '\n\n$ignoredColumnCount columna(s) no configurada(s) se ignorarán.';
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            icon: Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F4F6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.upload_file_rounded,
                  color: Color(0xFF17677F), size: 34),
            ),
            title: const Text(
              'Confirmar importación',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            content: Text(
              'Se importarán $rowCount fila(s) de "$fileName". '
              'Los campos opcionales vacíos se omitirán y los identificadores '
              'técnicos se crearán automáticamente.$ignoredNote',
              textAlign: TextAlign.center,
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF17677F),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Aceptar'),
              ),
            ],
          ),
        );
      },
    );
    return result ?? false;
  }

  Future<void> _importFile() async {
    final table = tableName;
    if (table == null || table.trim().isEmpty) return;

    // En web, el selector debe abrirse directamente desde el gesto del usuario.
    // Esperar una comprobación de red antes de pickFiles puede hacer que el
    // navegador bloquee silenciosamente el diálogo de archivos.
    if (!kIsWeb) {
      final connectivity = await Connectivity().checkConnectivity();
      if (!SyncService.connectivityIndicatesNetwork(connectivity)) {
        await _showImportMessage(
          title: 'Sin conexión',
          message: 'Conéctate a una red de internet para importar el archivo.',
          kind: _ImportMessageKind.warning,
        );
        return;
      }
    }

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv', 'xls', 'html'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      if (!mounted) return;

      final file = picked.files.first;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final lower = file.name.toLowerCase();

      var grid = <List<String>>[];
      if (lower.endsWith('.xlsx')) {
        grid = _parseXlsx(bytes);
      } else {
        final text = _decodeImportBytes(bytes);
        final decodedText = _decodeHtmlEntities(text);
        if (lower.endsWith('.xls') ||
            lower.endsWith('.html') ||
            decodedText.toLowerCase().contains('<table')) {
          grid = _parseHtmlTable(decodedText);
        }
        if (grid.isEmpty) {
          grid = _parseCsv(decodedText);
        }
      }

      if (grid.length < 2) {
        await _showImportMessage(
          title: 'Archivo sin datos',
          message: 'El archivo no tiene filas con datos para importar.',
          kind: _ImportMessageKind.warning,
        );
        return;
      }

      final validColumns = await _importableColumns();
      final importFields = await _importFieldRows();
      final fieldByCampo = <String, Map<String, dynamic>>{
        for (final f in importFields) (f['campo']?.toString() ?? ''): f,
      };
      final columnByKey = <String, String>{
        // La plantilla descarga encabezados con el nombre real de campo.
        // Se acepta también etiqueta antigua para compatibilidad, pero se guarda por campo real.
        for (final c in validColumns)
          if (!RecordImportUtils.isTechnicalIdentifierName(c)) _headerKey(c): c,
        for (final f in importFields)
          if ((f['campo']?.toString().trim() ?? '').isNotEmpty)
            if (!RecordImportUtils.isAutomaticField(f))
              _headerKey(f['campo'].toString()): f['campo'].toString(),
        for (final f in importFields)
          if ((f['etiqueta']?.toString().trim() ?? '').isNotEmpty &&
              (f['campo']?.toString().trim() ?? '').isNotEmpty)
            if (!RecordImportUtils.isAutomaticField(f))
              _headerKey(f['etiqueta'].toString()): f['campo'].toString(),
      };
      final detected = _detectImportHeaderRow(grid, columnByKey);
      if (detected == null) {
        throw Exception(
            'No se reconocieron encabezados válidos. Descarga nuevamente la plantilla y no cambies los nombres de columna.');
      }

      final rawHeaders = detected.rawHeaders;
      final headers = detected.headers;
      final unknownHeaders = <String>[];
      for (var i = 0; i < rawHeaders.length; i++) {
        final h = rawHeaders[i];
        if (h.trim().isEmpty) continue;
        // Si la fila contiene restos de HTML/XML, los ignoramos.
        if ({'HTML', 'HEAD', 'BODY', 'TABLE', 'TR', 'TH', 'TD', 'LT', 'GT'}
            .contains(_headerKey(h))) {
          continue;
        }
        if (headers[i] == null) {
          unknownHeaders.add(h);
        }
      }
      if (unknownHeaders.isNotEmpty) {
        debugPrint(
            'Columnas ignoradas durante la importación: ${unknownHeaders.join(', ')}');
      }

      final hiddenGeneratedFields = await _importHiddenGeneratedFields();
      final rows = <Map<String, dynamic>>[];
      for (var lineIndex = detected.index + 1;
          lineIndex < grid.length;
          lineIndex++) {
        final line = grid[lineIndex];
        final payload = <String, dynamic>{};
        final rowNumber = lineIndex + 1;
        for (var i = 0; i < headers.length && i < line.length; i++) {
          final h = headers[i];
          if (h == null || h.trim().isEmpty) continue;
          final raw = _cleanImportText(line[i]).trim();
          final field = fieldByCampo[h];
          if (RecordImportUtils.isAutomaticField(field, fallbackName: h)) {
            continue;
          }
          final formatted = _formatImportValue(
              rawValue: raw, campo: h, field: field, rowNumber: rowNumber);
          if (formatted != null) payload[h] = formatted;
        }
        if (payload.isEmpty) continue;

        for (final f in importFields) {
          final campo = f['campo']?.toString().trim() ?? '';
          if (campo.isEmpty) continue;
          if (_isRequiredField(f) &&
              !RecordImportUtils.isAutomaticField(f) &&
              !payload.containsKey(campo)) {
            final label = _fieldLabel(f, campo);
            throw Exception(
                'Fila $rowNumber: llene el campo obligatorio "$label".');
          }
        }

        final nowIso = DateTime.now().toUtc().toIso8601String();
        payload.putIfAbsent('id_local', _generateImportLocalId);
        payload.putIfAbsent('created_at', () => nowIso);
        payload.putIfAbsent('updated_at', () => nowIso);
        payload.putIfAbsent('eliminado', () => false);
        payload.putIfAbsent('estado_sync', () => 'importado');
        payload.putIfAbsent('activo', () => true);

        // Las columnas ocultas tipo hidden_id no vienen en la plantilla,
        // pero algunas tablas las tienen como NOT NULL. Se generan aquí
        // para que la importación funcione en cualquier tabla dinámica.
        for (final entry in hiddenGeneratedFields.entries) {
          payload.putIfAbsent(
              entry.key, () => _generateImportCode(entry.value));
        }

        rows.add(payload);
      }

      if (rows.isEmpty) {
        await _showImportMessage(
          title: 'Sin filas válidas',
          message:
              'No se encontraron datos configurados para importar en este archivo.',
          kind: _ImportMessageKind.warning,
        );
        return;
      }

      final confirmed = await _confirmImportFile(
        fileName: file.name,
        rowCount: rows.length,
        ignoredColumnCount: unknownHeaders.length,
      );
      if (!confirmed) return;
      if (mounted) setState(() => _importingFile = true);

      final importResult = await supabase.rpc(
        'fn_importar_registros_sin_duplicados',
        params: {
          'p_tabla': table,
          'p_registros': rows,
        },
      );

      int recibidas = rows.length;
      int insertadas = rows.length;
      int omitidas = 0;

      if (importResult is List &&
          importResult.isNotEmpty &&
          importResult.first is Map) {
        final r = Map<String, dynamic>.from(importResult.first as Map);
        recibidas =
            int.tryParse(r['filas_recibidas']?.toString() ?? '') ?? recibidas;
        insertadas =
            int.tryParse(r['filas_insertadas']?.toString() ?? '') ?? insertadas;
        omitidas =
            int.tryParse(r['filas_omitidas']?.toString() ?? '') ?? omitidas;
      } else if (importResult is Map) {
        final r = Map<String, dynamic>.from(importResult);
        recibidas =
            int.tryParse(r['filas_recibidas']?.toString() ?? '') ?? recibidas;
        insertadas =
            int.tryParse(r['filas_insertadas']?.toString() ?? '') ?? insertadas;
        omitidas =
            int.tryParse(r['filas_omitidas']?.toString() ?? '') ?? omitidas;
      }

      await _load();
      if (!mounted) return;
      setState(() => _importingFile = false);
      await _showImportMessage(
        title: 'Importación completada',
        message:
            '$insertadas fila(s) importada(s) y $omitidas omitida(s) de $recibidas recibida(s).'
            '${unknownHeaders.isEmpty ? '' : '\n\nLas ${unknownHeaders.length} columna(s) no configurada(s) se ignoraron.'}',
        kind: _ImportMessageKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      if (_importingFile) setState(() => _importingFile = false);
      await _showImportMessage(
        title: 'No se pudo importar',
        message: _friendlyImportError(e),
        kind: _ImportMessageKind.error,
      );
    }
  }

  Widget _importButton() {
    final enabled = canImport &&
        !loading &&
        !_importingFile &&
        error == null &&
        tableName != null;
    if (!enabled) {
      return _unavailableTransferButton(
        icon: Icons.upload_file,
        tooltip: 'Importar',
        message: !canImport
            ? 'No tienes permiso para importar en este formato.'
            : _importingFile
                ? 'La importación está en proceso.'
                : 'La importación estará disponible cuando termine de cargar la tabla.',
      );
    }
    return SizedBox(
      height: 44,
      width: 48,
      child: PopupMenuButton<String>(
        enabled: true,
        tooltip: 'Importar',
        color: const Color(0xFF1B6A82),
        onSelected: (value) async {
          if (value == 'template') await _downloadImportTemplate();
          if (value == 'import') await _importFile();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
              value: 'template',
              child: Text('Descargar plantilla Excel',
                  style: TextStyle(color: Colors.white))),
          PopupMenuItem(
              value: 'import',
              child: Text('Subir archivo Excel/CSV',
                  style: TextStyle(color: Colors.white))),
        ],
        child: Container(
          height: 44,
          width: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF17677F),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE8F3F5)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x22000000), blurRadius: 7, offset: Offset(0, 2))
            ],
          ),
          child: const Icon(Icons.upload_file, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _exportButton() {
    final enabled = canExport && !loading && error == null && tableName != null;
    if (!enabled) {
      return _unavailableTransferButton(
        icon: Icons.download,
        tooltip: 'Exportar',
        message: !canExport
            ? 'No tienes permiso para exportar en este formato.'
            : 'La exportación estará disponible cuando termine de cargar la tabla.',
      );
    }
    return SizedBox(
      height: 44,
      width: 48,
      child: PopupMenuButton<String>(
        enabled: true,
        tooltip: 'Exportar',
        color: const Color(0xFF1B6A82),
        onSelected: _exportRecords,
        itemBuilder: (_) => const [
          PopupMenuItem(
              value: 'excel',
              child: Text('Exportar en Excel',
                  style: TextStyle(color: Colors.white))),
          PopupMenuItem(
              value: 'pdf',
              child: Text('Exportar en PDF',
                  style: TextStyle(color: Colors.white))),
          PopupMenuItem(
              value: 'csv',
              child: Text('Exportar en CSV',
                  style: TextStyle(color: Colors.white))),
        ],
        child: Container(
          height: 44,
          width: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF17677F),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE8F3F5)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x22000000), blurRadius: 7, offset: Offset(0, 2))
            ],
          ),
          child: const Icon(Icons.download, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _unavailableTransferButton({
    required IconData icon,
    required String tooltip,
    required String message,
  }) {
    return SizedBox(
      height: 44,
      width: 48,
      child: Tooltip(
        message: '$tooltip · $message',
        child: Material(
          color: const Color(0xFFE8EEF0),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
            },
            child: Icon(icon, color: const Color(0xFF71838A), size: 20),
          ),
        ),
      ),
    );
  }

  bool get _isPersonalPlanillaTable {
    final t = (tableName ?? widget.format['tabla_destino']?.toString() ?? '')
        .trim()
        .toUpperCase();
    return t == 'GH-REGISTRO_PERSONAL_PLANILLA';
  }

  bool get _isTareoTable => _isNamedTable(
      tableName ?? widget.format['tabla_destino']?.toString(),
      'GT-TAREO_PERSONAL');

  bool get _isPayrollPeriodTable => _isNamedTable(
      tableName ?? widget.format['tabla_destino']?.toString(),
      'PLANILLA_PERIODOS_APPGT');

  bool get _isPayrollSlipTable => _isNamedTable(
      tableName ?? widget.format['tabla_destino']?.toString(),
      'PLANILLA_BOLETAS_APPGT');

  bool get _isPermissionLeaveTable => _isNamedTable(
      tableName ?? widget.format['tabla_destino']?.toString(),
      'GH_PERMISOS_LICENCIAS_APPGT');

  bool get _isSanctionTable => _isNamedTable(
      tableName ?? widget.format['tabla_destino']?.toString(),
      'GH_SANCIONES_PERSONAL_APPGT');

  bool get _isHumanResourcesApprovalTable =>
      _isPermissionLeaveTable || _isSanctionTable;
  Future<void> _authorizeSelectedOvertime() async {
    if (!_isTareoTable || _selectedDeleteRows.isEmpty) return;
    final eligible = _selectedDeleteRows.values.where((row) {
      final required = _boolValue(_value(row, [
        'REQUIERE_HORAS_EXTRA',
        'requiere_horas_extra',
      ]));
      final state = (_value(row, ['ESTADO_HORAS_EXTRA']) ?? '')
          .toString()
          .trim()
          .toUpperCase();
      return required && state == 'SOLICITADO';
    }).toList();
    if (eligible.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Seleccione tareos con horas extra en estado SOLICITADO.'),
      ));
      return;
    }
    final reasonCtrl = TextEditingController();
    try {
      final decision = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Autorizar horas extra'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se procesarán ${eligible.length} tareo(s). La autorización '
                'quedará registrada con usuario, fecha y hora.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Observación de autorización (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Rechazar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Autorizar'),
            ),
          ],
        ),
      );
      if (decision == null) return;
      for (final row in eligible) {
        final id = (_value(row, ['id_local', 'id']) ?? '').toString().trim();
        if (id.isEmpty) continue;
        await supabase.rpc(
          'appgt_autorizar_horas_extra_tareo_v1',
          params: {
            'p_id_local': id,
            'p_autorizar': decision,
            'p_motivo': reasonCtrl.text.trim(),
          },
        );
      }
      _selectedDeleteRowKeys.clear();
      _selectedDeleteRows.clear();
      _notifyDeleteSelectionChanged();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(decision
            ? 'Horas extra autorizadas y auditadas.'
            : 'Horas extra rechazadas y auditadas.'),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo procesar las horas extra: $error')),
      );
    } finally {
      reasonCtrl.dispose();
    }
  }

  Future<void> _runPayrollLifecycle() async {
    if (!_isPayrollPeriodTable || _selectedDeleteRows.length != 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Seleccione un solo periodo de planilla.'),
        ));
      }
      return;
    }
    final row = _selectedDeleteRows.values.single;
    final id = (_value(row, ['id']) ?? '').toString().trim();
    final state = (_value(row, ['estado', 'ESTADO']) ?? 'BORRADOR')
        .toString()
        .trim()
        .toUpperCase();
    final payrollEngine =
        (_value(row, ['motor_calculo', 'MOTOR_CALCULO']) ?? '')
            .toString()
            .trim()
            .toUpperCase();
    if (id.isEmpty) return;

    final actions = <String>[];
    if (state == 'BORRADOR') actions.add('VALIDAR');
    if (state == 'CALCULADA') {
      actions.add('VALIDAR');
      if (payrollEngine != 'REQUIERE_RECALCULO') actions.add('REVISAR');
    }
    if (state == 'REVISADA') actions.add('APROBAR');
    if (state == 'APROBADA') actions.add('CERRAR');
    if (state == 'CERRADA') actions.add('REABRIR');
    if (actions.isEmpty) return;

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Planilla $state'),
        children: actions
            .map((value) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, value),
                  child: ListTile(
                    leading: Icon(switch (value) {
                      'CALCULAR' => Icons.calculate_outlined,
                      'VALIDAR' => Icons.fact_check_outlined,
                      'REVISAR' => Icons.fact_check_outlined,
                      'APROBAR' => Icons.verified_outlined,
                      'CERRAR' => Icons.lock_outline,
                      _ => Icons.lock_open_outlined,
                    }),
                    title: Text(value == 'VALIDAR'
                        ? state == 'BORRADOR'
                            ? 'Validar y calcular'
                            : 'Validar y recalcular'
                        : value),
                  ),
                ))
            .toList(),
      ),
    );
    if (action == null || !mounted) return;

    String reason = '';
    if (action == 'REABRIR') {
      final reasonCtrl = TextEditingController();
      try {
        final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Reabrir planilla cerrada'),
            content: TextField(
              controller: reasonCtrl,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo obligatorio',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  if (reasonCtrl.text.trim().isEmpty) return;
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Reabrir'),
              ),
            ],
          ),
        );
        if (accepted != true) return;
        reason = reasonCtrl.text.trim();
      } finally {
        reasonCtrl.dispose();
      }
    } else if (action == 'CERRAR') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cerrar planilla'),
          content: const Text(
            'Después del cierre se bloquearán asistencia, tareos, permisos y '
            'filas calculadas del periodo. ¿Desea continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (action != 'REABRIR') {
      final isValid = await _validatePayrollPeriodBeforeAction(id);
      if (!isValid || !mounted) return;
    }

    try {
      await supabase.rpc(
        'appgt_cambiar_estado_planilla_periodo_v1',
        params: {
          'p_periodo_id': id,
          'p_accion': action,
          'p_motivo': reason,
        },
      );
      _selectedDeleteRowKeys.clear();
      _selectedDeleteRows.clear();
      _notifyDeleteSelectionChanged();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Acción $action completada y auditada.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo ejecutar $action: $error')),
      );
    }
  }

  Future<bool> _validatePayrollPeriodBeforeAction(String periodId) async {
    try {
      final response = await supabase.rpc(
        'appgt_generar_validaciones_planilla_v2',
        params: {'p_periodo': periodId},
      );
      final errorCount = response is num
          ? response.toInt()
          : int.tryParse(response?.toString() ?? '') ?? 0;
      if (errorCount == 0) return true;

      final responseRows = await supabase
          .from('PLANILLA_VALIDACIONES_APPGT')
          .select('nivel,codigo,dni,mensaje')
          .eq('periodo_id', periodId)
          .eq('resuelto', false)
          .order('id');
      final validations = (responseRows as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
      if (!mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            'Planilla bloqueada: $errorCount '
            '${errorCount == 1 ? 'validacion' : 'validaciones'}',
          ),
          content: SizedBox(
            width: 680,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: validations.length,
                separatorBuilder: (_, __) => const Divider(height: 18),
                itemBuilder: (context, index) {
                  final row = validations[index];
                  final dni = (row['dni'] ?? '').toString().trim();
                  final code = (row['codigo'] ?? '').toString().trim();
                  final message = (row['mensaje'] ?? '').toString().trim();
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                    ),
                    title: Text(message),
                    subtitle: Text([
                      if (dni.isNotEmpty) 'DNI $dni',
                      if (code.isNotEmpty) code,
                    ].join(' - ')),
                  );
                },
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return false;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo validar la planilla: $error')),
      );
      return false;
    }
  }

  Widget _humanWorkflowToolbarButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String tooltip,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF147A6E),
            backgroundColor:
                onPressed == null ? Colors.white : const Color(0xFFF2FAF8),
            side: BorderSide(
              color: onPressed == null
                  ? Colors.grey.shade300
                  : const Color(0xFF147A6E),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: EdgeInsets.zero,
          ),
          child: Icon(icon),
        ),
      ),
    );
  }

  Widget _workflowToolbarMenu() {
    return ValueListenableBuilder<int>(
      valueListenable: _deleteSelectionVersion,
      builder: (context, _, __) {
        final hasSelection = _selectedDeleteRows.isNotEmpty;
        final isDispatchVoucher =
            _isNamedTable(tableName, 'ERP_VALES_DESPACHO_APPGT');
        final mayReview = canReview;
        final mayApprove = canApprove;
        final mayDispatch = isDispatchVoucher && (canApprove || canUpdate);
        final mayAnnul = canUpdate || canDelete;
        final hasAccess = mayReview || mayApprove || mayDispatch || mayAnnul;
        final icon = Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hasAccess ? const Color(0xFF0D5F78) : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle,
            size: 24,
            color: hasAccess ? const Color(0xFF45C86B) : Colors.grey.shade500,
          ),
        );
        return SizedBox(
          width: 44,
          height: 44,
          child: Tooltip(
            message: hasAccess
                ? (hasSelection ? 'Estados del flujo' : 'Seleccione registros')
                : 'Sin acceso',
            child: hasAccess
                ? PopupMenuButton<String>(
                    tooltip: 'Estados del flujo',
                    onSelected: _setSelectedWorkflowState,
                    itemBuilder: (_) => [
                      if (mayReview)
                        PopupMenuItem(
                          value: 'REVISADO',
                          enabled: hasSelection,
                          child: const ListTile(
                            dense: true,
                            leading: Icon(Icons.fact_check_outlined),
                            title: Text('Revisar'),
                          ),
                        ),
                      if (mayApprove)
                        PopupMenuItem(
                          value: 'APROBADO',
                          enabled: hasSelection,
                          child: const ListTile(
                            dense: true,
                            leading: Icon(Icons.verified_outlined),
                            title: Text('Aprobar'),
                          ),
                        ),
                      if (mayDispatch)
                        PopupMenuItem(
                          value: 'DESPACHADO',
                          enabled: hasSelection,
                          child: const ListTile(
                            dense: true,
                            leading: Icon(Icons.local_shipping_outlined),
                            title: Text('Despachar'),
                          ),
                        ),
                      if (mayAnnul)
                        PopupMenuItem(
                          value: 'ANULADO',
                          enabled: hasSelection,
                          child: const ListTile(
                            dense: true,
                            leading: Icon(Icons.block_outlined),
                            title: Text('Anular'),
                          ),
                        ),
                    ],
                    child: icon,
                  )
                : IconButton(onPressed: null, icon: icon),
          ),
        );
      },
    );
  }

  String _payrollSlipFileName(Map<String, dynamic> row) {
    final dni = (_value(row, ['dni', 'DNI']) ?? '').toString().trim();
    final start = (_value(row, ['fecha_inicio']) ?? '').toString().trim();
    final safeDni = dni.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '_');
    final safeStart = start.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '_');
    return 'boleta_${safeDni.isEmpty ? 'trabajador' : safeDni}_${safeStart.isEmpty ? 'periodo' : safeStart}.pdf';
  }

  bool _hasPayrollSlipContext(dynamic value) {
    if (value is Map) return value.isNotEmpty;
    if (value is Iterable) return value.isNotEmpty;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text.isNotEmpty && text != '{}' && text != '[]' && text != 'null';
  }

  Future<dynamic> _loadPayrollSlipContextV2(String slipId) async {
    try {
      return await supabase.rpc(
        'appgt_obtener_contexto_boleta_v2',
        params: {'p_boleta_id': slipId},
      );
    } catch (_) {
      // Instalaciones que aún no aplicaron la migración V2 siguen pudiendo
      // emitir una boleta a partir del snapshot histórico.
      return null;
    }
  }

  Future<Map<String, dynamic>?> _loadPayrollSettlementFallback(
    Map<String, dynamic> slip,
  ) async {
    final settlementId =
        (_value(slip, ['liquidacion_id']) ?? '').toString().trim();
    if (settlementId.isEmpty) return null;
    try {
      final rawSettlement = await supabase
          .from('PLANILLA_LIQUIDACION_TRABAJADOR_APPGT')
          .select()
          .eq('id', settlementId)
          .maybeSingle();
      return rawSettlement == null
          ? null
          : Map<String, dynamic>.from(rawSettlement);
    } catch (_) {
      return null;
    }
  }

  Future<void> _registerPayrollSlipPdfV2({
    required String slipId,
    required String pdfUrl,
  }) async {
    try {
      await supabase.rpc('appgt_registrar_pdf_boleta_v2', params: {
        'p_boleta_id': slipId,
        'p_pdf_url': pdfUrl,
        'p_pdf_version': PayrollSlipPdf.currentVersion,
      });
    } catch (_) {
      // El RPC v1 no conoce la versión, por lo cual su PDF no se reutiliza
      // como V2 en una próxima apertura: se regenerará de forma segura.
      await supabase.rpc('appgt_registrar_pdf_boleta_v1', params: {
        'p_boleta_id': slipId,
        'p_pdf_url': pdfUrl,
      });
    }
  }

  Future<void> _openOrGeneratePayrollSlip(Map<String, dynamic> slip) async {
    final slipId = (_value(slip, ['id']) ?? '').toString().trim();
    if (slipId.isEmpty) return;
    Uint8List? bytes;
    try {
      final stored = (_value(slip, ['pdf_url']) ?? '').toString().trim();
      final storedVersion =
          PayrollSlipPdf.versionOf(_value(slip, ['pdf_version']));
      if (stored.isNotEmpty && storedVersion >= PayrollSlipPdf.currentVersion) {
        final parsed = EvidenceStorage.extractBucketAndPath(stored);
        if (parsed != null) {
          try {
            bytes = await supabase.storage
                .from(parsed.bucket)
                .download(parsed.path);
          } catch (_) {
            // Un enlace V2 vencido o borrado se vuelve a generar abajo.
            bytes = null;
          }
        }
      }
      if (bytes == null) {
        final rpcContext = await _loadPayrollSlipContextV2(slipId);
        final fallbackSettlement = _hasPayrollSlipContext(rpcContext)
            ? null
            : await _loadPayrollSettlementFallback(slip);
        final context = PayrollSlipPdf.contextFromPayload(
          rpcContext,
          fallbackSlip: slip,
          fallbackSnapshot: _value(slip, ['liquidacion_snapshot']),
          fallbackSettlement: fallbackSettlement,
        );
        if (!context.hasLiquidationData) {
          throw StateError(
            'No se encontró el contexto ni la liquidación de esta boleta.',
          );
        }
        bytes = await PayrollSlipPdf.build(context);
        final empresaId =
            (_value(slip, ['empresa_id']) ?? '').toString().trim();
        final periodoId =
            (_value(slip, ['periodo_id']) ?? '').toString().trim();
        final dni = (_value(slip, ['dni']) ?? '').toString().trim();
        if (empresaId.isEmpty || periodoId.isEmpty || dni.isEmpty) {
          throw StateError('Faltan datos de empresa, periodo o DNI.');
        }
        final path =
            '$empresaId/$periodoId/${dni.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '_')}_v${PayrollSlipPdf.currentVersion}.pdf';
        await supabase.storage.from('planilla-boletas').uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(
                  contentType: 'application/pdf', upsert: true),
            );
        await _registerPayrollSlipPdfV2(
          slipId: slipId,
          pdfUrl: EvidenceStorage.toStorageUri(path,
              bucketName: 'planilla-boletas'),
        );
        await _load();
      }
      final file = await _writeExportFile(_payrollSlipFileName(slip), bytes);
      if (!kIsWeb) await OpenFilex.open(file);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                kIsWeb ? 'Boleta PDF preparada.' : 'Boleta abierta: $file')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo preparar la boleta: $error')),
      );
    }
  }

  bool _isHumanResourcesDocumentColumn(String column) {
    if (!_isHumanResourcesApprovalTable) return false;
    return const {'DOCUMENTO_GENERADO', 'DOCUMENTO_SUSTENTO'}
        .contains(_norm(column));
  }

  String _humanResourcesDocumentFileName(
    Map<String, dynamic> row,
    String column,
  ) {
    if (_norm(column) == 'DOCUMENTO_GENERADO') {
      return _isSanctionTable
          ? HumanResourcesRecordPdf.sanctionFileName(row)
          : HumanResourcesRecordPdf.permissionFileName(row);
    }
    return 'documento_sustento.pdf';
  }

  Future<void> _presentHumanResourcesPdf(
    String fileName,
    Uint8List bytes,
  ) async {
    if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw StateError('El archivo almacenado no es un PDF válido.');
    }
    if (kIsWeb) {
      await openPdfBytes(fileName: fileName, bytes: bytes);
      return;
    }
    final dir = _downloadsDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}\\$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await OpenFilex.open(file.path);
  }

  Future<void> _openHumanResourcesStoredDocument(
    Map<String, dynamic> row,
    String column,
  ) async {
    final source = (_value(row, [column]) ?? '').toString().trim();
    if (source.isEmpty || source.toUpperCase() == 'NULL') return;
    try {
      final bytes = await _downloadBytesForPdf(
        source,
        defaultBucket: _norm(column) == 'DOCUMENTO_GENERADO'
            ? EvidenceStorage.laborDocumentsBucket
            : EvidenceStorage.permissionDocumentsBucket,
      );
      if (bytes == null) {
        throw StateError('No se encontró el archivo en el almacenamiento.');
      }
      await _presentHumanResourcesPdf(
        _humanResourcesDocumentFileName(row, column),
        bytes,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir el documento: $error')),
      );
    }
  }

  Future<void> _openOrGenerateHumanResourcesDocument(
    Map<String, dynamic> row,
  ) async {
    if (!isApprovedHumanResourcesRecord(row)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('El documento se genera únicamente después de aprobar.'),
        ),
      );
      return;
    }

    final stored =
        (_value(row, ['documento_generado']) ?? '').toString().trim();
    if (stored.isNotEmpty && stored.toUpperCase() != 'NULL') {
      final existing = await _downloadBytesForPdf(
        stored,
        defaultBucket: EvidenceStorage.laborDocumentsBucket,
      );
      if (existing != null &&
          existing.length >= 5 &&
          String.fromCharCodes(existing.take(5)) == '%PDF-') {
        await _presentHumanResourcesPdf(
          _humanResourcesDocumentFileName(row, 'documento_generado'),
          existing,
        );
        return;
      }
    }

    if (!canApprove) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No tiene permiso para generar este documento.'),
        ),
      );
      return;
    }

    final table = tableName;
    if (table == null || table.trim().isEmpty) return;
    try {
      final bytes = _isSanctionTable
          ? await HumanResourcesRecordPdf.buildSanction(row)
          : await HumanResourcesRecordPdf.buildPermission(row);
      final fileName =
          _humanResourcesDocumentFileName(row, 'documento_generado');
      final empresaId = (_value(row, ['empresa_id']) ??
              await LocalSession().cachedEmpresaId())
          .toString()
          .trim();
      final primaryKey = _primaryKeyColumn(row);
      if (empresaId.isEmpty || primaryKey == null || row[primaryKey] == null) {
        throw StateError('Falta la empresa o el identificador del registro.');
      }
      final recordId = _safeFileName(row[primaryKey].toString());
      final folder = _isSanctionTable ? 'sanciones' : 'permisos';
      final path = '$empresaId/$folder/$recordId/$fileName';
      await supabase.storage
          .from(EvidenceStorage.laborDocumentsBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: true,
            ),
          );

      var generatedColumn = 'documento_generado';
      for (final key in row.keys) {
        if (_norm(key) == 'DOCUMENTO_GENERADO') {
          generatedColumn = key;
          break;
        }
      }
      await supabase.from(table).update({
        generatedColumn: EvidenceStorage.toStorageUri(
          path,
          bucketName: EvidenceStorage.laborDocumentsBucket,
        ),
      }).eq(primaryKey, row[primaryKey]);
      await _load();
      await _presentHumanResourcesPdf(fileName, bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Documento generado y almacenado.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar el documento: $error')),
      );
    }
  }

  Widget _humanResourcesStoredDocumentButton(
    Map<String, dynamic> row,
    String column,
  ) {
    final source = (_value(row, [column]) ?? '').toString().trim();
    final hasDocument = source.isNotEmpty && source.toUpperCase() != 'NULL';
    final generated = _norm(column) == 'DOCUMENTO_GENERADO';
    final approved = isApprovedHumanResourcesRecord(row);
    final enabled = generated ? approved : hasDocument;
    return Tooltip(
      message: generated
          ? (approved
              ? (hasDocument
                  ? 'Ver e imprimir documento generado'
                  : 'Generar documento PDF')
              : 'Disponible después de aprobar')
          : (hasDocument
              ? 'Ver documento de sustento'
              : 'Sin documento de sustento'),
      child: IconButton(
        icon: Icon(
          hasDocument ? Icons.picture_as_pdf : Icons.picture_as_pdf_outlined,
          color: enabled ? const Color(0xFFC62828) : Colors.grey,
        ),
        onPressed: enabled
            ? () => generated
                ? _openOrGenerateHumanResourcesDocument(row)
                : _openHumanResourcesStoredDocument(row, column)
            : null,
      ),
    );
  }

  Widget _mobileToolsMenu() {
    return PopupMenuButton<String>(
      enabled: !loading && error == null,
      tooltip: 'Importar y exportar',
      icon: const Icon(Icons.more_vert, color: Color(0xFF176B87)),
      onSelected: (value) async {
        if (value == 'template') await _downloadImportTemplate();
        if (value == 'import') await _importFile();
        if (value.startsWith('export:')) {
          await _exportRecords(value.substring('export:'.length));
        }
        if (value == 'review') {
          await _setSelectedWorkflowState('REVISADO');
        }
        if (value == 'approve') {
          await _setSelectedWorkflowState('APROBADO');
        }
        if (value == 'dispatch') {
          await _setSelectedWorkflowState('DESPACHADO');
        }
        if (value == 'annul') {
          await _setSelectedWorkflowState('ANULADO');
        }
        if (value == 'authorize_overtime') {
          await _authorizeSelectedOvertime();
        }
        if (value == 'payroll_lifecycle') {
          await _runPayrollLifecycle();
        }
        if (value == 'payroll_slip' && _selectedDeleteRows.length == 1) {
          await _openOrGeneratePayrollSlip(
            _selectedDeleteRows.values.single,
          );
        }
        if (value == 'hr_document' && _selectedDeleteRows.length == 1) {
          await _openOrGenerateHumanResourcesDocument(
            _selectedDeleteRows.values.single,
          );
        }
      },
      itemBuilder: (_) => [
        if (canImport)
          const PopupMenuItem(
            value: 'template',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.file_download_outlined),
              title: Text('Descargar plantilla'),
            ),
          ),
        if (canImport)
          const PopupMenuItem(
            value: 'import',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.upload_file),
              title: Text('Importar Excel/CSV'),
            ),
          ),
        if (canExport)
          const PopupMenuItem(
            value: 'export:excel',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.table_view_outlined),
              title: Text('Exportar Excel'),
            ),
          ),
        if (canExport)
          const PopupMenuItem(
            value: 'export:pdf',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.picture_as_pdf_outlined),
              title: Text('Exportar PDF'),
            ),
          ),
        if (canExport)
          const PopupMenuItem(
            value: 'export:csv',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.data_object),
              title: Text('Exportar CSV'),
            ),
          ),
        if (_approvalsEnabled && canReview)
          PopupMenuItem(
            value: 'review',
            enabled: _selectedDeleteRows.isNotEmpty,
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.fact_check_outlined),
              title: Text('Marcar REVISADO'),
            ),
          ),
        if (_approvalsEnabled && canApprove)
          PopupMenuItem(
            value: 'approve',
            enabled: _selectedDeleteRows.isNotEmpty,
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.verified_outlined),
              title: Text('Marcar APROBADO'),
            ),
          ),
        if (_approvalsEnabled &&
            _isNamedTable(tableName, 'ERP_VALES_DESPACHO_APPGT') &&
            (canApprove || canUpdate))
          PopupMenuItem(
            value: 'dispatch',
            enabled: _selectedDeleteRows.isNotEmpty,
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.local_shipping_outlined),
              title: Text('Marcar DESPACHADO'),
            ),
          ),
        if (_approvalsEnabled && (canUpdate || canDelete))
          PopupMenuItem(
            value: 'annul',
            enabled: _selectedDeleteRows.isNotEmpty,
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.block_outlined),
              title: Text('Anular'),
            ),
          ),
        if (_isTareoTable && canApprove)
          PopupMenuItem(
            value: 'authorize_overtime',
            enabled: _selectedDeleteRows.isNotEmpty,
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.more_time_outlined),
              title: Text('Autorizar horas extra'),
            ),
          ),
        if (_isPayrollPeriodTable)
          PopupMenuItem(
            value: 'payroll_lifecycle',
            enabled: _selectedDeleteRows.length == 1,
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.account_tree_outlined),
              title: Text('Ciclo de planilla'),
            ),
          ),
        if (_isPayrollSlipTable)
          PopupMenuItem(
            value: 'payroll_slip',
            enabled: _selectedDeleteRows.length == 1,
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.picture_as_pdf_outlined),
              title: Text('Generar o ver boleta PDF'),
            ),
          ),
        if (_isHumanResourcesApprovalTable)
          PopupMenuItem(
            value: 'hr_document',
            enabled: _selectedDeleteRows.length == 1,
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.picture_as_pdf_outlined),
              title: Text('Generar o ver documento PDF'),
            ),
          ),
        if (!canImport &&
            !canExport &&
            !(_approvalsEnabled && (canReview || canApprove)) &&
            !_isTareoTable &&
            !_isPayrollPeriodTable)
          const PopupMenuItem(
            enabled: false,
            child: Text('Sin herramientas habilitadas'),
          ),
      ],
    );
  }

  String _rowText(Map<String, dynamic> row, List<String> keys) {
    for (final k in keys) {
      for (final e in row.entries) {
        if (_norm(e.key) == _norm(k)) {
          final v = e.value?.toString().trim() ?? '';
          if (v.isNotEmpty && v.toUpperCase() != 'NULL') return v;
        }
      }
    }
    return '';
  }

  Future<List<Map<String, dynamic>>> _fetchPersonalRowsForPhotocheck() async {
    try {
      final res = await supabase
          .from('GH-REGISTRO_PERSONAL_PLANILLA')
          .select()
          .or('eliminado.is.null,eliminado.eq.false')
          .order('DNI', ascending: true);
      final rows = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (rows.isNotEmpty) return rows;
    } catch (_) {
      // Si Supabase bloquea la lectura por RLS o falla la conexión, se usa la
      // data que ya está cargada en la tabla para no dejar el botón sin acción.
    }
    if (records.isNotEmpty)
      return records.map((e) => Map<String, dynamic>.from(e)).toList();
    return <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> _fetchPhotocheckDesigns() async {
    try {
      dynamic res;
      try {
        res = await supabase
            .from('GT-DISEÑO_PHOTOCHEK')
            .select()
            .or('eliminado.is.null,eliminado.eq.false')
            .order('DISEÑO', ascending: true);
      } catch (_) {
        res = await supabase
            .from('MATRIZ-PHOTOCHEK')
            .select()
            .or('eliminado.is.null,eliminado.eq.false')
            .order('DISEÑO', ascending: true);
      }
      final rows = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (rows.isNotEmpty) return rows;
    } catch (_) {}
    return <Map<String, dynamic>>[
      {
        'DISEÑO': 1,
        'CAMPOS': 'Logo,FOTO,Apellidos y Nombres,Dni,QR,Puesto',
        'PUESTO': ''
      }
    ];
  }

  List<String> _photocheckDesignFields(Map<String, dynamic> design) {
    final raw = _rowText(design, ['CAMPOS', 'Campos', 'campos']);
    final fields = raw
        .split(RegExp(r'[,;|]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return fields.isEmpty
        ? <String>['Logo', 'FOTO', 'Apellidos y Nombres', 'Dni', 'QR', 'Puesto']
        : fields;
  }

  String _photocheckFieldKey(String label) {
    final n = _norm(label);
    if (n == 'LOGO') return 'LOGO';
    if (n == 'FOTO' ||
        n == 'FOTO1' ||
        n == 'PHOTO' ||
        n == 'PHOTO1' ||
        n == 'PHOTO_URL') return 'FOTO';
    if (n == 'QR' || n == 'CODIGO_QR') return 'QR';
    if (n == 'DNI' || n == 'DOCUMENTO') return 'DNI';
    if (n == 'APELLIDOSYNOMBRES' ||
        n == 'APELLIDOSNOMBRES' ||
        n == 'NOMBRE' ||
        n == 'NOMBRES') return 'APELLIDOS Y NOMBRES';
    if (n == 'PUESTO' || n == 'CARGO') return 'PUESTO';
    if (n == 'AREA' || n == 'ÁREA') return 'AREA';
    return label.trim();
  }

  String _workerValueByDesignField(
      Map<String, dynamic> worker, String fieldLabel) {
    final key = _photocheckFieldKey(fieldLabel);
    switch (key) {
      case 'DNI':
        return _rowText(worker, ['DNI', 'Dni', 'DOCUMENTO', 'Documento']);
      case 'APELLIDOS Y NOMBRES':
        return _rowText(worker, [
          'APELLIDOS Y NOMBRES',
          'Apellidos y Nombres',
          'APELLIDOS_NOMBRES',
          'NOMBRE',
          'NOMBRES'
        ]);
      case 'PUESTO':
        return _rowText(worker, ['PUESTO', 'Puesto', 'CARGO', 'Cargo']);
      case 'AREA':
        return _rowText(worker, ['AREA', 'Área', 'ÁREA']);
      case 'FOTO':
        return _rowText(worker, [
          'FOTO1',
          'Foto1',
          'FOTO 1',
          'FOTO_1',
          'FOTO',
          'Foto',
          'PHOTO_URL',
          'photo_url'
        ]);
      default:
        return _rowText(worker, [fieldLabel, key]);
    }
  }

  Map<String, dynamic> _designForWorker(
      Map<String, dynamic> worker, List<Map<String, dynamic>> designs) {
    final puesto = _rowText(worker, ['PUESTO', 'Puesto', 'CARGO', 'Cargo'])
        .trim()
        .toUpperCase();
    for (final d in designs) {
      final designPuesto = _rowText(d, [
        'PUESTO',
        'Puesto',
        'tipo de trabajador',
        'TIPO_TRABAJADOR',
        'TIPO DE TRABAJADOR'
      ]).trim().toUpperCase();
      if (designPuesto.isEmpty || puesto.isEmpty) continue;
      final parts = designPuesto
          .split(RegExp(r'[,;|]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty);
      if (parts.any((p) => p == puesto)) return d;
    }
    return designs.firstWhere(
      (d) => _rowText(d, ['DISEÑO', 'Diseño']) == '1',
      orElse: () =>
          designs.isNotEmpty ? designs.first : <String, dynamic>{'DISEÑO': 1},
    );
  }

  String? _splitStoragePath(String value, {String? defaultBucket}) {
    var clean = value.trim();
    if (clean.isEmpty) return null;
    if (clean.startsWith('storage://'))
      clean = clean.substring('storage://'.length);
    clean = clean.replaceAll('\\', '/');
    clean = clean.replaceFirst(RegExp(r'^/+'), '');
    if (clean.startsWith('object/public/'))
      clean = clean.substring('object/public/'.length);
    if (clean.startsWith('object/sign/'))
      clean = clean.substring('object/sign/'.length);
    if (clean.startsWith('storage/v1/object/public/'))
      clean = clean.substring('storage/v1/object/public/'.length);
    if (clean.startsWith('storage/v1/object/sign/'))
      clean = clean.substring('storage/v1/object/sign/'.length);
    final parts = clean.split('/').where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts.first}/${parts.skip(1).join('/')}';
    if (defaultBucket != null && parts.isNotEmpty)
      return '$defaultBucket/${parts.first}';
    return null;
  }

  Future<String?> _resolveSupabaseMediaUrl(String value,
      {String? defaultBucket}) async {
    var clean = value.trim();
    if (clean.isEmpty || clean.toUpperCase() == 'NULL') return null;
    if (clean.toLowerCase().startsWith('http')) return clean;
    if (clean.startsWith('/storage/v1/'))
      return '${SupabaseConfig.supabaseUrl}$clean';
    if (clean.startsWith('storage/v1/'))
      return '${SupabaseConfig.supabaseUrl}/$clean';

    final storagePath = _splitStoragePath(clean, defaultBucket: defaultBucket);
    if (storagePath == null) return null;
    final slash = storagePath.indexOf('/');
    if (slash <= 0 || slash >= storagePath.length - 1) return null;
    final bucket = storagePath.substring(0, slash);
    final path = storagePath.substring(slash + 1);
    try {
      return await supabase.storage.from(bucket).createSignedUrl(path, 60 * 60);
    } catch (_) {
      try {
        return supabase.storage.from(bucket).getPublicUrl(path);
      } catch (_) {
        return null;
      }
    }
  }

  Future<Uint8List?> _downloadBytesForPdf(String source,
      {String? defaultBucket}) async {
    final clean = source.trim();
    if (clean.isEmpty || clean.toUpperCase() == 'NULL') return null;
    if ((clean.startsWith('data:image/') ||
            clean.startsWith('data:application/pdf')) &&
        clean.contains(',')) {
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

    final resolved =
        await _resolveSupabaseMediaUrl(clean, defaultBucket: defaultBucket);
    final resolvedBytes = await fetchUrlBytes(resolved);
    if (resolvedBytes != null) return resolvedBytes;

    final isExplicitSource = clean.toLowerCase().startsWith('http') ||
        clean.startsWith('storage://') ||
        clean.contains('storage/v1/');
    if (!isExplicitSource) {
      final normalizedPath = clean.replaceAll('\\', '/').replaceFirst(
            RegExp(r'^/+'),
            '',
          );
      final buckets = <String>{
        if (defaultBucket != null) defaultBucket,
        'appgt-evidencias',
        'migracion-appsheets',
      };
      for (final bucket in buckets) {
        try {
          final url = await supabase.storage
              .from(bucket)
              .createSignedUrl(normalizedPath, 60 * 60);
          final bytes = await fetchUrlBytes(url);
          if (bytes != null) return bytes;
        } catch (_) {}
      }
    }
    return null;
  }

  Future<pw.Widget> _photocheckCard(
      Map<String, dynamic> worker, Map<String, dynamic> design) async {
    final fields = _photocheckDesignFields(design);
    final fieldKeys = fields.map(_photocheckFieldKey).toList();
    final dni = _workerValueByDesignField(worker, 'DNI');
    final qrValue = dni.isNotEmpty
        ? dni
        : _rowText(worker, ['id_local', 'CODIGO_PERSONAL']);
    final logoUrl = _rowText(design, ['LOGO', 'Logo']);
    final fotoUrl = _workerValueByDesignField(worker, 'FOTO');
    final showLogo = fieldKeys.contains('LOGO') && logoUrl.trim().isNotEmpty;
    final showFoto = fieldKeys.contains('FOTO') && fotoUrl.trim().isNotEmpty;
    final showQr = fieldKeys.contains('QR');
    final logoBytes = showLogo
        ? await _downloadBytesForPdf(logoUrl, defaultBucket: 'imagenes_app')
        : null;
    final fotoBytes = showFoto ? await _downloadBytesForPdf(fotoUrl) : null;

    final textFields = <MapEntry<String, String>>[];
    for (final f in fields) {
      final key = _photocheckFieldKey(f);
      if (key == 'LOGO' || key == 'FOTO' || key == 'QR') continue;
      final value = _workerValueByDesignField(worker, f);
      if (value.trim().isEmpty) continue;
      final label = key == 'APELLIDOS Y NOMBRES' || key == 'PUESTO'
          ? ''
          : '${f.trim()}: ';
      textFields.add(MapEntry(key, '$label$value'));
    }

    return pw.Container(
      width: 54 * PdfPageFormat.mm,
      height: 86 * PdfPageFormat.mm,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColors.black, width: 1.1),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            height: 13 * PdfPageFormat.mm,
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: pw.BoxDecoration(
              color: PdfColor(0.08, 0.48, 0.43),
              borderRadius: pw.BorderRadius.only(
                  topLeft: pw.Radius.circular(3),
                  topRight: pw.Radius.circular(3)),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'PHOTOCHECK',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold),
                  ),
                ),
                if (logoBytes != null)
                  pw.Container(
                    width: 10 * PdfPageFormat.mm,
                    height: 9 * PdfPageFormat.mm,
                    alignment: pw.Alignment.centerRight,
                    child: pw.Image(pw.MemoryImage(logoBytes),
                        fit: pw.BoxFit.contain),
                  )
                else
                  pw.SizedBox(width: 10 * PdfPageFormat.mm),
              ],
            ),
          ),
          pw.SizedBox(height: 4),
          if (fieldKeys.contains('FOTO') && fotoBytes != null)
            pw.Center(
              child: pw.Container(
                width: 24 * PdfPageFormat.mm,
                height: 28 * PdfPageFormat.mm,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 0.7)),
                child:
                    pw.Image(pw.MemoryImage(fotoBytes), fit: pw.BoxFit.cover),
              ),
            ),
          pw.SizedBox(height: 5),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 5),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: textFields.map((entry) {
                  final isName = entry.key == 'APELLIDOS Y NOMBRES';
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2.2),
                    child: pw.Text(
                      entry.value,
                      textAlign: pw.TextAlign.center,
                      maxLines: isName ? 3 : 2,
                      style: pw.TextStyle(
                          fontSize: isName ? 10.5 : 6.8,
                          fontWeight: isName
                              ? pw.FontWeight.bold
                              : pw.FontWeight.normal),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          if (showQr && qrValue.trim().isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: qrValue.trim(),
                  width: 18 * PdfPageFormat.mm,
                  height: 18 * PdfPageFormat.mm,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _generatePhotocheckPdf(
      List<Map<String, dynamic>> workers) async {
    if (workers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Selecciona al menos un trabajador para generar el Photocheck.')));
      }
      return;
    }
    try {
      final inactiveCount = workers
          .where((w) =>
              _rowText(w, ['Status', 'STATUS', 'ESTADO', 'ESTADO_PERSONAL'])
                  .toUpperCase() ==
              'INACTIVO')
          .length;
      if (inactiveCount > 0 && mounted) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Personal inactivo'),
            content: Text(
                'Hay $inactiveCount personas que no son de planilla. ¿Deseas continuar?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Continuar')),
            ],
          ),
        );
        if (ok != true) return;
      }
      final designs = await _fetchPhotocheckDesigns();
      final cards = <pw.Widget>[];
      for (final w in workers) {
        final design = _designForWorker(w, designs);
        cards.add(await _photocheckCard(w, design));
      }
      final pdf = pw.Document();
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        build: (_) => [
          pw.Wrap(spacing: 8, runSpacing: 8, children: cards),
        ],
      ));
      final filePath = await _writeExportFile('pdf', await pdf.save());
      if (!kIsWeb) await OpenFilex.open(filePath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photocheck generado: $filePath')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo generar el Photocheck: $e')));
    }
  }

  Future<void> _showPhotocheckSelector() async {
    final all = await _fetchPersonalRowsForPhotocheck();
    final selected = <String, Map<String, dynamic>>{};
    if (_selectedDeleteRows.isNotEmpty) {
      for (final r in _selectedDeleteRows.values) {
        final dni = _rowText(r, ['DNI', 'Dni', 'DOCUMENTO']);
        if (dni.isNotEmpty) selected[dni] = r;
      }
    }
    String query = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final q = query.toUpperCase();
          final filtered = all
              .where((r) {
                final dni = _rowText(r, ['DNI', 'Dni', 'DOCUMENTO']);
                final nombre = _rowText(r, [
                  'APELLIDOS Y NOMBRES',
                  'APELLIDOS_NOMBRES',
                  'NOMBRE',
                  'NOMBRES'
                ]);
                return q.isEmpty || '$dni $nombre'.toUpperCase().contains(q);
              })
              .take(100)
              .toList();
          return AlertDialog(
            title: const Text('Generar Photocheck'),
            content: SizedBox(
              width: 620,
              height: 520,
              child: Column(children: [
                TextField(
                    decoration: const InputDecoration(
                        labelText: 'Buscar por DNI o nombres',
                        border: OutlineInputBorder()),
                    onChanged: (v) => setDialogState(() => query = v)),
                const SizedBox(height: 10),
                Expanded(
                    child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final r = filtered[i];
                    final dni = _rowText(r, ['DNI', 'Dni', 'DOCUMENTO']);
                    final nombre = _rowText(r, [
                      'APELLIDOS Y NOMBRES',
                      'APELLIDOS_NOMBRES',
                      'NOMBRE',
                      'NOMBRES'
                    ]);
                    final isSel = selected.containsKey(dni);
                    return ListTile(
                      dense: true,
                      leading: Icon(
                          isSel ? Icons.check_circle : Icons.person_outline,
                          color: isSel ? const Color(0xFF147A6E) : null),
                      title: Text('$dni - $nombre'),
                      onTap: () => setDialogState(() {
                        if (dni.isNotEmpty) selected[dni] = r;
                      }),
                    );
                  },
                )),
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Seleccionados: ${selected.length}')),
                SizedBox(
                    height: 70,
                    child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: selected.keys
                            .map((dni) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Chip(
                                    label: Text(dni),
                                    onDeleted: () => setDialogState(
                                        () => selected.remove(dni)))))
                            .toList())),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar')),
              FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, true),
                  child: const Text('Generar')),
            ],
          );
        },
      ),
    );
    if (ok == true) await _generatePhotocheckPdf(selected.values.toList());
  }

  Future<void> _downloadPhotocheckImportTemplate() async {
    final excel = xlsx.Excel.createExcel();
    final sheet = excel['PHOTOCHECK'];
    sheet.appendRow([xlsx.TextCellValue('DNI')]);
    final bytes = excel.encode();
    if (bytes == null) return;
    final filePath = await _writeExportFile('xlsx', Uint8List.fromList(bytes));
    if (!kIsWeb) await OpenFilex.open(filePath);
  }

  Future<void> _importPhotocheckList() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: true);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes ??
        (picked.path == null ? null : await File(picked.path!).readAsBytes());
    if (bytes == null) return;
    final ext = picked.extension?.toLowerCase() ?? '';
    final dnis = <String>{};
    if (ext == 'csv') {
      final lines = const LineSplitter()
          .convert(utf8.decode(bytes, allowMalformed: true));
      for (final line in lines.skip(1)) {
        final dni = line.split(',').first.trim();
        if (dni.isNotEmpty) dnis.add(dni);
      }
    } else {
      final excel = xlsx.Excel.decodeBytes(bytes);
      final table =
          excel.tables.values.isEmpty ? null : excel.tables.values.first;
      if (table != null) {
        for (final row in table.rows.skip(1)) {
          final dni =
              row.isNotEmpty ? (row[0]?.value?.toString().trim() ?? '') : '';
          if (dni.isNotEmpty) dnis.add(dni);
        }
      }
    }
    if (dnis.isEmpty) return;
    final all = await _fetchPersonalRowsForPhotocheck();
    final byDni = {
      for (final r in all) _rowText(r, ['DNI', 'Dni', 'DOCUMENTO']): r
    };
    final workers = <Map<String, dynamic>>[];
    final missing = <String>[];
    for (final dni in dnis) {
      final w = byDni[dni];
      if (w != null) {
        workers.add(w);
      } else {
        missing.add(dni);
      }
    }
    if (missing.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'DNI no encontrados: ${missing.take(8).join(', ')}${missing.length > 8 ? '...' : ''}')));
    }
    await _generatePhotocheckPdf(workers);
  }

  Widget _photocheckButton() {
    if (!_isPersonalPlanillaTable) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      width: 48,
      child: PopupMenuButton<String>(
        enabled: !loading && !offline && error == null,
        tooltip: 'Photocheck',
        color: const Color(0xFF1B6A82),
        onSelected: (value) async {
          try {
            if (value == 'generate') {
              if (_selectedDeleteRows.isNotEmpty) {
                await _generatePhotocheckPdf(_selectedDeleteRows.values
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList());
              } else {
                await _showPhotocheckSelector();
              }
            }
            if (value == 'template') await _downloadPhotocheckImportTemplate();
            if (value == 'import') await _importPhotocheckList();
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error en Photocheck: $e')));
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
              value: 'generate',
              child: Text('Generar Photocheck',
                  style: TextStyle(color: Colors.white))),
          PopupMenuItem(
              value: 'template',
              child: Text('Descargar plantilla',
                  style: TextStyle(color: Colors.white))),
          PopupMenuItem(
              value: 'import',
              child: Text('Importar', style: TextStyle(color: Colors.white))),
        ],
        child: Container(
          height: 44,
          width: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF17677F),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE8F3F5)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x22000000), blurRadius: 7, offset: Offset(0, 2))
            ],
          ),
          child: const Icon(Icons.qr_code_2, color: Colors.white, size: 21),
        ),
      ),
    );
  }

  Future<void> _newRecord() async {
    if (_attendanceCaptureBlocked(selectedTableName ?? tableName)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La asistencia solo se puede marcar desde la aplicación móvil.',
          ),
        ),
      );
      return;
    }
    final Widget page = special.isNotEmpty
        ? SpecialFormRouterPage(
            moduleId: widget.module['id'] as String,
            format: widget.format,
            special: special.first,
          )
        : FormRunnerPage(
            moduleId: widget.module['id'] as String,
            format: widget.format,
          );

    // El formulario se abre sin desmontar la tabla. Al cerrarlo se hace un
    // refresco silencioso de sus filas, sin reconstruir fotos ni formularios.
    final compact = widget.mobileMode || MediaQuery.sizeOf(context).width < 760;
    if (compact) {
      // En móvil el formulario debe disponer de todo el ancho. Se conserva la
      // misma página dinámica; solo cambia el contenedor de navegación.
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => page,
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = math.min(
                ZumacResponsiveLimits.formDialog,
                constraints.maxWidth - 32.0,
              );
              return Dialog(
                insetPadding: const EdgeInsets.all(16),
                backgroundColor: Colors.transparent,
                child: Center(
                  child: SizedBox(
                    width: width,
                    height: constraints.maxHeight * 0.94,
                    child: ClipRRect(
                      borderRadius: BorderRadius.zero,
                      child: Material(
                        elevation: 10,
                        color: Colors.white,
                        child: page,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    }

    // Refrescar contadores locales y luego la tabla activa automáticamente.
    if (mounted) {
      await widget.onLocalRecordsChanged?.call();
      final activeTable = tableName?.trim() ?? '';
      final formatId = widget.format['id']?.toString().trim() ?? '';
      if (activeTable.isNotEmpty && formatId.isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await _refreshTableSilentlyAfterLoad(
          activeTable,
          formatId,
          _loadSerial,
        );
      }
    }
  }

  Widget _emptyMessage(String message) {
    return Center(
      child: Text(
        message,
        style: const TextStyle(
            color: Color(0xFF4A6075),
            fontSize: 20,
            fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
    );
  }

  void _scheduleRenderRows(int totalRows) {
    // Desactivado: con paginación de 200 filas, repintar por bloques hacía lenta la UI.
  }

  ({String table, String foreignKey, String parentKey, String title})?
      _erpDetailSpec() {
    final table = _norm(tableName ?? '');
    if (table == _norm('ERP_SOLICITUDES_COMPRA_APPGT')) {
      return (
        table: 'ERP_SOLICITUDES_COMPRA_DETALLE_APPGT',
        foreignKey: 'solicitud_numero',
        parentKey: 'numero',
        title: 'Detalle de la solicitud de pedido',
      );
    }
    if (table == _norm('ERP_ORDENES_COMPRA_APPGT')) {
      return (
        table: 'ERP_ORDENES_COMPRA_DETALLE_APPGT',
        foreignKey: 'orden_numero',
        parentKey: 'numero',
        title: 'Detalle de la orden de compra',
      );
    }
    if (table == _norm('ERP_INGRESOS_ALMACEN_APPGT')) {
      return (
        table: 'ERP_INGRESOS_ALMACEN_DETALLE_APPGT',
        foreignKey: 'ingreso_numero',
        parentKey: 'numero',
        title: 'Detalle de Ingresos en Almacén',
      );
    }
    if (table == _norm('ERP_VALES_DESPACHO_APPGT')) {
      return (
        table: 'ERP_VALES_DESPACHO_DETALLE_APPGT',
        foreignKey: 'vale_numero',
        parentKey: 'numero',
        title: 'Detalle del vale de despacho',
      );
    }
    return null;
  }

  bool get _hasEmbeddedErpDetail => _erpDetailSpec() != null;

  Future<void> _showEmbeddedErpDetail(Map<String, dynamic> row) async {
    final spec = _erpDetailSpec();
    if (spec == null) return;
    final parentValue = _value(row, [spec.parentKey])?.toString().trim() ?? '';
    if (parentValue.isEmpty) return;
    final horizontalController = ScrollController();
    final verticalController = ScrollController();
    try {
      final raw = await supabase
          .from(spec.table)
          .select()
          .eq(spec.foreignKey, parentValue)
          .eq('eliminado', false)
          .order('linea');
      final details = (raw as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (!mounted) return;
      final technical = {
        'ID',
        'ID_LOCAL',
        'EMPRESA_ID',
        'CREATED_BY',
        'UPDATED_BY',
        'CREATED_AT',
        'UPDATED_AT',
        'DELETED_AT',
        'ELIMINADO',
        'ESTADO_SYNC',
        'VERSION',
        if (spec.table == 'ERP_VALES_DESPACHO_DETALLE_APPGT')
          'CANTIDAD_DESPACHADA',
        if (spec.table == 'ERP_INGRESOS_ALMACEN_DETALLE_APPGT')
          'CANTIDAD_PENDIENTE_ANTES',
      };
      final columns = <String>[];
      for (final detail in details) {
        for (final key in detail.keys) {
          if (!technical.contains(_norm(key)) && !columns.contains(key)) {
            columns.add(key);
          }
        }
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: const RoundedRectangleBorder(),
          title: Text('${spec.title} · $parentValue'),
          content: SizedBox(
            width: math.min(MediaQuery.sizeOf(context).width * .88, 1180),
            height: math.min(MediaQuery.sizeOf(context).height * .68, 620),
            child: details.isEmpty
                ? const Center(child: Text('No hay líneas registradas.'))
                : Scrollbar(
                    controller: verticalController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    child: SingleChildScrollView(
                      controller: verticalController,
                      child: Scrollbar(
                        controller: horizontalController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        scrollbarOrientation: ScrollbarOrientation.bottom,
                        notificationPredicate: (notification) =>
                            notification.metrics.axis == Axis.horizontal,
                        child: SingleChildScrollView(
                          controller: horizontalController,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(bottom: 16),
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                                const Color(0xFF42576B)),
                            headingTextStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                            columns: columns
                                .map((column) => DataColumn(
                                    label: Text(_erpDetailHeaderLabel(
                                        spec.table, column))))
                                .toList(),
                            rows: details
                                .map((detail) => DataRow(
                                      cells: columns.map((column) {
                                        final value =
                                            _valueByColumn(detail, column);
                                        if (_norm(column) == 'FOTO_URL') {
                                          final photo =
                                              value?.toString().trim() ?? '';
                                          return DataCell(photo.isEmpty
                                              ? const Icon(Icons.photo_outlined,
                                                  color: Colors.grey)
                                              : IconButton(
                                                  tooltip:
                                                      'Ver foto solicitada',
                                                  onPressed: () =>
                                                      ErpImageAttachment.show(
                                                    dialogContext,
                                                    storageUrl: photo,
                                                  ),
                                                  icon: const Icon(
                                                    Icons.photo,
                                                    color: Color(0xFF008C95),
                                                  ),
                                                ));
                                        }
                                        return DataCell(Text(
                                          _displayCellValue(value),
                                        ));
                                      }).toList(),
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar el detalle: $error')),
      );
    } finally {
      horizontalController.dispose();
      verticalController.dispose();
    }
  }

  String _erpDetailHeaderLabel(String table, String column) {
    if (table == 'ERP_VALES_DESPACHO_DETALLE_APPGT' &&
        _norm(column) == 'CANTIDAD_SOLICITADA') {
      return 'cantidad';
    }
    return _tableHeaderLabel(column);
  }

  bool get _isErpDocumentTable =>
      ErpDocumentPdf.supports(tableName?.trim() ?? '');

  Future<void> _openOrGenerateErpDocument(Map<String, dynamic> row) async {
    final table = tableName?.trim() ?? '';
    if (!ErpDocumentPdf.supports(table)) return;
    try {
      await ErpDocumentPdf.openOrGenerate(
        context: context,
        client: supabase,
        table: table,
        row: row,
      );
      if (mounted) await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  Widget _erpPdfCell(Map<String, dynamic> row) {
    final stored =
        _value(row, const ['pdf_url', 'PDF_URL'])?.toString().trim() ?? '';
    final allowed = stored.isNotEmpty ||
        ErpDocumentPdf.mayGenerate(tableName?.trim() ?? '', row);
    return Tooltip(
      message: allowed
          ? (stored.isEmpty ? 'Generar PDF' : 'Ver PDF generado')
          : 'Disponible desde APROBADO',
      child: IconButton(
        onPressed: allowed ? () => _openOrGenerateErpDocument(row) : null,
        icon: Icon(
          stored.isEmpty ? Icons.picture_as_pdf_outlined : Icons.picture_as_pdf,
          color: allowed ? const Color(0xFFC62828) : Colors.grey,
        ),
      ),
    );
  }

  bool _isMediaColumn(String column) {
    final n = _norm(column);
    return n.contains('FOTO') ||
        n.contains('FIRMA') ||
        n.contains('IMAGEN') ||
        n.contains('EVIDENCIA');
  }

  bool _isSignatureColumn(String column) {
    return _norm(column).contains('FIRMA');
  }

  String _sanitizeStoragePart(String value) {
    final clean = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return clean.isEmpty ? 'sin_valor' : clean;
  }

  Future<String> _uploadDesktopSignature({
    required String table,
    required Object pkValue,
    required String column,
    required Uint8List bytes,
  }) async {
    final safeTable = _sanitizeStoragePart(table);
    final safePk = _sanitizeStoragePart(pkValue.toString());
    final safeColumn = _sanitizeStoragePart(column);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path =
        'firmas/desktop_updates/$safeTable/$safePk/${safeColumn}_$stamp.png';

    await supabase.storage.from(EvidenceStorage.bucket).uploadBinary(
          path,
          bytes,
          fileOptions:
              const FileOptions(contentType: 'image/png', upsert: true),
        );

    return EvidenceStorage.toStorageUri(path);
  }

  bool _looksLikeUrl(String value) {
    final s = value.trim().toLowerCase();
    if (s.isEmpty) return false;
    if (s.startsWith('data:image/')) return true;
    if (s.startsWith('http://') || s.startsWith('https://')) return true;
    if (EvidenceStorage.isStorageUri(value)) return true;
    final imageExt = RegExp(r'\.(jpg|jpeg|png|webp|gif|bmp|heic|heif)(\?|$)',
        caseSensitive: false);
    if (imageExt.hasMatch(s)) return true;
    if (s.contains('/') &&
        (s.contains('foto') ||
            s.contains('firma') ||
            s.contains('image') ||
            s.contains('imagen') ||
            s.contains('evidencia'))) return true;
    return _tryDecodeImageBytes(value) != null;
  }

  String _displayCellValue(dynamic value) {
    if (value == null) return '';
    if (value is List || value is Map) return jsonEncode(value);
    return value.toString();
  }

  void _openMediaPreview(String column, String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF0F5265),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        column,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5,
                    child: Center(
                      child: _networkMediaImage(url,
                          fit: BoxFit.contain, preview: true),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<String> _signedMediaUrlFuture(String value) {
    final key = value.trim();
    return _signedMediaUrlFutures.putIfAbsent(
        key, () => EvidenceStorage.signedUrlForValue(key));
  }

  ImageProvider _mediaImageProvider(String signedUrl) {
    return _mediaImageProviders.putIfAbsent(
        signedUrl, () => NetworkImage(signedUrl));
  }

  Uint8List? _tryDecodeImageBytes(String value) {
    final key = value.trim();
    if (key.isEmpty) return null;
    final cached = _decodedMediaBytes[key];
    if (cached != null) return cached;
    var payload = key;
    final comma = payload.indexOf(',');
    if (payload.toLowerCase().startsWith('data:image/') && comma >= 0) {
      payload = payload.substring(comma + 1);
    }
    final compact = payload.replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 80) return null;
    if (!RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(compact)) return null;
    try {
      final bytes = base64Decode(compact);
      if (bytes.length < 20) return null;
      if (_decodedMediaBytes.length > 24) {
        _decodedMediaBytes.clear();
      }
      _decodedMediaBytes[key] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Widget _mediaFallback(String text, {double size = 20}) {
    return Tooltip(
      message: text,
      child:
          Icon(Icons.broken_image, color: const Color(0xFF60758A), size: size),
    );
  }

  Widget _networkMediaImage(String value,
      {double? width,
      double? height,
      BoxFit fit = BoxFit.cover,
      bool preview = false}) {
    final bytes = _tryDecodeImageBytes(value);
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            _mediaFallback('No se pudo leer la imagen/firma.'),
      );
    }

    final future = _signedMediaUrlFuture(value);
    return FutureBuilder<String>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            width: width ?? 24,
            height: height ?? 24,
            child: const Center(
                child: Icon(Icons.image, color: Color(0xFF60758A), size: 18)),
          );
        }
        final resolved = snapshot.data?.trim() ?? '';
        if (resolved.isEmpty)
          return _mediaFallback('Ruta vacía o no disponible.');
        return Image(
          image: _mediaImageProvider(resolved),
          width: width,
          height: height,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _mediaFallback(
              'No se pudo cargar: $resolved',
              size: preview ? 48 : 20),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return SizedBox(
              width: width ?? 24,
              height: height ?? 24,
              child: const Center(
                  child: Icon(Icons.image, color: Color(0xFF60758A), size: 18)),
            );
          },
        );
      },
    );
  }

  Widget _mediaCell(String column, String url) {
    // Rendimiento: en la grilla no se descargan/renderizan miniaturas de fotos/firmas.
    // La imagen real se carga solo al abrir el preview. Esto evita picos de CPU/RAM
    // al filtrar, abrir/cerrar sidebar, seleccionar filas o cambiar páginas.
    final isSignature = _norm(column).contains('FIRMA');
    return InkWell(
      onTap: () => _openMediaPreview(column, url),
      child: Container(
        width: 64,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white38),
          color: const Color(0xFFEAF2F6),
        ),
        child: Icon(
          isSignature ? Icons.draw_outlined : Icons.image_outlined,
          color: const Color(0xFF60758A),
          size: 20,
        ),
      ),
    );
  }

  dynamic _fieldMetaValueAny(Map<String, dynamic> field, List<String> names) {
    for (final name in names) {
      if (field.containsKey(name)) return field[name];
      final wanted = _norm(name);
      for (final entry in field.entries) {
        if (_norm(entry.key.toString()) == wanted) return entry.value;
      }
    }
    return null;
  }

  Color? _parseTableMatrixColor(dynamic value) {
    if (value == null) return null;
    var text = value.toString().trim();
    if (text.isEmpty || text.toUpperCase() == 'NULL') return null;
    text = text.replaceAll('"', '').replaceAll("'", '').trim().toLowerCase();
    const names = {
      'rojo': Colors.red,
      'red': Colors.red,
      'verde': Colors.green,
      'green': Colors.green,
      'amarillo': Colors.yellow,
      'yellow': Colors.yellow,
      'azul': Colors.blue,
      'blue': Colors.blue,
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

  FormulaEngine _tableFormulaEngine(Map<String, dynamic> row) {
    return FormulaEngine(
      fields: allLocalFormFields,
      matrixRowsByTable: matrixRowsByTable,
      getValue: (campo) {
        if (row.containsKey(campo)) return row[campo];
        final wanted = _norm(campo);
        for (final entry in row.entries) {
          if (_norm(entry.key.toString()) == wanted) return entry.value;
        }
        return null;
      },
    );
  }

  dynamic _evalTableFormatExpression(
      String expression, Map<String, dynamic> row) {
    var expr = expression.trim();
    if (expr.isEmpty) return '';
    final call =
        RegExp(r'^([A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9_]+)\s*\((.*)\)$', dotAll: true)
            .firstMatch(expr);
    if (call != null) {
      final name = _norm(call.group(1) ?? '');
      final args = _splitTableFormatArgs(call.group(2) ?? '');
      if ((name == 'IF' || name == 'SI') && args.length == 2) {
        final first = _evalTableFormatExpression(args[0], row);
        return _truthyTableValue(first)
            ? first
            : _evalTableFormatExpression(args[1], row);
      }
      if ((name == 'O' || name == 'OR') && args.length >= 3) {
        for (var i = 0; i + 1 < args.length; i += 2) {
          if (_evalTableFormatBool(args[i], row))
            return _evalTableFormatExpression(args[i + 1], row);
        }
        if (args.length.isOdd)
          return _evalTableFormatExpression(args.last, row);
        return '';
      }
    }
    try {
      return _tableFormulaEngine(row).evaluate(expr);
    } catch (_) {
      return expr.replaceAll('"', '').replaceAll("'", '').trim();
    }
  }

  bool _evalTableFormatBool(String condition, Map<String, dynamic> row) {
    try {
      return _tableFormulaEngine(row)
          .evaluateCondition(condition.replaceAll('<>', '!='));
    } catch (_) {
      return _truthyTableValue(_evalTableFormatExpression(condition, row));
    }
  }

  bool _truthyTableValue(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toUpperCase();
    if (text.isEmpty || text == 'NULL') return false;
    return text != 'FALSE' && text != 'FALSO' && text != 'NO' && text != '0';
  }

  List<String> _splitTableFormatArgs(String raw) {
    final args = <String>[];
    final current = StringBuffer();
    var square = 0;
    var paren = 0;
    var inString = false;
    String? quote;
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
        if (c == '(') paren++;
        if (c == ')' && paren > 0) paren--;
        if ((c == ',' || c == ';') && square == 0 && paren == 0) {
          args.add(current.toString().trim());
          current.clear();
          continue;
        }
      }
      current.write(c);
    }
    args.add(current.toString().trim());
    return args.where((e) => e.isNotEmpty).toList();
  }

  String? _tableConditionalResult(
      Map<String, dynamic> field, Map<String, dynamic> row, String column) {
    final raw = _fieldMetaValueAny(field, [
      'formato_condicional_campo',
      'formato condicional campo',
      'condicion_formato',
      'condición formato',
      'formato_condicional'
    ]);
    if (raw == null) return null;
    var condition = raw.toString().trim();
    if (condition.isEmpty || condition.toUpperCase() == 'NULL') return null;
    if (RegExp(r'^(>=|<=|<>|!=|==|=|>|<)').hasMatch(condition)) {
      condition = '[$column] $condition';
      return _evalTableFormatBool(condition, row) ? 'true' : null;
    }
    final value = _evalTableFormatExpression(condition, row);
    if (!_truthyTableValue(value)) return null;
    return value.toString().trim();
  }

  String? _resolveTableColorRaw(dynamic rawColor, String? conditionalResult) {
    if (rawColor == null) return null;
    final text = rawColor.toString().trim();
    if (text.isEmpty || text.toUpperCase() == 'NULL') return null;
    final normalized = text
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceFirst(RegExp(r'^\s*=\s*'), '')
        .trim()
        .toLowerCase();
    if (normalized == 'formato_condicional_campo') return conditionalResult;
    return text;
  }

  bool _tableStyleConditionApplies(
    dynamic raw,
    Map<String, dynamic> row,
    String column,
  ) {
    if (raw == null) return true;
    var condition = raw.toString().trim();
    if (condition.isEmpty || condition.toUpperCase() == 'NULL') return true;
    if (RegExp(r'^(>=|<=|<>|!=|==|=|>|<)').hasMatch(condition)) {
      condition = '[$column] $condition';
    }
    return _evalTableFormatBool(condition.replaceAll('<>', '!='), row);
  }

  _TableCellFormat _tableCellFormat(String column, Map<String, dynamic> row) {
    final field = _fieldDefForCurrentTableColumn(column);
    if (field == null) return const _TableCellFormat();
    final apply = _editBool(
        _fieldMetaValueAny(field, [
          'aplicar_formato_condicional_tabla',
          'aplicar formato condicional tabla',
          'aplicar_condicional_tabla',
          'formato_condicional_tabla'
        ]),
        defaultValue: false);
    if (!apply) return const _TableCellFormat();
    final legacyCondition = _fieldMetaValueAny(field, [
      'formato_condicional_campo',
      'formato condicional campo',
      'condicion_formato',
      'condición formato',
      'formato_condicional'
    ]);
    final result = _tableConditionalResult(field, row, column);
    final textCondition = _fieldMetaValueAny(
            field, ['condicion_color_texto', 'condicion color texto']) ??
        legacyCondition;
    final bgCondition = _fieldMetaValueAny(
            field, ['condicion_color_fondo', 'condicion color fondo']) ??
        legacyCondition;
    final borderCondition = _fieldMetaValueAny(
            field, ['condicion_color_borde', 'condicion color borde']) ??
        legacyCondition;
    final textColor = _tableStyleConditionApplies(textCondition, row, column)
        ? _parseTableMatrixColor(_resolveTableColorRaw(
            _fieldMetaValueAny(
                field, ['color_texto', 'color texto', 'texto_color']),
            result))
        : null;
    final bgColor = _tableStyleConditionApplies(bgCondition, row, column)
        ? _parseTableMatrixColor(_resolveTableColorRaw(
            _fieldMetaValueAny(
                field, ['color_fondo', 'color fondo', 'fondo_color']),
            result))
        : null;
    final borderColor =
        _tableStyleConditionApplies(borderCondition, row, column)
            ? _parseTableMatrixColor(_resolveTableColorRaw(
                _fieldMetaValueAny(
                    field, ['color_borde', 'color borde', 'borde_color']),
                result))
            : null;
    final fontSizeRaw = _fieldMetaValueAny(
        field, ['tamanio_letra', 'tamano_letra', 'tamaño_letra', 'font_size']);
    final parsedFontSize = double.tryParse(fontSizeRaw?.toString() ?? '');
    final fontSize =
        parsedFontSize != null && parsedFontSize >= 8 && parsedFontSize <= 72
            ? parsedFontSize
            : null;
    return _TableCellFormat(
        textColor: textColor,
        bgColor: bgColor,
        borderColor: borderColor,
        fontSize: fontSize);
  }

  DataCell _buildCell(String column, Map<String, dynamic> row) {
    final value = row[column];
    final text = _displayCellValue(value);
    if (_isHumanResourcesDocumentColumn(column)) {
      return DataCell(_humanResourcesStoredDocumentButton(row, column));
    }
    if (_isPayrollSlipTable && _norm(column) == 'PDF_URL') {
      return DataCell(IconButton(
        tooltip: text.isEmpty ? 'Generar boleta PDF' : 'Ver boleta PDF',
        icon: Icon(text.isEmpty
            ? Icons.picture_as_pdf_outlined
            : Icons.picture_as_pdf),
        color: const Color(0xFFC62828),
        onPressed: () => _openOrGeneratePayrollSlip(row),
      ));
    }
    if (text.isEmpty) return const DataCell(Text(''));
    if (_isMediaColumn(column) && _looksLikeUrl(text)) {
      return DataCell(_mediaCell(column, text));
    }
    return DataCell(
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
      ),
    );
  }

  bool _isHiddenWindowsColumn(String column) {
    final n = _norm(column);
    const hidden = {
      'ID',
      'ID_LOCAL',
      'ID_LOCA_L',
      'ID_REGISTRO',
      'HASH_FILA_SIN_IDS',
      'HASH_FILA_SIN_ID',
    };
    if (hidden.contains(n)) return true;
    const technical = {
      'EMPRESA_ID',
      'USER_ID',
      'CREATED_BY',
      'UPDATED_BY',
      'CREATED_AT',
      'UPDATED_AT',
      'DELETED_AT',
      'ESTADO_SYNC',
      'VERSION',
      'ACTIVO',
      'ELIMINADO',
      'ID_FILA_SERIAL',
    };
    return technical.contains(n) || n.startsWith('ID_') || n.endsWith('_ID');
  }

  Map<String, dynamic>? _fieldDefForCurrentTableColumn(String column) {
    final wanted = _norm(column);
    final currentTable = _norm(tableName ?? '');
    if (wanted.isEmpty) return null;
    final cacheKey = '$currentTable|$wanted';
    if (_fieldDefColumnCache.containsKey(cacheKey))
      return _fieldDefColumnCache[cacheKey];

    Map<String, dynamic>? fallback;
    // Usar allLocalFormFields, no fieldDefsById.values. fieldDefsById se indexa
    // por id/campo/etiqueta con putIfAbsent; cuando muchas tablas comparten
    // columnas como FECHA, PRODUCTO o ESTADO, algunas definiciones desaparecen
    // del mapa. Eso hacía que Windows tomara metadata de otra tabla o no tomara
    // visible/numero_decimales correctamente.
    for (final def in allLocalFormFields) {
      final campo = _norm(def['campo']?.toString() ?? '');
      final etiqueta = _norm(def['etiqueta']?.toString() ?? '');
      final defTable = _norm(def['tabla_destino']?.toString() ?? '');
      final matches = wanted == campo || wanted == etiqueta;
      if (!matches) continue;
      if (currentTable.isNotEmpty && defTable == currentTable) {
        _fieldDefColumnCache[cacheKey] = def;
        return def;
      }
      fallback ??= def;
    }
    _fieldDefColumnCache[cacheKey] = fallback;
    return fallback;
  }

  String _tableHeaderLabel(String column) {
    // En tablas Windows se muestra el nombre real del campo.
    // La etiqueta queda reservada para formularios/captura.
    final def = _fieldDefForCurrentTableColumn(column);
    final campo = def?['campo']?.toString().trim() ?? '';
    if (campo.isNotEmpty && campo.toUpperCase() != 'NULL') return campo;
    return column;
  }

  List<String> _visibleWindowsColumns(List<String> sourceColumns) {
    final out = <String>[];
    final seen = <String>{};
    for (final column in sourceColumns) {
      final n = _norm(column);
      final def = _fieldDefForCurrentTableColumn(column);
      final tipoUi = def?['tipo_ui']?.toString().trim().toLowerCase() ?? '';
      final visibleTabla = def == null
          ? false
          : _editBool(def['visible_tabla'] ?? def['visible'],
              defaultValue: true);
      if (n.isEmpty ||
          def == null ||
          !visibleTabla ||
          _isHiddenWindowsColumn(column) ||
          tipoUi == 'hidden' ||
          tipoUi == 'hidden_id') continue;
      if (seen.add(n)) out.add(column);
    }
    return out;
  }

  List<String> _matrixColumnsForTable(
      String table, List<String> fetchedColumns) {
    final wantedTable = _norm(table);
    final cacheKey = '$wantedTable|${fetchedColumns.map(_norm).join('|')}';
    final cached = _matrixColumnsCache[cacheKey];
    if (cached != null) return cached;

    final fetchedByNorm = <String, String>{};
    for (final c in fetchedColumns) {
      fetchedByNorm.putIfAbsent(_norm(c), () => c);
    }
    final out = <String>[];
    final seen = <String>{};
    for (final def in allLocalFormFields) {
      final defTable = _norm(def['tabla_destino']?.toString() ?? '');
      if (wantedTable.isNotEmpty && defTable != wantedTable) continue;
      final campo = def['campo']?.toString().trim() ?? '';
      if (campo.isEmpty) continue;
      final tipoUi = def['tipo_ui']?.toString().trim().toLowerCase() ?? '';
      final visibleTabla =
          _editBool(def['visible_tabla'] ?? def['visible'], defaultValue: true);
      if (!visibleTabla ||
          tipoUi == 'hidden' ||
          tipoUi == 'hidden_id' ||
          _isHiddenWindowsColumn(campo)) continue;
      final norm = _norm(campo);
      if (seen.add(norm)) out.add(fetchedByNorm[norm] ?? campo);
    }
    final result =
        out.isNotEmpty ? out : _visibleWindowsColumns(fetchedColumns);
    _matrixColumnsCache[cacheKey] = List<String>.unmodifiable(result);
    return _matrixColumnsCache[cacheKey]!;
  }

  double _tableColumnWidth(String column) {
    final custom = _columnWidths[column];
    if (custom != null) return custom;
    if (_isPayrollSlipTable && _norm(column) == 'PDF_URL') return 92;
    if (_isHumanResourcesApprovalTable &&
        const {'DOCUMENTO_GENERADO', 'DOCUMENTO_SUSTENTO'}
            .contains(_norm(column))) {
      return 130;
    }

    final clean = column.trim();
    if (clean.length > 28) return 230;
    if (_norm(clean).contains('OBSERV') || _norm(clean).contains('DESCRIP'))
      return 260;
    if (_norm(clean).contains('FOTO') || _norm(clean).contains('FIRMA'))
      return 180;
    return 150;
  }

  void _setColumnWidth(String column, double width) {
    _columnWidths[column] = width.clamp(80.0, 520.0);
    _columnWidthDebounce?.cancel();
    _columnWidthDebounce = Timer(const Duration(milliseconds: 40), () {
      if (mounted) _notifyTableRenderChanged();
    });
  }

  String? _primaryKeyColumn(Map<String, dynamic> row) {
    final preferredNormalized = <String>[
      'ID',
      'ID_LOCAL',
      'PK_ID',
      'ID_PK',
      'HASH_FILA_SIN_IDS',
      'HASH_FILA_SIN_ID',
    ];

    for (final wanted in preferredNormalized) {
      for (final entry in row.entries) {
        if (_norm(entry.key) != wanted) continue;
        final value = entry.value;
        if (value != null &&
            value.toString().trim().isNotEmpty &&
            value.toString().trim().toUpperCase() != 'NULL') {
          return entry.key;
        }
      }
    }

    for (final key in row.keys) {
      final n = _norm(key);
      final value = row[key];
      if ((n == 'ID' || n.endsWith('_ID')) &&
          value != null &&
          value.toString().trim().isNotEmpty &&
          value.toString().trim().toUpperCase() != 'NULL') {
        return key;
      }
    }
    return null;
  }

  bool _isEditableColumn(String column) {
    final n = _norm(column);
    const blocked = {
      'ID',
      'ID_LOCAL',
      'ID_FILA_SERIAL',
      'PK_ID',
      'ID_PK',
      'CREATED_AT',
      'UPDATED_AT',
      'USER_ID',
      'HASH_FILA_SIN_IDS',
      'HASH_FILA_SIN_ID',
      'ID_REGISTRO',
    };
    return !_isHiddenWindowsColumn(column) && !blocked.contains(n);
  }

  String _editRawFieldValue(
      Map<String, dynamic> field, List<String> candidates) {
    final value = _value(field, candidates);
    final text = value?.toString().trim() ?? '';
    return text.toUpperCase() == 'NULL' ? '' : text;
  }

  String _editTipo(Map<String, dynamic> field) {
    final tipo =
        _editRawFieldValue(field, ['tipo', 'type', 'tipo_dato', 'data_type']);
    return tipo.isEmpty ? 'text' : tipo.toLowerCase();
  }

  String _editUiType(Map<String, dynamic> field) {
    final ui = _editRawFieldValue(
        field, ['tipo_ui', 'tipo ui', 'ui', 'tipo_control', 'control_ui']);
    if (ui.isNotEmpty) return ui.toLowerCase();
    return _editTipo(field);
  }

  String _editDropdownRaw(Map<String, dynamic> field) {
    return _editRawFieldValue(field, [
      'id_campo_dropdown',
      'id campo dropdown',
      'id_dropdown',
      'campo_dropdown',
      'dropdown'
    ]);
  }

  String _editFormulaRaw(Map<String, dynamic> field) {
    return _editRawFieldValue(field,
        ['formula_funcion', 'formula funcion', 'formula', 'funcion_formula']);
  }

  bool _editBool(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    if (s.isEmpty || s == 'null') return defaultValue;
    return s == 'true' || s == '1' || s == 'si' || s == 'sí' || s == 'yes';
  }

  bool _editFieldEditable(Map<String, dynamic> field) {
    final ui = _editUiType(field);
    final tipo = _editTipo(field);
    if (ui == 'formula' ||
        ui == 'lookup' ||
        tipo == 'calculated' ||
        tipo == 'readonly') return false;
    final raw = field['editable'];
    if (raw == null) return true;
    return _editBool(raw, defaultValue: true);
  }

  int _editNumeroDecimales(Map<String, dynamic> field) {
    final raw = field['numero_decimales'];
    if (raw == null) return 0;
    if (raw is int) return raw.clamp(0, 8).toInt();
    if (raw is num) return raw.toInt().clamp(0, 8).toInt();
    final text = raw.toString().trim();
    if (text.isEmpty || text.toUpperCase() == 'NULL') return 0;
    final parsed = int.tryParse(text);
    return (parsed ?? 0).clamp(0, 8).toInt();
  }

  String _editFormatNumberText(dynamic value, Map<String, dynamic> field) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty || raw.toUpperCase() == 'NULL') return '';
    final number = double.tryParse(raw.replaceAll(',', '.'));
    if (number == null) return raw;
    return number.toStringAsFixed(_editNumeroDecimales(field));
  }

  bool _editIsNumberField(Map<String, dynamic> field) {
    final tipo = _editTipo(field);
    final ui = _editUiType(field);
    return tipo == 'number' ||
        tipo == 'numeric' ||
        tipo == 'decimal' ||
        tipo == 'double' ||
        tipo == 'integer' ||
        tipo == 'int' ||
        ui == 'number' ||
        ui == 'numeric' ||
        ui == 'decimal' ||
        ui == 'double' ||
        ui == 'integer' ||
        ui == 'int';
  }

  bool _editAllowsDecimal(Map<String, dynamic> field) {
    final tipo = _editTipo(field);
    final ui = _editUiType(field);
    if (tipo == 'integer' || tipo == 'int' || ui == 'integer' || ui == 'int')
      return false;
    return _editNumeroDecimales(field) > 0;
  }

  int? _editMaxCharacters(Map<String, dynamic> field) {
    final raw = field['num_caracteres'];
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty || text.toUpperCase() == 'NULL') return null;
    final parsed = int.tryParse(text);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  List<TextInputFormatter> _editInputFormattersForField(
      Map<String, dynamic> field) {
    final formatters = <TextInputFormatter>[];
    if (_editIsNumberField(field)) {
      final decimals = _editNumeroDecimales(field);
      final decimal = _editAllowsDecimal(field);
      formatters.add(TextInputFormatter.withFunction((oldValue, newValue) {
        final text = newValue.text.trim();
        if (text.isEmpty || text == '-') return newValue;
        final pattern = decimal
            ? RegExp(r'^-?\d*([.,]\d{0,' + decimals.toString() + r'})?$')
            : RegExp(r'^-?\d*$');
        return pattern.hasMatch(text) ? newValue : oldValue;
      }));
    }
    final maxChars = _editMaxCharacters(field);
    if (maxChars != null)
      formatters.add(LengthLimitingTextInputFormatter(maxChars));
    return formatters;
  }

  String? _editNumberValidationError(
      Map<String, dynamic> field, String raw, String label) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (!_editIsNumberField(field)) return null;
    final number = num.tryParse(text.replaceAll(',', '.'));
    if (number == null) return 'El campo "$label" debe ser numérico.';
    if (!_editAllowsDecimal(field) && text.contains(RegExp(r'[.,]'))) {
      return 'El campo "$label" no acepta decimales según su configuración.';
    }
    final decimals = _editNumeroDecimales(field);
    final match = RegExp(r'[.,](\d+)$').firstMatch(text);
    if (match != null && match.group(1)!.length > decimals) {
      return 'El campo "$label" solo acepta $decimals decimal(es).';
    }
    return null;
  }

  String _editFieldLabel(Map<String, dynamic>? field, String campo) {
    final label = field?['etiqueta']?.toString().trim();
    return (label == null || label.isEmpty || label.toUpperCase() == 'NULL')
        ? campo
        : label;
  }

  String _editUnwrapBracketReference(String value) {
    final text = value.trim();
    if (text.startsWith('[') && text.endsWith(']') && text.length >= 2) {
      return text.substring(1, text.length - 1).trim();
    }
    return text;
  }

  bool _editIsLiteralDropdownSource(String value) {
    final text = value.trim();
    if (!text.startsWith('[') || !text.endsWith(']')) return false;

    // [a,b,c] o [a;b;c] es lista manual.
    // [uuid-del-campo] / [CAMPO] / [Etiqueta] es referencia dinámica.
    final content = _editUnwrapBracketReference(text);
    return content.contains(',') ||
        content.contains(';') ||
        content.contains('|');
  }

  List<String>? _editLiteralDropdownOptions(Map<String, dynamic> field) {
    final raw = _editDropdownRaw(field);
    if (raw.isEmpty) return null;
    if (!_editIsLiteralDropdownSource(raw)) return null;
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

  Map<String, dynamic>? _editFieldDefByIdentifier(String identifier) {
    final wanted = _norm(identifier);
    if (wanted.isEmpty) return null;
    final currentTable = _norm(tableName ?? '');

    Map<String, dynamic>? fallback;
    for (final field in allLocalFormFields) {
      final matches = [
        field['id'],
        field['campo'],
        field['etiqueta'],
        field['nombre_campo']
      ].any((value) => _norm(value?.toString() ?? '') == wanted);
      if (!matches) continue;
      final fieldTable = _norm(field['tabla_destino']?.toString() ?? '');
      if (currentTable.isNotEmpty && fieldTable == currentTable) return field;
      fallback ??= field;
    }
    return fallback ?? fieldDefsById[wanted];
  }

  String _editCatalogKeyForSourceField(Map<String, dynamic> sourceField) {
    final sourceTable = sourceField['tabla_destino']?.toString() ?? '';
    final sourceColumn = sourceField['campo']?.toString() ?? '';
    return '$sourceTable.$sourceColumn';
  }

  List<String> _editOptionsForCatalog(String catalogKey) {
    final direct = catalogValues[catalogKey];
    if (direct != null && direct.isNotEmpty) return direct;

    final parts = catalogKey.split('.');
    if (parts.length < 2) return const <String>[];
    final table = parts.first.trim();
    final column = parts.sublist(1).join('.').trim();
    final rows = matrixRowsByTable[table] ?? const <Map<String, dynamic>>[];
    final seen = <String>{};
    final out = <String>[];
    final wanted = _norm(column);
    for (final row in rows) {
      dynamic value = row[column];
      if (value == null) {
        for (final entry in row.entries) {
          if (_norm(entry.key) == wanted) {
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
    return out;
  }

  String? _editDynamicDropdownCatalog(Map<String, dynamic> field) {
    final dropdownRaw = _editDropdownRaw(field);
    if (dropdownRaw.isEmpty) return null;
    if (_editIsLiteralDropdownSource(dropdownRaw)) return null;
    final dropdownId = _editUnwrapBracketReference(dropdownRaw);
    if (dropdownId.contains('.')) return dropdownId;
    final sourceField = _editFieldDefByIdentifier(dropdownId);
    if (sourceField == null) return null;
    return _editCatalogKeyForSourceField(sourceField);
  }

  bool _editHasDropdownSource(Map<String, dynamic> field) {
    final raw = _editDropdownRaw(field);
    return raw.isNotEmpty;
  }

  String _editNormalizeTimeText(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text.toUpperCase() == 'NULL') return '';
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(text);
    if (match == null) return text;
    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    if (hour == null || minute == null) return text;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  Future<List<Map<String, dynamic>>> _editFieldRows(
      String table, Map<String, dynamic> row) async {
    final wanted = _norm(table);
    var rows = allLocalFormFields.where((field) {
      final activo = _editBool(field['activo'], defaultValue: true);
      return activo &&
          _norm(field['tabla_destino']?.toString() ?? '') == wanted;
    }).toList();
    if (rows.isEmpty) {
      rows = await local.where(
        'local_form_fields',
        'tabla_destino = ? and activo = 1',
        [table],
        orderBy: 'orden',
      );
    }

    final technical = {
      'ID',
      'ID_LOCAL',
      'ID_FILA_SERIAL',
      'PK_ID',
      'ID_PK',
      'HASH_FILA_SIN_IDS',
      'HASH_FILA_SIN_ID',
      'ID_REGISTRO'
    };
    final normalizedRowKeys = row.keys.map(_norm).toSet();
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final field in rows) {
      final campo = field['campo']?.toString().trim() ?? '';
      if (campo.isEmpty) continue;
      final n = _norm(campo);
      if (technical.contains(n)) continue;
      if (_editUiType(field) == 'hidden_id' || _editUiType(field) == 'hidden')
        continue;
      if (!normalizedRowKeys.contains(n)) {
        // Permite campos de fórmula/lookup aunque no hayan venido en la consulta si están en matriz.
        final ui = _editUiType(field);
        if (ui != 'formula' && ui != 'lookup') continue;
      }
      if (seen.add(n)) result.add(field);
    }

    if (result.isEmpty) {
      for (final column in (displayColumns.isNotEmpty
              ? displayColumns
              : _columnsFromRows([row]))
          .where(_isEditableColumn)) {
        result.add({
          'campo': column,
          'etiqueta': column,
          'tipo': 'text',
          'tipo_ui': 'text',
          'editable': true
        });
      }
    }
    return result;
  }

  String _editInitialValue(Map<String, dynamic> row, String campo,
      [Map<String, dynamic>? field]) {
    String? value;
    if (row.containsKey(campo)) {
      value = _displayCellValue(row[campo]);
    } else {
      final wanted = _norm(campo);
      for (final entry in row.entries) {
        if (_norm(entry.key) == wanted) {
          value = _displayCellValue(entry.value);
          break;
        }
      }
    }

    if (value != null &&
        value.trim().isNotEmpty &&
        value.toUpperCase() != 'NULL') {
      if (field != null &&
          (_editTipo(field) == 'time' || _editUiType(field) == 'time')) {
        return _editNormalizeTimeText(value);
      }
      return value;
    }

    final defaultValue = field?['valor_default']?.toString().trim() ?? '';
    if (defaultValue.isNotEmpty && defaultValue.toUpperCase() != 'NULL') {
      final tipo = field == null ? '' : _editTipo(field);
      final ui = field == null ? '' : _editUiType(field);
      if (field != null &&
          (tipo == 'number' ||
              tipo == 'numeric' ||
              tipo == 'integer' ||
              ui == 'number' ||
              ui == 'numeric' ||
              ui == 'integer')) {
        return _editFormatNumberText(defaultValue, field);
      }
      return defaultValue;
    }

    return value ?? '';
  }

  void _editRecalculateFormulas(
      {required List<Map<String, dynamic>> fields,
      required Map<String, TextEditingController> controllers}) {
    String valueOf(String campo) {
      final wanted = _norm(campo);
      for (final entry in controllers.entries) {
        if (_norm(entry.key) == wanted) return entry.value.text.trim();
      }
      return '';
    }

    final engine = FormulaEngine(
      fields: fields,
      matrixRowsByTable: matrixRowsByTable,
      getValue: valueOf,
    );

    for (var pass = 0; pass < 3; pass++) {
      for (final field in fields) {
        final ui = _editUiType(field);
        if (ui != 'formula' && ui != 'lookup') continue;
        final campo = field['campo']?.toString() ?? '';
        final formula = _editFormulaRaw(field);
        final controller = controllers[campo];
        if (campo.isEmpty || formula.trim().isEmpty || controller == null)
          continue;
        try {
          final result = engine.evaluateToText(formula);
          if (controller.text != result) controller.text = result;
        } catch (_) {}
      }
    }
  }

  Future<String?> _editShowSearchableDropdownPicker({
    required BuildContext dialogContext,
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
        context: dialogContext,
        builder: (context) {
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
            title: Text(title),
            content: SizedBox(
              width: 480,
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
                      constraints: const BoxConstraints(maxHeight: 420),
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
                                return ListTile(
                                  dense: true,
                                  title: Text(option),
                                  trailing:
                                      selected ? const Icon(Icons.check) : null,
                                  onTap: () => Navigator.pop(context, option),
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
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar')),
              TextButton(
                  onPressed: () => Navigator.pop(context, ''),
                  child: const Text('Limpiar')),
            ],
          );
        },
      );
    } finally {
      searchController.dispose();
    }
  }

  Widget _editSearchableDropdownField({
    required BuildContext dialogContext,
    required String label,
    required TextEditingController controller,
    required List<String> options,
    required bool editable,
    required VoidCallback recalc,
  }) {
    final current = controller.text.trim();
    final hasValidValue = current.isNotEmpty && options.contains(current);
    return InkWell(
      onTap: editable
          ? () async {
              final selected = await _editShowSearchableDropdownPicker(
                dialogContext: dialogContext,
                title: label,
                options: options,
                currentValue: hasValidValue ? current : null,
              );
              if (selected == null) return;
              controller.text = selected;
              recalc();
            }
          : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: Icon(editable ? Icons.search : Icons.lock_outline),
          helperText: options.isEmpty
              ? 'Sin opciones configuradas o descargadas.'
              : null,
        ),
        child: Text(
          hasValidValue ? current : 'Seleccione o busque...',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: hasValidValue ? null : Colors.grey[600]),
        ),
      ),
    );
  }

  Widget _editFieldWidget({
    required BuildContext dialogContext,
    required Map<String, dynamic> field,
    required Map<String, TextEditingController> controllers,
    required List<Map<String, dynamic>> fields,
    required void Function(void Function()) setDialogState,
  }) {
    final campo = field['campo']?.toString() ?? '';
    final label = _editFieldLabel(field, campo);
    final tipo = _editTipo(field);
    final ui = _editUiType(field);
    final editable = _editFieldEditable(field) && !_isMediaColumn(campo);
    final controller = controllers[campo] ??= TextEditingController();

    void recalc() => setDialogState(() =>
        _editRecalculateFormulas(fields: fields, controllers: controllers));

    Set<String> parseMultiSelect(String raw) {
      if (raw.trim().isEmpty) return <String>{};
      return raw
          .split(RegExp(r'[|,;]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
    }

    if (ui == 'multiselect') {
      final options = _editLiteralDropdownOptions(field) ??
          _editOptionsForCatalog(_editDynamicDropdownCatalog(field) ?? '');
      final selected = parseMultiSelect(controller.text);
      final selectedText = selected.isEmpty
          ? 'Seleccionar...'
          : (selected.toList()..sort()).join(', ');

      Future<void> openPicker() async {
        if (!editable || options.isEmpty) return;
        final temp = Set<String>.from(selected);
        final result = await showDialog<Set<String>>(
          context: dialogContext,
          builder: (context) => AlertDialog(
            title: Text(label),
            content: SizedBox(
              width: 420,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: StatefulBuilder(
                  builder: (context, setLocalState) => ListView.builder(
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final checked = temp.contains(option);
                      return CheckboxListTile(
                        value: checked,
                        title: Text(option),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (value) {
                          setLocalState(() {
                            if (value == true) {
                              temp.add(option);
                            } else {
                              temp.remove(option);
                            }
                          });
                        },
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
        controller.text = (result.toList()..sort()).join('|');
        recalc();
      }

      return InkWell(
        onTap: openPicker,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
            helperText: options.isEmpty
                ? 'Sin opciones configuradas o descargadas.'
                : 'Toca para seleccionar uno o varios valores',
            suffixIcon:
                Icon(editable ? Icons.arrow_drop_down : Icons.lock_outline),
          ),
          child: Text(
            selectedText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: selected.isEmpty ? Colors.grey[600] : null),
          ),
        ),
      );
    }

    if (ui == 'dropdown' || _editHasDropdownSource(field)) {
      final options = _editLiteralDropdownOptions(field) ??
          _editOptionsForCatalog(_editDynamicDropdownCatalog(field) ?? '');
      if (options.isNotEmpty) {
        return _editSearchableDropdownField(
          dialogContext: dialogContext,
          label: label,
          controller: controller,
          options: options,
          editable: editable,
          recalc: recalc,
        );
      }
    }

    if (tipo == 'time' || ui == 'time') {
      return TextField(
        controller: controller,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: const Icon(Icons.access_time, size: 18),
        ),
        onTap: editable
            ? () async {
                final normalized = _editNormalizeTimeText(controller.text);
                TimeOfDay initial = TimeOfDay.now();
                final parts = normalized.split(':');
                if (parts.length >= 2) {
                  final hour = int.tryParse(parts[0]);
                  final minute = int.tryParse(parts[1]);
                  if (hour != null &&
                      minute != null &&
                      hour >= 0 &&
                      hour <= 23 &&
                      minute >= 0 &&
                      minute <= 59) {
                    initial = TimeOfDay(hour: hour, minute: minute);
                  }
                }
                final picked = await showTimePicker(
                  context: dialogContext,
                  initialTime: initial,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(alwaysUse24HourFormat: true),
                    child: child ?? const SizedBox.shrink(),
                  ),
                );
                if (picked == null) return;
                controller.text =
                    '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                recalc();
              }
            : null,
      );
    }

    if (tipo == 'date' || ui == 'date') {
      return TextField(
        controller: controller,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        onTap: editable
            ? () async {
                final initial =
                    DateTime.tryParse(controller.text.trim()) ?? DateTime.now();
                final picked = await showDatePicker(
                  context: dialogContext,
                  initialDate: initial,
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2100),
                );
                if (picked == null) return;
                controller.text = picked.toIso8601String().substring(0, 10);
                recalc();
              }
            : null,
      );
    }

    return TextField(
      controller: controller,
      readOnly: !editable || ui == 'formula' || ui == 'lookup',
      keyboardType: _editIsNumberField(field)
          ? TextInputType.numberWithOptions(
              decimal: _editAllowsDecimal(field), signed: true)
          : TextInputType.text,
      inputFormatters: _editInputFormattersForField(field),
      minLines: _isMediaColumn(campo) ? 1 : 1,
      maxLines: _isMediaColumn(campo) ? 3 : 1,
      onChanged: (_) =>
          _editRecalculateFormulas(fields: fields, controllers: controllers),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        helperText: (ui == 'formula' || ui == 'lookup')
            ? 'Calculado según matriz'
            : null,
      ),
    );
  }

  int? _editGridNumber(Map<String, dynamic> field, String key) {
    final raw = key == 'grid_fila'
        ? _value(field, ['grid_fila', 'grid fila', 'fila', 'fila_grid'])
        : _value(
            field, ['grid_columna', 'grid columna', 'columna', 'columna_grid']);
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty || text.toUpperCase() == 'NULL') return null;
    final parsed = int.tryParse(text);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  Widget _editSignatureWidget({
    required BuildContext dialogContext,
    required String column,
    required TextEditingController controller,
    required Map<String, Uint8List> newSignatures,
    required void Function(void Function()) setDialogState,
  }) {
    final currentValue = controller.text.trim();
    final hasNewSignature = newSignatures.containsKey(column);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: column,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasNewSignature)
            Container(
              height: 92,
              alignment: Alignment.center,
              color: const Color(0xFFF4F8F2),
              child: Image.memory(newSignatures[column]!, fit: BoxFit.contain),
            )
          else if (currentValue.isNotEmpty && _looksLikeUrl(currentValue))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _openMediaPreview(column, currentValue),
                icon: const Icon(Icons.visibility),
                label: const Text('Ver firma actual'),
              ),
            )
          else
            const Text('Sin firma capturada'),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () async {
                final bytes = await showDialog<Uint8List>(
                  context: dialogContext,
                  barrierDismissible: false,
                  builder: (_) => const SignatureDialog(),
                );
                if (bytes == null) return;
                setDialogState(() {
                  newSignatures[column] = bytes;
                });
              },
              icon: const Icon(Icons.draw),
              label: Text(
                  hasNewSignature ? 'Volver a firmar' : 'Capturar nueva firma'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editWidgetForField({
    required BuildContext dialogContext,
    required Map<String, dynamic> field,
    required Map<String, TextEditingController> controllers,
    required List<Map<String, dynamic>> fields,
    required Map<String, Uint8List> newSignatures,
    required void Function(void Function()) setDialogState,
  }) {
    final column = field['campo']?.toString() ?? '';
    if (_isSignatureColumn(column)) {
      return _editSignatureWidget(
        dialogContext: dialogContext,
        column: column,
        controller: controllers[column] ??= TextEditingController(),
        newSignatures: newSignatures,
        setDialogState: setDialogState,
      );
    }
    return _editFieldWidget(
      dialogContext: dialogContext,
      field: field,
      controllers: controllers,
      fields: fields,
      setDialogState: setDialogState,
    );
  }

  int _editFieldOrderNumber(Map<String, dynamic> field) {
    final parsed = int.tryParse(field['orden']?.toString() ?? '');
    if (parsed == null || parsed <= 0) return 999999;
    return parsed;
  }

  List<Widget> _buildEditDialogRows({
    required BuildContext dialogContext,
    required List<Map<String, dynamic>> editFields,
    required Map<String, TextEditingController> controllers,
    required Map<String, Uint8List> newSignatures,
    required void Function(void Function()) setDialogState,
  }) {
    // Misma regla que el formulario móvil/general:
    // grid_fila manda la fila visual; si no existe, se usa orden.
    // Antes se pintaban primero todas las filas con grid y eso hacía que T1..T4
    // aparezcan arriba aunque tu matriz los tenga en grid_fila=6.
    final rowBuckets = <int, List<Map<String, dynamic>>>{};
    for (final field in editFields) {
      final fila =
          _editGridNumber(field, 'grid_fila') ?? _editFieldOrderNumber(field);
      rowBuckets.putIfAbsent(fila, () => <Map<String, dynamic>>[]).add(field);
    }

    final children = <Widget>[];
    void addField(Map<String, dynamic> field) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _editWidgetForField(
          dialogContext: dialogContext,
          field: field,
          controllers: controllers,
          fields: editFields,
          newSignatures: newSignatures,
          setDialogState: setDialogState,
        ),
      ));
    }

    for (final entry in rowBuckets.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      final rowFields = entry.value;
      rowFields.sort((a, b) {
        final ca =
            _editGridNumber(a, 'grid_columna') ?? _editFieldOrderNumber(a);
        final cb =
            _editGridNumber(b, 'grid_columna') ?? _editFieldOrderNumber(b);
        if (ca != cb) return ca.compareTo(cb);
        return _editFieldOrderNumber(a).compareTo(_editFieldOrderNumber(b));
      });
      if (rowFields.length == 1) {
        addField(rowFields.first);
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < rowFields.length; i++) ...[
                Expanded(
                  child: _editWidgetForField(
                    dialogContext: dialogContext,
                    field: rowFields[i],
                    controllers: controllers,
                    fields: editFields,
                    newSignatures: newSignatures,
                    setDialogState: setDialogState,
                  ),
                ),
                if (i < rowFields.length - 1) const SizedBox(width: 12),
              ],
            ],
          ),
        ));
      }
    }
    return children;
  }

  String? _editControllerColumnByCandidates(
    Map<String, TextEditingController> controllers,
    List<String> candidates,
  ) {
    final wanted = candidates.map(_norm).toSet();
    for (final column in controllers.keys) {
      if (wanted.contains(_norm(column))) return column;
    }
    return null;
  }

  String _editControllerTextByCandidates(
    Map<String, TextEditingController> controllers,
    List<String> candidates,
  ) {
    final column = _editControllerColumnByCandidates(controllers, candidates);
    return column == null ? '' : controllers[column]!.text.trim();
  }

  Future<bool> _confirmPersonalStatusTransition(
    Map<String, dynamic> row,
    Map<String, TextEditingController> controllers,
  ) async {
    final statusColumn = _editControllerColumnByCandidates(
      controllers,
      const ['Status', 'ESTADO', 'ESTADO_PERSONAL'],
    );
    if (statusColumn == null) return true;

    final oldStatus = _norm(
      _rowText(row, const ['Status', 'ESTADO', 'ESTADO_PERSONAL']),
    );
    final newStatus = _norm(controllers[statusColumn]!.text);
    final active = _norm('Activo');
    final terminated = _norm('Cese');
    final pendingRenewal = _norm('pendiente renovación');

    if (newStatus == terminated &&
        oldStatus != terminated &&
        (oldStatus == active || oldStatus == pendingRenewal)) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirmar cese'),
          content: const Text(
            '¿Está seguro de activar Cese para este trabajador?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Activar Cese'),
            ),
          ],
        ),
      );
      if (confirmed != true) return false;
    }

    if (newStatus != active ||
        (oldStatus != terminated && oldStatus != pendingRenewal)) return true;

    const startCandidates = [
      'Fecha inicio de Contrato',
      'FECHA_INICIO_CONTRATO'
    ];
    const endCandidates = ['Fecha fin de Contrato', 'FECHA_FIN_CONTRATO'];
    final required = <String, List<String>>{
      'Fecha inicio de Contrato': startCandidates,
      'Fecha fin de Contrato': endCandidates,
    };
    if (oldStatus == terminated) {
      required.addAll({
        'Fecha de Ingreso': const ['Fecha de Ingreso', 'FECHA_INGRESO'],
        'Sueldo': const ['Sueldo', 'SUELDO_MENSUAL', 'REMUNERACION'],
        'Asignación familiar': const [
          'Asignación familiar',
          'ASIGNACION_FAMILIAR'
        ],
      });
    }

    final missing = <String>[];
    for (final entry in required.entries) {
      if (_editControllerTextByCandidates(controllers, entry.value).isEmpty) {
        missing.add(entry.key);
      }
    }
    final salary = _editControllerTextByCandidates(
      controllers,
      const ['Sueldo', 'SUELDO_MENSUAL', 'REMUNERACION'],
    );
    if (oldStatus == terminated &&
        salary.isNotEmpty &&
        (num.tryParse(salary.replaceAll(',', '.')) ?? 0) <= 0) {
      if (!missing.contains('Sueldo')) missing.add('Sueldo mayor que cero');
    }
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Para activar al trabajador complete: ${missing.join(', ')}.',
          ),
        ),
      );
      return false;
    }

    final start = _parseDate(
      _editControllerTextByCandidates(controllers, startCandidates),
    );
    final end = _parseDate(
      _editControllerTextByCandidates(controllers, endCandidates),
    );
    if (start == null || end == null || end.isBefore(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El rango de contrato no es válido: la fecha fin debe ser igual o posterior al inicio.',
          ),
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _editRemoteRecord(Map<String, dynamic> row) async {
    final table = tableName;
    if (!canUpdate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No tienes permiso para actualizar este formato.')),
      );
      return;
    }
    if (!_workflowStateAllows(row, 'update')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No tienes permiso para editar registros en estado ${_workflowStateForRow(row)}.',
          ),
        ),
      );
      return;
    }
    if (table == null || table.trim().isEmpty) return;

    final pkColumn = _primaryKeyColumn(row);
    if (pkColumn == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'No se pudo identificar una columna ID para actualizar el registro.')),
      );
      return;
    }
    final pkValue = row[pkColumn];

    String? editIdLocal;
    for (final entry in row.entries) {
      if (_norm(entry.key) == 'ID_LOCAL') {
        editIdLocal = entry.value?.toString().trim();
        break;
      }
    }
    if (editIdLocal?.isEmpty == true) editIdLocal = null;

    String? formatTableId;
    for (final config in internalTableRows) {
      if (_norm(config['tabla_destino']?.toString() ?? '') == _norm(table)) {
        formatTableId = config['id']?.toString();
        break;
      }
    }

    final initialPayload = Map<String, dynamic>.from(row);
    final Widget page = special.isNotEmpty
        ? SpecialFormRouterPage(
            moduleId: widget.module['id'] as String,
            format: widget.format,
            special: special.first,
            initialPayload: initialPayload,
            editIdLocal: editIdLocal,
          )
        : FormRunnerPage(
            moduleId: widget.module['id'] as String,
            format: widget.format,
            initialPayload: initialPayload,
            editIdLocal: editIdLocal,
            initialFormatTableId: formatTableId,
            editPrimaryKeyColumn: pkColumn,
            editPrimaryKeyValue: pkValue,
          );

    final compact = widget.mobileMode || MediaQuery.sizeOf(context).width < 760;
    if (compact) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => page,
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => LayoutBuilder(
          builder: (context, constraints) {
            final width = math.min(
              ZumacResponsiveLimits.formDialog,
              constraints.maxWidth - 32.0,
            );
            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              backgroundColor: Colors.transparent,
              child: Center(
                child: SizedBox(
                  width: width,
                  height: constraints.maxHeight * 0.94,
                  child: ClipRRect(
                    borderRadius: BorderRadius.zero,
                    child: Material(
                      elevation: 10,
                      color: Colors.white,
                      child: page,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    if (!mounted) return;
    await _load();
  }

  void _notifyDeleteSelectionChanged() {
    _deleteSelectionVersion.value++;
  }

  void _notifyTableRenderChanged({bool filtersChanged = false}) {
    _tableRenderVersion.value++;
    if (filtersChanged) _filterControlsVersion.value++;
  }

  String _workflowStateForRow(Map<String, dynamic> row) {
    for (final preferred in const ['ESTADO_APROBACION', 'ESTADO']) {
      for (final entry in row.entries) {
        if (_norm(entry.key) == preferred) {
          return entry.value?.toString().trim().toUpperCase() ?? '';
        }
      }
    }
    return '';
  }

  bool _workflowStateAllows(Map<String, dynamic> row, String action) {
    if (_workflowStatePermissions.isEmpty) return true;
    final state = _workflowStateForRow(row);
    if (state.isEmpty) return true;
    final permissions = _workflowStatePermissions[state];
    if (permissions == null) return false;
    return permissions[action] ?? false;
  }

  void _toggleDeleteSelection(
      Map<String, dynamic> row, int index, bool? selected) {
    final key = _remoteRowHighlightKey(row, index);
    if (selected == true) {
      _selectedDeleteRowKeys.add(key);
      _selectedDeleteRows[key] = row;
    } else {
      _selectedDeleteRowKeys.remove(key);
      _selectedDeleteRows.remove(key);
    }
    _notifyDeleteSelectionChanged();
  }

  void _toggleSelectAllVisible(
      List<Map<String, dynamic>> rows, bool? selected) {
    if (selected == true) {
      for (var i = 0; i < rows.length; i++) {
        final key = _remoteRowHighlightKey(rows[i], i);
        _selectedDeleteRowKeys.add(key);
        _selectedDeleteRows[key] = rows[i];
      }
    } else {
      for (var i = 0; i < rows.length; i++) {
        final key = _remoteRowHighlightKey(rows[i], i);
        _selectedDeleteRowKeys.remove(key);
        _selectedDeleteRows.remove(key);
      }
    }
    _notifyDeleteSelectionChanged();
    _notifyTableRenderChanged();
  }

  Future<void> _deleteSelectedRows() async {
    final table = tableName;
    if (!canDelete ||
        table == null ||
        table.trim().isEmpty ||
        _selectedDeleteRows.isEmpty) return;
    final unauthorized = _selectedDeleteRows.values
        .where((row) => !_workflowStateAllows(row, 'delete'))
        .toList(growable: false);
    if (unauthorized.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La selección incluye registros cuyo estado no permite eliminar.',
          ),
        ),
      );
      return;
    }
    final count = _selectedDeleteRows.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar borrado'),
        content: Text('¿Está seguro de borrar $count registro(s)?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('Borrar'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      for (final row in _selectedDeleteRows.values) {
        final pkColumn = _primaryKeyColumn(row);
        if (pkColumn == null) continue;
        final pkValue = row[pkColumn];
        final nowIso = DateTime.now().toUtc().toIso8601String();
        await supabase.from(table).update({
          'eliminado': true,
          'deleted_at': nowIso,
          'updated_at': nowIso,
          'estado_sync': 'eliminado',
        }).eq(pkColumn, pkValue);
      }
      _selectedDeleteRowKeys.clear();
      _selectedDeleteRows.clear();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registro(s) eliminado(s).')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo borrar: $e')));
    }
  }

  String _approvalColumnForRow(Map<String, dynamic> row) {
    for (final key in row.keys) {
      if (_norm(key) == 'ESTADO_APROBACION') return key;
    }
    for (final key in row.keys) {
      if (_norm(key) == 'ESTADO') return key;
    }
    final currentTable = _norm(tableName ?? '');
    for (final field in allLocalFormFields) {
      if (_norm(field['tabla_destino']?.toString() ?? '') != currentTable) {
        continue;
      }
      final campo = field['campo']?.toString().trim() ?? '';
      if (_norm(campo) == 'ESTADO_APROBACION') return campo;
    }
    for (final field in allLocalFormFields) {
      if (_norm(field['tabla_destino']?.toString() ?? '') != currentTable) {
        continue;
      }
      final campo = field['campo']?.toString().trim() ?? '';
      if (_norm(campo) == 'ESTADO') return campo;
    }
    return 'ESTADO_APROBACION';
  }

  Future<void> _setSelectedWorkflowState(String nextState) async {
    final table = tableName;
    final desired = nextState.trim().toUpperCase();
    final allowed = switch (desired) {
      'REVISADO' => canReview,
      'APROBADO' => canApprove,
      'DESPACHADO' => _isNamedTable(table, 'ERP_VALES_DESPACHO_APPGT') &&
          (canApprove || canUpdate),
      'ANULADO' => canUpdate || canDelete,
      _ => false,
    };
    if (!_approvalsEnabled ||
        !allowed ||
        table == null ||
        table.trim().isEmpty ||
        _selectedDeleteRows.isEmpty) {
      return;
    }

    final eligible = <Map<String, dynamic>>[];
    for (final row in _selectedDeleteRows.values) {
      final column = _approvalColumnForRow(row);
      final current = row[column]?.toString().trim().toUpperCase() ?? '';
      final stateAllowed = _workflowStateAllows(row, 'update');
      final validTransition = switch (desired) {
        'REVISADO' => current == 'PENDIENTE' && stateAllowed,
        'APROBADO' => current == 'REVISADO' && stateAllowed,
        'DESPACHADO' => current == 'APROBADO' && stateAllowed,
        'ANULADO' => _isNamedTable(table, 'ERP_VALES_DESPACHO_APPGT')
            ? current != 'ANULADO'
            : const {'PENDIENTE', 'REVISADO', 'APROBADO'}.contains(current),
        _ => false,
      };
      if (validTransition) {
        eligible.add(row);
      }
    }
    if (eligible.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(switch (desired) {
          'APROBADO' =>
            'Para aprobar, seleccione registros que ya estén REVISADOS.',
          'REVISADO' =>
            'Para revisar, seleccione registros en estado PENDIENTE.',
          'DESPACHADO' =>
            'Para despachar, seleccione vales en estado APROBADO.',
          'ANULADO' => 'La selección no contiene registros anulables.',
          _ => 'No hay registros elegibles para esta transición.',
        }),
      ));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        title: Text(switch (desired) {
          'APROBADO' => 'Aprobar registros',
          'REVISADO' => 'Revisar registros',
          'DESPACHADO' => 'Despachar vales',
          'ANULADO' => 'Anular registros',
          _ => 'Actualizar registros',
        }),
        content: Text(
            'Se marcarán ${eligible.length} registro(s) como $desired. ¿Continuar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(switch (desired) {
              'APROBADO' => 'Aprobar',
              'REVISADO' => 'Revisar',
              'DESPACHADO' => 'Despachar',
              'ANULADO' => 'Anular',
              _ => 'Continuar',
            }),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      for (final row in eligible) {
        if (_isNamedTable(table, 'ERP_VALES_DESPACHO_APPGT')) {
          final number =
              _value(row, const ['numero', 'NUMERO'])?.toString().trim() ?? '';
          if (number.isNotEmpty) {
            await supabase.rpc('erp_cambiar_estado_vale_despacho_v1', params: {
              'p_vale_numero': number,
              'p_estado': desired,
            });
          }
        } else {
          final pkColumn = _primaryKeyColumn(row);
          if (pkColumn == null) continue;
          final column = _approvalColumnForRow(row);
          await supabase
              .from(table)
              .update({column: desired}).eq(pkColumn, row[pkColumn]);
        }
      }
      _selectedDeleteRowKeys.clear();
      _selectedDeleteRows.clear();
      _notifyDeleteSelectionChanged();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registro(s) marcados como $desired.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar la aprobación: $error')),
      );
    }
  }

  DataCell _deleteSelectCell(Map<String, dynamic> row, int index) {
    final key = _remoteRowHighlightKey(row, index);
    return DataCell(
      SizedBox(
        width: 48,
        child: StatefulBuilder(
          builder: (context, setLocalState) {
            final selected = _selectedDeleteRowKeys.contains(key);
            return Checkbox(
              value: selected,
              onChanged: (v) {
                _toggleDeleteSelection(row, index, v);
                setLocalState(() {});
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _showPinColumnsDialog(List<String> columns) async {
    final temp = Set<String>.from(_pinnedColumns.where(columns.contains));
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Fijar columnas'),
          content: SizedBox(
            width: 420,
            height: 460,
            child: ListView(
              children: columns
                  .map((column) => CheckboxListTile(
                        dense: true,
                        value: temp.contains(column),
                        title: Text(column),
                        onChanged: (v) => setLocalState(() {
                          if (v == true)
                            temp.add(column);
                          else
                            temp.remove(column);
                        }),
                      ))
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, <String>{}),
                child: const Text('Quitar fijadas')),
            FilledButton(
                onPressed: () => Navigator.pop(context, temp),
                child: const Text('Aplicar')),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _pinnedColumns
        ..clear()
        ..addAll(result);
    });
  }

  DataCell _editCell(Map<String, dynamic> row) {
    final allowed = canUpdate && _workflowStateAllows(row, 'update');
    return DataCell(
      IconButton(
        tooltip: allowed ? 'Editar registro' : 'Actualización no permitida',
        icon: Icon(Icons.edit,
            size: 18, color: allowed ? const Color(0xFF176B87) : Colors.grey),
        onPressed: allowed ? () => _editRemoteRecord(row) : null,
      ),
    );
  }

  String _remoteRowHighlightKey(Map<String, dynamic> row, int index) {
    final cached = _rowKeyCache[row];
    if (cached != null) return cached;

    const candidates = [
      'id_local',
      'ID_LOCAL',
      'id',
      'ID',
      'hash_fila_sin_ids',
      'HASH_FILA_SIN_IDS',
      'ID_REGISTRO',
      'id_registro'
    ];
    for (final key in candidates) {
      final value = row[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        final out = '$key:${value.toString()}';
        _rowKeyCache[row] = out;
        return out;
      }
    }

    final out = 'row:${identityHashCode(row)}';
    _rowKeyCache[row] = out;
    return out;
  }

  Widget _recordsTable(List<Map<String, dynamic>> rows) {
    final visibleRows = rows.length > _renderRowLimit
        ? rows.take(_renderRowLimit).toList()
        : rows;
    final rawColumns = displayColumns.isNotEmpty
        ? displayColumns
        : _columnsFromRows(records.isNotEmpty ? records : rows);
    final allColumnsRaw = _matrixColumnsForTable(
        tableName ?? widget.format['tabla_destino']?.toString() ?? '',
        rawColumns);
    final pinned =
        allColumnsRaw.where(_pinnedColumns.contains).toList(growable: false);
    final unpinned = allColumnsRaw
        .where((c) => !_pinnedColumns.contains(c))
        .toList(growable: false);
    final allColumns = <String>[...pinned, ...unpinned];
    if (allColumns.isEmpty) return _emptyMessage('No hay columnas visibles');

    // FASE 3C - RENDERIZADO VIRTUAL:
    // Antes se usaba DataTable. DataTable mide todas las celdas para calcular
    // anchos intrínsecos; con muchas columnas + 200 filas + acciones/fotos eso
    // bloquea el hilo UI al filtrar, seleccionar, editar o abrir/cerrar menú.
    // Este render mantiene la misma funcionalidad, pero usa filas virtualizadas
    // con ListView.builder: Flutter solo construye las filas visibles en pantalla.
    // Se desactivan keep-alives/índices semánticos en filas de grilla para reducir
    // memoria y reconstrucciones en tablas grandes, sin tocar datos/filtros/exportación.

    Widget headerCell(String column, double width) {
      final label = _tableHeaderLabel(column);
      final sorted = _sortColumn == column;
      return Container(
        width: width,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          color: _appgtHeaderColor,
          border:
              Border(right: BorderSide(color: Color(0x55314457), width: 0.8)),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () {
                  if (_sortColumn == column) {
                    _sortAscending = !_sortAscending;
                  } else {
                    _sortColumn = column;
                    _sortAscending = true;
                  }
                  _currentPage = 0;
                  _invalidateFilteredCache();
                  unawaited(_load());
                },
                onDoubleTap: () => _setColumnWidth(
                    column, _autoWidthForColumn(column, visibleRows)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5),
                      ),
                    ),
                    if (sorted)
                      Icon(
                          _sortAscending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 14,
                          color: Colors.white),
                  ],
                ),
              ),
            ),
            Tooltip(
              message: _columnFilters.containsKey(column)
                  ? 'Cambiar filtro de $label'
                  : 'Filtrar $label',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _showColumnValueFilterDialog(column),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Icon(
                    _columnFilters.containsKey(column)
                        ? Icons.filter_alt_rounded
                        : Icons.filter_alt_outlined,
                    size: 16,
                    color: _columnFilters.containsKey(column)
                        ? const Color(0xFFFFD166)
                        : Colors.white70,
                  ),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (details) => _setColumnWidth(
                  column, _tableColumnWidth(column) + details.delta.dx),
              child: const SizedBox(
                  width: 10,
                  height: 36,
                  child: Center(
                      child: VerticalDivider(
                          color: Color(0x99FFFFFF), thickness: 1))),
            ),
          ],
        ),
      );
    }

    Widget actionHeader({required double width, Widget? child}) {
      return Container(
        width: width,
        height: 48,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: _appgtHeaderColor,
          border:
              Border(right: BorderSide(color: Color(0x55314457), width: 0.8)),
        ),
        child: child,
      );
    }

    Widget deleteHeader() {
      final allVisibleSelected = visibleRows.isNotEmpty &&
          visibleRows.asMap().entries.every((e) => _selectedDeleteRowKeys
              .contains(_remoteRowHighlightKey(e.value, e.key)));
      return actionHeader(
        width: 54,
        child: Checkbox(
          value: allVisibleSelected,
          onChanged: (v) => _toggleSelectAllVisible(visibleRows, v),
          checkColor: const Color(0xFF176B87),
          fillColor: MaterialStateProperty.all(Colors.white),
        ),
      );
    }

    Widget rowCell(Map<String, dynamic> r, int index, String column) {
      final width = _tableColumnWidth(column);
      final value = r[column];
      final text = _displayCellValue(value);
      Widget child;
      final fmt = _tableCellFormat(column, r);
      if (_isHumanResourcesDocumentColumn(column)) {
        child = _humanResourcesStoredDocumentButton(r, column);
      } else if (_isErpDocumentTable && _norm(column) == 'PDF_URL') {
        child = _erpPdfCell(r);
      } else if (_isPayrollSlipTable && _norm(column) == 'PDF_URL') {
        child = Tooltip(
          message: text.isEmpty
              ? 'Generar boleta PDF'
              : 'Ver o descargar boleta PDF',
          child: IconButton(
            icon: Icon(
              text.isEmpty
                  ? Icons.picture_as_pdf_outlined
                  : Icons.picture_as_pdf,
              color: const Color(0xFFC62828),
            ),
            onPressed: () => _openOrGeneratePayrollSlip(r),
          ),
        );
      } else if (text.isEmpty) {
        child = const SizedBox.shrink();
      } else if (_isMediaColumn(column) && _looksLikeUrl(text)) {
        child = Align(
            alignment: Alignment.centerLeft, child: _mediaCell(column, text));
      } else {
        child = Text(text,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            style: TextStyle(
                color: fmt.textColor ?? Colors.black87,
                fontSize: fmt.fontSize ?? 12.5));
      }
      return Container(
        width: width,
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: fmt.bgColor ??
              (index.isEven ? Colors.white : const Color(0xFFFAFCFD)),
          border: Border(
            right: BorderSide(
                color: fmt.borderColor ?? const Color(0xFFE7EDF3),
                width: fmt.borderColor == null ? 0.8 : 1.4),
            top: fmt.borderColor == null
                ? BorderSide.none
                : BorderSide(color: fmt.borderColor!, width: 1.0),
            bottom: BorderSide(
              color: fmt.borderColor ?? const Color(0xFFD7E1E9),
              width: fmt.borderColor == null ? 0.8 : 1.0,
            ),
          ),
        ),
        child: child,
      );
    }

    Widget deleteCell(Map<String, dynamic> row, int index) {
      final key = _remoteRowHighlightKey(row, index);
      return Container(
        width: 54,
        height: 46,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
            border: Border(
          right: BorderSide(color: Color(0xFFE7EDF3), width: 0.8),
          bottom: BorderSide(color: Color(0xFFD7E1E9), width: 0.8),
        )),
        child: StatefulBuilder(
          builder: (context, setLocalState) {
            final selected = _selectedDeleteRowKeys.contains(key);
            return Checkbox(
              value: selected,
              onChanged: (v) {
                _toggleDeleteSelection(row, index, v);
                setLocalState(() {});
              },
            );
          },
        ),
      );
    }

    Widget editCell(Map<String, dynamic> row) {
      final allowed = canUpdate && _workflowStateAllows(row, 'update');
      return Container(
        width: 72,
        height: 46,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
            border: Border(
          right: BorderSide(color: Color(0xFFE7EDF3), width: 0.8),
          bottom: BorderSide(color: Color(0xFFD7E1E9), width: 0.8),
        )),
        child: IconButton(
          tooltip: allowed ? 'Editar registro' : 'Actualización no permitida',
          icon: Icon(Icons.edit,
              size: 18, color: allowed ? const Color(0xFF176B87) : Colors.grey),
          onPressed: allowed ? () => _editRemoteRecord(row) : null,
          splashRadius: 18,
        ),
      );
    }

    Widget headerRow() {
      return Row(
        children: [
          if (_canSelectRows) deleteHeader(),
          if (canUpdate)
            actionHeader(
                width: 72,
                child: const Text('Editar',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5))),
          ...allColumns.map((c) => headerCell(c, _tableColumnWidth(c))),
        ],
      );
    }

    Widget dataRow(int index) {
      final r = visibleRows[index];
      final rowKey = _remoteRowHighlightKey(r, index);
      final highlighted = _highlightedRemoteRowKeys.contains(rowKey);
      return RepaintBoundary(
        child: Container(
          color: highlighted ? const Color(0xFFE8F4F8) : Colors.white,
          child: InkWell(
            onTap:
                _hasEmbeddedErpDetail ? () => _showEmbeddedErpDetail(r) : null,
            child: Row(
              children: [
                if (_canSelectRows) deleteCell(r, index),
                if (canUpdate) editCell(r),
                ...allColumns.map((c) => rowCell(r, index, c)),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final actionWidth =
            (_canSelectRows ? 54.0 : 0.0) + (canUpdate ? 72.0 : 0.0);
        final pinnedWidth =
            pinned.fold<double>(0.0, (sum, c) => sum + _tableColumnWidth(c));
        final fixedRawWidth = actionWidth + pinnedWidth;
        final scrollWidth = math.max(
          constraints.maxWidth + 420.0,
          unpinned.fold<double>(0.0, (sum, c) => sum + _tableColumnWidth(c)),
        );

        if (pinned.isNotEmpty) {
          Widget fixedHeaderRow() => Row(
                children: [
                  if (_canSelectRows) deleteHeader(),
                  if (canUpdate)
                    actionHeader(
                        width: 72,
                        child: const Text('Editar',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5))),
                  ...pinned.map((c) => headerCell(c, _tableColumnWidth(c))),
                ],
              );

          Widget fixedDataRow(int index) {
            final r = visibleRows[index];
            final rowKey = _remoteRowHighlightKey(r, index);
            final highlighted = _highlightedRemoteRowKeys.contains(rowKey);
            return RepaintBoundary(
              child: Container(
                color: highlighted ? const Color(0xFFE8F4F8) : Colors.white,
                child: InkWell(
                  onTap: _hasEmbeddedErpDetail
                      ? () => _showEmbeddedErpDetail(r)
                      : null,
                  child: Row(
                    children: [
                      if (_canSelectRows) deleteCell(r, index),
                      if (canUpdate) editCell(r),
                      ...pinned.map((c) => rowCell(r, index, c)),
                    ],
                  ),
                ),
              ),
            );
          }

          Widget scrollHeaderRow() => Row(
              children: unpinned
                  .map((c) => headerCell(c, _tableColumnWidth(c)))
                  .toList());

          Widget scrollDataRow(int index) {
            final r = visibleRows[index];
            final rowKey = _remoteRowHighlightKey(r, index);
            final highlighted = _highlightedRemoteRowKeys.contains(rowKey);
            return RepaintBoundary(
              child: Container(
                color: highlighted ? const Color(0xFFE8F4F8) : Colors.white,
                child: InkWell(
                  onTap: _hasEmbeddedErpDetail
                      ? () => _showEmbeddedErpDetail(r)
                      : null,
                  child: Row(
                      children:
                          unpinned.map((c) => rowCell(r, index, c)).toList()),
                ),
              ),
            );
          }

          final fixedWidth = math.min(
              fixedRawWidth, math.max(160.0, constraints.maxWidth - 180.0));
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: fixedWidth,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  primary: false,
                  child: SizedBox(
                    width: fixedRawWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RepaintBoundary(child: fixedHeaderRow()),
                        Expanded(
                          child: ListView.builder(
                            controller: _fixedVerticalTableController,
                            primary: false,
                            itemExtent: _virtualRowHeight,
                            itemCount: visibleRows.length,
                            cacheExtent: _virtualCacheExtent,
                            addAutomaticKeepAlives: false,
                            addSemanticIndexes: false,
                            itemBuilder: (context, index) =>
                                fixedDataRow(index),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: RawScrollbar(
                  controller: _verticalTableController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  interactive: true,
                  thickness: 12,
                  radius: const Radius.circular(10),
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.vertical,
                  child: RawScrollbar(
                    controller: _horizontalTableController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    interactive: true,
                    thickness: 12,
                    radius: const Radius.circular(10),
                    notificationPredicate: (notification) =>
                        notification.metrics.axis == Axis.horizontal,
                    child: SingleChildScrollView(
                      controller: _horizontalTableController,
                      scrollDirection: Axis.horizontal,
                      primary: false,
                      child: SizedBox(
                        width: scrollWidth,
                        height: constraints.maxHeight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RepaintBoundary(child: scrollHeaderRow()),
                            Expanded(
                              child: ListView.builder(
                                controller: _verticalTableController,
                                primary: false,
                                itemExtent: _virtualRowHeight,
                                itemCount: visibleRows.length,
                                cacheExtent: _virtualCacheExtent,
                                addAutomaticKeepAlives: false,
                                addSemanticIndexes: false,
                                itemBuilder: (context, index) =>
                                    scrollDataRow(index),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final tableWidth = math.max(
          constraints.maxWidth + 420.0,
          actionWidth +
              allColumns.fold<double>(
                  0.0, (sum, c) => sum + _tableColumnWidth(c)),
        );

        // El scrollbar vertical queda fuera del scroll horizontal para que se vea
        // siempre en el borde derecho de la vista, no recién al llegar a la última columna.
        return RawScrollbar(
          controller: _verticalTableController,
          thumbVisibility: true,
          trackVisibility: true,
          interactive: true,
          thickness: 12,
          radius: const Radius.circular(10),
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.vertical,
          child: RawScrollbar(
            controller: _horizontalTableController,
            thumbVisibility: true,
            trackVisibility: true,
            interactive: true,
            thickness: 12,
            radius: const Radius.circular(10),
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _horizontalTableController,
              scrollDirection: Axis.horizontal,
              primary: false,
              child: SizedBox(
                width: tableWidth,
                height: constraints.maxHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RepaintBoundary(child: headerRow()),
                    Expanded(
                      child: ListView.builder(
                        controller: _verticalTableController,
                        primary: false,
                        itemExtent: _virtualRowHeight,
                        itemCount: visibleRows.length,
                        cacheExtent: _virtualCacheExtent,
                        addAutomaticKeepAlives: false,
                        addSemanticIndexes: false,
                        itemBuilder: (context, index) => dataRow(index),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _goToPage(int page) async {
    if (page < 0) return;
    setState(() => _currentPage = page);
    await _load();
  }

  Widget _paginationControls(int shownRows) {
    final total = _knownTotalRows;
    final rangeStart = shownRows == 0 ? 0 : (_currentPage * _pageSize) + 1;
    final rangeEnd =
        shownRows == 0 ? 0 : (_currentPage * _pageSize) + shownRows;
    final rowsLabel = total != null && total > 0
        ? 'Mostrando $rangeStart-$rangeEnd de $total filas'
        : 'Mostrando $shownRows filas';
    return Row(
      children: [
        Expanded(
          child: Text(
            tableName == null
                ? 'Vista no configurada'
                : '${_tableVisualName()} · $rowsLabel',
            style: const TextStyle(color: Color(0xFF60758A), fontSize: 12),
          ),
        ),
        TextButton.icon(
          onPressed: loading || _currentPage == 0
              ? null
              : () => _goToPage(_currentPage - 1),
          icon: const Icon(Icons.chevron_left, size: 18),
          label: const Text('Anterior'),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE1E8EF)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('${_currentPage + 1}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        TextButton.icon(
          onPressed: loading || !_hasNextPage
              ? null
              : () => _goToPage(_currentPage + 1),
          icon: const Icon(Icons.chevron_right, size: 18),
          label: const Text('Siguiente'),
        ),
      ],
    );
  }

  String _cleanHeaderValue(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.toUpperCase() == 'NULL') return '';
    return text;
  }

  String _normHeaderTable(dynamic value) {
    return (value?.toString().trim() ?? '').toUpperCase();
  }

  bool _hasAnyHeaderValue(Map<String, dynamic> meta) {
    return ['titulo1', 'titulo2', 'codigo1', 'codigo2']
        .any((key) => _cleanHeaderValue(meta[key]).isNotEmpty);
  }

  Map<String, dynamic> _formatHeaderMeta() {
    final table = tableName;
    final tableKey = _normHeaderTable(table);
    final rows = table == null
        ? <Map<String, dynamic>>[]
        : (matrixRowsByTable[table] ?? <Map<String, dynamic>>[]);
    final fields = <Map<String, dynamic>>[
      ...allLocalFormFields
          .where((f) => _normHeaderTable(f['tabla_destino']) == tableKey),
      ...rows,
    ];
    final tableDefinition =
        internalTableRows.cast<Map<String, dynamic>?>().firstWhere(
              (row) => _normHeaderTable(row?['tabla_destino']) == tableKey,
              orElse: () => null,
            );

    String firstNonEmpty(String key) {
      for (final row in fields) {
        final value = _cleanHeaderValue(row[key]);
        if (value.isNotEmpty) return value;
      }
      final fromFormat = _cleanHeaderValue(widget.format[key]);
      if (fromFormat.isNotEmpty) return fromFormat;
      return '';
    }

    dynamic firstValue(String key) {
      final tableValue = tableDefinition?[key];
      if (tableValue != null && tableValue.toString().trim().isNotEmpty) {
        return tableValue;
      }
      for (final row in fields) {
        final value = row[key];
        if (value != null && value.toString().trim().isNotEmpty) return value;
      }
      return widget.format[key];
    }

    return {
      'titulo1': firstNonEmpty('titulo1'),
      'titulo2': firstNonEmpty('titulo2'),
      'codigo1': firstNonEmpty('codigo1'),
      'codigo2': firstNonEmpty('codigo2'),
      'auditable': firstValue('auditable') ?? true,
      'icono': firstValue('icono') ?? 'assignment',
      'imagen_encabezado': firstValue('imagen_encabezado'),
      for (final key in [
        'titulo1_alineacion',
        'titulo1_tamanio_letra',
        'titulo1_color',
        'titulo1_padding',
        'titulo2_alineacion',
        'titulo2_tamanio_letra',
        'titulo2_color',
        'titulo2_padding',
      ])
        key: firstValue(key),
    };
  }

  String _headerLineBreaks(String value) {
    return value.replaceAll('%%', '\n').trim();
  }

  Future<void> _showHeaderCodeDialog(String code) async {
    final cleanCode = _headerLineBreaks(code);
    if (cleanCode.isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 260, vertical: 180),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, minWidth: 360),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Código del formato',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF147A6E)),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4FAF8),
                      border:
                          Border.all(color: const Color(0xFF147A6E), width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      cleanCode,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.28,
                          color: Color(0xFF17324D)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cerrar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Alignment _headerAlignment(dynamic raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    if (value == 'right' || value == 'derecha') return Alignment.centerRight;
    if (value == 'left' || value == 'izquierda') return Alignment.centerLeft;
    return Alignment.center;
  }

  TextAlign _headerTextAlign(dynamic raw) {
    final alignment = _headerAlignment(raw);
    if (alignment == Alignment.centerRight) return TextAlign.right;
    if (alignment == Alignment.centerLeft) return TextAlign.left;
    return TextAlign.center;
  }

  EdgeInsets _headerPadding(dynamic raw) {
    final values = raw
        ?.toString()
        .split(RegExp(r'[,; ]+'))
        .map((value) => double.tryParse(value.trim()))
        .whereType<double>()
        .toList();
    if (values == null || values.isEmpty) {
      return const EdgeInsets.symmetric(horizontal: 8, vertical: 3);
    }
    if (values.length == 1) return EdgeInsets.all(values.first);
    if (values.length == 2) {
      return EdgeInsets.symmetric(horizontal: values[0], vertical: values[1]);
    }
    if (values.length >= 4) {
      return EdgeInsets.fromLTRB(values[0], values[1], values[2], values[3]);
    }
    return const EdgeInsets.symmetric(horizontal: 8, vertical: 3);
  }

  Widget _formatDocumentHeader(Map<String, dynamic> meta) {
    final selectedTitle = _headerLineBreaks(meta['titulo1'] ?? '');
    final selectedTitle2 = _headerLineBreaks(meta['titulo2'] ?? '');
    final selectedCode = _headerLineBreaks(meta['codigo1'] ?? '');
    final selectedCode2 = _headerLineBreaks(meta['codigo2'] ?? '');
    final title1Color =
        _parseTableMatrixColor(meta['titulo1_color']) ?? Colors.white;
    final title2Color =
        _parseTableMatrixColor(meta['titulo2_color']) ?? Colors.white;
    final title1Size =
        double.tryParse(meta['titulo1_tamanio_letra']?.toString() ?? '') ??
            15.5;
    final title2Size =
        double.tryParse(meta['titulo2_tamanio_letra']?.toString() ?? '') ??
            12.5;

    return Container(
      height: 104,
      decoration: BoxDecoration(
        color: _appgtHeaderColor,
        border: Border.all(color: _appgtHeaderBorderColor, width: 1.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 92,
            alignment: Alignment.center,
            color: _appgtHeaderColor,
            padding: const EdgeInsets.all(3),
            child: ClipOval(
              child: Image.asset(
                'assets/images/logo_app.png',
                width: 56,
                height: 56,
                cacheWidth: 168,
                cacheHeight: 168,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 8,
            child: Container(
              alignment: _headerAlignment(meta['titulo1_alineacion']),
              decoration: BoxDecoration(
                color: _appgtHeaderColor,
                border: Border.all(color: _appgtHeaderBorderColor, width: 1.2),
              ),
              padding: _headerPadding(meta['titulo1_padding']),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    selectedTitle,
                    textAlign: _headerTextAlign(meta['titulo1_alineacion']),
                    maxLines: selectedTitle2.isEmpty ? 4 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: title1Color,
                        fontWeight: FontWeight.w800,
                        fontSize: title1Size,
                        height: 1.12),
                  ),
                  if (selectedTitle2.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Padding(
                      padding: _headerPadding(meta['titulo2_padding']),
                      child: Text(
                        selectedTitle2,
                        textAlign: _headerTextAlign(meta['titulo2_alineacion']),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: title2Color,
                          fontWeight: FontWeight.w700,
                          fontSize: title2Size,
                          height: 1.08,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: InkWell(
              onTap: selectedCode.isEmpty
                  ? null
                  : () => _showHeaderCodeDialog(selectedCode),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _appgtHeaderColor,
                  border:
                      Border.all(color: _appgtHeaderBorderColor, width: 1.2),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                child: Text(
                  [selectedCode, selectedCode2]
                      .where((value) => value.isNotEmpty)
                      .join('\n'),
                  textAlign: TextAlign.center,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                      height: 1.08),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactFormatDocumentHeader(Map<String, dynamic> meta) {
    final configuredTitle = _headerLineBreaks(meta['titulo1'] ?? '');
    final selectedTitle = configuredTitle.isEmpty
        ? (widget.format['nombre']?.toString() ?? 'Formato')
        : configuredTitle;
    final selectedTitle2 = _headerLineBreaks(meta['titulo2'] ?? '');
    final selectedCode = _headerLineBreaks(meta['codigo1'] ?? '');
    final selectedCode2 = _headerLineBreaks(meta['codigo2'] ?? '');
    final title1Color =
        _parseTableMatrixColor(meta['titulo1_color']) ?? Colors.white;
    final title2Color =
        _parseTableMatrixColor(meta['titulo2_color']) ?? Colors.white;
    final title1Size =
        (double.tryParse(meta['titulo1_tamanio_letra']?.toString() ?? '') ??
                15.5)
            .clamp(11.0, 17.0);
    final title2Size =
        (double.tryParse(meta['titulo2_tamanio_letra']?.toString() ?? '') ??
                12.5)
            .clamp(9.0, 13.0);
    final auditable = _boolValue(meta['auditable']);

    Widget visual() {
      final image = meta['imagen_encabezado']?.toString().trim() ?? '';
      if (image.startsWith('data:image/') && image.contains(',')) {
        try {
          return Image.memory(
            base64Decode(image.split(',').last),
            width: 43,
            height: 43,
            fit: BoxFit.cover,
          );
        } catch (_) {}
      }
      if (image.startsWith('http://') || image.startsWith('https://')) {
        return Image.network(
          image,
          width: 43,
          height: 43,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            configurationIconForName(meta['icono']?.toString()),
            size: 34,
            color: Colors.white,
          ),
        );
      }
      return Icon(
        configurationIconForName(meta['icono']?.toString()),
        size: 34,
        color: Colors.white,
      );
    }

    Widget visualPanel() => Container(
          width: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _appgtHeaderColor,
            border: Border.all(color: _appgtHeaderBorderColor, width: 1),
          ),
          padding: const EdgeInsets.all(5),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: visual(),
          ),
        );

    Widget titlePanel() => Container(
          alignment: _headerAlignment(meta['titulo1_alineacion']),
          decoration: BoxDecoration(
            color: _appgtHeaderColor,
            border: Border.all(color: _appgtHeaderBorderColor, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                selectedTitle,
                textAlign: _headerTextAlign(meta['titulo1_alineacion']),
                maxLines: selectedTitle2.isEmpty ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: title1Color,
                  fontWeight: FontWeight.w800,
                  fontSize: title1Size,
                  height: 1.05,
                ),
              ),
              if (selectedTitle2.isNotEmpty)
                Text(
                  selectedTitle2,
                  textAlign: _headerTextAlign(meta['titulo2_alineacion']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: title2Color,
                    fontWeight: FontWeight.w700,
                    fontSize: title2Size,
                    height: 1.02,
                  ),
                ),
            ],
          ),
        );

    Widget codePanel() => InkWell(
          onTap: selectedCode.isEmpty
              ? null
              : () => _showHeaderCodeDialog(selectedCode),
          child: Container(
            width: 150,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _appgtHeaderColor,
              border: Border.all(color: _appgtHeaderBorderColor, width: 1),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            child: Text(
              [selectedCode, selectedCode2]
                  .where((value) => value.isNotEmpty)
                  .join('\n'),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 9.5,
                height: 1.02,
              ),
            ),
          ),
        );

    return Container(
      height: 68,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _appgtHeaderColor,
        border: Border.all(color: _appgtHeaderBorderColor, width: 1.2),
      ),
      child: auditable
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                visualPanel(),
                const SizedBox(width: 4),
                Expanded(child: titlePanel()),
                const SizedBox(width: 4),
                codePanel(),
              ],
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 66),
                  child: titlePanel(),
                ),
                Align(alignment: Alignment.centerLeft, child: visualPanel()),
              ],
            ),
    );
  }

  Widget _desktopBody() {
    final headerMeta = _formatHeaderMeta();

    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE1E8EF), width: 1.0),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _compactFormatDocumentHeader(headerMeta),
          const SizedBox(height: 10),
          ValueListenableBuilder<int>(
            valueListenable: _filterControlsVersion,
            builder: (context, _, __) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: Tooltip(
                          message: 'Limpiar filtros',
                          child: OutlinedButton(
                            onPressed:
                                _hasAnyActiveFilters ? _clearAllFilters : null,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF147A6E),
                              backgroundColor: const Color(0xFFF2FAF8),
                              side: const BorderSide(color: Color(0xFFB7DDD6)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: EdgeInsets.zero,
                            ),
                            child: const Icon(Icons.cleaning_services_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ..._visibleFilterFields.map(_fieldFilterControl),
                      ..._periodFilterKeys.map(_periodFilterControl),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (internalTableRows.length > 1) ...[
                  SizedBox(
                    width: 260,
                    height: 44,
                    child: DropdownButtonFormField<String>(
                      value: selectedTableName,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Tabla del formato',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: internalTableRows.map((row) {
                        final table = _clean(row['tabla_destino']) ?? '';
                        final label = _clean(row['nombre_tabla']) ??
                            _clean(row['nombre']) ??
                            'Vista ${internalTableRows.indexOf(row) + 1}';
                        return DropdownMenuItem<String>(
                            value: table,
                            child:
                                Text(label, overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: loading
                          ? null
                          : (value) async {
                              if (value == null || value == selectedTableName)
                                return;
                              setState(() {
                                selectedTableName = value;
                                _currentPage = 0;
                                _pinnedColumns.clear();
                                _columnFilters.clear();
                                _sortColumn = null;
                                _invalidateFilteredCache();
                              });
                              await _load();
                            },
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: displayColumns.isEmpty || loading
                        ? null
                        : _showAddFilterDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Filtro'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF147A6E),
                      backgroundColor: const Color(0xFFF2FAF8),
                      side: const BorderSide(color: Color(0xFF147A6E)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: OutlinedButton(
                    onPressed: displayColumns.isEmpty
                        ? null
                        : () => _showPinColumnsDialog(
                            _visibleWindowsColumns(displayColumns)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF147A6E),
                      side: const BorderSide(color: Color(0xFF147A6E)),
                      backgroundColor: const Color(0xFFF2FAF8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: EdgeInsets.zero,
                    ),
                    child: Icon(_pinnedColumns.isEmpty
                        ? Icons.push_pin_outlined
                        : Icons.push_pin),
                  ),
                ),
                const SizedBox(width: 10),
                if (canDelete) ...[
                  ValueListenableBuilder<int>(
                    valueListenable: _deleteSelectionVersion,
                    builder: (context, _, __) {
                      final hasSelection = _selectedDeleteRows.isNotEmpty;
                      return SizedBox(
                        width: 44,
                        height: 44,
                        child: OutlinedButton(
                          onPressed: hasSelection ? _deleteSelectedRows : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                            side: BorderSide(
                                color: hasSelection
                                    ? Colors.red.shade700
                                    : Colors.grey.shade300),
                            backgroundColor: hasSelection
                                ? const Color(0xFFFFF4F4)
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Icon(Icons.delete_outline),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                ],
                if (_approvalsEnabled) ...[
                  _workflowToolbarMenu(),
                  const SizedBox(width: 10),
                ],
                if (_isTareoTable && canApprove) ...[
                  ValueListenableBuilder<int>(
                    valueListenable: _deleteSelectionVersion,
                    builder: (context, _, __) => _humanWorkflowToolbarButton(
                      onPressed: _selectedDeleteRows.isEmpty
                          ? null
                          : _authorizeSelectedOvertime,
                      icon: Icons.more_time_outlined,
                      tooltip: 'Autorizar horas extra seleccionadas',
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (_isPayrollPeriodTable) ...[
                  ValueListenableBuilder<int>(
                    valueListenable: _deleteSelectionVersion,
                    builder: (context, _, __) => _humanWorkflowToolbarButton(
                      onPressed: _selectedDeleteRows.length == 1
                          ? _runPayrollLifecycle
                          : null,
                      icon: Icons.account_tree_outlined,
                      tooltip: 'Calcular, revisar, aprobar, cerrar o reabrir',
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (_isPayrollSlipTable) ...[
                  ValueListenableBuilder<int>(
                    valueListenable: _deleteSelectionVersion,
                    builder: (context, _, __) => _humanWorkflowToolbarButton(
                      onPressed: _selectedDeleteRows.length == 1
                          ? () => _openOrGeneratePayrollSlip(
                                _selectedDeleteRows.values.single,
                              )
                          : null,
                      icon: Icons.picture_as_pdf_outlined,
                      tooltip: 'Generar o ver boleta PDF',
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (_isHumanResourcesApprovalTable) ...[
                  ValueListenableBuilder<int>(
                    valueListenable: _deleteSelectionVersion,
                    builder: (context, _, __) => _humanWorkflowToolbarButton(
                      onPressed: _selectedDeleteRows.length == 1
                          ? () => _openOrGenerateHumanResourcesDocument(
                                _selectedDeleteRows.values.single,
                              )
                          : null,
                      icon: Icons.picture_as_pdf_outlined,
                      tooltip: 'Generar o ver documento PDF',
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                // Mantener visibles Importar y Exportar en la barra.
                // La habilitación real sigue controlada dentro de cada botón
                // por canImport/canExport, loading, offline, error y registros.
                _importButton(),
                const SizedBox(width: 10),
                _exportButton(),
                if (_isPersonalPlanillaTable) ...[
                  const SizedBox(width: 10),
                  _photocheckButton(),
                ],
                const SizedBox(width: 10),
                if (canInsert)
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: OutlinedButton(
                      onPressed: _newRecord,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF147A6E),
                        backgroundColor: const Color(0xFFF2FAF8),
                        side: const BorderSide(color: Color(0xFFB7DDD6)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Icon(Icons.add),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE1E8EF), width: 1.0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: loading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(_loadingMessage,
                              style: const TextStyle(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )
                  : offline
                      ? _emptyMessage('Sin conexión a Internet')
                      : error != null
                          ? Center(
                              child: Text(error!,
                                  style:
                                      const TextStyle(color: Colors.black87)))
                          : ValueListenableBuilder<int>(
                              valueListenable: _tableRenderVersion,
                              builder: (context, _, __) {
                                final currentRows = filteredRecords;
                                return RepaintBoundary(
                                    child: _recordsTable(currentRows));
                              },
                            ),
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<int>(
            valueListenable: _tableRenderVersion,
            builder: (context, _, __) =>
                _paginationControls(filteredRecords.length),
          ),
        ],
      ),
    );
  }

  Widget _mobileBody() {
    List<String> mobileColumns() {
      final rawColumns = displayColumns.isNotEmpty
          ? displayColumns
          : _columnsFromRows(records.isNotEmpty ? records : filteredRecords);
      return _matrixColumnsForTable(
        tableName ?? widget.format['tabla_destino']?.toString() ?? '',
        rawColumns,
      );
    }

    List<Map<String, dynamic>> mobileRows(List<String> columns) {
      final query = _norm(_mobileSearchController.text);
      if (query.isEmpty) return filteredRecords;
      return filteredRecords.where((row) {
        return columns.any((column) {
          final value = _displayCellValue(_valueByColumn(row, column));
          return _norm(value).contains(query);
        });
      }).toList(growable: false);
    }

    Widget mobileCell(
      BuildContext context,
      Map<String, dynamic> row,
      String column,
    ) {
      final value = _valueByColumn(row, column);
      final text = _displayCellValue(value);
      final format = _tableCellFormat(column, row);
      if (_isHumanResourcesDocumentColumn(column)) {
        return Align(
          alignment: Alignment.centerLeft,
          child: _humanResourcesStoredDocumentButton(row, column),
        );
      }
      if (_isErpDocumentTable && _norm(column) == 'PDF_URL') {
        return Align(
          alignment: Alignment.centerLeft,
          child: _erpPdfCell(row),
        );
      }
      if (_isPayrollSlipTable && _norm(column) == 'PDF_URL') {
        return Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: text.isEmpty
                ? 'Generar boleta PDF'
                : 'Ver o descargar boleta PDF',
            child: IconButton(
              icon: Icon(
                text.isEmpty
                    ? Icons.picture_as_pdf_outlined
                    : Icons.picture_as_pdf,
                color: const Color(0xFFC62828),
              ),
              onPressed: () => _openOrGeneratePayrollSlip(row),
            ),
          ),
        );
      }
      if (_isMediaColumn(column) && _looksLikeUrl(text)) {
        return Align(
          alignment: Alignment.centerLeft,
          child: _mediaCell(column, text),
        );
      }
      return Container(
        padding: format.bgColor == null
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: format.bgColor,
          border: format.borderColor == null
              ? null
              : Border.all(color: format.borderColor!),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          text.isEmpty ? '—' : text,
          style: TextStyle(
            color: format.textColor ?? const Color(0xFF17324D),
            fontSize: format.fontSize ?? 13,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: loading
              ? Center(child: Text(_loadingMessage))
              : offline
                  ? _emptyMessage('Sin conexión a Internet')
                  : error != null
                      ? Center(
                          child: Text(error!,
                              style: const TextStyle(color: Colors.black87)))
                      : ValueListenableBuilder<int>(
                          valueListenable: _tableRenderVersion,
                          builder: (context, _, __) {
                            final columns = mobileColumns();
                            final rows = mobileRows(columns);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${widget.format['nombre'] ?? 'Registros'}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF17324D),
                                              fontSize: 19,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          Text(
                                            '${tableName == null ? 'Vista no configurada' : _tableVisualName()} · ${rows.length} registro(s)',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF60758A),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Actualizar tabla',
                                      onPressed: _load,
                                      icon: const Icon(Icons.refresh,
                                          color: Color(0xFF176B87)),
                                    ),
                                    _mobileToolsMenu(),
                                    if (canDelete)
                                      ValueListenableBuilder<int>(
                                        valueListenable:
                                            _deleteSelectionVersion,
                                        builder: (context, _, __) => IconButton(
                                          tooltip: 'Eliminar seleccionados',
                                          onPressed: _selectedDeleteRows.isEmpty
                                              ? null
                                              : _deleteSelectedRows,
                                          icon: Badge(
                                            isLabelVisible:
                                                _selectedDeleteRows.isNotEmpty,
                                            label: Text(
                                                '${_selectedDeleteRows.length}'),
                                            child: const Icon(
                                                Icons.delete_outline),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 9),
                                TextField(
                                  controller: _mobileSearchController,
                                  onChanged: (_) => _notifyTableRenderChanged(),
                                  textInputAction: TextInputAction.search,
                                  decoration: InputDecoration(
                                    hintText: 'Buscar en esta tabla',
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: _mobileSearchController
                                            .text.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Limpiar búsqueda',
                                            onPressed: () {
                                              _mobileSearchController.clear();
                                              _notifyTableRenderChanged();
                                            },
                                            icon: const Icon(Icons.close),
                                          ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    isDense: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFDCE6EC)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFDCE6EC)),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Expanded(
                                  child: columns.isEmpty
                                      ? _emptyMessage(
                                          'No hay columnas visibles')
                                      : ValueListenableBuilder<int>(
                                          valueListenable:
                                              _deleteSelectionVersion,
                                          builder: (context, _, __) =>
                                              MobileRecordsList(
                                            records: rows,
                                            columns: columns,
                                            layout: widget
                                                    .format['layout_registros']
                                                    ?.toString() ??
                                                'TABLA',
                                            rowNumberOffset:
                                                _currentPage * _pageSize,
                                            labelFor: _tableHeaderLabel,
                                            textFor: (row, column) =>
                                                _displayCellValue(
                                              _valueByColumn(row, column),
                                            ),
                                            cellBuilder: mobileCell,
                                            onEdit: canUpdate
                                                ? _editRemoteRecord
                                                : null,
                                            onOpen: _hasEmbeddedErpDetail
                                                ? _showEmbeddedErpDetail
                                                : null,
                                            selectionEnabled: _canSelectRows,
                                            isSelected: (row, index) =>
                                                _selectedDeleteRowKeys.contains(
                                                    _remoteRowHighlightKey(
                                                        row, index)),
                                            onSelected:
                                                (row, index, selected) =>
                                                    _toggleDeleteSelection(
                                                        row, index, selected),
                                          ),
                                        ),
                                ),
                                _mobilePaginationControls(rows.length),
                              ],
                            );
                          },
                        ),
        ),
      ),
      floatingActionButton: canInsert
          ? FloatingActionButton.extended(
              onPressed: _newRecord,
              tooltip: 'Nuevo registro',
              icon: const Icon(Icons.add),
              label: const Text('Nuevo'),
            )
          : null,
    );
  }

  Widget _mobilePaginationControls(int shownRows) {
    return Container(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Página ${_currentPage + 1} · $shownRows registro(s)',
              style: const TextStyle(color: Color(0xFF60758A), fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: 'Página anterior',
            onPressed: loading || _currentPage == 0
                ? null
                : () => _goToPage(_currentPage - 1),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Página siguiente',
            onPressed: loading || !_hasNextPage
                ? null
                : () => _goToPage(_currentPage + 1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mobileMode) return _mobileBody();
    if (widget.embedded) {
      return _desktopBody();
    }

    return Scaffold(
      appBar: AppBar(
          title: Text('${widget.format['nombre'] ?? widget.format['id']}')),
      body: _desktopBody(),
    );
  }
}
