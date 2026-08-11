import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/configuration_icon_catalog.dart';
import '../../core/widgets/responsive_layout.dart';

import '../../core/services/app_experience_service.dart';
import '../../core/services/local_db.dart';
import '../../core/services/sync_service.dart';
import '../../core/services/zumac_consultant_service.dart';
import '../../core/widgets/branded_loading.dart';
import '../../core/widgets/zumac_feature_header.dart';
import '../../core/services/local_session.dart';
import '../../core/services/onboarding_service.dart';
import '../auth/login_page.dart';
import '../../core/platform/app_platform.dart';
import '../formats/desktop_format_records_page.dart';
import '../formats/formats_page.dart';
import '../form_runner/form_runner_page.dart';
import '../form_runner/special_form_pages.dart';
import '../local_records/local_records_page.dart';
import '../reports/reports_page.dart';
import '../configuration_admin/configuration_admin_page.dart';
import '../configuration_admin/configuration_admin_repository.dart';
import '../knowledge_admin/knowledge_admin_page.dart';
import '../onboarding/onboarding_page.dart';
import '../alerts_actions/alerts_actions_page.dart';
import '../metrics/metrics_page.dart';
import 'generic_section_page.dart';
import 'dynamic_views_page.dart';

class ModulesPage extends StatefulWidget {
  const ModulesPage({super.key});

  @override
  State<ModulesPage> createState() => _ModulesPageState();
}

class _HomeDecorationCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _HomeDecorationCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _ConsultantChatTurn {
  const _ConsultantChatTurn({
    required this.question,
    required this.result,
  });

  final String question;
  final ZumacConsultantResult result;
}

class _CreatorModeChoice extends StatelessWidget {
  const _CreatorModeChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? Colors.white : const Color(0xFF17324D);
    return Material(
      color: filled ? const Color(0xFF176B87) : const Color(0xFFF7FAFB),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: filled ? const Color(0xFF176B87) : const Color(0xFFD4E3E8),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: foreground, size: 30),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color:
                            filled ? Colors.white70 : const Color(0xFF60758A),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tabla operativa del Consultor con desplazamiento independiente en ambos
/// ejes. Mantener los controladores dentro del widget evita que el scroll se
/// reinicie cada vez que cambia otra parte de la pantalla.
class _ConsultantReportTableCard extends StatefulWidget {
  const _ConsultantReportTableCard({
    super.key,
    required this.report,
    required this.onOpen,
  });

  final ZumacConsultantReportTable report;
  final VoidCallback? onOpen;

