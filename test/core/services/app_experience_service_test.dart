import 'package:appgt_offline_subtables/core/services/app_experience_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppExperienceService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = AppExperienceService();
  });

  test('conserva navegación, vista del creador y última sincronización',
      () async {
    final synchronizedAt = DateTime.utc(2026, 7, 22, 14, 30);

    await service.saveNavigation({
      'kind': 'format',
      'section_id': 'calidad',
      'module_id': 'packing',
      'format_id': 'inspeccion',
    });
    await service.saveCreatorView({
      'rubro_id': 'rubro_general_zumac',
      'search': 'calibración',
      'scroll_offset': 180.0,
    });
    await service.saveLastSync(synchronizedAt);

    expect((await service.loadNavigation())['format_id'], 'inspeccion');
    expect((await service.loadCreatorView())['scroll_offset'], 180.0);
    expect(await service.loadLastSync(), synchronizedAt);
  });

  test('guarda, recupera y elimina borradores automáticos', () async {
    await service.saveBuilderDraft('formato_prueba', {
      'current_step': 3,
      'payload': {'nombre': 'Inspección'},
    });

    final saved = await service.loadBuilderDraft('formato_prueba');
    expect(saved['current_step'], 3);
    expect((saved['payload'] as Map)['nombre'], 'Inspección');

    await service.clearBuilderDraft('formato_prueba');
    expect(await service.loadBuilderDraft('formato_prueba'), isEmpty);
  });

  test('conserva filtros, desplazamiento y selección de una vista', () async {
    await service.saveRecordView('calidad_inspeccion', {
      'selected_table': 'INSPECCION_PT',
      'column_filters': {'turno': 'NOCHE'},
      'vertical_offset': 420.0,
      'selected_row_keys': ['id:registro-10'],
    });

    final saved = await service.loadRecordView('calidad_inspeccion');
    expect(saved['selected_table'], 'INSPECCION_PT');
    expect((saved['column_filters'] as Map)['turno'], 'NOCHE');
    expect(saved['vertical_offset'], 420.0);
    expect(saved['selected_row_keys'], ['id:registro-10']);
  });
}
