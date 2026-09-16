import 'dart:async';

import 'package:flutter/material.dart' hide ScaffoldMessenger;

import '../../core/services/sync_service.dart';
import '../../core/widgets/zumac_feature_header.dart';
import '../../core/widgets/zumac_scaffold_messenger.dart';
import 'alerts_actions_repository.dart';

const _navy = Color(0xFF17324D);
const _muted = Color(0xFF60758A);
const _teal = Color(0xFF176B87);
const _orange = Color(0xFFC56A13);
const _rose = Color(0xFFB4425A);

/// Petición que Alerts devuelve a la pantalla principal para abrir los datos
/// o el dashboard asociados al último hallazgo de una regla.
class AlertNavigationTarget {
  const AlertNavigationTarget({
    required this.tableName,
    this.moduleId,
    this.formatId,
    this.recordField,
    this.recordValue,
    this.openChart = false,
  });

  final String tableName;
  final String? moduleId;
  final String? formatId;
  final String? recordField;
  final String? recordValue;
  final bool openChart;
}

/// Centro operativo de reglas, eventos y tareas de la empresa activa.
class AlertsActionsPage extends StatefulWidget {
  const AlertsActionsPage({
    super.key,
    this.initialTab = 0,
    this.embedded = false,
    this.onNavigate,
  });

  final int initialTab;
  final bool embedded;
  final Future<void> Function(AlertNavigationTarget target)? onNavigate;

  @override
  State<AlertsActionsPage> createState() => _AlertsActionsPageState();
}