  @override
  State<_ConsultantReportTableCard> createState() =>
      _ConsultantReportTableCardState();
}

class _ConsultantReportTableCardState
    extends State<_ConsultantReportTableCard> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD7E6EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.table_chart_outlined,
                      size: 20,
                      color: Color(0xFF176B87),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.title,
                          style: const TextStyle(
                            color: Color(0xFF17324D),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${report.totalRows} ${report.totalRows == 1 ? 'registro' : 'registros'}',
                          style: const TextStyle(
                            color: Color(0xFF60758A),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final openButton = report.canOpen && widget.onOpen != null
                  ? TextButton.icon(
                      onPressed: widget.onOpen,
                      icon: const Icon(Icons.open_in_new, size: 17),
                      label: const Text('Abrir registros'),
                    )
                  : null;
              return Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                child: constraints.maxWidth < 480
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          title,
                          if (openButton != null)
                            Align(
                              alignment: Alignment.centerRight,
                              child: openButton,
                            ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: title),
                          if (openButton != null) openButton,
                        ],
                      ),
              );
            },
          ),
          if (report.columns.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                'Los registros encontrados solo contienen identificadores técnicos.',
                style: TextStyle(color: Color(0xFF60758A)),
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              color: const Color(0xFFF7FAFB),
              child: const Row(
                children: [
                  Icon(
                    Icons.swipe_outlined,
                    size: 16,
                    color: Color(0xFF60758A),
                  ),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Desliza horizontal y verticalmente para revisar la tabla.',
                      style: TextStyle(
                        color: Color(0xFF60758A),
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                var tableWidth = report.columns.length * 168.0;
                if (tableWidth < constraints.maxWidth) {
                  tableWidth = constraints.maxWidth;
                }
                if (tableWidth > 1800) tableWidth = 1800;
                final contentHeight = 58.0 + (report.rows.length * 52.0);
                final viewportHeight = contentHeight.clamp(150.0, 390.0);
                return SizedBox(
                  height: viewportHeight,
                  child: Scrollbar(
                    controller: _verticalController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    notificationPredicate: (notification) =>
                        notification.metrics.axis == Axis.vertical,
                    child: SingleChildScrollView(
                      controller: _verticalController,
                      scrollDirection: Axis.vertical,
                      child: Scrollbar(
                        controller: _horizontalController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        scrollbarOrientation: ScrollbarOrientation.bottom,
                        notificationPredicate: (notification) =>
                            notification.metrics.axis == Axis.horizontal,
                        child: SingleChildScrollView(
                          controller: _horizontalController,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: tableWidth),
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(
                                const Color(0xFFEAF3F6),
                              ),
                              headingRowHeight: 54,
                              dataRowMinHeight: 48,
                              dataRowMaxHeight: 72,
                              dividerThickness: 0.8,
                              headingTextStyle: const TextStyle(
                                color: Color(0xFF17324D),
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                              dataTextStyle: const TextStyle(
                                color: Color(0xFF304A60),
                                fontSize: 12.5,
                              ),
                              columnSpacing: 20,
                              horizontalMargin: 16,
                              columns: [
                                for (final column in report.columns)
                                  DataColumn(
                                    label: Text(
                                      column.label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              rows: [
                                for (var index = 0;
                                    index < report.rows.length;
                                    index++)
                                  DataRow(
                                    color: WidgetStateProperty.all(
                                      index.isEven
                                          ? Colors.white
                                          : const Color(0xFFF8FBFC),
                                    ),
                                    cells: [
                                      for (final column in report.columns)
                                        DataCell(
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              minWidth: 92,
                                              maxWidth: 250,
                                            ),
                                            child: SelectableText(
                                              report.rows[index][column.key] ??
                                                  '—',
                                              maxLines: 3,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
          if (report.totalRows > report.rows.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'Mostrando ${report.rows.length} de ${report.totalRows} registros. Puedes precisar la fecha, lote, persona u otro campo para acotar la consulta.',
                style: const TextStyle(
                  color: Color(0xFF60758A),
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModulesPageState extends State<ModulesPage> {
  static const _toolHome = 'home';
  static const _toolConsultant = 'consultant';
  static const _toolCreatorCreate = 'creator_create';
  static const _toolCreatorEdit = 'creator_edit';
  static const _toolMetrics = 'metrics';
  static const _toolAlerts = 'alerts';
  static const _toolActions = 'actions';

  final local = LocalDb.instance;
  final sync = SyncService();
  final experience = AppExperienceService();
  final consultant = ZumacConsultantService();
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _consultantController = TextEditingController();
  final FocusNode _consultantFocusNode = FocusNode();
  final stt.SpeechToText _consultantSpeech = stt.SpeechToText();
  final GlobalKey _consultantComposerKey = GlobalKey();
  final String _consultantConversationId =
      'consultor-${DateTime.now().microsecondsSinceEpoch}';

  List<Map<String, dynamic>> modules = [];
  List<Map<String, dynamic>> sections = [];
  Map<String, List<Map<String, dynamic>>> formatsByModule = {};
  Set<String> allowedSections = {};
  int pending = 0;
  bool busy = false;
  String? busyMessage;
  bool _reportNavigationLoading = false;
  double busyProgress = 0;
  bool localLoaded = false;
  bool desktopSidebarOpen = true;
  final ValueNotifier<bool> _desktopSidebarOpenNotifier =
      ValueNotifier<bool>(true);
  String profileName = '';
  Map<String, dynamic>? desktopSelectedModule;
  Map<String, dynamic>? desktopSelectedFormat;
  Map<String, dynamic>? desktopSelectedSection;
  Map<String, dynamic>? desktopSelectedReportModule;
  Map<String, dynamic>? desktopSelectedReportView;
  List<Map<String, dynamic>> reportModules = [];
  List<Map<String, dynamic>> reportViews = [];
  List<Map<String, dynamic>> reportPermissions = [];
  List<Map<String, dynamic>> dynamicViews = [];
  Map<String, dynamic>? desktopSelectedDynamicView;
  Map<String, dynamic>? mobileSelectedSpecial;
  String? _expandedSectionId;
  bool canManageConfiguration = false;
  bool canManageCompany = false;
  bool canUseZumacConsultor = false;
  bool canUseZumacCreator = false;
  bool canUseZumacAlerts = false;
  bool canUseZumacActions = false;
  bool canUseZumacMetrics = false;
  int openAlertEvents = 0;
  int pendingActions = 0;
  bool online = true;
  DateTime? lastSyncAt;
  Map<String, dynamic> restoredNavigation = {};
  final List<Map<String, dynamic>> navigationHistory = [];
  bool _consultantBusy = false;
  bool _consultantSpeechListening = false;
  bool _consultantSpeechInitializing = false;
  String _consultantSpeechBaseText = '';
  bool _consultantSuggestionsExpanded = false;
  bool _consultantOpen = false;
  String _activeWorkspaceTool = _toolHome;
  final List<_ConsultantChatTurn> _consultantTurns = [];
  String? _consultantTableName;
  String? _consultantRecordField;
  String? _consultantRecordValue;
  String? _metricsInitialSourceTable;
  bool _incrementalRefreshRunning = false;
  bool _incrementalRefreshQueued = false;

  String? _desktopContentCacheKey;
  Widget? _desktopContentCache;
  String? _desktopSidebarCacheKey;
  Widget? _desktopSidebarCache;

  void _clearDesktopContentCache() {
    _desktopContentCacheKey = null;
    _desktopContentCache = null;
  }

  void _clearDesktopSidebarCache() {
    _desktopSidebarCacheKey = null;
    _desktopSidebarCache = null;
  }

  void _clearConsultantFocusState() {
    _consultantTableName = null;
    _consultantRecordField = null;
    _consultantRecordValue = null;
  }

  @override
  void dispose() {
    unawaited(_persistNavigation());
    unawaited(_consultantSpeech.cancel());
    _consultantController.dispose();
    _consultantFocusNode.dispose();
    consultant.clearConversation(_consultantConversationId);
    _desktopSidebarOpenNotifier.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_restoreExperience());
    unawaited(_loadCachedAndRefresh());
    unawaited(_loadConfigurationAccess());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeOpenOnboarding());
    });
  }

  Future<void> _loadCachedAndRefresh() async {
    await loadLocal();
    await _refreshIncrementallyOnEntry();
  }

  /// Revalida configuración, permisos y registros al entrar a cualquier vista.
  /// Las llamadas simultáneas se agrupan para que navegar rápido no dispare
  /// varias descargas; si hubo otra entrada durante la descarga, se ejecuta un
  /// último delta al terminar.
  Future<void> _refreshIncrementallyOnEntry() async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    if (_incrementalRefreshRunning) {
      _incrementalRefreshQueued = true;
      return;
    }
    _incrementalRefreshRunning = true;
    try {
      do {
        _incrementalRefreshQueued = false;
        try {
          final hasCache = await local.hasOfflineBootstrapCache();
          await sync.downloadAllForOffline(
            allowFullFallback: !hasCache,
            forceConfigurationRefresh: false,
          );
          await loadLocal();
          await _loadConfigurationAccess();
          final completedAt = DateTime.now();
          if (mounted) {
            setState(() {
              online = true;
              lastSyncAt = completedAt;
            });
          }
          unawaited(experience.saveLastSync(completedAt));
        } catch (_) {
          if (mounted) setState(() => online = false);
        }
      } while (_incrementalRefreshQueued && mounted);
    } finally {
      _incrementalRefreshRunning = false;
    }
  }

  Future<void> _restoreExperience() async {
    final restored = await experience.loadNavigation();
    final restoredSync = await experience.loadLastSync();
    final connected = await sync.hasInternet();
    if (!mounted) return;
    setState(() {
      restoredNavigation = restored;
      _expandedSectionId = restored['expanded_section_id']?.toString();
      desktopSidebarOpen = restored['sidebar_open'] != false;
      _desktopSidebarOpenNotifier.value = desktopSidebarOpen;
      lastSyncAt = restoredSync;
      online = connected;
    });
    if (localLoaded) _applyRestoredNavigation();
  }

  Map<String, dynamic> _navigationSnapshot() {
    if (_activeWorkspaceTool != _toolHome) {
      return {
        'kind': 'tool',
        'tool': _activeWorkspaceTool,
      };
    }
    if (desktopSelectedModule != null && desktopSelectedFormat != null) {
      return {
        'kind': 'format',
        'module_id': _txt(desktopSelectedModule!['id']),
        'format_id': _txt(desktopSelectedFormat!['id']),
      };
    }
    if (desktopSelectedSection != null) {
      return {
        'kind': 'section',
        'section_id': _txt(desktopSelectedSection!['id']),
        'dynamic_view_id': _txt(desktopSelectedDynamicView?['id']),
      };
    }
    return const {'kind': 'home'};
  }

  void _rememberNavigation() {
    final current = _navigationSnapshot();
    if (navigationHistory.isEmpty ||
        jsonEncode(navigationHistory.last) != jsonEncode(current)) {
      navigationHistory.add(current);
      if (navigationHistory.length > 12) navigationHistory.removeAt(0);
    }
  }

  Future<void> _persistNavigation() => experience.saveNavigation({
        ..._navigationSnapshot(),
        'expanded_section_id': _expandedSectionId,
        'sidebar_open': desktopSidebarOpen,
      });

  void _applyRestoredNavigation() {
    if (restoredNavigation.isEmpty) return;
    final snapshot = Map<String, dynamic>.from(restoredNavigation);
    restoredNavigation = {};
    _applyNavigationSnapshot(snapshot, persist: false);
  }

  void _applyNavigationSnapshot(
    Map<String, dynamic> snapshot, {
    bool persist = true,
  }) {
    final kind = snapshot['kind']?.toString();
    Map<String, dynamic>? selectedSection;
    Map<String, dynamic>? selectedModule;
    Map<String, dynamic>? selectedFormat;
    var restoredTool = _toolHome;
    if (kind == 'tool') {
      final candidate = snapshot['tool']?.toString() ?? _toolHome;
      if (const {
        _toolConsultant,
        _toolCreatorCreate,
        _toolCreatorEdit,
        _toolMetrics,
        _toolAlerts,
        _toolActions,
      }.contains(candidate)) {
        restoredTool = candidate;
      }
    } else if (kind == 'section') {
      selectedSection = sections.cast<Map<String, dynamic>?>().firstWhere(
            (row) => _sameId(row?['id'], snapshot['section_id']),
            orElse: () => null,
          );
    } else if (kind == 'format') {
      selectedModule = modules.cast<Map<String, dynamic>?>().firstWhere(
            (row) => _sameId(row?['id'], snapshot['module_id']),
            orElse: () => null,
          );
      final candidates = formatsByModule[_txt(snapshot['module_id'])] ??
          const <Map<String, dynamic>>[];
      selectedFormat = candidates.cast<Map<String, dynamic>?>().firstWhere(
            (row) => _sameId(row?['id'], snapshot['format_id']),
            orElse: () => null,
          );
    }
    setState(() {
      _clearDesktopContentCache();
      _clearConsultantFocusState();
      _activeWorkspaceTool = restoredTool;
      _consultantOpen = restoredTool == _toolConsultant;
      desktopSelectedSection = selectedSection;
      desktopSelectedModule = selectedModule;
      desktopSelectedFormat = selectedFormat;
      desktopSelectedReportModule = null;
      desktopSelectedReportView = null;
      desktopSelectedDynamicView = null;
      mobileSelectedSpecial = null;
    });
    if (persist) unawaited(_persistNavigation());
  }

  void _restorePreviousNavigation() {
    final previous = navigationHistory.isEmpty
        ? const <String, dynamic>{'kind': 'home'}
        : navigationHistory.removeLast();
    _applyNavigationSnapshot(previous);
  }

  Future<void> _maybeOpenOnboarding() async {
    final service = OnboardingService();
    if (!await service.shouldShow() || !mounted) return;
    await _openOnboarding();
  }

  Future<void> _openOnboarding({bool replay = false}) async {
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => OnboardingPage(replay: replay),
      ),
    );
    if (completed == true) await OnboardingService().markSeen();
  }

  Future<void> _loadConfigurationAccess() async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    try {
      final contextData = await ConfigurationAdminRepository()
          .loadContext()
          .timeout(const Duration(seconds: 4));
      Map<String, dynamic> alertsContext = const {};
      Map<String, dynamic> metricsContext = const {};
      try {
        final raw = await Supabase.instance.client
            .rpc('appgt_alertas_contexto_v1')
            .timeout(const Duration(seconds: 4));
        if (raw is Map) alertsContext = Map<String, dynamic>.from(raw);
      } catch (_) {
        // Permite que una compilación nueva siga entrando mientras la migración
        // de Alerts/Actions aún está pendiente de desplegar en Supabase.
      }
      try {
        final raw = await Supabase.instance.client
            .rpc('appgt_metrics_contexto_v1')
            .timeout(const Duration(seconds: 4));
        if (raw is Map) metricsContext = Map<String, dynamic>.from(raw);
      } catch (_) {
        // Una app nueva puede convivir temporalmente con el esquema anterior.
      }
      if (!mounted) return;
      setState(() {
        canUseZumacConsultor =
            contextData['zumac_consultor_habilitado'] == true;
        canUseZumacCreator = contextData['zumac_creator_habilitado'] == true;
        canUseZumacAlerts = alertsContext['alerts_habilitado'] == true;
        canUseZumacActions = alertsContext['actions_habilitado'] == true;
        canUseZumacMetrics = metricsContext['metrics_habilitado'] == true;
        final summary = alertsContext['resumen'];
        if (summary is Map) {
          openAlertEvents = (summary['eventos_abiertos'] as num?)?.toInt() ?? 0;
          pendingActions =
              (summary['acciones_pendientes'] as num?)?.toInt() ?? 0;
        }
        canManageCompany = contextData['puede_gestionar_empresa'] == true;
        canManageConfiguration = canManageCompany && canUseZumacCreator;
      });
    } catch (_) {
      // El constructor requiere conexión. La navegación offline principal no
      // debe bloquearse si Supabase no responde.
      if (mounted) {
        setState(() {
          canManageConfiguration = false;
          canManageCompany = false;
          canUseZumacConsultor = false;
          canUseZumacCreator = false;
          canUseZumacAlerts = false;
          canUseZumacActions = false;
          canUseZumacMetrics = false;
        });
      }
    }
  }

  Future<void> _openConfigurationAdmin({
    CreatorEntryMode mode = CreatorEntryMode.create,
  }) async {
    _activateWorkspaceTool(
      mode == CreatorEntryMode.edit ? _toolCreatorEdit : _toolCreatorCreate,
    );
  }

  Future<void> _chooseCreatorMode() async {
    if (!canUseZumacCreator || !canManageConfiguration) return;
    final mode = await showDialog<CreatorEntryMode>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.dashboard_customize_outlined),
        title: const Text('Creator'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CreatorModeChoice(
                icon: Icons.edit_note_outlined,
                title: 'Editar existentes',
                subtitle: 'Revisar, modificar u ocultar lo que ya existe.',
                onTap: () =>
                    Navigator.of(dialogContext).pop(CreatorEntryMode.edit),
              ),
              const SizedBox(height: 10),
              _CreatorModeChoice(
                icon: Icons.add_circle_outline,
                title: 'Crear',
                subtitle:
                    'Crear secciones, módulos, formatos o una app desde un documento.',
                filled: true,
                onTap: () =>
                    Navigator.of(dialogContext).pop(CreatorEntryMode.create),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (mode != null && mounted) {
      await _openConfigurationAdmin(mode: mode);
    }
  }

  Future<void> _openMetrics({String? sourceTable}) async {
    _metricsInitialSourceTable = sourceTable;
    _activateWorkspaceTool(_toolMetrics);
  }

  Future<void> _openAlertsActions(int initialTab) async {
    _activateWorkspaceTool(initialTab == 0 ? _toolAlerts : _toolActions);
  }

  void _activateWorkspaceTool(String tool) {
    unawaited(_refreshIncrementallyOnEntry());
    _rememberNavigation();
    setState(() {
      _clearDesktopContentCache();
      _clearDesktopSidebarCache();
      _clearConsultantFocusState();
      _activeWorkspaceTool = tool;
      _consultantOpen = tool == _toolConsultant;
      desktopSelectedSection = null;
      desktopSelectedModule = null;
      desktopSelectedFormat = null;
      desktopSelectedReportModule = null;
      desktopSelectedReportView = null;
      desktopSelectedDynamicView = null;
      mobileSelectedSpecial = null;
    });
    unawaited(_persistNavigation());
    if (tool == _toolConsultant) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _consultantFocusNode.requestFocus();
      });
    }
  }

  Future<void> _handleAlertNavigation(AlertNavigationTarget target) async {
    if (!mounted) return;
    await _loadConfigurationAccess();
    if (!mounted) return;
    if (target.openChart) {
      await _openMetrics(sourceTable: target.tableName);
      return;
    }
    if ((target.moduleId ?? '').isEmpty || (target.formatId ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La alerta no tiene todavía el vínculo de formato. Evalúala nuevamente para actualizarlo.',
          ),
        ),
      );
      return;
    }
    _reviewConsultantFinding(
      ZumacConsultantFinding(
        title: 'Registros de la alerta',
        detail: '',
        tableName: target.tableName,
        moduleId: target.moduleId,
        formatId: target.formatId,
        recordField: target.recordField,
        recordValue: target.recordValue,
      ),
    );
  }

  Future<void> _refreshAfterCreatorChange() async {
    await download();
    if (mounted) await _loadConfigurationAccess();
  }

  Future<void> _toggleConsultantSpeech() async {
    if (_consultantSpeechInitializing || _consultantBusy) return;
    if (_consultantSpeech.isListening) {
      await _consultantSpeech.stop();
      if (mounted) setState(() => _consultantSpeechListening = false);
      return;
    }

    setState(() => _consultantSpeechInitializing = true);
    try {
      final available = await _consultantSpeech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          final listening = status == 'listening';
          if (_consultantSpeechListening != listening) {
            setState(() => _consultantSpeechListening = listening);
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() => _consultantSpeechListening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                error.permanent
                    ? 'Zumac no tiene permiso para usar el micrófono. Habilítalo en la configuración del dispositivo o navegador.'
                    : 'No se pudo reconocer la voz. Intenta nuevamente en un lugar con menos ruido.',
              ),
            ),
          );
        },
      );
      if (!available) {
        throw StateError(
          'El reconocimiento de voz no está disponible en este dispositivo o navegador.',
        );
      }

      String? localeId;
      try {
        final locales = await _consultantSpeech.locales();
        stt.LocaleName? preferred;
        for (final locale in locales) {
          if (locale.localeId.toLowerCase() == 'es_pe') {
            preferred = locale;
            break;
          }
          if (preferred == null &&
              locale.localeId.toLowerCase().startsWith('es')) {
            preferred = locale;
          }
        }
        localeId = preferred?.localeId;
      } catch (_) {
        // Algunos navegadores no exponen la lista; se usa el idioma del sistema.
      }

      _consultantSpeechBaseText = _consultantController.text.trim();
      await _consultantSpeech.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: localeId,
          listenFor: const Duration(seconds: 45),
          pauseFor: const Duration(seconds: 4),
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.confirmation,
        ),
        onResult: (result) {
          if (!mounted) return;
          final recognized = result.recognizedWords.trim();
          final combined = [
            if (_consultantSpeechBaseText.isNotEmpty) _consultantSpeechBaseText,
            if (recognized.isNotEmpty) recognized,
          ].join(' ');
          _consultantController
            ..text = combined
            ..selection = TextSelection.collapsed(offset: combined.length);
          setState(() {
            _clearDesktopContentCache();
            _consultantSpeechListening = !result.finalResult;
          });
        },
      );
      if (mounted) {
        setState(() => _consultantSpeechListening = true);
        _consultantFocusNode.requestFocus();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _consultantSpeechInitializing = false);
    }
  }

  Future<void> _askConsultant({
    String? questionOverride,
    String? displayQuestion,
    String? selectedSourceTable,
  }) async {
    final question = (questionOverride ?? _consultantController.text).trim();
    if (question.isEmpty || _consultantBusy) return;
    if (_consultantSpeech.isListening) {
      await _consultantSpeech.stop();
    }
    setState(() {
      _clearDesktopContentCache();
      _consultantBusy = true;
      _consultantSpeechListening = false;
    });
    try {
      final result = await consultant
          .ask(
            question,
            conversationId: _consultantConversationId,
            selectedSourceTable: selectedSourceTable,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException(
              'La consulta tardó demasiado. Zumac detuvo la búsqueda para no dejar la pantalla cargando. Intenta precisar el formato, el mes o la fecha.',
            ),
          );
      if (!mounted) return;
      setState(() {
        _clearDesktopContentCache();
        _consultantTurns.add(
          _ConsultantChatTurn(
            question: displayQuestion?.trim().isNotEmpty == true
                ? displayQuestion!.trim()
                : question,
            result: result,
          ),
        );
        _consultantController.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final composerContext = _consultantComposerKey.currentContext;
        if (composerContext != null) {
          Scrollable.ensureVisible(
            composerContext,
            duration: const Duration(milliseconds: 280),
            alignment: 0.92,
          );
        }
        if (mounted) _consultantFocusNode.requestFocus();
      });
    } catch (error) {
      if (!mounted) return;
      final message = error is TimeoutException
          ? error.message ?? 'La consulta excedió el tiempo permitido.'
          : 'No se pudo completar la consulta: $error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _clearDesktopContentCache();
          _consultantBusy = false;
        });
      }
    }
  }

  void _clearConsultantAnswer() {
    unawaited(_consultantSpeech.cancel());
    setState(() {
      _clearDesktopContentCache();
      _consultantTurns.clear();
      _consultantController.clear();
      _consultantSuggestionsExpanded = false;
      _consultantSpeechListening = false;
      _clearConsultantFocusState();
      consultant.clearConversation(_consultantConversationId);
    });
    _consultantFocusNode.requestFocus();
  }

  void _reviewConsultantFinding(ZumacConsultantFinding finding) {
    final format = formatsByModule.values
        .expand((rows) => rows)
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (row) => _sameId(row?['id'], finding.formatId),
          orElse: () => null,
        );
    final module = modules.cast<Map<String, dynamic>?>().firstWhere(
          (row) => _sameId(row?['id'], finding.moduleId),
          orElse: () => null,
        );
    if (format == null || module == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El registro fue encontrado, pero su formato no está disponible en este perfil.',
          ),
        ),
      );
      return;
    }
    _rememberNavigation();
    setState(() {
      _clearDesktopContentCache();
      _clearDesktopSidebarCache();
      _clearConsultantFocusState();
      _activeWorkspaceTool = _toolHome;
      _consultantOpen = false;
      desktopSelectedSection = null;
      desktopSelectedModule = Map<String, dynamic>.from(module);
      desktopSelectedFormat = Map<String, dynamic>.from(format);
      desktopSelectedReportModule = null;
      desktopSelectedReportView = null;
      desktopSelectedDynamicView = null;
      mobileSelectedSpecial = null;
      _consultantTableName = finding.tableName;
      _consultantRecordField = finding.recordField;
      _consultantRecordValue = finding.recordValue;
    });
    unawaited(_persistNavigation());
  }

  void _openConsultantReport(ZumacConsultantReportTable report) {
    _reviewConsultantFinding(
      ZumacConsultantFinding(
        title: report.title,
        detail: '',
        tableName: report.tableName,
        moduleId: report.moduleId,
        formatId: report.formatId,
      ),
    );
  }

  void _openConsultantRelatedTable(ZumacConsultantRelatedTable table) {
    _reviewConsultantFinding(
      ZumacConsultantFinding(
        title: table.title,
        detail: '',
        tableName: table.tableName,
        moduleId: table.moduleId,
        formatId: table.formatId,
      ),
    );
  }

  Future<void> _refreshPendingBadge() async {
    final p = await local.pendingCount();
    if (!mounted) return;
    setState(() => pending = p);
  }

  void _closeMobileFormatAfterSpecialSave() {
    if (!mounted) return;
    setState(() {
      desktopSelectedFormat = null;
      mobileSelectedSpecial = null;
    });
    _refreshPendingBadge();
  }

  void _closeMobileDrawer() {
    final scaffold = scaffoldKey.currentState;
    if (scaffold?.isDrawerOpen == true) {
      scaffold!.closeDrawer();
    }
  }

  bool _canSection(String sectionId) {
    // Sin catálogo de secciones solo se exponen áreas que ya contienen módulos
    // autorizados en el cache del usuario.
    if (allowedSections.isEmpty) return _sectionHasFormatModules(sectionId);
    return allowedSections.contains(sectionId);
  }

  bool _asBool(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    return s == 'true' ||
        s == 't' ||
        s == '1' ||
        s == 'si' ||
        s == 'sí' ||
        s == 's' ||
        s == 'yes';
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _txt(dynamic value) => value?.toString().trim() ?? '';

  String _id(dynamic value) => _txt(value).toLowerCase();

  bool _sameId(dynamic a, dynamic b) => _id(a) == _id(b);

  String _sectionKind(Map<String, dynamic> section) {
    final configured = _txt(section['tipo_contenido']).toUpperCase();
    if (configured.isNotEmpty) return configured;
    switch (_id(section['id'])) {
      case 'reportes':
        return 'REPORTES';
      case 'registros_pendientes':
        return 'VISTAS_DINAMICAS';
      case 'registros_locales':
        return 'REGISTROS_LOCALES';
      case 'inicio_gt':
        return 'INICIO';
      default:
        return _sectionHasFormatModules(_txt(section['id']))
            ? 'FORMATOS'
            : 'GENERICO';
    }
  }

  bool _sectionUsesDynamicViews(Map<String, dynamic> section) =>
      _sectionKind(section) == 'VISTAS_DINAMICAS' ||
      _sectionHasDynamicViews(_txt(section['id']));

  void _onSectionExpansionChanged(String sectionId, bool expanded) {
    final next = expanded
        ? sectionId
        : (_expandedSectionId == sectionId ? null : _expandedSectionId);
    if (next == _expandedSectionId) return;
    setState(() {
      _expandedSectionId = next;
      _clearDesktopSidebarCache();
    });
    unawaited(_persistNavigation());
  }

  List<Map<String, dynamic>> _modulesForSection(String sectionId) {
    return modules.where((m) {
      final configured = _txt(m['seccion']);
      return configured.isNotEmpty && _sameId(configured, sectionId);
    }).toList();
  }

  bool _isPermissionsSectionId(String sectionId) {
    final section = sections.cast<Map<String, dynamic>?>().firstWhere(
          (item) => _sameId(item?['id'], sectionId),
          orElse: () => null,
        );
    final fingerprint = [
      sectionId,
      section?['nombre'],
      section?['tipo_contenido'],
    ].map(_txt).join(' ').toLowerCase();
    return fingerprint.contains('permis') ||
        fingerprint.contains('gestión de accesos') ||
        fingerprint.contains('gestion de accesos');
  }

  bool _sectionHasFormatModules(String sectionId) =>
      !_isPermissionsSectionId(sectionId) &&
      _modulesForSection(sectionId).isNotEmpty;

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
          if ((v.startsWith('"') && v.endsWith('"')) ||
              (v.startsWith("'") && v.endsWith("'"))) {
            v = v.substring(1, v.length - 1);
          }
          return v.trim();
        })
        .where((e) => e.isNotEmpty && e.toLowerCase() != 'null')
        .toSet()
        .toList();
  }

  bool _permissionIncludesSection(
      Map<String, dynamic> permission, String sectionId) {
    final sections = _permissionSectionIds(permission['seccion']);
    return sections.isEmpty || sections.any((s) => _sameId(s, sectionId));
  }

  Future<void> _loadReportNavigation() async {
    try {
      // Offline-first: no consultamos Supabase al abrir/reanudar la app sin señal.
      // Antes esto podía esperar el timeout de red y dar la sensación de pantalla lenta.
      if (!await sync.hasInternet()) {
        reportModules = [];
        reportViews = [];
        reportPermissions = [];
        return;
      }

      final moduleRows = await Supabase.instance.client
          .from('MATRIZ_MODULOS_GRAFICOS_DINAMICOS')
          .select()
          .timeout(const Duration(seconds: 2));
      final viewRows = await Supabase.instance.client
          .from('MATRIZ_VISTAS_REPORTES')
          .select()
          .timeout(const Duration(seconds: 2));

      List<Map<String, dynamic>> permissionRows = [];
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        try {
          final rows = await Supabase.instance.client
              .from('PERMISOS_REPORTES_USUARIOS_APPGT')
              .select()
              .eq('user_id', user.id)
              .eq('activo', true)
              .timeout(const Duration(seconds: 2));
          permissionRows = List<Map<String, dynamic>>.from(rows);
        } catch (_) {
          permissionRows = [];
        }
      }

      final modulesLoaded = List<Map<String, dynamic>>.from(moduleRows)
          .where((m) => _asBool(m['activo'], fallback: true))
          .toList()
        ..sort((a, b) => _asInt(a['orden']).compareTo(_asInt(b['orden'])));

      final viewsLoaded = List<Map<String, dynamic>>.from(viewRows)
          .where((v) => _asBool(v['activo'], fallback: true))
          .toList()
        ..sort((a, b) => _asInt(a['orden']).compareTo(_asInt(b['orden'])));

      reportModules = modulesLoaded;
      reportViews = viewsLoaded;
      reportPermissions = permissionRows;
    } catch (_) {
      reportModules = [];
      reportViews = [];
      reportPermissions = [];
    }
  }

  Future<void> _refreshReportNavigationInBackground() async {
    if (_reportNavigationLoading) return;
    _reportNavigationLoading = true;
    try {
      await _loadReportNavigation();
      if (!mounted) return;
      setState(() {
        _clearDesktopContentCache();
        _clearDesktopSidebarCache();
      });
    } finally {
      _reportNavigationLoading = false;
    }
  }

  bool _canReportView(Map<String, dynamic> module, Map<String, dynamic> view) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return true;
    if (reportPermissions.isEmpty) return true;
    final moduleId = _txt(module['id']);
    final viewId = _txt(view['id']);
    return reportPermissions.any((p) =>
        _txt(p['id_modulo_reporte']) == moduleId &&
        _txt(p['id_vista_reporte']) == viewId &&
        _asBool(p['puede_ver'], fallback: true) &&
        _asBool(p['activo'], fallback: true));
  }

  List<Map<String, dynamic>> _dynamicViewsForSection(String sectionId) {
    return dynamicViews
        .where((v) =>
            _sameId(v['seccion'], sectionId) &&
            _asBool(v['activo'], fallback: true))
        .toList()
      ..sort((a, b) => _asInt(a['orden']).compareTo(_asInt(b['orden'])));
  }

  Map<String, List<Map<String, dynamic>>> _dynamicViewsGroupedByModule(
      String sectionId) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final view in _dynamicViewsForSection(sectionId)) {
      final module =
          _txt(view['modulo']).isEmpty ? 'General' : _txt(view['modulo']);
      grouped.putIfAbsent(module, () => <Map<String, dynamic>>[]).add(view);
    }
    return grouped;
  }

  bool _sectionHasDynamicViews(String sectionId) =>
      _dynamicViewsForSection(sectionId).isNotEmpty;

  List<Map<String, dynamic>> _reportViewsForModule(
      Map<String, dynamic> module) {
    final moduleId = _txt(module['id']);
    return reportViews
        .where((v) =>
            _txt(v['id_modulo_reporte']) == moduleId &&
            _canReportView(module, v))
        .toList()
      ..sort((a, b) => _asInt(a['orden']).compareTo(_asInt(b['orden'])));
  }

  Future<List<Map<String, dynamic>>> _loadDynamicViewsForSidebar() async {
    return local.getAll('local_dynamic_views', orderBy: 'orden');
  }

  Future<void> loadLocal() async {
    if (mounted && !localLoaded) setState(() => busy = true);

    final pendingFuture = local.pendingCount();
    final localReads = await Future.wait<List<Map<String, dynamic>>>([
      local.getAll('local_permissions'),
      local.getAll('local_section_permissions'),
      local.getAll('local_sections', orderBy: 'orden, id'),
      local.getAll('local_profile'),
      local.getAll('local_modules', orderBy: 'orden, id'),
      local.getAll('local_formats', orderBy: 'orden, id'),
      _loadDynamicViewsForSidebar(),
    ]);
    final rawPermissions = localReads[0];
    final rawSectionPerms = localReads[1];
    final localSections = localReads[2];
    final rawProfileRows = localReads[3];
    final allLocalModules = localReads[4];
    final allLocalFormats = localReads[5];
    final remoteDynamicViews = localReads[6];
    final sessionValues = await Future.wait<String?>([
      LocalSession().cachedEmpresaId(),
      LocalSession().cachedUserId(),
    ]);
    final activeEmpresaId = sessionValues[0] ?? '';
    bool belongsToActiveEmpresa(Map<String, dynamic> row) {
      final rowEmpresaId = row['empresa_id']?.toString().trim() ?? '';
      return rowEmpresaId.isEmpty || rowEmpresaId == activeEmpresaId;
    }

    // Seguridad visual/local: nunca renderizar el menú con permisos cacheados
    // de otro usuario. La BD local es un cache de trabajo, por eso al cambiar
    // de cuenta puede quedar información anterior hasta que se actualicen
    // matrices. Se filtra por el usuario activo antes de construir el sidebar.
    final authUserId = Supabase.instance.client.auth.currentUser?.id;
    final cachedUserId = sessionValues[1];
    final activeUserId = (authUserId ?? cachedUserId ?? '').trim();

    final permissions = activeUserId.isEmpty
        ? <Map<String, dynamic>>[]
        : rawPermissions
            .where((e) =>
                belongsToActiveEmpresa(e) &&
                e['user_id']?.toString().trim() == activeUserId)
            .toList();

    final sectionPerms = activeUserId.isEmpty
        ? <Map<String, dynamic>>[]
        : rawSectionPerms
            .where((e) =>
                belongsToActiveEmpresa(e) &&
                e['user_id']?.toString().trim() == activeUserId)
            .toList();

    final profileRows = activeUserId.isEmpty
        ? <Map<String, dynamic>>[]
        : rawProfileRows
            .where((e) =>
                belongsToActiveEmpresa(e) &&
                e['id']?.toString().trim() == activeUserId)
            .toList();

    final allowedModuleIds = permissions
        .where((e) => _asBool(e['can_view']))
        .map((e) => _txt(e['modulo']))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    final allowedSectionIds = sectionPerms
        .where((e) => _asBool(e['can_view'], fallback: true))
        .map((e) => _txt(e['seccion_id']))
        .where((e) => e.isNotEmpty)
        .toSet();

    final allowedModuleKeys = allowedModuleIds.map(_id).toSet();
    final moduleRows = allLocalModules
        .where((row) =>
            belongsToActiveEmpresa(row) &&
            _asBool(row['activo'], fallback: true) &&
            allowedModuleKeys.contains(_id(row['id'])))
        .toList(growable: false);

    final moduleFormats = <String, List<Map<String, dynamic>>>{};
    for (final module in moduleRows) {
      final moduleId = _txt(module['id']);
      final allowedFormatKeys = permissions
          .where(
              (e) => _asBool(e['can_view']) && _sameId(e['modulo'], moduleId))
          .map((e) => _id(e['formato']))
          .where((e) => e.isNotEmpty)
          .toSet();
      if (allowedFormatKeys.isEmpty) {
        moduleFormats[moduleId] = [];
        continue;
      }
      final candidates = allLocalFormats.where((format) =>
          belongsToActiveEmpresa(format) &&
          _asBool(format['activo'], fallback: true) &&
          _sameId(format['modulo_id'], moduleId));
      moduleFormats[moduleId] = candidates.where((format) {
        return allowedFormatKeys.contains(_id(format['id'])) ||
            allowedFormatKeys.contains(_id(format['tabla_destino']));
      }).toList();
    }

    // Rendimiento/offline: el sidebar usa el cache local de vistas dinámicas.
    // Los cambios de Supabase llegan al presionar Actualizar datos; evitamos consultar
    // internet cada vez que se reconstruye el menú, porque eso vuelve lenta la navegación.
    final visibleDynamicViews = remoteDynamicViews.where((view) {
      if (!belongsToActiveEmpresa(view)) return false;
      if (!_asBool(view['activo'], fallback: true)) return false;
      final sectionId = _txt(view['seccion']);
      final sectionIsAllowed = allowedSectionIds.isEmpty ||
          allowedSectionIds.any((allowed) => _sameId(allowed, sectionId)) ||
          _sameId(sectionId, 'registros_pendientes');
      if (!sectionIsAllowed) return false;

      // Registros Pendientes debe respetar la jerarquía configurada en
      // MATRIZ_VISTAS_DINAMICAS_APPGT: sección -> módulo -> vista/formato.
      // No se debe ocultar el módulo por no encontrar una coincidencia exacta
      // en PERMISOS_DE_USUARIOS_APPGT.modulo, porque esa matriz puede manejar
      // permisos por formato/tabla y no necesariamente por la misma etiqueta
      // de módulo usada en la vista dinámica.
      if (_sameId(sectionId, 'registros_pendientes')) {
        // Registros Pendientes es una vista operativa configurada por
        // MATRIZ_VISTAS_DINAMICAS_APPGT. Si la vista existe y está activa,
        // debe aparecer como árbol sección -> módulo -> vista. No se filtra
        // aquí por permisos de tabla porque eso deja el menú plano cuando el
        // permiso viene con bool/string/int o cuando el usuario solo tiene
        // permiso de flujo. La seguridad final se valida al abrir/sincronizar.
        return true;
      }

      final moduleId = _txt(view['modulo']);
      return permissions.any((permission) {
        final permModule = _txt(permission['modulo']);
        final canSee = _asBool(permission['can_view_pending']) ||
            _asBool(permission['can_view']) ||
            _asBool(permission['can_complete_pending']);
        if (!canSee) return false;
        final sectionMatches =
            _permissionIncludesSection(permission, sectionId);
        final moduleMatches =
            permModule.isEmpty || _sameId(permModule, moduleId);
        return sectionMatches && moduleMatches;
      });
    }).toList();

    final p = await pendingFuture;
    if (!mounted) return;
    setState(() {
      _clearDesktopContentCache();
      _clearDesktopSidebarCache();
      modules = moduleRows;
      sections = localSections
          .where((e) => e['activo'] == 1 && belongsToActiveEmpresa(e))
          .toList();
      formatsByModule = moduleFormats;
      dynamicViews = visibleDynamicViews;
      allowedSections = allowedSectionIds;
      pending = p;
      profileName = profileRows.isEmpty
          ? ''
          : (profileRows.first['nombres']?.toString().trim() ?? '');
      localLoaded = true;
      busy = false;
    });
    _applyRestoredNavigation();
    unawaited(_refreshReportNavigationInBackground());
  }

  Future<void> download() async {
    setState(() {
      busy = true;
      busyMessage = 'Preparando actualización...';
      busyProgress = 0.06;
    });
    await Future<void>.delayed(const Duration(milliseconds: 48));
    try {
      final hasCache = await local.hasOfflineBootstrapCache();
      await sync.downloadAllForOffline(
        allowFullFallback: !hasCache,
        forceConfigurationRefresh: true,
        onProgress: (message) {
          if (mounted) {
            setState(() {
              busyMessage = message;
              busyProgress = (busyProgress + 0.045).clamp(0.0, 0.94).toDouble();
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          busyProgress = 0.97;
          busyMessage = 'Aplicando cambios locales...';
        });
      }
      await loadLocal();
      if (!mounted) return;
      final completedAt = DateTime.now();
      if (mounted) {
        setState(() {
          busyProgress = 1;
          lastSyncAt = completedAt;
          online = true;
        });
      }
      unawaited(experience.saveLastSync(completedAt));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datos actualizados.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => online = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sync.friendlyError(e))),
      );
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          busyMessage = null;
          busyProgress = 0;
        });
      }
    }
  }

  Future<void> syncPending() async {
    setState(() => busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 48));
    try {
      final count = await sync.syncPending();
      await loadLocal();
      if (!mounted) return;
      final completedAt = DateTime.now();
      setState(() {
        lastSyncAt = completedAt;
        online = true;
      });
      unawaited(experience.saveLastSync(completedAt));
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registros sincronizados: $count')));
    } catch (e) {
      if (!mounted) return;
      setState(() => online = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(sync.friendlyError(e))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> logout() async {
    await Supabase.instance.client.auth.signOut();
    await LocalSession().clearActiveSession();
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  Widget _drawerItem(IconData icon, String title, VoidCallback onTap,
      {String? badge}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: badge == null
          ? null
          : CircleAvatar(
              radius: 11,
              child: Text(badge, style: const TextStyle(fontSize: 11))),
      onTap: onTap,
    );
  }

  IconData _iconForSection(String sectionId, [String? iconName]) {
    return configurationIconForName(iconName ?? sectionId);
  }

  String _sectionTitle(Map<String, dynamic> section) {
    final id = section['id']?.toString() ?? '';
    final name = section['nombre']?.toString().trim() ?? '';
    return name.isNotEmpty ? name : id;
  }

  String _mobileAppBarTitle() {
    // En móvil el título completo se muestra debajo de la barra superior para no
    // competir con los iconos de actualizar app / datos / sincronizar.
    return '';
  }

  bool _mobileIsHome() {
    return _activeWorkspaceTool == _toolHome &&
        desktopSelectedModule == null &&
        desktopSelectedFormat == null &&
        desktopSelectedReportModule == null &&
        desktopSelectedReportView == null &&
        desktopSelectedSection == null &&
        desktopSelectedDynamicView == null &&
        mobileSelectedSpecial == null;
  }

  bool get _usesImmersiveWorkspace => const {
        _toolMetrics,
        _toolAlerts,
        _toolActions,
      }.contains(_activeWorkspaceTool);

  bool get _canClearConsultant =>
      _activeWorkspaceTool == _toolConsultant &&
      (_consultantTurns.isNotEmpty ||
          _consultantController.text.trim().isNotEmpty);

  Map<String, dynamic>? _sectionForModule(Map<String, dynamic>? module) {
    if (module == null) return null;
    final sectionId = _txt(module['seccion']);
    for (final section in sections) {
      if (_sameId(section['id'], sectionId)) return section;
    }
    return null;
  }

  String _formatFamilyTitle() {
    final module = desktopSelectedModule;
    if (module == null) return '';
    final section = _sectionForModule(module);
    final sectionKey =
        '${section?['id'] ?? ''} ${section?['nombre'] ?? ''}'.toUpperCase();
    final prefix = sectionKey.contains('MATRIZ') ? 'MATRIZ' : 'FORMATOS';
    final moduleName = _txt(module['nombre']).isEmpty
        ? _txt(module['id'])
        : _txt(module['nombre']);
    return '$prefix DE ${moduleName.toUpperCase()}';
  }

  Widget _workspaceTitle({bool compact = false}) {
    if (_activeWorkspaceTool != _toolHome) {
      final (title, icon, color) = switch (_activeWorkspaceTool) {
        _toolConsultant => (
            'Zumac Consultor',
            Icons.forum_outlined,
            const Color(0xFF176B87)
          ),
        _toolCreatorCreate => (
            'Zumac Creator · Crear',
            Icons.dashboard_customize_outlined,
            const Color(0xFF237A57)
          ),
        _toolCreatorEdit => (
            'Zumac Creator · Editar',
            Icons.dashboard_customize_outlined,
            const Color(0xFF237A57)
          ),
        _toolMetrics => (
            'Zumac Metrics',
            Icons.insights_outlined,
            const Color(0xFF6E56CF)
          ),
        _toolAlerts => (
            'Zumac Alerts',
            Icons.notifications_active_outlined,
            const Color(0xFFC56A13)
          ),
        _toolActions => (
            'Zumac Actions',
            Icons.bolt_outlined,
            const Color(0xFFB4425A)
          ),
        _ => ('ZUMAC', Icons.home_outlined, const Color(0xFF176B87)),
      };
      return ZumacFeatureHeader(
        title: title,
        icon: icon,
        color: color,
        compact: compact,
      );
    }
    final familyTitle = _formatFamilyTitle();
    final title = familyTitle.isNotEmpty ? familyTitle : _mobilePageTitle();
    return Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: const Color(0xFF17324D),
        fontSize: compact ? 16 : 18,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  String _mobilePageTitle() {
    if (_activeWorkspaceTool != _toolHome) {
      return switch (_activeWorkspaceTool) {
        _toolConsultant => 'Consultor',
        _toolCreatorCreate => 'Creator · Crear',
        _toolCreatorEdit => 'Creator · Editar',
        _toolMetrics => 'Metrics',
        _toolAlerts => 'Alerts',
        _toolActions => 'Actions',
        _ => 'ZUMAC',
      };
    }
    if (desktopSelectedModule != null && desktopSelectedFormat != null) {
      return desktopSelectedFormat!['nombre']?.toString().trim().isNotEmpty ==
              true
          ? desktopSelectedFormat!['nombre'].toString()
          : (desktopSelectedFormat!['id']?.toString() ?? 'Formato');
    }
    if (desktopSelectedReportModule != null &&
        desktopSelectedReportView != null) {
      return desktopSelectedReportView!['nombre_vista']
                  ?.toString()
                  .trim()
                  .isNotEmpty ==
              true
          ? desktopSelectedReportView!['nombre_vista'].toString()
          : 'Reportes';
    }
    if (desktopSelectedSection != null) {
      return _sectionTitle(desktopSelectedSection!);
    }
    return 'ZUMAC';
  }

  Widget _mobileTitleBar() {
    if (_mobileIsHome()) return const SizedBox.shrink();
    // Cuando se abre un formato en móvil, FormRunnerPage ya trae su propio AppBar
    // con flecha y título. Evita el segundo título fijo que quitaba espacio útil.
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver a la vista anterior',
            icon: const Icon(Icons.arrow_back),
            onPressed: _restorePreviousNavigation,
          ),
          Expanded(child: _workspaceTitle(compact: true)),
          if (_canClearConsultant)
            TextButton.icon(
              onPressed: _consultantBusy ? null : _clearConsultantAnswer,
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: const Text('Limpiar'),
            ),
        ],
      ),
    );
  }

  void _openHomeFromBreadcrumb() {
    _rememberNavigation();
    setState(() {
      _clearDesktopContentCache();
      _clearDesktopSidebarCache();
      _clearConsultantFocusState();
      _activeWorkspaceTool = _toolHome;
      _consultantOpen = false;
      desktopSelectedSection = null;
      desktopSelectedModule = null;
      desktopSelectedFormat = null;
      desktopSelectedReportModule = null;
      desktopSelectedReportView = null;
      desktopSelectedDynamicView = null;
      mobileSelectedSpecial = null;
    });
    unawaited(_persistNavigation());
  }

  Widget _animatedContent(Widget child) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.015, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey('content-${_desktopContentSignature()}'),
        child: child,
      ),
    );
  }

  VoidCallback _sectionTap(Map<String, dynamic> section) {
    final id = section['id']?.toString() ?? '';
    final kind = _sectionKind(section);
    final desktopLayout = isWideDesktopLayout(context);

    if (desktopLayout) {
      return () => _selectDesktopSection(section);
    }

    if (id == 'modulos') return () => Navigator.pop(context);
    if (kind == 'REGISTROS_LOCALES') {
      return () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const LocalRecordsPage()))
          .then((_) => loadLocal());
    }
    if (kind == 'REPORTES') {
      return () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const ReportsPage()));
    }
    if (_sectionUsesDynamicViews(section)) {
      return () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => DynamicViewsPage(
                  section: section,
                  onPendingChanged: loadLocal))).then((_) => loadLocal());
    }
    return () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => GenericSectionPage(section: section)))
        .then((_) => loadLocal());
  }

  // ignore: unused_element
  Widget _menuItems() {
    final visibleSections =
        sections.where((s) => _canSection(s['id']?.toString() ?? '')).toList();

    if (visibleSections.isEmpty && _canSection('modulos')) {
      visibleSections.add({
        'id': 'modulos',
        'nombre': 'Formatos',
        'icono': 'apps',
        'orden': 1,
        'activo': 1,
      });
    }

    return Column(
      children: [
        for (final section in visibleSections)
          _drawerItem(
            _iconForSection(
                section['id']?.toString() ?? '', section['icono']?.toString()),
            _sectionTitle(section),
            _sectionTap(section),
            badge: _sectionKind(section) == 'REGISTROS_LOCALES' && pending > 0
                ? '$pending'
                : null,
          ),
      ],
    );
  }

  void _selectDesktopSection(Map<String, dynamic> section) {
    unawaited(_refreshIncrementallyOnEntry());
    if (desktopSelectedSection?['id']?.toString() ==
            section['id']?.toString() &&
        desktopSelectedModule == null &&
        desktopSelectedFormat == null &&
        desktopSelectedReportModule == null &&
        desktopSelectedReportView == null &&
        desktopSelectedDynamicView == null) {
      return;
    }
    _rememberNavigation();
    setState(() {
      _clearDesktopContentCache();
      _clearDesktopSidebarCache();
      _clearConsultantFocusState();
      _activeWorkspaceTool = _toolHome;
      _consultantOpen = false;
      desktopSelectedSection = Map<String, dynamic>.from(section);
      desktopSelectedModule = null;
      desktopSelectedFormat = null;
      desktopSelectedReportModule = null;
      desktopSelectedReportView = null;
      desktopSelectedDynamicView = null;
      mobileSelectedSpecial = null;
    });
    unawaited(_persistNavigation());
  }

  Widget _desktopPanelShell({required String title, required Widget child}) {
    // En Windows el panel derecho debe mostrar directamente el contenido seleccionado.
    // El título superior fijo se elimina para no duplicar el nombre de la vista.
    return child;
  }

  void _selectDesktopFormat(
      Map<String, dynamic> module, Map<String, dynamic> format) {
    unawaited(_refreshIncrementallyOnEntry());
    final sameSelection = desktopSelectedModule?['id']?.toString() ==
            module['id']?.toString() &&
        desktopSelectedFormat?['id']?.toString() == format['id']?.toString() &&
        desktopSelectedSection == null &&
        desktopSelectedReportModule == null &&
        desktopSelectedReportView == null &&
        desktopSelectedDynamicView == null;
    if (sameSelection) return;
    _rememberNavigation();
    setState(() {
      _clearDesktopContentCache();
      _clearDesktopSidebarCache();
      _clearConsultantFocusState();
      _activeWorkspaceTool = _toolHome;
      _consultantOpen = false;
      desktopSelectedSection = null;
      desktopSelectedModule = Map<String, dynamic>.from(module);
      desktopSelectedFormat = Map<String, dynamic>.from(format);
      desktopSelectedReportModule = null;
      desktopSelectedReportView = null;
      desktopSelectedDynamicView = null;
      mobileSelectedSpecial = null;
    });
    unawaited(_persistNavigation());
  }

  void _selectDesktopReportView(
      Map<String, dynamic> module, Map<String, dynamic> view) {
    _rememberNavigation();
    setState(() {
      _clearDesktopContentCache();
      _clearDesktopSidebarCache();
      _clearConsultantFocusState();
      _activeWorkspaceTool = _toolHome;
      _consultantOpen = false;
      desktopSelectedSection = null;
      desktopSelectedModule = null;
      desktopSelectedFormat = null;
      desktopSelectedReportModule = Map<String, dynamic>.from(module);
      desktopSelectedReportView = Map<String, dynamic>.from(view);
      desktopSelectedDynamicView = null;
      mobileSelectedSpecial = null;
    });
    unawaited(_persistNavigation());
  }

  void _selectDesktopDynamicView(
      Map<String, dynamic> section, Map<String, dynamic> view) {
    _rememberNavigation();
    setState(() {
      _clearDesktopContentCache();
      _clearDesktopSidebarCache();
      _clearConsultantFocusState();
      _activeWorkspaceTool = _toolHome;
      _consultantOpen = false;
      desktopSelectedSection = Map<String, dynamic>.from(section);
      desktopSelectedDynamicView = Map<String, dynamic>.from(view);
      desktopSelectedModule = null;
      desktopSelectedFormat = null;
      desktopSelectedReportModule = null;
      desktopSelectedReportView = null;
      mobileSelectedSpecial = null;
    });
    unawaited(_persistNavigation());
  }

  Widget _desktopDefaultPanel() {
    return _homeDashboard(desktop: true);
  }

  Widget _homeDashboard({required bool desktop}) {
    if (_consultantOpen && canUseZumacConsultor) {
      return _consultantWorkspace(desktop: desktop);
    }
    final normalizedName = profileName.trim();
    final firstName = normalizedName.isEmpty
        ? ''
        : normalizedName.split(RegExp(r'\s+')).first;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final compact = constraints.maxWidth < 620;
        final horizontalPadding =
            (constraints.maxWidth * 0.045).clamp(14.0, 64.0);
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFF8FBFC),
                Color(0xFFEAF4F6),
                Color(0xFFF4F8FA),
              ],
            ),
          ),
          child: Stack(
            children: [
              const Positioned(
                top: -90,
                right: -70,
                child: _HomeDecorationCircle(
                  size: 230,
                  color: Color(0x17176B87),
                ),
              ),
              const Positioned(
                bottom: -110,
                left: -80,
                child: _HomeDecorationCircle(
                  size: 270,
                  color: Color(0x120A315E),
                ),
              ),
              SingleChildScrollView(
                key: const PageStorageKey('zumac-home-scroll'),
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  compact ? 4 : 6,
                  horizontalPadding,
                  compact ? 24 : 36,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: ZumacResponsiveLimits.page,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _welcomeHomePanel(
                          firstName: firstName,
                          wide: wide,
                          desktop: desktop,
                        ),
                        SizedBox(height: compact ? 16 : 22),
                        _homeTools(compact: compact),
                        if (_consultantOpen && canUseZumacConsultor) ...[
                          SizedBox(height: compact ? 16 : 22),
                          _consultantPanel(compact: compact),
                          if (_consultantTurns.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _consultantConversationPanel(),
                          ],
                          const SizedBox(height: 14),
                          _consultantComposer(compact: compact),
                        ],
                        if (_consultantOpen &&
                            canUseZumacConsultor &&
                            canManageCompany) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) => const KnowledgeAdminPage(),
                                ),
                              ),
                              icon: const Icon(Icons.hub_outlined),
                              label: const Text(
                                'Revisar base de conocimiento IA',
                              ),
                            ),
                          ),
                        ],
                      ],
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

  // ignore: unused_element
  Widget _homeQuickActions({
    required bool desktop,
  }) {
    Widget action({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      Widget? badge,
    }) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: label,
            onPressed: onPressed,
            icon: Icon(icon),
          ),
          if (badge != null) Positioned(right: -3, top: -3, child: badge),
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (!desktop)
          action(
            icon: Icons.menu,
            label: 'Menú',
            onPressed: () => scaffoldKey.currentState?.openDrawer(),
          ),
        action(
          icon: Icons.refresh,
          label: 'Actualizar datos',
          onPressed: busy ? null : download,
        ),
        action(
          icon: online ? Icons.sync : Icons.sync_problem_outlined,
          label: 'Sincronizar',
          onPressed: busy ? null : syncPending,
          badge: pending <= 0
              ? null
              : CircleAvatar(
                  radius: 9,
                  child: Text(
                    '$pending',
                    style: const TextStyle(fontSize: 9),
                  ),
                ),
        ),
        action(
          icon: Icons.help_outline,
          label: 'Guía de uso',
          onPressed: busy ? null : () => _openOnboarding(replay: true),
        ),
      ],
    );
  }

  Widget _consultantWorkspace({required bool desktop}) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF8FBFC), Color(0xFFEAF4F6)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                desktop ? 34 : 14,
                20,
                desktop ? 34 : 14,
                34,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _consultantPanel(compact: !desktop),
                      if (_consultantTurns.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _consultantConversationPanel(),
                      ],
                      const SizedBox(height: 14),
                      _consultantComposer(compact: !desktop),
                      if (canManageCompany) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => const KnowledgeAdminPage(),
                              ),
                            ),
                            icon: const Icon(Icons.hub_outlined),
                            label:
                                const Text('Revisar base de conocimiento IA'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeTools({required bool compact}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1050
            ? 5
            : constraints.maxWidth >= 620
                ? 3
                : compact
                    ? 2
                    : 3;
        const spacing = 12.0;
        final cardWidth = math.min(
          220.0,
          (constraints.maxWidth - (columns - 1) * spacing) / columns,
        );

        Widget toolCard({
          required String title,
          required String subtitle,
          required IconData icon,
          required Color color,
          required VoidCallback? onTap,
          bool selected = false,
          String? badge,
        }) {
          final enabled = onTap != null;
          return SizedBox(
            width: cardWidth,
            height: compact ? 142 : 150,
            child: Material(
              color: selected ? color : Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: selected ? color : const Color(0xFFD5E5EA),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1017324D),
                        blurRadius: 16,
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 39,
                            height: 39,
                            decoration: BoxDecoration(
                              color: selected
                                  ? Colors.white.withValues(alpha: 0.18)
                                  : color.withValues(alpha: 0.11),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              icon,
                              color: selected
                                  ? Colors.white
                                  : enabled
                                      ? color
                                      : const Color(0xFF8A99A8),
                            ),
                          ),
                          const Spacer(),
                          if (badge != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? Colors.white.withValues(alpha: 0.18)
                                    : const Color(0xFFF0F4F6),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                badge,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFF60758A),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : enabled
                                  ? const Color(0xFF17324D)
                                  : const Color(0xFF7A8A99),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? Colors.white70
                              : const Color(0xFF60758A),
                          fontSize: 11,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Herramientas de trabajo',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF17324D),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: spacing,
              runSpacing: spacing,
              children: [
                toolCard(
                  title: 'Consultor',
                  subtitle: canUseZumacConsultor
                      ? 'Pregunta cualquier tema de tu empresa.'
                      : 'No habilitado para esta empresa.',
                  icon: Icons.forum_outlined,
                  color: const Color(0xFF176B87),
                  selected: _consultantOpen && canUseZumacConsultor,
                  onTap: canUseZumacConsultor
                      ? () => _activateWorkspaceTool(_toolConsultant)
                      : null,
                ),
                toolCard(
                  title: 'Creator',
                  subtitle: canUseZumacCreator && canManageConfiguration
                      ? 'Crear o editar la estructura de la empresa.'
                      : 'No habilitado para este usuario.',
                  icon: Icons.dashboard_customize_outlined,
                  color: const Color(0xFF237A57),
                  onTap: canUseZumacCreator && canManageConfiguration
                      ? _chooseCreatorMode
                      : null,
                ),
                toolCard(
                  title: 'Metrics',
                  subtitle: canUseZumacMetrics
                      ? 'Dashboards, indicadores y análisis visual.'
                      : 'No habilitado para esta empresa.',
                  icon: Icons.insights_outlined,
                  color: const Color(0xFF6E56CF),
                  onTap: canUseZumacMetrics ? _openMetrics : null,
                ),
                toolCard(
                  title: 'Alerts',
                  subtitle: canUseZumacAlerts
                      ? 'Vigilancia de condiciones y anomalías.'
                      : 'No habilitado para esta empresa.',
                  icon: Icons.notifications_active_outlined,
                  color: const Color(0xFFC56A13),
                  badge:
                      openAlertEvents > 0 ? '$openAlertEvents ABIERTAS' : null,
                  onTap: canUseZumacAlerts ? () => _openAlertsActions(0) : null,
                ),
                toolCard(
                  title: 'Actions',
                  subtitle: canUseZumacActions
                      ? 'Tareas, aprobaciones y evidencia.'
                      : 'No habilitado para esta empresa.',
                  icon: Icons.bolt_outlined,
                  color: const Color(0xFFB4425A),
                  badge:
                      pendingActions > 0 ? '$pendingActions PENDIENTES' : null,
                  onTap:
                      canUseZumacActions ? () => _openAlertsActions(1) : null,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _consultantPanel({required bool compact}) {
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD5E5EA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1217324D),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Consulta el conocimiento de tu empresa, compara datos y haz preguntas de seguimiento.',
                  style: TextStyle(
                    color: Color(0xFF60758A),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _consultantBusy
                  ? null
                  : () => setState(() {
                        _clearDesktopContentCache();
                        _consultantSuggestionsExpanded =
                            !_consultantSuggestionsExpanded;
                      }),
              icon: Icon(
                _consultantSuggestionsExpanded
                    ? Icons.expand_less
                    : Icons.lightbulb_outline,
                size: 18,
              ),
              label: Text(
                _consultantSuggestionsExpanded
                    ? 'Ocultar sugerencias'
                    : 'Sugerencias',
              ),
            ),
          ),
          if (_consultantSuggestionsExpanded)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.account_tree_outlined, size: 17),
                  label: const Text('Relaciones del drenaje'),
                  onPressed: _consultantBusy
                      ? null
                      : () {
                          _consultantController.text =
                              '¿Qué registros están relacionados con drenaje?';
                          _askConsultant();
                        },
                ),
                ActionChip(
                  avatar: const Icon(Icons.science_outlined, size: 17),
                  label: const Text('pH mayores a 6 hoy'),
                  onPressed: _consultantBusy
                      ? null
                      : () {
                          _consultantController.text =
                              '¿Hay pH mayores a 6 hoy?';
                          _askConsultant();
                        },
                ),
                ActionChip(
                  avatar: const Icon(Icons.how_to_reg_outlined, size: 17),
                  label: const Text('Asistencia y salidas de hoy'),
                  onPressed: _consultantBusy
                      ? null
                      : () {
                          _consultantController.text =
                              '¿Cuántas personas tienen asistencia hoy y cuántas ya salieron?';
                          _askConsultant();
                        },
                ),
                ActionChip(
                  avatar: const Icon(Icons.compare_arrows_outlined, size: 17),
                  label: const Text('Tareo sin asistencia'),
                  onPressed: _consultantBusy
                      ? null
                      : () {
                          _consultantController.text =
                              '¿Qué personas tienen tareo hoy pero no asistencia?';
                          _askConsultant();
                        },
                ),
                ActionChip(
                  avatar: const Icon(Icons.pest_control_outlined, size: 17),
                  label: const Text('Plagas, lotes y productos'),
                  onPressed: _consultantBusy
                      ? null
                      : () {
                          _consultantController.text =
                              '¿Qué plagas se encontraron, en qué lotes y qué productos con stock sirven para combatirlas?';
                          _askConsultant();
                        },
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _consultantConversationPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < _consultantTurns.length; index++) ...[
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 760),
              margin: const EdgeInsets.only(left: 38),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFF176B87),
                borderRadius: BorderRadius.circular(17).copyWith(
                  bottomRight: const Radius.circular(5),
                ),
              ),
              child: Text(
                _consultantTurns[index].question,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _consultantAnswerPanel(_consultantTurns[index].result),
          if (index != _consultantTurns.length - 1) const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _consultantComposer({required bool compact}) {
    return Container(
      key: _consultantComposerKey,
      padding: EdgeInsets.all(compact ? 11 : 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBFDCE4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1017324D),
            blurRadius: 16,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_consultantSpeechListening) ...[
            const Row(
              children: [
                Icon(Icons.graphic_eq_rounded,
                    size: 18, color: Color(0xFFB4425A)),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Escuchando… habla con claridad y Zumac escribirá la pregunta.',
                    style: TextStyle(
                      color: Color(0xFFB4425A),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _consultantController,
                  focusNode: _consultantFocusNode,
                  enabled: !_consultantBusy,
                  minLines: 1,
                  maxLines: compact ? 4 : 5,
                  textInputAction: TextInputAction.send,
                  onChanged: (_) => setState(_clearDesktopContentCache),
                  onSubmitted: (_) => _askConsultant(),
                  decoration: const InputDecoration(
                    hintText: 'Consulta',
                    prefixIcon: Icon(Icons.chat_bubble_outline),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton.filledTonal(
                  tooltip: _consultantSpeechListening
                      ? 'Detener dictado'
                      : 'Dictar pregunta',
                  style: IconButton.styleFrom(
                    backgroundColor: _consultantSpeechListening
                        ? const Color(0xFFFFE8EC)
                        : const Color(0xFFE2F2F5),
                    foregroundColor: _consultantSpeechListening
                        ? const Color(0xFFB4425A)
                        : const Color(0xFF176B87),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _consultantBusy || _consultantSpeechInitializing
                      ? null
                      : _toggleConsultantSpeech,
                  icon: _consultantSpeechInitializing
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _consultantSpeechListening
                              ? Icons.stop_rounded
                              : Icons.mic_none_rounded,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _consultantBusy ? null : _askConsultant,
                  child: _consultantBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _consultantAnswerPanel(ZumacConsultantResult result) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5F7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBFDCE4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.auto_awesome,
                color: Color(0xFF176B87),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  result.answer,
                  style: const TextStyle(
                    color: Color(0xFF17324D),
                    fontSize: 16,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (result.citations.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Fuentes consultadas',
              style: TextStyle(
                color: Color(0xFF17324D),
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (var index = 0; index < result.citations.length; index++)
                  Tooltip(
                    message: result.citations[index].status == 'GENERADA_IA'
                        ? 'Contenido sugerido por IA pendiente de aprobación administrativa'
                        : 'Contenido aprobado',
                    child: Chip(
                      avatar: Icon(
                        result.citations[index].status == 'GENERADA_IA'
                            ? Icons.auto_awesome_outlined
                            : Icons.verified_outlined,
                        size: 16,
                        color: result.citations[index].status == 'GENERADA_IA'
                            ? const Color(0xFF9A6700)
                            : const Color(0xFF237A57),
                      ),
                      label: Text(
                        '[${index + 1}] ${result.citations[index].title} · '
                        '${result.citations[index].sourceName}',
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (result.relatedConcepts.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Conocimiento relacionado',
              style: TextStyle(
                color: Color(0xFF17324D),
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final concept in result.relatedConcepts.take(10))
                  ActionChip(
                    label: Text(concept),
                    onPressed: _consultantBusy
                        ? null
                        : () {
                            _consultantController.text =
                                '¿Cómo se relaciona $concept con lo anterior?';
                            _askConsultant();
                          },
                  ),
              ],
            ),
          ],
          if (result.detailLines.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .72),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD2E5EA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final line in result.detailLines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        line,
                        style: const TextStyle(
                          color: Color(0xFF28465E),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (result.options.isNotEmpty) ...[
            const SizedBox(height: 13),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in result.options)
                  ActionChip(
                    avatar: Icon(
                      option.kind == ZumacConsultantOptionKind.source
                          ? Icons.assignment_outlined
                          : Icons.calendar_month_outlined,
                      size: 17,
                    ),
                    label: Text(option.label),
                    onPressed: _consultantBusy
                        ? null
                        : () => _askConsultant(
                              questionOverride: option.query,
                              displayQuestion: option.label,
                              selectedSourceTable: option.sourceTable,
                            ),
                  ),
              ],
            ),
          ],
          if (result.reportTables.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final report in result.reportTables)
                  OutlinedButton.icon(
                    onPressed: report.canOpen
                        ? () => _openConsultantReport(report)
                        : null,
                    icon: const Icon(Icons.open_in_new, size: 17),
                    label: Text(
                      result.reportTables.length == 1
                          ? 'Ver registros'
                          : 'Ver registros · ${report.title}',
                    ),
                  ),
              ],
            ),
          ],
          if (result.relatedTables.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Quizá te interesa',
              style: TextStyle(
                color: Color(0xFF17324D),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Estas son tablas de referencia relacionadas. Ábrelas solo si necesitas consultar su catálogo.',
              style: TextStyle(
                color: Color(0xFF60758A),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final related in result.relatedTables)
                  ActionChip(
                    avatar: const Icon(Icons.link_outlined, size: 17),
                    label: Text(related.title),
                    onPressed: related.canOpen
                        ? () => _openConsultantRelatedTable(related)
                        : null,
                  ),
              ],
            ),
          ],
          if ((result.followUpPrompt ?? '').isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              result.followUpPrompt!,
              style: const TextStyle(
                color: Color(0xFF5F935D),
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _consultantReportTable(ZumacConsultantReportTable report) {
    return _ConsultantReportTableCard(
      key: ValueKey('consultant-report-${report.tableName}'),
      report: report,
      onOpen: report.canOpen ? () => _openConsultantReport(report) : null,
    );
  }

  Widget _welcomeHomePanel({
    required String firstName,
    required bool wide,
    required bool desktop,
  }) {
    final message = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          firstName.isEmpty ? '¡Hola!' : '¡Hola, $firstName!',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: const Color(0xFF176B87),
            fontSize: desktop ? 31 : 27,
            height: 1.1,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Tus herramientas y datos, listos para convertir trabajo en decisiones.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: const Color(0xFF17324D),
            fontSize: desktop ? 20 : 18,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: wide ? 22 : 16,
        vertical: wide ? 18 : 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x80D5E5EA)),
      ),
      child: message,
    );
  }

  String _desktopContentSignature() {
    if (busy) return 'busy';
    if (_activeWorkspaceTool != _toolHome) {
      return 'tool:$_activeWorkspaceTool';
    }
    if (desktopSelectedModule != null && desktopSelectedFormat != null) {
      return 'format:${desktopSelectedModule!['id']}:${desktopSelectedFormat!['id']}:'
          '${_consultantTableName ?? ''}:${_consultantRecordField ?? ''}:'
          '${_consultantRecordValue ?? ''}';
    }
    if (desktopSelectedModule != null) {
      return 'module:${desktopSelectedModule!['id']}';
    }
    if (desktopSelectedReportModule != null &&
        desktopSelectedReportView != null) {
      return 'report:${desktopSelectedReportModule!['id']}:${desktopSelectedReportView!['id']}';
    }
    if (desktopSelectedSection != null && desktopSelectedDynamicView != null) {
      return 'dynamic:${desktopSelectedSection!['id']}:${desktopSelectedDynamicView!['id']}';
    }
    if (desktopSelectedSection != null) {
      return 'section:${desktopSelectedSection!['id']}';
    }
    final result =
        _consultantTurns.isEmpty ? null : _consultantTurns.last.result;
    return 'home:${_consultantBusy ? 1 : 0}:'
        '${_consultantOpen ? 1 : 0}:${_consultantTurns.length}:'
        '${result == null ? 0 : Object.hash(result.question, result.answer, result.findings.length)}';
  }

  Widget _desktopSelectedContentCached() {
    final key = _desktopContentSignature();
    if (_desktopContentCacheKey == key && _desktopContentCache != null) {
      return _desktopContentCache!;
    }
    final built = RepaintBoundary(child: _desktopSelectedContentRaw());
    _desktopContentCacheKey = key;
    _desktopContentCache = built;
    return built;
  }

  Widget _desktopSelectedContentRaw() {
    if (busy) return const Center(child: CircularProgressIndicator());

    final toolContent = _workspaceToolContent(desktop: true);
    if (toolContent != null) return toolContent;

    final module = desktopSelectedModule;
    final format = desktopSelectedFormat;
    if (module != null && format != null) {
      return _desktopPanelShell(
        title: 'Formatos',
        child: DesktopFormatRecordsPage(
          key: ValueKey(
            '${module['id']}_${format['id']}_${_consultantTableName ?? ''}_'
            '${_consultantRecordField ?? ''}_${_consultantRecordValue ?? ''}',
          ),
          module: module,
          format: format,
          embedded: true,
          onLocalRecordsChanged: loadLocal,
          initialTableName: _consultantTableName,
          initialRecordField: _consultantRecordField,
          initialRecordValue: _consultantRecordValue,
        ),
      );
    }
    if (module != null) {
      return _desktopPanelShell(
        title: _txt(module['nombre']),
        child: _desktopFormatsForModule(module),
      );
    }

    final reportModule = desktopSelectedReportModule;
    final reportView = desktopSelectedReportView;
    if (reportModule != null && reportView != null) {
      return _desktopPanelShell(
        title: 'Reportes',
        child: ReportsPage(
          key: ValueKey('report_${reportModule['id']}_${reportView['id']}'),
          embedded: true,
          initialModuleId: reportModule['id']?.toString(),
          initialViewId: reportView['id']?.toString(),
          showRail: false,
        ),
      );
    }

    final section = desktopSelectedSection;
    if (section != null) {
      final id = section['id']?.toString() ?? '';
      final title = _sectionTitle(section);
      final kind = _sectionKind(section);
      if (kind == 'REGISTROS_LOCALES') {
        return _desktopPanelShell(
            title: title,
            child: LocalRecordsPage(embedded: true, onChanged: loadLocal));
      }
      if (kind == 'REPORTES') {
        return _desktopPanelShell(
            title: title, child: const ReportsPage(embedded: true));
      }
      if (_sectionUsesDynamicViews(section)) {
        return _desktopPanelShell(
          title: title,
          child: DynamicViewsPage(
            section: section,
            view: desktopSelectedDynamicView,
            embedded: true,
            onPendingChanged: loadLocal,
          ),
        );
      }
      if (_sectionHasFormatModules(id)) {
        return _desktopPanelShell(title: title, child: _desktopModulesList());
      }
      return _desktopPanelShell(
          title: title,
          child: GenericSectionPage(section: section, embedded: true));
    }

    return _desktopDefaultPanel();
  }

  Widget _desktopModulesList() {
    return ListView.separated(
      padding: const EdgeInsets.all(18),
      itemCount: modules.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final module = modules[index];
        final moduleId = module['id']?.toString() ?? '';
        final formats =
            formatsByModule[moduleId] ?? const <Map<String, dynamic>>[];

        return Card(
          child: ExpansionTile(
            leading:
                Icon(configurationIconForName(module['icono']?.toString())),
            title: Text(
              '${module['nombre']}',
              style:
                  const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
            // No mostramos el id técnico debajo del módulo para ahorrar espacio en el menú.
            subtitle: null,
            children: formats.isEmpty
                ? const [
                    ListTile(
                      dense: true,
                      title:
                          Text('No tienes formatos permitidos en este módulo.'),
                    ),
                  ]
                : formats.map((format) {
                    return ListTile(
                      contentPadding:
                          const EdgeInsets.only(left: 72, right: 24),
                      leading: const Icon(Icons.assignment_outlined),
                      title: Text('${format['nombre']}'),
                      // No mostramos el id técnico debajo del formato para ahorrar espacio en el menú.
                      subtitle: null,
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () => _selectDesktopFormat(module, format),
                    );
                  }).toList(),
          ),
        );
      },
    );
  }

  Widget _desktopFormatsForModule(Map<String, dynamic> module) {
    final moduleId = _txt(module['id']);
    final moduleFormats =
        formatsByModule[moduleId] ?? const <Map<String, dynamic>>[];
    if (moduleFormats.isEmpty) {
      return const Center(
        child: Text('No tienes formatos permitidos en este módulo.'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(18),
      itemCount: moduleFormats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final format = moduleFormats[index];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFDCE7EC)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE2F1F4),
              foregroundColor: Color(0xFF176B87),
              child: Icon(Icons.assignment_outlined),
            ),
            title: Text(
              _txt(format['nombre']).isEmpty
                  ? _txt(format['id'])
                  : _txt(format['nombre']),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('Abrir formato y registros'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _selectDesktopFormat(module, format),
          ),
        );
      },
    );
  }

  String _desktopSidebarSignature() {
    final selected = [
      desktopSidebarOpen ? 'open' : 'closed',
      pending.toString(),
      desktopSelectedModule?['id']?.toString() ?? '',
      desktopSelectedFormat?['id']?.toString() ?? '',
      desktopSelectedSection?['id']?.toString() ?? '',
      desktopSelectedReportModule?['id']?.toString() ?? '',
      desktopSelectedReportView?['id']?.toString() ?? '',
      desktopSelectedDynamicView?['id']?.toString() ?? '',
      _expandedSectionId ?? '',
      modules.length.toString(),
      sections.length.toString(),
      formatsByModule.values.fold<int>(0, (a, b) => a + b.length).toString(),
      reportModules.length.toString(),
      reportViews.length.toString(),
      dynamicViews.length.toString(),
      profileName,
    ];
    return selected.join('|');
  }

  Widget _desktopSidebarCached() {
    final key = _desktopSidebarSignature();
    if (_desktopSidebarCacheKey == key && _desktopSidebarCache != null) {
      return _desktopSidebarCache!;
    }
    final built = RepaintBoundary(child: _desktopSidebar());
    _desktopSidebarCacheKey = key;
    _desktopSidebarCache = built;
    return built;
  }

  Widget _desktopSidebar() {
    final visibleSections = sections
        .where((section) => _canSection(section['id']?.toString() ?? ''))
        .where((section) => _sectionKind(section) != 'REPORTES')
        .toList();
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final openWidth = (viewportWidth * .19).clamp(272.0, 340.0);

    return Container(
      width: desktopSidebarOpen ? openWidth : 68,
      decoration: const BoxDecoration(
        color: Color(0xFF0F2F4A),
        boxShadow: [
          BoxShadow(
              color: Color(0x22000000), blurRadius: 16, offset: Offset(4, 0))
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 8, 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.asset(
                      'assets/images/logo_app.png',
                      width: 26,
                      height: 26,
                      cacheWidth: 78,
                      cacheHeight: 78,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  if (desktopSidebarOpen) ...[
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'ZUMAC',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .4),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Inicio',
                      onPressed: _openHomeFromBreadcrumb,
                      icon: const Icon(
                        Icons.home_outlined,
                        color: Colors.white,
                      ),
                    ),
                  ],
                  IconButton(
                    tooltip:
                        desktopSidebarOpen ? 'Ocultar menú' : 'Mostrar menú',
                    onPressed: () {
                      desktopSidebarOpen = !desktopSidebarOpen;
                      _clearDesktopSidebarCache();
                      _desktopSidebarOpenNotifier.value = desktopSidebarOpen;
                      unawaited(_persistNavigation());
                    },
                    icon: Icon(
                        desktopSidebarOpen
                            ? Icons.chevron_left
                            : Icons.chevron_right,
                        color: Colors.white),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            Expanded(
              child: desktopSidebarOpen
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                      children: [
                        for (final section in visibleSections.where(
                            (s) => _sectionHasFormatModules(_txt(s['id']))))
                          Theme(
                            data: Theme.of(context)
                                .copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              key: ValueKey(
                                  'desktop-section-${_txt(section['id'])}-${_expandedSectionId == _txt(section['id'])}'),
                              initiallyExpanded:
                                  _expandedSectionId == _txt(section['id']),
                              onExpansionChanged: (expanded) =>
                                  _onSectionExpansionChanged(
                                      _txt(section['id']), expanded),
                              leading: Icon(
                                  _iconForSection(_txt(section['id']),
                                      section['icono']?.toString()),
                                  color: Colors.white),
                              iconColor: Colors.white,
                              collapsedIconColor: Colors.white70,
                              title: Text(_sectionTitle(section),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                              children: _modulesForSection(_txt(section['id']))
                                  .map((module) {
                                final moduleId = module['id']?.toString() ?? '';
                                final formats = formatsByModule[moduleId] ??
                                    const <Map<String, dynamic>>[];
                                return ExpansionTile(
                                  tilePadding:
                                      const EdgeInsets.only(left: 24, right: 8),
                                  leading: Icon(
                                    configurationIconForName(
                                      module['icono']?.toString(),
                                    ),
                                    color: Colors.white70,
                                    size: 19,
                                  ),
                                  childrenPadding: EdgeInsets.zero,
                                  iconColor: Colors.white,
                                  collapsedIconColor: Colors.white54,
                                  title: Text(
                                    module['nombre']?.toString() ?? moduleId,
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  children: formats.map((format) {
                                    return ListTile(
                                      dense: true,
                                      contentPadding: const EdgeInsets.only(
                                          left: 46, right: 8),
                                      leading: const Icon(
                                          Icons.description_outlined,
                                          color: Colors.white54,
                                          size: 18),
                                      title: Text(
                                        format['nombre']?.toString() ??
                                            format['id']?.toString() ??
                                            '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12.5),
                                      ),
                                      selected: desktopSelectedFormat?['id']
                                              ?.toString() ==
                                          format['id']?.toString(),
                                      selectedTileColor: Colors.white10,
                                      onTap: () =>
                                          _selectDesktopFormat(module, format),
                                    );
                                  }).toList(),
                                );
                              }).toList(),
                            ),
                          ),
                        for (final section in visibleSections.where(
                            (s) => !_sectionHasFormatModules(_txt(s['id']))))
                          if (_sectionKind(section) == 'REPORTES')
                            Theme(
                              data: Theme.of(context)
                                  .copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                key: ValueKey(
                                    'desktop-section-${_txt(section['id'])}-${_expandedSectionId == _txt(section['id'])}'),
                                initiallyExpanded:
                                    _expandedSectionId == _txt(section['id']),
                                onExpansionChanged: (expanded) =>
                                    _onSectionExpansionChanged(
                                        _txt(section['id']), expanded),
                                leading: Icon(
                                    _iconForSection(
                                        section['id']?.toString() ?? '',
                                        section['icono']?.toString()),
                                    color: Colors.white70),
                                iconColor: Colors.white,
                                collapsedIconColor: Colors.white70,
                                title: Text(_sectionTitle(section),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600)),
                                children: reportModules.map((module) {
                                  final moduleViews =
                                      _reportViewsForModule(module);
                                  return ExpansionTile(
                                    tilePadding: const EdgeInsets.only(
                                        left: 24, right: 8),
                                    childrenPadding: EdgeInsets.zero,
                                    iconColor: Colors.white,
                                    collapsedIconColor: Colors.white54,
                                    title: Text(
                                      module['nombre']?.toString() ??
                                          module['id']?.toString() ??
                                          '',
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    children: moduleViews.isEmpty
                                        ? const [
                                            ListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.only(
                                                  left: 46, right: 8),
                                              title: Text(
                                                  'Sin vistas permitidas',
                                                  style: TextStyle(
                                                      color: Colors.white54,
                                                      fontSize: 12)),
                                            ),
                                          ]
                                        : moduleViews.map((view) {
                                            return ListTile(
                                              dense: true,
                                              contentPadding:
                                                  const EdgeInsets.only(
                                                      left: 46, right: 8),
                                              leading: const Icon(
                                                  Icons.insert_chart_outlined,
                                                  color: Colors.white54,
                                                  size: 18),
                                              title: Text(
                                                view['nombre_vista']
                                                        ?.toString() ??
                                                    view['id']?.toString() ??
                                                    '',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12.5),
                                              ),
                                              selected:
                                                  desktopSelectedReportView?[
                                                              'id']
                                                          ?.toString() ==
                                                      view['id']?.toString(),
                                              selectedTileColor: Colors.white10,
                                              onTap: () =>
                                                  _selectDesktopReportView(
                                                      module, view),
                                            );
                                          }).toList(),
                                  );
                                }).toList(),
                              ),
                            )
                          else if (_sectionUsesDynamicViews(section))
                            Theme(
                              data: Theme.of(context)
                                  .copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                key: ValueKey(
                                    'desktop-section-${_txt(section['id'])}-${_expandedSectionId == _txt(section['id'])}'),
                                initiallyExpanded:
                                    _expandedSectionId == _txt(section['id']),
                                onExpansionChanged: (expanded) =>
                                    _onSectionExpansionChanged(
                                        _txt(section['id']), expanded),
                                leading: Icon(
                                    _iconForSection(
                                        section['id']?.toString() ?? '',
                                        section['icono']?.toString()),
                                    color: Colors.white70),
                                iconColor: Colors.white,
                                collapsedIconColor: Colors.white70,
                                title: Text(_sectionTitle(section),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600)),
                                children: _dynamicViewsGroupedByModule(
                                        section['id']?.toString() ?? '')
                                    .entries
                                    .map((entry) {
                                  return ExpansionTile(
                                    tilePadding: const EdgeInsets.only(
                                        left: 24, right: 8),
                                    childrenPadding: EdgeInsets.zero,
                                    iconColor: Colors.white,
                                    collapsedIconColor: Colors.white54,
                                    title: Text(entry.key,
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                    children: entry.value
                                        .map((view) => ListTile(
                                              dense: true,
                                              contentPadding:
                                                  const EdgeInsets.only(
                                                      left: 46, right: 8),
                                              leading: const Icon(
                                                  Icons.view_list_outlined,
                                                  color: Colors.white54,
                                                  size: 18),
                                              title: Text(
                                                  view['nombre_vista']
                                                          ?.toString() ??
                                                      view['id']?.toString() ??
                                                      '',
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12.5)),
                                              selected:
                                                  desktopSelectedDynamicView?[
                                                              'id']
                                                          ?.toString() ==
                                                      view['id']?.toString(),
                                              selectedTileColor: Colors.white10,
                                              onTap: () =>
                                                  _selectDesktopDynamicView(
                                                      section, view),
                                            ))
                                        .toList(),
                                  );
                                }).toList(),
                              ),
                            )
                          else
                            ListTile(
                              leading: Icon(
                                  _iconForSection(
                                      section['id']?.toString() ?? '',
                                      section['icono']?.toString()),
                                  color: Colors.white70),
                              title: Text(_sectionTitle(section),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                              trailing: _sectionKind(section) ==
                                          'REGISTROS_LOCALES' &&
                                      pending > 0
                                  ? CircleAvatar(
                                      radius: 10,
                                      child: Text('$pending',
                                          style: const TextStyle(fontSize: 10)))
                                  : null,
                              onTap: _sectionTap(section),
                            ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        IconButton(
                          tooltip: 'Inicio',
                          onPressed: _openHomeFromBreadcrumb,
                          icon: const Icon(
                            Icons.home_outlined,
                            color: Colors.white,
                          ),
                        ),
                        for (final section in visibleSections)
                          IconButton(
                            tooltip: _sectionTitle(section),
                            onPressed: () {
                              final sectionId = _txt(section['id']);
                              final expandsTree =
                                  _sectionHasFormatModules(sectionId) ||
                                      _sectionUsesDynamicViews(section) ||
                                      _sectionKind(section) == 'REPORTES';
                              if (expandsTree) {
                                setState(() {
                                  desktopSidebarOpen = true;
                                  _expandedSectionId = sectionId;
                                  _clearDesktopSidebarCache();
                                });
                                _desktopSidebarOpenNotifier.value = true;
                                unawaited(_persistNavigation());
                                unawaited(_refreshIncrementallyOnEntry());
                              } else {
                                _sectionTap(section)();
                              }
                            },
                            icon: Icon(
                              _iconForSection(
                                _txt(section['id']),
                                section['icono']?.toString(),
                              ),
                              color: Colors.white70,
                            ),
                          ),
                      ],
                    ),
            ),
            const Divider(color: Colors.white24, height: 1),
            if (desktopSidebarOpen && profileName.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline,
                        color: Colors.white70, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        profileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            IconButton(
              tooltip: 'Salir',
              onPressed: logout,
              icon: const Icon(Icons.logout, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectMobileFormat(
      Map<String, dynamic> module, Map<String, dynamic> format) async {
    final specialRows = await local.where(
      'local_special_formats',
      'formato_id = ? and activo = 1',
      [format['id']],
    );
    if (!mounted) return;
    // Cerrar el Drawer mediante Scaffold evita que el PopScope interprete el
    // cierre como "volver" y restaure la vista anterior después del cambio.
    _closeMobileDrawer();
    _rememberNavigation();
    setState(() {
      _clearConsultantFocusState();
      desktopSelectedSection = null;
      desktopSelectedModule = Map<String, dynamic>.from(module);
      desktopSelectedFormat = Map<String, dynamic>.from(format);
      desktopSelectedReportModule = null;
      desktopSelectedReportView = null;
      mobileSelectedSpecial = specialRows.isNotEmpty
          ? Map<String, dynamic>.from(specialRows.first)
          : ((format['tabla_destino']?.toString() ?? '') == 'GT-TAREO_PERSONAL'
              ? <String, dynamic>{
                  'tipo_pantalla': 'tareo_personal',
                  'activo': 1
                }
              : null);
    });
    unawaited(_persistNavigation());
  }

  void _selectMobileSection(Map<String, dynamic> section) {
    _closeMobileDrawer();
    _rememberNavigation();
    setState(() {
      _clearConsultantFocusState();
      desktopSelectedSection = Map<String, dynamic>.from(section);
      desktopSelectedModule = null;
      desktopSelectedFormat = null;
      desktopSelectedReportModule = null;
      desktopSelectedReportView = null;
      desktopSelectedDynamicView = null;
      mobileSelectedSpecial = null;
    });
    unawaited(_persistNavigation());
  }

  void _selectMobileDynamicView(
      Map<String, dynamic> section, Map<String, dynamic> view) {
    _closeMobileDrawer();
    _rememberNavigation();
    setState(() {
      _clearConsultantFocusState();
      desktopSelectedSection = Map<String, dynamic>.from(section);
      desktopSelectedDynamicView = Map<String, dynamic>.from(view);
      desktopSelectedModule = null;
      desktopSelectedFormat = null;
      desktopSelectedReportModule = null;
      desktopSelectedReportView = null;
      mobileSelectedSpecial = null;
    });
    unawaited(_persistNavigation());
  }

  void _selectMobileReportView(
      Map<String, dynamic> module, Map<String, dynamic> view) {
    _closeMobileDrawer();
    _rememberNavigation();
    setState(() {
      _clearConsultantFocusState();
      desktopSelectedSection = null;
      desktopSelectedModule = null;
      desktopSelectedFormat = null;
      desktopSelectedReportModule = Map<String, dynamic>.from(module);
      desktopSelectedReportView = Map<String, dynamic>.from(view);
      desktopSelectedDynamicView = null;
      mobileSelectedSpecial = null;
    });
    unawaited(_persistNavigation());
  }

  Widget _logoHomePanel() {
    return _homeDashboard(desktop: false);
  }

  Widget _mobileSelectedContent() {
    if (busy) return const Center(child: CircularProgressIndicator());

    final toolContent = _workspaceToolContent(desktop: false);
    if (toolContent != null) return toolContent;

    final module = desktopSelectedModule;
    final format = desktopSelectedFormat;
    if (module != null && format != null) {
      final moduleId = module['id']?.toString() ?? '';
      final key = ValueKey(
        'mobile_${moduleId}_${format['id']}_${mobileSelectedSpecial?['id'] ?? ''}_'
        '${_consultantTableName ?? ''}_${_consultantRecordField ?? ''}_'
        '${_consultantRecordValue ?? ''}',
      );
      if (mobileSelectedSpecial != null) {
        return SpecialFormRouterPage(
          key: key,
          moduleId: moduleId,
          format: format,
          special: mobileSelectedSpecial!,
          onLocalChanged: _refreshPendingBadge,
          onSavedAndExit: _closeMobileFormatAfterSpecialSave,
        );
      }
      if (_asBool(format['tabla_visible_app'])) {
        return DesktopFormatRecordsPage(
          key: key,
          module: module,
          format: format,
          embedded: true,
          mobileMode: true,
          onLocalRecordsChanged: loadLocal,
          initialTableName: _consultantTableName,
          initialRecordField: _consultantRecordField,
          initialRecordValue: _consultantRecordValue,
        );
      }
      return FormRunnerPage(
        key: key,
        moduleId: moduleId,
        format: format,
        onBack: _restorePreviousNavigation,
      );
    }

    final reportModule = desktopSelectedReportModule;
    final reportView = desktopSelectedReportView;
    if (reportModule != null && reportView != null) {
      return ReportsPage(
        key:
            ValueKey('mobile_report_${reportModule['id']}_${reportView['id']}'),
        embedded: true,
        initialModuleId: reportModule['id']?.toString(),
        initialViewId: reportView['id']?.toString(),
        showRail: false,
      );
    }

    final section = desktopSelectedSection;
    if (section != null) {
      final id = section['id']?.toString() ?? '';
      final kind = _sectionKind(section);
      if (kind == 'REGISTROS_LOCALES') {
        return LocalRecordsPage(embedded: true, onChanged: loadLocal);
      }
      if (kind == 'REPORTES') {
        return const ReportsPage(embedded: true, showRail: false);
      }
      if (_sectionUsesDynamicViews(section)) {
        return DynamicViewsPage(
            section: section,
            view: desktopSelectedDynamicView,
            embedded: true,
            onPendingChanged: loadLocal);
      }
      if (!_sectionHasFormatModules(id)) {
        return GenericSectionPage(section: section, embedded: true);
      }
    }

    return _logoHomePanel();
  }

  Widget? _workspaceToolContent({required bool desktop}) {
    switch (_activeWorkspaceTool) {
      case _toolConsultant:
        return _consultantWorkspace(desktop: desktop);
      case _toolCreatorCreate:
      case _toolCreatorEdit:
        return ConfigurationAdminPage(
          key: ValueKey(_activeWorkspaceTool),
          embedded: true,
          initialMode: _activeWorkspaceTool == _toolCreatorEdit
              ? CreatorEntryMode.edit
              : CreatorEntryMode.create,
          onConfigurationChanged: _refreshAfterCreatorChange,
        );
      case _toolMetrics:
        return MetricsPage(
          key: const ValueKey('workspace-metrics'),
          embedded: true,
          initialSourceTable: _metricsInitialSourceTable,
        );
      case _toolAlerts:
      case _toolActions:
        return AlertsActionsPage(
          key: ValueKey(_activeWorkspaceTool),
          embedded: true,
          initialTab: _activeWorkspaceTool == _toolAlerts ? 0 : 1,
          onNavigate: _handleAlertNavigation,
        );
      default:
        return null;
    }
  }

  Widget _mobileMenuItems() {
    final visibleSections = sections
        .where((s) => _canSection(s['id']?.toString() ?? ''))
        .where((s) => _sectionKind(s) != 'REPORTES')
        .toList();

    if (visibleSections.isEmpty && _canSection('modulos')) {
      visibleSections.add({
        'id': 'modulos',
        'nombre': 'Formatos',
        'icono': 'apps',
        'orden': 1,
        'activo': 1,
      });
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ListTile(
          leading: const Icon(Icons.home_outlined),
          title: const Text(
            'Inicio',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          selected: _mobileIsHome(),
          onTap: () {
            _closeMobileDrawer();
            _openHomeFromBreadcrumb();
          },
        ),
        const Divider(height: 1),
        for (final section in visibleSections)
          if (_sectionHasFormatModules(_txt(section['id'])))
            ExpansionTile(
              key: ValueKey(
                  'mobile-section-${_txt(section['id'])}-${_expandedSectionId == _txt(section['id'])}'),
              initiallyExpanded: _expandedSectionId == _txt(section['id']),
              onExpansionChanged: (expanded) =>
                  _onSectionExpansionChanged(_txt(section['id']), expanded),
              leading: Icon(_iconForSection(
                  _txt(section['id']), section['icono']?.toString())),
              title: Text(_sectionTitle(section),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              children: _modulesForSection(_txt(section['id'])).map((module) {
                final moduleId = module['id']?.toString() ?? '';
                final formats =
                    formatsByModule[moduleId] ?? const <Map<String, dynamic>>[];
                return ExpansionTile(
                  tilePadding: const EdgeInsets.only(left: 32, right: 16),
                  leading: Icon(
                    configurationIconForName(module['icono']?.toString()),
                    size: 20,
                  ),
                  title: Text(module['nombre']?.toString() ?? moduleId),
                  // No mostrar id técnico del módulo en móvil.
                  subtitle: null,
                  children: formats.isEmpty
                      ? const [
                          ListTile(
                            dense: true,
                            contentPadding:
                                EdgeInsets.only(left: 72, right: 16),
                            title: Text('Sin formatos permitidos'),
                          ),
                        ]
                      : formats.map((format) {
                          return ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.only(left: 72, right: 16),
                            leading: const Icon(Icons.description_outlined,
                                size: 18),
                            title: Text(
                              format['nombre']?.toString() ??
                                  format['id']?.toString() ??
                                  '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // No mostrar id técnico del formato en móvil.
                            subtitle: null,
                            onTap: () => _selectMobileFormat(module, format),
                          );
                        }).toList(),
                );
              }).toList(),
            )
          else if (_sectionKind(section) == 'REPORTES')
            ExpansionTile(
              key: ValueKey(
                  'mobile-section-${_txt(section['id'])}-${_expandedSectionId == _txt(section['id'])}'),
              initiallyExpanded: _expandedSectionId == _txt(section['id']),
              onExpansionChanged: (expanded) =>
                  _onSectionExpansionChanged(_txt(section['id']), expanded),
              leading: Icon(
                  _iconForSection('reportes', section['icono']?.toString())),
              title: Text(_sectionTitle(section),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              children: reportModules.map((module) {
                final views = _reportViewsForModule(module);
                return ExpansionTile(
                  tilePadding: const EdgeInsets.only(left: 32, right: 16),
                  leading: const Icon(Icons.folder_copy_outlined, size: 20),
                  title: Text(module['nombre']?.toString() ??
                      module['id']?.toString() ??
                      ''),
                  children: views.isEmpty
                      ? const [
                          ListTile(
                            dense: true,
                            contentPadding:
                                EdgeInsets.only(left: 72, right: 16),
                            title: Text('Sin vistas permitidas'),
                          ),
                        ]
                      : views.map((view) {
                          return ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.only(left: 72, right: 16),
                            leading: const Icon(Icons.insert_chart_outlined,
                                size: 18),
                            title: Text(
                              view['nombre_vista']?.toString() ??
                                  view['id']?.toString() ??
                                  '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _selectMobileReportView(module, view),
                          );
                        }).toList(),
                );
              }).toList(),
            )
          else if (_sectionUsesDynamicViews(section))
            ExpansionTile(
              key: ValueKey(
                  'mobile-section-${_txt(section['id'])}-${_expandedSectionId == _txt(section['id'])}'),
              initiallyExpanded: _expandedSectionId == _txt(section['id']),
              onExpansionChanged: (expanded) =>
                  _onSectionExpansionChanged(_txt(section['id']), expanded),
              leading: Icon(_iconForSection(section['id']?.toString() ?? '',
                  section['icono']?.toString())),
              title: Text(_sectionTitle(section),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              children: () {
                final grouped = _dynamicViewsGroupedByModule(
                    section['id']?.toString() ?? '');
                if (grouped.isEmpty) {
                  return const <Widget>[
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.only(left: 46, right: 16),
                      title: Text('Sin vistas configuradas/actualizadas'),
                    ),
                  ];
                }
                return grouped.entries
                    .map((entry) => ExpansionTile(
                          tilePadding:
                              const EdgeInsets.only(left: 32, right: 16),
                          leading:
                              const Icon(Icons.folder_open_outlined, size: 20),
                          title: Text(entry.key),
                          children: entry.value
                              .map((view) => ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.only(
                                        left: 72, right: 16),
                                    leading: const Icon(
                                        Icons.view_list_outlined,
                                        size: 18),
                                    title: Text(
                                        view['nombre_vista']?.toString() ??
                                            view['id']?.toString() ??
                                            '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    onTap: () =>
                                        _selectMobileDynamicView(section, view),
                                  ))
                              .toList(),
                        ))
                    .toList();
              }(),
            )
          else
            ListTile(
              leading: Icon(_iconForSection(section['id']?.toString() ?? '',
                  section['icono']?.toString())),
              title: Text(_sectionTitle(section),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing:
                  _sectionKind(section) == 'REGISTROS_LOCALES' && pending > 0
                      ? CircleAvatar(
                          radius: 10,
                          child: Text('$pending',
                              style: const TextStyle(fontSize: 10)))
                      : null,
              onTap: () => _selectMobileSection(section),
            ),
      ],
    );
  }

  // ignore: unused_element
  Widget _mobileModulesList() {
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: modules.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final m = modules[index];
        return Card(
          child: ListTile(
            dense: true,
            leading: Icon(configurationIconForName(m['icono']?.toString())),
            title: Text('${m['nombre']}',
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => FormatsPage(module: m)),
            ).then((_) => loadLocal()),
          ),
        );
      },
    );
  }

  Widget _desktopContentActions() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 54, maxHeight: 54),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_usesImmersiveWorkspace)
              IconButton(
                onPressed: _openHomeFromBreadcrumb,
                icon: const Icon(Icons.home_outlined),
                tooltip: 'Inicio',
              ),
            if (_canClearConsultant)
              TextButton.icon(
                onPressed: _consultantBusy ? null : _clearConsultantAnswer,
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                label: const Text('Limpiar'),
              ),
            IconButton(
              onPressed: busy ? null : download,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar datos',
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  onPressed: busy ? null : syncPending,
                  tooltip: 'Sincronizar',
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: busy
                        ? const SizedBox(
                            key: ValueKey('desktop-syncing'),
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            online ? Icons.sync : Icons.sync_problem_outlined,
                            key: ValueKey(
                              online ? 'desktop-online' : 'desktop-offline',
                            ),
                          ),
                  ),
                ),
                if (pending > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: CircleAvatar(
                      radius: 9,
                      child: Text(
                        '$pending',
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  ),
              ],
            ),
            IconButton(
              onPressed: busy ? null : () => _openOnboarding(replay: true),
              icon: const Icon(Icons.help_outline),
              tooltip: 'Guía de uso',
            ),
          ],
        ),
      ),
    );
  }

  Widget _desktopTopBar({required bool isHome}) {
    return Container(
      height: 54,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFD9E5EA))),
      ),
      child: Row(
        children: [
          Expanded(
            child: isHome
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _workspaceTitle(compact: true),
                    ),
                  ),
          ),
          _desktopContentActions(),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktopLayout = isWideDesktopLayout(context);
    final isHome = _mobileIsHome();
    final content = busy
        ? Center(
            child: BrandedLoading(
              progress: busyProgress > 0 ? busyProgress : 0.18,
              message: busyMessage ?? 'Procesando...',
            ),
          )
        : desktopLayout
            ? _desktopSelectedContentCached()
            : _mobileSelectedContent();

    final appBar = AppBar(
      titleSpacing: 0,
      title: Text(
        isHome ? 'ZUMAC' : _mobileAppBarTitle(),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        if (_usesImmersiveWorkspace)
          IconButton(
            onPressed: _openHomeFromBreadcrumb,
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Inicio',
          ),
        IconButton(
            onPressed: busy ? null : download,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar datos'),
        Stack(
          alignment: Alignment.topRight,
          children: [
            IconButton(
                onPressed: busy ? null : syncPending,
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: busy
                      ? const SizedBox(
                          key: ValueKey('syncing'),
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          online ? Icons.sync : Icons.sync_problem_outlined,
                          key: ValueKey(online ? 'online' : 'offline'),
                        ),
                ),
                tooltip: 'Sincronizar'),
            if (pending > 0)
              CircleAvatar(
                  radius: 10,
                  child:
                      Text('$pending', style: const TextStyle(fontSize: 11))),
          ],
        ),
        const SizedBox(width: 12),
        IconButton(
          onPressed: busy ? null : () => _openOnboarding(replay: true),
          icon: const Icon(Icons.help_outline),
          tooltip: 'Guía de uso',
        ),
      ],
    );

    if (isWideDesktopLayout(context)) {
      return Scaffold(
        key: scaffoldKey,
        body: Row(
          children: [
            if (!_usesImmersiveWorkspace)
              ValueListenableBuilder<bool>(
                valueListenable: _desktopSidebarOpenNotifier,
                builder: (context, _, __) => _desktopSidebarCached(),
              ),
            Expanded(
              child: Column(
                children: [
                  _desktopTopBar(isHome: isHome),
                  Expanded(
                    child: RepaintBoundary(
                      child: _animatedContent(content),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final mobileScaffold = Scaffold(
      key: scaffoldKey,
      drawer: _usesImmersiveWorkspace
          ? null
          : Drawer(
              child: SafeArea(
                child: Column(
                  children: [
                    ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/images/logo_app.png',
                          width: 38,
                          height: 38,
                          cacheWidth: 114,
                          cacheHeight: 114,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                      title: const Text('ZUMAC',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        profileName.isEmpty
                            ? 'Menú principal'
                            : 'Menú principal\n$profileName',
                      ),
                    ),
                    const Divider(),
                    Expanded(child: _mobileMenuItems()),
                    const Divider(),
                    _drawerItem(Icons.logout, 'Salir', logout),
                  ],
                ),
              ),
            ),
      appBar: appBar,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _mobileTitleBar(),
          Expanded(child: _animatedContent(content)),
        ],
      ),
    );
    return PopScope(
      canPop: _mobileIsHome(),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (scaffoldKey.currentState?.isDrawerOpen == true) {
          _closeMobileDrawer();
          return;
        }
        if (!_mobileIsHome()) _restorePreviousNavigation();
      },
      child: mobileScaffold,
    );
  }
}
