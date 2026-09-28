import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide ScaffoldMessenger;

import '../../core/services/sync_service.dart';
import '../../core/widgets/zumac_feature_header.dart';
import '../../core/widgets/zumac_scaffold_messenger.dart';
import 'metrics_layout.dart';
import 'metrics_repository.dart';

const _metricsNavy = Color(0xFF142F49);
const _metricsTeal = Color(0xFF14738A);
const _metricsCanvas = Color(0xFFF3F7FA);
const _metricsMuted = Color(0xFF63798B);
const _metricsPalette = <Color>[
  Color(0xFF14738A),
  Color(0xFFE08A35),
  Color(0xFF5A6CCB),
  Color(0xFF2F9D75),
  Color(0xFFC9536A),
  Color(0xFF8659B5),
];

enum _MetricGeometrySide { left, right, top, bottom }

double metricsToolbarTitleMaxWidth(double availableWidth) =>
    math.max(90, availableWidth - 910);

double metricsToolbarTitleFontSize(double availableWidth) =>
    availableWidth < 1050 ? 14 : 17;

class MetricsDashboardItem {
  const MetricsDashboardItem({required this.id, required this.name});

  final String id;
  final String name;
}

/// Puente entre Metrics y la barra superior del workspace. La barra pertenece
/// a ModulesPage, mientras que selección, permisos y persistencia pertenecen
/// exclusivamente a MetricsPage.
class MetricsToolbarController extends ChangeNotifier {
  Object? _owner;
  String dashboardTitle = '';
  String dashboardTitleFont = 'Roboto';
  Color dashboardTitleColor = _metricsNavy;
  String? selectedDashboardId;
  List<MetricsDashboardItem> dashboards = const [];
  bool canManage = false;
  bool busy = false;
  Future<void> Function(String id)? _selectDashboard;
  Future<void> Function(int oldIndex, int newIndex)? _reorderDashboards;
  Future<void> Function()? _createDashboard;
  Future<void> Function()? _createWidget;
  Future<void> Function()? _openFilters;
  Future<void> Function()? _editDashboard;
  Future<void> Function()? _manageRelations;
  Future<void> Function()? _deleteDashboard;

  bool get ready => dashboards.isNotEmpty && selectedDashboardId != null;

  void attach({
    required Object owner,
    required String title,
    required String titleFont,
    required Color titleColor,
    required String? selectedId,
    required List<MetricsDashboardItem> items,
    required bool allowManagement,
    required bool operationInProgress,
    required Future<void> Function(String id) onSelectDashboard,
    required Future<void> Function(int oldIndex, int newIndex)
        onReorderDashboards,
    required Future<void> Function() onCreateDashboard,
    required Future<void> Function() onCreateWidget,
    required Future<void> Function() onOpenFilters,
    required Future<void> Function() onEditDashboard,
    required Future<void> Function() onManageRelations,
    required Future<void> Function() onDeleteDashboard,
  }) {
    final changed = _owner != owner ||
        dashboardTitle != title ||
        dashboardTitleFont != titleFont ||
        dashboardTitleColor != titleColor ||
        selectedDashboardId != selectedId ||
        !_sameDashboardItems(dashboards, items) ||
        canManage != allowManagement ||
        busy != operationInProgress;
    _owner = owner;
    dashboardTitle = title;
    dashboardTitleFont = titleFont;
    dashboardTitleColor = titleColor;
    selectedDashboardId = selectedId;
    dashboards = List<MetricsDashboardItem>.unmodifiable(items);
    canManage = allowManagement;
    busy = operationInProgress;
    _selectDashboard = onSelectDashboard;
    _reorderDashboards = onReorderDashboards;
    _createDashboard = onCreateDashboard;
    _createWidget = onCreateWidget;
    _openFilters = onOpenFilters;
    _editDashboard = onEditDashboard;
    _manageRelations = onManageRelations;
    _deleteDashboard = onDeleteDashboard;
    if (changed) notifyListeners();
  }

  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    dashboardTitle = '';
    selectedDashboardId = null;
    dashboards = const [];
    canManage = false;
    busy = false;
    _selectDashboard = null;
    _reorderDashboards = null;
    _createDashboard = null;
    _createWidget = null;
    _openFilters = null;
    _editDashboard = null;
    _manageRelations = null;
    _deleteDashboard = null;
    notifyListeners();
  }

  Future<void> selectDashboard(String id) async => _selectDashboard?.call(id);
  Future<void> reorderDashboards(int oldIndex, int newIndex) async =>
      _reorderDashboards?.call(oldIndex, newIndex);
  Future<void> createDashboard() async => _createDashboard?.call();
  Future<void> createWidget() async => _createWidget?.call();
  Future<void> openFilters() async => _openFilters?.call();
  Future<void> editDashboard() async => _editDashboard?.call();
  Future<void> manageRelations() async => _manageRelations?.call();
  Future<void> deleteDashboard() async => _deleteDashboard?.call();

  static bool _sameDashboardItems(
    List<MetricsDashboardItem> left,
    List<MetricsDashboardItem> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].id != right[index].id ||
          left[index].name != right[index].name) {
        return false;
      }
    }
    return true;
  }
}

class MetricsDashboardPickerDialog extends StatelessWidget {
  const MetricsDashboardPickerDialog({
    super.key,
    required this.controller,
  });

