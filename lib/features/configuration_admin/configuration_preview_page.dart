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

  Future<void> _createVersion() async {
    final templateId = widget.template['id']?.toString();
    if (templateId == null || creatingVersion) return;
    setState(() => creatingVersion = true);
    try {
      final draft = await repository.createDraftFromPublished(templateId);
      if (!mounted) return;
      Navigator.pop(context, draft);
    } catch (exception) {
      if (!mounted) return;
      setState(() => creatingVersion = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('No se pudo crear la nueva versión: $exception')),
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
          title: Text(widget.template['nombre']?.toString() ?? 'Vista previa'),
          actions: [
            if (widget.canCreateVersion)
              TextButton.icon(
                onPressed: loading || creatingVersion ? null : _createVersion,
                icon: creatingVersion
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.edit_note_outlined),
                label: const Text('Nueva versión'),
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
                '$entityType · $entityId · Versión ${root['version'] ?? 1}',
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
        if (entityType == 'FORMATO') ...[
          const SizedBox(height: 18),
          _formatDetail(),
        ],
      ],
    );
  }

  Widget _metadataCard(Map<String, dynamic> definition) {
    final rows = <MapEntry<String, dynamic>>[
      MapEntry('Código técnico', entityId),
      MapEntry('Rubro', widget.template['rubro_id']),
      MapEntry('Padre', widget.template['padre_origen_id']),
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
              subtitle: Text(
                _map(format['definicion'])['tabla_destino']?.toString() ?? '',
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _formatDetail() {
    final detail = _map(preview['detalle_formato']);
    final tables = _maps(detail['tablas']);
    final fields = _maps(detail['campos']);
    final matrices = _maps(detail['matrices']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Estructura dinámica · ${tables.length} tabla(s), ${fields.length} campo(s), ${matrices.length} matriz(ces)',
          style: const TextStyle(
            color: Color(0xFF17324D),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        for (final table in tables)
          Builder(
            builder: (context) {
              final tableDefinition = _map(table['definicion']);
              final origin = table['entidad_origen_id']?.toString();
              final destination = tableDefinition['tabla_destino']?.toString();
              final tableFields = fields.where((field) {
                final definition = _map(field['definicion']);
                return field['padre_origen_id']?.toString() == origin ||
                    definition['tabla_destino']?.toString() == destination;
              }).toList();
              return Card(
                elevation: 0,
                child: ExpansionTile(
                  leading: const Icon(Icons.table_chart_outlined),
                  title: Text(table['nombre']?.toString() ?? 'Tabla'),
                  subtitle:
                      Text('$destination · ${tableFields.length} campo(s)'),
                  children: tableFields
                      .map(
                        (field) => ListTile(
                          contentPadding:
                              const EdgeInsets.only(left: 56, right: 16),
                          leading: const Icon(Icons.text_fields_outlined),
                          title: Text(
                            _map(field['definicion'])['etiqueta']?.toString() ??
                                field['nombre']?.toString() ??
                                'Campo',
                          ),
                          subtitle: Text(
                            '${_map(field['definicion'])['campo'] ?? ''} · ${_map(field['definicion'])['tipo_ui'] ?? _map(field['definicion'])['tipo'] ?? ''}',
                          ),
                        ),
                      )
                      .toList(),
                ),
              );
            },
          ),
      ],
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
}
