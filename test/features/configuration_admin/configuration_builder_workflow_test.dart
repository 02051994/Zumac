import 'package:appgt_offline_subtables/features/configuration_admin/configuration_admin_repository.dart';
import 'package:appgt_offline_subtables/features/configuration_admin/configuration_entity_wizard_page.dart';
import 'package:appgt_offline_subtables/features/configuration_admin/format_structure_wizard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _BuilderRepository extends ConfigurationAdminRepository {
  _BuilderRepository()
      : super(
          client: SupabaseClient(
            'http://localhost',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  @override
  Future<Map<String, dynamic>> listTemplates({
    String? entityType,
    String? rubroId,
    String? parentId,
    String? search,
    int limit = 100,
    int offset = 0,
  }) async {
    final items = switch (entityType) {
      'SECCION' => <Map<String, dynamic>>[
          {
            'id': '00000000-0000-0000-0000-000000000010',
            'entidad_origen_id': 'calidad',
            'rubro_id': 'rubro_general_zumac',
            'nombre': 'Calidad',
            'definicion': {
              'rubro_id': 'rubro_general_zumac',
              'orden': 1,
            },
          },
          {
            'id': '00000000-0000-0000-0000-000000000011',
            'entidad_origen_id': 'tienda',
            'rubro_id': 'rubro_retail',
            'nombre': 'Tienda',
            'definicion': {'rubro_id': 'rubro_retail', 'orden': 1},
          },
        ],
      'MODULO' => <Map<String, dynamic>>[
          {
            'id': '00000000-0000-0000-0000-000000000020',
            'entidad_origen_id': 'calidad_campo',
            'rubro_id': 'rubro_general_zumac',
            'nombre': 'Calidad Campo',
            'definicion': {
              'rubro_id': 'rubro_general_zumac',
              'seccion_id': 'calidad',
            },
          },
          {
            'id': '00000000-0000-0000-0000-000000000021',
            'entidad_origen_id': 'ventas',
            'rubro_id': 'rubro_retail',
            'nombre': 'Ventas',
            'definicion': {'rubro_id': 'rubro_retail'},
          },
        ],
      _ => <Map<String, dynamic>>[],
    };
    return {'items': items};
  }
}

const _context = <String, dynamic>{
  'puede_publicar': true,
  'rubros': [
    {
      'id': 'rubro_general_zumac',
      'nombre': 'Agroexportación',
    },
    {
      'id': 'rubro_retail',
      'nombre': 'Retail',
    },
  ],
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('el módulo solo ofrece secciones del rubro seleccionado',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ConfigurationEntityWizardPage(
          entityType: 'MODULO',
          contextData: _context,
          initialRubroId: 'rubro_general_zumac',
          repository: _BuilderRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Creador de módulo'), findsOneWidget);
    tester.widget<Stepper>(find.byType(Stepper)).onStepTapped!(2);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Calidad'), findsWidgets);
    expect(find.text('Tienda'), findsNothing);
    expect(find.text('Seleccione icono'), findsOneWidget);

    final iconSelector = find.ancestor(
      of: find.text('Seleccione icono'),
      matching: find.byType(InkWell),
    );
    final iconPanel = find.byKey(
      const ValueKey('configuration-icon-picker-panel'),
    );
    expect(
      tester.widget<AnimatedCrossFade>(iconPanel).crossFadeState,
      CrossFadeState.showFirst,
    );

    tester.widget<InkWell>(iconSelector).onTap!();
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      tester.widget<AnimatedCrossFade>(iconPanel).crossFadeState,
      CrossFadeState.showSecond,
    );
    expect(find.byTooltip('Agricultura'), findsOneWidget);
  });

  testWidgets(
      'el editor focalizado oculta fotos si la capacidad está desactivada',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: FormatStructureWizardPage(
          contextData: _context,
          initialRubroId: 'rubro_general_zumac',
          repository: _BuilderRepository(),
          initialDraft: const {
            'id': '00000000-0000-0000-0000-000000000030',
            'nombre': 'Inspección de prueba',
            'codigo': 'ca_id_inspeccion_prueba',
            'rubro_id': 'rubro_general_zumac',
            '_requested_table_index': 0,
            '_requested_field_index': 0,
            'definicion': {
              'rubro_id': 'rubro_general_zumac',
              'modulo_id': 'calidad_campo',
              'capacidades': {'fotos': false},
              'tablas': [
                {
                  'nombre': 'Inspección',
                  'codigo': 'ca_tabla_inspeccion',
                  'tabla_destino': 'ca-tabla_inspeccion',
                  'campos': [
                    {
                      'nombre': 'Fecha',
                      'etiqueta': 'Fecha',
                      'codigo': 'ca_campo_fecha',
                      'campo': 'Fecha',
                      'tipo': 'date',
                      'tipo_ui': 'date',
                      'requerido': true,
                      'editable': true,
                      'visible': true,
                      'visible_tabla': true,
                      'activo': true,
                    },
                  ],
                },
              ],
            },
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Editar campo'), findsWidgets);
    await tester.tap(find.text('Opciones avanzadas'));
    await tester.pumpAndSettle();
    expect(find.text('Fotos'), findsNothing);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Formato: Inspección de prueba'), findsOneWidget);
    expect(find.text('Control'), findsOneWidget);
    expect(find.text('Tipo de dato'), findsOneWidget);
    expect(find.textContaining('Módulo:'), findsNothing);
  });
}