  final MetricsToolbarController controller;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.space_dashboard_outlined),
            SizedBox(width: 9),
            Text('Dashboards'),
          ],
        ),
        content: SizedBox(
          width: 430,
          height: 470,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              if (controller.dashboards.isEmpty) {
                return const Center(child: Text('No hay dashboards.'));
              }
              return ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: controller.dashboards.length,
                onReorder: controller.busy || !controller.canManage
                    ? (_, __) {}
                    : (oldIndex, newIndex) => unawaited(
                          controller.reorderDashboards(oldIndex, newIndex),
                        ),
                itemBuilder: (_, index) {
                  final dashboard = controller.dashboards[index];
                  final selected =
                      dashboard.id == controller.selectedDashboardId;
                  return Card(
                    key: ValueKey('metrics-dashboard-${dashboard.id}'),
                    elevation: 0,
                    color: selected
                        ? _metricsTeal.withValues(alpha: .10)
                        : Colors.white,
                    child: ListTile(
                      leading: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.space_dashboard_outlined,
                        color: selected ? _metricsTeal : _metricsMuted,
                      ),
                      title: Text(
                        dashboard.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      trailing: controller.canManage
                          ? ReorderableDragStartListener(
                              index: index,
                              child: const Tooltip(
                                message: 'Arrastra para reposicionar',
                                child: Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(Icons.drag_indicator_rounded),
                                ),
                              ),
                            )
                          : null,
                      onTap: () async {
                        await controller.selectDashboard(dashboard.id);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      );
}

/// Entorno de visualización configurable de Zumac.
///
/// A diferencia del módulo heredado Reportes, Metrics guarda dashboards,
/// gráficos y relaciones como metadatos por empresa. Ninguna tabla de negocio
/// está codificada dentro de esta pantalla.
class MetricsPage extends StatefulWidget {
  const MetricsPage({
    super.key,
    this.initialSourceTable,
    this.embedded = false,
    this.toolbarController,
  });

  final String? initialSourceTable;
  final bool embedded;
  final MetricsToolbarController? toolbarController;

  @override
  State<MetricsPage> createState() => _MetricsPageState();
}

class _MetricsPageState extends State<MetricsPage> {
  final _repository = MetricsRepository();
  final _sync = SyncService();
  Map<String, dynamic> _context = const {};
  List<Map<String, dynamic>> _dashboards = const [];
  List<Map<String, dynamic>> _widgets = const [];
  List<Map<String, dynamic>> _relations = const [];
  final Map<String, MetricDataset> _datasets = {};
  final Map<String, dynamic> _dashboardFilterValues = {};
  String? _dashboardId;
  bool _loading = true;
  bool _loadingData = false;
  bool _refreshingAll = false;
  bool _initialSourceResolved = false;
  Map<String, dynamic>? _editingWidget;
  int _editorRevision = 0;
  bool _filterEditorOpen = false;
  bool _addingDashboardFilter = false;
  bool _reorderingDashboards = false;
  int _layoutSaveOperations = 0;
  int _dashboardLoadRevision = 0;
  int _datasetLoadRevision = 0;
  String? _resizingWidgetId;
  String? _movingWidgetId;
  bool _approvalNoticeShown = false;
  double? _desktopCanvasReferenceWidth;
  final Map<String, Size> _liveWidgetSizes = {};
  final Map<String, Offset> _liveWidgetPositions = {};
  Offset? _geometryGestureOrigin;
  Offset? _geometryPointerPosition;
  Offset? _geometryPointerDownPosition;
  Timer? _geometryHoldTimer;
  int? _geometryPointerId;
  bool _geometryMoveMode = false;
  bool _geometryGestureChanged = false;
  String? _error;

  bool get _canManage => _context['puede_gestionar'] == true;
  bool get _requiresAdminApproval =>
      _context['rol']?.toString().toUpperCase() == 'GESTOR';
  bool get _enabled => _context['metrics_habilitado'] == true;
  List<Map<String, dynamic>> get _sources => _maps(_context['fuentes']);

  Map<String, dynamic>? get _selectedDashboard {
    for (final dashboard in _dashboards) {
      if ('${dashboard['id']}' == _dashboardId) return dashboard;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _geometryHoldTimer?.cancel();
    widget.toolbarController?.detach(this);
    super.dispose();
  }

  void _scheduleToolbarSync() {
    if (widget.toolbarController == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dashboard = _selectedDashboard;
      final config = _map(dashboard?['configuracion']);
      widget.toolbarController!.attach(
        owner: this,
        title: dashboard?['nombre']?.toString().trim() ?? '',
        titleFont:
            config['dashboard_title_font']?.toString().trim().isNotEmpty == true
                ? config['dashboard_title_font'].toString().trim()
                : 'Roboto',
        titleColor: _color(
          config['dashboard_title_color'],
          _metricsNavy,
        ),
        selectedId: _dashboardId,
        items: _dashboards
            .map((item) => MetricsDashboardItem(
                  id: '${item['id']}',
                  name: item['nombre']?.toString().trim().isNotEmpty == true
                      ? item['nombre'].toString().trim()
                      : 'Dashboard',
                ))
            .toList(growable: false),
        allowManagement: _canManage,
        operationInProgress:
            _reorderingDashboards || _loading || _layoutSaveOperations > 0,
        onSelectDashboard: _selectDashboard,
        onReorderDashboards: _reorderDashboards,
        onCreateDashboard: () => _editDashboard(),
        onCreateWidget: () => _editWidget(),
        onOpenFilters: () async => _openFilterPanel(),
        onEditDashboard: () => _editDashboard(_selectedDashboard),
        onManageRelations: _manageRelations,
        onDeleteDashboard: _deleteDashboard,
      );
    });
  }

  Future<void> _load({String? selectDashboard}) async {
    final requestRevision = ++_dashboardLoadRevision;
    ++_datasetLoadRevision;
    if (mounted) setState(() => _loading = true);
    try {
      final initial = await Future.wait<dynamic>([
        _repository.loadContext(),
        _repository.listDashboards(),
      ]);
      final contextData = initial[0] as Map<String, dynamic>;
      final dashboards = initial[1] as List<Map<String, dynamic>>;
      var selected = selectDashboard ?? _dashboardId;
      if (!_initialSourceResolved &&
          (widget.initialSourceTable ?? '').trim().isNotEmpty) {
        selected = await _repository
            .findDashboardForSource(widget.initialSourceTable!.trim());
        _initialSourceResolved = true;
      }
      if (selected == null ||
          !dashboards.any((row) => '${row['id']}' == selected)) {
        selected = dashboards.isEmpty ? null : '${dashboards.first['id']}';
      }
      List<Map<String, dynamic>> widgets = const [];
      List<Map<String, dynamic>> relations = const [];
      if (selected != null) {
        final values = await Future.wait([
          _repository.listWidgets(selected),
          _repository.listRelations(selected),
        ]);
        widgets = values[0];
        relations = values[1];
      }
      if (!mounted || requestRevision != _dashboardLoadRevision) return;
      setState(() {
        _context = contextData;
        _dashboards = dashboards;
        _dashboardId = selected;
        _widgets = widgets;
        _relations = relations;
        _datasets.clear();
        _liveWidgetSizes.clear();
        _liveWidgetPositions.clear();
        _error = null;
      });
      await _loadDatasets();
    } catch (error) {
      if (mounted && requestRevision == _dashboardLoadRevision) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted && requestRevision == _dashboardLoadRevision) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshAllData() async {
    if (_refreshingAll || _reorderingDashboards || _layoutSaveOperations > 0) {
      return;
    }
    setState(() => _refreshingAll = true);
    try {
      await _sync.downloadAllForOffline(
        allowFullFallback: false,
        forceConfigurationRefresh: true,
      );
      await _load(selectDashboard: _dashboardId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos y configuración actualizados.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_sync.friendlyError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshingAll = false);
    }
  }

  Future<void> _approvalNotice({bool once = false}) async {
    if (!_requiresAdminApproval || !mounted) return;
    if (once && _approvalNoticeShown) return;
    _approvalNoticeShown = true;
    await ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Cambio enviado como Solicitado. Un administrador de esta empresa '
          'debe aprobarlo antes de que se publique.',
        ),
      ),
    );
  }

  Future<void> _selectDashboard(String id) async {
    final requestRevision = ++_dashboardLoadRevision;
    ++_datasetLoadRevision;
    setState(() {
      _dashboardId = id;
      _widgets = const [];
      _relations = const [];
      _datasets.clear();
      _liveWidgetSizes.clear();
      _liveWidgetPositions.clear();
      _editingWidget = null;
      _filterEditorOpen = false;
      _addingDashboardFilter = false;
      _resizingWidgetId = null;
      _loadingData = true;
    });
    try {
      final values = await Future.wait([
        _repository.listWidgets(id),
        _repository.listRelations(id),
      ]);
      if (!mounted ||
          requestRevision != _dashboardLoadRevision ||
          _dashboardId != id) {
        return;
      }
      setState(() {
        _widgets = values[0];
        _relations = values[1];
      });
      await _loadDatasets();
    } finally {
      if (mounted &&
          requestRevision == _dashboardLoadRevision &&
          _dashboardId == id) {
        setState(() => _loadingData = false);
      }
    }
  }

  List<MetricGlobalFilter> get _globalFilters {
    final dashboard = _selectedDashboard;
    if (dashboard == null) return const [];
    final output = <MetricGlobalFilter>[];
    for (final filter in _maps(dashboard['filtros_globales'])) {
      final id = filter['id']?.toString() ??
          '${filter['table'] ?? filter['tabla']}_${filter['field'] ?? filter['campo']}';
      final value = _dashboardFilterValues[id];
      final table = (filter['table'] ?? filter['tabla'])?.toString() ?? '';
      final field = (filter['field'] ?? filter['campo'])?.toString() ?? '';
      final hasValue = value is List
          ? value.isNotEmpty
          : value is Map
              ? value.values.any((item) => '${item ?? ''}'.trim().isNotEmpty)
              : '${value ?? ''}'.trim().isNotEmpty;
      if (!hasValue || table.isEmpty || field.isEmpty) continue;
      output.add(MetricGlobalFilter(
        id: id,
        table: table,
        field: field,
        value: value,
        operator: filter['mode']?.toString() ?? 'list',
      ));
    }
    return output;
  }

  Future<void> _loadDatasets() async {
    final revision = ++_datasetLoadRevision;
    final dashboardId = _dashboardId;
    final widgets = _widgets
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    final relations = _relations
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    final filters = List<MetricGlobalFilter>.from(_globalFilters);
    if (widgets.isEmpty) {
      if (mounted) {
        setState(() {
          _datasets.clear();
          _loadingData = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _loadingData = true);
    final entries = await Future.wait(widgets.map((widget) async {
      final widgetId = '${widget['id']}';
      try {
        if ('${widget['tipo_grafico']}'.toUpperCase() == 'TEXT') {
          return MapEntry(
            widgetId,
            const MetricDataset(points: [], rows: []),
          );
        }
        final ignored =
            (_map(widget['configuracion'])['ignored_filters'] as List? ??
                    const [])
                .map((value) => value.toString())
                .toSet();
        final dataset = await _repository.queryWidget(
          widget: widget,
          relations: relations,
          globalFilters:
              filters.where((filter) => !ignored.contains(filter.id)).toList(),
        );
        return MapEntry(widgetId, dataset);
      } catch (_) {
        return MapEntry(
          widgetId,
          const MetricDataset(points: [], rows: []),
        );
      }
    }));
    if (mounted &&
        revision == _datasetLoadRevision &&
        dashboardId == _dashboardId) {
      setState(() {
        _datasets
          ..clear()
          ..addEntries(entries);
        _loadingData = false;
      });
    }
  }

  Future<void> _editDashboard([Map<String, dynamic>? dashboard]) async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DashboardEditorDialog(
        initial: dashboard,
        users: _maps(_context['usuarios']),
      ),
    );
    if (payload == null) return;
    final result = await _repository.saveDashboard(payload);
    if (result['solicitado'] == true) {
      await _approvalNotice();
      await _load();
      return;
    }
    await _load(selectDashboard: '${result['id']}');
  }

  Future<void> _deleteDashboard() async {
    final dashboard = _selectedDashboard;
    if (dashboard == null) return;
    if (!await _confirm('Eliminar dashboard',
        'Se ocultará este dashboard y todos sus gráficos.')) {
      return;
    }
    final result =
        await _repository.deleteItem('DASHBOARD', '${dashboard['id']}');
    if (result['solicitado'] == true) await _approvalNotice();
    await _load();
  }

  Future<void> _editWidget([Map<String, dynamic>? widget]) async {
    if (_dashboardId == null) return;
    setState(() {
      _editorRevision++;
      _editingWidget = widget == null ? <String, dynamic>{} : _deepMap(widget);
      _filterEditorOpen = false;
      _addingDashboardFilter = false;
      _resizingWidgetId = widget?['id']?.toString();
    });
  }

  Future<void> _saveWidgetFromPanel(Map<String, dynamic> payload) async {
    final result = await _repository.saveWidget(payload);
    if (result['solicitado'] == true) await _approvalNotice();
    if (!mounted) return;
    setState(() {
      _editingWidget = null;
      _resizingWidgetId = null;
    });
    await _selectDashboard(_dashboardId!);
  }

  void _openFilterPanel() {
    if (_dashboardId == null) return;
    setState(() {
      _filterEditorOpen = true;
      _addingDashboardFilter = false;
      _editingWidget = null;
      _resizingWidgetId = null;
    });
  }

  void _closeRightPanel() {
    setState(() {
      _editingWidget = null;
      _filterEditorOpen = false;
      _addingDashboardFilter = false;
      _resizingWidgetId = null;
    });
  }

  Future<void> _addDashboardFilter(Map<String, dynamic> filter) async {
    final dashboard = _selectedDashboard;
    if (dashboard == null) return;
    final filters = _maps(dashboard['filtros_globales']);
    filters.add(filter);
    final result = await _repository.saveDashboard({
      'id': dashboard['id'],
      'nombre': dashboard['nombre'],
      'descripcion': dashboard['descripcion'],
      'color': dashboard['color'],
      'orden': dashboard['orden'] ?? 0,
      'filtros_globales': filters,
      'configuracion': _map(dashboard['configuracion']),
    });
    if (result['solicitado'] == true) await _approvalNotice();
    if (!mounted) return;
    setState(() {
      _addingDashboardFilter = false;
      _filterEditorOpen = true;
    });
    await _load(selectDashboard: _dashboardId);
  }

  Future<void> _updateDashboardFilter(Map<String, dynamic> filter) async {
    final dashboard = _selectedDashboard;
    if (dashboard == null) return;
    final id = filter['id']?.toString();
    final filters = _maps(dashboard['filtros_globales']);
    final index = filters.indexWhere((item) => item['id']?.toString() == id);
    if (index < 0) return;
    filters[index] = filter;
    final result = await _repository.saveDashboard({
      'id': dashboard['id'],
      'nombre': dashboard['nombre'],
      'descripcion': dashboard['descripcion'],
      'color': dashboard['color'],
      'orden': dashboard['orden'] ?? 0,
      'filtros_globales': filters,
      'configuracion': _map(dashboard['configuracion']),
    });
    if (result['solicitado'] == true) await _approvalNotice();
    await _load(selectDashboard: _dashboardId);
  }

  Future<void> _removeDashboardFilter(Map<String, dynamic> filter) async {
    final dashboard = _selectedDashboard;
    if (dashboard == null) return;
    final wantedId = filter['id']?.toString();
    final filters = _maps(dashboard['filtros_globales'])
      ..removeWhere((item) => item['id']?.toString() == wantedId);
    final result = await _repository.saveDashboard({
      'id': dashboard['id'],
      'nombre': dashboard['nombre'],
      'descripcion': dashboard['descripcion'],
      'color': dashboard['color'],
      'orden': dashboard['orden'] ?? 0,
      'filtros_globales': filters,
      'configuracion': _map(dashboard['configuracion']),
    });
    if (result['solicitado'] == true) await _approvalNotice();
    await _load(selectDashboard: _dashboardId);
  }

  Future<void> _reorderDashboards(int oldIndex, int newIndex) async {
    if (_reorderingDashboards || oldIndex == newIndex) return;
    final original =
        _dashboards.map((row) => Map<String, dynamic>.from(row)).toList();
    if (newIndex > oldIndex) newIndex--;
    final reordered =
        _dashboards.map((row) => Map<String, dynamic>.from(row)).toList();
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    setState(() => _dashboards = reordered);
    final save = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.swap_vert_rounded, color: _metricsTeal),
            title: const Text('Guardar orden'),
            content: const Text('¿Deseas guardar estos cambios?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('No, volver'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Sí, guardar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!save) {
      if (mounted) setState(() => _dashboards = original);
      return;
    }
    if (mounted) setState(() => _reorderingDashboards = true);
    try {
      final saved = await _repository.reorderDashboards(
        reordered.map((dashboard) => '${dashboard['id']}').toList(),
      );
      if (!mounted) return;
      setState(() => _dashboards = saved);
      if (_requiresAdminApproval) {
        await _approvalNotice();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Orden guardado y verificado nuevamente en Supabase.'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _dashboards = original);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el orden: $error')),
      );
    } finally {
      if (mounted) setState(() => _reorderingDashboards = false);
    }
  }

  Future<void> _deleteWidget(Map<String, dynamic> widget) async {
    if (!await _confirm('Eliminar gráfico',
        'El gráfico se quitará del dashboard sin borrar sus datos de origen.')) {
      return;
    }
    final result = await _repository.deleteItem('WIDGET', '${widget['id']}');
    if (result['solicitado'] == true) await _approvalNotice();
    await _selectDashboard(_dashboardId!);
  }

  Future<void> _manageRelations() async {
    if (_dashboardId == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _RelationsDialog(
        dashboardId: _dashboardId!,
        sources: _sources,
        relations: _relations,
        repository: _repository,
      ),
    );
    await _selectDashboard(_dashboardId!);
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    _scheduleToolbarSync();
    final pageBody = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? _MetricsError(message: _error!, retry: _load)
            : !_enabled
                ? const _MetricsEmpty(
                    icon: Icons.analytics_outlined,
                    title: 'Metrics no está habilitado',
                    text: 'Activa la herramienta para esta empresa.',
                  )
                : LayoutBuilder(builder: (context, constraints) {
                    // Bajo este ancho se usa la composición fluida: selector
                    // superior y gráficos apilables sin coordenadas absolutas.
                    final desktop = constraints.maxWidth >= 1180;
                    final panelOpen =
                        _editingWidget != null || _filterEditorOpen;
                    if (desktop) {
                      return Row(children: [
                        Expanded(
                          child: _dashboardViewport(panelOpen: panelOpen),
                        ),
                        if (panelOpen) ...[
                          const VerticalDivider(width: 1),
                          SizedBox(width: 430, child: _rightPanel()),
                        ],
                      ]);
                    }
                    return Stack(
                      children: [
                        _dashboardCanvas(desktop: false),
                        if (panelOpen)
                          Positioned.fill(
                            child: ColoredBox(
                              color: Colors.black26,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: SizedBox(
                                  width:
                                      math.min(430, constraints.maxWidth * .94),
                                  child: _rightPanel(),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  });
    final title = const ZumacFeatureHeader(
      title: 'Zumac Metrics',
      icon: Icons.insights_outlined,
      color: Color(0xFF6E56CF),
      compact: true,
    );
    final refreshButton = IconButton(
      tooltip: 'Actualizar datos y configuración',
      onPressed: _loading ||
              _refreshingAll ||
              _reorderingDashboards ||
              _layoutSaveOperations > 0
          ? null
          : _refreshAllData,
      icon: _refreshingAll
          ? const SizedBox.square(
              dimension: 19,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded),
    );
    if (widget.embedded) {
      return ColoredBox(color: _metricsCanvas, child: pageBody);
    }
    return Scaffold(
      backgroundColor: _metricsCanvas,
      appBar: AppBar(
        title: title,
        actions: [refreshButton, const SizedBox(width: 8)],
      ),
      body: pageBody,
    );
  }

  /// Conserva la geometría del dashboard y reduce visualmente el lienzo cuando
  /// se abre el panel, como Power BI. El panel ocupa su propia columna y nunca
  /// tapa ni recorta los gráficos.
  Widget _dashboardViewport({required bool panelOpen}) {
    return SizedBox.expand(
      child: _dashboardCanvas(
        desktop: true,
        preserveDesktopGeometry: panelOpen,
      ),
    );
  }

  Widget _rightPanel() {
    if (_filterEditorOpen) {
      if (!_addingDashboardFilter) {
        return _DashboardFiltersPanel(
          filters: _maps(_selectedDashboard?['filtros_globales']),
          repository: _repository,
          values: _dashboardFilterValues,
          onClose: _closeRightPanel,
          onAdd: () => setState(() => _addingDashboardFilter = true),
          onRemove: _removeDashboardFilter,
          onUpdate: _updateDashboardFilter,
          onApply: (id, value) async {
            setState(() => _dashboardFilterValues[id] = value);
            await _loadDatasets();
          },
        );
      }
      return _DashboardFilterEditorPanel(
        sources: _sources,
        onClose: () => setState(() => _addingDashboardFilter = false),
        onSave: _addDashboardFilter,
      );
    }
    return _MetricEditorPanel(
      key: ValueKey(
        'metric-editor-${_editingWidget?['id'] ?? 'new'}-$_editorRevision',
      ),
      dashboardId: _dashboardId!,
      sources: _sources,
      initial: _editingWidget!.isEmpty ? null : _editingWidget,
      onClose: _closeRightPanel,
      onSave: _saveWidgetFromPanel,
    );
  }

  Widget _dashboardCanvas({
    required bool desktop,
    bool preserveDesktopGeometry = false,
  }) {
    if (_dashboards.isEmpty) {
      return _MetricsEmpty(
        icon: Icons.dashboard_customize_outlined,
        title: 'Construye tu primer dashboard',
        text:
            'Combina tablas, agrega gráficos y crea filtros compartidos sin modificar los formatos.',
        action: _canManage
            ? FilledButton.icon(
                onPressed: _editDashboard,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nuevo dashboard'),
              )
            : null,
      );
    }
    final dashboard = _selectedDashboard!;
    final canvasConfig = _map(dashboard['configuracion']);
    final backgroundColor = _color(
      canvasConfig['background_color'] ?? dashboard['color'],
      _metricsCanvas,
    );
    DecorationImage? backgroundImage;
    final rawBackground = canvasConfig['background_image']?.toString() ?? '';
    if (rawBackground.startsWith('data:image/') &&
        rawBackground.contains(',')) {
      try {
        backgroundImage = DecorationImage(
          image: MemoryImage(base64Decode(rawBackground.split(',').last)),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.white.withValues(
              alpha: 1 -
                  ((canvasConfig['background_opacity'] as num?)?.toDouble() ??
                      1),
            ),
            BlendMode.srcOver,
          ),
        );
      } catch (_) {}
    }
    final decoration = BoxDecoration(
      color: _colorWithOpacity(
        backgroundColor,
        (canvasConfig['background_opacity'] as num?)?.toDouble() ?? 1,
      ),
      image: backgroundImage,
    );
    if (desktop) {
      return Container(
        decoration: decoration,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const horizontalMargin = 12.0;
            const verticalMargin = 8.0;
            final viewportWidth =
                math.max(0.0, constraints.maxWidth - horizontalMargin * 2);
            final viewportHeight =
                math.max(0.0, constraints.maxHeight - verticalMargin * 2);
            if (_widgets.isEmpty) {
              return _MetricsEmpty(
                icon: Icons.add_chart_outlined,
                title: 'Este dashboard todavía está vacío',
                text:
                    'Agrega un KPI, barras, líneas, áreas, circular, dispersión o tabla.',
                action: _canManage
                    ? FilledButton.icon(
                        onPressed: _editWidget,
                        icon: const Icon(Icons.add_chart_outlined),
                        label: const Text('Agregar gráfico'),
                      )
                    : null,
              );
            }
            final referenceWidth = metricsDesktopGeometryWidth(
              availableWidth: viewportWidth,
              panelOpen: preserveDesktopGeometry,
              lastFullWidth: _desktopCanvasReferenceWidth,
            );
            if (!preserveDesktopGeometry) {
              _desktopCanvasReferenceWidth = viewportWidth;
            }
            final columns = referenceWidth >= 1280
                ? 3
                : referenceWidth >= 720
                    ? 2
                    : 1;
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: horizontalMargin,
                vertical: verticalMargin,
              ),
              child: _desktopWidgetCanvas(
                viewportWidth: viewportWidth,
                viewportHeight: viewportHeight,
                geometryWidth: referenceWidth,
                columns: columns,
                gap: 14,
              ),
            );
          },
        ),
      );
    }
    return Container(
      decoration: decoration,
      child: RefreshIndicator(
        onRefresh: _loadDatasets,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.toolbarController == null)
                        _mobileDashboardPicker(),
                      _mobileDashboardActions(dashboard),
                      const SizedBox(height: 8),
                      if (_maps(dashboard['filtros_globales']).isNotEmpty)
                        const Text(
                          'Usa el botón de filtros para aplicar o modificar los filtros de esta vista.',
                          style: TextStyle(color: _metricsMuted, fontSize: 12),
                        ),
                      if (_maps(dashboard['filtros_globales']).isNotEmpty)
                        const SizedBox(height: 12),
                    ]),
              ),
            ),
            if (_widgets.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _MetricsEmpty(
                  icon: Icons.add_chart_outlined,
                  title: 'Este dashboard todavía está vacío',
                  text:
                      'Agrega un KPI, barras, líneas, áreas, circular, dispersión o tabla.',
                  action: _canManage
                      ? FilledButton.icon(
                          onPressed: _editWidget,
                          icon: const Icon(Icons.add_chart_outlined),
                          label: const Text('Agregar gráfico'),
                        )
                      : null,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;
                    final columns = width >= 1100 ? 2 : 1;
                    const gap = 14.0;
                    final cardWidth = (width - gap * (columns - 1)) / columns;
                    return SliverToBoxAdapter(
                      child: Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: _widgets.map((widget) {
                          final gridWidth =
                              (widget['ancho'] as num?)?.toInt() ?? 6;
                          final span = columns == 1
                              ? 1
                              : math.max(
                                  1,
                                  math.min(
                                    columns,
                                    (gridWidth / (12 / columns)).ceil(),
                                  ),
                                );
                          final widgetId = widget['id']?.toString() ?? '';
                          final config = _map(widget['configuracion']);
                          final defaultWidth =
                              cardWidth * span + gap * (span - 1);
                          final persistedHeight =
                              (config['pixel_height'] as num?)?.toDouble();
                          final liveSize = _liveWidgetSizes[widgetId];
                          // En modo responsive la geometría libre no se
                          // usa: cada tarjeta ocupa su celda completa y
                          // nunca puede desbordar el viewport.
                          final sizedWidth =
                              defaultWidth.clamp(0.0, width).toDouble();
                          final sizedHeight = (liveSize?.height ??
                                  persistedHeight ??
                                  _widgetHeight(widget, columns))
                              .clamp(190.0, 1000.0)
                              .toDouble();
                          return DragTarget<String>(
                            onWillAcceptWithDetails: (details) =>
                                details.data != widgetId,
                            onAcceptWithDetails: (details) =>
                                unawaited(_moveWidget(details.data, widgetId)),
                            builder: (context, candidates, _) =>
                                AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              width: sizedWidth,
                              height: sizedHeight,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  metricsChartBorderRadius(config),
                                ),
                                border: candidates.isEmpty
                                    ? null
                                    : Border.all(
                                        color: _metricsTeal,
                                        width: 3,
                                      ),
                              ),
                              child: Stack(
                                children: [
                                  Positioned.fill(child: _metricCard(widget)),
                                  Positioned(
                                    right: 3,
                                    bottom: 3,
                                    child: _expandButton(widget),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mobileDashboardActions(Map<String, dynamic> dashboard) => Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: 2,
          children: [
            if (_canManage)
              IconButton(
                tooltip: 'Agregar gráfico',
                onPressed: _editWidget,
                icon: const Icon(Icons.add_chart_outlined),
              ),
            if (_canManage)
              IconButton(
                tooltip: 'Agregar filtro',
                onPressed: _openFilterPanel,
                icon: const Icon(Icons.filter_alt_outlined),
              ),
            if (_canManage)
              PopupMenuButton<String>(
                tooltip: 'Administrar dashboard',
                onSelected: (value) {
                  if (value == 'edit') _editDashboard(dashboard);
                  if (value == 'relations') _manageRelations();
                  if (value == 'delete') _deleteDashboard();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Editar')),
                  PopupMenuItem(
                    value: 'relations',
                    child: Text('Relacionar tablas'),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Eliminar dashboard'),
                  ),
                ],
              ),
          ],
        ),
      );

  /// Cada objeto conserva su posición y tamaño en `configuracion`, de modo
  /// que mover un gráfico no altera el orden ni el diseño de los demás.
  Widget _desktopWidgetCanvas({
    required double viewportWidth,
    required double viewportHeight,
    required double geometryWidth,
    required int columns,
    required double gap,
  }) {
    final cellWidth = (geometryWidth - gap * (columns - 1)) / columns;
    final rects = <({Map<String, dynamic> widget, Rect rect})>[];
    for (var index = 0; index < _widgets.length; index++) {
      final widget = _widgets[index];
      final widgetId = widget['id']?.toString() ?? 'widget-$index';
      final config = _map(widget['configuracion']);
      final fallbackHeight = _widgetHeight(widget, columns);
      final size = _liveWidgetSizes[widgetId] ??
          Size(
            ((config['pixel_width'] as num?)?.toDouble() ?? cellWidth)
                .clamp(260.0, geometryWidth)
                .toDouble(),
            ((config['pixel_height'] as num?)?.toDouble() ?? fallbackHeight)
                .clamp(190.0, 1000.0)
                .toDouble(),
          );
      final fallback = Offset(
        (index % columns) * (cellWidth + gap),
        (index ~/ columns) * (fallbackHeight + gap),
      );
      final position = _liveWidgetPositions[widgetId] ??
          Offset(
            (config['pixel_x'] as num?)?.toDouble() ?? fallback.dx,
            (config['pixel_y'] as num?)?.toDouble() ?? fallback.dy,
          );
      rects.add((
        widget: widget,
        rect: Rect.fromLTWH(
          position.dx.clamp(0.0, math.max(0.0, geometryWidth - size.width)),
          math.max(0.0, position.dy),
          size.width,
          size.height,
        ),
      ));
    }
    final geometryHeight = rects.fold<double>(360, (current, item) {
      return math.max(current, item.rect.bottom + 24);
    });
    final scale = metricsDesktopCanvasScale(
      viewportWidth: viewportWidth,
      geometryWidth: geometryWidth,
      viewportHeight: viewportHeight,
      geometryHeight: geometryHeight,
    );
    return SizedBox(
      width: viewportWidth,
      height: viewportHeight,
      child: ClipRect(
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: geometryWidth,
            height: geometryHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: rects.map((item) {
                final widget = item.widget;
                final rect = item.rect;
                final widgetId = widget['id']?.toString() ?? '';
                final editingWidgetId =
                    _editingWidget?['id']?.toString().trim();
                final canResize = metricsCanResizeWidget(
                  canManage: _canManage,
                  filterPanelOpen: _filterEditorOpen,
                  editingWidgetId: editingWidgetId,
                  widgetId: widgetId,
                );
                final selected = _resizingWidgetId == widgetId ||
                    _movingWidgetId == widgetId;
                final config = _map(widget['configuracion']);
                final borderRadius = metricsChartBorderRadius(config);
                return Positioned(
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 90),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(borderRadius),
                      border: selected
                          ? Border.all(color: _metricsTeal, width: 2)
                          : null,
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _metricCard(widget),
                        ),
                        if (editingWidgetId != null &&
                            editingWidgetId.isNotEmpty &&
                            editingWidgetId != widgetId)
                          Positioned.fill(
                            child: Semantics(
                              button: true,
                              label: 'Editar ${widget['titulo'] ?? 'gráfico'}',
                              child: GestureDetector(
                                key: ValueKey(
                                  'metrics-select-widget-$widgetId',
                                ),
                                behavior: HitTestBehavior.opaque,
                                onTap: () => unawaited(_editWidget(widget)),
                              ),
                            ),
                          ),
                        if (canResize) ...[
                          _geometryEdge(
                            widget: widget,
                            rect: rect,
                            canvasWidth: geometryWidth,
                            canvasScale: scale,
                            side: _MetricGeometrySide.left,
                          ),
                          _geometryEdge(
                            widget: widget,
                            rect: rect,
                            canvasWidth: geometryWidth,
                            canvasScale: scale,
                            side: _MetricGeometrySide.right,
                          ),
                          _geometryEdge(
                            widget: widget,
                            rect: rect,
                            canvasWidth: geometryWidth,
                            canvasScale: scale,
                            side: _MetricGeometrySide.top,
                          ),
                          _geometryEdge(
                            widget: widget,
                            rect: rect,
                            canvasWidth: geometryWidth,
                            canvasScale: scale,
                            side: _MetricGeometrySide.bottom,
                          ),
                        ],
                        Positioned(
                          left: 3,
                          bottom: 3,
                          child: _expandButton(widget),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _expandButton(Map<String, dynamic> widget) {
    return Material(
      color: Colors.white.withValues(alpha: .94),
      shape: const CircleBorder(),
      elevation: 1,
      child: IconButton(
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        padding: EdgeInsets.zero,
        tooltip: 'Ampliar gráfico',
        onPressed: () => _expandWidget(widget),
        icon: const Icon(Icons.open_in_full_rounded, size: 18),
      ),
    );
  }

  Widget _geometryEdge({
    required Map<String, dynamic> widget,
    required Rect rect,
    required double canvasWidth,
    required double canvasScale,
    required _MetricGeometrySide side,
  }) {
    final safeScale = math.max(.1, canvasScale);
    final widgetId = widget['id']?.toString() ?? '';
    final horizontalBorder =
        side == _MetricGeometrySide.top || side == _MetricGeometrySide.bottom;
    final horizontalInset = metricsCanvasHitTarget(
      screenPixels: 16,
      canvasScale: safeScale,
      maximumCanvasPixels: rect.width * .20,
    );
    final verticalInset = metricsCanvasHitTarget(
      screenPixels: 16,
      canvasScale: safeScale,
      maximumCanvasPixels: rect.height * .20,
    );
    final verticalEdgeWidth = metricsCanvasHitTarget(
      screenPixels: 14,
      canvasScale: safeScale,
      maximumCanvasPixels: rect.width * .25,
    );
    final horizontalEdgeHeight = metricsCanvasHitTarget(
      screenPixels: 14,
      canvasScale: safeScale,
      maximumCanvasPixels: rect.height * .25,
    );
    final edge = MouseRegion(
      cursor: horizontalBorder
          ? SystemMouseCursors.resizeUpDown
          : SystemMouseCursors.resizeLeftRight,
      child: Tooltip(
        message: horizontalBorder
            ? 'Arrastra para ajustar el alto; mantén presionado para mover'
            : 'Arrastra para ajustar el ancho; mantén presionado para mover',
        child: Listener(
          key: ValueKey('metrics-geometry-${side.name}-$widgetId'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (_geometryPointerId != null) return;
            _geometryHoldTimer?.cancel();
            _geometryPointerId = event.pointer;
            _geometryGestureOrigin =
                _liveWidgetPositions[widgetId] ?? rect.topLeft;
            _geometryPointerPosition = event.position;
            _geometryPointerDownPosition = event.position;
            _geometryMoveMode = false;
            _geometryGestureChanged = false;
            _geometryHoldTimer = Timer(const Duration(milliseconds: 420), () {
              if (!mounted || _geometryPointerId != event.pointer) return;
              setState(() {
                _geometryMoveMode = true;
                _movingWidgetId = widgetId;
              });
            });
          },
          onPointerMove: (event) {
            if (_geometryPointerId != event.pointer) return;
            final previousPointer = _geometryPointerPosition ?? event.position;
            final pointerDown = _geometryPointerDownPosition ?? previousPointer;
            final screenDelta = event.position - previousPointer;
            final totalScreenDelta = event.position - pointerDown;
            _geometryPointerPosition = event.position;
            if (!_geometryMoveMode && totalScreenDelta.distance < 3) return;
            _geometryGestureChanged = true;
            if (_geometryMoveMode) {
              final origin = _geometryGestureOrigin ?? rect.topLeft;
              final next = Offset(
                (origin.dx +
                        metricsCanvasGestureDelta(
                          screenDelta: totalScreenDelta.dx,
                          canvasScale: safeScale,
                        ))
                    .clamp(0.0, math.max(0.0, canvasWidth - rect.width)),
                math.max(
                  0.0,
                  origin.dy +
                      metricsCanvasGestureDelta(
                        screenDelta: totalScreenDelta.dy,
                        canvasScale: safeScale,
                      ),
                ),
              );
              setState(() => _liveWidgetPositions[widgetId] = next);
              return;
            }
            _geometryHoldTimer?.cancel();
            setState(() {
              _movingWidgetId = null;
              _resizingWidgetId = widgetId;
            });
            _resizeWidgetFromEdge(
              widget,
              rect,
              Offset(
                metricsCanvasGestureDelta(
                  screenDelta: screenDelta.dx,
                  canvasScale: safeScale,
                ),
                metricsCanvasGestureDelta(
                  screenDelta: screenDelta.dy,
                  canvasScale: safeScale,
                ),
              ),
              side: side,
              canvasWidth: canvasWidth,
            );
          },
          onPointerUp: (event) {
            if (_geometryPointerId != event.pointer) return;
            _finishGeometryPointer(widget, widgetId, persist: true);
          },
          onPointerCancel: (event) {
            if (_geometryPointerId != event.pointer) return;
            _finishGeometryPointer(widget, widgetId, persist: false);
          },
          child: const SizedBox.expand(),
        ),
      ),
    );
    return switch (side) {
      _MetricGeometrySide.left => Positioned(
          left: 0,
          top: verticalInset,
          bottom: verticalInset,
          width: verticalEdgeWidth,
          child: edge,
        ),
      _MetricGeometrySide.right => Positioned(
          right: 0,
          top: verticalInset,
          bottom: verticalInset,
          width: verticalEdgeWidth,
          child: edge,
        ),
      _MetricGeometrySide.top => Positioned(
          left: horizontalInset,
          right: horizontalInset,
          top: 0,
          height: horizontalEdgeHeight,
          child: edge,
        ),
      _MetricGeometrySide.bottom => Positioned(
          left: horizontalInset,
          right: horizontalInset,
          bottom: 0,
          height: horizontalEdgeHeight,
          child: edge,
        ),
    };
  }

  void _finishGeometryPointer(
    Map<String, dynamic> widget,
    String widgetId, {
    required bool persist,
  }) {
    _geometryHoldTimer?.cancel();
    _geometryHoldTimer = null;
    final changed = _geometryGestureChanged;
    _geometryPointerId = null;
    _geometryGestureOrigin = null;
    _geometryPointerPosition = null;
    _geometryPointerDownPosition = null;
    _geometryMoveMode = false;
    _geometryGestureChanged = false;
    if (mounted) {
      setState(() {
        _movingWidgetId = null;
        _resizingWidgetId =
            _editingWidget?['id']?.toString() == widgetId ? widgetId : null;
      });
    }
    if (persist && changed) unawaited(_persistWidgetGeometry(widget));
  }

  void _resizeWidgetFromEdge(
    Map<String, dynamic> widget,
    Rect rect,
    Offset delta, {
    required _MetricGeometrySide side,
    required double canvasWidth,
  }) {
    final widgetId = widget['id']?.toString() ?? '';
    if (widgetId.isEmpty) return;
    final currentSize = _liveWidgetSizes[widgetId] ?? rect.size;
    final currentPosition = _liveWidgetPositions[widgetId] ?? rect.topLeft;
    var nextSize = currentSize;
    var nextPosition = currentPosition;
    if (side == _MetricGeometrySide.left || side == _MetricGeometrySide.right) {
      final leading = side == _MetricGeometrySide.left;
      final maximum = leading
          ? currentPosition.dx + currentSize.width
          : canvasWidth - currentPosition.dx;
      final proposed = currentSize.width + (leading ? -delta.dx : delta.dx);
      final nextWidth = proposed
          .clamp(math.min(260.0, maximum), math.max(260.0, maximum))
          .toDouble();
      if (leading) {
        nextPosition = Offset(
          currentPosition.dx + currentSize.width - nextWidth,
          currentPosition.dy,
        );
      }
      nextSize = Size(nextWidth, currentSize.height);
    } else {
      final leading = side == _MetricGeometrySide.top;
      final proposed = currentSize.height + (leading ? -delta.dy : delta.dy);
      final nextHeight = proposed.clamp(190.0, 1000.0).toDouble();
      if (leading) {
        nextPosition = Offset(
          currentPosition.dx,
          math.max(0.0, currentPosition.dy + currentSize.height - nextHeight),
        );
      }
      nextSize = Size(currentSize.width, nextHeight);
    }
    setState(() {
      _liveWidgetSizes[widgetId] = nextSize;
      if (nextPosition != currentPosition) {
        _liveWidgetPositions[widgetId] = nextPosition;
      }
    });
  }

  double _widgetHeight(Map<String, dynamic> widget, int columns) {
    final type = '${widget['tipo_grafico']}'.toUpperCase();
    if (type == 'KPI') return 235;
    final configured = (widget['alto'] as num?)?.toInt() ?? 4;
    final extra = math.max(0, configured - 4) * 28.0;
    if (type == 'TABLE') return (columns == 1 ? 390 : 360) + extra;
    return (columns == 1 ? 350 : 330) + extra;
  }

  Widget _mobileDashboardPicker() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        initialValue: _dashboardId,
        decoration: const InputDecoration(
          labelText: 'Dashboard',
          border: OutlineInputBorder(),
        ),
        items: _dashboards
            .map((dashboard) => DropdownMenuItem(
                value: '${dashboard['id']}',
                child: Text('${dashboard['nombre']}')))
            .toList(),
        onChanged: (value) {
          if (value != null) _selectDashboard(value);
        },
      ),
    );
  }

  Future<void> _persistWidgetGeometry(Map<String, dynamic> widget) async {
    final widgetId = widget['id']?.toString() ?? '';
    final liveSize = _liveWidgetSizes[widgetId];
    final livePosition = _liveWidgetPositions[widgetId];
    if (liveSize == null && livePosition == null) return;
    final config = _map(widget['configuracion']);
    if (liveSize != null) {
      config
        ..['pixel_width'] = liveSize.width.round()
        ..['pixel_height'] = liveSize.height.round();
    }
    if (livePosition != null) {
      config
        ..['pixel_x'] = livePosition.dx.round()
        ..['pixel_y'] = livePosition.dy.round();
    }
    final geometry = <String, dynamic>{
      if (liveSize != null) 'pixel_width': liveSize.width.round(),
      if (liveSize != null) 'pixel_height': liveSize.height.round(),
      if (livePosition != null) 'pixel_x': livePosition.dx.round(),
      if (livePosition != null) 'pixel_y': livePosition.dy.round(),
    };
    if (mounted) setState(() => _layoutSaveOperations++);
    try {
      final saved = await _repository.saveWidgetGeometry(
        widgetId: widgetId,
        dashboardId: _dashboardId!,
        geometry: geometry,
      );
      if (saved['solicitado'] == true) {
        await _approvalNotice(once: true);
        return;
      }
      final savedConfig = _map(saved['configuracion']);
      for (final entry in geometry.entries) {
        final confirmed = (savedConfig[entry.key] as num?)?.round();
        if (confirmed != entry.value) {
          throw StateError('PostgreSQL no confirmó ${entry.key}.');
        }
      }
      if (mounted) {
        setState(() {
          widget['configuracion'] = <String, dynamic>{
            ...config,
            ...savedConfig,
          };
          _liveWidgetSizes.remove(widgetId);
          _liveWidgetPositions.remove(widgetId);
        });
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la posición: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _layoutSaveOperations = math.max(0, _layoutSaveOperations - 1);
        });
      }
    }
  }

  Future<void> _moveWidget(String draggedId, String targetId) async {
    if (draggedId == targetId) return;
    final reordered =
        _widgets.map((item) => Map<String, dynamic>.from(item)).toList();
    final oldIndex =
        reordered.indexWhere((item) => item['id']?.toString() == draggedId);
    final targetIndex =
        reordered.indexWhere((item) => item['id']?.toString() == targetId);
    if (oldIndex < 0 || targetIndex < 0) return;
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(targetIndex, moved);
    if (mounted) setState(() => _widgets = reordered);
    try {
      for (var index = 0; index < reordered.length; index++) {
        final item = reordered[index];
        final result = await _repository.saveWidget({
          ...item,
          'dashboard_id': _dashboardId,
          'orden': index,
          'configuracion': _map(item['configuracion']),
          'filtros': _maps(item['filtros']),
        });
        if (result['solicitado'] == true) {
          await _approvalNotice(once: true);
        }
      }
      await _selectDashboard(_dashboardId!);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la posición: $error')),
      );
      await _selectDashboard(_dashboardId!);
    }
  }

  Future<void> _saveWidgetConfiguration(
    Map<String, dynamic> widget,
    Map<String, dynamic> config,
  ) async {
    final result = await _repository.saveWidget({
      ...widget,
      'dashboard_id': _dashboardId,
      'configuracion': config,
      'filtros': _maps(widget['filtros']),
    });
    if (result['solicitado'] == true) await _approvalNotice();
    await _selectDashboard(_dashboardId!);
  }

  Future<void> _configureIgnoredFilters(Map<String, dynamic> widget) async {
    final filters = _maps(_selectedDashboard?['filtros_globales']);
    if (filters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Este dashboard todavía no tiene filtros.')),
      );
      return;
    }
    final config = _map(widget['configuracion']);
    final selected = (config['ignored_filters'] as List? ?? const [])
        .map((value) => value.toString())
        .toSet();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Filtros que no afectan este gráfico'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: filters.map((filter) {
                final id = filter['id']?.toString() ??
                    '${filter['table']}_${filter['field']}';
                return CheckboxListTile(
                  value: selected.contains(id),
                  title: Text(filter['label']?.toString() ?? id),
                  subtitle: Text(
                      '${filter['table'] ?? ''} · ${filter['field'] ?? ''}'),
                  onChanged: (value) => setDialogState(() {
                    if (value == true) {
                      selected.add(id);
                    } else {
                      selected.remove(id);
                    }
                  }),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _saveWidgetConfiguration(widget, {
      ...config,
      'ignored_filters': result.toList(),
    });
  }

  Future<void> _setWidgetSort(
      Map<String, dynamic> widget, String sortMode) async {
    await _saveWidgetConfiguration(widget, {
      ..._map(widget['configuracion']),
      'sort_mode': sortMode,
    });
  }

  Future<void> _expandWidget(Map<String, dynamic> widget) async {
    final dataset = _datasets['${widget['id']}'] ??
        const MetricDataset(points: [], rows: []);
    final config = _map(widget['configuracion']);
    final title = widget['titulo']?.toString().trim() ?? '';
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: const Color(0xFFF3F7FA),
        child: SafeArea(
          child: Stack(
            children: [
              Column(children: [
                if (title.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
                    color: Colors.white,
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: _metricsNavy,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar vista ampliada',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_fullscreen),
                      ),
                    ]),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Card(
                      elevation: 2,
                      color: _color(config['background_color'], Colors.white),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: _MetricVisualization(
                          widget: widget,
                          dataset: dataset,
                          color: _color(config['color'], _metricsTeal),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
              if (title.isEmpty)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.white.withValues(alpha: .94),
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      tooltip: 'Cerrar vista ampliada',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_fullscreen),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricCard(Map<String, dynamic> widget) {
    final dataset = _datasets['${widget['id']}'];
    final config = _map(widget['configuracion']);
    final color = _color(config['color'], _metricsTeal);
    final editing = _resizingWidgetId == widget['id']?.toString();
    final hasTitle = metricsChartHasTitle(widget['titulo']);
    final borderRadius = metricsChartBorderRadius(config);
    return Card(
      key: ValueKey('metrics-card-${widget['id']}'),
      elevation: config['shadow'] == false ? 0 : 2,
      margin: EdgeInsets.zero,
      color: _color(config['background_color'], Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(
          color: editing
              ? _metricsTeal
              : _color(config['border_color'], const Color(0xFFDCE7EC)),
          width:
              editing ? 2 : (config['border_width'] as num?)?.toDouble() ?? 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (hasTitle)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _color(config['title_background'], Colors.transparent),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: _color(
                      config['title_border_color'], const Color(0xFFDCE7EC)),
                  width:
                      (config['title_border_width'] as num?)?.toDouble() ?? 0,
                ),
              ),
              child: Row(children: [
                Expanded(
                  child: Text('${widget['titulo']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: switch (
                          config['title_alignment']?.toString()) {
                        'center' => TextAlign.center,
                        'right' => TextAlign.right,
                        _ => TextAlign.left,
                      },
                      style: TextStyle(
                        color: _color(config['title_color'], _metricsNavy),
                        fontSize:
                            ((config['title_size'] as num?)?.toDouble() ?? 16),
                        fontFamily: config['title_font']?.toString(),
                        fontWeight: FontWeight.w800,
                      )),
                ),
                if (_canManage)
                  PopupMenuButton<String>(
                    tooltip: 'Configurar gráfico',
                    onSelected: (value) {
                      if (value == 'edit') _editWidget(widget);
                      if (value == 'ignore_filters') {
                        _configureIgnoredFilters(widget);
                      }
                      if (value == 'delete') _deleteWidget(widget);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'edit', child: Text('Editar gráfico')),
                      const PopupMenuItem(
                        value: 'ignore_filters',
                        child: Text('Filtros que no afectan'),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem<String>(
                        enabled: false,
                        padding: EdgeInsets.zero,
                        child: SubmenuButton(
                          menuChildren: [
                            MenuItemButton(
                              onPressed: () =>
                                  _setWidgetSort(widget, 'label_asc'),
                              child: const Text('Ascendente'),
                            ),
                            MenuItemButton(
                              onPressed: () =>
                                  _setWidgetSort(widget, 'value_desc'),
                              child: const Text('Mayor a menor'),
                            ),
                            MenuItemButton(
                              onPressed: () =>
                                  _setWidgetSort(widget, 'value_asc'),
                              child: const Text('Menor a mayor'),
                            ),
                            MenuItemButton(
                              onPressed: () =>
                                  _setWidgetSort(widget, 'label_desc'),
                              child: const Text('Descendente'),
                            ),
                          ],
                          child: const Text('Ordenar por'),
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                          value: 'delete', child: Text('Eliminar')),
                    ],
                  ),
              ]),
            ),
          if ('${config['subtitle'] ?? ''}'.trim().isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 4),
              child: Text(
                '${config['subtitle']}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _color(config['subtitle_color'], _metricsMuted),
                  fontSize: (config['subtitle_size'] as num?)?.toDouble() ?? 12,
                  fontFamily: config['title_font']?.toString(),
                ),
              ),
            ),
            if (config['subtitle_divider'] == true)
              Divider(
                color: _color(
                  config['subtitle_divider_color'],
                  const Color(0xFFDCE7EC),
                ),
                thickness:
                    (config['subtitle_divider_width'] as num?)?.toDouble() ?? 1,
                height: 8,
              ),
          ],
          if ('${widget['descripcion'] ?? ''}'.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3, bottom: 6),
              child: Text('${widget['descripcion']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _metricsMuted, fontSize: 12)),
            ),
          if (hasTitle ||
              '${config['subtitle'] ?? ''}'.trim().isNotEmpty ||
              '${widget['descripcion'] ?? ''}'.trim().isNotEmpty)
            const SizedBox(height: 7),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _loadingData && dataset == null
                      ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _MetricVisualization(
                          widget: widget,
                          dataset: dataset ??
                              const MetricDataset(points: [], rows: []),
                          color: color,
                        ),
                ),
                if (!hasTitle && _canManage)
                  Positioned(
                    top: -10,
                    right: -8,
                    child: _compactMetricCardMenu(widget),
                  ),
              ],
            ),
          ),
          if (dataset?.truncated == true)
            const Align(
              alignment: Alignment.centerRight,
              child: Tooltip(
                message: 'Vista limitada a 5000 filas',
                child: Icon(Icons.info_outline, size: 16, color: _metricsMuted),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _compactMetricCardMenu(Map<String, dynamic> widget) =>
      PopupMenuButton<String>(
        tooltip: 'Configurar gráfico',
        onSelected: (value) {
          if (value == 'edit') _editWidget(widget);
          if (value == 'ignore_filters') _configureIgnoredFilters(widget);
          if (value == 'delete') _deleteWidget(widget);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Editar gráfico')),
          PopupMenuItem(
            value: 'ignore_filters',
            child: Text('Filtros que no afectan'),
          ),
          PopupMenuDivider(),
          PopupMenuItem(value: 'delete', child: Text('Eliminar')),
        ],
      );
}

// -----------------------------------------------------------------------------
// Editores
// -----------------------------------------------------------------------------

class _DashboardFiltersPanel extends StatelessWidget {
  const _DashboardFiltersPanel({
    required this.filters,
    required this.repository,
    required this.values,
    required this.onClose,
    required this.onAdd,
    required this.onRemove,
    required this.onUpdate,
    required this.onApply,
  });

  final List<Map<String, dynamic>> filters;
  final MetricsRepository repository;
  final Map<String, dynamic> values;
  final VoidCallback onClose;
  final VoidCallback onAdd;
  final Future<void> Function(Map<String, dynamic>) onRemove;
  final Future<void> Function(Map<String, dynamic>) onUpdate;
  final Future<void> Function(String, dynamic) onApply;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        child: SafeArea(
          left: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PanelHeader(
                icon: Icons.filter_alt_outlined,
                title: 'Filtros',
                onClose: onClose,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Los filtros afectan a todos los gráficos y a los que estén relacionados.',
                      style: TextStyle(color: _metricsMuted, height: 1.35),
                    ),
                    const SizedBox(height: 14),
                    if (filters.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Text(
                            'Aún no agregaste filtros.',
                            style: TextStyle(color: _metricsMuted),
                          ),
                        ),
                      ),
                    for (final filter in filters)
                      _DashboardFilterAccordion(
                        key: ValueKey(
                          '${filter['id']}-${filter['mode']}',
                        ),
                        filter: filter,
                        repository: repository,
                        initialValue: values[filter['id']?.toString()],
                        onApply: (value) =>
                            onApply(filter['id'].toString(), value),
                        onModeChanged: (mode) => onUpdate({
                          ...filter,
                          'mode': mode,
                        }),
                        onDelete: () => onRemove(filter),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Agregar filtro'),
                ),
              ),
            ],
          ),
        ),
      );
}

