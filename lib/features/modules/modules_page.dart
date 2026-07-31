import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/configuration_icon_catalog.dart';
import '../../core/widgets/responsive_layout.dart';

import '../../core/services/app_experience_service.dart';
import '../../core/services/local_db.dart';
import '../../core/services/sync_service.dart';
import '../../core/services/zumac_consultant_service.dart';
import '../../core/widgets/branded_loading.dart';
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
import '../onboarding/onboarding_page.dart';
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

class _ModulesPageState extends State<ModulesPage> {
  final local = LocalDb.instance;
  final sync = SyncService();
  final experience = AppExperienceService();
  final consultant = ZumacConsultantService();
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _consultantController = TextEditingController();

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
  bool online = true;
  DateTime? lastSyncAt;
  Map<String, dynamic> restoredNavigation = {};
  final List<Map<String, dynamic>> navigationHistory = [];
  bool _consultantBusy = false;
  ZumacConsultantResult? _consultantResult;
  String? _consultantTableName;
  String? _consultantRecordField;
  String? _consultantRecordValue;

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
    _consultantController.dispose();
    _desktopSidebarOpenNotifier.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_restoreExperience());
    loadLocal();
    unawaited(_loadConfigurationAccess());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeOpenOnboarding());
    });
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
    if (kind == 'section') {
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
      if (!mounted) return;
      setState(() =>
          canManageConfiguration = contextData['puede_gestionar'] == true);
    } catch (_) {
      // El constructor requiere conexión. La navegación offline principal no
      // debe bloquearse si Supabase no responde.
      if (mounted && canManageConfiguration) {
        setState(() => canManageConfiguration = false);
      }
    }
  }

  Future<void> _openConfigurationAdmin({
    CreatorEntryMode mode = CreatorEntryMode.create,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ConfigurationAdminPage(initialMode: mode),
      ),
    );
    if (!mounted) return;
    await _loadConfigurationAccess();
  }

  Future<void> _askConsultant() async {
    final question = _consultantController.text.trim();
    if (question.isEmpty || _consultantBusy) return;
    setState(() {
      _clearDesktopContentCache();
      _consultantBusy = true;
    });
    try {
      final result = await consultant.ask(question);
      if (!mounted) return;
      setState(() {
        _clearDesktopContentCache();
        _consultantResult = result;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo completar la consulta: $error')),
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
    setState(() {
      _clearDesktopContentCache();
      _consultantResult = null;
      _consultantController.clear();
    });
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
    // Regla anti-bloqueo: Formatos siempre queda visible si no hay permisos de
    // secciones descargados. Así el usuario puede volver a actualizar matrices.
    if (allowedSections.isEmpty) return sectionId == 'modulos';
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

    await Future<void>.delayed(const Duration(milliseconds: 1));
    final rawPermissions = await local.getAll('local_permissions');
    final rawSectionPerms = await local.getAll('local_section_permissions');
    final localSections =
        await local.getAll('local_sections', orderBy: 'orden');
    final rawProfileRows = await local.getAll('local_profile');
    final activeEmpresaId = await LocalSession().cachedEmpresaId();
    bool belongsToActiveEmpresa(Map<String, dynamic> row) {
      final rowEmpresaId = row['empresa_id']?.toString().trim() ?? '';
      return rowEmpresaId.isEmpty || rowEmpresaId == activeEmpresaId;
    }

    // Seguridad visual/local: nunca renderizar el menú con permisos cacheados
    // de otro usuario. La BD local es un cache de trabajo, por eso al cambiar
    // de cuenta puede quedar información anterior hasta que se actualicen
    // matrices. Se filtra por el usuario activo antes de construir el sidebar.
    final authUserId = Supabase.instance.client.auth.currentUser?.id;
    final cachedUserId = await LocalSession().cachedUserId();
    final activeUserId = (authUserId ?? cachedUserId ?? '').trim();

    await Future<void>.delayed(const Duration(milliseconds: 1));
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

    List<Map<String, dynamic>> moduleRows = [];
    if (allowedModuleIds.isNotEmpty) {
      final placeholders = List.filled(allowedModuleIds.length, '?').join(',');
      moduleRows = await local.where(
        'local_modules',
        'id in ($placeholders) and activo = 1 and empresa_id = ?',
        [...allowedModuleIds, activeEmpresaId],
        orderBy: 'orden',
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 1));
    final moduleFormats = <String, List<Map<String, dynamic>>>{};
    for (final moduleId in allowedModuleIds) {
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
      final candidates = await local.where(
        'local_formats',
        'modulo_id = ? and activo = 1 and empresa_id = ?',
        [moduleId, activeEmpresaId],
        orderBy: 'orden',
      );
      moduleFormats[moduleId] = candidates.where((format) {
        return allowedFormatKeys.contains(_id(format['id'])) ||
            allowedFormatKeys.contains(_id(format['tabla_destino']));
      }).toList();
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    // Rendimiento/offline: el sidebar usa el cache local de vistas dinámicas.
    // Los cambios de Supabase llegan al presionar Actualizar datos; evitamos consultar
    // internet cada vez que se reconstruye el menú, porque eso vuelve lenta la navegación.
    final remoteDynamicViews = await _loadDynamicViewsForSidebar();

    await Future<void>.delayed(const Duration(milliseconds: 1));
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

    final p = await local.pendingCount();
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
      if (mounted)
        setState(() {
          busyProgress = 0.97;
          busyMessage = 'Aplicando cambios locales...';
        });
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
    if (name.isNotEmpty) return name;
    if (id == 'modulos') return 'Formatos';
    if (id == 'registros_locales') return 'Registros locales';
    if (id == 'reportes') return 'Reportes';
    return id;
  }

  String _mobileAppBarTitle() {
    // En móvil el título completo se muestra debajo de la barra superior para no
    // competir con los iconos de actualizar app / datos / sincronizar.
    return '';
  }

  bool _mobileIsHome() {
    return desktopSelectedModule == null &&
        desktopSelectedFormat == null &&
        desktopSelectedReportModule == null &&
        desktopSelectedReportView == null &&
        desktopSelectedSection == null &&
        desktopSelectedDynamicView == null &&
        mobileSelectedSpecial == null;
  }

  String _mobilePageTitle() {
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
    if (desktopSelectedSection != null)
      return _sectionTitle(desktopSelectedSection!);
    return 'ZUMAC';
  }

  Widget _mobileTitleBar() {
    if (_mobileIsHome()) return const SizedBox.shrink();
    // Cuando se abre un formato en móvil, FormRunnerPage ya trae su propio AppBar
    // con flecha y título. Evita el segundo título fijo que quitaba espacio útil.
    if (desktopSelectedFormat != null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver a la vista anterior',
            icon: const Icon(Icons.arrow_back),
            onPressed: _restorePreviousNavigation,
          ),
          Expanded(
            child: Text(
              _mobilePageTitle(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
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

  void _selectDesktopModule(Map<String, dynamic> module) {
    _rememberNavigation();
    setState(() {
      _clearDesktopContentCache();
      _clearDesktopSidebarCache();
      desktopSelectedSection = null;
      desktopSelectedModule = Map<String, dynamic>.from(module);
      desktopSelectedFormat = null;
      desktopSelectedReportModule = null;
      desktopSelectedReportView = null;
      desktopSelectedDynamicView = null;
      mobileSelectedSpecial = null;
    });
    unawaited(_persistNavigation());
  }

  Map<String, dynamic> _formatsSectionForModule(Map<String, dynamic>? module) {
    final sectionId = _txt(module?['seccion']);
    final existing = sections.cast<Map<String, dynamic>?>().firstWhere(
          (row) => _sameId(row?['id'], sectionId),
          orElse: () => null,
        );
    return existing ??
        <String, dynamic>{
          'id': sectionId.isEmpty ? 'modulos' : sectionId,
          'nombre': 'Formatos',
          'icono': 'apps',
        };
  }

  void _openFormatsFromBreadcrumb() {
    _selectDesktopSection(_formatsSectionForModule(desktopSelectedModule));
    if (!desktopSidebarOpen) {
      setState(() {
        desktopSidebarOpen = true;
        _clearDesktopSidebarCache();
      });
      _desktopSidebarOpenNotifier.value = true;
      unawaited(_persistNavigation());
    }
  }

  List<({String label, VoidCallback? onTap})> _breadcrumbItems() {
    final items = <({String label, VoidCallback? onTap})>[
      (label: 'Agroexportación', onTap: _openHomeFromBreadcrumb),
    ];
    final module = desktopSelectedModule;
    final format = desktopSelectedFormat;
    if (module != null) {
      final sectionId = _txt(module['seccion']);
      final section = sections.cast<Map<String, dynamic>?>().firstWhere(
            (row) => _sameId(row?['id'], sectionId),
            orElse: () => null,
          );
      final sectionName = section == null ? '' : _sectionTitle(section);
      if (sectionName.isNotEmpty) {
        items.add((label: sectionName, onTap: _openFormatsFromBreadcrumb));
      }
      items.add((
        label: _txt(module['nombre']).isEmpty
            ? _txt(module['id'])
            : _txt(module['nombre']),
        onTap: () => _selectDesktopModule(module),
      ));
      if (format != null) {
        items.add((
          label: _txt(format['nombre']).isEmpty
              ? _txt(format['id'])
              : _txt(format['nombre']),
          onTap: null,
        ));
      }
    } else if (desktopSelectedSection != null) {
      items.add((
        label: _sectionTitle(desktopSelectedSection!),
        onTap: desktopSelectedDynamicView == null
            ? null
            : () => _selectDesktopSection(desktopSelectedSection!),
      ));
      if (desktopSelectedDynamicView != null) {
        items.add((
          label: _txt(desktopSelectedDynamicView!['nombre']),
          onTap: null,
        ));
      }
    } else if (desktopSelectedReportView != null) {
      items.add((
        label: 'Reportes',
        onTap: () => _selectDesktopSection({
              'id': 'reportes',
              'nombre': 'Reportes',
              'icono': 'bar_chart',
            }),
      ));
      items.add((
        label: _txt(desktopSelectedReportView!['nombre_vista']),
        onTap: null,
      ));
    }
    return items;
  }

  Widget _breadcrumbBar() {
    if (_mobileIsHome()) return const SizedBox.shrink();
    final items = _breadcrumbItems();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFFEAF3F6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    Icons.chevron_right,
                    size: 15,
                    color: Color(0xFF6A8290),
                  ),
                ),
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: items[index].onTap,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    items[index].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: items[index].onTap == null
                          ? const Color(0xFF17324D)
                          : const Color(0xFF176B87),
                      fontSize: 12,
                      fontWeight: items[index].onTap == null
                          ? FontWeight.w700
                          : FontWeight.w600,
                      decoration: items[index].onTap == null
                          ? TextDecoration.none
                          : TextDecoration.underline,
                      decorationColor: const Color(0xFF176B87),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
    if (desktopSelectedSection?['id']?.toString() ==
            section['id']?.toString() &&
        desktopSelectedModule == null &&
        desktopSelectedFormat == null &&
        desktopSelectedReportModule == null &&
        desktopSelectedReportView == null &&
        desktopSelectedDynamicView == null) return;
    _rememberNavigation();
    setState(() {
      _clearDesktopContentCache();
      _clearDesktopSidebarCache();
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

  Widget _desktopPanelShell({required String title, required Widget child}) {
    // En Windows el panel derecho debe mostrar directamente el contenido seleccionado.
    // El título superior fijo se elimina para no duplicar el nombre de la vista.
    return child;
  }

  void _selectDesktopFormat(
      Map<String, dynamic> module, Map<String, dynamic> format) {
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
        final logoSize =
            (constraints.maxWidth * (wide ? 0.14 : 0.34)).clamp(132.0, 220.0);
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
                        _homeQuickActions(
                          desktop: desktop,
                        ),
                        SizedBox(height: compact ? 6 : 10),
                        _welcomeHomePanel(
                          firstName: firstName,
                          wide: wide,
                          logoSize: logoSize,
                          desktop: desktop,
                        ),
                        SizedBox(height: compact ? 16 : 22),
                        _consultantPanel(compact: compact),
                        if (_consultantResult != null) ...[
                          const SizedBox(height: 14),
                          _consultantAnswerPanel(),
                        ],
                        if (canManageConfiguration) ...[
                          const SizedBox(height: 18),
                          _creatorHomePanel(compact: compact),
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
              Container(
                width: compact ? 38 : 44,
                height: compact ? 38 : 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2F2F5),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.auto_awesome_outlined,
                  color: Color(0xFF176B87),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Consultor Zumac',
                      style: TextStyle(
                        color: Color(0xFF17324D),
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Pregunta, compara fechas y cruza información entre formatos.',
                      style: TextStyle(
                        color: Color(0xFF60758A),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (_consultantResult != null)
                IconButton(
                  tooltip: 'Nueva consulta',
                  onPressed: _clearConsultantAnswer,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _consultantController,
            enabled: !_consultantBusy,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _askConsultant(),
            decoration: InputDecoration(
              hintText: compact
                  ? 'Ej.: ¿Hay pH mayores a 6 hoy?'
                  : 'Escribe una pregunta, por ejemplo: ¿Hay pH mayores a 6 hoy?',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _consultantBusy
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Consultar',
                      onPressed: _askConsultant,
                      icon: const Icon(Icons.arrow_forward),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.science_outlined, size: 17),
                label: const Text('pH mayores a 6 hoy'),
                onPressed: _consultantBusy
                    ? null
                    : () {
                        _consultantController.text = '¿Hay pH mayores a 6 hoy?';
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

  Widget _consultantAnswerPanel() {
    final result = _consultantResult!;
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
          if (result.reportTables.isNotEmpty) ...[
            const SizedBox(height: 18),
            for (final report in result.reportTables) ...[
              _consultantReportTable(report),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }

  Widget _consultantReportTable(ZumacConsultantReportTable report) {
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.table_chart_outlined,
                  size: 20,
                  color: Color(0xFF176B87),
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
                if (report.canOpen)
                  TextButton.icon(
                    onPressed: () => _openConsultantReport(report),
                    icon: const Icon(Icons.open_in_new, size: 17),
                    label: const Text('Abrir registros'),
                  ),
              ],
            ),
          ),
          if (report.columns.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                'Los registros encontrados solo contienen identificadores técnicos.',
                style: TextStyle(color: Color(0xFF60758A)),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 4),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFF1F7F9),
                ),
                headingTextStyle: const TextStyle(
                  color: Color(0xFF17324D),
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
                dataTextStyle: const TextStyle(
                  color: Color(0xFF304A60),
                  fontSize: 12.5,
                ),
                columnSpacing: 24,
                horizontalMargin: 16,
                columns: [
                  for (final column in report.columns)
                    DataColumn(label: Text(column.label)),
                ],
                rows: [
                  for (final row in report.rows)
                    DataRow(
                      cells: [
                        for (final column in report.columns)
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 260),
                              child: SelectableText(
                                row[column.key] ?? '—',
                                maxLines: 3,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
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

  Widget _creatorHomePanel({required bool compact}) {
    Widget creatorCard({
      required IconData icon,
      required String title,
      required String subtitle,
      required CreatorEntryMode mode,
      required bool filled,
    }) {
      return SizedBox(
        width: compact ? double.infinity : 310,
        height: compact ? 102 : 96,
        child: Material(
          color: filled ? const Color(0xFF176B87) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openConfigurationAdmin(mode: mode),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: filled
                      ? const Color(0xFF176B87)
                      : const Color(0xFFD4E3E8),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: filled ? Colors.white : const Color(0xFF176B87),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color:
                                filled ? Colors.white : const Color(0xFF17324D),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: filled
                                ? Colors.white70
                                : const Color(0xFF60758A),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: filled ? Colors.white70 : const Color(0xFF60758A),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Zumac Creator',
          style: TextStyle(
            color: Color(0xFF17324D),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 9),
        if (compact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              creatorCard(
                icon: Icons.edit_note_outlined,
                title: 'Editar objetos',
                subtitle: 'Revisar, editar u ocultar objetos existentes',
                mode: CreatorEntryMode.edit,
                filled: false,
              ),
              const SizedBox(height: 9),
              creatorCard(
                icon: Icons.add_circle_outline,
                title: '+ Objetos',
                subtitle: 'Crear secciones, módulos y formatos',
                mode: CreatorEntryMode.create,
                filled: true,
              ),
            ],
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              creatorCard(
                icon: Icons.edit_note_outlined,
                title: 'Editar objetos',
                subtitle: 'Revisar, editar u ocultar objetos existentes',
                mode: CreatorEntryMode.edit,
                filled: false,
              ),
              creatorCard(
                icon: Icons.add_circle_outline,
                title: '+ Objetos',
                subtitle: 'Crear secciones, módulos y formatos',
                mode: CreatorEntryMode.create,
                filled: true,
              ),
            ],
          ),
      ],
    );
  }

  Widget _welcomeHomePanel({
    required String firstName,
    required bool wide,
    required double logoSize,
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
          'Todo está listo para que sigas gestionando tu trabajo en Zumac.',
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
    final logo = Container(
      width: logoSize,
      height: logoSize,
      padding: EdgeInsets.all(wide ? 15 : 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCE7EC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1517324D),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Image.asset(
        'assets/images/logo_bienvenida.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: 'Logo de Zumac',
      ),
    );
    return Container(
      padding: EdgeInsets.all(wide ? 24 : 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x80D5E5EA)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          logo,
          SizedBox(height: wide ? 20 : 16),
          message,
        ],
      ),
    );
  }

  String _desktopContentSignature() {
    if (busy) return 'busy';
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
    if (desktopSelectedSection != null)
      return 'section:${desktopSelectedSection!['id']}';
    final result = _consultantResult;
    return 'home:${_consultantBusy ? 1 : 0}:'
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
                  : Column(
                      children: [
                        IconButton(
                          tooltip: 'Inicio',
                          onPressed: _openHomeFromBreadcrumb,
                          icon: const Icon(
                            Icons.home_outlined,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Formatos',
                          onPressed: () {
                            desktopSidebarOpen = true;
                            _clearDesktopSidebarCache();
                            _desktopSidebarOpenNotifier.value = true;
                            unawaited(_persistNavigation());
                          },
                          icon: const Icon(Icons.apps, color: Colors.white),
                        ),
                        IconButton(
                          tooltip: 'Registros locales',
                          onPressed: () => _selectDesktopSection({
                            'id': 'registros_locales',
                            'nombre': 'Registros locales',
                            'icono': 'storage'
                          }),
                          icon:
                              const Icon(Icons.storage, color: Colors.white70),
                        ),
                        IconButton(
                          tooltip: 'Reportes',
                          onPressed: () => _selectDesktopSection({
                            'id': 'reportes',
                            'nombre': 'Reportes',
                            'icono': 'bar_chart'
                          }),
                          icon: const Icon(Icons.bar_chart,
                              color: Colors.white70),
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
      if (kind == 'REGISTROS_LOCALES')
        return LocalRecordsPage(embedded: true, onChanged: loadLocal);
      if (kind == 'REPORTES')
        return const ReportsPage(embedded: true, showRail: false);
      if (_sectionUsesDynamicViews(section))
        return DynamicViewsPage(
            section: section,
            view: desktopSelectedDynamicView,
            embedded: true,
            onPendingChanged: loadLocal);
      if (!_sectionHasFormatModules(id))
        return GenericSectionPage(section: section, embedded: true);
    }

    return _logoHomePanel();
  }

  Widget _mobileMenuItems() {
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
    return SizedBox(
      height: 54,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
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
      title: desktopLayout ? const SizedBox.shrink() : const SizedBox.shrink(),
      actions: [
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
            ValueListenableBuilder<bool>(
              valueListenable: _desktopSidebarOpenNotifier,
              builder: (context, _, __) => _desktopSidebarCached(),
            ),
            Expanded(
              child: Column(
                children: [
                  if (!isHome) _desktopContentActions(),
                  _breadcrumbBar(),
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
      drawer: Drawer(
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
      appBar: isHome ? null : appBar,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _breadcrumbBar(),
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
