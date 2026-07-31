import 'package:appgt_offline_subtables/features/configuration_admin/configuration_admin_repository.dart';
import 'package:appgt_offline_subtables/features/configuration_admin/configuration_preview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _PreviewRepository extends ConfigurationAdminRepository {
  _PreviewRepository()
      : super(
          client: SupabaseClient(
            'http://localhost',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  @override
  Future<Map<String, dynamic>> previewConfiguration({
    required String entityType,
    required String entityId,
  }) async {
    if (entityType == 'SECCION' || entityType == 'MODULO') {
      return {
        'raiz': {
          'nombre': entityType == 'SECCION' ? 'Calidad' : 'Calidad Campo',
          'definicion': {'activo': true, 'orden': 0},
        },
        'navegacion': [
          {
            'nombre': 'Calidad',
            'modulos': [
              {
                'nombre': 'Calidad Campo',
                'formatos': [
                  {'nombre': 'Inspección'},
                  {'nombre': 'Calibración'},
                ],
              },
              if (entityType == 'SECCION')
                {
                  'nombre': 'Calidad Packing',
                  'formatos': <dynamic>[],
                },
            ],
          },
        ],
      };
    }
    return {
      'raiz': {
        'nombre': 'Calibración de Balanzas y Equipos de Campo',
        'definicion': {'activo': true, 'orden': 0},
      },
      'navegacion': <dynamic>[],
      'detalle_formato': {
        'tablas': [
          {
            'nombre': 'Calibración de Balanzas',
            'entidad_origen_id': 'tabla_calibracion',
            'definicion': {'tabla_destino': 'calibracion_balanzas'},
          },
        ],
        'campos': [
          {
            'nombre': 'Identificador',
            'padre_origen_id': 'tabla_calibracion',
            'definicion': {
              'campo': 'id',
              'etiqueta': 'Identificador',
              'tipo_ui': 'hidden_id',
              'activo': true,
            },
          },
          {
            'nombre': 'Peso patrón',
            'entidad_origen_id': 'campo_peso',
            'padre_origen_id': 'tabla_calibracion',
            'definicion': {
              'campo': 'peso_patron',
              'etiqueta': 'Peso patrón',
              'tipo_ui': 'number',
              'orden': 1,
              'activo': true,
              'visible': true,
            },
          },
        ],
        'matrices': <dynamic>[],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> configurationHistory({
    required String entityType,
    required String entityId,
  }) async {
    return {'versiones': <dynamic>[], 'auditoria': <dynamic>[]};
  }
}

void main() {
  testWidgets('la vista del formato prioriza sus campos sin duplicar el título',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConfigurationPreviewPage(
          template: const {
            'id': '00000000-0000-0000-0000-000000000001',
            'entidad_tipo': 'FORMATO',
            'entidad_origen_id': 'formato_calibracion',
            'nombre': 'Calibración de Balanzas y Equipos de Campo',
          },
          canCreateVersion: true,
          repository: _PreviewRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Calibración de Balanzas y Equipos de Campo'),
      findsOneWidget,
    );
    expect(
      find.text('Usa el menú ⋮ para editar, activar/desactivar.'),
      findsOneWidget,
    );
    expect(find.text('Ubicación en la aplicación'), findsNothing);
    expect(find.textContaining('Estructura dinámica'), findsNothing);
    expect(find.text('Campos'), findsOneWidget);
    expect(find.text('N° de campos'), findsOneWidget);
    expect(find.text('Peso patrón'), findsOneWidget);
    expect(find.text('Identificador'), findsNothing);

    await tester.tap(find.byTooltip('Acciones del campo'));
    await tester.pumpAndSettle();
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('Ocultar'), findsOneWidget);
    expect(find.text('Eliminar'), findsOneWidget);
  });

  testWidgets('la sección muestra solo estado, cantidad y nombres de módulos',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConfigurationPreviewPage(
          template: const {
            'id': '00000000-0000-0000-0000-000000000002',
            'entidad_tipo': 'SECCION',
            'entidad_origen_id': 'calidad',
            'nombre': 'Calidad',
          },
          canCreateVersion: true,
          repository: _PreviewRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Activo'), findsOneWidget);
    expect(find.text('Módulos de esta sección'), findsOneWidget);
    expect(find.text('Calidad Campo'), findsOneWidget);
    expect(find.text('Calidad Packing'), findsOneWidget);
    expect(find.text('Ubicación en la aplicación'), findsNothing);
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('el módulo muestra solo estado, cantidad y nombres de formatos',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConfigurationPreviewPage(
          template: const {
            'id': '00000000-0000-0000-0000-000000000003',
            'entidad_tipo': 'MODULO',
            'entidad_origen_id': 'calidad_campo',
            'nombre': 'Calidad Campo',
          },
          canCreateVersion: true,
          repository: _PreviewRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Activo'), findsOneWidget);
    expect(find.text('Formatos de este módulo'), findsOneWidget);
    expect(find.text('Inspección'), findsOneWidget);
    expect(find.text('Calibración'), findsOneWidget);
    expect(find.text('Calidad'), findsNothing);
    expect(find.byType(ExpansionTile), findsNothing);
  });
}
