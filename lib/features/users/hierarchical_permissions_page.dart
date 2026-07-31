import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/local_session.dart';
import '../../core/services/sync_service.dart';
import '../../core/widgets/responsive_layout.dart';
import 'hierarchical_access_resolver.dart';

class HierarchicalPermissionsPage extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onChanged;

  const HierarchicalPermissionsPage({
    super.key,
    this.embedded = false,
    this.onChanged,
  });

  @override
  State<HierarchicalPermissionsPage> createState() =>
      _HierarchicalPermissionsPageState();
}

class _HierarchicalPermissionsPageState
    extends State<HierarchicalPermissionsPage> {
  final supabase = Supabase.instance.client;
  final searchController = TextEditingController();

  List<Map<String, dynamic>> sections = [];
  List<Map<String, dynamic>> modules = [];
  List<Map<String, dynamic>> formats = [];
  List<Map<String, dynamic>> profiles = [];
  List<Map<String, dynamic>> formatPermissions = [];
  List<Map<String, dynamic>> sectionPermissions = [];

  String? selectedUserId;
  String scope = 'SECCION';
  String? selectedSectionId;
  String? selectedModuleId;
  String? selectedFormatId;
  String formatSearch = '';

  bool canView = true;
  bool canInsert = true;
  bool canUpdate = false;
  bool canDelete = false;
  bool canExport = false;
  bool canImport = false;
  bool canReview = false;
  bool canApprove = false;
  bool loading = true;
  bool saving = false;
  String? loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  bool _bool(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    return const {'true', 't', '1', 'si', 'sí', 'yes'}
        .contains(value.toString().trim().toLowerCase());
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  bool _same(dynamic a, dynamic b) =>
      _text(a).toLowerCase() == _text(b).toLowerCase();

  int _order(Map<String, dynamic> row) =>
      int.tryParse(_text(row['orden'])) ?? 0;

  bool _isActive(Map<String, dynamic> row) =>
      _bool(row['activo'], fallback: true) &&
      _text(row['deleted_at']).isEmpty &&
      !_bool(row['eliminado']);

  bool _rpcUnavailable(Object error) {
    if (error is PostgrestException &&
        const {'PGRST202', '42883'}.contains(error.code)) {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('could not find the function') ||
        message.contains('function does not exist');
  }

  String _permissionSaveError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('m.seccion_id') ||
        (message.contains('42703') && message.contains('seccion_id'))) {
      return 'No se pudo guardar el permiso porque el servicio de permisos del servidor está desactualizado. Actualice la base de datos e inténtelo nuevamente.';
    }
    if (message.contains('42703') && message.contains('tabla_destino')) {
      return 'No se pudo guardar el permiso porque falta actualizar la compatibilidad de formatos nuevos en el servidor.';
    }
    if (message.contains('active format/module hierarchy not found') ||
        message.contains('active format/module/table hierarchy not found')) {
      return 'No se pudo guardar el permiso porque el formato todavía no está vinculado a su módulo y tabla publicados. Actualice datos e inténtelo nuevamente.';
    }
    if (message.contains('target user does not belong')) {
      return 'No se pudo guardar el permiso porque el usuario no pertenece a la empresa activa.';
    }
    if (message.contains('42501') ||
        message.contains('administrator permission required') ||
        message.contains('permission denied') ||
        message.contains('jwt')) {
      return 'No se pudo guardar el permiso. Verifique que la sesión siga activa y que su usuario sea administrador de la empresa.';
    }
    return 'No se pudo guardar el permiso: ${SyncService().friendlyError(error)}';
  }

  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  Future<List<Map<String, dynamic>>> _tableRows(String table) async {
    final value = await supabase.from(table).select();
    return List<Map<String, dynamic>>.from(value);
  }

  List<Map<String, dynamic>> _maps(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _loadPermissionCatalog() async {
    try {
      final value = await supabase.rpc('appgt_admin_permission_catalog_v1');
      if (value is Map) return Map<String, dynamic>.from(value);
    } catch (error) {
      if (!_rpcUnavailable(error)) rethrow;
    }
    final rows = await Future.wait([
      _tableRows('MATRIZ_SECCIONES_APPGT'),
      _tableRows('MATRIZ_MODULOS_APPGT'),
      _tableRows('MATRIZ_FORMATOS_APPGT'),
    ]);
    return {
      'secciones': rows[0],
      'modulos': rows[1],
      'formatos': rows[2],
    };
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      if (!await _hasInternet()) {
        throw StateError('Conéctese a internet para administrar permisos.');
      }
      final results = await Future.wait<dynamic>([
        _loadPermissionCatalog(),
        _loadProfiles(),
      ]);
      final catalog = Map<String, dynamic>.from(results[0] as Map);
      if (!mounted) return;
      setState(() {
        sections = _maps(catalog['secciones']).where(_isActive).toList()
          ..sort((a, b) => _order(a).compareTo(_order(b)));
        modules = _maps(catalog['modulos']).where(_isActive).toList()
          ..sort((a, b) => _order(a).compareTo(_order(b)));
        formats = _maps(catalog['formatos']).where(_isActive).toList()
          ..sort((a, b) => _order(a).compareTo(_order(b)));
        profiles = (results[1] as List<Map<String, dynamic>>)
            .where(_isActive)
            .toList();
        loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        loading = false;
        loadError = SyncService().friendlyError(error);
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadProfiles() async {
    try {
      final value = await supabase.rpc('appgt_admin_list_profiles');
      return List<Map<String, dynamic>>.from(value);
    } catch (_) {
      final value = await supabase.from('PERFILES_DE_USUARIOS_APPGT').select();
      return List<Map<String, dynamic>>.from(value);
    }
  }

  String _profileUserId(Map<String, dynamic> profile) {
    for (final key in const [
      'user_id',
      'usuario_id',
      'auth_user_id',
      'auth_id',
      'uid',
      'id_usuario',
      'id',
    ]) {
      final value = _text(profile[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _profileLabel(Map<String, dynamic> profile) {
    final code = _text(profile['CODIGO_USUARIO']).isNotEmpty
        ? _text(profile['CODIGO_USUARIO'])
        : _text(profile['codigo_usuario']);
    final name = _text(profile['nombres']).isNotEmpty
        ? _text(profile['nombres'])
        : _text(profile['NOMBRES']);
    if (code.isNotEmpty && name.isNotEmpty) return '$code · $name';
    if (code.isNotEmpty) return code;
    if (name.isNotEmpty) return name;
    return _profileUserId(profile);
  }

  List<String> _candidateUserIds(String userId) {
    final values = <String>{userId};
    final profile = profiles.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row != null && _profileUserId(row) == userId,
          orElse: () => null,
        );
    if (profile != null) {
      for (final key in const [
        'user_id',
        'usuario_id',
        'auth_user_id',
        'auth_id',
        'uid',
        'id_usuario',
        'id',
      ]) {
        final value = _text(profile[key]);
        if (value.isNotEmpty) values.add(value);
      }
    }
    return values.toList();
  }

  Future<void> _loadUserPermissions(String userId) async {
    setState(() {
      saving = true;
      formatPermissions = [];
      sectionPermissions = [];
    });
    try {
      final formatRows = <String, Map<String, dynamic>>{};
      final sectionRows = <String, Map<String, dynamic>>{};
      for (final candidate in _candidateUserIds(userId)) {
        var loadedCanonicalAccess = false;
        try {
          final value = await supabase.rpc(
            'appgt_admin_user_access_v1',
            params: {'p_user_id': candidate},
          );
          final access = value is Map
              ? Map<String, dynamic>.from(value)
              : <String, dynamic>{};
          for (final row in _maps(access['permisos_formatos'])) {
            formatRows[
                    '${_text(row['modulo']).toLowerCase()}::${_text(row['formato']).toLowerCase()}'] =
                row;
          }
          for (final row in _maps(access['permisos_secciones'])) {
            final section = _sectionPermissionId(row);
            if (section.isNotEmpty) sectionRows[section.toLowerCase()] = row;
          }
          loadedCanonicalAccess = true;
        } catch (error) {
          if (!_rpcUnavailable(error)) rethrow;
        }
        if (!loadedCanonicalAccess) {
          try {
            final value = await supabase.rpc(
              'appgt_admin_list_user_permissions',
              params: {'p_user_id': candidate},
            );
            for (final row in List<Map<String, dynamic>>.from(value)) {
              formatRows[
                      '${_text(row['modulo']).toLowerCase()}::${_text(row['formato']).toLowerCase()}'] =
                  row;
            }
          } catch (_) {
            final value = await supabase
                .from('PERMISOS_DE_USUARIOS_APPGT')
                .select()
                .eq('user_id', candidate);
            for (final row in List<Map<String, dynamic>>.from(value)) {
              formatRows[
                      '${_text(row['modulo']).toLowerCase()}::${_text(row['formato']).toLowerCase()}'] =
                  row;
            }
          }
          try {
            final value = await supabase
                .from('PERMISOS_SECCIONES_APPGT')
                .select()
                .eq('user_id', candidate);
            for (final row in List<Map<String, dynamic>>.from(value)) {
              final section = _sectionPermissionId(row);
              if (section.isNotEmpty) {
                sectionRows[section.toLowerCase()] = row;
              }
            }
          } catch (_) {
            // El catálogo canónico evita este camino una vez aplicada la
            // migración; se conserva solo por compatibilidad temporal.
          }
        }
      }
      if (!mounted) return;
      setState(() {
        formatPermissions = formatRows.values.toList();
        sectionPermissions = sectionRows.values.toList();
        _applySelectedFormatActions();
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(SyncService().friendlyError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String _sectionPermissionId(Map<String, dynamic> row) {
    final canonical = _text(row['seccion_id']);
    return canonical.isNotEmpty ? canonical : _text(row['seccion']);
  }

  String _moduleSectionId(Map<String, dynamic> module) {
    for (final key in const ['seccion_id', 'seccion', 'id_seccion']) {
      final value = _text(module[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _formatModuleId(Map<String, dynamic> format) {
    for (final key in const ['modulo_id', 'modulo', 'id_modulo']) {
      final value = _text(format[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Map<String, dynamic>? _moduleById(String? id) {
    if (id == null) return null;
    for (final module in modules) {
      if (_same(module['id'], id)) return module;
    }
    return null;
  }

  Map<String, dynamic>? _formatById(String? id) {
    if (id == null) return null;
    for (final format in formats) {
      if (_same(format['id'], id)) return format;
    }
    return null;
  }

  Map<String, dynamic>? _sectionById(String? id) {
    if (id == null) return null;
    for (final section in sections) {
      if (_same(section['id'], id)) return section;
    }
    return null;
  }

  List<Map<String, dynamic>> get _modulesForSelectedSection => modules
      .where((module) => _same(_moduleSectionId(module), selectedSectionId))
      .toList();

  List<Map<String, dynamic>> _formatsForModule(String moduleId) => formats
      .where((format) => _same(_formatModuleId(format), moduleId))
      .toList();

  List<Map<String, dynamic>> get _matchingFormats {
    final query = formatSearch.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return formats
        .where((format) {
          return _text(format['nombre']).toLowerCase().contains(query) ||
              _text(format['id']).toLowerCase().contains(query) ||
              _text(format['tabla_destino']).toLowerCase().contains(query);
        })
        .take(20)
        .toList();
  }

  String _sectionName(String? id) =>
      _text(_sectionById(id)?['nombre']).isNotEmpty
          ? _text(_sectionById(id)?['nombre'])
          : _text(id);

  String _moduleName(String? id) => _text(_moduleById(id)?['nombre']).isNotEmpty
      ? _text(_moduleById(id)?['nombre'])
      : _text(id);

  String _formatBreadcrumb(Map<String, dynamic> format) {
    final moduleId = _formatModuleId(format);
    final sectionId = _moduleSectionId(_moduleById(moduleId) ?? const {});
    return '${_sectionName(sectionId)}  ›  ${_moduleName(moduleId)}';
  }

  void _selectFormat(Map<String, dynamic> format) {
    final moduleId = _formatModuleId(format);
    final sectionId = _moduleSectionId(_moduleById(moduleId) ?? const {});
    setState(() {
      selectedFormatId = _text(format['id']);
      selectedModuleId = moduleId;
      selectedSectionId = sectionId;
      searchController.text = _text(format['nombre']);
      formatSearch = searchController.text;
      _applySelectedFormatActions();
    });
  }

  Map<String, dynamic>? _permissionForSelectedFormat() {
    final format = _formatById(selectedFormatId);
    if (format == null) return null;
    final moduleId = _formatModuleId(format);
    for (final permission in formatPermissions) {
      final matchesModule = _same(permission['modulo'], moduleId) ||
          _same(permission['modulo_id'], moduleId);
      final matchesFormat = _same(permission['formato'], format['id']) ||
          _same(permission['formato_id'], format['id']) ||
          _same(permission['formato'], format['tabla_destino']) ||
          _same(permission['tabla_destino'], format['tabla_destino']);
      if (matchesModule && matchesFormat) return permission;
    }
    return null;
  }

  void _applySelectedFormatActions() {
    final permission = _permissionForSelectedFormat();
    canView = permission == null ? true : _bool(permission['can_view']);
    canInsert = permission == null ? true : _bool(permission['can_insert']);
    canUpdate = permission != null && _bool(permission['can_update']);
    canDelete = permission != null && _bool(permission['can_delete']);
    canExport = permission != null && _bool(permission['can_export']);
    canImport = permission != null && _bool(permission['can_import']);
    canReview = permission != null && _bool(permission['can_review']);
    canApprove = permission != null && _bool(permission['can_approve']);
  }

  bool _selectedFormatUsesApprovals() {
    final format = _formatById(selectedFormatId);
    if (format == null) return false;
    if (_bool(format['approvals_enabled'])) return true;
    final raw = format['capacidades'];
    if (raw is Map) {
      return _bool(raw['aprobaciones']) || _bool(raw['approvals']);
    }
    final text = _text(raw).toLowerCase();
    return text.contains('"aprobaciones":true') ||
        text.contains('"approvals":true');
  }

  String? _resolvedSectionId() {
    if (scope == 'SECCION') return selectedSectionId;
    if (scope == 'MODULO') {
      return _moduleSectionId(_moduleById(selectedModuleId) ?? const {});
    }
    final format = _formatById(selectedFormatId);
    final module = _moduleById(
        format == null ? selectedModuleId : _formatModuleId(format));
    return _moduleSectionId(module ?? const {});
  }

  Future<void> _upsertSectionPermission(
    String userId,
    String sectionId,
  ) async {
    try {
      await supabase.rpc('appgt_admin_upsert_section_permission', params: {
        'p_user_id': userId,
        'p_seccion_id': sectionId,
        'p_can_view': true,
      });
      return;
    } catch (error) {
      if (!_rpcUnavailable(error)) rethrow;
      // Compatibilidad temporal mientras se aplica la migración de la RPC.
    }
    final empresaId = await LocalSession().cachedEmpresaId();
    final existing = await supabase
        .from('PERMISOS_SECCIONES_APPGT')
        .select('id')
        .eq('user_id', userId)
        .or('seccion.eq.$sectionId,seccion_id.eq.$sectionId')
        .maybeSingle();
    final payload = <String, dynamic>{
      'user_id': userId,
      'seccion': sectionId,
      'seccion_id': sectionId,
      'can_view': true,
      'activo': true,
      'eliminado': false,
      if (empresaId.isNotEmpty) 'empresa_id': empresaId,
    };
    if (existing == null) {
      await supabase.from('PERMISOS_SECCIONES_APPGT').insert(payload);
    } else {
      await supabase
          .from('PERMISOS_SECCIONES_APPGT')
          .update(payload)
          .eq('id', existing['id']);
    }
  }

  Future<void> _upsertFormatPermission({
    required String userId,
    required String moduleId,
    required String formatId,
    required bool view,
    required bool insert,
    required bool update,
    required bool delete,
    required bool export,
    required bool import,
    required bool review,
    required bool approve,
  }) async {
    try {
      await supabase.rpc('appgt_admin_upsert_user_permission_v4', params: {
        'p_user_id': userId,
        'p_modulo': moduleId,
        'p_formato': formatId,
        'p_can_view': view,
        'p_can_insert': insert,
        'p_can_update': update,
        'p_can_delete': delete,
        'p_can_export': export,
        'p_can_import': import,
        'p_can_review': review,
        'p_can_approve': approve,
      });
      return;
    } catch (error) {
      if (!_rpcUnavailable(error)) rethrow;
      // Respaldo temporal para instalaciones que aún no aplicaron la RPC v4.
      try {
        await supabase.rpc('appgt_admin_upsert_user_permission_v3', params: {
          'p_user_id': userId,
          'p_modulo': moduleId,
          'p_formato': formatId,
          'p_can_view': view,
          'p_can_insert': insert,
          'p_can_update': update,
          'p_can_delete': delete,
          'p_can_export': export,
          'p_can_import': import,
        });
        return;
      } catch (legacyError) {
        if (!_rpcUnavailable(legacyError)) rethrow;
      }
    }
    final existing = await supabase
        .from('PERMISOS_DE_USUARIOS_APPGT')
        .select('id')
        .eq('user_id', userId)
        .eq('modulo', moduleId)
        .eq('formato', formatId)
        .maybeSingle();
    final payload = {
      'user_id': userId,
      'modulo': moduleId,
      'formato': formatId,
      'can_view': view,
      'can_insert': insert,
      'can_update': update,
      'can_delete': delete,
      'can_export': export,
      'can_import': import,
      'can_review': review,
      'can_approve': approve,
      'activo': true,
      'eliminado': false,
    };
    if (existing == null) {
      await supabase.from('PERMISOS_DE_USUARIOS_APPGT').insert(payload);
    } else {
      await supabase
          .from('PERMISOS_DE_USUARIOS_APPGT')
          .update(payload)
          .eq('id', existing['id']);
    }
  }

  Future<void> _deleteFormatPermission(
    String userId,
    String moduleId,
    String formatId,
  ) async {
    try {
      await supabase.rpc('appgt_admin_delete_user_permission', params: {
        'p_user_id': userId,
        'p_modulo': moduleId,
        'p_formato': formatId,
      });
      return;
    } catch (error) {
      if (!_rpcUnavailable(error)) rethrow;
      await supabase
          .from('PERMISOS_DE_USUARIOS_APPGT')
          .delete()
          .eq('user_id', userId)
          .eq('modulo', moduleId)
          .eq('formato', formatId);
    }
  }

  Future<void> _deleteSectionPermission(
    String userId,
    String sectionId,
  ) async {
    try {
      await supabase.rpc('appgt_admin_delete_section_permission', params: {
        'p_user_id': userId,
        'p_seccion_id': sectionId,
      });
      return;
    } catch (error) {
      if (!_rpcUnavailable(error)) rethrow;
      await supabase
          .from('PERMISOS_SECCIONES_APPGT')
          .delete()
          .eq('user_id', userId)
          .or('seccion.eq.$sectionId,seccion_id.eq.$sectionId');
    }
  }

  Future<void> _savePermission() async {
    final userId = selectedUserId;
    final sectionId = _resolvedSectionId();
    if (userId == null || userId.isEmpty) {
      _message('Seleccione un usuario.');
      return;
    }
    if (sectionId == null || sectionId.isEmpty) {
      _message('Seleccione la sección correspondiente.');
      return;
    }
    if (scope == 'MODULO' && selectedModuleId == null) {
      _message('Seleccione un módulo.');
      return;
    }
    if (scope == 'FORMATO' && selectedFormatId == null) {
      _message('Busque y seleccione un formato.');
      return;
    }

    setState(() => saving = true);
    try {
      await _upsertSectionPermission(userId, sectionId);
      if (scope == 'SECCION') {
        final childModules = modules.where(
          (module) => _same(_moduleSectionId(module), sectionId),
        );
        for (final module in childModules) {
          final moduleId = _text(module['id']);
          for (final format in _formatsForModule(moduleId)) {
            await _upsertFormatPermission(
              userId: userId,
              moduleId: moduleId,
              formatId: _text(format['id']),
              view: true,
              insert: false,
              update: false,
              delete: false,
              export: false,
              import: false,
              review: false,
              approve: false,
            );
          }
        }
      } else if (scope == 'MODULO') {
        final moduleId = selectedModuleId!;
        final children = _formatsForModule(moduleId);
        if (children.isEmpty) {
          throw StateError('El módulo no contiene formatos activos.');
        }
        for (final format in children) {
          await _upsertFormatPermission(
            userId: userId,
            moduleId: moduleId,
            formatId: _text(format['id']),
            view: true,
            insert: false,
            update: false,
            delete: false,
            export: false,
            import: false,
            review: false,
            approve: false,
          );
        }
      } else if (scope == 'FORMATO') {
        final format = _formatById(selectedFormatId)!;
        await _upsertFormatPermission(
          userId: userId,
          moduleId: _formatModuleId(format),
          formatId: _text(format['id']),
          view: canView,
          insert: canInsert,
          update: canUpdate,
          delete: canDelete,
          export: canExport,
          import: canImport,
          review: canReview,
          approve: canApprove,
        );
      }
      await _loadUserPermissions(userId);
      final currentUserId = supabase.auth.currentUser?.id;
      final isCurrentUser = currentUserId != null &&
          _candidateUserIds(userId).contains(currentUserId);
      var refreshedCurrentUser = false;
      if (isCurrentUser) {
        try {
          await SyncService().refreshLoginPermissionsOnly();
          refreshedCurrentUser = true;
        } catch (_) {
          // El permiso remoto ya quedó guardado. La actualización manual de
          // datos lo descargará si el refresco inmediato no estuvo disponible.
        }
      }
      if (!mounted) return;
      widget.onChanged?.call();
      _message(refreshedCurrentUser
          ? 'Permiso guardado y actualizado en este dispositivo.'
          : 'Permiso guardado. El usuario debe actualizar datos o volver a ingresar.');
    } catch (error) {
      if (mounted) _message(_permissionSaveError(error));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _removePermission() async {
    final userId = selectedUserId;
    final sectionId = _resolvedSectionId();
    if (userId == null || sectionId == null || sectionId.isEmpty) {
      _message('Seleccione usuario y alcance antes de quitar acceso.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quitar acceso'),
        content: Text(
          scope == 'SECCION'
              ? 'Se quitará la sección y todos sus formatos para este usuario.'
              : scope == 'MODULO'
                  ? 'Se quitarán todos los formatos de este módulo.'
                  : 'Se quitará el acceso al formato seleccionado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Quitar acceso'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => saving = true);
    try {
      if (scope == 'SECCION') {
        final childModules = modules
            .where((module) => _same(_moduleSectionId(module), sectionId));
        for (final module in childModules) {
          final moduleId = _text(module['id']);
          for (final format in _formatsForModule(moduleId)) {
            await _deleteFormatPermission(
              userId,
              moduleId,
              _text(format['id']),
            );
          }
        }
        await _deleteSectionPermission(userId, sectionId);
      } else if (scope == 'MODULO') {
        final moduleId = selectedModuleId!;
        for (final format in _formatsForModule(moduleId)) {
          await _deleteFormatPermission(userId, moduleId, _text(format['id']));
        }
      } else {
        final format = _formatById(selectedFormatId)!;
        await _deleteFormatPermission(
          userId,
          _formatModuleId(format),
          _text(format['id']),
        );
      }
      await _loadUserPermissions(userId);
      if (mounted) _message('Acceso retirado.');
    } catch (error) {
      if (mounted) _message(SyncService().friendlyError(error));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _selectorCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '2. Conceder permiso',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 430;
                Widget label(String text) => Text(
                      text,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: TextStyle(fontSize: compact ? 11.5 : 14),
                    );
                return SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(
                          horizontal: compact ? 5 : 12,
                          vertical: compact ? 11 : 12,
                        ),
                      ),
                      visualDensity: compact
                          ? VisualDensity.compact
                          : VisualDensity.standard,
                    ),
                    segments: [
                      ButtonSegment(
                        value: 'SECCION',
                        icon: Icon(Icons.view_sidebar_outlined,
                            size: compact ? 16 : 19),
                        label: label('Sección'),
                      ),
                      ButtonSegment(
                        value: 'MODULO',
                        icon: Icon(Icons.grid_view_outlined,
                            size: compact ? 16 : 19),
                        label: label('Módulo'),
                      ),
                      ButtonSegment(
                        value: 'FORMATO',
                        icon: Icon(Icons.assignment_outlined,
                            size: compact ? 16 : 19),
                        label: label('Formato'),
                      ),
                    ],
                    selected: {scope},
                    onSelectionChanged: saving
                        ? null
                        : (values) => setState(() {
                              scope = values.first;
                              selectedSectionId = null;
                              selectedModuleId = null;
                              selectedFormatId = null;
                              formatSearch = '';
                              searchController.clear();
                              _applySelectedFormatActions();
                            }),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            if (scope == 'SECCION') _sectionSelector(),
            if (scope == 'MODULO') ...[
              _sectionSelector(),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'permission-module-$selectedSectionId-$selectedModuleId',
                ),
                initialValue: selectedModuleId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Módulo de la sección',
                  prefixIcon: Icon(Icons.grid_view_outlined),
                ),
                items: _modulesForSelectedSection
                    .map((module) => DropdownMenuItem(
                          value: _text(module['id']),
                          child: Text(
                            _text(module['nombre']),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: selectedSectionId == null
                    ? null
                    : (value) => setState(() => selectedModuleId = value),
              ),
              const SizedBox(height: 8),
              const Text(
                'El módulo concede acceso a todos sus formatos. Después puede quitar o ajustar uno desde “Formato”.',
                style: TextStyle(color: Color(0xFF60758A), fontSize: 12),
              ),
            ],
            if (scope == 'FORMATO') _formatSearch(),
          ],
        ),
      ),
    );
  }

  Widget _userSelectorCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '1. Usuario',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey('permission-user-$selectedUserId'),
              initialValue: selectedUserId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Usuario',
                helperText: 'Seleccione la persona a la que dará acceso.',
                prefixIcon: Icon(Icons.person_search_outlined),
              ),
              items: profiles
                  .where((profile) => _profileUserId(profile).isNotEmpty)
                  .map((profile) => DropdownMenuItem(
                        value: _profileUserId(profile),
                        child: Text(
                          _profileLabel(profile),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: saving
                  ? null
                  : (value) async {
                      setState(() => selectedUserId = value);
                      if (value != null) await _loadUserPermissions(value);
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionSelector() {
    return DropdownButtonFormField<String>(
      key: ValueKey('permission-section-$scope-$selectedSectionId'),
      initialValue: selectedSectionId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Sección',
        prefixIcon: Icon(Icons.view_sidebar_outlined),
      ),
      items: sections
          .map((section) => DropdownMenuItem(
                value: _text(section['id']),
                child: Text(
                  _text(section['nombre']),
                  overflow: TextOverflow.ellipsis,
                ),
              ))
          .toList(),
      onChanged: (value) => setState(() {
        selectedSectionId = value;
        selectedModuleId = null;
      }),
    );
  }

  Widget _formatSearch() {
    final selected = _formatById(selectedFormatId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: searchController,
          decoration: const InputDecoration(
            labelText: 'Buscar formato por nombre',
            hintText: 'Escriba el nombre del formato',
            helperText:
                'El resultado indica la sección y el módulo al que pertenece.',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() {
            formatSearch = value;
            if (selected != null && value != _text(selected['nombre'])) {
              selectedFormatId = null;
            }
          }),
        ),
        if (selected != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F3F5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFC8E0E6)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF176B87)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _text(selected['nombre']),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        _formatBreadcrumb(selected),
                        style: const TextStyle(
                            color: Color(0xFF60758A), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ] else if (formatSearch.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFDCE6EC)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _matchingFormats.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('No se encontraron formatos.'),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _matchingFormats.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final format = _matchingFormats[index];
                      return ListTile(
                        leading: const Icon(Icons.assignment_outlined),
                        title: Text(_text(format['nombre'])),
                        subtitle: Text(_formatBreadcrumb(format)),
                        trailing: const Icon(Icons.add_circle_outline),
                        onTap: () => _selectFormat(format),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }

  Widget _actionsCard() {
    if (scope != 'FORMATO' || selectedFormatId == null) {
      return const SizedBox.shrink();
    }
    Widget permissionSwitch(
      String title,
      String subtitle,
      bool value,
      ValueChanged<bool> change,
    ) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: value,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        onChanged: saving ? null : change,
      );
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '3. Acciones permitidas en el formato',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            permissionSwitch(
              'Ver',
              'Consultar el formato y sus registros.',
              canView,
              (value) => setState(() => canView = value),
            ),
            permissionSwitch(
              'Crear y sincronizar',
              'Registrar datos nuevos y enviarlos a la plataforma.',
              canInsert,
              (value) => setState(() => canInsert = value),
            ),
            permissionSwitch(
              'Editar',
              'Modificar registros existentes.',
              canUpdate,
              (value) => setState(() => canUpdate = value),
            ),
            permissionSwitch(
              'Eliminar',
              'Retirar registros cuando el formato lo permita.',
              canDelete,
              (value) => setState(() => canDelete = value),
            ),
            permissionSwitch(
              'Exportar',
              'Descargar registros en archivos.',
              canExport,
              (value) => setState(() => canExport = value),
            ),
            permissionSwitch(
              'Importar',
              'Cargar registros desde archivos.',
              canImport,
              (value) => setState(() => canImport = value),
            ),
            if (_selectedFormatUsesApprovals()) ...[
              permissionSwitch(
                'Revisar',
                'Realizar la primera aprobación y marcar como REVISADO.',
                canReview,
                (value) => setState(() => canReview = value),
              ),
              permissionSwitch(
                'Aprobar',
                'Realizar la aprobación final y marcar como APROBADO.',
                canApprove,
                (value) => setState(() => canApprove = value),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _currentAccessCard() {
    if (selectedUserId == null) return const SizedBox.shrink();
    final access = resolveEffectiveAccessTree(
      sections: sections,
      modules: modules,
      formats: formats,
      sectionPermissions: sectionPermissions,
      formatPermissions: formatPermissions,
    );
    final bySection = access.bySection;

    return Card(
      elevation: 0,
      child: ExpansionTile(
        leading: const Icon(Icons.account_tree_outlined),
        title: const Text(
          'Accesos actuales',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          bySection.isEmpty
              ? 'Este usuario todavía no tiene accesos asignados.'
              : '${bySection.length} sección(es), ${access.moduleCount} módulo(s), ${access.formatCount} formato(s)',
        ),
        children: bySection.isEmpty
            ? const [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child:
                        Text('Use el selector inferior para conceder acceso.'),
                  ),
                ),
              ]
            : bySection.entries.map((sectionEntry) {
                return ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 18),
                  leading: const Icon(Icons.view_sidebar_outlined, size: 20),
                  title: Text(_sectionName(sectionEntry.key)),
                  children: sectionEntry.value.entries.map((moduleEntry) {
                    return ExpansionTile(
                      tilePadding: const EdgeInsets.only(left: 38, right: 18),
                      leading: const Icon(Icons.grid_view_outlined, size: 18),
                      title: Text(_moduleName(moduleEntry.key)),
                      children: moduleEntry.value
                          .map(
                            (format) => ListTile(
                              contentPadding:
                                  const EdgeInsets.only(left: 70, right: 18),
                              leading: const Icon(Icons.assignment_outlined,
                                  size: 18),
                              title: Text(_text(format['nombre'])),
                            ),
                          )
                          .toList(),
                    );
                  }).toList(),
                );
              }).toList(),
      ),
    );
  }

  Widget _body() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 10),
              Text(loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth > ZumacResponsiveLimits.page
            ? ZumacResponsiveLimits.page
            : constraints.maxWidth;
        return Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: contentWidth,
                height: constraints.maxHeight,
                child: ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F5265), Color(0xFF176B87)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Permisos por jerarquía',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'Elija usuario y conceda acceso a una sección, un módulo o un formato específico.',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _userSelectorCard(),
                    if (selectedUserId != null) const SizedBox(height: 12),
                    _currentAccessCard(),
                    if (selectedUserId != null) const SizedBox(height: 12),
                    _selectorCard(),
                    if (scope == 'FORMATO' && selectedFormatId != null) ...[
                      const SizedBox(height: 12),
                      _actionsCard(),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: saving ? null : _removePermission,
                          icon: const Icon(Icons.remove_circle_outline),
                          label: const Text('Quitar acceso'),
                        ),
                        FilledButton.icon(
                          onPressed: saving ? null : _savePermission,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Guardar permiso'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
            if (saving)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x33000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _body();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permisos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: loading || saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _body(),
    );
  }
}
