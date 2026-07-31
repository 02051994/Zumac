import 'package:flutter/material.dart';

import 'configuration_admin_repository.dart';

class ConfigurationPreviewPage extends StatefulWidget {
  final Map<String, dynamic> template;
  final bool canCreateVersion;
  final ConfigurationAdminRepository? repository;

  const ConfigurationPreviewPage({
    super.key,
    required this.template,
    required this.canCreateVersion,
    this.repository,
  });

  @override
  State<ConfigurationPreviewPage> createState() =>
      _ConfigurationPreviewPageState();
}

class _ConfigurationPreviewPageState extends State<ConfigurationPreviewPage> {
  late final ConfigurationAdminRepository repository;
  bool loading = true;
  bool creatingVersion = false;
  String? error;
  Map<String, dynamic> preview = {};
  Map<String, dynamic> history = {};

  String get entityType => widget.template['entidad_tipo']?.toString() ?? '';
  String get entityId => widget.template['entidad_origen_id']?.toString() ?? '';
  bool get isCurrentlyActive {
    final root = _map(preview['raiz']);
    final definition = _map(root['definicion']);
    if (definition.containsKey('activo')) return definition['activo'] != false;
    final templateDefinition = _map(widget.template['definicion']);
    if (templateDefinition.containsKey('activo')) {
      return templateDefinition['activo'] != false;
    }
    return widget.template['activo'] != false;
  }

  @override
  void initState() {
    super.initState();
    repository = widget.repository ?? ConfigurationAdminRepository();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final results = await Future.wait([
        repository.previewConfiguration(
          entityType: entityType,
          entityId: entityId,
        ),
        repository.configurationHistory(
          entityType: entityType,
          entityId: entityId,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        preview = results[0];
        history = results[1];
        loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'No se pudo cargar la previsualización: $exception';
      });
    }
  }