class _DashboardFilterAccordion extends StatefulWidget {
  const _DashboardFilterAccordion({
    super.key,
    required this.filter,
    required this.repository,
    required this.initialValue,
    required this.onApply,
    required this.onModeChanged,
    required this.onDelete,
  });

  final Map<String, dynamic> filter;
  final MetricsRepository repository;
  final dynamic initialValue;
  final Future<void> Function(dynamic) onApply;
  final Future<void> Function(String) onModeChanged;
  final Future<void> Function() onDelete;

  @override
  State<_DashboardFilterAccordion> createState() =>
      _DashboardFilterAccordionState();
}

class _DashboardFilterAccordionState extends State<_DashboardFilterAccordion> {
  final _search = TextEditingController();
  final _first = TextEditingController();
  final _second = TextEditingController();
  List<String>? _options;
  Set<String> _selected = <String>{};
  bool _loading = false;
  bool _applying = false;

  String get _table =>
      (widget.filter['table'] ?? widget.filter['tabla'])?.toString() ?? '';
  String get _field =>
      (widget.filter['field'] ?? widget.filter['campo'])?.toString() ?? '';
  String get _mode => widget.filter['mode']?.toString() ?? 'list';
  String get _type =>
      widget.filter['data_type']?.toString().toLowerCase() ?? '';
  bool get _isDate => RegExp(r'date|fecha|timestamp').hasMatch(_type);
  bool get _isNumeric =>
      RegExp(r'int|numeric|decimal|double|float|number|percent|porcentaje')
          .hasMatch(_type);

