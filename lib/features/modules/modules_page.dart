import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/local_db.dart';
import '../../core/services/sync_service.dart';
import '../../core/widgets/branded_loading.dart';
import '../../core/services/local_session.dart';
import '../../core/services/app_update_service.dart';
import '../auth/login_page.dart';
import '../../core/platform/app_platform.dart';
import '../../config/app_version.dart';
import '../formats/desktop_format_records_page.dart';
import '../formats/formats_page.dart';
import '../form_runner/form_runner_page.dart';
import '../form_runner/special_form_pages.dart';
import '../local_records/local_records_page.dart';
import '../reports/reports_page.dart';
import 'generic_section_page.dart';
import 'dynamic_views_page.dart';

class ModulesPage extends StatefulWidget {
  const ModulesPage({super.key});

  @override
  State<ModulesPage> createState() => _ModulesPageState();
}

class _ModulesPageState extends State<ModulesPage> {
  final local = LocalDb.instance;
  final sync = SyncService();

  List<Map<String, dynamic>> modules = [];
  List<Map<String, dynamic>> sections = [];
  Map<String, List<Map<String, dynamic>>> formatsByModule = {};
  Set<String> allowedSections = {};
  int pending = 0;
  bool busy = false;
  String? busyMessage;
  double busyProgress = 0;
  bool localLoaded = false;
  bool desktopSidebarOpen = true;
  final ValueNotifier<bool> _desktopSidebarOpenNotifier = ValueNotifier<bool>(true);
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


  @override
  void dispose() {
    _desktopSidebarOpenNotifier.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    loadLocal();
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
    return s == 'true' || s == 't' || s == '1' || s == 'si' || s == 'sí' || s == 's' || s == 'yes';
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
    final next = expanded ? sectionId : (_expandedSectionId == sectionId ? null : _expandedSectionId);
    if (next == _expandedSectionId) return;
    setState(() {
      _expandedSectionId = next;
      _clearDesktopSidebarCache();
    });
  }

  List<Map<String, dynamic>> _modulesForSection(String sectionId) {
    return modules.where((m) {
      final configured = _txt(m['seccion']);
      return configured.isNotEmpty && _sameId(configured, sectionId);
    }).toList();
  }