class _AlertsActionsPageState extends State<AlertsActionsPage>
    with SingleTickerProviderStateMixin {
  final _repository = AlertsActionsRepository();
  final _sync = SyncService();
  late final TabController _tabs;
  Timer? _refreshTimer;
  Map<String, dynamic> _context = const {};
  List<Map<String, dynamic>> _rules = const [];
  List<Map<String, dynamic>> _events = const [];
  List<Map<String, dynamic>> _actions = const [];
  Set<String> _tablesWithMetrics = const {};
  bool _loading = true;
  bool _working = false;
  String? _error;

  bool get _canManage => _context['puede_gestionar'] == true;
  bool get _alertsEnabled => _context['alerts_habilitado'] == true;
  bool get _actionsEnabled => _context['actions_habilitado'] == true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    unawaited(_load());
    // Realtime está preparado en Supabase. Este refresco de respaldo también
    // mantiene la bandeja vigente en navegadores que suspenden WebSockets.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => unawaited(_load(silent: true)),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final values = await Future.wait<dynamic>([
        _repository.loadContext(),
        _repository.listRules(),
        _repository.listEvents(),
        _repository.listActions(),
        _repository.listTablesWithMetrics(),
      ]);
      if (!mounted) return;
      setState(() {
        _context = values[0] as Map<String, dynamic>;
        _rules = values[1] as List<Map<String, dynamic>>;
        _events = values[2] as List<Map<String, dynamic>>;
        _actions = values[3] as List<Map<String, dynamic>>;
        _tablesWithMetrics = values[4] as Set<String>;
        _error = null;
      });
    } catch (error) {
      if (mounted && !silent) setState(() => _error = '$error');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _refreshAllData() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await _sync.downloadAllForOffline(
        allowFullFallback: false,
        forceConfigurationRefresh: true,
      );
      await _load(silent: true);
      if (mounted) _message('Datos y configuración actualizados.');
    } catch (error) {
      if (mounted) _message(_sync.friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _evaluate() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final result = await _repository.evaluateNow();
      if (!mounted) return;
      _message(
        'Evaluación terminada: ${result['reglas_evaluadas'] ?? 0} reglas y '
        '${result['eventos_creados'] ?? 0} eventos nuevos.',
      );
      await _load(silent: true);
    } catch (error) {
      if (mounted) _message('No se pudo evaluar: $error', error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? const Color(0xFF9F2F42) : null,
      ),
    );
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
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _toggleRule(Map<String, dynamic> rule, bool active) async {
    try {
      await _repository.setRuleActive('${rule['id']}', active);
      await _load(silent: true);
    } catch (error) {
      if (mounted) _message('No se pudo cambiar la regla: $error', error: true);
    }
  }

  Future<void> _deleteRule(Map<String, dynamic> rule) async {
    if (!await _confirm(
      'Eliminar alerta',
      'Se quitará la regla y su aviso actual. Los datos del formato no se modificarán.',
    )) {
      return;
    }
    try {
      await _repository.deleteRule('${rule['id']}');
      await _load(silent: true);
    } catch (error) {
      if (mounted) _message('No se pudo eliminar: $error', error: true);
    }
  }

  Future<void> _deleteAction(Map<String, dynamic> action) async {
    if (!await _confirm(
      'Eliminar acción',
      'La acción se archivará como cancelada; no se borrarán los datos de origen.',
    )) {
      return;
    }
    try {
      await _repository.deleteAction('${action['id']}');
      await _load(silent: true);
    } catch (error) {
      if (mounted) _message('No se pudo eliminar: $error', error: true);
    }
  }

  void _openEventTarget(Map<String, dynamic> event, {bool chart = false}) {
    final contextData = event['contexto'];
    final values = contextData is Map
        ? Map<String, dynamic>.from(contextData)
        : const <String, dynamic>{};
    final data = event['datos_origen'];
    Map<String, dynamic> firstRow = const {};
    if (data is Map &&
        data['rows'] is List &&
        (data['rows'] as List).isNotEmpty) {
      final first = (data['rows'] as List).first;
      if (first is Map) firstRow = Map<String, dynamic>.from(first);
    }
    final recordField = firstRow.containsKey('id')
        ? 'id'
        : firstRow.containsKey('ID')
            ? 'ID'
            : null;
    final target = AlertNavigationTarget(
      tableName: '${event['tabla_origen'] ?? values['tabla_nombre'] ?? ''}',
      moduleId: values['modulo_id']?.toString(),
      formatId: values['formato_id']?.toString(),
      recordField: recordField,
      recordValue:
          recordField == null ? null : firstRow[recordField]?.toString(),
      openChart: chart,
    );
    if (widget.onNavigate != null) {
      unawaited(widget.onNavigate!(target));
    } else {
      Navigator.of(context).pop(target);
    }
  }

  Future<void> _editRule([Map<String, dynamic>? rule]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AlertRuleEditorPage(
          contextData: _context,
          initialRule: rule,
          repository: _repository,
        ),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _newAction({Map<String, dynamic>? event}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ActionEditorDialog(
        users: _users,
        event: event,
        repository: _repository,
      ),
    );
    if (saved == true) await _load();
  }

  List<Map<String, dynamic>> get _users =>
      (_context['usuarios'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final pageBody = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
            : TabBarView(
                controller: _tabs,
                children: [_alertsView(), _actionsView()],
              );
    final title = AnimatedBuilder(
      animation: _tabs,
      builder: (context, _) => ZumacFeatureHeader(
        title: _tabs.index == 0 ? 'Zumac Alerts' : 'Zumac Actions',
        icon: _tabs.index == 0
            ? Icons.notifications_active_outlined
            : Icons.bolt_outlined,
        color: _tabs.index == 0 ? _orange : _rose,
        compact: true,
      ),
    );
    final refreshButton = IconButton(
      tooltip: 'Actualizar datos y configuración',
      onPressed: _loading || _working ? null : _refreshAllData,
      icon: const Icon(Icons.refresh_rounded),
    );
    final tabs = TabBar(
      controller: _tabs,
      tabs: const [
        Tab(icon: Icon(Icons.notifications_active_outlined), text: 'Alerts'),
        Tab(icon: Icon(Icons.bolt_outlined), text: 'Actions'),
      ],
    );
    final floatingButton = _loading
        ? null
        : AnimatedBuilder(
            animation: _tabs,
            builder: (_, __) {
              if (_tabs.index == 0 && _alertsEnabled && _canManage) {
                return FloatingActionButton.extended(
                  onPressed: _editRule,
                  icon: const Icon(Icons.add_alert_outlined),
                  label: const Text('Nueva alerta'),
                );
              }
              if (_tabs.index == 1 && _actionsEnabled) {
                return FloatingActionButton.extended(
                  onPressed: _newAction,
                  backgroundColor: _rose,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add_task_outlined),
                  label: const Text('Nueva acción'),
                );
              }
              return const SizedBox.shrink();
            },
          );
    if (widget.embedded) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F8FA),
        body: Column(
          children: [
            Material(color: Colors.white, child: tabs),
            const Divider(height: 1),
            Expanded(child: pageBody),
          ],
        ),
        floatingActionButton: floatingButton,
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FA),
      appBar: AppBar(
        title: title,
        actions: [refreshButton],
        bottom: tabs,
      ),
      body: pageBody,
      floatingActionButton: floatingButton,
    );
  }

  Widget _alertsView() {
    if (!_alertsEnabled) {
      return const _DisabledFeature(
        icon: Icons.notifications_off_outlined,
        title: 'Alerts no está habilitado',
        text: 'Un administrador de Zumac debe habilitarlo para esta empresa.',
      );
    }
    final openEvents = _events
        .where((e) => !const ['CERRADA', 'DESCARTADA'].contains(e['estado']))
        .toList();
    return LayoutBuilder(builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 1040;
      final rulesContent = <Widget>[
        Row(
          children: [
            const Expanded(child: _SectionTitle('Reglas de vigilancia')),
            if (_canManage)
              OutlinedButton.icon(
                onPressed: _working ? null : _evaluate,
                icon: _working
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: const Text('Evaluar ahora'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_rules.isEmpty)
          const _EmptyCard(
            icon: Icons.add_alert_outlined,
            text:
                'Aún no hay reglas. Crea la primera y pruébala antes de activarla.',
          )
        else
          ..._rules.map(_ruleCard),
      ];
      final eventsContent = <Widget>[
        const _SectionTitle('Alertas actuales'),
        const SizedBox(height: 4),
        const Text(
          'Cada regla conserva un solo aviso vivo; la evaluación más reciente reemplaza su contenido.',
          style: TextStyle(color: _muted),
        ),
        const SizedBox(height: 8),
        if (openEvents.isEmpty)
          const _EmptyCard(
            icon: Icons.verified_outlined,
            text:
                'No hay condiciones activas. Todo está dentro de lo esperado.',
          )
        else
          ...openEvents.map(_eventCard),
      ];
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1380),
                child: Column(children: [
                  _SummaryHeader(
                    color: _orange,
                    icon: Icons.radar_outlined,
                    title: 'Vigilancia empresarial',
                    text:
                        'Zumac evalúa condiciones configurables y mantiene un único estado vigente por regla.',
                    stats: [
                      _Stat('Reglas activas',
                          '${_rules.where((r) => r['activa'] == true).length}'),
                      _Stat('Eventos abiertos', '${openEvents.length}'),
                      _Stat('Críticos',
                          '${openEvents.where((e) => e['severidad'] == 'CRITICA').length}'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (desktop)
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              flex: 5, child: Column(children: rulesContent)),
                          const SizedBox(width: 18),
                          Expanded(
                              flex: 6, child: Column(children: eventsContent)),
                        ])
                  else ...[
                    ...rulesContent,
                    const SizedBox(height: 20),
                    ...eventsContent,
                  ],
                ]),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _ruleCard(Map<String, dynamic> rule) {
    final active = rule['activa'] == true;
    final severity = '${rule['severidad'] ?? 'MEDIA'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: _severityColor(severity).withValues(alpha: 0.12),
          child: Icon(Icons.notifications_active_outlined,
              color: _severityColor(severity)),
        ),
        title: Text('${rule['nombre'] ?? 'Alerta'}',
            style: const TextStyle(fontWeight: FontWeight.w800, color: _navy)),
        subtitle: Text(
          '${rule['tabla_origen']} · cada ${rule['frecuencia_minutos']} min · $severity',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusPill(active ? 'ACTIVA' : 'PAUSADA',
                color: active ? const Color(0xFF237A57) : _muted),
            if (_canManage)
              PopupMenuButton<String>(
                tooltip: 'Administrar regla',
                onSelected: (value) {
                  if (value == 'edit') _editRule(rule);
                  if (value == 'toggle') _toggleRule(rule, !active);
                  if (value == 'delete') _deleteRule(rule);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Editar')),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(active ? 'Pausar' : 'Activar'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Eliminar'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _eventCard(Map<String, dynamic> event) {
    final severity = '${event['severidad'] ?? 'MEDIA'}';
    final state = '${event['estado'] ?? 'DETECTADA'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showEvent(event),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 5,
                height: 58,
                decoration: BoxDecoration(
                  color: _severityColor(severity),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${event['titulo'] ?? 'Evento'}',
                        style: const TextStyle(
                            color: _navy, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text('${event['mensaje'] ?? ''}',
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 7),
                    Wrap(spacing: 7, runSpacing: 6, children: [
                      _StatusPill(severity, color: _severityColor(severity)),
                      _StatusPill(state, color: _teal),
                      if ((event['ocurrencias'] as num? ?? 1) > 1)
                        _StatusPill('${event['ocurrencias']} coincidencias',
                            color: _muted),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      'Activo desde ${_shortDate(event['detectada_at'])} · última evaluación ${_shortDate(event['ultima_ocurrencia_at'])}',
                      style: const TextStyle(color: _muted, fontSize: 11.5),
                    ),
                    const SizedBox(height: 7),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      TextButton.icon(
                        onPressed: () => _openEventTarget(event),
                        icon: const Icon(Icons.table_rows_outlined, size: 18),
                        label: const Text('Ver registros'),
                      ),
                      if (_tablesWithMetrics
                          .contains('${event['tabla_origen']}'))
                        TextButton.icon(
                          onPressed: () => _openEventTarget(event, chart: true),
                          icon:
                              const Icon(Icons.insert_chart_outlined, size: 18),
                          label: const Text('Ver gráfico'),
                        ),
                    ]),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _muted),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEvent(Map<String, dynamic> event) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (sheetContext) => _EventDetailsSheet(
        event: event,
        users: _users,
        repository: _repository,
        onCreateAction: () {
          Navigator.pop(sheetContext, false);
          unawaited(_newAction(event: event));
        },
      ),
    );
    if (changed == true) await _load();
  }

  Widget _actionsView() {
    if (!_actionsEnabled) {
      return const _DisabledFeature(
        icon: Icons.bolt_outlined,
        title: 'Actions no está habilitado',
        text: 'Un administrador de Zumac debe habilitarlo para esta empresa.',
      );
    }
    final pending = _actions
        .where((e) => const ['PENDIENTE', 'EN_PROGRESO'].contains(e['estado']))
        .toList();
    final completed = _actions
        .where((e) => !const ['PENDIENTE', 'EN_PROGRESO'].contains(e['estado']))
        .toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SummaryHeader(
                      color: _rose,
                      icon: Icons.task_alt_outlined,
                      title: 'Ejecución y seguimiento',
                      text:
                          'Convierte hallazgos en tareas, aprobaciones y evidencia verificable.',
                      stats: [
                        _Stat('Pendientes',
                            '${pending.where((a) => a['estado'] == 'PENDIENTE').length}'),
                        _Stat('En progreso',
                            '${pending.where((a) => a['estado'] == 'EN_PROGRESO').length}'),
                        _Stat('Finalizadas', '${completed.length}'),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const _SectionTitle('Por atender'),
                    const SizedBox(height: 8),
                    if (pending.isEmpty)
                      const _EmptyCard(
                        icon: Icons.done_all_rounded,
                        text: 'No hay acciones pendientes.',
                      )
                    else
                      ...pending.map(_actionCard),
                    if (completed.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const _SectionTitle('Historial reciente'),
                      const SizedBox(height: 8),
                      ...completed.take(20).map(_actionCard),
                    ],
                  ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionCard(Map<String, dynamic> action) {
    final state = '${action['estado'] ?? 'PENDIENTE'}';
    final priority = '${action['prioridad'] ?? 'MEDIA'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showAction(action),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(_actionIcon('${action['tipo']}'), color: _rose),
                const SizedBox(width: 9),
                Expanded(
                  child: Text('${action['titulo'] ?? 'Acción'}',
                      style: const TextStyle(
                          color: _navy, fontWeight: FontWeight.w800)),
                ),
                if (_canManage)
                  PopupMenuButton<String>(
                    tooltip: 'Administrar acción',
                    onSelected: (value) {
                      if (value == 'open') _showAction(action);
                      if (value == 'delete') _deleteAction(action);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'open', child: Text('Abrir')),
                      PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                    ],
                  )
                else
                  const Icon(Icons.chevron_right_rounded, color: _muted),
              ]),
              if ('${action['descripcion'] ?? ''}'.trim().isNotEmpty) ...[
                const SizedBox(height: 7),
                Text('${action['descripcion']}',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 9),
              Wrap(spacing: 7, runSpacing: 6, children: [
                _StatusPill(state, color: _actionStateColor(state)),
                _StatusPill(priority, color: _severityColor(priority)),
                if (action['fecha_limite'] != null)
                  _StatusPill('Límite ${_shortDate(action['fecha_limite'])}',
                      color: _muted),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAction(Map<String, dynamic> action) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ActionDetailsSheet(
        action: action,
        repository: _repository,
      ),
    );
    if (changed == true) await _load();
  }
}

class AlertRuleEditorPage extends StatefulWidget {
  const AlertRuleEditorPage({
    super.key,
    required this.contextData,
    required this.repository,
    this.initialRule,
  });

  final Map<String, dynamic> contextData;
  final Map<String, dynamic>? initialRule;
  final AlertsActionsRepository repository;

  @override
  State<AlertRuleEditorPage> createState() => _AlertRuleEditorPageState();
}

class _AlertRuleEditorPageState extends State<AlertRuleEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _title;
  late final TextEditingController _message;
  late final TextEditingController _frequency;
  late final TextEditingController _cooldown;
  String? _table;
  String _logic = 'AND';
  String _trigger = 'PROGRAMADA';
  String _severity = 'MEDIA';
  String _validity = 'SIEMPRE';
  DateTime? _validFrom;
  DateTime? _validUntil;
  String _recipientType = 'TODOS';
  String? _recipientRole;
  String? _recipientUser;
  bool _active = true;
  bool _createTask = false;
  String? _taskAssignee;
  final List<Map<String, dynamic>> _conditions = [];
  bool _busy = false;
  Map<String, dynamic>? _testResult;

  List<Map<String, dynamic>> get _sources =>
      (widget.contextData['fuentes'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
  List<Map<String, dynamic>> get _users =>
      (widget.contextData['usuarios'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
  Map<String, dynamic>? get _source => _sources
      .cast<Map<String, dynamic>?>()
      .firstWhere((source) => source?['tabla'] == _table, orElse: () => null);
  List<Map<String, dynamic>> get _fields =>
      (_source?['campos'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);

  @override
  void initState() {
    super.initState();
    final rule = widget.initialRule ?? const <String, dynamic>{};
    _name = TextEditingController(text: '${rule['nombre'] ?? ''}');
    _description = TextEditingController(text: '${rule['descripcion'] ?? ''}');
    _title = TextEditingController(text: '${rule['plantilla_titulo'] ?? ''}');
    _message =
        TextEditingController(text: '${rule['plantilla_mensaje'] ?? ''}');
    _frequency =
        TextEditingController(text: '${rule['frecuencia_minutos'] ?? 15}');
    _cooldown =
        TextEditingController(text: '${rule['cooldown_minutos'] ?? 60}');
    _table = rule['tabla_origen']?.toString();
    _trigger = '${rule['tipo_disparador'] ?? 'PROGRAMADA'}';
    _severity = '${rule['severidad'] ?? 'MEDIA'}';
    _validity = '${rule['vigencia_tipo'] ?? 'SIEMPRE'}';
    _validFrom = DateTime.tryParse('${rule['vigente_desde'] ?? ''}');
    _validUntil = DateTime.tryParse('${rule['vigente_hasta'] ?? ''}');
    _active = rule['activa'] != false;
    _logic = '${(rule['expresion_regla'] as Map?)?['logic'] ?? 'AND'}';
    final rawConditions = (rule['expresion_regla'] as Map?)?['conditions'];
    if (rawConditions is List) {
      _conditions.addAll(rawConditions
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item)));
    }
    final auto = rule['accion_automatica'];
    if (auto is Map) {
      _createTask = auto['crear_tarea'] == true;
      _taskAssignee = auto['asignado_a']?.toString();
    }
    if (_conditions.isEmpty) _conditions.add(_emptyCondition());
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _title.dispose();
    _message.dispose();
    _frequency.dispose();
    _cooldown.dispose();
    super.dispose();
  }

  Map<String, dynamic> _emptyCondition() => {
        'field': _fields.isEmpty ? null : _fields.first['campo'],
        'operator': 'eq',
        'value': '',
        'value_type':
            _fields.isEmpty ? 'text' : _valueType(_fields.first['tipo']),
      };

  Map<String, dynamic> _payload() {
    _normalizeValidityDates();
    final recipients = <Map<String, dynamic>>[];
    if (_recipientType == 'ROL') {
      recipients.add(
          {'tipo_destinatario': 'ROL', 'rol': _recipientRole, 'canal': 'APP'});
    } else if (_recipientType == 'USUARIO') {
      recipients.add({
        'tipo_destinatario': 'USUARIO',
        'user_id': _recipientUser,
        'canal': 'APP'
      });
    } else {
      recipients.add({'tipo_destinatario': 'TODOS', 'canal': 'APP'});
    }
    return {
      if (widget.initialRule?['id'] != null) 'id': widget.initialRule!['id'],
      'nombre': _name.text.trim(),
      'descripcion': _description.text.trim(),
      'tipo_disparador': _trigger,
      'tabla_origen': _table,
      'expresion_regla': {'logic': _logic, 'conditions': _conditions},
      'plantilla_titulo':
          _title.text.trim().isEmpty ? _name.text.trim() : _title.text.trim(),
      'plantilla_mensaje': _message.text.trim(),
      'severidad': _severity,
      'frecuencia_minutos': int.tryParse(_frequency.text) ?? 15,
      'cooldown_minutos': int.tryParse(_cooldown.text) ?? 60,
      'activa': _active,
      'vigencia_tipo': _validity,
      'vigente_desde': _validFrom?.toUtc().toIso8601String(),
      'vigente_hasta': _validUntil?.toUtc().toIso8601String(),
      'accion_automatica': {
        'crear_tarea': _createTask,
        if (_taskAssignee != null) 'asignado_a': _taskAssignee,
        'plazo_horas': 24,
      },
      'destinatarios': recipients,
    };
  }

  void _normalizeValidityDates() {
    final now = DateTime.now();
    DateTime startOf(DateTime value) =>
        DateTime(value.year, value.month, value.day);
    DateTime endOf(DateTime value) =>
        DateTime(value.year, value.month, value.day, 23, 59, 59, 999);
    switch (_validity) {
      case 'HOY':
        _validFrom = startOf(now);
        _validUntil = endOf(now);
      case 'SEMANA':
        final monday = startOf(now).subtract(Duration(days: now.weekday - 1));
        _validFrom = monday;
        _validUntil = endOf(monday.add(const Duration(days: 6)));
      case 'ANIO':
        _validFrom = DateTime(now.year);
        _validUntil = DateTime(now.year, 12, 31, 23, 59, 59, 999);
      case 'RANGO':
        if (_validFrom != null) _validFrom = startOf(_validFrom!);
        if (_validUntil != null) _validUntil = endOf(_validUntil!);
      default:
        _validFrom = null;
        _validUntil = null;
    }
  }

  Future<void> _pickValidityDate({required bool from}) async {
    final current = from ? _validFrom : _validUntil;
    final selected = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: from ? 'Inicio de vigencia' : 'Fin de vigencia',
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (from) {
        _validFrom = selected;
      } else {
        _validUntil = selected;
      }
    });
  }

  void _insertMessageField(String field) {
    final insertion = '[$field]';
    final selection = _message.selection;
    final text = _message.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    _message.value = TextEditingValue(
      text: text.replaceRange(start, end, insertion),
      selection: TextSelection.collapsed(offset: start + insertion.length),
    );
  }

  bool _valid() {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    if (_validity == 'RANGO' &&
        (_validFrom == null ||
            _validUntil == null ||
            _validUntil!.isBefore(_validFrom!))) {
      _notify('Selecciona un rango de fechas válido.', error: true);
      return false;
    }
    if (_table == null || _conditions.any((c) => c['field'] == null)) {
      _notify('Selecciona una fuente y todos los campos.', error: true);
      return false;
    }
    if (_recipientType == 'ROL' && _recipientRole == null ||
        _recipientType == 'USUARIO' && _recipientUser == null) {
      _notify('Selecciona el destinatario.', error: true);
      return false;
    }
    return true;
  }

  Future<void> _test() async {
    if (!_valid() || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.repository.testRule(_payload());
      if (mounted) setState(() => _testResult = result);
    } catch (error) {
      if (mounted) _notify('La prueba falló: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_valid() || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.saveRule(_payload());
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _notify('No se pudo guardar: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notify(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? const Color(0xFF9F2F42) : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FA),
      appBar: AppBar(
        title:
            Text(widget.initialRule == null ? 'Nueva alerta' : 'Editar alerta'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
          children: [
            const _EditorIntro(
              step: '1',
              title: 'Qué debe vigilar Zumac',
              text:
                  'Elige una tabla configurada y describe la regla con lenguaje de negocio.',
            ),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final name = TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Nombre de la alerta',
                    border: OutlineInputBorder()),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Escribe un nombre'
                    : null,
              );
              final description = TextFormField(
                controller: _description,
                maxLines: 1,
                decoration: const InputDecoration(
                    labelText: 'Descripción interna',
                    border: OutlineInputBorder()),
              );
              if (constraints.maxWidth < 760) {
                return Column(
                    children: [name, const SizedBox(height: 12), description]);
              }
              return Row(children: [
                Expanded(child: name),
                const SizedBox(width: 12),
                Expanded(child: description),
              ]);
            }),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue:
                  _sources.any((s) => s['tabla'] == _table) ? _table : null,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Fuente de datos', border: OutlineInputBorder()),
              items: _sources
                  .map((source) => DropdownMenuItem(
                        value: '${source['tabla']}',
                        child: Text('${source['nombre']} · ${source['tabla']}',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (value) => setState(() {
                _table = value;
                _conditions
                  ..clear()
                  ..add(_emptyCondition());
                _testResult = null;
              }),
              validator: (value) =>
                  value == null ? 'Selecciona una fuente' : null,
            ),
            const SizedBox(height: 22),
            const _EditorIntro(
              step: '2',
              title: 'Condiciones',
              text: 'Puedes exigir que se cumplan todas (Y) o cualquiera (O).',
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 330),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'AND', label: Text('Todas (Y)')),
                    ButtonSegment(value: 'OR', label: Text('Cualquiera (O)')),
                  ],
                  selected: {_logic},
                  onSelectionChanged: (values) =>
                      setState(() => _logic = values.first),
                ),
              ),
            ),
            const SizedBox(height: 10),
            ...List.generate(
                _conditions.length, (index) => _conditionEditor(index)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _fields.isEmpty
                    ? null
                    : () => setState(() => _conditions.add(_emptyCondition())),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Agregar condición'),
              ),
            ),
            const SizedBox(height: 18),
            const _EditorIntro(
              step: '3',
              title: 'Frecuencia y respuesta',
              text:
                  'Define prioridad, deduplicación, destinatarios y la acción automática.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String>(
                      initialValue: _trigger,
                      decoration: const InputDecoration(
                          labelText: 'Tipo', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(
                            value: 'PROGRAMADA',
                            child: Text('Condición programada')),
                        DropdownMenuItem(
                            value: 'AUSENCIA',
                            child: Text('Ausencia de registro')),
                        DropdownMenuItem(
                            value: 'EVENTO', child: Text('Evento de datos')),
                      ],
                      onChanged: (value) =>
                          setState(() => _trigger = value ?? _trigger),
                    )),
                SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: _severity,
                      decoration: const InputDecoration(
                          labelText: 'Severidad', border: OutlineInputBorder()),
                      items: const [
                        'INFORMATIVA',
                        'BAJA',
                        'MEDIA',
                        'ALTA',
                        'CRITICA'
                      ]
                          .map((value) => DropdownMenuItem(
                              value: value, child: Text(value)))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _severity = value ?? _severity),
                    )),
                SizedBox(
                    width: 180,
                    child: TextFormField(
                      controller: _frequency,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Evaluar cada (min)',
                          border: OutlineInputBorder()),
                      validator: _positiveNumber,
                    )),
                SizedBox(
                    width: 180,
                    child: TextFormField(
                      controller: _cooldown,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'No repetir por (min)',
                          border: OutlineInputBorder()),
                      validator: _nonNegativeNumber,
                    )),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 230,
                  child: DropdownButtonFormField<String>(
                    initialValue: _validity,
                    decoration: const InputDecoration(
                      labelText: 'Vigencia de la alerta',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'SIEMPRE', child: Text('Siempre')),
                      DropdownMenuItem(value: 'HOY', child: Text('Solo hoy')),
                      DropdownMenuItem(
                          value: 'SEMANA', child: Text('Esta semana')),
                      DropdownMenuItem(value: 'ANIO', child: Text('Este año')),
                      DropdownMenuItem(
                          value: 'RANGO', child: Text('Rango de fechas')),
                    ],
                    onChanged: (value) => setState(() {
                      _validity = value ?? 'SIEMPRE';
                      _normalizeValidityDates();
                    }),
                  ),
                ),
                if (_validity == 'RANGO') ...[
                  OutlinedButton.icon(
                    onPressed: () => _pickValidityDate(from: true),
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(_validFrom == null
                        ? 'Fecha inicial'
                        : 'Desde ${_dateLabel(_validFrom)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickValidityDate(from: false),
                    icon: const Icon(Icons.event_available_outlined),
                    label: Text(_validUntil == null
                        ? 'Fecha final'
                        : 'Hasta ${_dateLabel(_validUntil)}'),
                  ),
                ] else
                  Text(
                    _validityDescription(_validity),
                    style: const TextStyle(color: _muted),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Título del evento',
                helperText:
                    'Usa [NOMBRE_CAMPO] o {{NOMBRE_CAMPO}}. Si hay varios valores, Zumac los agrupa.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _message,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Mensaje que verá el equipo',
                  border: OutlineInputBorder()),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Escribe el mensaje'
                  : null,
            ),
            if (_fields.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Insertar campo:',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                    ..._fields.take(12).map(
                          (field) => ActionChip(
                            label: Text('${field['etiqueta']}'),
                            onPressed: () =>
                                _insertMessageField('${field['campo']}'),
                          ),
                        ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _recipientType,
              decoration: const InputDecoration(
                  labelText: 'Destinatarios', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(
                    value: 'TODOS', child: Text('Toda la empresa')),
                DropdownMenuItem(value: 'ROL', child: Text('Un rol')),
                DropdownMenuItem(value: 'USUARIO', child: Text('Una persona')),
              ],
              onChanged: (value) =>
                  setState(() => _recipientType = value ?? 'TODOS'),
            ),
            if (_recipientType == 'ROL') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _recipientRole,
                decoration: const InputDecoration(
                    labelText: 'Rol', border: OutlineInputBorder()),
                items: const ['ADMIN', 'GESTOR', 'COLABORADOR', 'VISUALIZADOR']
                    .map((role) =>
                        DropdownMenuItem(value: role, child: Text(role)))
                    .toList(),
                onChanged: (value) => setState(() => _recipientRole = value),
              ),
            ],
            if (_recipientType == 'USUARIO') ...[
              const SizedBox(height: 10),
              _userDropdown(
                label: 'Persona',
                value: _recipientUser,
                onChanged: (value) => setState(() => _recipientUser = value),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              value: _createTask,
              onChanged: (value) => setState(() => _createTask = value),
              title: const Text('Crear una acción automáticamente'),
              subtitle: const Text(
                  'El evento aparecerá también como tarea pendiente.'),
            ),
            if (_createTask)
              _userDropdown(
                label: 'Asignar tarea a (opcional)',
                value: _taskAssignee,
                allowEmpty: true,
                onChanged: (value) => setState(() => _taskAssignee = value),
              ),
            SwitchListTile.adaptive(
              value: _active,
              onChanged: (value) => setState(() => _active = value),
              title: const Text('Regla activa'),
              subtitle: const Text(
                  'Puedes guardarla pausada mientras terminas de validarla.'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _test,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.science_outlined),
              label: const Text('Probar con hasta 500 registros'),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 10),
              _TestResultCard(result: _testResult!),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_active ? 'Guardar y activar' : 'Guardar pausada'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conditionEditor(int index) {
    final condition = _conditions[index];
    final operators = _operatorsFor('${condition['value_type'] ?? 'text'}');
    final needsValue =
        !const ['is_null', 'is_not_null'].contains(condition['operator']);
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 250,
              child: DropdownButtonFormField<String>(
                initialValue:
                    _fields.any((field) => field['campo'] == condition['field'])
                        ? '${condition['field']}'
                        : null,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Campo', border: OutlineInputBorder()),
                items: _fields
                    .map((field) => DropdownMenuItem(
                          value: '${field['campo']}',
                          child: Text('${field['etiqueta']}',
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (value) => setState(() {
                  condition['field'] = value;
                  final field =
                      _fields.firstWhere((item) => item['campo'] == value);
                  condition['value_type'] = _valueType(field['tipo']);
                  condition['operator'] = 'eq';
                }),
              ),
            ),
            SizedBox(
              width: 205,
              child: DropdownButtonFormField<String>(
                initialValue:
                    operators.any((op) => op.$1 == condition['operator'])
                        ? '${condition['operator']}'
                        : 'eq',
                decoration: const InputDecoration(
                    labelText: 'Operador', border: OutlineInputBorder()),
                items: operators
                    .map((op) =>
                        DropdownMenuItem(value: op.$1, child: Text(op.$2)))
                    .toList(),
                onChanged: (value) =>
                    setState(() => condition['operator'] = value ?? 'eq'),
              ),
            ),
            if (needsValue)
              SizedBox(
                width: 230,
                child: TextFormField(
                  initialValue: '${condition['value'] ?? ''}',
                  decoration: InputDecoration(
                    labelText: condition['operator'] == 'between'
                        ? 'Valores separados por coma'
                        : 'Valor esperado',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    condition['value'] = condition['operator'] == 'between'
                        ? value.split(',').map((v) => v.trim()).toList()
                        : value;
                  },
                  validator: (value) =>
                      needsValue && (value == null || value.trim().isEmpty)
                          ? 'Escribe un valor'
                          : null,
                ),
              ),
            IconButton(
              tooltip: 'Quitar condición',
              onPressed: _conditions.length == 1
                  ? null
                  : () => setState(() => _conditions.removeAt(index)),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _userDropdown({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
    bool allowEmpty = false,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: _users.any((u) => u['user_id'] == value) ? value : null,
      isExpanded: true,
      decoration:
          InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [
        if (allowEmpty)
          const DropdownMenuItem(value: null, child: Text('Sin asignar')),
        ..._users.map((user) => DropdownMenuItem(
              value: '${user['user_id']}',
              child: Text(_userLabel(user)),
            )),
      ],
      onChanged: onChanged,
    );
  }
}

class _ActionEditorDialog extends StatefulWidget {
  const _ActionEditorDialog(
      {required this.users, required this.repository, this.event});
  final List<Map<String, dynamic>> users;
  final AlertsActionsRepository repository;
  final Map<String, dynamic>? event;

  @override
  State<_ActionEditorDialog> createState() => _ActionEditorDialogState();
}

class _ActionEditorDialogState extends State<_ActionEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  String _type = 'TAREA';
  String _priority = 'MEDIA';
  String? _assignee;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(
      text: widget.event == null
          ? ''
          : 'Atender: ${widget.event!['titulo'] ?? 'alerta'}',
    );
    _description =
        TextEditingController(text: '${widget.event?['mensaje'] ?? ''}');
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false) || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.saveAction({
        'alerta_evento_id': widget.event?['id'],
        'alerta_id': widget.event?['alerta_id'],
        'tipo': _type,
        'titulo': _title.text.trim(),
        'descripcion': _description.text.trim(),
        'prioridad': _priority,
        'asignado_a': _assignee,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo crear: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 820;
    final titleField = TextFormField(
      controller: _title,
      decoration: const InputDecoration(
          labelText: 'Título', border: OutlineInputBorder()),
      validator: (value) =>
          value == null || value.trim().isEmpty ? 'Escribe un título' : null,
    );
    final descriptionField = TextFormField(
      controller: _description,
      maxLines: desktop ? 1 : 3,
      decoration: const InputDecoration(
          labelText: 'Qué debe realizarse', border: OutlineInputBorder()),
    );
    final typeField = DropdownButtonFormField<String>(
      initialValue: _type,
      decoration: const InputDecoration(
          labelText: 'Tipo', border: OutlineInputBorder()),
      items: const [
        DropdownMenuItem(value: 'TAREA', child: Text('Tarea')),
        DropdownMenuItem(
            value: 'SOLICITUD_APROBACION',
            child: Text('Solicitud de aprobación')),
        DropdownMenuItem(value: 'NOTIFICACION', child: Text('Notificación')),
      ],
      onChanged: (value) => setState(() => _type = value ?? _type),
    );
    final priorityField = DropdownButtonFormField<String>(
      initialValue: _priority,
      decoration: const InputDecoration(
          labelText: 'Prioridad', border: OutlineInputBorder()),
      items: const ['BAJA', 'MEDIA', 'ALTA', 'CRITICA']
          .map((value) => DropdownMenuItem(value: value, child: Text(value)))
          .toList(),
      onChanged: (value) => setState(() => _priority = value ?? _priority),
    );
    final assigneeField = DropdownButtonFormField<String>(
      initialValue: _assignee,
      isExpanded: true,
      decoration: const InputDecoration(
          labelText: 'Responsable (opcional)', border: OutlineInputBorder()),
      items: [
        const DropdownMenuItem(value: null, child: Text('Sin asignar')),
        ...widget.users.map((user) => DropdownMenuItem(
              value: '${user['user_id']}',
              child: Text(_userLabel(user)),
            )),
      ],
      onChanged: (value) => setState(() => _assignee = value),
    );
    return AlertDialog(
      title: const Text('Nueva acción'),
      content: SizedBox(
        width: desktop ? 820 : 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (desktop)
                Row(children: [
                  Expanded(child: titleField),
                  const SizedBox(width: 10),
                  Expanded(child: descriptionField),
                ])
              else ...[
                titleField,
                const SizedBox(height: 10),
                descriptionField,
              ],
              const SizedBox(height: 10),
              if (desktop)
                Row(children: [
                  Expanded(child: typeField),
                  const SizedBox(width: 10),
                  Expanded(child: priorityField),
                  const SizedBox(width: 10),
                  Expanded(child: assigneeField),
                ])
              else ...[
                typeField,
                const SizedBox(height: 10),
                priorityField,
                const SizedBox(height: 10),
                assigneeField,
              ],
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: _busy ? null : _save, child: const Text('Crear acción')),
      ],
    );
  }
}

class _EventDetailsSheet extends StatefulWidget {
  const _EventDetailsSheet({
    required this.event,
    required this.users,
    required this.repository,
    required this.onCreateAction,
  });
  final Map<String, dynamic> event;
  final List<Map<String, dynamic>> users;
  final AlertsActionsRepository repository;
  final VoidCallback onCreateAction;

  @override
  State<_EventDetailsSheet> createState() => _EventDetailsSheetState();
}

class _EventDetailsSheetState extends State<_EventDetailsSheet> {
  String? _responsible;
  bool _busy = false;

  Future<void> _update(String state) async {
    setState(() => _busy = true);
    try {
      await widget.repository.updateEvent('${widget.event['id']}',
          state: state, responsibleId: _responsible);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo actualizar: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.event['datos_origen'];
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Expanded(child: _SectionTitle('Detalle de la alerta')),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
              const SizedBox(height: 8),
              Text('${widget.event['titulo']}',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900, color: _navy)),
              const SizedBox(height: 8),
              Text('${widget.event['mensaje']}',
                  style: const TextStyle(fontSize: 15, height: 1.45)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _StatusPill('${widget.event['severidad']}',
                    color: _severityColor('${widget.event['severidad']}')),
                _StatusPill('${widget.event['estado']}', color: _teal),
                _StatusPill('${widget.event['ocurrencias']} coincidencia(s)',
                    color: _muted),
              ]),
              const SizedBox(height: 20),
              const _SectionTitle('Responsable'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: widget.users.any(
                        (u) => u['user_id'] == widget.event['responsable_id'])
                    ? '${widget.event['responsable_id']}'
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(), labelText: 'Asignar a'),
                items: widget.users
                    .map((user) => DropdownMenuItem(
                          value: '${user['user_id']}',
                          child: Text(_userLabel(user)),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _responsible = value),
              ),
              const SizedBox(height: 20),
              if (data is Map && data.isNotEmpty) ...[
                const _SectionTitle('Datos que originaron el evento'),
                const SizedBox(height: 8),
                _KeyValueCard(
                  values:
                      data['rows'] is List && (data['rows'] as List).isNotEmpty
                          ? Map<String, dynamic>.from(
                              (data['rows'] as List).first as Map)
                          : Map<String, dynamic>.from(data),
                ),
                const SizedBox(height: 18),
              ],
              Wrap(spacing: 9, runSpacing: 9, children: [
                OutlinedButton.icon(
                    onPressed: _busy ? null : widget.onCreateAction,
                    icon: const Icon(Icons.add_task_outlined),
                    label: const Text('Crear acción')),
                OutlinedButton.icon(
                    onPressed: _busy ? null : () => _update('ASIGNADA'),
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Asignar')),
                FilledButton.icon(
                    onPressed: _busy ? null : () => _update('ATENDIDA'),
                    icon: const Icon(Icons.done_rounded),
                    label: const Text('Marcar atendida')),
                TextButton.icon(
                    onPressed: _busy ? null : () => _update('CERRADA'),
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Cerrar')),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionDetailsSheet extends StatefulWidget {
  const _ActionDetailsSheet({required this.action, required this.repository});
  final Map<String, dynamic> action;
  final AlertsActionsRepository repository;

  @override
  State<_ActionDetailsSheet> createState() => _ActionDetailsSheetState();
}

class _ActionDetailsSheetState extends State<_ActionDetailsSheet> {
  final _comment = TextEditingController();
  List<Map<String, dynamic>> _comments = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadComments());
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final rows =
          await widget.repository.listComments('${widget.action['id']}');
      if (mounted) setState(() => _comments = rows);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeState(String state) async {
    setState(() => _busy = true);
    try {
      await widget.repository.updateAction('${widget.action['id']}', state);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo actualizar: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.repository.addComment('${widget.action['id']}', text);
      _comment.clear();
      await _loadComments();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo guardar evidencia: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = '${widget.action['estado']}';
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Expanded(child: _SectionTitle('Detalle de la acción')),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
              const SizedBox(height: 8),
              Text('${widget.action['titulo']}',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900, color: _navy)),
              const SizedBox(height: 8),
              Text('${widget.action['descripcion'] ?? ''}',
                  style: const TextStyle(fontSize: 15, height: 1.45)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                _StatusPill(state, color: _actionStateColor(state)),
                _StatusPill('${widget.action['prioridad']}',
                    color: _severityColor('${widget.action['prioridad']}')),
              ]),
              const SizedBox(height: 18),
              Wrap(spacing: 9, runSpacing: 9, children: [
                if (state == 'PENDIENTE')
                  FilledButton.icon(
                      onPressed:
                          _busy ? null : () => _changeState('EN_PROGRESO'),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Iniciar')),
                if (state == 'EN_PROGRESO' || state == 'PENDIENTE')
                  FilledButton.icon(
                      onPressed:
                          _busy ? null : () => _changeState('COMPLETADA'),
                      icon: const Icon(Icons.done),
                      label: const Text('Completar')),
                if (widget.action['tipo'] == 'SOLICITUD_APROBACION' &&
                    !const ['APROBADA', 'RECHAZADA'].contains(state)) ...[
                  OutlinedButton(
                      onPressed: _busy ? null : () => _changeState('APROBADA'),
                      child: const Text('Aprobar')),
                  TextButton(
                      onPressed: _busy ? null : () => _changeState('RECHAZADA'),
                      child: const Text('Rechazar')),
                ],
              ]),
              const SizedBox(height: 22),
              const _SectionTitle('Comentarios y evidencia'),
              const SizedBox(height: 8),
              TextField(
                controller: _comment,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText:
                      'Describe lo realizado, una observación o la evidencia…',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                      onPressed: _busy ? null : _addComment,
                      icon: const Icon(Icons.send_rounded)),
                ),
              ),
              const SizedBox(height: 10),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_comments.isEmpty)
                const Text('Aún no se registraron comentarios.',
                    style: TextStyle(color: _muted))
              else
                ..._comments.map((comment) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                          child: Icon(Icons.notes_rounded, size: 18)),
                      title: Text('${comment['comentario']}'),
                      subtitle: Text(_shortDate(comment['created_at'])),
                    )),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader(
      {required this.color,
      required this.icon,
      required this.title,
      required this.text,
      required this.stats});
  final Color color;
  final IconData icon;
  final String title;
  final String text;
  final List<_Stat> stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient:
            LinearGradient(colors: [color, Color.lerp(color, _navy, .45)!]),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: .18),
              blurRadius: 20,
              offset: const Offset(0, 9))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(text,
                    style:
                        const TextStyle(color: Colors.white70, height: 1.35)),
              ])),
        ]),
        const SizedBox(height: 18),
        Wrap(
            spacing: 10,
            runSpacing: 10,
            children: stats
                .map((stat) => Container(
                      constraints: const BoxConstraints(minWidth: 112),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 9),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .13),
                          borderRadius: BorderRadius.circular(12)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(stat.value,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900)),
                            Text(stat.label,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 11)),
                          ]),
                    ))
                .toList()),
      ]),
    );
  }
}