  Map<String, String> get _modes => _isDate
      ? const {
          'list': 'Lista',
          'range': 'Rango',
          'after': 'Después de',
          'before': 'Antes de',
        }
      : _isNumeric
          ? const {
              'list': 'Lista',
              'gt': 'Mayor que',
              'lt': 'Menor que',
              'between': 'Entre',
              'neq': 'No es',
            }
          : const {
              'list': 'Lista',
              'eq': 'Igual a',
              'contains': 'Contiene',
              'neq': 'No es igual a',
              'not_contains': 'No contiene',
            };

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    if (initial is List) _selected = initial.map((value) => '$value').toSet();
    if (initial is Map) {
      _first.text = '${initial['start'] ?? initial['min'] ?? ''}';
      _second.text = '${initial['end'] ?? initial['max'] ?? ''}';
    } else if (initial != null && initial is! List) {
      _first.text = '$initial';
    }
    _search.addListener(_refresh);
  }

  @override
  void dispose() {
    _search
      ..removeListener(_refresh)
      ..dispose();
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  Future<void> _loadOptions() async {
    if (_options != null || _loading || _table.isEmpty || _field.isEmpty) {
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await widget.repository
          .listDistinctValues(table: _table, field: _field);
      if (mounted) setState(() => _options = result);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    dynamic value;
    if (_mode == 'list') {
      value = _selected.toList();
    } else if (_mode == 'between' || _mode == 'range') {
      value = {'start': _first.text.trim(), 'end': _second.text.trim()};
    } else {
      value = _first.text.trim();
    }
    await widget.onApply(value);
    if (mounted) setState(() => _applying = false);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.filter['label']?.toString().trim().isNotEmpty == true
        ? widget.filter['label'].toString()
        : _field;
    final visible = (_options ?? const <String>[])
        .where((value) =>
            value.toLowerCase().contains(_search.text.trim().toLowerCase()))
        .toList();
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: const BorderSide(color: Color(0xFFDCE5EA)),
      ),
      child: ExpansionTile(
        onExpansionChanged: (expanded) {
          if (expanded && _mode == 'list') {
            unawaited(_loadOptions());
          }
        },
        leading: const Icon(Icons.filter_alt_outlined, color: _metricsTeal),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(_modes[_mode] ?? _mode),
        trailing: PopupMenuButton<String>(
          tooltip: 'Opciones del filtro',
          onSelected: (action) {
            if (action == 'delete') {
              unawaited(widget.onDelete());
            } else if (action.startsWith('mode:')) {
              unawaited(widget.onModeChanged(action.substring(5)));
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(enabled: false, child: Text('Mostrar como')),
            for (final entry in _modes.entries)
              PopupMenuItem(
                value: 'mode:${entry.key}',
                child: Row(children: [
                  Icon(entry.key == _mode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off),
                  const SizedBox(width: 8),
                  Text(entry.value),
                ]),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          if (_mode == 'list') ...[
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Buscar valor…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDCE5EA)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        CheckboxListTile(
                          dense: true,
                          value: visible.isNotEmpty &&
                              visible.every(_selected.contains),
                          title: const Text('Seleccionar todos'),
                          onChanged: (checked) => setState(() {
                            if (checked == true) {
                              _selected.addAll(visible);
                            } else {
                              _selected.removeAll(visible);
                            }
                          }),
                        ),
                        for (final option in visible)
                          CheckboxListTile(
                            dense: true,
                            value: _selected.contains(option),
                            title: Text(option,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            onChanged: (checked) => setState(() {
                              if (checked == true) {
                                _selected.add(option);
                              } else {
                                _selected.remove(option);
                              }
                            }),
                          ),
                      ],
                    ),
            ),
          ] else ...[
            TextField(
              controller: _first,
              keyboardType: _isNumeric
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : null,
              decoration: InputDecoration(
                labelText:
                    _mode == 'between' || _mode == 'range' ? 'Desde' : 'Valor',
                border: const OutlineInputBorder(),
              ),
            ),
            if (_mode == 'between' || _mode == 'range') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _second,
                keyboardType: _isNumeric
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Hasta',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _applying ? null : _apply,
              icon: _applying
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 17),
              label: const Text('Aplicar'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardFilterEditorPanel extends StatefulWidget {
  const _DashboardFilterEditorPanel({
    required this.sources,
    required this.onClose,
    required this.onSave,
  });

  final List<Map<String, dynamic>> sources;
  final VoidCallback onClose;
  final Future<void> Function(Map<String, dynamic>) onSave;

  @override
  State<_DashboardFilterEditorPanel> createState() =>
      _DashboardFilterEditorPanelState();
}

class _DashboardFilterEditorPanelState
    extends State<_DashboardFilterEditorPanel> {
  final _label = TextEditingController();
  String? _table;
  String? _field;
  bool _saving = false;

  List<Map<String, dynamic>> get _fields {
    for (final source in widget.sources) {
      if (source['tabla']?.toString() == _table) return _maps(source['campos']);
    }
    return const [];
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_table == null || _field == null || _saving) return;
    setState(() => _saving = true);
    final field = _fields.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['campo']?.toString() == _field,
          orElse: () => null,
        );
    await widget.onSave({
      'id': 'filter-${DateTime.now().microsecondsSinceEpoch}',
      'table': _table,
      'field': _field,
      'label': _label.text.trim().isEmpty ? _field : _label.text.trim(),
      'data_type': field?['tipo']?.toString() ?? 'text',
      'mode': 'list',
    });
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        left: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PanelHeader(
              icon: Icons.filter_alt_outlined,
              title: 'Agregar filtro',
              onClose: widget.onClose,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  const Text(
                    'Los filtros afectan a todos los gráficos y a los que estén relacionados.',
                    style: TextStyle(color: _metricsMuted, height: 1.35),
                  ),
                  const SizedBox(height: 18),
                  _SearchSelectionField(
                    label: 'Origen',
                    value: _table,
                    options: {
                      for (final source in widget.sources)
                        if ((source['tabla']?.toString() ?? '').isNotEmpty)
                          source['tabla'].toString():
                              source['nombre']?.toString() ??
                                  source['tabla'].toString(),
                    },
                    onChanged: (value) => setState(() {
                      _table = value;
                      _field = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  _SearchSelectionField(
                    key: ValueKey('filter-field-$_table'),
                    label: 'Campo',
                    value: _field,
                    options: {
                      for (final field in _fields)
                        if ((field['campo']?.toString() ?? '').isNotEmpty)
                          field['campo'].toString():
                              field['etiqueta']?.toString() ??
                                  field['campo'].toString(),
                    },
                    onChanged: (value) => setState(() => _field = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _label,
                    decoration: const InputDecoration(
                      labelText: 'Título visible',
                      hintText: 'Ejemplo: Campaña',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed:
                    _table == null || _field == null || _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: const Text('Agregar filtro'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricEditorPanel extends StatefulWidget {
  const _MetricEditorPanel({
    super.key,
    required this.dashboardId,
    required this.sources,
    required this.onClose,
    required this.onSave,
    this.initial,
  });

  final String dashboardId;
  final List<Map<String, dynamic>> sources;
  final Map<String, dynamic>? initial;
  final VoidCallback onClose;
  final Future<void> Function(Map<String, dynamic>) onSave;

  @override
  State<_MetricEditorPanel> createState() => _MetricEditorPanelState();
}

class _MetricEditorPanelState extends State<_MetricEditorPanel> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _subtitle;
  late final TextEditingController _axisX;
  late final TextEditingController _axisY;
  late final TextEditingController _axisY2;
  late final TextEditingController _legendTitle;
  late final TextEditingController _conditionValue;
  late final TextEditingController _alertValue;
  late final TextEditingController _textContent;
  int _tab = 0;
  String? _table;
  List<String> _dimensions = [];
  List<String> _values = [];
  List<String> _valuesY2 = [];
  List<String> _details = [];
  final Map<String, String> _valueAggregations = {};
  late Map<String, Map<String, String>> _axisAliases;
  late Map<String, dynamic> _appearance;
  List<String> _labelFields = ['*'];
  late Map<String, dynamic> _labelProfiles;
  String? _legend;
  String _chart = 'BAR';
  String _aggregation = 'COUNT';
  String _titleColor = '#142F49';
  String _fontFamily = 'Roboto';
  double _titleSize = 16;
  String _subtitleColor = '#63798B';
  double _subtitleSize = 12;
  bool _subtitleDivider = false;
  String _subtitleDividerColor = '#DCE7EC';
  double _subtitleDividerWidth = 1;
  String _background = '#FFFFFF';
  String _borderColor = '#DCE7EC';
  double _borderWidth = 1;
  double _borderRadius = 0;
  bool _shadow = true;
  String _seriesColor = '#14738A';
  double _seriesWidth = 2;
  String _seriesStyle = 'solid';
  double _barWidth = .72;
  bool _showLegend = true;
  String _legendPosition = 'bottom';
  double _legendSize = 12;
  String _conditionOperator = 'gt';
  String _conditionColor = '#C9536A';
  bool _trendline = false;
  String _trendColor = '#8659B5';
  String _trendStyle = 'solid';
  double _trendWidth = 1.5;
  double _trendOpacity = .9;
  String _alertColor = '#C9536A';
  String _alertStyle = 'dash';
  double _alertWidth = 1.6;
  double _alertOpacity = .85;
  List<Map<String, dynamic>> _alertLines = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _textShapes = <Map<String, dynamic>>[];
  String _textColor = '#142F49';
  String _textBackground = 'transparent';
  String _textAlignment = 'left';
  double _textSize = 24;
  int _width = 6;
  int _height = 4;
  bool _saving = false;

  static const _charts = <String, (String, IconData)>{
    'KPI': ('KPI', Icons.numbers_outlined),
    'BAR': ('Barras', Icons.bar_chart_outlined),
    'STACKED_BAR': ('Barras agrupadas', Icons.view_column_outlined),
    'LINE': ('Líneas', Icons.show_chart),
    'MULTI_LINE': ('Líneas múltiples', Icons.multiline_chart_rounded),
    'AREA': ('Área', Icons.area_chart_outlined),
    'PIE': ('Circular', Icons.pie_chart_outline),
    'DONUT': ('Anillo', Icons.donut_large_outlined),
    'SCATTER': ('Dispersión', Icons.scatter_plot_outlined),
    'FUNNEL': ('Embudo', Icons.filter_alt_outlined),
    'COMBO': ('Línea y columnas', Icons.stacked_line_chart_outlined),
    'TABLE': ('Tabla', Icons.table_chart_outlined),
    'TEXT': ('Texto y figuras', Icons.text_fields_rounded),
  };

  static const _textShapeTypes = <String, (String, IconData)>{
    'circle': ('Círculo', Icons.circle_outlined),
    'square': ('Cuadrado', Icons.square_outlined),
    'triangle': ('Triángulo', Icons.change_history_rounded),
    'diamond': ('Rombo', Icons.diamond_outlined),
    'star': ('Estrella', Icons.star_outline_rounded),
    'hexagon': ('Hexágono', Icons.hexagon_outlined),
    'arrow': ('Flecha', Icons.arrow_forward_rounded),
    'heart': ('Corazón', Icons.favorite_border_rounded),
    'line': ('Línea', Icons.horizontal_rule_rounded),
  };

  List<Map<String, dynamic>> get _fields {
    for (final source in widget.sources) {
      if (source['tabla']?.toString() == _table) return _maps(source['campos']);
    }
    return const [];
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial ?? const <String, dynamic>{};
    final config = _map(initial['configuracion']);
    _appearance = Map<String, dynamic>.from(config);
    final savedAliases = _map(config['axis_aliases']);
    _axisAliases = {
      for (final axis in const ['x', 'y', 'y2'])
        axis: savedAliases[axis] is Map
            ? Map<String, String>.fromEntries(
                (savedAliases[axis] as Map).entries.map(
                      (entry) => MapEntry(
                        '${entry.key}',
                        '${entry.value}'.trim(),
                      ),
                    ),
              )
            : <String, String>{},
    };
    _labelProfiles = _map(config['data_label_profiles']);
    _labelProfiles.putIfAbsent('*', () => <String, dynamic>{'visible': false});
    _title = TextEditingController(text: initial['titulo']?.toString() ?? '');
    _subtitle =
        TextEditingController(text: config['subtitle']?.toString() ?? '');
    _axisX = TextEditingController(text: config['axis_x']?.toString() ?? '');
    _axisY = TextEditingController(text: config['axis_y']?.toString() ?? '');
    _axisY2 = TextEditingController(text: config['axis_y2']?.toString() ?? '');
    _legendTitle =
        TextEditingController(text: config['legend_title']?.toString() ?? '');
    _conditionValue = TextEditingController(
        text: config['condition_value']?.toString() ?? '');
    _alertValue =
        TextEditingController(text: config['alert_value']?.toString() ?? '');
    _textContent =
        TextEditingController(text: config['text_content']?.toString() ?? '');
    _table = initial['tabla_origen']?.toString();
    _chart = initial['tipo_grafico']?.toString() ?? 'BAR';
    _aggregation = initial['agregacion']?.toString() ?? 'COUNT';
    _dimensions = (config['dimensions'] as List? ?? const [])
        .map((value) => value.toString())
        .toList();
    if (_dimensions.isEmpty && initial['campo_dimension'] != null) {
      _dimensions.add(initial['campo_dimension'].toString());
    }
    _values = (config['values'] as List? ?? const [])
        .map((value) => value.toString())
        .toList();
    if (_values.isEmpty && initial['campo_valor'] != null) {
      _values.add(initial['campo_valor'].toString());
    }
    _valuesY2 = (config['values_y2'] as List? ?? const [])
        .map((value) => value.toString())
        .toList();
    _details = (config['details'] as List? ?? const [])
        .map((value) => value.toString())
        .toList();
    _labelFields = (config['active_label_fields'] as List? ?? const ['*'])
        .map((value) => value.toString())
        .toList();
    if (_labelFields.isEmpty) _labelFields = ['*'];
    final savedAggregations = _map(config['value_aggregations']);
    for (final field in [..._values, ..._valuesY2]) {
      _valueAggregations[field] =
          savedAggregations[field]?.toString() ?? _aggregation;
    }
    _legend = initial['campo_serie']?.toString();
    _titleColor = config['title_color']?.toString() ?? '#142F49';
    _fontFamily = config['title_font']?.toString() ?? 'Roboto';
    _titleSize = (config['title_size'] as num?)?.toDouble() ?? 16;
    _subtitleColor = config['subtitle_color']?.toString() ?? '#63798B';
    _subtitleSize = (config['subtitle_size'] as num?)?.toDouble() ?? 12;
    _subtitleDivider = config['subtitle_divider'] == true;
    _subtitleDividerColor =
        config['subtitle_divider_color']?.toString() ?? '#DCE7EC';
    _subtitleDividerWidth =
        (config['subtitle_divider_width'] as num?)?.toDouble() ?? 1;
    _background = config['background_color']?.toString() ?? '#FFFFFF';
    _borderColor = config['border_color']?.toString() ?? '#DCE7EC';
    _borderWidth = (config['border_width'] as num?)?.toDouble() ?? 1;
    _borderRadius = metricsChartBorderRadius(
      config,
      legacyDefault: widget.initial == null ? 0 : 18,
    );
    _shadow = config['shadow'] != false;
    _seriesColor = config['color']?.toString() ?? '#14738A';
    _seriesWidth = (config['series_width'] as num?)?.toDouble() ?? 2;
    _seriesStyle = config['series_style']?.toString() ?? 'solid';
    _barWidth = (config['bar_width'] as num?)?.toDouble() ?? .72;
    _showLegend = config['show_legend'] != false;
    _legendPosition = config['legend_position']?.toString() ?? 'bottom';
    _legendSize = (config['legend_size'] as num?)?.toDouble() ?? 12;
    _conditionOperator = config['condition_operator']?.toString() ?? 'gt';
    _conditionColor = config['condition_color']?.toString() ?? '#C9536A';
    _trendline = config['trendline'] == true;
    _trendColor = config['trend_color']?.toString() ?? '#8659B5';
    _trendStyle = config['trend_style']?.toString() ?? 'solid';
    _trendWidth = (config['trend_width'] as num?)?.toDouble() ?? 1.5;
    _trendOpacity = (config['trend_opacity'] as num?)?.toDouble() ?? .9;
    _alertColor = config['alert_color']?.toString() ?? '#C9536A';
    _alertStyle = config['alert_style']?.toString() ?? 'dash';
    _alertWidth = (config['alert_width'] as num?)?.toDouble() ?? 1.6;
    _alertOpacity = (config['alert_opacity'] as num?)?.toDouble() ?? .85;
    _alertLines = _maps(config['alert_lines']);
    _textShapes = _maps(config['text_shapes']);
    _textColor = config['text_color']?.toString() ?? '#142F49';
    _textBackground = config['text_background']?.toString() ?? 'transparent';
    _textAlignment = config['text_alignment']?.toString() ?? 'left';
    _textSize = (config['text_size'] as num?)?.toDouble() ?? 24;
    if (_alertLines.isEmpty && _alertValue.text.trim().isNotEmpty) {
      _alertLines = [
        {
          'label': 'Referencia',
          'value': _alertValue.text.trim(),
          'color': _alertColor,
          'style': _alertStyle,
          'width': _alertWidth,
          'opacity': _alertOpacity,
        }
      ];
    }
    _width = (initial['ancho'] as num?)?.toInt() ?? 6;
    _height = (initial['alto'] as num?)?.toInt() ?? 4;
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _axisX.dispose();
    _axisY.dispose();
    _axisY2.dispose();
    _legendTitle.dispose();
    _conditionValue.dispose();
    _alertValue.dispose();
    _textContent.dispose();
    super.dispose();
  }

  Map<String, dynamic> _payload() {
    final savedConfiguration = _map(widget.initial?['configuracion'])
      ..remove('border_style');
    return {
      if (widget.initial?['id'] != null) 'id': widget.initial!['id'],
      'dashboard_id': widget.dashboardId,
      'titulo': _title.text.trim(),
      'descripcion': widget.initial?['descripcion'] ?? '',
      'tabla_origen': _table,
      'campo_dimension': _dimensions.isEmpty ? null : _dimensions.first,
      'campo_valor': _values.isEmpty ? null : _values.first,
      'campo_serie': _legend,
      'tipo_grafico': _chart,
      'agregacion': _aggregation,
      'filtros': widget.initial?['filtros'] ?? const [],
      'configuracion': {
        ...savedConfiguration,
        ..._appearance,
        'dimensions': _dimensions,
        'values': _values,
        'values_y2': _valuesY2,
        'details': _details,
        'value_aggregations': _valueAggregations,
        'axis_aliases': _axisAliases,
        'active_label_fields': _labelFields,
        'data_label_profiles': _labelProfiles,
        'title_color': _titleColor,
        'title_font': _fontFamily,
        'title_size': _titleSize,
        'subtitle': _subtitle.text.trim(),
        'subtitle_color': _subtitleColor,
        'subtitle_size': _subtitleSize,
        'subtitle_divider': _subtitleDivider,
        'subtitle_divider_color': _subtitleDividerColor,
        'subtitle_divider_width': _subtitleDividerWidth,
        'background_color': _background,
        'border_color': _borderColor,
        'border_width': _borderWidth,
        'border_radius': _borderRadius,
        'shadow': _shadow,
        'color': _seriesColor,
        'series_width': _seriesWidth,
        'series_style': _seriesStyle,
        'bar_width': _barWidth,
        'axis_x': _axisX.text.trim(),
        'axis_y': _axisY.text.trim(),
        'axis_y2': _axisY2.text.trim(),
        'show_legend': _showLegend,
        'legend_title': _legendTitle.text.trim(),
        'legend_position': _legendPosition,
        'legend_size': _legendSize,
        'condition_operator': _conditionOperator,
        'condition_value': _conditionValue.text.trim(),
        'condition_color': _conditionColor,
        'trendline': _trendline,
        'trend_color': _trendColor,
        'trend_style': _trendStyle,
        'trend_width': _trendWidth,
        'trend_opacity': _trendOpacity,
        'alert_value': _alertValue.text.trim(),
        'alert_color': _alertColor,
        'alert_style': _alertStyle,
        'alert_width': _alertWidth,
        'alert_opacity': _alertOpacity,
        'alert_lines': _alertLines,
        'text_content': _textContent.text.trim(),
        'text_shapes': _textShapes,
        'text_color': _textColor,
        'text_background': _textBackground,
        'text_alignment': _textAlignment,
        'text_size': _textSize,
      },
      'ancho': _width,
      'alto': _height,
    };
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_table == null && _chart != 'TEXT') {
      setState(() => _tab = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una tabla de origen.')),
      );
      return;
    }
    if (!(_form.currentState?.validate() ?? true)) return;
    setState(() => _saving = true);
    await widget.onSave(_payload());
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        left: false,
        child: Column(
          children: [
            _PanelHeader(
              icon: widget.initial == null
                  ? Icons.add_chart_outlined
                  : Icons.edit_note_outlined,
              title:
                  widget.initial == null ? 'Crear gráfico' : 'Editar gráfico',
              onClose: widget.onClose,
            ),
            Container(
              color: const Color(0xFFF4F8FA),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _editorTab(Icons.dataset_outlined, 'Datos', 0),
                  _editorTab(Icons.format_paint_outlined, 'Apariencia', 1),
                  _editorTab(Icons.trending_up_outlined, 'Analítica', 2),
                ],
              ),
            ),
            Expanded(
              child: Form(
                key: _form,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: ListView(
                    key: ValueKey(_tab),
                    padding: const EdgeInsets.all(16),
                    children: _tab == 0
                        ? _dataFields()
                        : _tab == 1
                            ? _appearanceFields()
                            : _analyticsFields(),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onClose,
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editorTab(IconData icon, String tooltip, int value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: IconButton.filledTonal(
          tooltip: tooltip,
          onPressed: () => setState(() => _tab = value),
          style: IconButton.styleFrom(
            backgroundColor:
                _tab == value ? _metricsTeal : const Color(0xFFE7EEF2),
            foregroundColor: _tab == value ? Colors.white : _metricsNavy,
          ),
          icon: Icon(icon),
        ),
      );

  List<Widget> _dataFields() => [
        const _PanelSectionTitle('Datos del gráfico'),
        _chartTypeSelector(),
        if (_chart != 'TEXT') ...[
          const SizedBox(height: 14),
          _sourceSelector(),
          const SizedBox(height: 16),
          _axisBuilder(
            title: 'Eje X',
            aliasAxis: 'x',
            values: _dimensions,
            onAdd: (value) => setState(() => _dimensions.add(value)),
          ),
          const SizedBox(height: 14),
          _axisBuilder(
            title: 'Eje Y',
            aliasAxis: 'y',
            values: _values,
            onAdd: (value) => setState(() {
              _values.add(value);
              _valueAggregations[value] = _aggregation;
            }),
            valueAxis: true,
          ),
          const SizedBox(height: 14),
          _axisBuilder(
            title: 'Eje Y2',
            aliasAxis: 'y2',
            values: _valuesY2,
            onAdd: (value) => setState(() {
              _valuesY2.add(value);
              _valueAggregations[value] = _aggregation;
            }),
            valueAxis: true,
            secondaryAxis: true,
          ),
          const SizedBox(height: 14),
          _singleFieldBuilder(
            title: 'Leyenda',
            value: _legend,
            onChanged: (value) => setState(() => _legend = value),
          ),
          const SizedBox(height: 14),
          _axisBuilder(
            title: 'Detalle',
            values: _details,
            onAdd: (value) => setState(() => _details.add(value)),
          ),
        ] else ...[
          const SizedBox(height: 14),
          _textObjectFields(),
        ],
      ];

  Widget _textObjectFields() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _textContent,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Contenido de texto',
              hintText: 'Escribe un título, explicación o nota del dashboard',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _alignmentPicker(
            value: _textAlignment,
            onChanged: (value) => setState(() => _textAlignment = value),
          ),
          const SizedBox(height: 12),
          _numberSlider(
            'Tamaño del texto ${_textSize.round()} px',
            _textSize,
            9,
            72,
            (value) => setState(() => _textSize = value),
          ),
          const SizedBox(height: 10),
          _colorEditor(
            'Color del texto',
            _textColor,
            (value) => setState(() => _textColor = value),
          ),
          const SizedBox(height: 10),
          _colorEditor(
            'Fondo del objeto',
            _textBackground,
            (value) => setState(() => _textBackground = value),
          ),
          const Divider(height: 28),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Figuras',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Agregar figura',
                onPressed: _addTextShape,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          if (_textShapes.isEmpty)
            const Text(
              'Puedes acompañar el texto con círculos, triángulos o líneas.',
              style: TextStyle(color: _metricsMuted),
            )
          else
            ..._textShapes.asMap().entries.map((entry) {
              final shape = entry.value;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _textShapeTypes[shape['type']?.toString()]?.$2 ??
                      Icons.circle_outlined,
                  color: _color(shape['color'], _metricsTeal),
                ),
                title: Text(
                    _textShapeTypes[shape['type']?.toString()]?.$1 ?? 'Figura'),
                subtitle: Text('${shape['size'] ?? 40} px'),
                trailing: IconButton(
                  tooltip: 'Quitar figura',
                  onPressed: () =>
                      setState(() => _textShapes.removeAt(entry.key)),
                  icon: const Icon(Icons.delete_outline),
                ),
              );
            }),
        ],
      );

  Future<void> _addTextShape() async {
    var type = 'circle';
    var color = '#14738A';
    var borderColor = 'transparent';
    var borderWidth = 0.0;
    var size = 40.0;
    const palette = <String>[
      'transparent',
      '#D32F2F',
      '#F57C00',
      '#FBC02D',
      '#388E3C',
      '#14738A',
      '#039BE5',
      '#1976D2',
      '#E91E63',
      '#8659B5',
      '#142F49',
      '#000000',
      '#FFFFFF',
    ];
    Widget colorPalette(
      String selected,
      ValueChanged<String> onSelected,
    ) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: palette.map((candidate) {
          final active = candidate == selected;
          return Tooltip(
            message: candidate,
            child: InkWell(
              onTap: () => onSelected(candidate),
              customBorder: const CircleBorder(),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _colorFromHex(candidate),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: active ? _metricsNavy : const Color(0xFFCBD8DE),
                    width: active ? 3 : 1,
                  ),
                ),
                child: candidate == 'transparent'
                    ? const Icon(Icons.block, size: 18, color: _metricsMuted)
                    : null,
              ),
            ),
          );
        }).toList(),
      );
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Agregar figura'),
          content: SizedBox(
            width: 390,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Figura',
                    border: OutlineInputBorder(),
                  ),
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: _textShapeTypes.entries.map((entry) {
                      return Tooltip(
                        message: entry.value.$1,
                        child: IconButton.filledTonal(
                          isSelected: type == entry.key,
                          onPressed: () =>
                              setDialogState(() => type = entry.key),
                          icon: Icon(entry.value.$2),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Color de relleno',
                    border: OutlineInputBorder(),
                  ),
                  child: colorPalette(
                    color,
                    (value) => setDialogState(() => color = value),
                  ),
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Color del borde',
                    border: OutlineInputBorder(),
                  ),
                  child: colorPalette(
                    borderColor,
                    (value) => setDialogState(() => borderColor = value),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Tamaño'),
                    Expanded(
                      child: Slider(
                        value: size,
                        min: 12,
                        max: 140,
                        divisions: 32,
                        label: '${size.round()} px',
                        onChanged: (value) =>
                            setDialogState(() => size = value),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Borde'),
                    Expanded(
                      child: Slider(
                        value: borderWidth,
                        min: 0,
                        max: 12,
                        divisions: 24,
                        label: '${borderWidth.toStringAsFixed(1)} px',
                        onChanged: (value) =>
                            setDialogState(() => borderWidth = value),
                      ),
                    ),
                  ],
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
              onPressed: () => Navigator.pop(dialogContext, {
                'type': type,
                'color': color,
                'size': size,
                'border_color': borderColor,
                'border_width': borderWidth,
              }),
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _textShapes.add(result));
    }
  }

  List<Widget> _appearanceFields() => [
        const _PanelSectionTitle('Formato visual'),
        _appearanceAccordion(
          title: 'Título del gráfico',
          icon: Icons.title_rounded,
          initiallyExpanded: true,
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                prefixIcon: Icon(Icons.edit_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            _colorEditor(
                'Color del texto', _titleColor, (value) => _titleColor = value),
            _colorEditor(
              'Fondo del título',
              _styleString('title_background', '#FFFFFF'),
              (value) => _setStyle('title_background', value),
            ),
            _fontPicker(
              label: 'Tipo de letra',
              value: _fontFamily,
              onChanged: (value) => setState(() => _fontFamily = value),
            ),
            _numberSlider(
              'Tamaño ${_titleSize.round()} px',
              _titleSize,
              9,
              44,
              (value) => setState(() => _titleSize = value),
            ),
            _alignmentPicker(
              value: _styleString('title_alignment', 'left'),
              onChanged: (value) => _setStyle('title_alignment', value),
            ),
            _numberSlider(
              'Borde del título ${_styleDouble('title_border_width', 0).toStringAsFixed(1)} px',
              _styleDouble('title_border_width', 0),
              0,
              8,
              (value) => _setStyle('title_border_width', value),
            ),
            _colorEditor(
              'Color del borde del título',
              _styleString('title_border_color', '#DCE7EC'),
              (value) => _setStyle('title_border_color', value),
            ),
          ],
        ),
        _appearanceAccordion(
          title: 'Subtítulo',
          icon: Icons.subtitles_outlined,
          children: [
            TextField(
              controller: _subtitle,
              decoration: const InputDecoration(
                labelText: 'Texto del subtítulo',
                hintText: 'Opcional',
                border: OutlineInputBorder(),
              ),
            ),
            _colorEditor('Color del subtítulo', _subtitleColor,
                (value) => _subtitleColor = value),
            _numberSlider(
              'Tamaño ${_subtitleSize.round()} px',
              _subtitleSize,
              8,
              32,
              (value) => setState(() => _subtitleSize = value),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _subtitleDivider,
              title: const Text('Línea divisoria debajo'),
              onChanged: (value) => setState(() => _subtitleDivider = value),
            ),
            if (_subtitleDivider) ...[
              _colorEditor(
                'Color de la división',
                _subtitleDividerColor,
                (value) => _subtitleDividerColor = value,
              ),
              _numberSlider(
                'Grosor ${_subtitleDividerWidth.toStringAsFixed(1)} px',
                _subtitleDividerWidth,
                .5,
                8,
                (value) => setState(() => _subtitleDividerWidth = value),
              ),
            ],
          ],
        ),
        _appearanceAccordion(
          title: 'Propiedades del gráfico',
          icon: Icons.crop_square_rounded,
          children: [
            _colorEditor(
                'Color de fondo', _background, (value) => _background = value),
            _colorEditor('Color de borde', _borderColor,
                (value) => _borderColor = value),
            _numberSlider(
              'Borde ${_borderWidth.toStringAsFixed(1)} px',
              _borderWidth,
              0,
              8,
              (value) => setState(() => _borderWidth = value),
            ),
            _numberSlider(
              'Borde redondeado ${_borderRadius.round()} px',
              _borderRadius,
              0,
              48,
              (value) => setState(() => _borderRadius = value),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.blur_on_outlined),
              value: _shadow,
              title: const Text('Sombreado'),
              onChanged: (value) => setState(() => _shadow = value),
            ),
          ],
        ),
        _appearanceAccordion(
          title: _chart.contains('BAR') || _chart == 'COMBO'
              ? 'Barras y líneas'
              : 'Líneas y series',
          icon: Icons.show_chart_rounded,
          children: [
            _colorEditor('Color de la serie', _seriesColor,
                (value) => _seriesColor = value),
            _numberSlider(
              'Grosor ${_seriesWidth.toStringAsFixed(1)} px',
              _seriesWidth,
              1,
              8,
              (value) => setState(() => _seriesWidth = value),
            ),
            if (_chart.contains('BAR') || _chart == 'COMBO')
              _numberSlider(
                'Ancho de barras ${(_barWidth * 100).round()}%',
                _barWidth,
                .25,
                1,
                (value) => setState(() => _barWidth = value),
              ),
          ],
        ),
        _axisAppearance(
          title: 'Eje X (valores)',
          keyPrefix: 'x',
          titleController: _axisX,
        ),
        _axisAppearance(
          title: 'Eje Y (valores)',
          keyPrefix: 'y',
          titleController: _axisY,
          showRange: true,
        ),
        _axisAppearance(
          title: 'Eje Y2 (valores)',
          keyPrefix: 'y2',
          titleController: _axisY2,
          showRange: true,
        ),
        _dataLabelsAppearance(),
        _appearanceAccordion(
          title: 'Leyenda',
          icon: Icons.list_alt_rounded,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _showLegend,
              title: const Text('Visible'),
              onChanged: (value) => setState(() => _showLegend = value),
            ),
            TextField(
              controller: _legendTitle,
              decoration: const InputDecoration(
                labelText: 'Título de la leyenda',
                prefixIcon: Icon(Icons.title_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 9),
            _compactDropdown(
              label: 'Posición',
              value: _legendPosition,
              options: const {
                'top': 'Arriba',
                'bottom': 'Abajo',
                'left': 'Izquierda',
                'right': 'Derecha',
              },
              onChanged: (value) => setState(() => _legendPosition = value),
            ),
            _numberSlider(
              'Tamaño ${_legendSize.round()} px',
              _legendSize,
              8,
              24,
              (value) => setState(() => _legendSize = value),
            ),
          ],
        ),
      ];

  String _styleString(String key, String fallback) =>
      _appearance[key]?.toString() ?? fallback;

  double _styleDouble(String key, double fallback) =>
      (_appearance[key] as num?)?.toDouble() ?? fallback;

  bool _styleBool(String key, bool fallback) =>
      _appearance[key] is bool ? _appearance[key] == true : fallback;

  void _setStyle(String key, dynamic value) => setState(() {
        _appearance[key] = value;
      });

  Widget _appearanceAccordion({
    required String title,
    required IconData icon,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFDCE5EA)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: Icon(icon, color: _metricsTeal, size: 21),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(height: 10),
            children[index],
          ],
        ],
      ),
    );
  }

  Widget _fontPicker({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    const fonts = [
      'Roboto',
      'Arial',
      'Montserrat',
      'Poppins',
      'Inter',
      'Lato',
      'Open Sans',
      'Nunito',
      'Merriweather',
      'Georgia',
      'Serif',
    ];
    return DropdownButtonFormField<String>(
      initialValue: fonts.contains(value) ? value : 'Roboto',
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.font_download_outlined),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: fonts
          .map((font) => DropdownMenuItem(value: font, child: Text(font)))
          .toList(),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }

  Widget _alignmentPicker({
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Row(
      children: [
        const Icon(Icons.format_align_left_rounded,
            size: 20, color: _metricsMuted),
        const SizedBox(width: 10),
        const Expanded(
          child:
              Text('Alineación', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
                value: 'left',
                icon: Icon(Icons.format_align_left_rounded),
                tooltip: 'Izquierda'),
            ButtonSegment(
                value: 'center',
                icon: Icon(Icons.format_align_center_rounded),
                tooltip: 'Centro'),
            ButtonSegment(
                value: 'right',
                icon: Icon(Icons.format_align_right_rounded),
                tooltip: 'Derecha'),
          ],
          selected: {value},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ],
    );
  }

  Widget _compactDropdown({
    required String label,
    required String value,
    required Map<String, String> options,
    required ValueChanged<String> onChanged,
    IconData icon = Icons.tune_rounded,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: options.containsKey(value) ? value : options.keys.first,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: options.entries
          .map((entry) =>
              DropdownMenuItem(value: entry.key, child: Text(entry.value)))
          .toList(),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }

  Widget _axisAppearance({
    required String title,
    required String keyPrefix,
    required TextEditingController titleController,
    bool showRange = false,
  }) {
    return _appearanceAccordion(
      title: title,
      icon: keyPrefix == 'x'
          ? Icons.horizontal_rule_rounded
          : Icons.vertical_align_center_rounded,
      children: [
        if (showRange)
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: _styleString('${keyPrefix}_min', ''),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Rango mínimo',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) =>
                      _appearance['${keyPrefix}_min'] = value.trim(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: _styleString('${keyPrefix}_max', ''),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Rango máximo',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) =>
                      _appearance['${keyPrefix}_max'] = value.trim(),
                ),
              ),
            ],
          ),
        _fontPicker(
          label: 'Fuente de valores',
          value: _styleString('${keyPrefix}_font', 'Roboto'),
          onChanged: (value) => _setStyle('${keyPrefix}_font', value),
        ),
        _numberSlider(
          'Tamaño de valores ${_styleDouble('${keyPrefix}_size', 11).round()} px',
          _styleDouble('${keyPrefix}_size', 11),
          7,
          28,
          (value) => _setStyle('${keyPrefix}_size', value),
        ),
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Negrita',
              isSelected: _styleBool('${keyPrefix}_bold', false),
              onPressed: () => _setStyle(
                  '${keyPrefix}_bold', !_styleBool('${keyPrefix}_bold', false)),
              icon: const Icon(Icons.format_bold_rounded),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Subrayado',
              isSelected: _styleBool('${keyPrefix}_underline', false),
              onPressed: () => _setStyle('${keyPrefix}_underline',
                  !_styleBool('${keyPrefix}_underline', false)),
              icon: const Icon(Icons.format_underlined_rounded),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Text('Estilo de los valores')),
          ],
        ),
        _colorEditor(
          'Color de valores',
          _styleString('${keyPrefix}_color', '#63798B'),
          (value) => _setStyle('${keyPrefix}_color', value),
        ),
        TextField(
          controller: titleController,
          decoration: const InputDecoration(
            labelText: 'Título del eje',
            prefixIcon: Icon(Icons.title_rounded),
            border: OutlineInputBorder(),
          ),
        ),
        _colorEditor(
          'Color del título',
          _styleString('${keyPrefix}_title_color', '#142F49'),
          (value) => _setStyle('${keyPrefix}_title_color', value),
        ),
        _numberSlider(
          'Tamaño del título ${_styleDouble('${keyPrefix}_title_size', 12).round()} px',
          _styleDouble('${keyPrefix}_title_size', 12),
          8,
          30,
          (value) => _setStyle('${keyPrefix}_title_size', value),
        ),
        _fontPicker(
          label: 'Fuente del título',
          value: _styleString('${keyPrefix}_title_font', 'Roboto'),
          onChanged: (value) => _setStyle('${keyPrefix}_title_font', value),
        ),
      ],
    );
  }

  String get _labelProfileKey {
    if (_labelFields.contains('*') || _labelFields.isEmpty) return '*';
    final fields = [..._labelFields]..sort();
    return fields.join('|');
  }

  Map<String, dynamic> _activeLabelProfile() {
    final existing = _labelProfiles[_labelProfileKey];
    if (existing is Map) return Map<String, dynamic>.from(existing);
    return <String, dynamic>{};
  }

  void _setLabelProfile(String key, dynamic value) {
    setState(() {
      final profile = _activeLabelProfile()..[key] = value;
      _labelProfiles[_labelProfileKey] = profile;
    });
  }

  Widget _dataLabelsAppearance() {
    final fields = <String>{..._values, ..._valuesY2}.toList();
    final profile = _activeLabelProfile();
    final conditions = _maps(profile['conditions']);
    final visible = profile['visible'] != false;
    return _appearanceAccordion(
      title: 'Valores de datos',
      icon: Icons.pin_outlined,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Valor', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FilterChip(
              selected: _labelFields.contains('*'),
              label: const Text('Todos'),
              onSelected: (_) => setState(() => _labelFields = ['*']),
            ),
            ...fields.map((field) => FilterChip(
                  selected: _labelFields.contains(field),
                  label: Text(_fieldLabel(field)),
                  onSelected: (selected) => setState(() {
                    _labelFields.remove('*');
                    if (selected) {
                      _labelFields.add(field);
                    } else {
                      _labelFields.remove(field);
                    }
                    if (_labelFields.isEmpty) _labelFields = ['*'];
                  }),
                )),
          ],
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: visible,
          title: const Text('Visible'),
          secondary: Icon(visible
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined),
          onChanged: (value) => _setLabelProfile('visible', value),
        ),
        _compactDropdown(
          label: 'Posición',
          value: profile['position']?.toString() ?? 'above',
          options: const {
            'above': 'Encima',
            'below': 'Debajo',
            'center': 'Centro',
            'inside': 'Interior',
          },
          icon: Icons.open_with_rounded,
          onChanged: (value) => _setLabelProfile('position', value),
        ),
        _numberSlider(
          'Espacio ${((profile['padding'] as num?)?.toDouble() ?? 4).round()} px',
          (profile['padding'] as num?)?.toDouble() ?? 4,
          0,
          24,
          (value) => _setLabelProfile('padding', value),
        ),
        _fontPicker(
          label: 'Tipo de fuente',
          value: profile['font']?.toString() ?? 'Roboto',
          onChanged: (value) => _setLabelProfile('font', value),
        ),
        _colorEditor(
          'Color del valor',
          profile['color']?.toString() ?? '#142F49',
          (value) => _setLabelProfile('color', value),
        ),
        _colorEditor(
          'Fondo del valor',
          profile['background']?.toString() ?? '#FFFFFF',
          (value) => _setLabelProfile('background', value),
        ),
        _numberSlider(
          'Tamaño ${((profile['size'] as num?)?.toDouble() ?? 11).round()} px',
          (profile['size'] as num?)?.toDouble() ?? 11,
          7,
          30,
          (value) => _setLabelProfile('size', value),
        ),
        _numberSlider(
          'Transparencia ${(((profile['opacity'] as num?)?.toDouble() ?? 1) * 100).round()}%',
          (profile['opacity'] as num?)?.toDouble() ?? 1,
          0,
          1,
          (value) => _setLabelProfile('opacity', value),
        ),
        _numberSlider(
          'Decimales ${((profile['decimals'] as num?)?.toDouble() ?? 0).round()}',
          (profile['decimals'] as num?)?.toDouble() ?? 0,
          0,
          6,
          (value) => _setLabelProfile('decimals', value.round()),
        ),
        _compactDropdown(
          label: 'Unidades',
          value: profile['units']?.toString() ?? 'none',
          options: const {
            'none': 'Ninguno',
            'thousands': 'Miles',
            'millions': 'Millones',
            'billions': 'Billones',
          },
          icon: Icons.numbers_rounded,
          onChanged: (value) => _setLabelProfile('units', value),
        ),
        const Divider(),
        Row(
          children: [
            const Expanded(
              child: Text('Colores condicionales',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            IconButton.filledTonal(
              tooltip: 'Agregar condición',
              onPressed: _addDataLabelCondition,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        if (conditions.isEmpty)
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Sin condiciones. Se usará el color general.',
                style: TextStyle(color: _metricsMuted)),
          )
        else
          ...conditions.asMap().entries.map((entry) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 10,
                  backgroundColor:
                      _color(entry.value['color']?.toString(), _metricsTeal),
                ),
                title: Text(
                    '${_conditionLabel(entry.value['operator']?.toString())} ${entry.value['value'] ?? ''}'),
                trailing: IconButton(
                  tooltip: 'Eliminar condición',
                  onPressed: () {
                    final updated = [...conditions]..removeAt(entry.key);
                    _setLabelProfile('conditions', updated);
                  },
                  icon: const Icon(Icons.delete_outline, size: 19),
                ),
              )),
      ],
    );
  }

  String _conditionLabel(String? operator) =>
      const {
        'gt': 'Mayor que',
        'gte': 'Mayor o igual que',
        'lt': 'Menor que',
        'lte': 'Menor o igual que',
        'between': 'Entre',
        'eq': 'Igual a',
        'neq': 'Diferente de',
        'contains': 'Contiene',
      }[operator] ??
      'Condición';

  Future<void> _addDataLabelCondition() async {
    var operator = 'gt';
    final valueController = TextEditingController();
    final colorController = TextEditingController(text: '#C9536A');
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nueva condición de color'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: operator,
                  decoration: const InputDecoration(
                    labelText: 'Se cumple cuando',
                    border: OutlineInputBorder(),
                  ),
                  items: const {
                    'gt': 'Mayor que',
                    'gte': 'Mayor o igual que',
                    'lt': 'Menor que',
                    'lte': 'Menor o igual que',
                    'between': 'Está entre',
                    'eq': 'Es igual a',
                    'neq': 'Es diferente de',
                    'contains': 'Contiene',
                  }
                      .entries
                      .map((entry) => DropdownMenuItem(
                          value: entry.key, child: Text(entry.value)))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => operator = value ?? operator),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: valueController,
                  decoration: InputDecoration(
                    labelText: operator == 'between'
                        ? 'Valores (mínimo, máximo)'
                        : 'Valor',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: colorController,
                  decoration: const InputDecoration(
                    labelText: 'Color hexadecimal o RGBA',
                    prefixIcon: Icon(Icons.palette_outlined),
                    border: OutlineInputBorder(),
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
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'operator': operator,
                'value': valueController.text.trim(),
                'color': colorController.text.trim(),
              }),
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
    valueController.dispose();
    colorController.dispose();
    if (result == null || !mounted) return;
    final profile = _activeLabelProfile();
    final conditions = _maps(profile['conditions'])..add(result);
    _setLabelProfile('conditions', conditions);
  }

  List<Widget> _analyticsFields() => [
        _PanelSectionTitle('Tendencia y líneas de referencia'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _trendline,
          title: const Text('Agregar línea de tendencia'),
          subtitle: const Text('Calculada sobre los valores del gráfico.'),
          onChanged: (value) => setState(() => _trendline = value),
        ),
        if (_trendline) ...[
          _colorEditor('Color de tendencia', _trendColor,
              (value) => _trendColor = value),
          const SizedBox(height: 9),
          DropdownButtonFormField<String>(
            initialValue: _trendStyle,
            decoration: const InputDecoration(
              labelText: 'Tipo de línea de tendencia',
              border: OutlineInputBorder(),
            ),
            items: const {
              'solid': 'Continua',
              'dash': 'Guiones',
              'dot': 'Puntos',
            }
                .entries
                .map((entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ))
                .toList(),
            onChanged: (value) =>
                setState(() => _trendStyle = value ?? 'solid'),
          ),
          const SizedBox(height: 8),
          _numberSlider(
            'Grosor de tendencia ${_trendWidth.toStringAsFixed(1)} px',
            _trendWidth,
            .5,
            6,
            (value) => setState(() => _trendWidth = value),
          ),
          _numberSlider(
            'Opacidad ${(_trendOpacity * 100).round()}%',
            _trendOpacity,
            .1,
            1,
            (value) => setState(() => _trendOpacity = value),
          ),
        ],
        const SizedBox(height: 18),
        _alertLinesEditor(),
      ];

  Widget _alertLinesEditor() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PanelSectionTitle('Líneas de alerta'),
          if (_alertLines.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'No hay líneas configuradas. Puedes agregar varias referencias independientes.',
                style: TextStyle(color: _metricsMuted),
              ),
            ),
          for (var index = 0; index < _alertLines.length; index++)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 7),
              child: ListTile(
                leading: Container(
                  width: 30,
                  height: 4,
                  color: _color(
                    _alertLines[index]['color'],
                    const Color(0xFFC9536A),
                  ),
                ),
                title: Text(
                  _alertLines[index]['label']?.toString().trim().isNotEmpty ==
                          true
                      ? _alertLines[index]['label'].toString()
                      : 'Referencia ${index + 1}',
                ),
                subtitle: Text(
                  'Valor ${_alertLines[index]['value']} · ${_alertLines[index]['style'] ?? 'dash'}',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'edit') _editAlertLine(index);
                    if (action == 'delete') {
                      setState(() => _alertLines.removeAt(index));
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                  ],
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _editAlertLine,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Agregar línea de alerta'),
          ),
        ],
      );

  Future<void> _editAlertLine([int? index]) async {
    final initial = index == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(_alertLines[index]);
    final label = TextEditingController(text: initial['label']?.toString());
    final value = TextEditingController(text: initial['value']?.toString());
    var color = initial['color']?.toString() ?? '#C9536A';
    var style = initial['style']?.toString() ?? 'dash';
    var width = (initial['width'] as num?)?.toDouble() ?? 1.6;
    var opacity = (initial['opacity'] as num?)?.toDouble() ?? .85;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(index == null ? 'Nueva línea' : 'Editar línea'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: label,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    hintText: 'Ejemplo: Límite superior',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: value,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Valor',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: style,
                  decoration: const InputDecoration(
                    labelText: 'Estilo',
                    border: OutlineInputBorder(),
                  ),
                  items: const {
                    'solid': 'Continua',
                    'dash': 'Guiones',
                    'dot': 'Puntos',
                  }
                      .entries
                      .map((entry) => DropdownMenuItem(
                          value: entry.key, child: Text(entry.value)))
                      .toList(),
                  onChanged: (next) =>
                      setDialogState(() => style = next ?? 'dash'),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: const [
                    '#C9536A',
                    '#E08A35',
                    '#14738A',
                    '#2F9D75',
                    '#8659B5'
                  ]
                      .map((candidate) => ChoiceChip(
                            selected: candidate == color,
                            avatar: CircleAvatar(
                              backgroundColor: _colorFromHex(candidate),
                            ),
                            label: Text(candidate),
                            onSelected: (_) =>
                                setDialogState(() => color = candidate),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  const Text('Grosor'),
                  Expanded(
                    child: Slider(
                      value: width,
                      min: .5,
                      max: 6,
                      onChanged: (next) => setDialogState(() => width = next),
                    ),
                  ),
                  Text(width.toStringAsFixed(1)),
                ]),
                Row(children: [
                  const Text('Opacidad'),
                  Expanded(
                    child: Slider(
                      value: opacity,
                      min: .1,
                      max: 1,
                      onChanged: (next) => setDialogState(() => opacity = next),
                    ),
                  ),
                  Text('${(opacity * 100).round()}%'),
                ]),
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (_number(value.text) == null) return;
                Navigator.pop(dialogContext, {
                  'label': label.text.trim(),
                  'value': value.text.trim(),
                  'color': color,
                  'style': style,
                  'width': width,
                  'opacity': opacity,
                });
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    value.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _alertLines = <Map<String, dynamic>>[
          ..._alertLines,
          Map<String, dynamic>.from(result),
        ];
      } else {
        _alertLines = <Map<String, dynamic>>[
          for (var itemIndex = 0; itemIndex < _alertLines.length; itemIndex++)
            itemIndex == index
                ? Map<String, dynamic>.from(result)
                : Map<String, dynamic>.from(_alertLines[itemIndex]),
        ];
      }
    });
  }

  Future<String?> _showSearchPicker({
    required String title,
    required Map<String, String> options,
    String? selected,
  }) async {
    var search = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final visible = options.entries
              .where((entry) =>
                  entry.value.toLowerCase().contains(search.toLowerCase()) ||
                  entry.key.toLowerCase().contains(search.toLowerCase()))
              .toList(growable: false);
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 470,
              height: 480,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Buscar…',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) =>
                        setDialogState(() => search = value.trim()),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: visible.isEmpty
                        ? const Center(child: Text('No hay coincidencias.'))
                        : ListView.builder(
                            itemCount: visible.length,
                            itemBuilder: (_, index) {
                              final entry = visible[index];
                              final active = entry.key == selected;
                              return ListTile(
                                leading: Icon(
                                  active
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  color: active ? _metricsTeal : _metricsMuted,
                                ),
                                title: Text(entry.value),
                                subtitle: entry.key == entry.value
                                    ? null
                                    : Text(entry.key),
                                onTap: () =>
                                    Navigator.pop(dialogContext, entry.key),
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
            ],
          );
        },
      ),
    );
  }

  Widget _sourceSelector() {
    String? sourceName;
    for (final source in widget.sources) {
      if (source['tabla']?.toString() == _table) {
        sourceName = source['nombre']?.toString() ?? _table;
        break;
      }
    }
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: () async {
        final options = <String, String>{
          for (final source in widget.sources)
            if ((source['tabla']?.toString() ?? '').isNotEmpty)
              source['tabla'].toString():
                  source['nombre']?.toString() ?? source['tabla'].toString(),
        };
        final value = await _showSearchPicker(
          title: 'Seleccionar origen',
          options: options,
          selected: _table,
        );
        if (value == null || !mounted || value == _table) return;
        setState(() {
          _table = value;
          _dimensions.clear();
          _values.clear();
          _valuesY2.clear();
          _details.clear();
          _valueAggregations.clear();
          for (final aliases in _axisAliases.values) {
            aliases.clear();
          }
          _legend = null;
        });
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Origen',
          prefixIcon: Icon(Icons.storage_outlined),
          suffixIcon: Icon(Icons.search_rounded),
          border: OutlineInputBorder(),
        ),
        child: Text(
          sourceName ?? 'Buscar una tabla del sistema',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: sourceName == null ? _metricsMuted : _metricsNavy,
            fontWeight: sourceName == null ? FontWeight.w400 : FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _chartTypeSelector() {
    final current = _charts[_chart] ?? _charts['BAR']!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Tipo de gráfico',
            style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F8FA),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD8E3E9)),
          ),
          child: Row(
            children: [
              Icon(current.$2, color: _metricsTeal),
              const SizedBox(width: 10),
              Expanded(
                child: Text(current.$1,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              IconButton.filledTonal(
                tooltip: 'Elegir tipo de gráfico',
                onPressed: () async {
                  final value = await _showChartTypePicker();
                  if (value != null && mounted) {
                    setState(() => _chart = value);
                  }
                },
                icon: Icon(widget.initial == null
                    ? Icons.add_rounded
                    : Icons.edit_outlined),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<String?> _showChartTypePicker() => showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Tipos de gráfico'),
          content: SizedBox(
            width: 470,
            height: 520,
            child: ListView.separated(
              itemCount: _charts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final entry = _charts.entries.elementAt(index);
                final selected = entry.key == _chart;
                return ListTile(
                  minVerticalPadding: 12,
                  leading: Container(
                    width: 46,
                    height: 42,
                    decoration: BoxDecoration(
                      color: selected
                          ? _metricsTeal.withValues(alpha: .14)
                          : const Color(0xFFF1F5F7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      entry.value.$2,
                      color: selected ? _metricsTeal : _metricsMuted,
                    ),
                  ),
                  title: Text(
                    entry.value.$1,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_circle, color: _metricsTeal)
                      : null,
                  onTap: () => Navigator.pop(dialogContext, entry.key),
                );
              },
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

  Widget _axisBuilder({
    required String title,
    required List<String> values,
    required ValueChanged<String> onAdd,
    String? aliasAxis,
    bool valueAxis = false,
    bool secondaryAxis = false,
  }) {
    final candidates = _fields
        .map((field) => field['campo']?.toString() ?? '')
        .where((field) => field.isNotEmpty && !values.contains(field))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (values.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: values.length,
            onReorder: (oldIndex, newIndex) => setState(() {
              if (newIndex > oldIndex) newIndex--;
              final item = values.removeAt(oldIndex);
              values.insert(newIndex, item);
            }),
            itemBuilder: (_, index) {
              final field = values[index];
              final calculation = _valueAggregations[field] ?? _aggregation;
              final alias = aliasAxis == null
                  ? ''
                  : (_axisAliases[aliasAxis]?[field] ?? '').trim();
              return Container(
                key: ValueKey('$title-$field-$index'),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F8FA),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0xFFDCE5EA)),
                ),
                child: Row(children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.drag_indicator_rounded,
                          size: 19, color: _metricsMuted),
                    ),
                  ),
                  Icon(
                    valueAxis
                        ? (secondaryAxis
                            ? Icons.stacked_line_chart_rounded
                            : Icons.show_chart_rounded)
                        : Icons.segment_outlined,
                    size: 19,
                    color:
                        secondaryAxis ? const Color(0xFF8659B5) : _metricsTeal,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onDoubleTap: aliasAxis == null
                          ? null
                          : () => _renameAxisField(aliasAxis, field),
                      child: Tooltip(
                        message: aliasAxis == null
                            ? _fieldLabel(field)
                            : 'Doble clic para cambiar el nombre visual',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                alias.isEmpty ? _fieldLabel(field) : alias,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: alias.isEmpty
                                      ? FontWeight.w500
                                      : FontWeight.w800,
                                ),
                              ),
                              if (alias.isNotEmpty)
                                Text(
                                  'Campo: ${_fieldLabel(field)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _metricsMuted,
                                    fontSize: 10.5,
                                  ),
                                ),
                              if (valueAxis)
                                Text(
                                  _calculationLabel(calculation),
                                  style: const TextStyle(
                                    color: _metricsMuted,
                                    fontSize: 10.5,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (valueAxis)
                    PopupMenuButton<String>(
                      tooltip: 'Opciones del campo',
                      onSelected: (action) async {
                        if (action == 'delete') {
                          setState(() {
                            values.removeAt(index);
                            _valueAggregations.remove(field);
                            if (aliasAxis != null) {
                              _axisAliases[aliasAxis]?.remove(field);
                            }
                          });
                        } else if (action == 'calculation') {
                          await _configureValueAxis(field);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'calculation', child: Text('Cálculo')),
                        PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                      ],
                    )
                  else
                    IconButton(
                      tooltip: 'Eliminar campo',
                      onPressed: () => setState(() {
                        values.removeAt(index);
                        if (aliasAxis != null) {
                          _axisAliases[aliasAxis]?.remove(field);
                        }
                      }),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                ]),
              );
            },
          ),
        OutlinedButton.icon(
          onPressed: _table == null || candidates.isEmpty
              ? null
              : () async {
                  final value = await _showSearchPicker(
                    title: 'Agregar campo a $title',
                    options: {
                      for (final field in candidates) field: _fieldLabel(field),
                    },
                  );
                  if (value != null && mounted) onAdd(value);
                },
          icon: const Icon(Icons.add_rounded),
          label: Text(values.isEmpty ? 'Agregar campo' : 'Agregar otro campo'),
        ),
      ],
    );
  }

  Widget _singleFieldBuilder({
    required String title,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (value != null && value.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF5F8FA),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFFDCE5EA)),
            ),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.label_outline, color: _metricsTeal),
              title: Text(_fieldLabel(value)),
              trailing: IconButton(
                tooltip: 'Quitar campo',
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: _table == null
                ? null
                : () async {
                    final options = <String, String>{
                      for (final field in _fields)
                        if ((field['campo']?.toString() ?? '').isNotEmpty)
                          field['campo'].toString():
                              _fieldLabel(field['campo'].toString()),
                    };
                    final selected = await _showSearchPicker(
                        title: 'Seleccionar $title', options: options);
                    if (selected != null && mounted) onChanged(selected);
                  },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Agregar campo'),
          ),
      ],
    );
  }

  Future<void> _renameAxisField(String axis, String field) async {
    final controller = TextEditingController(
      text: _axisAliases[axis]?[field] ?? '',
    );
    final alias = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nombre visual del campo'),
        content: SizedBox(
          width: 410,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: 'Nombre mostrado en el gráfico',
              helperText: 'Campo original: ${_fieldLabel(field)}',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: const Text('Usar nombre original'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || alias == null) return;
    setState(() {
      if (alias.isEmpty) {
        _axisAliases[axis]?.remove(field);
      } else {
        _axisAliases.putIfAbsent(axis, () => <String, String>{})[field] = alias;
      }
    });
  }

  String _fieldLabel(String fieldName) {
    for (final field in _fields) {
      if (field['campo']?.toString() == fieldName) {
        return field['etiqueta']?.toString() ?? fieldName;
      }
    }
    return fieldName;
  }

  String _calculationLabel(String calculation) =>
      const {
        'NONE': 'Sin cálculo',
        'COUNT': 'Conteo',
        'SUM': 'Suma',
        'SUBTRACT': 'Resta',
        'AVG': 'Promedio',
        'MEDIAN': 'Mediana',
        'MODE': 'Moda',
        'MIN': 'Mínimo',
        'MAX': 'Máximo',
      }[calculation] ??
      calculation;

  Future<void> _configureValueAxis(String field) async {
    const calculations = <String, String>{
      'NONE': 'Sin cálculo',
      'COUNT': 'Conteo',
      'SUM': 'Suma',
      'SUBTRACT': 'Resta',
      'AVG': 'Promedio',
      'MEDIAN': 'Mediana',
      'MODE': 'Moda',
      'MIN': 'Mínimo',
      'MAX': 'Máximo',
    };
    final current = _valueAggregations[field] ?? _aggregation;
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Cálculo · ${_fieldLabel(field)}'),
        children: calculations.entries
            .map((entry) => ListTile(
                  leading: Icon(
                    entry.key == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: entry.key == current ? _metricsTeal : _metricsMuted,
                  ),
                  title: Text(entry.value),
                  onTap: () => Navigator.pop(dialogContext, entry.key),
                ))
            .toList(),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _valueAggregations[field] = selected;
        if (_values.isNotEmpty && field == _values.first) {
          _aggregation = selected;
        }
      });
    }
  }

  Widget _numberSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          Slider(value: value, min: min, max: max, onChanged: onChanged),
        ],
      );

  Widget _colorEditor(
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) {
    const palette = [
      'transparent',
      '#D32F2F',
      '#F57C00',
      '#FBC02D',
      '#388E3C',
      '#14738A',
      '#039BE5',
      '#1976D2',
      '#E91E63',
      '#8659B5',
      '#AB47BC',
      '#7E57C2',
      '#142F49',
      '#000000',
      '#607D8B',
      '#FFFFFF',
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () async {
        var selected = value;
        final controller = TextEditingController(text: value);
        final result = await showDialog<String>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.palette_outlined, color: _metricsTeal),
                  const SizedBox(width: 9),
                  Expanded(child: Text(label)),
                ],
              ),
              content: SizedBox(
                width: 390,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      children: palette
                          .map((color) => InkWell(
                                onTap: () => setDialogState(() {
                                  selected = color;
                                  controller.text = color;
                                }),
                                borderRadius: BorderRadius.circular(22),
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _colorFromHex(color),
                                    border: Border.all(
                                      color: selected.toUpperCase() ==
                                              color.toUpperCase()
                                          ? _metricsNavy
                                          : const Color(0xFFCCD8DE),
                                      width: selected.toUpperCase() ==
                                              color.toUpperCase()
                                          ? 3
                                          : 1,
                                    ),
                                  ),
                                  child: color == 'transparent'
                                      ? const Icon(Icons.block,
                                          size: 21, color: _metricsMuted)
                                      : null,
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'Hexadecimal, RGB o RGBA',
                        hintText: '#14738A o rgba(20,115,138,0.8)',
                        prefixIcon: Icon(Icons.tag_rounded),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (next) => selected = next.trim(),
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
                  onPressed: () =>
                      Navigator.pop(dialogContext, controller.text.trim()),
                  child: const Text('Aplicar'),
                ),
              ],
            ),
          ),
        );
        controller.dispose();
        if (result == null || result.isEmpty || !mounted) return;
        onChanged(result);
        if (mounted) setState(() {});
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.palette_outlined),
          suffixIcon: const Icon(Icons.chevron_right_rounded),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: _color(value, _metricsTeal),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFBCCAD2)),
              ),
              child: value.toLowerCase() == 'transparent'
                  ? const Icon(Icons.block, size: 15, color: _metricsMuted)
                  : null,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                value.toLowerCase() == 'transparent' ? 'Sin color' : value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.icon,
    required this.title,
    required this.onClose,
  });

  final IconData icon;
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFDCE5EA))),
        ),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: _metricsTeal,
            foregroundColor: Colors.white,
            child: Icon(icon, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: _metricsNavy,
                    fontSize: 17,
                    fontWeight: FontWeight.w900)),
          ),
          IconButton(
            tooltip: 'Cerrar panel',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ]),
      );
}

