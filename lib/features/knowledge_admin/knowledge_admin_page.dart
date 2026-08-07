import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class KnowledgeAdminPage extends StatefulWidget {
  const KnowledgeAdminPage({super.key});

  @override
  State<KnowledgeAdminPage> createState() => _KnowledgeAdminPageState();
}

class _KnowledgeAdminPageState extends State<KnowledgeAdminPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _documents = [];
  List<Map<String, dynamic>> _sources = [];
  bool _loading = true;
  bool _working = false;
  String _filter = 'GENERADA_IA';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _supabase
            .from('FUENTES_CONOCIMIENTO_APPGT')
            .select()
            .order('prioridad'),
        _supabase
            .from('BASE_CONOCIMIENTO_APPGT')
            .select()
            .order('updated_at', ascending: false)
            .limit(500),
      ]);
      if (!mounted) return;
      setState(() {
        _sources = List<Map<String, dynamic>>.from(results[0]);
        _documents = List<Map<String, dynamic>>.from(results[1]);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar la base de conocimiento. '
            'Verifica que la migración del motor esté aplicada.\n$error';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final result = await _supabase.rpc(
        'appgt_generar_base_conocimiento_inicial_v1',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Generación terminada: $result')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar contenido: $error')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _review(
    Map<String, dynamic> document,
    String status, {
    Map<String, dynamic>? content,
  }) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await _supabase.rpc('appgt_revisar_conocimiento_v1', params: {
        'p_documento_id': document['id'],
        'p_estado': status,
        'p_contenido_estructurado': content,
      });
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la revisión: $error')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> document) async {
    final original = document['contenido_estructurado'];
    final controller = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(original),
    );
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar · ${document['titulo'] ?? ''}'),
        content: SizedBox(
          width: 720,
          child: TextField(
            controller: controller,
            minLines: 18,
            maxLines: 28,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              labelText: 'Contenido estructurado JSON',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              try {
                final decoded = jsonDecode(controller.text);
                if (decoded is! Map) throw const FormatException();
                Navigator.pop(context, Map<String, dynamic>.from(decoded));
              } catch (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('El JSON no es válido.')),
                );
              }
            },
            child: const Text('Guardar como sugerencia'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) {
      await _review(document, 'GENERADA_IA', content: result);
    }
  }

  Future<void> _configureSource(Map<String, dynamic> source) async {
    final priority = TextEditingController(
      text: (source['prioridad'] ?? 100).toString(),
    );
    var active = source['activa'] != false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(source['nombre']?.toString() ?? 'Fuente'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: priority,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Prioridad (menor se consulta primero)',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fuente activa'),
                  value: active,
                  onChanged: (value) => setDialogState(() => active = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) {
      priority.dispose();
      return;
    }
    final parsedPriority = int.tryParse(priority.text.trim());
    priority.dispose();
    if (parsedPriority == null || parsedPriority < 0) return;
    try {
      await _supabase.from('FUENTES_CONOCIMIENTO_APPGT').update({
        'prioridad': parsedPriority,
        'activa': active,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', source['id']);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar la fuente: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filter == 'TODAS'
        ? _documents
        : _documents
            .where((document) => document['estado'] == _filter)
            .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Base de conocimiento Zumac'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _working ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      _summary(visible.length),
                      const SizedBox(height: 16),
                      _sourcesPanel(),
                      const SizedBox(height: 18),
                      _filterBar(),
                      const SizedBox(height: 10),
                      if (visible.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(
                            child: Text('No hay documentos en este estado.'),
                          ),
                        )
                      else
                        for (final document in visible) _documentCard(document),
                    ],
                  ),
                ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storage_outlined, size: 48),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
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

  Widget _summary(int visibleCount) {
    return Card(
      color: const Color(0xFFEAF5F7),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 650,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$visibleCount documentos visibles · ${_sources.length} fuentes',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'El contenido generado por IA no reemplaza información existente. '
                    'Permanece como sugerencia hasta que un administrador lo apruebe.',
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _working ? null : _generate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generar faltantes'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourcesPanel() {
    return ExpansionTile(
      initiallyExpanded: true,
      title: const Text('Prioridad de fuentes'),
      subtitle: const Text(
        'La prioridad es configurable; no forma parte de la lógica del motor.',
      ),
      children: [
        for (final source in _sources)
          ListTile(
            leading: CircleAvatar(child: Text('${source['prioridad'] ?? 0}')),
            title: Text(source['nombre']?.toString() ?? ''),
            subtitle: Text(source['codigo']?.toString() ?? ''),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  source['activa'] == false
                      ? Icons.pause_circle_outline
                      : Icons.check_circle_outline,
                  color: source['activa'] == false ? Colors.grey : Colors.green,
                ),
                IconButton(
                  tooltip: 'Configurar',
                  onPressed: () => _configureSource(source),
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _filterBar() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final state in const [
          'GENERADA_IA',
          'APROBADA',
          'RECHAZADA',
          'TODAS',
        ])
          ChoiceChip(
            selected: _filter == state,
            label: Text(state.replaceAll('_', ' ')),
            onSelected: (_) => setState(() => _filter = state),
          ),
      ],
    );
  }

  Widget _documentCard(Map<String, dynamic> document) {
    final content = document['contenido_estructurado'];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(_iconFor(document['entidad_tipo']?.toString() ?? '')),
        title: Text(document['titulo']?.toString() ?? ''),
        subtitle: Text(
          '${document['entidad_tipo'] ?? ''} · ${document['fuente_codigo'] ?? ''} · '
          '${document['estado'] ?? ''}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F8FA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(content),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _working ? null : () => _edit(document),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar sugerencia'),
              ),
              OutlinedButton.icon(
                onPressed:
                    _working ? null : () => _review(document, 'RECHAZADA'),
                icon: const Icon(Icons.block),
                label: const Text('Rechazar'),
              ),
              FilledButton.icon(
                onPressed:
                    _working ? null : () => _review(document, 'APROBADA'),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Aprobar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String type) => switch (type) {
        'FORMATO' => Icons.description_outlined,
        'MODULO' => Icons.widgets_outlined,
        'SECCION' => Icons.folder_outlined,
        'CONCEPTO' => Icons.account_tree_outlined,
        _ => Icons.article_outlined,
      };
}