  bool _sectionHasFormatModules(String sectionId) => _modulesForSection(sectionId).isNotEmpty;



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
        .where((v) => _sameId(v['seccion'], sectionId) && _asBool(v['activo'], fallback: true))
        .toList()
      ..sort((a, b) => _asInt(a['orden']).compareTo(_asInt(b['orden'])));
  }

  Map<String, List<Map<String, dynamic>>> _dynamicViewsGroupedByModule(String sectionId) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final view in _dynamicViewsForSection(sectionId)) {
      final module = _txt(view['modulo']).isEmpty ? 'General' : _txt(view['modulo']);
      grouped.putIfAbsent(module, () => <Map<String, dynamic>>[]).add(view);
    }
    return grouped;
  }

  bool _sectionHasDynamicViews(String sectionId) => _dynamicViewsForSection(sectionId).isNotEmpty;

  List<Map<String, dynamic>> _reportViewsForModule(Map<String, dynamic> module) {
    final moduleId = _txt(module['id']);
    return reportViews
        .where((v) => _txt(v['id_modulo_reporte']) == moduleId && _canReportView(module, v))
        .toList()
      ..sort((a, b) => _asInt(a['orden']).compareTo(_asInt(b['orden'])));
  }

  Map<String, dynamic> _dynamicViewToLocalRow(Map<String, dynamic> e) {
    return {
      'id': e['id']?.toString() ?? '${e['seccion']}_${e['modulo']}_${e['nombre_vista']}',
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
      'requiere_todos_campos': _asBool(e['requiere_todos_campos']) ? 1 : 0,
      'activo': _asBool(e['activo'], fallback: true) ? 1 : 0,
      'orden': _asInt(e['orden']),
      'payload_json': jsonEncode(e),
    };
  }

  Future<List<Map<String, dynamic>>> _loadDynamicViewsForSidebar() async {
    final rows = await local.getAll('local_dynamic_views', orderBy: 'orden');
    final hasPendingViews = rows.any((v) =>
        _sameId(v['seccion'], 'registros_pendientes') &&
        _asBool(v['activo'], fallback: true));

    // Defensa específica: si el cache local no trae vistas de Registros Pendientes,
    // consultamos la matriz real. Esto evita que el menú quede como botón plano
    // o como expansión vacía cuando el incremental no trajo esa matriz.
    if (!hasPendingViews && await sync.hasInternet()) {
      try {
        final remoteRows = await Supabase.instance.client
            .from('MATRIZ_VISTAS_DINAMICAS_APPGT')
            .select()
            .eq('seccion', 'registros_pendientes')
            .order('orden')
            .timeout(const Duration(seconds: 2));

        final mapped = List<Map<String, dynamic>>.from(remoteRows)
            .map(_dynamicViewToLocalRow)
            .where((v) => _asBool(v['activo'], fallback: true))
            .toList();

        if (mapped.isNotEmpty) {
          await local.upsertTable('local_dynamic_views', mapped);
          final merged = <String, Map<String, dynamic>>{};
          for (final r in rows) {
            merged[_txt(r['id'])] = r;
          }
          for (final r in mapped) {
            merged[_txt(r['id'])] = r;
          }
          return merged.values.toList()
            ..sort((a, b) => _asInt(a['orden']).compareTo(_asInt(b['orden'])));
        }
      } catch (_) {
        // Offline o RLS: usamos el cache local existente.
      }
    }

    return rows;
  }

  Future<void> loadLocal() async {
    if (mounted && !localLoaded) setState(() => busy = true);

    await Future<void>.delayed(const Duration(milliseconds: 1));
    final rawPermissions = await local.getAll('local_permissions');
    final rawSectionPerms = await local.getAll('local_section_permissions');
    final localSections = await local.getAll('local_sections', orderBy: 'orden');
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
          .where((e) => _asBool(e['can_view']) && _sameId(e['modulo'], moduleId))
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

    await _loadReportNavigation();

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
        final sectionMatches = _permissionIncludesSection(permission, sectionId);
        final moduleMatches = permModule.isEmpty || _sameId(permModule, moduleId);
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
      profileName = profileRows.isEmpty ? '' : (profileRows.first['nombres']?.toString().trim() ?? '');
      localLoaded = true;
      busy = false;
    });
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
        onProgress: (message) {
          if (mounted) {
            setState(() {
              busyMessage = message;
              busyProgress = (busyProgress + 0.045).clamp(0.0, 0.94).toDouble();
            });
          }
        },
      );
      if (mounted) setState(() { busyProgress = 0.97; busyMessage = 'Aplicando cambios locales...'; });
      await loadLocal();
      if (!mounted) return;
      if (mounted) setState(() => busyProgress = 1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datos actualizados.')),
      );
    } catch (e) {
      if (!mounted) return;
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


  Future<void> checkAppUpdate() async {
    final action = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(80, 80, 0, 0),
      items: const [
        PopupMenuItem(value: 'update_app', child: Text('Actualizar app')),
      ],
    );
    if (action != 'update_app') return;

    setState(() => busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 48));
    try {
      final result = await AppUpdateService().checkAndDownloadLatest();
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(result.hasUpdate ? 'Actualización descargada' : 'Actualizar app'),
          content: Text(result.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo verificar/descargar la actualización: $e')),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> syncPending() async {
    setState(() => busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 48));
    try {
      final count = await sync.syncPending();
      await loadLocal();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Registros sincronizados: $count')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sync.friendlyError(e))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> logout() async {
    await Supabase.instance.client.auth.signOut();
    await LocalSession().clearActiveSession();
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  Widget _drawerItem(IconData icon, String title, VoidCallback onTap, {String? badge}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: badge == null ? null : CircleAvatar(radius: 11, child: Text(badge, style: const TextStyle(fontSize: 11))),
      onTap: onTap,
    );
  }

  IconData _iconForSection(String sectionId, [String? iconName]) {
    switch ((iconName ?? sectionId).trim().toLowerCase()) {
      case 'apps':
      case 'app':
      case 'modulos':
        return Icons.apps;
      case 'storage':
      case 'database':
      case 'registros_locales':
        return Icons.storage;
      case 'bar_chart':
      case 'analytics':
      case 'reportes':
        return Icons.bar_chart;
      case 'people':
      case 'users':
      case 'usuarios':
        return Icons.people_alt;
      case 'pending':
      case 'pending_actions':
      case 'warning':
      case 'alert':
      case 'registros_pendientes':
        return Icons.pending_actions_outlined;
      case 'home':
      case 'inicio':
      case 'inicio_gt':
        return Icons.home_outlined;
      case 'assignment':
      case 'form':
      case 'formatos':
        return Icons.assignment_outlined;
      case 'checklist':
        return Icons.checklist_outlined;
      case 'fact_check':
        return Icons.fact_check_outlined;
      case 'verified':
        return Icons.verified_outlined;
      case 'security':
        return Icons.security_outlined;
      case 'settings':
        return Icons.settings_outlined;
      case 'inventory':
        return Icons.inventory_2_outlined;
      case 'water':
      case 'riego':
        return Icons.water_drop_outlined;
      case 'agriculture':
      case 'tractor':
        return Icons.agriculture_outlined;
      case 'map':
      case 'lotes':
        return Icons.map_outlined;
      case 'eco':
      case 'variedades':
        return Icons.eco_outlined;
      case 'account_tree':
      case 'centro_costo':
        return Icons.account_tree_outlined;
      case 'grid_view':
        return Icons.grid_view_outlined;
      case 'category':
        return Icons.category_outlined;
      default:
        return Icons.circle_outlined;
    }
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
      return desktopSelectedFormat!['nombre']?.toString().trim().isNotEmpty == true
          ? desktopSelectedFormat!['nombre'].toString()
          : (desktopSelectedFormat!['id']?.toString() ?? 'Formato');
    }
    if (desktopSelectedReportModule != null && desktopSelectedReportView != null) {
      return desktopSelectedReportView!['nombre_vista']?.toString().trim().isNotEmpty == true
          ? desktopSelectedReportView!['nombre_vista'].toString()
          : 'Reportes';
    }
    if (desktopSelectedSection != null) return _sectionTitle(desktopSelectedSection!);
    return 'ZUMAC';
  }

  void _goMobileHome() {
    setState(() {
      desktopSelectedSection = null;
      desktopSelectedModule = null;
      desktopSelectedFormat = null;
      desktopSelectedReportModule = null;
      desktopSelectedReportView = null;
      desktopSelectedDynamicView = null;
      mobileSelectedSpecial = null;
    });
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
            tooltip: 'Volver al inicio',
            icon: const Icon(Icons.arrow_back),
            onPressed: _goMobileHome,
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

  VoidCallback _sectionTap(Map<String, dynamic> section) {
    final id = section['id']?.toString() ?? '';
    final kind = _sectionKind(section);
    final desktopLayout = isWideDesktopLayout(context);

    if (desktopLayout) {
      return () => _selectDesktopSection(section);
    }

    if (id == 'modulos') return () => Navigator.pop(context);
    if (kind == 'REGISTROS_LOCALES') {
      return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LocalRecordsPage())).then((_) => loadLocal());
    }
    if (kind == 'REPORTES') {
      return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsPage()));
    }
    if (_sectionUsesDynamicViews(section)) {
      return () => Navigator.push(context, MaterialPageRoute(builder: (_) => DynamicViewsPage(section: section, onPendingChanged: loadLocal))).then((_) => loadLocal());
    }
    return () => Navigator.push(context, MaterialPageRoute(builder: (_) => GenericSectionPage(section: section))).then((_) => loadLocal());
  }

  Widget _menuItems() {
    final visibleSections = sections
        .where((s) => _canSection(s['id']?.toString() ?? ''))
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

    return Column(
      children: [
        for (final section in visibleSections)
          _drawerItem(
            _iconForSection(section['id']?.toString() ?? '', section['icono']?.toString()),
            _sectionTitle(section),
            _sectionTap(section),
            badge: _sectionKind(section) == 'REGISTROS_LOCALES' && pending > 0 ? '$pending' : null,
          ),
      ],
    );
  }


  void _selectDesktopSection(Map<String, dynamic> section) {
    if (desktopSelectedSection?['id']?.toString() == section['id']?.toString() &&
        desktopSelectedModule == null &&
        desktopSelectedFormat == null &&
        desktopSelectedReportModule == null &&
        desktopSelectedReportView == null &&
        desktopSelectedDynamicView == null) return;
    setState(() {
      _clearDesktopContentCache();
      _clearDesktopSidebarCache();
      desktopSelectedSection = Map<String, dynamic>.from(section);
      desktopSelectedModule = null;
      desktopSelectedFormat = null;
      desktopSelectedReportModule = null;
      desktopSelectedReportView = null;
      desktopSelectedDynamicView = null;
      mobileSelectedSpecial = null;
    });
  }

  Widget _desktopPanelShell({required String title, required Widget child}) {
    // En Windows el panel derecho debe mostrar directamente el contenido seleccionado.
    // El título superior fijo se elimina para no duplicar el nombre de la vista.
    return child;
  }

  void _selectDesktopFormat(Map<String, dynamic> module, Map<String, dynamic> format) {
    final sameSelection = desktopSelectedModule?['id']?.toString() == module['id']?.toString() &&
        desktopSelectedFormat?['id']?.toString() == format['id']?.toString() &&
        desktopSelectedSection == null &&
        desktopSelectedReportModule == null &&
        desktopSelectedReportView == null &&
        desktopSelectedDynamicView == null;
    if (sameSelection) return;
    setState(() {
      _clearDesktopContentCache();
      _clearDesktopSidebarCache();
      desktopSelectedSection = null;
      desktopSelectedModule = Map<String, dynamic>.from(module);
      desktopSelectedFormat = Map<String, dynamic>.from(format);
      desktopSelectedReportModule = null;
      desktopSelectedReportView = null;
      desktopSelectedDynamicView = null;
      mobileSelectedSpecial = null;
    });
  }

  void _selectDesktopReportView(Map<String, dynamic> module, Map<String, dynamic> view) {
    setState(() {
      _clearDesktopContentCache();
      _clearDesktopSidebarCache();
      desktopSelectedSection = null;
      desktopSelectedModule = null;
      desktopSelectedFormat = null;
      desktopSelectedReportModule = Map<String, dynamic>.from(module);
      desktopSelectedReportView = Map<String, dynamic>.from(view);
      desktopSelectedDynamicView = null;
      mobileSelectedSpecial = null;
    });
  }


  void _selectDesktopDynamicView(Map<String, dynamic> section, Map<String, dynamic> view) {
    setState(() {
      _clearDesktopContentCache();
      _clearDesktopSidebarCache();
      desktopSelectedSection = Map<String, dynamic>.from(section);
      desktopSelectedDynamicView = Map<String, dynamic>.from(view);
      desktopSelectedModule = null;
      desktopSelectedFormat = null;
      desktopSelectedReportModule = null;
      desktopSelectedReportView = null;
      mobileSelectedSpecial = null;
    });
  }

  Widget _desktopDefaultPanel() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Bienvenidos al Sistema Zumac', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF0D5F78))),
          const SizedBox(height: 28),
          Opacity(
            opacity: 0.96,
            child: ClipOval(
              child: Image.asset(
                'assets/images/logo_zumac.jpeg',
                width: 220,
                height: 220,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _desktopContentSignature() {
    if (busy) return 'busy';
    if (desktopSelectedModule != null && desktopSelectedFormat != null) {
      return 'format:${desktopSelectedModule!['id']}:${desktopSelectedFormat!['id']}';
    }
    if (desktopSelectedReportModule != null && desktopSelectedReportView != null) {
      return 'report:${desktopSelectedReportModule!['id']}:${desktopSelectedReportView!['id']}';
    }
    if (desktopSelectedSection != null && desktopSelectedDynamicView != null) {
      return 'dynamic:${desktopSelectedSection!['id']}:${desktopSelectedDynamicView!['id']}';
    }
    if (desktopSelectedSection != null) return 'section:${desktopSelectedSection!['id']}';
    return 'home';
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
          key: ValueKey('${module['id']}_${format['id']}'),
          module: module,
          format: format,
          embedded: true,
          onLocalRecordsChanged: loadLocal,
        ),
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
        return _desktopPanelShell(title: title, child: LocalRecordsPage(embedded: true, onChanged: loadLocal));
      }
      if (kind == 'REPORTES') {
        return _desktopPanelShell(title: title, child: const ReportsPage(embedded: true));
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
      if (_sectionHasFormatModules(id)) return _desktopDefaultPanel();
      return _desktopPanelShell(title: title, child: GenericSectionPage(section: section, embedded: true));
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
        final formats = formatsByModule[moduleId] ?? const <Map<String, dynamic>>[];

        return Card(
          child: ExpansionTile(
            leading: const Icon(Icons.apps),
            title: Text(
              '${module['nombre']}',
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
            // No mostramos el id técnico debajo del módulo para ahorrar espacio en el menú.
            subtitle: null,
            children: formats.isEmpty
                ? const [
                    ListTile(
                      dense: true,
                      title: Text('No tienes formatos permitidos en este módulo.'),
                    ),
                  ]
                : formats.map((format) {
                    return ListTile(
                      contentPadding: const EdgeInsets.only(left: 72, right: 24),
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

    return Container(
      width: desktopSidebarOpen ? 320 : 64,
      decoration: const BoxDecoration(
        color: Color(0xFF0F2F4A),
        boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 16, offset: Offset(4, 0))],
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.eco, color: Colors.white),
                  if (desktopSidebarOpen) ...[
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'ZUMAC',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: .4),
                      ),
                    ),
                  ],
                  IconButton(
                    tooltip: desktopSidebarOpen ? 'Ocultar menú' : 'Mostrar menú',
                    onPressed: () {
                      desktopSidebarOpen = !desktopSidebarOpen;
                      _clearDesktopSidebarCache();
                      _desktopSidebarOpenNotifier.value = desktopSidebarOpen;
                    },
                    icon: Icon(desktopSidebarOpen ? Icons.chevron_left : Icons.chevron_right, color: Colors.white),
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
                        for (final section in visibleSections.where((s) => _sectionHasFormatModules(_txt(s['id']))))
                          Theme(
                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              key: ValueKey('desktop-section-${_txt(section['id'])}-${_expandedSectionId == _txt(section['id'])}'),
                              initiallyExpanded: _expandedSectionId == _txt(section['id']),
                              onExpansionChanged: (expanded) =>
                                  _onSectionExpansionChanged(_txt(section['id']), expanded),
                              leading: Icon(_iconForSection(_txt(section['id']), section['icono']?.toString()), color: Colors.white),
                              iconColor: Colors.white,
                              collapsedIconColor: Colors.white70,
                              title: Text(_sectionTitle(section), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                              children: _modulesForSection(_txt(section['id'])).map((module) {
                                final moduleId = module['id']?.toString() ?? '';
                                final formats = formatsByModule[moduleId] ?? const <Map<String, dynamic>>[];
                                return ExpansionTile(
                                  tilePadding: const EdgeInsets.only(left: 24, right: 8),
                                  childrenPadding: EdgeInsets.zero,
                                  iconColor: Colors.white,
                                  collapsedIconColor: Colors.white54,
                                  title: Text(
                                    module['nombre']?.toString() ?? moduleId,
                                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                  children: formats.map((format) {
                                    return ListTile(
                                      dense: true,
                                      contentPadding: const EdgeInsets.only(left: 46, right: 8),
                                      leading: const Icon(Icons.description_outlined, color: Colors.white54, size: 18),
                                      title: Text(
                                        format['nombre']?.toString() ?? format['id']?.toString() ?? '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontSize: 12.5),
                                      ),
                                      selected: desktopSelectedFormat?['id']?.toString() == format['id']?.toString(),
                                      selectedTileColor: Colors.white10,
                                      onTap: () => _selectDesktopFormat(module, format),
                                    );
                                  }).toList(),
                                );
                              }).toList(),
                            ),
                          ),
                        for (final section in visibleSections.where((s) => !_sectionHasFormatModules(_txt(s['id']))))
                          if (_sectionKind(section) == 'REPORTES')
                            Theme(
                              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                key: ValueKey('desktop-section-${_txt(section['id'])}-${_expandedSectionId == _txt(section['id'])}'),
                                initiallyExpanded: _expandedSectionId == _txt(section['id']),
                                onExpansionChanged: (expanded) =>
                                    _onSectionExpansionChanged(_txt(section['id']), expanded),
                                leading: Icon(_iconForSection(section['id']?.toString() ?? '', section['icono']?.toString()), color: Colors.white70),
                                iconColor: Colors.white,
                                collapsedIconColor: Colors.white70,
                                title: Text(_sectionTitle(section), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                children: reportModules.map((module) {
                                  final moduleViews = _reportViewsForModule(module);
                                  return ExpansionTile(
                                    tilePadding: const EdgeInsets.only(left: 24, right: 8),
                                    childrenPadding: EdgeInsets.zero,
                                    iconColor: Colors.white,
                                    collapsedIconColor: Colors.white54,
                                    title: Text(
                                      module['nombre']?.toString() ?? module['id']?.toString() ?? '',
                                      style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                    children: moduleViews.isEmpty
                                        ? const [
                                            ListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.only(left: 46, right: 8),
                                              title: Text('Sin vistas permitidas', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                            ),
                                          ]
                                        : moduleViews.map((view) {
                                            return ListTile(
                                              dense: true,
                                              contentPadding: const EdgeInsets.only(left: 46, right: 8),
                                              leading: const Icon(Icons.insert_chart_outlined, color: Colors.white54, size: 18),
                                              title: Text(
                                                view['nombre_vista']?.toString() ?? view['id']?.toString() ?? '',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: Colors.white, fontSize: 12.5),
                                              ),
                                              selected: desktopSelectedReportView?['id']?.toString() == view['id']?.toString(),
                                              selectedTileColor: Colors.white10,
                                              onTap: () => _selectDesktopReportView(module, view),
                                            );
                                          }).toList(),
                                  );
                                }).toList(),
                              ),
                            )
                          else if (_sectionUsesDynamicViews(section))
                            Theme(
                              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                key: ValueKey('desktop-section-${_txt(section['id'])}-${_expandedSectionId == _txt(section['id'])}'),
                                initiallyExpanded: _expandedSectionId == _txt(section['id']),
                                onExpansionChanged: (expanded) =>
                                    _onSectionExpansionChanged(_txt(section['id']), expanded),
                                leading: Icon(_iconForSection(section['id']?.toString() ?? '', section['icono']?.toString()), color: Colors.white70),
                                iconColor: Colors.white,
                                collapsedIconColor: Colors.white70,
                                title: Text(_sectionTitle(section), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                children: _dynamicViewsGroupedByModule(section['id']?.toString() ?? '').entries.map((entry) {
                                  return ExpansionTile(
                                    tilePadding: const EdgeInsets.only(left: 24, right: 8),
                                    childrenPadding: EdgeInsets.zero,
                                    iconColor: Colors.white,
                                    collapsedIconColor: Colors.white54,
                                    title: Text(entry.key, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                                    children: entry.value.map((view) => ListTile(
                                      dense: true,
                                      contentPadding: const EdgeInsets.only(left: 46, right: 8),
                                      leading: const Icon(Icons.view_list_outlined, color: Colors.white54, size: 18),
                                      title: Text(view['nombre_vista']?.toString() ?? view['id']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                                      selected: desktopSelectedDynamicView?['id']?.toString() == view['id']?.toString(),
                                      selectedTileColor: Colors.white10,
                                      onTap: () => _selectDesktopDynamicView(section, view),
                                    )).toList(),
                                  );
                                }).toList(),
                              ),
                            )
                          else
                            ListTile(
                              leading: Icon(_iconForSection(section['id']?.toString() ?? '', section['icono']?.toString()), color: Colors.white70),
                              title: Text(_sectionTitle(section), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                              trailing: _sectionKind(section) == 'REGISTROS_LOCALES' && pending > 0
                                  ? CircleAvatar(radius: 10, child: Text('$pending', style: const TextStyle(fontSize: 10)))
                                  : null,
                              onTap: _sectionTap(section),
                            ),
                      ],
                    )
                  : Column(
                      children: [
                        IconButton(
                          tooltip: 'Formatos',
                          onPressed: () {
                            desktopSidebarOpen = true;
                            _clearDesktopSidebarCache();
                            _desktopSidebarOpenNotifier.value = true;
                          },
                          icon: const Icon(Icons.apps, color: Colors.white),
                        ),
                        IconButton(
                          tooltip: 'Registros locales',
                          onPressed: () => _selectDesktopSection({'id': 'registros_locales', 'nombre': 'Registros locales', 'icono': 'storage'}),
                          icon: const Icon(Icons.storage, color: Colors.white70),
                        ),
                        IconButton(
                          tooltip: 'Reportes',
                          onPressed: () => _selectDesktopSection({'id': 'reportes', 'nombre': 'Reportes', 'icono': 'bar_chart'}),
                          icon: const Icon(Icons.bar_chart, color: Colors.white70),
                        ),
                      ],
                    ),
            ),
            const Divider(color: Colors.white24, height: 1),
            if (desktopSidebarOpen && profileName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline, color: Colors.white70, size: 18),
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

  Future<void> _selectMobileFormat(Map<String, dynamic> module, Map<String, dynamic> format) async {
    final specialRows = await local.where(
      'local_special_formats',
      'formato_id = ? and activo = 1',
      [format['id']],
    );
    if (!mounted) return;
    Navigator.of(context).maybePop();
    setState(() {
      desktopSelectedSection = null;
      desktopSelectedModule = Map<String, dynamic>.from(module);
      desktopSelectedFormat = Map<String, dynamic>.from(format);
      desktopSelectedReportModule = null;
      desktopSelectedReportView = null;
      mobileSelectedSpecial = specialRows.isNotEmpty
          ? Map<String, dynamic>.from(specialRows.first)
          : ((format['tabla_destino']?.toString() ?? '') == 'GT-TAREO_PERSONAL'
              ? <String, dynamic>{'tipo_pantalla': 'tareo_personal', 'activo': 1}
              : null);
    });
  }

  void _selectMobileSection(Map<String, dynamic> section) {
    Navigator.of(context).maybePop();
    setState(() {
      desktopSelectedSection = Map<String, dynamic>.from(section);
      desktopSelectedModule = null;
      desktopSelectedFormat = null;
      desktopSelectedReportModule = null;
      desktopSelectedReportView = null;
      desktopSelectedDynamicView = null;
      mobileSelectedSpecial = null;
    });
  }

  void _selectMobileDynamicView(Map<String, dynamic> section, Map<String, dynamic> view) {
    Navigator.of(context).maybePop();
    setState(() {
      desktopSelectedSection = Map<String, dynamic>.from(section);
      desktopSelectedDynamicView = Map<String, dynamic>.from(view);
      desktopSelectedModule = null;
      desktopSelectedFormat = null;
      desktopSelectedReportModule = null;
      desktopSelectedReportView = null;
      mobileSelectedSpecial = null;
    });
  }

  void _selectMobileReportView(Map<String, dynamic> module, Map<String, dynamic> view) {
    Navigator.of(context).maybePop();
    setState(() {
      desktopSelectedSection = null;
      desktopSelectedModule = null;
      desktopSelectedFormat = null;
      desktopSelectedReportModule = Map<String, dynamic>.from(module);
      desktopSelectedReportView = Map<String, dynamic>.from(view);
      desktopSelectedDynamicView = null;
      mobileSelectedSpecial = null;
    });
  }

  Widget _logoHomePanel() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Bienvenidos al Sistema Zumac', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF0D5F78))),
          const SizedBox(height: 24),
          Opacity(
            opacity: 0.96,
            child: ClipOval(
              child: Image.asset(
                'assets/images/logo_zumac.jpeg',
                width: 180,
                height: 180,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileSelectedContent() {
    if (busy) return const Center(child: CircularProgressIndicator());

    final module = desktopSelectedModule;
    final format = desktopSelectedFormat;
    if (module != null && format != null) {
      final moduleId = module['id']?.toString() ?? '';
      final key = ValueKey('mobile_${moduleId}_${format['id']}_${mobileSelectedSpecial?['id'] ?? ''}');
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
        );
      }
      return FormRunnerPage(
        key: key,
        moduleId: moduleId,
        format: format,
        onBack: _goMobileHome,
      );
    }

    final reportModule = desktopSelectedReportModule;
    final reportView = desktopSelectedReportView;
    if (reportModule != null && reportView != null) {
      return ReportsPage(
        key: ValueKey('mobile_report_${reportModule['id']}_${reportView['id']}'),
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
      if (kind == 'REGISTROS_LOCALES') return LocalRecordsPage(embedded: true, onChanged: loadLocal);
      if (kind == 'REPORTES') return const ReportsPage(embedded: true, showRail: false);
      if (_sectionUsesDynamicViews(section)) return DynamicViewsPage(section: section, view: desktopSelectedDynamicView, embedded: true, onPendingChanged: loadLocal);
      if (!_sectionHasFormatModules(id)) return GenericSectionPage(section: section, embedded: true);
    }

    return _logoHomePanel();
  }

  Widget _mobileMenuItems() {
    final visibleSections = sections
        .where((s) => _canSection(s['id']?.toString() ?? ''))
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
        for (final section in visibleSections)
          if (_sectionHasFormatModules(_txt(section['id'])))
            ExpansionTile(
              key: ValueKey('mobile-section-${_txt(section['id'])}-${_expandedSectionId == _txt(section['id'])}'),
              initiallyExpanded: _expandedSectionId == _txt(section['id']),
              onExpansionChanged: (expanded) =>
                  _onSectionExpansionChanged(_txt(section['id']), expanded),
              leading: Icon(_iconForSection(_txt(section['id']), section['icono']?.toString())),
              title: Text(_sectionTitle(section), style: const TextStyle(fontWeight: FontWeight.w700)),
              children: _modulesForSection(_txt(section['id'])).map((module) {
                final moduleId = module['id']?.toString() ?? '';
                final formats = formatsByModule[moduleId] ?? const <Map<String, dynamic>>[];
                return ExpansionTile(
                  tilePadding: const EdgeInsets.only(left: 32, right: 16),
                  leading: const Icon(Icons.grid_view_outlined, size: 20),
                  title: Text(module['nombre']?.toString() ?? moduleId),
                  // No mostrar id técnico del módulo en móvil.
                  subtitle: null,
                  children: formats.isEmpty
                      ? const [
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.only(left: 72, right: 16),
                            title: Text('Sin formatos permitidos'),
                          ),
                        ]
                      : formats.map((format) {
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.only(left: 72, right: 16),
                            leading: const Icon(Icons.description_outlined, size: 18),
                            title: Text(
                              format['nombre']?.toString() ?? format['id']?.toString() ?? '',
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
              key: ValueKey('mobile-section-${_txt(section['id'])}-${_expandedSectionId == _txt(section['id'])}'),
              initiallyExpanded: _expandedSectionId == _txt(section['id']),
              onExpansionChanged: (expanded) =>
                  _onSectionExpansionChanged(_txt(section['id']), expanded),
              leading: Icon(_iconForSection('reportes', section['icono']?.toString())),
              title: Text(_sectionTitle(section), style: const TextStyle(fontWeight: FontWeight.w700)),
              children: reportModules.map((module) {
                final views = _reportViewsForModule(module);
                return ExpansionTile(
                  tilePadding: const EdgeInsets.only(left: 32, right: 16),
                  leading: const Icon(Icons.folder_copy_outlined, size: 20),
                  title: Text(module['nombre']?.toString() ?? module['id']?.toString() ?? ''),
                  children: views.isEmpty
                      ? const [
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.only(left: 72, right: 16),
                            title: Text('Sin vistas permitidas'),
                          ),
                        ]
                      : views.map((view) {
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.only(left: 72, right: 16),
                            leading: const Icon(Icons.insert_chart_outlined, size: 18),
                            title: Text(
                              view['nombre_vista']?.toString() ?? view['id']?.toString() ?? '',
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
              key: ValueKey('mobile-section-${_txt(section['id'])}-${_expandedSectionId == _txt(section['id'])}'),
              initiallyExpanded: _expandedSectionId == _txt(section['id']),
              onExpansionChanged: (expanded) =>
                  _onSectionExpansionChanged(_txt(section['id']), expanded),
              leading: Icon(_iconForSection(section['id']?.toString() ?? '', section['icono']?.toString())),
              title: Text(_sectionTitle(section), style: const TextStyle(fontWeight: FontWeight.w700)),
              children: () {
                final grouped = _dynamicViewsGroupedByModule(section['id']?.toString() ?? '');
                if (grouped.isEmpty) {
                  return const <Widget>[
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.only(left: 46, right: 16),
                      title: Text('Sin vistas configuradas/actualizadas'),
                    ),
                  ];
                }
                return grouped.entries.map((entry) => ExpansionTile(
                  tilePadding: const EdgeInsets.only(left: 32, right: 16),
                  leading: const Icon(Icons.folder_open_outlined, size: 20),
                  title: Text(entry.key),
                  children: entry.value.map((view) => ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 72, right: 16),
                    leading: const Icon(Icons.view_list_outlined, size: 18),
                    title: Text(view['nombre_vista']?.toString() ?? view['id']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(view['tabla_destino']?.toString() ?? '', style: const TextStyle(fontSize: 11)),
                    onTap: () => _selectMobileDynamicView(section, view),
                  )).toList(),
                )).toList();
              }(),
            )
          else
            ListTile(
              leading: Icon(_iconForSection(section['id']?.toString() ?? '', section['icono']?.toString())),
              title: Text(_sectionTitle(section), style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: _sectionKind(section) == 'REGISTROS_LOCALES' && pending > 0
                  ? CircleAvatar(radius: 10, child: Text('$pending', style: const TextStyle(fontSize: 10)))
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
            leading: const Icon(Icons.apps),
            title: Text('${m['nombre']}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            subtitle: Text('${m['id']}', style: const TextStyle(fontSize: 11.5)),
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

  @override
  Widget build(BuildContext context) {
    final desktopLayout = isWideDesktopLayout(context);
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
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(onPressed: busy ? null : checkAppUpdate, icon: const Icon(Icons.system_update_alt), tooltip: 'Actualizar app'),
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text(appVersionLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        IconButton(onPressed: busy ? null : download, icon: const Icon(Icons.refresh), tooltip: 'Actualizar datos'),
        Stack(
          alignment: Alignment.topRight,
          children: [
            IconButton(onPressed: busy ? null : syncPending, icon: const Icon(Icons.sync), tooltip: 'Sincronizar'),
            if (pending > 0)
              CircleAvatar(radius: 10, child: Text('$pending', style: const TextStyle(fontSize: 11))),
          ],
        ),
      ],
    );

    if (isWideDesktopLayout(context)) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: _desktopSidebarOpenNotifier,
              builder: (context, _, __) => _desktopSidebarCached(),
            ),
            Expanded(child: RepaintBoundary(child: content)),
          ],
        ),
      );
    }

    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.eco),
                title: const Text('ZUMAC', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  profileName.isEmpty ? 'Menú principal' : 'Menú principal\n$profileName',
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
          Expanded(child: content),
        ],
      ),
    );
  }

}