  Future<void> _createVersion({
    bool? active,
    int? tableIndex,
    int? fieldIndex,
    String? fieldCode,
    String? fieldAction,
    bool addField = false,
  }) async {
    final templateId = widget.template['id']?.toString();
    if (templateId == null || creatingVersion) return;
    if (active != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(active ? 'Activar formato' : 'Desactivar formato'),
          content: Text(
            active
                ? 'El formato volverá a estar disponible después de guardar y publicar el cambio.'
                : 'El formato dejará de mostrarse, pero sus datos existentes no se borrarán.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: Icon(active
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              label: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => creatingVersion = true);
    try {
      final draft = await repository.createDraftFromPublished(templateId);
      if (active != null) {
        final definition = _map(draft['definicion']);
        definition['activo'] = active;
        draft['definicion'] = definition;
        draft['_requested_action'] = active ? 'ACTIVATE' : 'DEACTIVATE';
      }
      if (tableIndex != null) {
        draft['_requested_table_index'] = tableIndex;
        if (fieldIndex != null) draft['_requested_field_index'] = fieldIndex;
        if (fieldCode != null) draft['_requested_field_code'] = fieldCode;
        if (fieldAction != null) draft['_requested_field_action'] = fieldAction;
        if (addField) draft['_requested_add_field'] = true;
      }
      if (!mounted) return;
      Navigator.pop(context, draft);
    } catch (exception) {
      if (!mounted) return;
      setState(() => creatingVersion = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir la edición: $exception')),
      );
    }
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
      : <Map<String, dynamic>>[];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F8FA),
        appBar: AppBar(
          toolbarHeight:
              (widget.template['nombre']?.toString().length ?? 0) > 27
                  ? 72
                  : 56,
          titleSpacing: 0,
          title: Text(
            widget.template['nombre']?.toString() ?? 'Vista previa',
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.visible,
            style: const TextStyle(fontSize: 20, height: 1.08),
          ),
          actions: [
            if (widget.canCreateVersion)
              if (creatingVersion)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                PopupMenuButton<String>(
                  enabled: !loading,
                  tooltip: 'Acciones de configuración',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (action) {
                    if (action == 'edit') _createVersion();
                    if (action == 'toggle_active') {
                      _createVersion(active: !isCurrentlyActive);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_note_outlined),
                        title: Text('Editar configuración'),
                        subtitle: Text(
                          'Modifica nombre, ubicación y características',
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'toggle_active',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(isCurrentlyActive
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        title: Text(isCurrentlyActive
                            ? 'Desactivar en la app'
                            : 'Reactivar en la app'),
                        subtitle: const Text('Conserva todos los datos'),
                      ),
                    ),
                  ],
                ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.visibility_outlined), text: 'Vista previa'),
              Tab(icon: Icon(Icons.history_outlined), text: 'Historial'),
            ],
          ),
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? _errorPanel()
                : TabBarView(
                    children: [
                      _previewTab(),
                      _historyTab(),
                    ],
                  ),
      ),
    );
  }

  Widget _previewTab() {
    final root = _map(preview['raiz']);
    final definition = _map(root['definicion']);
    final navigation = _maps(preview['navegacion']);
    if (entityType == 'FORMATO') {
      return _formatPreview(definition);
    }
    if (entityType == 'SECCION' || entityType == 'MODULO') {
      return _hierarchySummaryPreview(definition, navigation);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F5265), Color(0xFF176B87)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                root['nombre']?.toString() ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${_friendlyEntityType(entityType)} · Versión ${root['version'] ?? 1}',
                style: const TextStyle(color: Colors.white70),
              ),
              if ((root['descripcion']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  root['descripcion'].toString(),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (widget.canCreateVersion) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F3F5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFC8E0E6)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 20, color: Color(0xFF176B87)),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Usa el menú ⋮ para editar o desactivar. Se prepara una nueva versión y nada cambia hasta publicarla.',
                    style: TextStyle(color: Color(0xFF315B68)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        _metadataCard(definition),
        const SizedBox(height: 14),
        const Text(
          'Ubicación en la aplicación',
          style: TextStyle(
            color: Color(0xFF17324D),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        if (navigation.isEmpty)
          const Card(child: ListTile(title: Text('Sin navegación visible.')))
        else
          ...navigation.map(_sectionTile),
      ],
    );
  }

  Widget _hierarchySummaryPreview(
    Map<String, dynamic> definition,
    List<Map<String, dynamic>> navigation,
  ) {
    final modules = <Map<String, dynamic>>[];
    for (final section in navigation) {
      modules.addAll(_maps(section['modulos']));
    }
    final formats = <Map<String, dynamic>>[];
    for (final module in modules) {
      formats.addAll(_maps(module['formatos']));
    }
    final showingModules = entityType == 'SECCION';
    final children = showingModules ? modules : formats;
    final singular = showingModules ? 'módulo' : 'formato';
    final plural = showingModules ? 'módulos' : 'formatos';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: _summaryValue(
                    'Activo',
                    definition['activo'] != false ? 'Sí' : 'No',
                  ),
                ),
                Container(width: 1, height: 42, color: const Color(0xFFDCE5E9)),
                const SizedBox(width: 16),
                Expanded(
                  child: _summaryValue(
                    children.length == 1 ? singular : plural,
                    '${children.length}',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          showingModules
              ? 'Módulos de esta sección'
              : 'Formatos de este módulo',
          style: const TextStyle(
            color: Color(0xFF17324D),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        if (children.isEmpty)
          Card(
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: Text('No hay $plural configurados.'),
            ),
          )
        else
          for (final child in children)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  showingModules
                      ? Icons.grid_view_outlined
                      : Icons.assignment_outlined,
                  color: const Color(0xFF176B87),
                ),
                title: Text(
                  child['nombre']?.toString() ??
                      (showingModules ? 'Módulo' : 'Formato'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
      ],
    );
  }

  Widget _formatPreview(Map<String, dynamic> definition) {
    final fields = _configuredFormatFields();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.canCreateVersion) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F3F5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFC8E0E6)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 20, color: Color(0xFF176B87)),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Usa el menú ⋮ para editar, activar/desactivar.',
                    style: TextStyle(color: Color(0xFF315B68)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: _summaryValue(
                    'Activo',
                    definition['activo'] != false ? 'Sí' : 'No',
                  ),
                ),
                Container(width: 1, height: 42, color: const Color(0xFFDCE5E9)),
                const SizedBox(width: 16),
                Expanded(
                  child: _summaryValue('N° de campos', '${fields.length}'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _formatDetail(),
      ],
    );
  }

  Widget _summaryValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF60758A),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _metadataCard(Map<String, dynamic> definition) {
    final rows = <MapEntry<String, dynamic>>[
      MapEntry('Orden', definition['orden']),
      MapEntry('Activo', definition['activo'] != false ? 'Sí' : 'No'),
    ];
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: rows
              .where((row) => row.value != null && '${row.value}'.isNotEmpty)
              .map(
                (row) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          row.key,
                          style: const TextStyle(
                            color: Color(0xFF60758A),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(child: Text('${row.value}')),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _sectionTile(Map<String, dynamic> section) {
    final modules = _maps(section['modulos']);
    return Card(
      elevation: 0,
      child: ExpansionTile(
        leading: const Icon(Icons.view_sidebar_outlined),
        title: Text(
          section['nombre']?.toString() ?? 'Sección',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('${modules.length} módulo(s)'),
        initiallyExpanded: navigationShouldExpand(modules.length),
        children: modules.map(_moduleTile).toList(),
      ),
    );
  }

  bool navigationShouldExpand(int children) =>
      entityType == 'SECCION' ||
      entityType == 'MODULO' ||
      entityType == 'FORMATO';

  Widget _moduleTile(Map<String, dynamic> module) {
    final formats = _maps(module['formatos']);
    return ExpansionTile(
      leading: const Icon(Icons.grid_view_outlined),
      title: Text(module['nombre']?.toString() ?? 'Módulo'),
      subtitle: Text('${formats.length} formato(s)'),
      initiallyExpanded: entityType == 'MODULO' || entityType == 'FORMATO',
      children: formats
          .map(
            (format) => ListTile(
              contentPadding: const EdgeInsets.only(left: 56, right: 16),
              leading: const Icon(Icons.assignment_outlined),
              title: Text(format['nombre']?.toString() ?? 'Formato'),
            ),
          )
          .toList(),
    );
  }

  Widget _formatDetail() {
    final detail = _map(preview['detalle_formato']);
    final tables = _maps(detail['tablas']);
    final fields = _configuredFormatFields();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Campos',
                style: TextStyle(
                  color: Color(0xFF17324D),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (widget.canCreateVersion)
              IconButton.filledTonal(
                tooltip: tables.isEmpty
                    ? 'El formato todavía no tiene una tabla'
                    : 'Agregar campo',
                onPressed: creatingVersion || tables.isEmpty
                    ? null
                    : () => _selectTableAndAddField(tables),
                icon: const Icon(Icons.add),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (fields.isEmpty)
          const Card(
            elevation: 0,
            child: ListTile(
              leading: Icon(Icons.text_fields_outlined),
              title: Text('Este formato todavía no tiene campos configurados.'),
            ),
          )
        else
          for (final item in fields) _fieldTile(item),
      ],
    );
  }

  Widget _fieldTile(Map<String, dynamic> item) {
    final field = _map(item['field']);
    final definition = _map(item['definition']);
    final tableIndex = item['table_index'] as int;
    final fieldIndex = item['field_index'] as int;
    final code = item['field_code']?.toString();
    final hidden =
        definition['visible'] == false || definition['visible_tabla'] == false;
    final label = definition['etiqueta']?.toString().trim();
    final name = label?.isNotEmpty == true
        ? label!
        : field['nombre']?.toString() ?? 'Campo';
    final type = _friendlyControlName(
      definition['tipo_ui'] ?? definition['tipo'],
    );
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              hidden ? const Color(0xFFE4E8EA) : const Color(0xFFCDEFFA),
          child: Icon(
            hidden ? Icons.visibility_off_outlined : Icons.text_fields_outlined,
            color: const Color(0xFF176B87),
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(hidden ? '$type · Oculto' : type),
        onTap: !widget.canCreateVersion || creatingVersion
            ? null
            : () => _createVersion(
                  tableIndex: tableIndex,
                  fieldIndex: fieldIndex,
                  fieldCode: code,
                  fieldAction: 'EDIT',
                ),
        trailing: widget.canCreateVersion
            ? PopupMenuButton<String>(
                enabled: !creatingVersion,
                tooltip: 'Acciones del campo',
                onSelected: (action) {
                  if (action == 'edit') {
                    _createVersion(
                      tableIndex: tableIndex,
                      fieldIndex: fieldIndex,
                      fieldCode: code,
                      fieldAction: 'EDIT',
                    );
                  } else if (action == 'visibility') {
                    _createVersion(
                      tableIndex: tableIndex,
                      fieldIndex: fieldIndex,
                      fieldCode: code,
                      fieldAction: hidden ? 'SHOW' : 'HIDE',
                    );
                  } else if (action == 'delete') {
                    _confirmDeleteField(
                      name: name,
                      tableIndex: tableIndex,
                      fieldIndex: fieldIndex,
                      fieldCode: code,
                    );
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Editar'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'visibility',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      title: Text(hidden ? 'Mostrar' : 'Ocultar'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline, color: Colors.red),
                      title: Text('Eliminar'),
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Future<void> _confirmDeleteField({
    required String name,
    required int tableIndex,
    required int fieldIndex,
    required String? fieldCode,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar campo'),
        content: Text(
          '¿Desea eliminar “$name” de la configuración? Los registros existentes no se borrarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _createVersion(
      tableIndex: tableIndex,
      fieldIndex: fieldIndex,
      fieldCode: fieldCode,
      fieldAction: 'DELETE',
    );
  }

  Future<void> _selectTableAndAddField(
    List<Map<String, dynamic>> tables,
  ) async {
    if (tables.isEmpty) return;
    var tableIndex = 0;
    if (tables.length > 1) {
      final selected = await showDialog<int>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('¿En qué tabla desea agregar el campo?'),
          children: [
            for (var index = 0; index < tables.length; index++)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, index),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.table_chart_outlined),
                  title: Text(
                    tables[index]['nombre']?.toString() ?? 'Tabla ${index + 1}',
                  ),
                ),
              ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      tableIndex = selected;
    }
    await _createVersion(tableIndex: tableIndex, addField: true);
  }

  List<Map<String, dynamic>> _configuredFormatFields() {
    final detail = _map(preview['detalle_formato']);
    final tables = _maps(detail['tablas']);
    final fields = _maps(detail['campos']);
    final result = <Map<String, dynamic>>[];
    for (var tableIndex = 0; tableIndex < tables.length; tableIndex++) {
      final table = tables[tableIndex];
      final tableDefinition = _map(table['definicion']);
      final origin = table['entidad_origen_id']?.toString();
      final destination = tableDefinition['tabla_destino']?.toString();
      var configuredIndex = 0;
      for (final field in fields) {
        final definition = _map(field['definicion']);
        final belongs = field['padre_origen_id']?.toString() == origin ||
            (destination?.isNotEmpty == true &&
                definition['tabla_destino']?.toString() == destination);
        if (!belongs ||
            _isSystemField(definition) ||
            definition['activo'] == false) {
          continue;
        }
        result.add({
          'field': field,
          'definition': definition,
          'table_index': tableIndex,
          'field_index': configuredIndex,
          'field_code': definition['campo'] ??
              field['entidad_origen_id'] ??
              definition['codigo'] ??
              field['codigo'],
        });
        configuredIndex++;
      }
    }
    result.sort((a, b) {
      final left = int.tryParse('${_map(a['definition'])['orden']}') ?? 0;
      final right = int.tryParse('${_map(b['definition'])['orden']}') ?? 0;
      return left.compareTo(right);
    });
    return result;
  }

  bool _isSystemField(Map<String, dynamic> definition) {
    const reserved = {
      'id',
      'id_local',
      'empresa_id',
      'created_by',
      'created_at',
      'updated_at',
      'deleted_at',
      'eliminado',
      'estado_sync',
    };
    return reserved.contains(
      definition['campo']?.toString().trim().toLowerCase(),
    );
  }

  Widget _historyTab() {
    final versions = _maps(history['versiones']);
    final audits = _maps(history['auditoria']);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Versiones publicadas (${versions.length})',
          style: const TextStyle(
            color: Color(0xFF17324D),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        for (final version in versions)
          Card(
            elevation: 0,
            child: ListTile(
              leading: CircleAvatar(
                child: Text('v${version['version'] ?? 1}'),
              ),
              title: Text(version['nombre']?.toString() ?? entityId),
              subtitle: Text(
                '${version['published_at'] ?? version['created_at'] ?? ''}',
              ),
              trailing: version['es_actual'] == true
                  ? const Chip(label: Text('Actual'))
                  : const Text('Histórica'),
            ),
          ),
        const SizedBox(height: 18),
        Text(
          'Trazabilidad (${audits.length})',
          style: const TextStyle(
            color: Color(0xFF17324D),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        if (audits.isEmpty)
          const Card(
            child: ListTile(
              title: Text('No hay eventos del constructor para esta entidad.'),
            ),
          )
        else
          for (final audit in audits)
            Card(
              elevation: 0,
              child: ListTile(
                leading: const Icon(Icons.manage_history_outlined),
                title: Text(audit['accion']?.toString() ?? 'Evento'),
                subtitle: Text(
                  '${audit['estado_anterior'] ?? '—'} → ${audit['estado_nuevo'] ?? '—'}\n${audit['created_at'] ?? ''}',
                ),
                isThreeLine: true,
              ),
            ),
      ],
    );
  }

  Widget _errorPanel() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 10),
            Text(error ?? 'No se pudo cargar la previsualización.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }

  String _friendlyControlName(dynamic value) {
    final key = value?.toString().trim().toLowerCase() ?? '';
    const labels = <String, String>{
      'text': 'Texto',
      'multiline': 'Texto largo',
      'integer': 'Número entero',
      'number': 'Número decimal',
      'date': 'Fecha',
      'time': 'Hora',
      'datetime': 'Fecha y hora',
      'checkbox': 'Casilla de verificación',
      'switch': 'Interruptor Sí / No',
      'dropdown': 'Lista desplegable',
      'multiselect': 'Selección múltiple',
      'formula': 'Fórmula',
      'lookup': 'Consulta calculada',
      'photo': 'Foto',
      'signature': 'Firma',
      'qr_scan': 'Lector QR',
      'barcode_scan': 'Lector de código de barras',
      'hidden_id': 'Identificador automático',
    };
    return labels[key] ?? (key.isEmpty ? 'Campo' : 'Campo configurado');
  }

  String _friendlyEntityType(String value) {
    return const {
          'RUBRO': 'Rubro',
          'SECCION': 'Sección',
          'MODULO': 'Módulo',
          'FORMATO': 'Formato',
        }[value] ??
        value;
  }
}
