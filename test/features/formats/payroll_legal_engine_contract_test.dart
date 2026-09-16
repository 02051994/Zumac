import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;
  late String migration063;

  setUpAll(() {
    migration = File(
      'supabase/migrations/202608140045_peru_payroll_legal_engine.sql',
    ).readAsStringSync();
    migration063 = File(
      'supabase/migrations/'
      '202609100063_payroll_slip_v2_weekly_rest_and_compensation.sql',
    ).readAsStringSync();
  });

  test('separa costeo diario, liquidacion, provisiones y desembolso', () {
    expect(migration, contains('PLANILLA_LIQUIDACION_TRABAJADOR_APPGT'));
    expect(migration, contains('total_desembolso_trabajador'));
    expect(migration, contains('deposito_cts'));
    expect(migration, contains('total_provisiones'));
    expect(migration, contains("motor_calculo='PERU_LEGAL_V2'"));
  });

  test('soporta regimen agrario y general sin mezclar ONP y AFP', () {
    expect(migration, contains("'AGRARIO_31110'"));
    expect(migration, contains("'GENERAL_728'"));
    expect(migration, contains("if w.\"SISTEMA_PENSION_CODIGO\"='ONP'"));
    expect(migration, contains("elsif w.\"SISTEMA_PENSION_CODIGO\"='AFP'"));
    expect(
      migration,
      isNot(contains('Compatibilidad con la formula entregada mientras')),
    );
  });

  test('bloquea el ciclo antiguo y exige validaciones antes de aprobar', () {
    expect(
      migration,
      contains(
        'revoke all on function public.'
        'appgt_cambiar_estado_planilla_periodo_legacy_045',
      ),
    );
    expect(
      migration,
      contains('perform public.appgt_exigir_planilla_valida_v2(p_periodo_id)'),
    );
    expect(migration, contains("'ASISTENCIA_SIN_TAREO'"));
    expect(migration, contains("'TAREO_SIN_ASISTENCIA'"));
    expect(migration, contains("'PARAMETRO_LEGAL_SIN_VIGENCIA'"));
  });

  test('no proyecta parametros 2026 indefinidamente', () {
    expect(
      migration,
      contains("date '2026-01-01', date '2026-12-31', 1130, 5500"),
    );
    expect(migration, isNot(contains("date '2028-01-01'")));
  });

  test('aplica la tasa agraria temporal de la Ley 31969 en 2026', () {
    expect(migration, contains('Ley 31969 art. 9'));
    expect(
      migration,
      contains(
        "'AGRARIO_31110', date '2026-01-01', date '2026-12-31', 1130, 5500,\n"
        '    0.30, 0.06, 0.06',
      ),
    );
    expect(migration, isNot(contains("'ESSALUD_AGRARIO_SIN_CLASIFICAR'")));
    expect(
      migration,
      contains('else coalesce(v_param.essalud_general_tasa,0.09) end'),
    );
  });

  test('preserva tenant, documentos y frescura del calculo', () {
    expect(migration, contains('add column if not exists empresa_id uuid'));
    expect(
      migration,
      contains('set empresa_id = '
          "'00000000-0000-0000-0000-000000000001'::uuid"),
    );
    expect(migration, contains('where p.empresa_id=v_periodo.empresa_id'));
    expect(migration, contains('ELECCION_BENEFICIO_SIN_SUSTENTO'));
    expect(migration, contains('MODALIDAD_BENEFICIO_INCOMPATIBLE'));
    expect(
      migration,
      contains('cambiaron despues del ultimo calculo. Ejecute Calcular'),
    );
    expect(migration, contains("motor_calculo='REQUIERE_RECALCULO'"));
  });

  test('reconstruye permisos sin perder las horas reales', () {
    expect(migration, contains('horas_origen'));
    expect(migration, contains('horas_regulares_nuevas'));
    expect(
      migration,
      isNot(contains('greatest(p.horas_trabajadas-r.horas,0)')),
    );
  });

  test('incluye pruebas SQL de base 30 y quinta categoria', () {
    expect(
      migration,
      contains(
        "appgt_dias_base_30_v2(date '2026-02-01',date '2026-02-28')<>30",
      ),
    );
    expect(
      migration,
      contains('appgt_impuesto_anual_quinta_v2(27500,5500)-2200'),
    );
  });

  test('usa frecuencia operativa y conserva periodo de sueldo informativo', () {
    expect(migration063, contains('"FRECUENCIA_PAGO" set not null'));
    expect(
      migration063,
      contains("'Periodo de pago (solo informativo)'"),
    );
    expect(
      migration063,
      contains('No se deriva de "Periodo de pago"'),
    );
  });

  test('prorratea BETA solo con acuerdo escrito y documentado', () {
    expect(migration063, contains('"FECHA_ACUERDO_BETA" is not null'));
    expect(
      migration063,
      contains("nullif(btrim(p.\"DOCUMENTO_ACUERDO_BETA\"), '') is not null"),
    );
    expect(
      migration063,
      contains('appgt_validar_modalidad_beta_v2'),
    );
  });

  test('calcula descanso configurable, proporcional y sobretasa real', () {
    expect(
      migration063,
      contains('least(greatest(coalesce(v_dia_descanso, 7), 1), 7)'),
    );
    expect(migration063, contains('* 8.0 / 6.0'));
    expect(
      migration063,
      contains('appgt_horas_dso_trabajadas_v2'),
    );
    expect(
      migration063,
      contains('sobretasa_descanso_semanal_100_costo'),
    );
    expect(
      migration063,
      contains("periodo.estado = 'CERRADA'"),
    );
  });

  test('usa bonos maestros existentes y no crea montos diarios paralelos', () {
    expect(migration063, contains('array[\'Bono al cargo\']'));
    expect(migration063, contains('array[\'Bono movilidad\']'));
    expect(migration063, isNot(contains('BONO_CARGO_DIARIO')));
    expect(migration063, isNot(contains('BONO_MOVILIDAD_DIARIO')));
  });

  test('incluye compensacion C y contexto versionado de boleta', () {
    expect(
        migration063, contains("upper(btrim(q.tipo_permiso))='COMPENSACION'"));
    expect(migration063, contains("then 'C'"));
    expect(migration063, contains('pdf_version integer not null default 0'));
    expect(migration063, contains('appgt_obtener_contexto_boleta_v2'));
  });
}