class _Stat {
  const _Stat(this.label, this.value);
  final String label;
  final String value;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: _navy, fontSize: 17, fontWeight: FontWeight.w900));
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.text, {required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .11),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: color.withValues(alpha: .35))),
        child: Text(text.replaceAll('_', ' '),
            style: TextStyle(
                color: color, fontSize: 10.5, fontWeight: FontWeight.w800)),
      );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Icon(icon, color: _teal),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: _muted, height: 1.35)))
        ]),
      ));
}

class _DisabledFeature extends StatelessWidget {
  const _DisabledFeature(
      {required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 54, color: _muted),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _navy, fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted)),
        ]),
      ));
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined, size: 50, color: _rose),
          const SizedBox(height: 12),
          const Text('No se pudo abrir Alerts & Actions',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted)),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar')),
        ]),
      ));
}

class _EditorIntro extends StatelessWidget {
  const _EditorIntro(
      {required this.step, required this.title, required this.text});
  final String step;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
            radius: 16,
            backgroundColor: _teal,
            foregroundColor: Colors.white,
            child: Text(step)),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: _navy, fontWeight: FontWeight.w900, fontSize: 17)),
          Text(text, style: const TextStyle(color: _muted, height: 1.35)),
        ])),
      ]);
}

class _TestResultCard extends StatelessWidget {
  const _TestResultCard({required this.result});
  final Map<String, dynamic> result;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFFEAF5F7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBFDCE4))),
        child: Row(children: [
          const Icon(Icons.science_outlined, color: _teal),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
                  'Se revisaron ${result['filas_revisadas'] ?? 0} registros y ${result['coincidencias'] ?? 0} cumplen la condición.',
                  style: const TextStyle(
                      color: _navy, fontWeight: FontWeight.w700))),
        ]),
      );
}

