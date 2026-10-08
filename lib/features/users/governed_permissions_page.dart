import 'dart:convert';

import 'package:flutter/material.dart' hide ScaffoldMessenger;

import '../../core/widgets/responsive_layout.dart';
import '../../core/widgets/zumac_scaffold_messenger.dart';
import 'permission_management_repository.dart';
import 'permission_policy.dart';

class GovernedPermissionsPage extends StatefulWidget {
  const GovernedPermissionsPage({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<GovernedPermissionsPage> createState() =>
      _GovernedPermissionsPageState();
}

class _GovernedPermissionsPageState extends State<GovernedPermissionsPage> {
  final repo = PermissionManagementRepository();
  final userSearch = TextEditingController();
  final formatSearch = TextEditingController();
  Map<String, dynamic> data = {}, access = {};
  String? selectedId;
  String roleFilter = 'TODOS';
  bool loading = true, loadingAccess = false, saving = false;
  String? error;

  String text(dynamic value) => value?.toString().trim() ?? '';
  List<Map<String, dynamic>> maps(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : [];
  Map<String, dynamic> get actor =>
      Map<String, dynamic>.from(data['actor'] as Map? ?? {});
  Map<String, dynamic> get company =>
      Map<String, dynamic>.from(data['empresa'] as Map? ?? {});
  List<Map<String, dynamic>> get users => maps(data['usuarios']);
  List<Map<String, dynamic>> get sections => maps(data['secciones']);
  List<Map<String, dynamic>> get modules => maps(data['modulos']);
  List<Map<String, dynamic>> get formats => maps(data['formatos']);
  List<Map<String, dynamic>> get tools => maps(data['herramientas']);
  String get actorRole => text(actor['rol']).toUpperCase();
  String get targetRole => text(access['rol']).isNotEmpty
      ? text(access['rol']).toUpperCase()
      : text(selectedUser?['rol']).toUpperCase();
  Map<String, dynamic>? get selectedUser {
    for (final user in users) {
      if (text(user['user_id']) == selectedId) return user;
    }
    return null;
  }

  Map<String, PermissionActions> get permissions {
    final result = <String, PermissionActions>{};
    for (final row in maps(access['permisos_formatos'])) {
      result[text(row['formato'])] = PermissionActions.fromMap(row);
    }
    return result;
  }

  Map<String, bool> get toolPermissions {
    final result = <String, bool>{};
    for (final row in maps(access['permisos_herramientas'])) {
      result[text(row['herramienta']).toUpperCase()] =
          row['permitido'] == true || row['can_use'] == true;
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    userSearch.dispose();
    formatSearch.dispose();
    super.dispose();
  }

  Future<void> load({String? keep}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = await repo.loadContext();
      if (!mounted) return;
      final id = keep ?? selectedId;
      final exists =
          maps(next['usuarios']).any((u) => text(u['user_id']) == id);
      setState(() {
        data = next;
        selectedId = exists ? id : null;
        access = {};
        loading = false;
      });
      if (selectedId != null) await selectUser(selectedId!);
    } catch (e) {
      if (mounted)
        setState(() {
          loading = false;
          error = e.toString();
        });
    }
  }

  Future<void> selectUser(String id) async {
    setState(() {
      selectedId = id;
      access = {};
      loadingAccess = true;
    });
    try {
      final next = await repo.loadUserAccess(id);
      if (mounted && selectedId == id)
        setState(() {
          access = next;
          loadingAccess = false;
        });
    } catch (e) {
      if (mounted && selectedId == id) setState(() => loadingAccess = false);
      await message('No se pudo consultar el acceso: $e');
    }
  }

  Future<void> message(String value) async {
    if (mounted)
      await ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> openMetricRequests() async {
    if (saving || actorRole != 'ADMIN') return;
    setState(() => saving = true);
    try {
      final requests = await repo.listMetricRequests();
      if (!mounted) return;
      String? busyId;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Solicitudes de gráficos'),
            content: SizedBox(
              width: 720,
              child: requests.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No hay cambios de Metrics pendientes de aprobación.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: requests.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (_, index) {
                        final item = requests[index];
                        final id = text(item['id']);
                        final waiting = busyId == id;
                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.pending_actions_outlined),
                          ),
                          title: Text(
                            '${text(item['operacion'])} · ${text(item['tipo'])}',
                          ),
                          subtitle: Text(
                            'Solicitado por ${text(item['solicitante'])}',
                          ),
                          trailing: waiting
                              ? const SizedBox.square(
                                  dimension: 24,
                                  child: CircularProgressIndicator(),
                                )
                              : Wrap(
                                  spacing: 6,
                                  children: [
                                    OutlinedButton(
                                      onPressed: () async {
                                        setDialogState(() => busyId = id);
                                        try {
                                          await repo.resolveMetricRequest(
                                            requestId: id,
                                            approve: false,
                                          );
                                          requests.removeAt(index);
                                        } finally {
                                          setDialogState(() => busyId = null);
                                        }
                                      },
                                      child: const Text('Rechazar'),
                                    ),
                                    FilledButton(
                                      onPressed: () async {
                                        setDialogState(() => busyId = id);
                                        try {
                                          await repo.resolveMetricRequest(
                                            requestId: id,
                                            approve: true,
                                          );
                                          requests.removeAt(index);
                                        } finally {
                                          setDialogState(() => busyId = null);
                                        }
                                      },
                                      child: const Text('Aprobar'),
                                    ),
                                  ],
                                ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      await message('No se pudo abrir la bandeja de solicitudes: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> changeRole(String role) async {
    if (selectedId == null || saving) return;
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('Confirmar cambio de rol'),
              content: Text(
                  'Se asignará $role dentro de ${text(company['nombre'])}. Los permisos incompatibles se retirarán.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Asignar'))
              ],
            ));
    if (ok != true) return;
    setState(() => saving = true);
    try {
      await repo.assignRole(userId: selectedId!, role: role);
      if (!mounted) return;
      await load(keep: selectedId);
      await message('Rol asignado correctamente.');
    } catch (e) {
      await message('No se pudo asignar el rol: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  PermissionActions ceiling(Map<String, dynamic> format) =>
      PermissionActions.fromMap(Map<String, dynamic>.from(
          format['acciones_delegables'] as Map? ?? {}));

  List<String> workflowStates(Map<String, dynamic> format) {
    dynamic raw = format['flujo_estados'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        raw = null;
      }
    }
    if (raw is! List) return const <String>[];
    return raw
        .map((value) => value is Map
            ? text(value['codigo'] ?? value['nombre']).toUpperCase()
            : text(value).toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  Future<void> editFormat(Map<String, dynamic> format) async {
    if (selectedId == null || targetRole.isEmpty || saving) return;
    final id = text(format['id']);
    final result = await showDialog<PermissionActions>(
        context: context,
        builder: (_) => _PermissionDialog(
            name: name(format, 'Formato'),
            role: targetRole,
            initial: permissions[id] ?? const PermissionActions(),
            ceiling: ceiling(format),
            workflowStates: workflowStates(format)));
    if (result == null) return;
    setState(() => saving = true);
    try {
      if (result.hasAny) {
        await repo.saveFormatPermissions(
            userId: selectedId!, permissions: [result.toMap(formatId: id)]);
      } else {
        await repo.revokeFormats(userId: selectedId!, formatIds: [id]);
      }
      if (!mounted) return;
      await selectUser(selectedId!);
      setState(() => data['revision_permisos'] =
          (int.tryParse(text(data['revision_permisos'])) ?? 0) + 1);
      await message('Permisos del formato guardados.');
    } catch (e) {
      await message('No se pudieron guardar los permisos: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> editTool(Map<String, dynamic> tool, bool permitted) async {
    if (selectedId == null || saving || tool['delegable'] != true) return;
    final code = text(tool['codigo']).toUpperCase();
    if (code.isEmpty) return;
    setState(() => saving = true);
    try {
      await repo.saveToolPermissions(
        userId: selectedId!,
        permissions: [
          {'herramienta': code, 'permitido': permitted},
        ],
      );
      if (!mounted) return;
      await selectUser(selectedId!);
      await message(
        permitted
            ? 'Herramienta habilitada para el usuario.'
            : 'Acceso a la herramienta retirado.',
      );
    } catch (e) {
      await message('No se pudo guardar el acceso a la herramienta: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> bulk(List<Map<String, dynamic>> scope,
      {required bool revoke}) async {
    if (selectedId == null || scope.isEmpty || saving) return;
    if (revoke) {
      final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                title: const Text('Retirar acceso'),
                content: Text(
                    'Se retirarán todos los permisos de ${scope.length} formatos.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancelar')),
                  FilledButton.tonal(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Retirar'))
                ],
              ));
      if (ok != true) return;
    }
    setState(() => saving = true);
    try {
      if (revoke) {
        await repo.revokeFormats(
            userId: selectedId!,
            formatIds: scope.map((f) => text(f['id'])).toList());
      } else {
        final current = permissions;
        final payload = scope.map((f) {
          final id = text(f['id']),
              old = current[id] ?? const PermissionActions();
          return PermissionActions(
                  view: true,
                  insert: old.insert,
                  update: old.update,
                  delete: old.delete,
                  export: old.export,
                  import: old.import,
                  review: old.review,
                  approve: old.approve,
                  workflowStates: old.workflowStates)
              .normalizedForRole(targetRole)
              .boundedBy(ceiling(f))
              .toMap(formatId: id);
        }).toList();
        await repo.saveFormatPermissions(
            userId: selectedId!, permissions: payload);
      }
      if (!mounted) return;
      await selectUser(selectedId!);
      await message(revoke ? 'Acceso retirado.' : 'Lectura habilitada.');
    } catch (e) {
      await message('No se pudo aplicar el cambio: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
            ? _Error(message: error!, retry: load)
            : content();
    if (widget.embedded) return body;
    return Scaffold(
        appBar: AppBar(title: const Text('Gobierno de accesos')), body: body);
  }

  Widget content() => Stack(children: [
        Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: ZumacResponsiveLimits.page),
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      _Header(
                          company: company,
                          role: actorRole,
                          revision: data['revision_permisos'],
                          requests: actorRole == 'ADMIN' && !saving
                              ? openMetricRequests
                              : null,
                          refresh: saving ? null : load),
                      const SizedBox(height: 12),
                      Expanded(
                          child: LayoutBuilder(
                              builder: (_, box) => box.maxWidth < 820
                                  ? (selectedId == null
                                      ? usersPane()
                                      : accessPane(back: true))
                                  : Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                          SizedBox(
                                              width: 330, child: usersPane()),
                                          const SizedBox(width: 12),
                                          Expanded(child: accessPane())
                                        ]))),
                    ])))),
        if (saving)
          const Positioned.fill(
              child: ColoredBox(
                  color: Color(0x22000000),
                  child: Center(child: CircularProgressIndicator()))),
      ]);

  List<Map<String, dynamic>> get visibleUsers {
    final q = userSearch.text.trim().toLowerCase();
    return users.where((u) {
      final role = text(u['rol']).toUpperCase();
      return (roleFilter == 'TODOS' || role == roleFilter) &&
          (q.isEmpty ||
              [u['nombres'], u['dni'], u['cargo'], u['area'], u['rol']]
                  .map(text)
                  .join(' ')
                  .toLowerCase()
                  .contains(q));
    }).toList();
  }

  Widget usersPane() => Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Personas de la empresa',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)))),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
                controller: userSearch,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Nombre, DNI o cargo',
                    isDense: true))),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            child: Row(
                children: [
              'TODOS',
              'ADMIN',
              'GESTOR',
              'COLABORADOR',
              'VISUALIZADOR'
            ]
                    .map((r) => Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: ChoiceChip(
                            label: Text(r == 'TODOS' ? 'Todos' : roleLabel(r)),
                            selected: roleFilter == r,
                            onSelected: (_) => setState(() => roleFilter = r))))
                    .toList())),
        const Divider(height: 1),
        Expanded(
            child: visibleUsers.isEmpty
                ? const Center(child: Text('No hay personas para mostrar.'))
                : ListView.builder(
                    itemCount: visibleUsers.length,
                    itemBuilder: (_, i) {
                      final u = visibleUsers[i],
                          id = text(u['user_id']),
                          role = text(u['rol']).toUpperCase();
                      return ListTile(
                          selected: id == selectedId,
                          leading: CircleAvatar(
                              child: Text(initials(text(u['nombres'])))),
                          title: Text(
                              text(u['nombres']).isEmpty
                                  ? 'Sin nombre'
                                  : text(u['nombres']),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Wrap(spacing: 6, children: [
                            _RoleBadge(role),
                            Text('${u['cantidad_formatos'] ?? 0} formatos')
                          ]),
                          trailing: u['puede_gestionar'] == true
                              ? const Icon(Icons.chevron_right)
                              : const Icon(Icons.lock_outline, size: 18),
                          onTap: id.isEmpty ? null : () => selectUser(id));
                    }))
      ]));

  Widget accessPane({bool back = false}) {
    final user = selectedUser;
    if (user == null)
      return const Card(
          child: Center(
              child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.manage_accounts_outlined, size: 56),
                    SizedBox(height: 12),
                    Text(
                        'Seleccione una persona para revisar su rol y formatos.')
                  ]))));
    final manageable = user['puede_gestionar'] == true;
    return Card(
        clipBehavior: Clip.antiAlias,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                if (back)
                  IconButton(
                      onPressed: () => setState(() => selectedId = null),
                      icon: const Icon(Icons.arrow_back)),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          text(user['nombres']).isEmpty
                              ? 'Acceso de usuario'
                              : text(user['nombres']),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text([text(user['cargo']), text(user['area'])]
                          .where((e) => e.isNotEmpty)
                          .join(' · '))
                    ])),
                _RoleBadge(targetRole),
              ])),
          const Divider(height: 1),
          if (loadingAccess)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (!manageable)
            Expanded(
                child: Center(
                    child: Padding(
                        padding: const EdgeInsets.all(28),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.admin_panel_settings_outlined,
                              size: 56),
                          const SizedBox(height: 12),
                          Text(
                              targetRole == 'ADMIN'
                                  ? 'La membresía ADMIN está protegida y solo se administra desde Supabase.'
                                  : 'No puede modificar a esta persona desde su nivel de delegación.',
                              textAlign: TextAlign.center)
                        ]))))
          else ...[
            roleSelector(),
            if (targetRole.isEmpty)
              const Expanded(
                  child: Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                              'Asigne primero un rol de empresa. Después podrá habilitar formatos y acciones.',
                              textAlign: TextAlign.center))))
            else
              Expanded(child: formatTree()),
          ]
        ]));
  }

  Widget roleSelector() {
    final roles = delegableRoles(actorRole);
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          const Icon(Icons.badge_outlined),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Rol dentro de esta empresa'),
                Text(roleDescription(targetRole),
                    style: Theme.of(context).textTheme.bodySmall),
              ])),
          DropdownButton<String>(
              hint: const Text('Asignar rol'),
              value: roles.contains(targetRole) ? targetRole : null,
              items: roles
                  .map((r) =>
                      DropdownMenuItem(value: r, child: Text(roleLabel(r))))
                  .toList(),
              onChanged: saving
                  ? null
                  : (v) {
                      if (v != null && v != targetRole) changeRole(v);
                    }),
        ]));
  }

  Widget formatTree() {
    final q = formatSearch.text.trim().toLowerCase(), current = permissions;
    final visible = formats
        .where((f) =>
            q.isEmpty ||
            '${text(f['nombre'])} ${text(f['id'])}'.toLowerCase().contains(q))
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      children: [
        if (tools.isNotEmpty) _toolPermissionsPanel(),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
          child: TextField(
            controller: formatSearch,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.filter_alt_outlined),
              hintText: 'Filtrar formatos',
              helperText:
                  'El alcance termina en formato; no existen permisos por registro.',
              isDense: true,
            ),
          ),
        ),
        ...sections.map((section) {
          final sid = text(section['id']);
          final smods =
              modules.where((m) => text(m['seccion']) == sid).toList();
          final sf = visible
              .where((f) =>
                  smods.any((m) => text(m['id']) == text(f['modulo_id'])))
              .toList();
          if (sf.isEmpty) return const SizedBox.shrink();
          return ExpansionTile(
            initiallyExpanded: q.isNotEmpty,
            leading: const Icon(Icons.account_tree_outlined),
            title: Text(name(section, 'Sección')),
            subtitle: Text('${sf.length} formatos'),
            trailing: _ScopeMenu(
              view: () => bulk(sf, revoke: false),
              revoke: () => bulk(sf, revoke: true),
            ),
            children: smods.map((module) {
              final mid = text(module['id']);
              final mf =
                  visible.where((f) => text(f['modulo_id']) == mid).toList();
              if (mf.isEmpty) return const SizedBox.shrink();
              return ExpansionTile(
                initiallyExpanded: q.isNotEmpty,
                tilePadding: const EdgeInsets.only(left: 32, right: 8),
                leading: const Icon(Icons.folder_outlined),
                title: Text(name(module, 'Módulo')),
                subtitle: Text('${mf.length} formatos'),
                trailing: _ScopeMenu(
                  view: () => bulk(mf, revoke: false),
                  revoke: () => bulk(mf, revoke: true),
                ),
                children: mf.map((f) {
                  final a = current[text(f['id'])] ?? const PermissionActions();
                  return ListTile(
                    contentPadding: const EdgeInsets.only(left: 64, right: 12),
                    leading: Icon(
                      a.view ? Icons.description : Icons.description_outlined,
                    ),
                    title: Text(name(f, 'Formato')),
                    subtitle: _ActionSummary(a),
                    trailing: const Icon(Icons.tune),
                    onTap: () => editFormat(f),
                  );
                }).toList(),
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  Widget _toolPermissionsPanel() {
    final granted = toolPermissions;
    return Card(
      margin: const EdgeInsets.fromLTRB(6, 10, 6, 6),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.widgets_outlined),
        title: const Text('Herramientas de la pantalla principal'),
        subtitle: const Text('Acceso otorgado por ADMIN o GESTOR'),
        children: tools.map((tool) {
          final code = text(tool['codigo']).toUpperCase();
          final available = tool['habilitada_empresa'] == true;
          final delegable = tool['delegable'] == true;
          final permitted = granted[code] == true;
          return SwitchListTile.adaptive(
            dense: true,
            value: permitted,
            onChanged: available && delegable
                ? (value) => editTool(tool, value)
                : null,
            title: Text(text(tool['nombre'])),
            subtitle: Text(
              !available
                  ? 'La herramienta no está contratada para la empresa.'
                  : delegable
                      ? text(tool['descripcion'])
                      : 'Fuera de su alcance de delegación.',
            ),
          );
        }).toList(growable: false),
      ),
    );
  }

  String name(Map<String, dynamic> row, String fallback) =>
      text(row['nombre']).isEmpty
          ? '$fallback ${text(row['id'])}'
          : text(row['nombre']);
  String initials(String value) {
    final words = value.split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    final v = words.take(2).map((e) => e[0]).join().toUpperCase();
    return v.isEmpty ? '?' : v;
  }
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.company,
      required this.role,
      required this.revision,
      required this.requests,
      required this.refresh});
  final Map<String, dynamic> company;
  final String role;
  final dynamic revision;
  final VoidCallback? requests;
  final VoidCallback? refresh;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        const CircleAvatar(child: Icon(Icons.business_outlined)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              company['nombre']?.toString().trim().isNotEmpty == true
                  ? company['nombre'].toString()
                  : 'Empresa activa',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          Text(
              'Usted administra como ${roleLabel(role)} · revisión ${revision ?? 1}',
              style: Theme.of(context).textTheme.bodySmall),
        ])),
        if (requests != null)
          IconButton(
            tooltip: 'Solicitudes de gráficos',
            onPressed: requests,
            icon: const Icon(Icons.pending_actions_outlined),
          ),
        IconButton(
            tooltip: 'Actualizar',
            onPressed: refresh,
            icon: const Icon(Icons.refresh)),
      ]));
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge(this.role);
  final String role;
  @override
  Widget build(BuildContext context) {
    final color = switch (role) {
      'ADMIN' => Colors.deepPurple,
      'GESTOR' => Colors.blue,
      'COLABORADOR' => Colors.teal,
      'VISUALIZADOR' => Colors.orange,
      _ => Colors.grey
    };
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(999)),
        child: Text(role.isEmpty ? 'Sin rol' : roleLabel(role),
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 11)));
  }
}