class _PanelSectionTitle extends StatelessWidget {
  const _PanelSectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
              color: _metricsNavy,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            )),
      );
}

class _DashboardEditorDialog extends StatefulWidget {
  const _DashboardEditorDialog({this.initial, this.users = const []});
  final Map<String, dynamic>? initial;
  final List<Map<String, dynamic>> users;

  @override
  State<_DashboardEditorDialog> createState() => _DashboardEditorDialogState();
}

class _DashboardEditorDialogState extends State<_DashboardEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _userSearch;
  late final TextEditingController _backgroundColorController;
  late final TextEditingController _titleColorController;
  String _color = '#176B87';
  String _backgroundImage = '';
  double _backgroundOpacity = 1;
  String _titleFontFamily = 'Roboto';
  String _titleColor = '#142F49';
  String _visibility = 'ALL';
  final Set<String> _selectedUsers = <String>{};

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: '${widget.initial?['nombre'] ?? ''}');
    _description =
        TextEditingController(text: '${widget.initial?['descripcion'] ?? ''}');
    _userSearch = TextEditingController()..addListener(_refreshUserSearch);
    final config = _map(widget.initial?['configuracion']);
    _color = config['background_color']?.toString() ??
        '${widget.initial?['color'] ?? '#176B87'}';
    _backgroundColorController = TextEditingController(text: _color);
    _backgroundImage = config['background_image']?.toString() ?? '';
    _backgroundOpacity =
        (config['background_opacity'] as num?)?.toDouble() ?? 1;
    _titleFontFamily = config['dashboard_title_font']?.toString() ?? 'Roboto';
    _titleColor = config['dashboard_title_color']?.toString() ?? '#142F49';
    _titleColorController = TextEditingController(text: _titleColor);
    _visibility = config['visibility']?.toString() ?? 'ALL';
    _selectedUsers.addAll((config['users'] as List? ?? const [])
        .map((value) => value.toString()));
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _backgroundColorController.dispose();
    _titleColorController.dispose();
    _userSearch
      ..removeListener(_refreshUserSearch)
      ..dispose();
    super.dispose();
  }

  void _refreshUserSearch() => setState(() {});

  void _setBackgroundColor(String value) {
    _backgroundColorController.text = value;
    setState(() => _color = value);
  }

  void _setTitleColor(String value) {
    _titleColorController.text = value;
    setState(() => _titleColor = value);
  }

  Future<void> _openColorPalette({required bool title}) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _MetricsColorPickerDialog(
        initial: title ? _titleColor : _color,
        allowTransparent: !title,
      ),
    );
    if (!mounted || value == null) return;
    if (title) {
      _setTitleColor(value);
    } else {
      _setBackgroundColor(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title:
          Text(widget.initial == null ? 'Nuevo dashboard' : 'Editar dashboard'),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Nombre', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Descripción', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Estilo del título',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _titleFontFamily,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de letra',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    'Roboto',
                    'Arial',
                    'Calibri',
                    'Verdana',
                    'Georgia',
                    'Times New Roman',
                  ]
                      .map((font) => DropdownMenuItem(
                            value: font,
                            child:
                                Text(font, style: TextStyle(fontFamily: font)),
                          ))
                      .toList(),
                  onChanged: (value) => setState(
                    () => _titleFontFamily = value ?? 'Roboto',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _titleColorController,
                  decoration: InputDecoration(
                    labelText: 'Color del título',
                    hintText: '#142F49',
                    prefixIcon: Padding(
                      padding: const EdgeInsets.all(12),
                      child: CircleAvatar(
                        radius: 9,
                        backgroundColor: _colorFromHex(_titleColor),
                      ),
                    ),
                    suffixIcon: IconButton(
                      tooltip: 'Abrir paleta de colores',
                      onPressed: () => _openColorPalette(title: true),
                      icon: const Icon(Icons.palette_outlined),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _titleColor = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _backgroundColorController,
            decoration: InputDecoration(
              labelText: 'Color de fondo · Hex o RGB',
              hintText: '#176B87 o rgb(23,107,135)',
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12),
                child: CircleAvatar(
                  radius: 9,
                  backgroundColor: _colorFromHex(_color),
                ),
              ),
              suffixIcon: IconButton(
                tooltip: 'Abrir paleta completa de colores',
                onPressed: () => _openColorPalette(title: false),
                icon: const Icon(Icons.palette_outlined),
              ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _color = value),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 9,
              children: [
                'transparent',
                '#176B87',
                '#17324D',
                '#2F9D75',
                '#C56A13',
                '#8659B5'
              ]
                  .map((value) => Tooltip(
                      message: value == 'transparent' ? 'Sin color' : value,
                      child: InkWell(
                        onTap: () => _setBackgroundColor(value),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: _colorFromHex(value),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == value
                                  ? _metricsNavy
                                  : const Color(0xFFCCD8DE),
                              width: _color == value ? 2.5 : 1,
                            ),
                          ),
                          child: value == 'transparent'
                              ? const Icon(Icons.block, size: 17)
                              : null,
                        ),
                      )))
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await FilePicker.platform.pickFiles(
                    type: FileType.image,
                    withData: true,
                    allowMultiple: false,
                  );
                  final file = picked?.files.single;
                  final bytes = file?.bytes;
                  if (bytes == null || !mounted) return;
                  final extension = (file?.extension ?? 'png').toLowerCase();
                  final mime = extension == 'jpg' || extension == 'jpeg'
                      ? 'jpeg'
                      : extension == 'webp'
                          ? 'webp'
                          : 'png';
                  setState(() => _backgroundImage =
                      'data:image/$mime;base64,${base64Encode(bytes)}');
                },
                icon: const Icon(Icons.image_outlined),
                label: Text(_backgroundImage.isEmpty
                    ? 'Imagen de fondo'
                    : 'Cambiar imagen'),
              ),
            ),
            if (_backgroundImage.isNotEmpty)
              IconButton(
                tooltip: 'Quitar imagen',
                onPressed: () => setState(() => _backgroundImage = ''),
                icon: const Icon(Icons.delete_outline),
              ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const Text('Opacidad del fondo'),
            Expanded(
              child: Slider(
                value: _backgroundOpacity,
                min: .1,
                max: 1,
                onChanged: (value) =>
                    setState(() => _backgroundOpacity = value),
              ),
            ),
            Text('${(_backgroundOpacity * 100).round()}%'),
          ]),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _visibility,
            decoration: const InputDecoration(
              labelText: 'Quién puede ver este dashboard',
              border: OutlineInputBorder(),
            ),
            items: const {
              'ADMINS': 'Solo administradores',
              'ALL': 'Todos',
              'SPECIFIC': 'Usuario(s) específico(s)',
              'ALL_EXCEPT': 'Todos excepto',
            }
                .entries
                .map((entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ))
                .toList(),
            onChanged: (value) => setState(() => _visibility = value ?? 'ALL'),
          ),
          if (_visibility == 'SPECIFIC' || _visibility == 'ALL_EXCEPT') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _userSearch,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Buscar usuario…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD5E0E6)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: widget.users.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Text(
                          'No se recibió el directorio de usuarios. Actualiza Metrics e inténtalo de nuevo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _metricsMuted),
                        ),
                      ),
                    )
                  : ListView(
                      children: widget.users.where((user) {
                        final query = _userSearch.text.trim().toLowerCase();
                        if (query.isEmpty) return true;
                        return [
                          user['nombres'],
                          user['apellidos'],
                          user['email']
                        ]
                            .whereType<Object>()
                            .map((value) => value.toString().toLowerCase())
                            .any((value) => value.contains(query));
                      }).map((user) {
                        final id = user['id']?.toString() ?? '';
                        final label =
                            user['nombres']?.toString().trim().isNotEmpty ==
                                    true
                                ? user['nombres'].toString()
                                : user['email']?.toString() ?? id;
                        return CheckboxListTile(
                          dense: true,
                          value: _selectedUsers.contains(id),
                          title: Text(label),
                          onChanged: (selected) => setState(() {
                            if (selected == true) {
                              _selectedUsers.add(id);
                            } else {
                              _selectedUsers.remove(id);
                            }
                          }),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, {
                    if (widget.initial?['id'] != null)
                      'id': widget.initial!['id'],
                    'nombre': _name.text.trim(),
                    'descripcion': _description.text.trim(),
                    'color': _color,
                    'orden': widget.initial?['orden'] ?? 0,
                    'filtros_globales':
                        widget.initial?['filtros_globales'] ?? const [],
                    'configuracion': {
                      ..._map(widget.initial?['configuracion']),
                      'background_color': _color,
                      'background_image': _backgroundImage,
                      'background_opacity': _backgroundOpacity,
                      'dashboard_title_font': _titleFontFamily,
                      'dashboard_title_color': _titleColor,
                      'visibility': _visibility,
                      'users': _selectedUsers.toList(),
                    },
                  }),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _MetricsColorPickerDialog extends StatefulWidget {
  const _MetricsColorPickerDialog({
    required this.initial,
    required this.allowTransparent,
  });

  final String initial;
  final bool allowTransparent;

  @override
  State<_MetricsColorPickerDialog> createState() =>
      _MetricsColorPickerDialogState();
}

class _MetricsColorPickerDialogState extends State<_MetricsColorPickerDialog> {
  late HSVColor _hsv;
  late bool _transparent;
  late final TextEditingController _hex;

  static const _swatches = <Color>[
    Color(0xFF142F49),
    Color(0xFF176B87),
    Color(0xFF00838F),
    Color(0xFF00695C),
    Color(0xFF2E7D32),
    Color(0xFF558B2F),
    Color(0xFF9E9D24),
    Color(0xFFF9A825),
    Color(0xFFEF6C00),
    Color(0xFFD84315),
    Color(0xFFC62828),
    Color(0xFFAD1457),
    Color(0xFF6A1B9A),
    Color(0xFF4527A0),
    Color(0xFF283593),
    Color(0xFF1565C0),
    Color(0xFF0277BD),
    Color(0xFF455A64),
    Color(0xFF5D4037),
    Color(0xFF616161),
    Color(0xFFFFFFFF),
    Color(0xFFECEFF1),
    Color(0xFF90A4AE),
    Color(0xFF000000),
  ];

  @override
  void initState() {
    super.initState();
    _transparent = widget.initial.trim().toLowerCase() == 'transparent';
    final initialColor =
        _transparent ? _metricsTeal : _color(widget.initial, _metricsTeal);
    _hsv = HSVColor.fromColor(initialColor);
    _hex = TextEditingController(
      text: _transparent ? 'transparent' : _hexValue(initialColor),
    );
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  static String _hexValue(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  void _selectColor(Color color) {
    setState(() {
      _transparent = false;
      _hsv = HSVColor.fromColor(color);
      _hex.text = _hexValue(color);
    });
  }

  void _updateHsv(HSVColor value) {
    setState(() {
      _transparent = false;
      _hsv = value;
      _hex.text = _hexValue(value.toColor());
    });
  }

  void _applyTypedColor(String value) {
    final normalized = value.trim();
    if (widget.allowTransparent && normalized.toLowerCase() == 'transparent') {
      setState(() => _transparent = true);
      return;
    }
    _selectColor(_color(normalized, _hsv.toColor()));
  }

  @override
  Widget build(BuildContext context) {
    final selected = _hsv.toColor();
    return AlertDialog(
      scrollable: true,
      title: const Text('Paleta de colores'),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 62,
              decoration: BoxDecoration(
                color: _transparent ? Colors.transparent : selected,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFB9C8D0)),
              ),
              alignment: Alignment.center,
              child: _transparent
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.block),
                        SizedBox(width: 8),
                        Text('Fondo transparente'),
                      ],
                    )
                  : null,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: _swatches
                  .map((color) => InkWell(
                        onTap: () => _selectColor(color),
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: !_transparent &&
                                      selected.toARGB32() == color.toARGB32()
                                  ? _metricsTeal
                                  : const Color(0xFFB9C8D0),
                              width: 2,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _hex,
              decoration: const InputDecoration(
                labelText: 'Hex, RGB o RGBA',
                border: OutlineInputBorder(),
              ),
              onFieldSubmitted: _applyTypedColor,
            ),
            if (widget.allowTransparent)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sin color (transparente)'),
                value: _transparent,
                onChanged: (value) => setState(() {
                  _transparent = value;
                  _hex.text = value ? 'transparent' : _hexValue(selected);
                }),
              ),
            _ColorSlider(
              label: 'Matiz',
              value: _hsv.hue,
              max: 360,
              enabled: !_transparent,
              onChanged: (value) => _updateHsv(_hsv.withHue(value)),
            ),
            _ColorSlider(
              label: 'Saturación',
              value: _hsv.saturation,
              max: 1,
              enabled: !_transparent,
              onChanged: (value) => _updateHsv(_hsv.withSaturation(value)),
            ),
            _ColorSlider(
              label: 'Brillo',
              value: _hsv.value,
              max: 1,
              enabled: !_transparent,
              onChanged: (value) => _updateHsv(_hsv.withValue(value)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: () {
            _applyTypedColor(_hex.text);
            Navigator.pop(
              context,
              _transparent ? 'transparent' : _hexValue(_hsv.toColor()),
            );
          },
          icon: const Icon(Icons.check_rounded),
          label: const Text('Elegir'),
        ),
      ],
    );
  }
}

