import 'package:appgt_offline_subtables/features/configuration_admin/configuration_entity_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el asistente de sección contiene todas las preguntas indispensables',
      () {
    final ids = ConfigurationEntitySpec.section.questions
        .map((question) => question.id)
        .toSet();

    expect(
      ids,
      containsAll({
        'plantilla',
        'nombre',
        'codigo',
        'descripcion',
        'rubro_id',
        'icono',
        'orden',
        'tipo_contenido',
        'activo',
      }),
    );
  });

  test('el asistente de módulo exige su sección padre', () {
    final sectionQuestion = ConfigurationEntitySpec.module.questions
        .firstWhere((question) => question.id == 'seccion_id');

    expect(sectionQuestion.required, isTrue);
    expect(sectionQuestion.reason, isNotEmpty);
  });

  test('la validación local rechaza una sección incompleta', () {
    final errors = validateSectionOrModulePayload('SECCION', {
      'nombre': 'Operaciones',
      'codigo': 'OPERACIONES',
      'orden': 1,
      'activo': true,
    });

    expect(errors, isNotEmpty);
    expect(errors.join(' '), contains('rubro'));
    expect(errors.join(' '), contains('contenido'));
  });

  test('normaliza códigos técnicos sin caracteres inseguros', () {
    expect(
      normalizeConfigurationCode('  Control de Cosecha 2026 '),
      'CONTROL_DE_COSECHA_2026',
    );
  });
}