class _ScopeMenu extends StatelessWidget {
  const _ScopeMenu({required this.view, required this.revoke});
  final VoidCallback view, revoke;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
      tooltip: 'Acciones para todos los formatos',
      onSelected: (v) => v == 'view' ? view() : revoke(),
      itemBuilder: (_) => const [
            PopupMenuItem(
                value: 'view', child: Text('Habilitar lectura en todos')),
            PopupMenuItem(
                value: 'revoke', child: Text('Retirar acceso de todos'))
          ]);
}

class _ActionSummary extends StatelessWidget {
  const _ActionSummary(this.value);
  final PermissionActions value;
  @override
  Widget build(BuildContext context) {
    final labels = [
      if (value.view) 'Ver',
      if (value.insert) 'Agregar',
      if (value.update) 'Editar',
      if (value.delete) 'Eliminar',
      if (value.export) 'Exportar',
      if (value.import) 'Importar',
      if (value.review) 'Revisar',
      if (value.approve) 'Aprobar'
    ];
    return Text(labels.isEmpty ? 'Sin acceso' : labels.join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            color:
                labels.isEmpty ? Theme.of(context).colorScheme.error : null));
  }
}

class _PermissionDialog extends StatefulWidget {
  const _PermissionDialog(
      {required this.name,
      required this.role,
      required this.initial,
      required this.ceiling,
      required this.workflowStates});
  final String name, role;
  final PermissionActions initial, ceiling;
  final List<String> workflowStates;
  @override
  State<_PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<_PermissionDialog> {
  late PermissionActions value;
  @override
  void initState() {
    super.initState();
    value =
        widget.initial.normalizedForRole(widget.role).boundedBy(widget.ceiling);
  }

  void setAction(String action, bool enabled) {
    var next = PermissionActions(
        view: action == 'view' ? enabled : value.view,
        insert: action == 'insert' ? enabled : value.insert,
        update: action == 'update' ? enabled : value.update,
        delete: action == 'delete' ? enabled : value.delete,
        export: action == 'export' ? enabled : value.export,
        import: action == 'import' ? enabled : value.import,
        review: action == 'review' ? enabled : value.review,
        approve: action == 'approve' ? enabled : value.approve,
        workflowStates: value.workflowStates);
    if (action == 'view' && !enabled) next = const PermissionActions();
    setState(() =>
        value = next.normalizedForRole(widget.role).boundedBy(widget.ceiling));
  }

  Widget toggle(String title, String help, String action, bool enabled,
          bool available) =>
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(available
              ? help
              : 'No puede delegar una acción que usted no posee.'),
          value: enabled,
          onChanged: available ? (v) => setAction(action, v) : null);

