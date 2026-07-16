import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/local_db.dart';
import '../../core/services/local_session.dart';
import '../../core/services/sync_service.dart';

class UsersPage extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onChanged;

  const UsersPage({super.key, this.embedded = false, this.onChanged});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final local = LocalDb.instance;
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> modules = [];
  List<Map<String, dynamic>> formats = [];
  List<Map<String, dynamic>> sections = [];
  List<Map<String, dynamic>> profiles = [];
  List<Map<String, dynamic>> memberships = [];

  String? selectedUserId;
  String? activeEmpresaId;
  String currentActorRole = '';
  String selectedRole = 'COLABORADOR';
  final selectedFormats = <String>{};
  final originalFormats = <String>{};
  final selectedSections = <String>{};

  bool canView = true;
  bool canInsert = true;
  bool canUpdate = false;
  bool canDelete = false;

  bool loading = true;
  bool saving = false;
  String? loadError;

  bool get canAssignRoles => currentActorRole == 'ADMIN';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  Future<List<Map<String, dynamic>>> _selectRemoteRows({
    required String table,
    String orderBy = 'orden',
  }) async {
    final rows = await supabase.from(table).select().order(orderBy);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      loadError = null;
    });

    try {
      if (!await _hasInternet()) {
        if (!mounted) return;
        setState(() {
          loading = false;
          loadError = 'Conéctese a internet para administrar permisos.';
          modules = [];
          formats = [];
          sections = [];
          profiles = [];
        });
        return;
      }

      var remoteModules = <Map<String, dynamic>>[];
      var remoteFormats = <Map<String, dynamic>>[];
      var remoteSections = <Map<String, dynamic>>[];
      var remoteProfiles = <Map<String, dynamic>>[];
      var remoteMemberships = <Map<String, dynamic>>[];
      final empresaId = await LocalSession().cachedEmpresaId();
      final warnings = <String>[];

      if (empresaId.trim().isNotEmpty) {
        try {
          final rows = await supabase.from('USUARIOS_EMPRESAS_APPGT').select().eq('empresa_id', empresaId);
          remoteMemberships = List<Map<String, dynamic>>.from(rows);
        } catch (e) {
          warnings.add(
            'No se pudieron cargar los roles de la empresa: ${SyncService().friendlyError(e)}',
          );
        }
      }

      try {
        remoteModules = await _selectRemoteRows(table: 'MATRIZ_MODULOS_APPGT');
      } catch (e) {
        warnings.add('No se pudieron cargar módulos desde Supabase: ${SyncService().friendlyError(e)}');
        remoteModules = await local.getAll('local_modules', orderBy: 'orden');
      }

      try {
        remoteFormats = await _selectRemoteRows(table: 'MATRIZ_FORMATOS_APPGT');
      } catch (e) {
        warnings.add('No se pudieron cargar formatos desde Supabase: ${SyncService().friendlyError(e)}');
        remoteFormats = await local.getAll('local_formats', orderBy: 'orden');
      }

      try {
        remoteSections = await _selectRemoteRows(table: 'MATRIZ_SECCIONES_APPGT');
      } catch (e) {
        warnings.add('No se pudieron cargar secciones desde Supabase: ${SyncService().friendlyError(e)}');
        remoteSections = await local.getAll('local_sections', orderBy: 'orden');
      }

      try {
        final rows = await supabase.rpc('appgt_admin_list_profiles');
        remoteProfiles = List<Map<String, dynamic>>.from(rows);
      } catch (_) {
        try {
          final rows = await supabase.from('PERFILES_DE_USUARIOS_APPGT').select().order('nombres');
          remoteProfiles = List<Map<String, dynamic>>.from(rows);
        } catch (e) {
          warnings.add('No se pudieron cargar usuarios administrables: ${SyncService().friendlyError(e)}');
        }
      }

      if (!mounted) return;
      final actorId = supabase.auth.currentUser?.id;
      final actorMembership = remoteMemberships.where(
        (row) => row['user_id']?.toString() == actorId,
      );
      setState(() {
        modules = remoteModules.where((e) => e['activo'] != false && e['activo'] != 0).toList();
        formats = remoteFormats.where((e) => e['activo'] != false && e['activo'] != 0).toList();
        sections = remoteSections.where((e) => e['activo'] != false && e['activo'] != 0).toList();
        profiles = remoteProfiles.where((e) => e['activo'] != false && e['activo'] != 0).toList();
        memberships = remoteMemberships;
        activeEmpresaId = empresaId;
        currentActorRole = actorMembership.isEmpty ? '' : actorMembership.first['rol']?.toString().toUpperCase() ?? '';
        loading = false;
        loadError = warnings.isEmpty ? null : warnings.join('\n');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        loadError = 'No se pudieron cargar datos de administración: ${SyncService().friendlyError(e)}';
      });
    }
  }

  List<Map<String, dynamic>> _formatsFor(String moduleId) {
    return formats.where((f) => f['modulo_id']?.toString() == moduleId).toList();
  }

  String _profileLabel(Map<String, dynamic> profile) {
    final dni = profile['DNI']?.toString().trim();
    final name = profile['nombres']?.toString().trim();
    if (dni != null && dni.isNotEmpty && name != null && name.isNotEmpty) return '$dni - $name';
    if (name != null && name.isNotEmpty) return name;
    if (dni != null && dni.isNotEmpty) return dni;
    return profile['user_id']?.toString() ?? profile['id']?.toString() ?? 'Usuario sin datos';
  }

  bool _boolValue(dynamic value) {
    if (value == true) return true;
    if (value == false || value == null) return false;
    final s = value.toString().trim().toUpperCase();
    return s == 'TRUE' || s == '1' || s == 'SI' || s == 'SÍ' || s == 'YES';
  }

  String _norm(dynamic value) => (value ?? '').toString().trim().toLowerCase();

  String _permissionKey(dynamic modulo, dynamic formato) => '${_norm(modulo)}::${_norm(formato)}';

  String _profileUserId(Map<String, dynamic> profile) {
    const keys = [
      'user_id',
      'usuario_id',
      'auth_user_id',
      'auth_id',
      'uid',
      'id_usuario',
      'id',
    ];
    for (final key in keys) {
      final value = profile[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  Map<String, dynamic>? _selectedProfile() {
    final id = selectedUserId;
    if (id == null || id.isEmpty) return null;
    for (final p in profiles) {
      if (_profileUserId(p) == id) return p;
    }
    return null;
  }

  Map<String, dynamic>? _membershipForUser(String userId) {
    for (final membership in memberships) {
      if (membership['user_id']?.toString() == userId && membership['empresa_id']?.toString() == activeEmpresaId) {
        return membership;
      }
    }
    return null;
  }

  String _roleDescription(String role) {
    switch (role) {
      case 'ADMIN':
        return 'Administra roles, configura y publica cambios.';
      case 'GESTOR':
        return 'Prepara configuraciones, pero no las publica.';
      case 'VISUALIZADOR':
        return 'Consulta únicamente lo que tenga permitido.';
      default:
        return 'Trabaja con los formatos y acciones que se le asignen.';
    }
  }

  Future<void> _saveSelectedRole(String userId) async {
    if (!canAssignRoles || activeEmpresaId == null) return;
    final actorId = supabase.auth.currentUser?.id;
    if (userId == actorId && selectedRole != 'ADMIN') {
      throw StateError(
        'No puede quitarse su propio rol ADMIN desde esta pantalla.',
      );
    }

    final existing = _membershipForUser(userId);
    final payload = <String, dynamic>{
      'user_id': userId,
      'empresa_id': activeEmpresaId,
      'rol': selectedRole,
      'activo': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (existing == null) {
      payload['es_predeterminada'] = false;
      await supabase.from('USUARIOS_EMPRESAS_APPGT').insert(payload);
      memberships.add(Map<String, dynamic>.from(payload));
    } else {
      await supabase.from('USUARIOS_EMPRESAS_APPGT').update(payload).eq('id', existing['id']);
      existing.addAll(payload);
    }
  }

  List<String> _candidateUserIds(String userId) {
    final result = <String>{userId.trim()};
    final profile = _selectedProfile();
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
        final value = profile[key]?.toString().trim();
        if (value != null && value.isNotEmpty) result.add(value);
      }
    }
    result.removeWhere((e) => e.isEmpty);
    return result.toList();
  }

  Future<List<Map<String, dynamic>>> _listPermissionsForUser(String userId) async {
    final candidates = _candidateUserIds(userId);
    final byKey = <String, Map<String, dynamic>>{};

    for (final candidate in candidates) {
      try {
        final rows = await supabase.rpc(
          'appgt_admin_list_user_permissions',
          params: {'p_user_id': candidate},
        );
        for (final row in List<Map<String, dynamic>>.from(rows)) {
          final key = _permissionKey(row['modulo'], row['formato']);
          if (key != '::') byKey[key] = row;
        }
        if (byKey.isNotEmpty) return byKey.values.toList();
      } catch (_) {
        // Si la RPC está mal declarada o no existe, usamos la tabla real.
      }

      try {
        final rows = await supabase.from('PERMISOS_DE_USUARIOS_APPGT').select().eq('user_id', candidate);
        for (final row in List<Map<String, dynamic>>.from(rows)) {
          final key = _permissionKey(row['modulo'], row['formato']);
          if (key != '::') byKey[key] = row;
        }
        if (byKey.isNotEmpty) return byKey.values.toList();
      } catch (_) {
        // Continuar probando otros posibles identificadores del perfil.
      }
    }

    return byKey.values.toList();
  }

  Future<void> _loadPermissionsForUser(String userId) async {
    final membership = _membershipForUser(userId);
    setState(() {
      selectedFormats.clear();
      originalFormats.clear();
      selectedSections.clear();
      canView = true;
      canInsert = true;
      canUpdate = false;
      canDelete = false;
      selectedRole = membership?['rol']?.toString().toUpperCase() ?? 'COLABORADOR';
    });

    try {
      final modulePermissions = await _listPermissionsForUser(userId);

      if (!mounted) return;
      setState(() {
        for (final p in modulePermissions) {
          final visible = _boolValue(p['can_view']);

          final posiblesModulos = [
            p['modulo'],
            p['modulo_id'],
            p['seccion'],
            p['module'],
          ];

          final posiblesFormatos = [
            p['formato'],
            p['formato_id'],
            p['tabla_destino'],
            p['format'],
          ];

          if (visible) {
            for (final m in posiblesModulos) {
              for (final f in posiblesFormatos) {
                final mk = m?.toString();
                final fk = f?.toString();

                if (mk != null && mk.trim().isNotEmpty && fk != null && fk.trim().isNotEmpty) {
                  selectedFormats.add(_permissionKey(mk, fk));
                }
              }
            }
          }
        }
        originalFormats
          ..clear()
          ..addAll(selectedFormats);

        if (modulePermissions.isNotEmpty) {
          canView = modulePermissions.any((p) => _boolValue(p['can_view']));
          canInsert = modulePermissions.any((p) => _boolValue(p['can_insert']));
          canUpdate = modulePermissions.any((p) => _boolValue(p['can_update']));
          canDelete = modulePermissions.any((p) => _boolValue(p['can_delete']));
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar permisos actuales: ${SyncService().friendlyError(e)}')),
      );
    }
  }

  Future<void> _upsertModulePermission(Map<String, dynamic> row) async {
    try {
      await supabase.rpc(
        'appgt_admin_upsert_user_permission',
        params: {
          'p_user_id': row['user_id'],
          'p_modulo': row['modulo'],
          'p_formato': row['formato'],
          'p_can_view': row['can_view'],
          'p_can_insert': row['can_insert'],
          'p_can_update': row['can_update'],
          'p_can_delete': row['can_delete'],
        },
      );
      return;
    } catch (_) {
      // Respaldo directo: mantiene sincronía con PERMISOS_DE_USUARIOS_APPGT
      // aunque la RPC esté desactualizada o mal declarada en Supabase.
    }

    final existing = await supabase
        .from('PERMISOS_DE_USUARIOS_APPGT')
        .select('id')
        .eq('user_id', row['user_id'])
        .eq('modulo', row['modulo'])
        .eq('formato', row['formato'])
        .maybeSingle();

    final payload = {
      'user_id': row['user_id'],
      'modulo': row['modulo'],
      'formato': row['formato'],
      'can_view': row['can_view'],
      'can_insert': row['can_insert'],
      'can_update': row['can_update'],
      'can_delete': row['can_delete'],
    };

    if (existing != null && existing['id'] != null) {
      await supabase.from('PERMISOS_DE_USUARIOS_APPGT').update(payload).eq('id', existing['id']);
    } else {
      await supabase.from('PERMISOS_DE_USUARIOS_APPGT').insert(payload);
    }
  }

  Future<void> _deleteModulePermission({
    required String userId,
    required String modulo,
    required String formato,
  }) async {
    try {
      await supabase.rpc(
        'appgt_admin_delete_user_permission',
        params: {
          'p_user_id': userId,
          'p_modulo': modulo,
          'p_formato': formato,
        },
      );
      return;
    } catch (_) {
      // Respaldo directo si la RPC no está disponible.
    }

    await supabase.from('PERMISOS_DE_USUARIOS_APPGT').delete().eq('user_id', userId).eq('modulo', modulo).eq('formato', formato);
  }

  Future<void> _save() async {
    final userId = selectedUserId;
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona un usuario.')));
      return;
    }

    if (!await _hasInternet()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conéctese a internet para administrar permisos.')),
      );
      return;
    }

    setState(() => saving = true);
    try {
      await _saveSelectedRole(userId);
      final removed = originalFormats.difference(selectedFormats);

      for (final key in removed) {
        final parts = key.split('::');
        if (parts.length != 2) continue;
        await _deleteModulePermission(
          userId: userId,
          modulo: parts[0],
          formato: parts[1],
        );
      }

      for (final key in selectedFormats) {
        final parts = key.split('::');
        if (parts.length != 2) continue;
        await _upsertModulePermission({
          'user_id': userId,
          'modulo': parts[0],
          'formato': parts[1],
          'can_view': canView,
          'can_insert': canInsert,
          'can_update': canUpdate,
          'can_delete': canDelete,
        });
      }

      originalFormats
        ..clear()
        ..addAll(selectedFormats);

      if (userId == supabase.auth.currentUser?.id) {
        await SyncService().downloadCatalogs();
      }

      if (!mounted) return;
      widget.onChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rol y permisos actualizados. El usuario debe actualizar datos o volver a iniciar sesión.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudieron guardar el rol o los permisos: ${SyncService().friendlyError(e)}')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _permissionSwitch({required String label, required bool value, required ValueChanged<bool> onChanged}) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      value: value,
      onChanged: saving ? null : onChanged,
    );
  }

  String _sectionName(Map<String, dynamic> section) => section['nombre']?.toString() ?? section['id']?.toString() ?? 'Sección';

  @override
  Widget build(BuildContext context) {
    final body = loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(14),
            children: [
              if (loadError != null) ...[
                Card(
                  color: const Color(0xFFFFF3E0),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(loadError!, style: const TextStyle(fontSize: 12.5)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              DropdownButtonFormField<String>(
                value: selectedUserId,
                decoration: const InputDecoration(
                  labelText: 'Usuario',
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.person_search),
                ),
                items: profiles.map((profile) {
                  final id = _profileUserId(profile);
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Text(_profileLabel(profile), overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (value) async {
                  setState(() => selectedUserId = value);
                  if (value != null) await _loadPermissionsForUser(value);
                },
              ),
              const SizedBox(height: 12),
              if (selectedUserId != null) ...[
                Card(
                  elevation: 0,
                  color: const Color(0xFFEAF4F6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFC8E0E6)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.badge_outlined, color: Color(0xFF176B87)),
                            SizedBox(width: 8),
                            Text(
                              'Rol general en la empresa',
                              style: TextStyle(
                                color: Color(0xFF17324D),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: selectedRole,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Rol',
                            prefixIcon: const Icon(Icons.admin_panel_settings_outlined),
                            helperText: canAssignRoles ? _roleDescription(selectedRole) : 'Solo un ADMIN puede cambiar roles.',
                          ),
                          items: const [
                            DropdownMenuItem(value: 'ADMIN', child: Text('Administrador')),
                            DropdownMenuItem(value: 'GESTOR', child: Text('Gestor')),
                            DropdownMenuItem(value: 'COLABORADOR', child: Text('Colaborador')),
                            DropdownMenuItem(value: 'VISUALIZADOR', child: Text('Visualizador')),
                          ],
                          onChanged: !canAssignRoles || selectedUserId == supabase.auth.currentUser?.id
                              ? null
                              : (value) => setState(() {
                                    selectedRole = value ?? 'COLABORADOR';
                                  }),
                        ),
                        if (selectedUserId == supabase.auth.currentUser?.id && canAssignRoles)
                          const Padding(
                            padding: EdgeInsets.only(top: 7),
                            child: Text(
                              'Tu propio rol ADMIN está protegido para evitar perder el acceso de administración.',
                              style: TextStyle(
                                color: Color(0xFF60758A),
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Acciones permitidas en los formatos', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      _permissionSwitch(label: 'Ver', value: canView, onChanged: (v) => setState(() => canView = v)),
                      _permissionSwitch(label: 'Insertar', value: canInsert, onChanged: (v) => setState(() => canInsert = v)),
                      _permissionSwitch(label: 'Actualizar', value: canUpdate, onChanged: (v) => setState(() => canUpdate = v)),
                      _permissionSwitch(label: 'Eliminar', value: canDelete, onChanged: (v) => setState(() => canDelete = v)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Formatos', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final module in modules) ...[
                Card(
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                    title: Text('${module['nombre']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text('${module['id']}', style: const TextStyle(fontSize: 11)),
                    children: [
                      for (final format in _formatsFor(module['id']?.toString() ?? ''))
                        CheckboxListTile(
                          dense: true,
                          value: selectedFormats.contains(_permissionKey(module['id'], format['id'])),
                          title: Text('${format['nombre']}', style: const TextStyle(fontSize: 13)),
                          subtitle: Text('${format['id']}', style: const TextStyle(fontSize: 11)),
                          onChanged: selectedUserId == null
                              ? null
                              : (value) {
                                  final key = _permissionKey(module['id'], format['id']);
                                  setState(() {
                                    if (value == true) {
                                      selectedFormats.add(key);
                                    } else {
                                      selectedFormats.remove(key);
                                    }
                                  });
                                },
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: saving ? null : _save,
                icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                label: Text(saving ? 'Guardando...' : 'Guardar rol y permisos'),
              ),
            ],
          );

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 16, 0),
              child: IconButton(
                tooltip: 'Actualizar lista',
                onPressed: loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Usuarios, roles y permisos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar lista',
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
    );
  }
}