class _KeyValueCard extends StatelessWidget {
  const _KeyValueCard({required this.values});
  final Map<String, dynamic> values;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFFF7FAFB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD5E5EA))),
        child: Column(
            children: values.entries
                .take(30)
                .map((entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                                width: 145,
                                child: Text(entry.key,
                                    style: const TextStyle(
                                        color: _muted,
                                        fontWeight: FontWeight.w700))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: SelectableText('${entry.value ?? '—'}')),
                          ]),
                    ))
                .toList()),
      );
}

String? _positiveNumber(String? value) {
  final number = int.tryParse(value ?? '');
  return number == null || number < 1 ? 'Debe ser mayor que 0' : null;
}

String? _nonNegativeNumber(String? value) {
  final number = int.tryParse(value ?? '');
  return number == null || number < 0 ? 'Debe ser 0 o mayor' : null;
}

String _valueType(dynamic raw) {
  final value = '$raw'.toLowerCase();
  if (value.contains('int') ||
      value.contains('num') ||
      value.contains('decimal') ||
      value.contains('double')) {
    return 'number';
  }
  if (value.contains('date') || value.contains('time')) {
    return 'datetime';
  }
  return 'text';
}

List<(String, String)> _operatorsFor(String type) {
  final common = <(String, String)>[
    ('eq', 'Es igual a'),
    ('neq', 'Es diferente de'),
    ('is_null', 'Está vacío'),
    ('is_not_null', 'No está vacío'),
  ];
  if (type == 'number' || type == 'datetime') {
    return [
      ...common,
      ('gt', 'Mayor que'),
      ('gte', 'Mayor o igual'),
      ('lt', 'Menor que'),
      ('lte', 'Menor o igual'),
      ('between', 'Entre')
    ];
  }
  return [...common, ('contains', 'Contiene'), ('not_contains', 'No contiene')];
}