  WorkflowStateActions _stateValue(String state) {
    final existing = value.workflowStates[state];
    if (existing != null) return existing;
    final terminal = const {'DESPACHADO', 'ANULADO', 'CERRADO'}
        .contains(state.toUpperCase());
    return WorkflowStateActions(
      view: value.view,
      create: !terminal && state.toUpperCase() == 'PENDIENTE' && value.insert,
      update: !terminal && value.update,
      delete: !terminal && value.delete,
    );
  }

  void _setStateAction(String state, String action, bool enabled) {
    final current = _stateValue(state);
    final next = current.copyWith(
      view: action == 'view' ? enabled : null,
      create: action == 'create' ? enabled : null,
      update: action == 'update' ? enabled : null,
      delete: action == 'delete' ? enabled : null,
    );
    final updated = Map<String, WorkflowStateActions>.from(value.workflowStates)
      ..[state] = next;
    setState(() {
      value = PermissionActions(
        view: value.view || next.view,
        insert: value.insert || next.create,
        update: value.update || next.update,
        delete: value.delete || next.delete,
        export: value.export,
        import: value.import,
        review: value.review,
        approve: value.approve,
        workflowStates: updated,
      ).normalizedForRole(widget.role).boundedBy(widget.ceiling);
    });
  }

  Widget _stateCheck(String state, String action, String label, bool checked,
          bool available) =>
      SizedBox(
        width: 112,
        child: CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: checked,
          title: Text(label),
          onChanged: available
              ? (next) => _setStateAction(state, action, next == true)
              : null,
        ),
      );

  Widget _workflowPermissions() {
    if (widget.workflowStates.isEmpty) return const SizedBox.shrink();
    final visualizer = widget.role == 'VISUALIZADOR';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 28),
        Text('Permisos por estado',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'Define exactamente qué registros puede ver, crear, editar o eliminar en cada etapa.',
        ),
        const SizedBox(height: 10),
        for (final state in widget.workflowStates)
          Card.outlined(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(state,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Wrap(
                    spacing: 4,
                    runSpacing: 0,
                    children: [
                      _stateCheck(state, 'view', 'Ver', _stateValue(state).view,
                          widget.ceiling.view),
                      if (!visualizer)
                        _stateCheck(state, 'create', 'Crear',
                            _stateValue(state).create, widget.ceiling.insert),
                      if (!visualizer)
                        _stateCheck(state, 'update', 'Editar',
                            _stateValue(state).update, widget.ceiling.update),
                      if (!visualizer)
                        _stateCheck(state, 'delete', 'Eliminar',
                            _stateValue(state).delete, widget.ceiling.delete),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final visualizer = widget.role == 'VISUALIZADOR',
        collaborator = widget.role == 'COLABORADOR';
    return AlertDialog(
        title: Text(widget.name),
        content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Text(
                      '${roleLabel(widget.role)} · alcance únicamente en este formato.'),
                  const SizedBox(height: 10),
                  toggle('Ver', 'Consultar el formato y sus registros.', 'view',
                      value.view, widget.ceiling.view),
                  if (!visualizer) ...[
                    toggle('Agregar', 'Crear registros.', 'insert',
                        value.insert, widget.ceiling.insert),
                    toggle('Editar', 'Modificar registros.', 'update',
                        value.update, widget.ceiling.update),
                    toggle('Eliminar', 'Retirar registros.', 'delete',
                        value.delete, widget.ceiling.delete),
                    toggle('Exportar', 'Descargar información.', 'export',
                        value.export, widget.ceiling.export),
                    toggle('Importar', 'Cargar información.', 'import',
                        value.import, widget.ceiling.import),
                  ],
                  if (!visualizer && !collaborator) ...[
                    toggle('Revisar', 'Marcar información como revisada.',
                        'review', value.review, widget.ceiling.review),
                    toggle('Aprobar', 'Aprobar información.', 'approve',
                        value.approve, widget.ceiling.approve),
                  ],
                  _workflowPermissions(),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, const PermissionActions()),
              child: const Text('Retirar acceso')),
          FilledButton(
              onPressed: () => Navigator.pop(context, value),
              child: const Text('Guardar')),
        ]);
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline,
                size: 52, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            const Text('No se pudo cargar el gobierno de accesos.'),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar')),
          ])));
}

String roleLabel(String role) => switch (role.toUpperCase()) {
      'ADMIN' => 'Administrador',
      'GESTOR' => 'Gestor',
      'COLABORADOR' => 'Colaborador',
      'VISUALIZADOR' => 'Visualizador',
      _ => 'Sin rol'
    };

String roleDescription(String role) => switch (role.toUpperCase()) {
      'GESTOR' => 'Delega su propio alcance a colaboradores y visualizadores.',
      'COLABORADOR' => 'Opera solamente las acciones habilitadas por formato.',
      'VISUALIZADOR' => 'Solo consulta los formatos habilitados.',
      'ADMIN' => 'Administra exclusivamente la empresa asignada.',
      _ => 'Todavía no tiene un rol operativo.'
    };
