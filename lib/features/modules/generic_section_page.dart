import 'package:flutter/material.dart';

import '../users/governed_permissions_page.dart';

class GenericSectionPage extends StatelessWidget {
  final Map<String, dynamic> section;
  final bool embedded;

  const GenericSectionPage(
      {super.key, required this.section, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final title =
        section['nombre']?.toString() ?? section['id']?.toString() ?? 'Sección';
    final sectionId = section['id']?.toString() ?? '';
    final normalized = '$sectionId $title ${section['tipo_contenido'] ?? ''}'
        .trim()
        .toLowerCase();

    if (normalized.contains('permis') ||
        normalized.contains('gestión de accesos') ||
        normalized.contains('gestion de accesos')) {
      return GovernedPermissionsPage(embedded: embedded);
    }

    final body = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dashboard_customize_outlined, size: 52),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              sectionId.isEmpty ? 'Sección dinámica' : sectionId,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            const Text(
              'La sección ya está habilitada en el menú. Todavía no tiene una pantalla operativa asociada en Flutter.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    if (embedded) return body;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: body,
    );
  }
}