class _ColorSlider extends StatelessWidget {
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(width: 82, child: Text(label)),
          Expanded(
            child: Slider(
              value: value.clamp(0.0, max).toDouble(),
              max: max,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      );
}

class MetricWidgetEditorPage extends StatefulWidget {
  const MetricWidgetEditorPage({
    super.key,
    required this.dashboardId,
    required this.sources,
    this.initial,
  });

  final String dashboardId;
  final List<Map<String, dynamic>> sources;
  final Map<String, dynamic>? initial;

  @override
  State<MetricWidgetEditorPage> createState() => _MetricWidgetEditorPageState();
}

class _MetricWidgetEditorPageState extends State<MetricWidgetEditorPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _axisX;
  late final TextEditingController _axisY;
  late final TextEditingController _filterValue;
  late final TextEditingController _threshold;
  String? _table;
  String? _dimension;
  String? _value;
  String? _series;
  String? _filterField;
  String _filterOperator = 'eq';
  String _chart = 'BAR';
  String _aggregation = 'COUNT';
  String _color = '#14738A';
  String _conditionColor = '#C9536A';
  bool _trendline = false;
  bool _showLegend = true;
  double _titleSize = 16;
  int _width = 6;
  int _height = 4;

  List<Map<String, dynamic>> get _fields {
    for (final source in widget.sources) {
      if ('${source['tabla']}' == _table) return _maps(source['campos']);
    }
    return const [];
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial ?? const {};
    final config = _map(initial['configuracion']);
    final filters = _maps(initial['filtros']);
    final filter = filters.isEmpty ? const <String, dynamic>{} : filters.first;
    _title = TextEditingController(text: '${initial['titulo'] ?? ''}');
    _description =
        TextEditingController(text: '${initial['descripcion'] ?? ''}');
    _axisX = TextEditingController(text: '${config['axis_x'] ?? ''}');
    _axisY = TextEditingController(text: '${config['axis_y'] ?? ''}');
    _filterValue = TextEditingController(text: '${filter['value'] ?? ''}');
    _threshold = TextEditingController(text: '${config['threshold'] ?? ''}');
    _table = initial['tabla_origen']?.toString();
    _dimension = initial['campo_dimension']?.toString();
    _value = initial['campo_valor']?.toString();
    _series = initial['campo_serie']?.toString();
    _filterField = filter['field']?.toString();
    _filterOperator = '${filter['operator'] ?? 'eq'}';
    _chart = '${initial['tipo_grafico'] ?? 'BAR'}';
    _aggregation = '${initial['agregacion'] ?? 'COUNT'}';
    _color = '${config['color'] ?? '#14738A'}';
    _conditionColor = '${config['condition_color'] ?? '#C9536A'}';
    _trendline = config['trendline'] == true;
    _showLegend = config['show_legend'] != false;
    _titleSize = (config['title_size'] as num?)?.toDouble() ?? 16;
    _width = (initial['ancho'] as num?)?.toInt() ?? 6;
    _height = (initial['alto'] as num?)?.toInt() ?? 4;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _axisX.dispose();
    _axisY.dispose();
    _filterValue.dispose();
    _threshold.dispose();
    super.dispose();
  }

  Map<String, dynamic> _payload() => {
        if (widget.initial?['id'] != null) 'id': widget.initial!['id'],
        'dashboard_id': widget.dashboardId,
        'titulo': _title.text.trim(),
        'descripcion': _description.text.trim(),
        'tabla_origen': _table,
        'campo_dimension': _dimension,
        'campo_valor': _value,
        'campo_serie': _series,
        'tipo_grafico': _chart,
        'agregacion': _aggregation,
        'filtros': _filterField == null || _filterValue.text.trim().isEmpty
            ? <Map<String, dynamic>>[]
            : [
                {
                  'field': _filterField,
                  'operator': _filterOperator,
                  'value': _filterValue.text.trim(),
                }
              ],
        'configuracion': {
          'color': _color,
          'axis_x': _axisX.text.trim(),
          'axis_y': _axisY.text.trim(),
          'trendline': _trendline,
          'show_legend': _showLegend,
          'title_size': _titleSize,
          if (_threshold.text.trim().isNotEmpty)
            'threshold': double.tryParse(_threshold.text.trim()),
          'condition_color': _conditionColor,
        },
        'ancho': _width,
        'alto': _height,
      };

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_table == null) return;
    Navigator.pop(context, _payload());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _metricsCanvas,
      appBar: AppBar(
        title:
            Text(widget.initial == null ? 'Nuevo gráfico' : 'Editar gráfico'),
        actions: [
          TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar')),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _form,
        child: LayoutBuilder(builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 850;
          return ListView(
            padding: EdgeInsets.fromLTRB(
                desktop ? 28 : 14, 20, desktop ? 28 : 14, 50),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _BuilderSection(
                          number: '1',
                          title: 'Datos del gráfico',
                          text:
                              'Selecciona la fuente, los campos y la forma de resumirlos.',
                        ),
                        const SizedBox(height: 12),
                        _ResponsiveFieldRow(desktop: desktop, children: [
                          TextFormField(
                            controller: _title,
                            decoration: const InputDecoration(
                                labelText: 'Título',
                                border: OutlineInputBorder()),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Escribe un título'
                                    : null,
                          ),
                          TextFormField(
                            controller: _description,
                            decoration: const InputDecoration(
                                labelText: 'Descripción',
                                border: OutlineInputBorder()),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        _ResponsiveFieldRow(desktop: desktop, children: [
                          DropdownButtonFormField<String>(
                            initialValue: widget.sources
                                    .any((source) => source['tabla'] == _table)
                                ? _table
                                : null,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Tabla',
                                border: OutlineInputBorder()),
                            items: widget.sources
                                .map((source) => DropdownMenuItem(
                                    value: '${source['tabla']}',
                                    child: Text('${source['nombre']}',
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (value) => setState(() {
                              _table = value;
                              _dimension = null;
                              _value = null;
                              _series = null;
                              _filterField = null;
                            }),
                            validator: (value) =>
                                value == null ? 'Selecciona una tabla' : null,
                          ),
                          _fieldDropdown('Dimensión / eje X', _dimension,
                              (value) => setState(() => _dimension = value),
                              allowEmpty: _chart == 'KPI'),
                          _fieldDropdown('Valor / eje Y', _value,
                              (value) => setState(() => _value = value),
                              allowEmpty: _aggregation == 'COUNT'),
                        ]),
                        const SizedBox(height: 12),
                        _ResponsiveFieldRow(desktop: desktop, children: [
                          DropdownButtonFormField<String>(
                            initialValue: _chart,
                            decoration: const InputDecoration(
                                labelText: 'Tipo de gráfico',
                                border: OutlineInputBorder()),
                            items: const {
                              'KPI': 'Indicador KPI',
                              'BAR': 'Barras',
                              'LINE': 'Líneas',
                              'AREA': 'Área',
                              'PIE': 'Circular',
                              'TABLE': 'Tabla',
                              'SCATTER': 'Dispersión'
                            }
                                .entries
                                .map((entry) => DropdownMenuItem(
                                    value: entry.key, child: Text(entry.value)))
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _chart = value ?? 'BAR'),
                          ),
                          DropdownButtonFormField<String>(
                            initialValue: _aggregation,
                            decoration: const InputDecoration(
                                labelText: 'Cálculo',
                                border: OutlineInputBorder()),
                            items: const {
                              'COUNT': 'Contar',
                              'SUM': 'Sumar',
                              'AVG': 'Promedio',
                              'MIN': 'Mínimo',
                              'MAX': 'Máximo'
                            }
                                .entries
                                .map((entry) => DropdownMenuItem(
                                    value: entry.key, child: Text(entry.value)))
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _aggregation = value ?? 'COUNT'),
                          ),
                          _fieldDropdown('Serie (opcional)', _series,
                              (value) => setState(() => _series = value),
                              allowEmpty: true),
                        ]),
                        const SizedBox(height: 24),
                        const _BuilderSection(
                          number: '2',
                          title: 'Apariencia y comportamiento',
                          text:
                              'Personaliza colores, ejes, tendencia, tamaño y una regla visual.',
                        ),
                        const SizedBox(height: 12),
                        _ResponsiveFieldRow(desktop: desktop, children: [
                          TextField(
                              controller: _axisX,
                              decoration: const InputDecoration(
                                  labelText: 'Título eje X',
                                  border: OutlineInputBorder())),
                          TextField(
                              controller: _axisY,
                              decoration: const InputDecoration(
                                  labelText: 'Título eje Y',
                                  border: OutlineInputBorder())),
                          DropdownButtonFormField<int>(
                            initialValue: _width,
                            decoration: const InputDecoration(
                                labelText: 'Ancho',
                                border: OutlineInputBorder()),
                            items: const [3, 4, 6, 8, 12]
                                .map((value) => DropdownMenuItem(
                                    value: value,
                                    child: Text('$value columnas')))
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _width = value ?? 6),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        Wrap(
                            spacing: 9,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text('Color principal:',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                              ...[
                                '#14738A',
                                '#E08A35',
                                '#5A6CCB',
                                '#2F9D75',
                                '#C9536A',
                                '#8659B5'
                              ].map((value) => ChoiceChip(
                                    selected: _color == value,
                                    avatar: CircleAvatar(
                                        backgroundColor: _colorFromHex(value)),
                                    label: Text(value),
                                    onSelected: (_) =>
                                        setState(() => _color = value),
                                  )),
                            ]),
                        const SizedBox(height: 8),
                        _ResponsiveFieldRow(desktop: desktop, children: [
                          TextField(
                            controller: _threshold,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Regla visual: mayor que',
                                helperText: 'Opcional',
                                border: OutlineInputBorder()),
                          ),
                          DropdownButtonFormField<String>(
                            initialValue: _conditionColor,
                            decoration: const InputDecoration(
                                labelText: 'Color al cumplir',
                                border: OutlineInputBorder()),
                            items: ['#C9536A', '#E08A35', '#2F9D75', '#5A6CCB']
                                .map((value) => DropdownMenuItem(
                                    value: value,
                                    child: Row(children: [
                                      CircleAvatar(
                                          radius: 7,
                                          backgroundColor:
                                              _colorFromHex(value)),
                                      const SizedBox(width: 8),
                                      Text(value)
                                    ])))
                                .toList(),
                            onChanged: (value) => setState(() =>
                                _conditionColor = value ?? _conditionColor),
                          ),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Tamaño de título: ${_titleSize.round()}'),
                                Slider(
                                    value: _titleSize,
                                    min: 13,
                                    max: 24,
                                    divisions: 11,
                                    onChanged: (value) =>
                                        setState(() => _titleSize = value)),
                              ]),
                        ]),
                        Wrap(spacing: 18, children: [
                          FilterChip(
                              selected: _trendline,
                              label: const Text('Línea de tendencia'),
                              avatar: const Icon(Icons.trending_up, size: 18),
                              onSelected: (value) =>
                                  setState(() => _trendline = value)),
                          FilterChip(
                              selected: _showLegend,
                              label: const Text('Mostrar leyenda'),
                              avatar: const Icon(Icons.view_list_outlined,
                                  size: 18),
                              onSelected: (value) =>
                                  setState(() => _showLegend = value)),
                        ]),
                        const SizedBox(height: 24),
                        const _BuilderSection(
                            number: '3',
                            title: 'Filtro del gráfico',
                            text: 'Limita este gráfico sin afectar los demás.'),
                        const SizedBox(height: 12),
                        _ResponsiveFieldRow(desktop: desktop, children: [
                          _fieldDropdown('Campo de filtro', _filterField,
                              (value) => setState(() => _filterField = value),
                              allowEmpty: true),
                          DropdownButtonFormField<String>(
                            initialValue: _filterOperator,
                            decoration: const InputDecoration(
                                labelText: 'Condición',
                                border: OutlineInputBorder()),
                            items: const {
                              'eq': 'Igual a',
                              'neq': 'Distinto de',
                              'contains': 'Contiene',
                              'gt': 'Mayor que',
                              'gte': 'Mayor o igual',
                              'lt': 'Menor que',
                              'lte': 'Menor o igual'
                            }
                                .entries
                                .map((entry) => DropdownMenuItem(
                                    value: entry.key, child: Text(entry.value)))
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _filterOperator = value ?? 'eq'),
                          ),
                          TextField(
                              controller: _filterValue,
                              decoration: const InputDecoration(
                                  labelText: 'Valor',
                                  border: OutlineInputBorder())),
                        ]),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                            onPressed: _save,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Guardar gráfico')),
                      ]),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _fieldDropdown(
      String label, String? value, ValueChanged<String?> onChanged,
      {bool allowEmpty = false}) {
    final valid = _fields.any((field) => '${field['campo']}' == value);
    return DropdownButtonFormField<String>(
      initialValue: valid ? value : null,
      isExpanded: true,
      decoration:
          InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [
        if (allowEmpty)
          const DropdownMenuItem<String>(value: '', child: Text('Ninguno')),
        ..._fields.map((field) => DropdownMenuItem(
            value: '${field['campo']}',
            child:
                Text('${field['etiqueta']}', overflow: TextOverflow.ellipsis))),
      ],
      onChanged: (next) => onChanged(next?.isEmpty == true ? null : next),
    );
  }
}

class _RelationsDialog extends StatefulWidget {
  const _RelationsDialog(
      {required this.dashboardId,
      required this.sources,
      required this.relations,
      required this.repository});
  final String dashboardId;
  final List<Map<String, dynamic>> sources;
  final List<Map<String, dynamic>> relations;
  final MetricsRepository repository;

  @override
  State<_RelationsDialog> createState() => _RelationsDialogState();
}

class _RelationsDialogState extends State<_RelationsDialog> {
  late List<Map<String, dynamic>> _relations;
  String? _originTable;
  String? _originField;
  String? _destinationTable;
  String? _destinationField;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _relations = [...widget.relations];
  }

  List<Map<String, dynamic>> _fields(String? table) {
    for (final source in widget.sources) {
      if ('${source['tabla']}' == table) return _maps(source['campos']);
    }
    return const [];
  }

  Future<void> _save() async {
    if (_originTable == null ||
        _originField == null ||
        _destinationTable == null ||
        _destinationField == null) {
      return;
    }
    if (_originTable == _destinationTable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Relaciona dos tablas diferentes.')),
      );
      return;
    }
    final duplicate = _relations.any((relation) {
      final direct = relation['tabla_origen'] == _originTable &&
          relation['campo_origen'] == _originField &&
          relation['tabla_destino'] == _destinationTable &&
          relation['campo_destino'] == _destinationField;
      final reverse = relation['tabla_origen'] == _destinationTable &&
          relation['campo_origen'] == _destinationField &&
          relation['tabla_destino'] == _originTable &&
          relation['campo_destino'] == _originField;
      return direct || reverse;
    });
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esa relación ya existe.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.repository.saveRelation({
        'dashboard_id': widget.dashboardId,
        'tabla_origen': _originTable,
        'campo_origen': _originField,
        'tabla_destino': _destinationTable,
        'campo_destino': _destinationField,
        'nombre':
            '$_originTable.$_originField ↔ $_destinationTable.$_destinationField',
      });
      if (result['solicitado'] == true && mounted) {
        await ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Relación enviada como Solicitada para aprobación del Admin.',
            ),
          ),
        );
      }
      _relations = await widget.repository.listRelations(widget.dashboardId);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo crear la relación: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> relation) async {
    final result =
        await widget.repository.deleteItem('RELACION', '${relation['id']}');
    if (result['solicitado'] == true && mounted) {
      await ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El retiro de la relación quedó Solicitado para aprobación.',
          ),
        ),
      );
    }
    _relations = await widget.repository.listRelations(widget.dashboardId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Expanded(
                  child: Text('Relaciones entre tablas',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: _metricsNavy))),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded)),
            ]),
            const Text(
                'Una relación permite que el filtro de una tabla se propague a gráficos creados con la otra.',
                style: TextStyle(color: _metricsMuted)),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 720;
              final children = [
                _sourceDropdown(
                    'Tabla origen',
                    _originTable,
                    (value) => setState(() {
                          _originTable = value;
                          _originField = null;
                        })),
                _relationFieldDropdown(
                    'Campo clave',
                    _originField,
                    _fields(_originTable),
                    (value) => setState(() => _originField = value)),
                _sourceDropdown(
                    'Tabla destino',
                    _destinationTable,
                    (value) => setState(() {
                          _destinationTable = value;
                          _destinationField = null;
                        })),
                _relationFieldDropdown(
                    'Campo equivalente',
                    _destinationField,
                    _fields(_destinationTable),
                    (value) => setState(() => _destinationField = value)),
              ];
              return desktop
                  ? Row(children: [
                      for (var i = 0; i < children.length; i++) ...[
                        Expanded(child: children[i]),
                        if (i < children.length - 1) const SizedBox(width: 9)
                      ]
                    ])
                  : Column(children: [
                      for (var i = 0; i < children.length; i++) ...[
                        children[i],
                        if (i < children.length - 1) const SizedBox(height: 9)
                      ]
                    ]);
            }),
            const SizedBox(height: 10),
            Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.hub_outlined),
                    label: const Text('Crear relación'))),
            const Divider(height: 28),
            const Text('Relaciones activas',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Expanded(
              child: _relations.isEmpty
                  ? const Center(
                      child: Text('Aún no hay tablas relacionadas.',
                          style: TextStyle(color: _metricsMuted)))
                  : ListView.builder(
                      itemCount: _relations.length,
                      itemBuilder: (_, index) {
                        final relation = _relations[index];
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.hub_outlined,
                                color: _metricsTeal),
                            title: Text(
                                '${relation['tabla_origen']}.${relation['campo_origen']}'),
                            subtitle: Text(
                                'relacionado con ${relation['tabla_destino']}.${relation['campo_destino']}'),
                            trailing: IconButton(
                                tooltip: 'Eliminar relación',
                                onPressed: () => _delete(relation),
                                icon: const Icon(Icons.delete_outline)),
                          ),
                        );
                      }),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _sourceDropdown(
          String label, String? value, ValueChanged<String?> onChanged) =>
      _SearchSelectionField(
        label: label,
        value: value,
        options: {
          for (final source in widget.sources)
            '${source['tabla']}': '${source['nombre']}',
        },
        onChanged: onChanged,
      );

  Widget _relationFieldDropdown(String label, String? value,
          List<Map<String, dynamic>> fields, ValueChanged<String?> onChanged) =>
      _SearchSelectionField(
        label: label,
        value: value,
        options: {
          for (final field in fields)
            '${field['campo']}': '${field['etiqueta']}',
        },
        onChanged: onChanged,
      );
}

