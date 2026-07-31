import 'package:appgt_offline_subtables/features/users/hierarchical_access_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sections = [
    {'id': 'formatos', 'nombre': 'Formatos'},
    {'id': 'matrices', 'nombre': 'Matrices'},
  ];
  const modules = [
    {'id': 'calidad', 'nombre': 'Calidad', 'seccion': 'formatos'},
    {'id': 'riego', 'nombre': 'Riego', 'seccion': 'formatos'},
    {'id': 'general', 'nombre': 'General', 'seccion': 'matrices'},
  ];
  const formats = [
    {
      'id': 'inspeccion',
      'nombre': 'Inspección',
      'modulo_id': 'calidad',
      'tabla_destino': 'SIG-INSPECCION',
    },
    {
      'id': 'drenaje',
      'nombre': 'Drenaje',
      'modulo_id': 'riego',
      'tabla_destino': 'RF-DRENAJE',
    },
    {
      'id': 'areas',
      'nombre': 'Áreas',
      'modulo_id': 'general',
      'tabla_destino': 'MATRIZ_AREAS',
    },
  ];

  test('una sección concedida incluye todos sus módulos y formatos', () {
    final result = resolveEffectiveAccessTree(
      sections: sections,
      modules: modules,
      formats: formats,
      sectionPermissions: const [
        {'seccion_id': 'formatos', 'can_view': true, 'activo': true},
      ],
      formatPermissions: const [],
    );

    expect(result.bySection.keys, ['formatos']);
    expect(result.bySection['formatos']!.keys, ['calidad', 'riego']);
    expect(result.moduleCount, 2);
    expect(result.formatCount, 2);
  });

  test('reconoce permisos históricos por tabla_destino y evita duplicados', () {
    final result = resolveEffectiveAccessTree(
      sections: sections,
      modules: modules,
      formats: formats,
      sectionPermissions: const [],
      formatPermissions: const [
        {
          'modulo': 'general',
          'formato': 'MATRIZ_AREAS',
          'can_view': true,
        },
        {
          'modulo': 'general',
          'formato': 'areas',
          'can_view': true,
        },
      ],
    );

    expect(result.bySection.keys, ['matrices']);
    expect(result.bySection['matrices']!['general']!.single['id'], 'areas');
    expect(result.moduleCount, 1);
    expect(result.formatCount, 1);
  });
}
