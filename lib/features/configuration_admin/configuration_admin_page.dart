import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/app_experience_service.dart';
import '../../core/widgets/configuration_icon_catalog.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../core/widgets/zumac_feature_header.dart';
import 'configuration_admin_repository.dart';
import 'creator_document_import_page.dart';
import 'configuration_entity_wizard_page.dart';
import 'configuration_preview_page.dart';
import 'format_structure_wizard_page.dart';

enum CreatorEntryMode { create, edit }

class ConfigurationAdminPage extends StatefulWidget {
  const ConfigurationAdminPage({
    super.key,
    this.initialMode = CreatorEntryMode.create,
    this.embedded = false,
    this.onConfigurationChanged,
  });

  final CreatorEntryMode initialMode;
  final bool embedded;
  final Future<void> Function()? onConfigurationChanged;

  @override
  State<ConfigurationAdminPage> createState() => _ConfigurationAdminPageState();
}

class _ConfigurationAdminPageState extends State<ConfigurationAdminPage> {
  final repository = ConfigurationAdminRepository();
  final experience = AppExperienceService();
  final pageScrollController = ScrollController();
  final publishedSearchController = TextEditingController();

  bool loading = true;
  bool refreshing = false;
  bool actionRunning = false;
  bool publicationPendingSync = false;
  String? error;
  Map<String, dynamic> contextData = {};
  List<Map<String, dynamic>> drafts = [];
  List<Map<String, dynamic>> publishedConfigurations = [];
  String publishedSearch = '';
  String? selectedBuilderRubroId;
  String? selectedPublishedRubroId;
  bool experienceRestored = false;
  Timer? persistViewTimer;
  Map<String, dynamic> restoredViewState = <String, dynamic>{};
  final Set<String> expandedPublishedSections = <String>{};
  final Set<String> expandedPublishedModules = <String>{};