// -----------------------------------------------------------------------------
// Visualizaciones
// -----------------------------------------------------------------------------

class _MetricVisualization extends StatelessWidget {
  const _MetricVisualization(
      {required this.widget, required this.dataset, required this.color});
  final Map<String, dynamic> widget;
  final MetricDataset dataset;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final type = '${widget['tipo_grafico']}'.toUpperCase();
    final config = _map(widget['configuracion']);
    final configuredDimensions = (config['dimensions'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    final configuredValues = (config['values'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    final dimensions = configuredDimensions.isNotEmpty
        ? configuredDimensions
        : [
            if (widget['campo_dimension']?.toString().trim().isNotEmpty == true)
              widget['campo_dimension'].toString().trim(),
          ];
    final values = configuredValues.isNotEmpty
        ? configuredValues
        : [
            if (widget['campo_valor']?.toString().trim().isNotEmpty == true)
              widget['campo_valor'].toString().trim(),
          ];
    final valuesY2 = (config['values_y2'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    final valueAliases = <String, String>{
      for (final field in values)
        if (metricsAxisFieldAlias(config, 'y', field).isNotEmpty)
          field: metricsAxisFieldAlias(config, 'y', field),
      for (final field in valuesY2)
        if (metricsAxisFieldAlias(config, 'y2', field).isNotEmpty)
          field: metricsAxisFieldAlias(config, 'y2', field),
    };
    if (type == 'TEXT') {
      return _MetricTextObject(config: config);
    }
    if (dataset.points.isEmpty) {
      return const Center(
          child: Text('No hay datos para esta configuración.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _metricsMuted)));
    }
    if (type == 'KPI') {
      final total =
          dataset.points.fold<double>(0, (sum, point) => sum + point.value);
      final conditionValue = config['condition_value'];
      final displayColor =
          conditionValue?.toString().trim().isNotEmpty == true &&
                  _conditionMatchesRaw(total,
                      config['condition_operator']?.toString(), conditionValue)
              ? _color(config['condition_color'], const Color(0xFFC9536A))
              : color;
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(_formatNumber(total),
            style: TextStyle(
                color: displayColor,
                fontSize: 43,
                fontWeight: FontWeight.w900,
                height: 1)),
        const SizedBox(height: 8),
        Text('${widget['agregacion']} · ${dataset.rows.length} filas',
            style: const TextStyle(color: _metricsMuted)),
      ]);
    }
    if (type == 'TABLE') {
      return _MetricTable(dataset: dataset, valueAliases: valueAliases);
    }
    final points = dataset.points.take(120).toList();
    final chart = _ScrollableMetricChart(
      points: points,
      valueAliases: valueAliases,
      painter: _MetricChartPainter(
        points: points,
        type: type,
        color: color,
        seriesWidth: (config['series_width'] as num?)?.toDouble() ?? 2.4,
        seriesStyle: config['series_style']?.toString() ?? 'solid',
        barWidthRatio: (config['bar_width'] as num?)?.toDouble() ?? .62,
        trendline: config['trendline'] == true,
        trendColor: _color(config['trend_color'], const Color(0xFF8659B5)),
        trendWidth: (config['trend_width'] as num?)?.toDouble() ?? 1.5,
        trendStyle: config['trend_style']?.toString() ?? 'solid',
        trendOpacity: (config['trend_opacity'] as num?)?.toDouble() ?? .9,
        conditionValue: config['condition_value'],
        conditionOperator: config['condition_operator']?.toString() ?? 'gt',
        conditionColor:
            _color(config['condition_color'], const Color(0xFFC9536A)),
        alertValue:
            _number(config['alert_value']) ?? _number(config['threshold']),
        alertColor: _color(config['alert_color'], const Color(0xFFC9536A)),
        alertWidth: (config['alert_width'] as num?)?.toDouble() ?? 1.6,
        alertStyle: config['alert_style']?.toString() ?? 'dash',
        alertOpacity: (config['alert_opacity'] as num?)?.toDouble() ?? .85,
        alertLines: _maps(config['alert_lines']),
        dataLabelProfiles: _map(config['data_label_profiles']),
        yMinimum: _number(config['y_min']),
        yMaximum: _number(config['y_max']),
        y2Minimum: _number(config['y2_min']),
        y2Maximum: _number(config['y2_max']),
      ),
    );
    final axisX = metricsAxisTitle(
      configuration: config,
      axis: 'x',
      fields: dimensions,
      explicitTitle: config['axis_x']?.toString() ?? '',
    );
    final axisY = metricsAxisTitle(
      configuration: config,
      axis: 'y',
      fields: values,
      explicitTitle: config['axis_y']?.toString() ?? '',
    );
    final axisY2 = metricsAxisTitle(
      configuration: config,
      axis: 'y2',
      fields: valuesY2,
      explicitTitle: config['axis_y2']?.toString() ?? '',
    );
    Widget axisTitle(String text, String prefix) => Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _color(
              config['${prefix}_title_color'],
              _metricsNavy,
            ),
            fontSize:
                (config['${prefix}_title_size'] as num?)?.toDouble() ?? 12,
            fontFamily: config['${prefix}_title_font']?.toString(),
            fontWeight: FontWeight.w700,
          ),
        );
    final chartWithAxes = Column(
      children: [
        Expanded(
          child: Row(
            children: [
              if (axisY.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: axisTitle(axisY, 'y'),
                  ),
                ),
              Expanded(child: chart),
              if (axisY2.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: axisTitle(axisY2, 'y2'),
                  ),
                ),
            ],
          ),
        ),
        if (axisX.isNotEmpty) ...[
          const SizedBox(height: 4),
          axisTitle(axisX, 'x'),
        ],
      ],
    );
    if (config['show_legend'] == false) return chartWithAxes;
    final legend = _MetricLegend(
      points: points,
      type: type,
      primaryColor: color,
      title: config['legend_title']?.toString().trim() ?? '',
      fontSize: (config['legend_size'] as num?)?.toDouble() ?? 12,
      position: config['legend_position']?.toString() ?? 'bottom',
      valueAliases: valueAliases,
    );
    return switch (config['legend_position']?.toString()) {
      'top' => Column(children: [legend, Expanded(child: chartWithAxes)]),
      'left' => Row(children: [legend, Expanded(child: chartWithAxes)]),
      'right' => Row(children: [Expanded(child: chartWithAxes), legend]),
      _ => Column(children: [Expanded(child: chartWithAxes), legend]),
    };
  }
}

class _MetricLegend extends StatelessWidget {
  const _MetricLegend({
    required this.points,
    required this.type,
    required this.primaryColor,
    required this.title,
    required this.fontSize,
    required this.position,
    required this.valueAliases,
  });

  final List<MetricPoint> points;
  final String type;
  final Color primaryColor;
  final String title;
  final double fontSize;
  final String position;
  final Map<String, String> valueAliases;

  @override
  Widget build(BuildContext context) {
    final categoryLegend = const {'PIE', 'DONUT', 'FUNNEL'}.contains(type);
    final entries = <({String key, String label, Color color})>[];
    for (final point in points) {
      final key = categoryLegend
          ? point.label
          : '${point.axis}|${point.series}|${point.valueField}';
      if (entries.any((entry) => entry.key == key)) continue;
      final label = categoryLegend
          ? point.label
          : _metricPointSeriesLabel(point, valueAliases);
      final index = entries.length;
      entries.add((
        key: key,
        label: label,
        color: index == 0
            ? primaryColor
            : _metricsPalette[index % _metricsPalette.length],
      ));
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    final vertical = !metricsLegendTitleIsInline(position);
    final items = entries.take(16).map((entry) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MetricLegendMarker(type: type, color: entry.color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _metricsMuted, fontSize: fontSize),
              ),
            ),
          ],
        ),
      );
    }).toList();
    final titleWidget = title.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(5, 2, 8, 3),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _metricsNavy,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
    final content = vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (titleWidget != null) titleWidget,
              ...items,
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (titleWidget != null) titleWidget,
              ...items,
            ],
          );
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: vertical ? 150 : double.infinity,
        maxHeight: vertical ? double.infinity : 72,
      ),
      child: SingleChildScrollView(
        scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
        child: content,
      ),
    );
  }
}

class _MetricLegendMarker extends StatelessWidget {
  const _MetricLegendMarker({required this.type, required this.color});

