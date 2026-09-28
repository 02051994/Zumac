import 'package:flutter/material.dart';

import '../../core/services/local_db.dart';
import '../form_runner/form_runner_page.dart';
import '../form_runner/special_form_pages.dart';

class FormatsPage extends StatefulWidget {
  final Map<String, dynamic> module;
  const FormatsPage({super.key, required this.module});

  @override
  State<FormatsPage> createState() => _FormatsPageState();
}

class _FormatsPageState extends State<FormatsPage> {
  final local = LocalDb.instance;
  List<Map<String, dynamic>> formats = [];

  @override
  void initState() {
    super.initState();
    loadFormats();
  }

  Future<void> loadFormats() async {
    final permissions = await local.where(
      'local_permissions',
      'modulo = ? and can_view = 1',
      [widget.module['id']],
    );
    final allowedFormatIds =
        permissions.map((e) => e['formato'] as String).toSet().toList();
    if (allowedFormatIds.isEmpty) {
      setState(() => formats = []);
      return;
    }
    final placeholders = List.filled(allowedFormatIds.length, '?').join(',');
    final rows = await local.where(
      'local_formats',
      'modulo_id = ? and id in ($placeholders) and activo = 1',
      [widget.module['id'], ...allowedFormatIds],
      orderBy: 'orden',
    );
    setState(() => formats = rows);
  }

  @override
  Widget build(BuildContext context) {
    final moduleName = widget.module['nombre'] ?? widget.module['id'];
    return Scaffold(
      appBar: AppBar(title: Text('Formatos - $moduleName')),
      body: formats.isEmpty
          ? const Center(
              child: Text('No tienes formatos permitidos en este módulo.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: formats.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final f = formats[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.assignment),
                    title: Text('${f['nombre']}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final special = await local.where(
                        'local_special_formats',
                        'formato_id = ? and activo = 1',
                        [f['id']],
                      );
                      final resolvedSpecial = special.isNotEmpty
                          ? Map<String, dynamic>.from(special.first)
                          : appGtSpecialFormatFallback(f);
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => resolvedSpecial != null
                              ? SpecialFormRouterPage(
                                  moduleId: widget.module['id'] as String,
                                  format: f,
                                  special: resolvedSpecial,
                                )
                              : FormRunnerPage(
                                  moduleId: widget.module['id'] as String,
                                  format: f,
                                ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