  bool get canManage => contextData['puede_gestionar'] == true;
  bool get canPublish => contextData['puede_publicar'] == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    persistViewTimer?.cancel();
    unawaited(_persistViewState());
    pageScrollController.dispose();
    publishedSearchController.dispose();
    super.dispose();
  }

  Future<void> _restoreViewState() async {
    if (experienceRestored) return;
    final saved = await experience.loadCreatorView();
    restoredViewState = Map<String, dynamic>.from(saved);
    selectedBuilderRubroId = saved['builder_rubro_id']?.toString();
    selectedPublishedRubroId = saved['published_rubro_id']?.toString();
    publishedSearch = saved['search']?.toString() ?? '';
    publishedSearchController.text = publishedSearch;
    experienceRestored = true;
    final offsetKey = widget.initialMode == CreatorEntryMode.edit
        ? 'scroll_offset_edit'
        : 'scroll_offset_create';
    final offset = double.tryParse('${saved[offsetKey] ?? ''}');
    if (offset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (pageScrollController.hasClients) {
          pageScrollController.jumpTo(
            offset.clamp(0, pageScrollController.position.maxScrollExtent),
          );
        }
      });
    }
  }

  void _scheduleViewStatePersistence() {
    persistViewTimer?.cancel();
    persistViewTimer = Timer(
      const Duration(milliseconds: 220),
      () => unawaited(_persistViewState()),
    );
  }

  Future<void> _persistViewState() {
    final offsetKey = widget.initialMode == CreatorEntryMode.edit
        ? 'scroll_offset_edit'
        : 'scroll_offset_create';
    restoredViewState = {
      ...restoredViewState,
      'builder_rubro_id': selectedBuilderRubroId,
      'published_rubro_id': selectedPublishedRubroId,
      'search': publishedSearch,
      offsetKey:
          pageScrollController.hasClients ? pageScrollController.offset : 0,
    };
    return experience.saveCreatorView(restoredViewState);
  }

  Future<void> _load() async {
    await _restoreViewState();
    if (!mounted) return;
    final hasContent =
        contextData.isNotEmpty || publishedConfigurations.isNotEmpty;
    setState(() {
      if (hasContent) {
        refreshing = true;
      } else {
        loading = true;
      }
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
        final rubroRows = _publishedRubrosFrom(
          loadedContext,
          loadedPublished,
        );
        if (!rubroRows.any(
          (row) => row['id']?.toString() == selectedPublishedRubroId,
        )) {
          selectedPublishedRubroId =
              rubroRows.isEmpty ? null : rubroRows.first['id']?.toString();
        }
        if (!rubroRows.any(
          (row) => row['id']?.toString() == selectedBuilderRubroId,
        )) {
          selectedBuilderRubroId = null;
        }
        loading = false;
        refreshing = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        error = 'No se pudo abrir el constructor: $exception';
        loading = false;
        refreshing = false;
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
            initialRubroId: selectedBuilderRubroId,
            repository: repository,
          )
        : ConfigurationEntityWizardPage(
            entityType: entityType,
            contextData: contextData,
            initialDraft: draft,
            initialRubroId: selectedBuilderRubroId,
            repository: repository,
          );
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => page,
      ),
    );
    if (published == true) {
      publicationPendingSync = false;
      await widget.onConfigurationChanged?.call();
    }
    await _load();
  }

  Future<void> _openDocumentImport() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CreatorDocumentImportPage(
          contextData: contextData,
          initialRubroId: selectedBuilderRubroId,
          repository: repository,
        ),
      ),
    );
    await _load();
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
        publicationPendingSync = false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuración publicada.')),
        );
        await widget.onConfigurationChanged?.call();
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

  Future<void> _discardDraft(Map<String, dynamic> draft) async {
    final id = draft['id']?.toString();
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Descartar borrador'),
        content: Text(
          'Se eliminará el borrador “${draft['nombre'] ?? ''}”. La configuración publicada y sus registros no cambiarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => actionRunning = true);
    try {
      await repository.discardDraft(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Borrador descartado.')),
      );
      await _load();
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo descartar: $exception')),
      );
    } finally {
      if (mounted) setState(() => actionRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageBody = loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
            ? _errorPanel()
            : !canManage
                ? _accessDenied()
                : Stack(
                    children: [
                      IgnorePointer(
                        ignoring: actionRunning,
                        child: _creatorBody(),
                      ),
                      if (refreshing || actionRunning)
                        const Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: LinearProgressIndicator(minHeight: 3),
                        ),
                    ],
                  );
    final title = ZumacFeatureHeader(
      title: widget.initialMode == CreatorEntryMode.edit
          ? 'Zumac Creator · Editar objetos'
          : 'Zumac Creator · Nuevo objeto',
      icon: Icons.dashboard_customize_outlined,
      color: const Color(0xFF237A57),
      compact: true,
    );
    final refreshButton = IconButton(
      tooltip: 'Actualizar panel',
      onPressed: loading || refreshing ? null : _load,
      icon: const Icon(Icons.refresh),
    );
    if (widget.embedded) {
      return ColoredBox(
        color: const Color(0xFFF5F8FA),
        child: pageBody,
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FA),
      appBar: AppBar(
        titleSpacing: 8,
        title: title,
        actions: [refreshButton],
      ),
      body: pageBody,
    );
  }

  Widget _creatorBody() {
    final editing = widget.initialMode == CreatorEntryMode.edit;
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 700 ? 12.0 : 24.0;
        if (editing) {
          return _editCreatorBody(horizontalPadding);
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            key: PageStorageKey(
              editing
                  ? 'zumac-creator-edit-scroll'
                  : 'zumac-creator-new-scroll',
            ),
            controller: pageScrollController,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              18,
              horizontalPadding,
              32,
            ),
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: ZumacResponsiveLimits.page,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _constructorGuide(),
                      if (publicationPendingSync) ...[
                        const SizedBox(height: 14),
                        _syncNotice(),
                      ],
                      const SizedBox(height: 14),
                      _rubroSelector(),
                      if (selectedBuilderRubroId != null) ...[
                        const SizedBox(height: 18),
                        _entityActions(),
                      ],
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
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _editCreatorBody(double horizontalPadding) {
    // En móvil, la altura de cada árbol cambia mucho al expandir formatos.
    // Una lista convencional conserva una única geometría de desplazamiento y
    // evita el lienzo gris que podía aparecer al regresar rápidamente arriba.
    return ColoredBox(
      color: const Color(0xFFF5F8FA),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: const PageStorageKey('zumac-creator-edit-scroll-stable'),
          controller: pageScrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            18,
            horizontalPadding,
            32,
          ),
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: ZumacResponsiveLimits.page,
                ),
                child: _publishedPanel(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _constructorGuide() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Selecciona rubro',
          style: TextStyle(
            color: Color(0xFF17324D),
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'El rubro mantiene juntas sus secciones, módulos, formatos, tablas y permisos.',
          style: TextStyle(color: Color(0xFF60758A), fontSize: 12.5),
        ),
      ],
    );
  }

  String _rubroName(Map<String, dynamic> row) {
    if (row['id']?.toString() == 'rubro_general_zumac') {
      return 'Agroexportación';
    }
    return row['nombre']?.toString() ?? 'Rubro';
  }

  Widget _rubroSelector() {
    final rubros = _publishedRubros;
    return LayoutBuilder(
      builder: (context, constraints) {
        final visibleWidth = constraints.maxWidth;
        final cardWidth = ((visibleWidth - 12) / 2).clamp(150.0, 260.0);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _rubroCard(
                width: cardWidth,
                title: 'Agregar Rubro',
                icon: Icons.add_circle_outline,
                selected: false,
                onTap: () => _openWizard('RUBRO'),
              ),
              for (final rubro in rubros) ...[
                const SizedBox(width: 12),
                _rubroCard(
                  width: cardWidth,
                  title: _rubroName(rubro),
                  icon: configurationIconForName(
                    rubro['icono']?.toString() ?? 'agriculture',
                  ),
                  selected: rubro['id']?.toString() == selectedBuilderRubroId,
                  onTap: () {
                    setState(
                      () => selectedBuilderRubroId = rubro['id']?.toString(),
                    );
                    _scheduleViewStatePersistence();
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _rubroCard({
    required double width,
    required String title,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: selected ? const Color(0xFFE5F2F5) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? const Color(0xFF176B87) : const Color(0xFFDCE6EC),
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF17324D),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                Icon(icon, color: const Color(0xFF176B87), size: 32),
                if (selected) ...[
                  const SizedBox(height: 6),
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF0C7A5B),
                    size: 18,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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
        final columns = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 680
                ? 2
                : 1;
        final cardWidth =
            (constraints.maxWidth - (8 * (columns - 1))) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Crear en ${_selectedBuilderRubroName()}',
              style: const TextStyle(
                color: Color(0xFF17324D),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _entityCard(
                  width: cardWidth,
                  icon: Icons.view_sidebar_outlined,
                  title: 'Sección',
                  onTap: () => _openWizard('SECCION'),
                ),
                _entityCard(
                  width: cardWidth,
                  icon: Icons.grid_view_outlined,
                  title: 'Módulo',
                  onTap: () => _openWizard('MODULO'),
                ),
                _entityCard(
                  width: cardWidth,
                  icon: Icons.assignment_outlined,
                  title: 'Formato',
                  onTap: () => _openWizard('FORMATO'),
                ),
                _entityCard(
                  width: cardWidth,
                  icon: Icons.document_scanner_outlined,
                  title: 'Documento → App',
                  onTap: _openDocumentImport,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _selectedBuilderRubroName() {
    for (final rubro in _publishedRubros) {
      if (rubro['id']?.toString() == selectedBuilderRubroId) {
        return _rubroName(rubro);
      }
    }
    return 'el rubro seleccionado';
  }

  List<Map<String, dynamic>> _publishedRubrosFrom(
    Map<String, dynamic> context,
    List<Map<String, dynamic>> published,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    final rawRubros = context['rubros'];
    if (rawRubros is List) {
      for (final raw in rawRubros.whereType<Map>()) {
        final row = Map<String, dynamic>.from(raw);
        final id = row['id']?.toString() ?? '';
        if (id.isNotEmpty) byId[id] = row;
      }
    }
    for (final row in published.where(
      (item) => item['entidad_tipo']?.toString() == 'RUBRO',
    )) {
      final id = row['entidad_origen_id']?.toString() ??
          row['codigo']?.toString() ??
          '';
      if (id.isEmpty) continue;
      byId.putIfAbsent(
        id,
        () => {
          'id': id,
          'nombre': row['nombre']?.toString() ?? 'Rubro',
          'orden': _definitionOrder(row),
        },
      );
    }
    final rows = byId.values.toList();
    rows.sort((a, b) {
      final order = (int.tryParse('${a['orden'] ?? 0}') ?? 0)
          .compareTo(int.tryParse('${b['orden'] ?? 0}') ?? 0);
      if (order != 0) return order;
      return '${a['nombre'] ?? ''}'.compareTo('${b['nombre'] ?? ''}');
    });
    return rows;
  }

  List<Map<String, dynamic>> get _publishedRubros =>
      _publishedRubrosFrom(contextData, publishedConfigurations);

  Map<String, dynamic> _publishedDefinition(Map<String, dynamic> row) {
    final value = row['definicion'];
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  int _definitionOrder(Map<String, dynamic> row) =>
      int.tryParse('${_publishedDefinition(row)['orden'] ?? 0}') ?? 0;

  String _originId(Map<String, dynamic> row) =>
      row['entidad_origen_id']?.toString() ?? row['codigo']?.toString() ?? '';

  List<Map<String, dynamic>> _publishedChildren(
    String type,
    String parentId,
  ) {
    final rows = publishedConfigurations.where((row) {
      return row['entidad_tipo']?.toString() == type &&
          row['padre_origen_id']?.toString() == parentId;
    }).toList();
    rows.sort((a, b) {
      final order = _definitionOrder(a).compareTo(_definitionOrder(b));
      if (order != 0) return order;
      return '${a['nombre'] ?? ''}'.compareTo('${b['nombre'] ?? ''}');
    });
    return rows;
  }

  bool _publishedMatches(Map<String, dynamic> row, String query) {
    if (query.isEmpty) return true;
    return (row['nombre']?.toString().toLowerCase() ?? '').contains(query) ||
        (row['codigo']?.toString().toLowerCase() ?? '').contains(query);
  }

  bool _formatBranchMatches(Map<String, dynamic> format, String query) {
    if (_publishedMatches(format, query)) return true;
    return _publishedChildren('TABLA', _originId(format))
        .any((table) => _publishedMatches(table, query));
  }

  bool _moduleBranchMatches(Map<String, dynamic> module, String query) {
    if (_publishedMatches(module, query)) return true;
    return _publishedChildren('FORMATO', _originId(module))
        .any((format) => _formatBranchMatches(format, query));
  }

  bool _sectionBranchMatches(Map<String, dynamic> section, String query) {
    if (_publishedMatches(section, query)) return true;
    return _publishedChildren('MODULO', _originId(section))
        .any((module) => _moduleBranchMatches(module, query));
  }

  List<Map<String, dynamic>> _filteredPublishedSections() {
    final normalizedSearch = publishedSearch.trim().toLowerCase();
    return publishedConfigurations.where((row) {
      final rubroId = row['rubro_id']?.toString() ??
          _publishedDefinition(row)['rubro_id']?.toString();
      return row['entidad_tipo']?.toString() == 'SECCION' &&
          rubroId == selectedPublishedRubroId &&
          _sectionBranchMatches(row, normalizedSearch);
    }).toList()
      ..sort((a, b) => _definitionOrder(a).compareTo(_definitionOrder(b)));
  }

  Widget _publishedPanel({bool includeSectionTiles = true}) {
    final normalizedSearch = publishedSearch.trim().toLowerCase();
    final sections = _filteredPublishedSections();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Editar u ocultar existentes',
          style: TextStyle(
            color: Color(0xFF17324D),
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Toca un elemento para ver su estructura, historial, editarlo o desactivarlo sin borrar sus datos.',
          style: TextStyle(color: Color(0xFF60758A), fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: ValueKey('published-rubro-$selectedPublishedRubroId'),
          initialValue: _publishedRubros.any(
            (row) => row['id']?.toString() == selectedPublishedRubroId,
          )
              ? selectedPublishedRubroId
              : null,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.business_center_outlined),
            labelText: 'Rubro',
            helperText: selectedPublishedRubroId == null
                ? 'Elija el rubro que desea administrar.'
                : '${sections.length} ${sections.length == 1 ? 'sección' : 'secciones'} en este rubro',
            border: const OutlineInputBorder(),
          ),
          items: _publishedRubros
              .map(
                (row) => DropdownMenuItem(
                  value: row['id']?.toString(),
                  child: Text(
                    row['nombre']?.toString() ?? 'Rubro',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() {
            selectedPublishedRubroId = value;
            publishedSearch = '';
            publishedSearchController.clear();
            _scheduleViewStatePersistence();
          }),
        ),
        const SizedBox(height: 10),
        TextField(
          key: ValueKey('published-search-$selectedPublishedRubroId'),
          controller: publishedSearchController,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Buscar sección, módulo, formato o tabla',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            setState(() => publishedSearch = value);
            _scheduleViewStatePersistence();
          },
        ),
        const SizedBox(height: 10),
        if (_publishedRubros.isEmpty)
          const Card(
            elevation: 0,
            child: ListTile(
              leading: Icon(Icons.business_center_outlined),
              title: Text('Todavía no hay rubros publicados.'),
            ),
          )
        else if (sections.isEmpty)
          const Card(
            elevation: 0,
            child: ListTile(
              leading: Icon(Icons.search_off_outlined),
              title: Text('No se encontraron elementos en este rubro.'),
            ),
          )
        else if (includeSectionTiles)
          ...sections.map(
            (section) => _publishedSectionTile(section, normalizedSearch),
          ),
      ],
    );
  }

  Widget _publishedSectionTile(
    Map<String, dynamic> section,
    String query,
  ) {
    final sectionId = _originId(section);
    final allModules = _publishedChildren('MODULO', _originId(section));
    final visibleModules = query.isEmpty
        ? allModules
        : allModules
            .where((module) => _moduleBranchMatches(module, query))
            .toList();
    final active = _publishedDefinition(section)['activo'] != false;
    final expanded = expandedPublishedSections.contains(sectionId);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFDCE6EC)),
      ),
      child: ExpansionTile(
        key: ValueKey('published-section-$sectionId-${query.isNotEmpty}'),
        // No retener árboles completos fuera de pantalla. Con búsquedas amplias
        // maintainState conservaba cientos de tiles y podía dejar el lienzo gris
        // al volver rápidamente al inicio.
        maintainState: false,
        shape: const Border(),
        collapsedShape: const Border(),
        onExpansionChanged: (value) => setState(() {
          if (value) {
            expandedPublishedSections.add(sectionId);
          } else {
            expandedPublishedSections.remove(sectionId);
          }
        }),
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFDDF3F8),
          child: Icon(Icons.view_sidebar_outlined, size: 20),
        ),
        title: Text(
          section['nombre']?.toString() ?? 'Sección',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: active ? null : const Color(0xFF77858D),
          ),
        ),
        subtitle: Text(
          '${active ? 'Sección' : 'Desactivada'} · ${allModules.length} ${allModules.length == 1 ? 'módulo' : 'módulos'}',
        ),
        trailing: _visibilityMenu(section, active, expanded),
        initiallyExpanded: expanded,
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 8, 10),
        children: visibleModules.isEmpty
            ? const [
                ListTile(
                  dense: true,
                  leading: Icon(Icons.inbox_outlined, size: 19),
                  title: Text('Esta sección no contiene módulos.'),
                ),
              ]
            : visibleModules
                .map(
                  (module) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F8FA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2EBEF)),
                      ),
                      child: _publishedModuleTile(
                        module,
                        query,
                      ),
                    ),
                  ),
                )
                .toList(),
      ),
    );
  }

  Widget _publishedModuleTile(
    Map<String, dynamic> module,
    String query,
  ) {
    final moduleId = _originId(module);
    final allFormats = _publishedChildren('FORMATO', _originId(module));
    final visibleFormats = query.isEmpty
        ? allFormats
        : allFormats
            .where((format) => _formatBranchMatches(format, query))
            .toList();
    final active = _publishedDefinition(module)['activo'] != false;
    final expanded = expandedPublishedModules.contains(moduleId);
    return ExpansionTile(
      key: ValueKey('published-module-$moduleId-${query.isNotEmpty}'),
      maintainState: false,
      shape: const Border(),
      collapsedShape: const Border(),
      onExpansionChanged: (value) => setState(() {
        if (value) {
          expandedPublishedModules.add(moduleId);
        } else {
          expandedPublishedModules.remove(moduleId);
        }
      }),
      leading: const Icon(Icons.grid_view_outlined),
      title: Text(
        module['nombre']?.toString() ?? 'Módulo',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: active ? null : const Color(0xFF77858D),
        ),
      ),
      subtitle: Text(
        '${active ? 'Módulo' : 'Desactivado'} · ${allFormats.length} ${allFormats.length == 1 ? 'formato' : 'formatos'}',
      ),
      trailing: _visibilityMenu(module, active, expanded),
      initiallyExpanded: expanded,
      childrenPadding: const EdgeInsets.only(bottom: 6),
      children: visibleFormats.isEmpty
          ? const [
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.only(left: 42, right: 12),
                leading: Icon(Icons.inbox_outlined, size: 18),
                title: Text('Este módulo no contiene formatos.'),
              ),
            ]
          : visibleFormats.map(_publishedFormatTile).toList(),
    );
  }

  Widget _publishedFormatTile(Map<String, dynamic> format) {
    final tables = _publishedChildren('TABLA', _originId(format));
    final directTable =
        _publishedDefinition(format)['tabla_destino']?.toString().trim();
    final tableCount = tables.isNotEmpty
        ? tables.length
        : (directTable == null || directTable.isEmpty ? 0 : 1);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 44, right: 12),
      leading: const Icon(Icons.assignment_outlined),
      title: Text(
        format['nombre']?.toString() ?? 'Formato',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        'Formato · $tableCount ${tableCount == 1 ? 'tabla' : 'tablas'}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: actionRunning ? null : () => _openPreview(format),
    );
  }

  Widget _visibilityMenu(
    Map<String, dynamic> template,
    bool active,
    bool expanded,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<String>(
          tooltip: 'Opciones',
          enabled: !actionRunning,
          onSelected: (value) {
            if (value == 'visibility') {
              _requestVisibilityChange(template, !active);
            } else if (value == 'edit') {
              _openPreview(template);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'visibility',
              child: Row(
                children: [
                  Icon(active
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  const SizedBox(width: 10),
                  Text(active ? 'Desactivar' : 'Activar'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit_outlined),
                  SizedBox(width: 10),
                  Text('Revisar o editar'),
                ],
              ),
            ),
          ],
          icon: const Icon(Icons.more_vert),
        ),
        AnimatedRotation(
          turns: expanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: const Icon(Icons.expand_more),
        ),
      ],
    );
  }

  Future<void> _requestVisibilityChange(
    Map<String, dynamic> template,
    bool active,
  ) async {
    final name = template['nombre']?.toString() ?? 'este elemento';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(active ? 'Activar $name' : 'Desactivar $name'),
        content: Text(
          active
              ? 'Volverá a estar disponible para los usuarios después de publicar el cambio.'
              : 'Dejará de mostrarse, pero sus datos y configuración no se borrarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: Icon(
              active
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            label: Text(active ? 'Activar' : 'Desactivar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => actionRunning = true);
    try {
      final templateId = template['id']?.toString();
      if (templateId == null || templateId.isEmpty) {
        throw StateError('No se encontró la versión publicada.');
      }
      final draft = await repository.createDraftFromPublished(templateId);
      final definition = draft['definicion'] is Map
          ? Map<String, dynamic>.from(draft['definicion'] as Map)
          : <String, dynamic>{};
      definition['activo'] = active;
      draft['definicion'] = definition;
      draft['_requested_action'] = active ? 'ACTIVATE' : 'DEACTIVATE';
      if (!mounted) return;
      setState(() => actionRunning = false);
      await _openWizard(template['entidad_tipo']?.toString() ?? '',
          draft: draft);
    } catch (exception) {
      if (!mounted) return;
      setState(() => actionRunning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo preparar el cambio: $exception')),
      );
    }
  }

  Widget _entityCard({
    required double width,
    required IconData icon,
    required String title,
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
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 15),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5F2F5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: const Color(0xFF176B87)),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF17324D),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
                    if (editable)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB33B32),
                        ),
                        onPressed:
                            actionRunning ? null : () => _discardDraft(draft),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Descartar'),
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