  final String type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (const {'LINE', 'MULTI_LINE', 'COMBO'}.contains(type)) {
      return SizedBox(
        width: 22,
        height: 10,
        child: CustomPaint(painter: _MetricLegendLinePainter(color)),
      );
    }
    if (type == 'SCATTER' || type == 'PIE' || type == 'DONUT') {
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }
    return Container(
      width: type == 'AREA' ? 20 : 12,
      height: type == 'AREA' ? 8 : 12,
      decoration: BoxDecoration(
        color: type == 'AREA' ? color.withValues(alpha: .25) : color,
        border: type == 'AREA'
            ? Border(top: BorderSide(color: color, width: 2))
            : null,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _MetricLegendLinePainter extends CustomPainter {
  const _MetricLegendLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = color
        ..strokeWidth = 2.2,
    );
    canvas.drawCircle(
      Offset(size.width / 2, y),
      2.8,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _MetricLegendLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _MetricTextObject extends StatelessWidget {
  const _MetricTextObject({required this.config});

  final Map<String, dynamic> config;

  @override
  Widget build(BuildContext context) {
    final shapes = _maps(config['text_shapes']);
    final alignment = switch (config['text_alignment']?.toString()) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
    return Container(
      alignment: switch (alignment) {
        TextAlign.center => Alignment.center,
        TextAlign.right => Alignment.centerRight,
        _ => Alignment.centerLeft,
      },
      padding: const EdgeInsets.all(12),
      color: _color(config['text_background'], Colors.transparent),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: switch (alignment) {
          TextAlign.center => CrossAxisAlignment.center,
          TextAlign.right => CrossAxisAlignment.end,
          _ => CrossAxisAlignment.start,
        },
        children: [
          if (shapes.isNotEmpty) ...[
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: switch (alignment) {
                TextAlign.center => WrapAlignment.center,
                TextAlign.right => WrapAlignment.end,
                _ => WrapAlignment.start,
              },
              children: shapes.map((shape) {
                final size =
                    ((shape['size'] as num?)?.toDouble() ?? 40).clamp(8, 160);
                return SizedBox.square(
                  dimension: size.toDouble(),
                  child: CustomPaint(
                    painter: _MetricShapePainter(
                      type: shape['type']?.toString() ?? 'circle',
                      color: _color(shape['color'], _metricsTeal),
                      borderColor:
                          _color(shape['border_color'], Colors.transparent),
                      borderWidth:
                          (shape['border_width'] as num?)?.toDouble() ?? 0,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
          Flexible(
            child: Text(
              config['text_content']?.toString() ?? '',
              textAlign: alignment,
              overflow: TextOverflow.fade,
              style: TextStyle(
                color: _color(config['text_color'], _metricsNavy),
                fontSize: (config['text_size'] as num?)?.toDouble() ?? 24,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricShapePainter extends CustomPainter {
  const _MetricShapePainter({
    required this.type,
    required this.color,
    required this.borderColor,
    required this.borderWidth,
  });

  final String type;
  final Color color;
  final Color borderColor;
  final double borderWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeWidth = math.max(2, size.shortestSide * .08)
      ..strokeCap = StrokeCap.round;
    if (type == 'line') {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint..style = PaintingStyle.stroke,
      );
      return;
    }
    void drawBorder(Path path) {
      if (borderWidth <= 0 || borderColor.a == 0) return;
      canvas.drawPath(
        path,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth,
      );
    }

    if (type == 'square') {
      final path = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Offset.zero & size,
            Radius.circular(size.shortestSide * .10),
          ),
        );
      canvas.drawPath(path, paint);
      drawBorder(path);
      return;
    }
    if (type == 'diamond') {
      final path = Path()
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height / 2)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(0, size.height / 2)
        ..close();
      canvas.drawPath(path, paint);
      drawBorder(path);
      return;
    }
    if (type == 'hexagon') {
      final path = Path()
        ..moveTo(size.width * .25, 0)
        ..lineTo(size.width * .75, 0)
        ..lineTo(size.width, size.height / 2)
        ..lineTo(size.width * .75, size.height)
        ..lineTo(size.width * .25, size.height)
        ..lineTo(0, size.height / 2)
        ..close();
      canvas.drawPath(path, paint);
      drawBorder(path);
      return;
    }
    if (type == 'arrow') {
      final path = Path()
        ..moveTo(0, size.height * .34)
        ..lineTo(size.width * .60, size.height * .34)
        ..lineTo(size.width * .60, 0)
        ..lineTo(size.width, size.height / 2)
        ..lineTo(size.width * .60, size.height)
        ..lineTo(size.width * .60, size.height * .66)
        ..lineTo(0, size.height * .66)
        ..close();
      canvas.drawPath(path, paint);
      drawBorder(path);
      return;
    }
    if (type == 'heart') {
      final path = Path()
        ..moveTo(size.width / 2, size.height)
        ..cubicTo(-size.width * .08, size.height * .58, 0, size.height * .12,
            size.width * .25, size.height * .12)
        ..cubicTo(size.width * .40, size.height * .12, size.width * .50,
            size.height * .25, size.width / 2, size.height * .34)
        ..cubicTo(size.width * .50, size.height * .25, size.width * .60,
            size.height * .12, size.width * .75, size.height * .12)
        ..cubicTo(size.width, size.height * .12, size.width * 1.08,
            size.height * .58, size.width / 2, size.height)
        ..close();
      canvas.drawPath(path, paint);
      drawBorder(path);
      return;
    }
    if (type == 'star') {
      final path = Path();
      final center = Offset(size.width / 2, size.height / 2);
      final outer = size.shortestSide / 2;
      final inner = outer * .43;
      for (var index = 0; index < 10; index++) {
        final radius = index.isEven ? outer : inner;
        final angle = -math.pi / 2 + index * math.pi / 5;
        final point = Offset(
          center.dx + math.cos(angle) * radius,
          center.dy + math.sin(angle) * radius,
        );
        if (index == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
      drawBorder(path);
      return;
    }

    if (type == 'triangle') {
      final path = Path()
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(path, paint);
      drawBorder(path);
      return;
    }
    canvas.drawOval(Offset.zero & size, paint);
    if (borderWidth > 0 && borderColor.a > 0) {
      canvas.drawOval(
        Offset.zero & size,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MetricShapePainter oldDelegate) =>
      oldDelegate.type != type ||
      oldDelegate.color != color ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.borderWidth != borderWidth;
}

class _ScrollableMetricChart extends StatefulWidget {
  const _ScrollableMetricChart({
    required this.points,
    required this.painter,
    required this.valueAliases,
  });

  final List<MetricPoint> points;
  final _MetricChartPainter painter;
  final Map<String, String> valueAliases;

  @override
  State<_ScrollableMetricChart> createState() => _ScrollableMetricChartState();
}

class _ScrollableMetricChartState extends State<_ScrollableMetricChart> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.points.map((point) => point.label).toSet().length;
    return LayoutBuilder(builder: (context, constraints) {
      final contentWidth = math.max(
        constraints.maxWidth,
        labels > 14 ? labels * 54.0 : constraints.maxWidth,
      );
      final scrollable = contentWidth > constraints.maxWidth + 1;
      final content = SizedBox(
        width: contentWidth,
        height: constraints.maxHeight,
        child: _MetricChartHover(
          points: widget.points,
          painter: widget.painter,
          valueAliases: widget.valueAliases,
        ),
      );
      if (!scrollable) return content;
      return Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: content,
        ),
      );
    });
  }
}

class _MetricChartHover extends StatefulWidget {
  const _MetricChartHover({
    required this.points,
    required this.painter,
    required this.valueAliases,
  });

  final List<MetricPoint> points;
  final _MetricChartPainter painter;
  final Map<String, String> valueAliases;

  @override
  State<_MetricChartHover> createState() => _MetricChartHoverState();
}

class _MetricChartHoverState extends State<_MetricChartHover> {
  Offset? _pointer;
  String? _label;

  @override
  Widget build(BuildContext context) {
    final labels = <String>[];
    for (final point in widget.points) {
      if (!labels.contains(point.label)) labels.add(point.label);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        void update(PointerHoverEvent event) {
          if (labels.isEmpty) return;
          const left = 38.0;
          final right =
              widget.points.any((point) => point.axis == 'y2') ? 42.0 : 10.0;
          final plotWidth = math.max(1.0, constraints.maxWidth - left - right);
          final relative =
              ((event.localPosition.dx - left) / plotWidth).clamp(0.0, .999999);
          final index = (relative * labels.length).floor();
          setState(() {
            _pointer = event.localPosition;
            _label = labels[index];
          });
        }

        final hovered = widget.points
            .where((point) => point.label == _label)
            .toList(growable: false);
        return MouseRegion(
          onHover: update,
          onExit: (_) => setState(() {
            _pointer = null;
            _label = null;
          }),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: widget.painter,
                  child: const SizedBox.expand(),
                ),
              ),
              if (_pointer != null && hovered.isNotEmpty)
                Positioned(
                  left: math.min(math.max(4, _pointer!.dx + 10),
                      math.max(4, constraints.maxWidth - 210)),
                  top: math.min(math.max(4, _pointer!.dy - 24),
                      math.max(4, constraints.maxHeight - 120)),
                  child: IgnorePointer(
                    child: Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(9),
                      child: Container(
                        width: 200,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFDFDFEFF),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: const Color(0xFFD7E1E6)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_label!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            ...hovered.take(5).map((point) => Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '${_metricPointSeriesLabel(point, widget.valueAliases)}: ${_formatNumber(point.value)}${point.axis == 'y2' ? ' · Y2' : ''}${point.detail.isEmpty ? '' : '\n${point.detail}'}',
                                    maxLines: point.detail.isEmpty ? 1 : 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricTable extends StatelessWidget {
  const _MetricTable({required this.dataset, required this.valueAliases});
  final MetricDataset dataset;
  final Map<String, String> valueAliases;

  @override
  Widget build(BuildContext context) {
    final points = dataset.points.take(100).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SingleChildScrollView(
        child: Table(
          border: TableBorder(
              horizontalInside:
                  BorderSide(color: Colors.blueGrey.withValues(alpha: .16))),
          columnWidths: const {1: FixedColumnWidth(100)},
          children: [
            const TableRow(
                decoration: BoxDecoration(color: Color(0xFFF0F5F7)),
                children: [
                  Padding(
                      padding: EdgeInsets.all(9),
                      child: Text('Categoría',
                          style: TextStyle(fontWeight: FontWeight.w800))),
                  Padding(
                      padding: EdgeInsets.all(9),
                      child: Text('Valor',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontWeight: FontWeight.w800))),
                ]),
            ...points.map((point) => TableRow(children: [
                  Padding(
                      padding: const EdgeInsets.all(9),
                      child: Text(
                          point.series.isEmpty
                              ? point.label
                              : '${point.label} · ${_metricPointSeriesLabel(point, valueAliases)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                  Padding(
                      padding: const EdgeInsets.all(9),
                      child: Text(_formatNumber(point.value),
                          textAlign: TextAlign.right)),
                ])),
          ],
        ),
      ),
    );
  }
}

class _MetricChartPainter extends CustomPainter {
  _MetricChartPainter(
      {required this.points,
      required this.type,
      required this.color,
      required this.seriesWidth,
      required this.seriesStyle,
      required this.barWidthRatio,
      required this.trendline,
      required this.trendColor,
      required this.trendWidth,
      required this.trendStyle,
      required this.trendOpacity,
      this.conditionValue,
      required this.conditionOperator,
      required this.conditionColor,
      this.alertValue,
      required this.alertColor,
      required this.alertWidth,
      required this.alertStyle,
      required this.alertOpacity,
      required this.alertLines,
      required this.dataLabelProfiles,
      this.yMinimum,
      this.yMaximum,
      this.y2Minimum,
      this.y2Maximum});
  final List<MetricPoint> points;
  final String type;
  final Color color;
  final double seriesWidth;
  final String seriesStyle;
  final double barWidthRatio;
  final bool trendline;
  final Color trendColor;
  final double trendWidth;
  final String trendStyle;
  final double trendOpacity;
  final dynamic conditionValue;
  final String conditionOperator;
  final Color conditionColor;
  final double? alertValue;
  final Color alertColor;
  final double alertWidth;
  final String alertStyle;
  final double alertOpacity;
  final List<Map<String, dynamic>> alertLines;
  final Map<String, dynamic> dataLabelProfiles;
  final double? yMinimum;
  final double? yMaximum;
  final double? y2Minimum;
  final double? y2Maximum;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 20 || size.height <= 20) return;
    if (type == 'PIE' || type == 'DONUT') {
      _paintPie(canvas, size, donut: type == 'DONUT');
      return;
    }
    if (type == 'FUNNEL') {
      _paintFunnel(canvas, size);
      return;
    }
    const left = 38.0;
    final dimensionDepth = points.fold<int>(
      1,
      (depth, point) => math.max(depth, point.dimensionValues.length),
    );
    final bottom = 18.0 + dimensionDepth * 18.0;
    const top = 12.0;
    final hasSecondaryAxis = points.any((point) => point.axis == 'y2');
    final right = hasSecondaryAxis ? 42.0 : 10.0;
    final plot =
        Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    final primaryPoints = points.where((point) => point.axis != 'y2');
    final secondaryPoints = points.where((point) => point.axis == 'y2');
    final detectedMaxPrimary = primaryPoints.isEmpty
        ? 0.0
        : primaryPoints.map((point) => point.value).fold<double>(0, math.max);
    final detectedMinPrimary = primaryPoints.isEmpty
        ? 0.0
        : primaryPoints.map((point) => point.value).fold<double>(0, math.min);
    final detectedMaxSecondary = secondaryPoints.isEmpty
        ? 0.0
        : secondaryPoints.map((point) => point.value).fold<double>(0, math.max);
    final detectedMinSecondary = secondaryPoints.isEmpty
        ? 0.0
        : secondaryPoints.map((point) => point.value).fold<double>(0, math.min);
    final minY = yMinimum ?? math.min(0, detectedMinPrimary);
    final maxY = yMaximum ??
        (detectedMaxPrimary <= minY ? minY + 1 : detectedMaxPrimary * 1.12);
    final minY2 = y2Minimum ?? math.min(0, detectedMinSecondary);
    final maxY2 = y2Maximum ??
        (detectedMaxSecondary <= minY2
            ? minY2 + 1
            : detectedMaxSecondary * 1.12);
    final rangeY = math.max(.000001, maxY - minY);
    final rangeY2 = math.max(.000001, maxY2 - minY2);
    final axis = Paint()
      ..color = const Color(0xFFD7E1E6)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = plot.bottom - plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), axis);
      _label(canvas, _formatNumber(minY + rangeY * i / 4), Offset(0, y - 6), 34,
          align: TextAlign.right, size: 9);
      if (hasSecondaryAxis) {
        _label(
          canvas,
          _formatNumber(minY2 + rangeY2 * i / 4),
          Offset(plot.right + 4, y - 6),
          36,
          size: 9,
        );
      }
    }
    final labels = <String>[];
    final labelDimensions = <String, List<String>>{};
    for (final point in points) {
      if (!labels.contains(point.label)) {
        labels.add(point.label);
        labelDimensions[point.label] = point.dimensionValues.isEmpty
            ? <String>[point.label]
            : point.dimensionValues;
      }
    }
    final step = plot.width / math.max(1, labels.length);
    for (var dimensionIndex = dimensionDepth - 1;
        dimensionIndex >= 0;
        dimensionIndex--) {
      final row = dimensionDepth - 1 - dimensionIndex;
      var start = 0;
      while (start < labels.length) {
        final dimensions = labelDimensions[labels[start]]!;
        final value = dimensionIndex < dimensions.length
            ? dimensions[dimensionIndex]
            : '';
        final prefix = dimensions
            .take(math.min(dimensionIndex + 1, dimensions.length))
            .join('\u0000');
        var end = start + 1;
        while (end < labels.length) {
          final next = labelDimensions[labels[end]]!;
          final nextPrefix = next
              .take(math.min(dimensionIndex + 1, next.length))
              .join('\u0000');
          if (nextPrefix != prefix) break;
          end++;
        }
        final left = plot.left + step * start;
        final width = step * (end - start);
        final top = plot.bottom + 4 + row * 18;
        _label(
          canvas,
          value,
          Offset(left, top),
          width,
          align: TextAlign.center,
          size: 9,
        );
        if (dimensionIndex < dimensionDepth - 1 && end - start > 1) {
          canvas.drawLine(
            Offset(left + 2, top - 2),
            Offset(left + width - 2, top - 2),
            Paint()
              ..color = const Color(0xFFD7E1E6)
              ..strokeWidth = .8,
          );
        }
        start = end;
      }
    }

    double pointY(MetricPoint point) {
      final minimum = point.axis == 'y2' ? minY2 : minY;
      final range = point.axis == 'y2' ? rangeY2 : rangeY;
      return plot.bottom - ((point.value - minimum) / range) * plot.height;
    }

    bool isBarPoint(MetricPoint point) =>
        type == 'BAR' ||
        type == 'STACKED_BAR' ||
        (type == 'COMBO' && point.axis != 'y2');

    final seriesNames = <String>[];
    for (final point in points) {
      final name = '${point.axis}|${point.series}|${point.valueField}';
      if (!seriesNames.contains(name)) seriesNames.add(name);
    }
    Color pointColor(MetricPoint point) {
      if (conditionValue?.toString().trim().isNotEmpty == true &&
          _conditionMatchesRaw(
              point.value, conditionOperator, conditionValue)) {
        return conditionColor;
      }
      final key = '${point.axis}|${point.series}|${point.valueField}';
      final index = math.max(0, seriesNames.indexOf(key));
      return index == 0
          ? color
          : _metricsPalette[index % _metricsPalette.length];
    }

    for (var labelIndex = 0; labelIndex < labels.length; labelIndex++) {
      final label = labels[labelIndex];
      final barPoints = points
          .where((point) => point.label == label && isBarPoint(point))
          .toList(growable: false);
      if (barPoints.isEmpty) continue;
      final centerX = plot.left + step * labelIndex + step / 2;
      final available = math.min(step * barWidthRatio.clamp(.2, 1), 54.0);
      final barWidth = math.max(3.0, available / barPoints.length);
      for (var index = 0; index < barPoints.length; index++) {
        final point = barPoints[index];
        final x = centerX - available / 2 + barWidth * index + barWidth / 2;
        final y = pointY(point);
        final baseline = point.axis == 'y2'
            ? plot.bottom - ((0 - minY2) / rangeY2) * plot.height
            : plot.bottom - ((0 - minY) / rangeY) * plot.height;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(x - barWidth * .43, math.min(y, baseline),
                x + barWidth * .43, math.max(y, baseline)),
            const Radius.circular(4),
          ),
          Paint()..color = pointColor(point),
        );
        _paintDataLabel(canvas, point, Offset(x, y), pointColor(point));
      }
    }

    final lineGroups = <String, List<MetricPoint>>{};
    for (final point in points) {
      final linePoint = type == 'LINE' ||
          type == 'MULTI_LINE' ||
          type == 'AREA' ||
          type == 'SCATTER' ||
          (type == 'COMBO' && point.axis == 'y2');
      if (!linePoint) continue;
      final key = '${point.axis}|${point.series}|${point.valueField}';
      lineGroups.putIfAbsent(key, () => []).add(point);
    }
    for (final group in lineGroups.values) {
      group.sort(
          (a, b) => labels.indexOf(a.label).compareTo(labels.indexOf(b.label)));
      final path = Path();
      final areaPath = Path();
      for (var index = 0; index < group.length; index++) {
        final point = group[index];
        final labelIndex = labels.indexOf(point.label);
        final x = plot.left + step * labelIndex + step / 2;
        final y = pointY(point);
        if (index == 0) {
          path.moveTo(x, y);
          areaPath
            ..moveTo(x, plot.bottom)
            ..lineTo(x, y);
        } else {
          path.lineTo(x, y);
          areaPath.lineTo(x, y);
        }
        canvas.drawCircle(Offset(x, y), type == 'SCATTER' ? 4.5 : 3.2,
            Paint()..color = pointColor(point));
        _paintDataLabel(canvas, point, Offset(x, y), pointColor(point));
      }
      if (type == 'AREA' && group.isNotEmpty) {
        final lastIndex = labels.indexOf(group.last.label);
        areaPath
          ..lineTo(plot.left + step * lastIndex + step / 2, plot.bottom)
          ..close();
        canvas.drawPath(areaPath,
            Paint()..color = pointColor(group.first).withValues(alpha: .16));
      }
      if (type != 'SCATTER') {
        _drawStyledPath(
          canvas,
          path,
          Paint()
            ..color = pointColor(group.first)
            ..strokeWidth = seriesWidth
            ..style = PaintingStyle.stroke,
          seriesStyle,
        );
      }
    }
    if (trendline && points.length >= 2) {
      final y1 = pointY(points.first);
      final y2 = pointY(points.last);
      _drawStyledLine(
          canvas,
          Offset(plot.left + step / 2, y1),
          Offset(plot.right - step / 2, y2),
          Paint()
            ..color = trendColor.withValues(alpha: trendOpacity)
            ..strokeWidth = trendWidth
            ..style = PaintingStyle.stroke,
          trendStyle);
    }
    final configuredAlertLines = alertLines.isEmpty && alertValue != null
        ? <Map<String, dynamic>>[
            {
              'value': alertValue,
              'color': alertColor,
              'width': alertWidth,
              'style': alertStyle,
              'opacity': alertOpacity,
            }
          ]
        : alertLines;
    for (final line in configuredAlertLines) {
      final value = _number(line['value']);
      if (value == null) continue;
      final y = plot.bottom - ((value - minY) / rangeY) * plot.height;
      _drawStyledLine(
        canvas,
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()
          ..color = _color(line['color'], alertColor).withValues(
              alpha: (line['opacity'] as num?)?.toDouble() ?? alertOpacity)
          ..strokeWidth = (line['width'] as num?)?.toDouble() ?? alertWidth,
        line['style']?.toString() ?? alertStyle,
      );
    }
  }

  void _paintDataLabel(
    Canvas canvas,
    MetricPoint point,
    Offset anchor,
    Color fallbackColor,
  ) {
    if (dataLabelProfiles.isEmpty) return;
    Map<String, dynamic>? profile;
    for (final entry in dataLabelProfiles.entries) {
      if (entry.value is! Map) continue;
      final fields = entry.key.split('|');
      if (entry.key == '*' || fields.contains(point.valueField)) {
        profile = Map<String, dynamic>.from(entry.value as Map);
        if (entry.key != '*') break;
      }
    }
    if (profile == null || profile['visible'] == false) return;
    var textColor = _color(profile['color'], fallbackColor);
    for (final condition in _maps(profile['conditions'])) {
      if (_conditionMatchesRaw(
        point.value,
        condition['operator']?.toString(),
        condition['value'],
      )) {
        textColor = _color(condition['color'], textColor);
      }
    }
    final decimals = (profile['decimals'] as num?)?.toInt().clamp(0, 6) ?? 0;
    final units = profile['units']?.toString() ?? 'none';
    var displayValue = point.value;
    var suffix = '';
    if (units == 'thousands') {
      displayValue /= 1000;
      suffix = ' mil';
    } else if (units == 'millions') {
      displayValue /= 1000000;
      suffix = ' M';
    } else if (units == 'billions') {
      displayValue /= 1000000000;
      suffix = ' B';
    }
    final painter = TextPainter(
      text: TextSpan(
        text: '${displayValue.toStringAsFixed(decimals)}$suffix',
        style: TextStyle(
          color: textColor.withValues(
              alpha: (profile['opacity'] as num?)?.toDouble() ?? 1),
          fontSize: (profile['size'] as num?)?.toDouble() ?? 11,
          fontFamily: profile['font']?.toString(),
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final padding = (profile['padding'] as num?)?.toDouble() ?? 4;
    final position = profile['position']?.toString() ?? 'above';
    var top = anchor.dy - painter.height - padding - 3;
    if (position == 'below') top = anchor.dy + padding + 3;
    if (position == 'center' || position == 'inside') {
      top = anchor.dy + padding;
    }
    final offset = Offset(anchor.dx - painter.width / 2, top);
    final background = _color(profile['background'], Colors.transparent);
    if (background.a > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(offset.dx - 3, offset.dy - 2, painter.width + 6,
              painter.height + 4),
          const Radius.circular(3),
        ),
        Paint()
          ..color = background.withValues(
              alpha: (profile['opacity'] as num?)?.toDouble() ?? 1),
      );
    }
    painter.paint(canvas, offset);
  }

  void _drawStyledLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
    String style,
  ) {
    if (style == 'solid') {
      canvas.drawLine(start, end, paint);
      return;
    }
    final distance = (end - start).distance;
    if (distance <= 0) return;
    final direction = (end - start) / distance;
    final segment = style == 'dot' ? 1.5 : 7.0;
    final gap = style == 'dot' ? 5.0 : 6.0;
    for (double offset = 0; offset < distance; offset += segment + gap) {
      canvas.drawLine(
        start + direction * offset,
        start + direction * math.min(offset + segment, distance),
        paint..strokeCap = style == 'dot' ? StrokeCap.round : StrokeCap.butt,
      );
    }
  }

  void _drawStyledPath(Canvas canvas, Path path, Paint paint, String style) {
    if (style == 'solid') {
      canvas.drawPath(path, paint);
      return;
    }
    final segment = style == 'dot' ? 1.5 : 7.0;
    final gap = style == 'dot' ? 5.0 : 6.0;
    for (final metric in path.computeMetrics()) {
      for (double offset = 0; offset < metric.length; offset += segment + gap) {
        canvas.drawPath(
          metric.extractPath(offset, math.min(offset + segment, metric.length)),
          paint..strokeCap = style == 'dot' ? StrokeCap.round : StrokeCap.butt,
        );
      }
    }
  }

  void _paintPie(Canvas canvas, Size size, {required bool donut}) {
    final total =
        points.fold<double>(0, (sum, point) => sum + math.max(0, point.value));
    if (total <= 0) return;
    final center = Offset(size.width * .43, size.height * .48);
    final radius = math.min(size.width, size.height) * .30;
    var start = -math.pi / 2;
    for (var i = 0; i < points.length; i++) {
      final sweep = math.max(0, points[i].value) / total * math.pi * 2;
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          start,
          sweep,
          true,
          Paint()..color = _metricsPalette[i % _metricsPalette.length]);
      start += sweep;
    }
    if (donut) {
      canvas.drawCircle(center, radius * .48, Paint()..color = Colors.white);
      _label(canvas, _formatNumber(total),
          Offset(center.dx - radius * .38, center.dy - 9), radius * .76,
          align: TextAlign.center, size: 13, bold: true);
    }
  }

  void _paintFunnel(Canvas canvas, Size size) {
    final ordered = [...points]..sort((a, b) => b.value.compareTo(a.value));
    final visible = ordered.take(8).toList();
    final maxValue = visible.first.value.abs();
    if (maxValue <= 0) return;
    final centerX = size.width * .45;
    final availableWidth = size.width * .72;
    final rowHeight = math.min(38.0, (size.height - 20) / visible.length);
    for (var i = 0; i < visible.length; i++) {
      final ratio = visible[i].value.abs() / maxValue;
      final width = math.max(54.0, availableWidth * ratio);
      final top = 10.0 + i * rowHeight;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(centerX - width / 2, top, width, rowHeight - 4),
        const Radius.circular(5),
      );
      canvas.drawRRect(
          rect, Paint()..color = _metricsPalette[i % _metricsPalette.length]);
      _label(canvas, visible[i].label, Offset(centerX + width / 2 + 8, top + 6),
          size.width * .24,
          size: 9);
    }
  }

  void _label(Canvas canvas, String text, Offset offset, double width,
      {TextAlign align = TextAlign.left, double size = 10, bool bold = false}) {
    final painter = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                color: _metricsMuted,
                fontSize: size,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
        textDirection: TextDirection.ltr,
        textAlign: align,
        maxLines: 1,
        ellipsis: '…')
      ..layout(maxWidth: width);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _MetricChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.type != type ||
      oldDelegate.color != color ||
      oldDelegate.seriesWidth != seriesWidth ||
      oldDelegate.seriesStyle != seriesStyle ||
      oldDelegate.barWidthRatio != barWidthRatio ||
      oldDelegate.trendline != trendline ||
      oldDelegate.trendColor != trendColor ||
      oldDelegate.trendWidth != trendWidth ||
      oldDelegate.trendStyle != trendStyle ||
      oldDelegate.trendOpacity != trendOpacity ||
      oldDelegate.conditionValue != conditionValue ||
      oldDelegate.conditionOperator != conditionOperator ||
      oldDelegate.conditionColor != conditionColor ||
      oldDelegate.alertValue != alertValue ||
      oldDelegate.alertColor != alertColor ||
      oldDelegate.alertWidth != alertWidth ||
      oldDelegate.alertStyle != alertStyle ||
      oldDelegate.alertOpacity != alertOpacity ||
      oldDelegate.alertLines != alertLines ||
      oldDelegate.dataLabelProfiles != dataLabelProfiles ||
      oldDelegate.yMinimum != yMinimum ||
      oldDelegate.yMaximum != yMaximum ||
      oldDelegate.y2Minimum != y2Minimum ||
      oldDelegate.y2Maximum != y2Maximum;
}

// -----------------------------------------------------------------------------
// Pequeños componentes y conversiones tolerantes.
// -----------------------------------------------------------------------------

class _MetricValuePickerDialog extends StatefulWidget {
  const _MetricValuePickerDialog({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final Map<String, String> options;
  final String selected;

  @override
  State<_MetricValuePickerDialog> createState() =>
      _MetricValuePickerDialogState();
}

class _MetricValuePickerDialogState extends State<_MetricValuePickerDialog> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final visible = widget.options.entries
        .where((entry) =>
            entry.value.toLowerCase().contains(_search.trim().toLowerCase()))
        .toList(growable: false);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 450,
        height: 470,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Buscar valor…',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (_, index) {
                  final entry = visible[index];
                  return ListTile(
                    leading: Icon(
                      entry.key == widget.selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: entry.key == widget.selected
                          ? _metricsTeal
                          : _metricsMuted,
                    ),
                    title: Text(entry.value),
                    onTap: () => Navigator.pop(context, entry.key),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class _SearchSelectionField extends StatelessWidget {
  const _SearchSelectionField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final Map<String, String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final validValue = options.containsKey(value) ? value : null;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: options.isEmpty
          ? null
          : () async {
              var search = '';
              final selected = await showDialog<String>(
                context: context,
                builder: (dialogContext) => StatefulBuilder(
                  builder: (context, setDialogState) {
                    final visible = options.entries
                        .where((entry) =>
                            entry.key
                                .toLowerCase()
                                .contains(search.toLowerCase()) ||
                            entry.value
                                .toLowerCase()
                                .contains(search.toLowerCase()))
                        .toList(growable: false);
                    return AlertDialog(
                      title: Text('Seleccionar $label'),
                      content: SizedBox(
                        width: 460,
                        height: 470,
                        child: Column(
                          children: [
                            TextField(
                              autofocus: true,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search_rounded),
                                hintText: 'Buscar…',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (next) =>
                                  setDialogState(() => search = next.trim()),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: visible.isEmpty
                                  ? const Center(
                                      child: Text('No hay coincidencias.'))
                                  : ListView.builder(
                                      itemCount: visible.length,
                                      itemBuilder: (_, index) {
                                        final entry = visible[index];
                                        return ListTile(
                                          leading: Icon(
                                            entry.key == validValue
                                                ? Icons.radio_button_checked
                                                : Icons.radio_button_off,
                                            color: entry.key == validValue
                                                ? _metricsTeal
                                                : _metricsMuted,
                                          ),
                                          title: Text(entry.value),
                                          subtitle: entry.key == entry.value
                                              ? null
                                              : Text(entry.key),
                                          onTap: () => Navigator.pop(
                                              dialogContext, entry.key),
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
                      ],
                    );
                  },
                ),
              );
              if (selected != null) onChanged(selected);
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: const Icon(Icons.expand_more_rounded),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: Text(
          validValue == null ? 'Buscar y seleccionar' : options[validValue]!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: validValue == null ? _metricsMuted : _metricsNavy,
            fontWeight: validValue == null ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ResponsiveFieldRow extends StatelessWidget {
  const _ResponsiveFieldRow({required this.desktop, required this.children});
  final bool desktop;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => desktop
      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < children.length; i++) ...[
            Expanded(child: children[i]),
            if (i < children.length - 1) const SizedBox(width: 12)
          ]
        ])
      : Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) const SizedBox(height: 12)
          ]
        ]);
}

class _BuilderSection extends StatelessWidget {
  const _BuilderSection(
      {required this.number, required this.title, required this.text});
  final String number;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
            radius: 17,
            backgroundColor: _metricsTeal,
            foregroundColor: Colors.white,
            child: Text(number,
                style: const TextStyle(fontWeight: FontWeight.w800))),
        const SizedBox(width: 11),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: _metricsNavy,
                  fontSize: 19,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(text, style: const TextStyle(color: _metricsMuted))
        ])),
      ]);
}

class _MetricsEmpty extends StatelessWidget {
  const _MetricsEmpty(
      {required this.icon,
      required this.title,
      required this.text,
      this.action});
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(30),
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 52, color: _metricsTeal),
                const SizedBox(height: 14),
                Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: _metricsNavy,
                        fontSize: 23,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 7),
                Text(text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _metricsMuted, height: 1.45)),
                if (action != null) ...[const SizedBox(height: 18), action!]
              ]))));
}

class _MetricsError extends StatelessWidget {
  const _MetricsError({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => _MetricsEmpty(
      icon: Icons.error_outline,
      title: 'No se pudo abrir Metrics',
      text: message,
      action: FilledButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar')));
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

Map<String, dynamic> _deepMap(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false)
    : const [];

Color _color(dynamic value, Color fallback) {
  final raw = value?.toString().trim() ?? '';
  if (raw.toLowerCase() == 'transparent' || raw.toLowerCase() == 'sin color') {
    return Colors.transparent;
  }
  final rgb = RegExp(
          r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)$',
          caseSensitive: false)
      .firstMatch(raw);
  if (rgb != null) {
    final red = int.parse(rgb.group(1)!).clamp(0, 255);
    final green = int.parse(rgb.group(2)!).clamp(0, 255);
    final blue = int.parse(rgb.group(3)!).clamp(0, 255);
    final alpha =
        ((double.tryParse(rgb.group(4) ?? '1') ?? 1).clamp(0, 1) * 255).round();
    return Color.fromARGB(alpha, red, green, blue);
  }
  final text = raw.replaceAll('#', '');
  final parsed = int.tryParse(text.length == 6 ? 'FF$text' : text, radix: 16);
  return parsed == null ? fallback : Color(parsed);
}

Color _colorWithOpacity(Color color, double opacity) {
  final sourceAlpha = (color.toARGB32() >> 24) & 0xFF;
  if (sourceAlpha == 0) return Colors.transparent;
  return color.withValues(
    alpha: (opacity.clamp(0.0, 1.0) * sourceAlpha / 255).toDouble(),
  );
}

double? _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().trim().replaceAll(',', '.') ?? '');
}

bool _conditionMatchesRaw(double value, String? operator, dynamic rawValue) {
  final raw = rawValue?.toString().trim() ?? '';
  if (operator == 'between') {
    final limits = raw
        .split(RegExp(r'\s*(?:,|;|\.\.|\ba\b)\s*', caseSensitive: false))
        .map(_number)
        .whereType<double>()
        .toList();
    if (limits.length < 2) return false;
    final minimum = math.min(limits[0], limits[1]);
    final maximum = math.max(limits[0], limits[1]);
    return value >= minimum && value <= maximum;
  }
  final threshold = _number(rawValue);
  if (threshold == null) return false;
  switch (operator) {
    case 'lt':
      return value < threshold;
    case 'lte':
      return value <= threshold;
    case 'gte':
      return value >= threshold;
    case 'eq':
      return value == threshold;
    case 'neq':
      return value != threshold;
    case 'contains':
      return value.toString().contains(raw);
    default:
      return value > threshold;
  }
}

Color _colorFromHex(String value) => _color(value, _metricsTeal);

String _metricPointSeriesLabel(
  MetricPoint point,
  Map<String, String> aliases,
) {
  final field = point.valueField.trim();
  final series = point.series.trim();
  final alias = aliases[field]?.trim() ?? '';
  if (alias.isEmpty) {
    if (series.isNotEmpty) return series;
    return field.isNotEmpty ? field : 'Serie';
  }
  if (series.isEmpty || series == field) return alias;
  final fieldSuffix = ' · $field';
  if (series.endsWith(fieldSuffix)) {
    return '${series.substring(0, series.length - fieldSuffix.length)} · $alias';
  }
  return series;
}

String _formatNumber(double value) {
  if (value.abs() >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)} M';
  }
  if (value.abs() >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)} K';
  }
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(2);
}
