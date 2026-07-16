import 'package:flutter/material.dart';

import 'configuration_admin_repository.dart';
import 'configuration_entity_wizard_page.dart';
import 'configuration_preview_page.dart';
import 'format_structure_wizard_page.dart';
import '../users/users_page.dart';

class ConfigurationAdminPage extends StatefulWidget {
  const ConfigurationAdminPage({super.key});

  @override
  State<ConfigurationAdminPage> createState() => _ConfigurationAdminPageState();
}

class _ConfigurationAdminPageState extends State<ConfigurationAdminPage> {
  final repository = ConfigurationAdminRepository();

  bool loading = true;
  bool actionRunning = false;
  bool publicationPendingSync = false;
  String? error;
  Map<String, dynamic> contextData = {};
  List<Map<String, dynamic>> drafts = [];
  List<Map<String, dynamic>> publishedConfigurations = [];
  String publishedSearch = '';

  bool get canManage => contextData['puede_gestionar'] == true;
  bool get canPublish => contextData['puede_publicar'] == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loadedContext = await repository.loadContext();
      final loadedDrafts = loadedContext['puede_gestionar'] == true
          ? await repository.listDrafts()
          : <Map<String, dynamic>>[];
      final loadedPublished = loadedContext['puede_gestionar'] == true
          ? await repository.listPublishedNavigation()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        contextData = loadedContext;
        drafts = loadedDrafts;
        publishedConfigurations = loadedPublished;
        loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        error = 'No se pudo abrir el constructor: $exception';
        loading = false;
      });
    }
  }

  Future<void> _openPreview(Map<String, dynamic> template) async {
    final draft = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ConfigurationPreviewPage(
          template: template,
          canCreateVersion: canManage,
          repository: repository,
        ),
      ),
    );
    if (draft != null && mounted) {
      await _openWizard(
        draft['entidad_tipo']?.toString() ?? '',
        draft: draft,
      );
    } else {
      await _load();
    }
  }

  Future<void> _openWizard(
    String entityType, {
    Map<String, dynamic>? draft,
  }) async {
    final page = entityType == 'FORMATO'
        ? FormatStructureWizardPage(
            contextData: contextData,
            initialDraft: draft,
            repository: repository,
          )
        : ConfigurationEntityWizardPage(
            entityType: entityType,
            contextData: contextData,
            initialDraft: draft,
            repository: repository,
          );
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => page,
      ),
    );
    if (published == true) publicationPendingSync = true;
    await _load();
  }

  Future<void> _openUsersAndPermissions() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const UsersPage()),
    );
  }

  Future<void> _validateDraft(Map<String, dynamic> draft) async {
    final id = draft['id']?.toString();
    if (id == null) return;
    setState(() => actionRunning = true);
    try {
      final validation = draft['entidad_tipo'] == 'FORMATO'
          ? await repository.validateFormatStructure(id)
          : await repository.validateDraft(id);
      if (!mounted) return;
      final valid = validation['valido'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            valid
                ? 'Borrador válido y listo para publicar.'
                : 'El borrador todavía tiene errores.',
          ),
        ),
      );
      await _load();
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo validar: $exception')),
      );
    } finally {
      if (mounted) setState(() => actionRunning = false);
    }
  }

  Future<void> _publishDraft(Map<String, dynamic> draft) async {
    final id = draft['id']?.toString();
    if (id == null || !canPublish) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar publicación'),
        content: Text(
          'Se publicará ${draft['entidad_tipo']} “${draft['nombre']}” y se creará una nueva versión de configuración.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.publish_outlined),
            label: const Text('Publicar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => actionRunning = true);
    try {
      final result = draft['entidad_tipo'] == 'FORMATO'
          ? await repository.publishFormatStructure(
              id,
              notes:
                  'Publicación atómica desde el panel del constructor visual.',
            )
          : await repository.publishDraft(
              id,
              notes: 'Publicación desde el panel del constructor visual.',
            );
      if (!mounted) return;
      if (result['publicado'] == true) {
        publicationPendingSync = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuración publicada.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['error']?.toString() ?? 'La publicación fue rechazada.',
            ),
          ),
        );
      }
      await _load();
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo publicar: $exception')),
      );
    } finally {
      if (mounted) setState(() => actionRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FA),
      appBar: AppBar(
        title: const Text('Constructor visual'),
        actions: [
          IconButton(
            tooltip: 'Actualizar panel',
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? _errorPanel()
              : !canManage
                  ? _accessDenied()
                  : Stack(
                      children: [
                        RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              _constructorGuide(),
                              if (publicationPendingSync) ...[
                                const SizedBox(height: 14),
                                _syncNotice(),
                              ],
                              const SizedBox(height: 14),
                              _entityActions(),
                              const SizedBox(height: 18),
                              _managementPanel(),
                              const SizedBox(height: 22),
                              _publishedPanel(),
                              const SizedBox(height: 24),
                              _draftsHeader(),
                              const SizedBox(height: 10),
                              if (drafts.isEmpty)
                                _emptyDrafts()
                              else
                                ...drafts.map(_draftCard),
                            ],
                          ),
                        ),
                        if (actionRunning)
                          const ColoredBox(
                            color: Color(0x33000000),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
    );
  }

  Widget _constructorGuide() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '¿Qué deseas configurar?',
          style: TextStyle(
            color: Color(0xFF17324D),
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'La plataforma se organiza de lo general a lo específico:',
          style: TextStyle(color: Color(0xFF60758A), fontSize: 13),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F3F5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC8E0E6)),
          ),
          child: const Row(
            children: [
              Icon(Icons.account_tree_outlined, color: Color(0xFF176B87)),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Rubro  →  Sección  →  Módulo  →  Formato',
                  maxLines: 2,
                  style: TextStyle(
                    color: Color(0xFF315B68),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _syncNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6DE),
        border: Border.all(color: const Color(0xFFE7C96A)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.sync_outlined, color: Color(0xFF8A6815)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'La publicación terminó. Vuelva al menú principal y use “Actualizar datos” para descargar la nueva navegación.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _entityActions() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth >= 900
            ? (constraints.maxWidth - 30) / 3
            : constraints.maxWidth >= 560
                ? (constraints.maxWidth - 14) / 2
                : constraints.maxWidth;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _entityCard(
              width: cardWidth,
              step: 1,
              title: 'Rubro',
              description:
                  'Área principal del negocio. Ej.: Agricultura o Transporte.',
              count: _templateCount('RUBRO'),
              enabled: true,
              onTap: () => _openWizard('RUBRO'),
            ),
            _entityCard(
              width: cardWidth,
              step: 2,
              title: 'Sección',
              description:
                  'Grupo visible en el menú. Ej.: Operaciones o Calidad.',
              count: _templateCount('SECCION'),
              enabled: true,
              onTap: () => _openWizard('SECCION'),
            ),
            _entityCard(
              width: cardWidth,
              step: 3,
              title: 'Módulo',
              description: 'Agrupa procesos o formularios relacionados.',
              count: _templateCount('MODULO'),
              enabled: true,
              onTap: () => _openWizard('MODULO'),
            ),
            _entityCard(
              width: cardWidth,
              step: 4,
              title: 'Formato',
              description:
                  'Crea el formulario, su tabla, campos, listas y reglas.',
              count: _templateCount('FORMATO'),
              enabled: true,
              onTap: () => _openWizard('FORMATO'),
            ),
          ],
        );
      },
    );
  }

  int _templateCount(String type) {
    final summary = contextData['resumen_plantillas'];
    if (summary is! Map) return 0;
    return int.tryParse('${summary[type] ?? 0}') ?? 0;
  }

  Widget _publishedPanel() {
    final normalizedSearch = publishedSearch.trim().toLowerCase();
    final filtered = publishedConfigurations.where((row) {
      if (normalizedSearch.isEmpty) return true;
      return (row['nombre']?.toString().toLowerCase() ?? '')
              .contains(normalizedSearch) ||
          (row['codigo']?.toString().toLowerCase() ?? '')
              .contains(normalizedSearch) ||
          (row['entidad_tipo']?.toString().toLowerCase() ?? '')
              .contains(normalizedSearch);
    }).toList();
    final visible = filtered.take(40).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Editar u ocultar existentes',
                style: TextStyle(
                  color: Color(0xFF17324D),
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text('${publishedConfigurations.length} elemento(s)'),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Toca un elemento para ver su estructura, historial, editarlo o desactivarlo sin borrar sus datos.',
          style: TextStyle(color: Color(0xFF60758A), fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Buscar rubro, sección, módulo o formato',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => setState(() => publishedSearch = value),
        ),
        const SizedBox(height: 10),
        if (visible.isEmpty)
          const Card(
            elevation: 0,
            child: ListTile(
              leading: Icon(Icons.search_off_outlined),
              title: Text('No se encontraron configuraciones.'),
            ),
          )
        else
          Card(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < visible.length; index++) ...[
                  ListTile(
                    leading: CircleAvatar(
                      child: Icon(
                        _entityIcon(
                          visible[index]['entidad_tipo']?.toString() ?? '',
                        ),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      visible[index]['nombre']?.toString() ?? 'Sin nombre',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${visible[index]['entidad_tipo'] ?? ''} · ${visible[index]['codigo'] ?? ''} · v${visible[index]['version'] ?? 1}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: actionRunning
                        ? null
                        : () => _openPreview(visible[index]),
                  ),
                  if (index < visible.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        if (filtered.length > visible.length)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Se muestran 40 de ${filtered.length}. Escriba un nombre o código para filtrar.',
              style: const TextStyle(color: Color(0xFF60758A)),
            ),
          ),
      ],
    );
  }

  Widget _entityCard({
    required double width,
    required int step,
    required String title,
    required String description,
    required int count,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFDCE6EC)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: enabled
                      ? const Color(0xFFE5F2F5)
                      : const Color(0xFFF0F1F2),
                  child: Text(
                    '$step',
                    style: TextStyle(
                      color: enabled ? const Color(0xFF176B87) : Colors.grey,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF17324D),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: const TextStyle(
                            color: Color(0xFF60758A), fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        enabled
                            ? '$count existente(s) · reutilizables'
                            : 'Disponible en la siguiente etapa',
                        style: TextStyle(
                          color:
                              enabled ? const Color(0xFF176B87) : Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      enabled
                          ? Icons.arrow_forward_rounded
                          : Icons.lock_clock_outlined,
                      color: enabled ? const Color(0xFF176B87) : Colors.grey,
                    ),
                    if (enabled)
                      const Text(
                        'Crear',
                        style: TextStyle(
                          color: Color(0xFF176B87),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _managementPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Administración',
          style: TextStyle(
            color: Color(0xFF17324D),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFDCE6EC)),
          ),
          child: ListTile(
            enabled: canPublish,
            onTap: canPublish ? _openUsersAndPermissions : null,
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE5F2F5),
              foregroundColor: Color(0xFF176B87),
              child: Icon(Icons.manage_accounts_outlined),
            ),
            title: const Text(
              'Usuarios, roles y permisos',
              style: TextStyle(
                color: Color(0xFF17324D),
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: const Text(
              'Define quién puede ver, crear, editar o eliminar registros. Solo ADMIN.',
            ),
            trailing: Icon(
              canPublish ? Icons.chevron_right : Icons.lock_outline,
            ),
          ),
        ),
      ],
    );
  }

  Widget _draftsHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Borradores y publicaciones',
            style: TextStyle(
              color: Color(0xFF17324D),
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text('${drafts.length} elemento(s)'),
      ],
    );
  }

  Widget _draftCard(Map<String, dynamic> draft) {
    final state = draft['estado']?.toString() ?? 'BORRADOR';
    final entityType = draft['entidad_tipo']?.toString() ?? '';
    final validation = draft['validacion'] is Map
        ? Map<String, dynamic>.from(draft['validacion'] as Map)
        : <String, dynamic>{};
    final valid = validation['valido'] == true;
    final editable = state != 'PUBLICADO' && state != 'ARCHIVADO';
    final supported = entityType == 'RUBRO' ||
        entityType == 'SECCION' ||
        entityType == 'MODULO' ||
        entityType == 'FORMATO';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFDCE6EC)),
      ),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: _stateColor(state).withValues(alpha: 0.14),
          child: Icon(_entityIcon(entityType), color: _stateColor(state)),
        ),
        title: Text(
          draft['nombre']?.toString() ?? 'Sin nombre',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('$entityType · ${draft['codigo'] ?? ''}'),
        trailing: Chip(
          label: Text(state),
          side: BorderSide(color: _stateColor(state)),
          backgroundColor: _stateColor(state).withValues(alpha: 0.08),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  valid
                      ? 'Validación correcta.'
                      : 'Pendiente de validación o con errores.',
                  style: TextStyle(
                    color: valid
                        ? const Color(0xFF0C7A5B)
                        : const Color(0xFF8A6815),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (editable && supported)
                      OutlinedButton.icon(
                        onPressed: actionRunning
                            ? null
                            : () => _openWizard(entityType, draft: draft),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar'),
                      ),
                    if (editable)
                      OutlinedButton.icon(
                        onPressed:
                            actionRunning ? null : () => _validateDraft(draft),
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Validar'),
                      ),
                    if (editable && valid && canPublish)
                      FilledButton.icon(
                        onPressed:
                            actionRunning ? null : () => _publishDraft(draft),
                        icon: const Icon(Icons.publish_outlined),
                        label: const Text('Publicar'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'VALIDADO':
        return const Color(0xFF176B87);
      case 'PUBLICADO':
        return const Color(0xFF0C7A5B);
      case 'ERROR_PUBLICACION':
        return const Color(0xFFB33B32);
      case 'ARCHIVADO':
        return Colors.grey;
      default:
        return const Color(0xFF8A6815);
    }
  }

  IconData _entityIcon(String type) {
    switch (type) {
      case 'RUBRO':
        return Icons.business_center_outlined;
      case 'SECCION':
        return Icons.view_sidebar_outlined;
      case 'MODULO':
        return Icons.grid_view_outlined;
      case 'FORMATO':
        return Icons.assignment_outlined;
      case 'TABLA':
        return Icons.table_chart_outlined;
      case 'CAMPO':
        return Icons.text_fields_outlined;
      default:
        return Icons.account_tree_outlined;
    }
  }

  Widget _emptyDrafts() {
    return Container(
      padding: const EdgeInsets.all(28),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE6EC)),
      ),
      child: const Column(
        children: [
          Icon(Icons.inbox_outlined, size: 42, color: Color(0xFF60758A)),
          SizedBox(height: 8),
          Text('Todavía no hay borradores.'),
        ],
      ),
    );
  }

  Widget _accessDenied() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 52),
            SizedBox(height: 12),
            Text(
              'Se requiere rol ADMIN o GESTOR para usar el constructor.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorPanel() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 52),
            const SizedBox(height: 12),
            Text(error ?? 'No se pudo abrir el constructor.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