Color _severityColor(String value) => switch (value) {
      'CRITICA' => const Color(0xFF9F2F42),
      'ALTA' => const Color(0xFFC56A13),
      'BAJA' => const Color(0xFF237A57),
      'INFORMATIVA' => _teal,
      _ => const Color(0xFF6E56CF),
    };

Color _actionStateColor(String state) => switch (state) {
      'COMPLETADA' || 'APROBADA' => const Color(0xFF237A57),
      'RECHAZADA' || 'CANCELADA' => const Color(0xFF9F2F42),
      'EN_PROGRESO' => _teal,
      _ => _orange,
    };

IconData _actionIcon(String type) => switch (type) {
      'SOLICITUD_APROBACION' => Icons.approval_outlined,
      'NOTIFICACION' => Icons.campaign_outlined,
      'CAMBIO_ESTADO' => Icons.sync_alt_outlined,
      _ => Icons.task_alt_outlined,
    };

String _shortId(dynamic value) {
  final text = '$value';
  return text.length <= 12
      ? text
      : '${text.substring(0, 8)}…${text.substring(text.length - 4)}';
}

String _userLabel(Map<String, dynamic> user) {
  final name = '${user['nombre'] ?? ''}'.trim();
  final email = '${user['email'] ?? ''}'.trim();
  final identity = name.isNotEmpty
      ? name
      : email.isNotEmpty
          ? email
          : _shortId(user['user_id']);
  return '$identity · ${user['rol'] ?? 'USUARIO'}';
}

String _shortDate(dynamic value) {
  final parsed = DateTime.tryParse('$value')?.toLocal();
  if (parsed == null) return '$value';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(parsed.day)}/${two(parsed.month)}/${parsed.year} ${two(parsed.hour)}:${two(parsed.minute)}';
}

String _dateLabel(DateTime? value) {
  if (value == null) return '—';
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';
}

String _validityDescription(String value) {
  switch (value) {
    case 'HOY':
      return 'Se evaluará únicamente durante el día de hoy.';
    case 'SEMANA':
      return 'Se evaluará desde el lunes hasta el domingo actual.';
    case 'ANIO':
      return 'Se evaluará hasta finalizar el año actual.';
    default:
      return 'Continuará evaluándose hasta que la pauses o elimines.';
  }
}
