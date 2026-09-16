import 'dart:convert';

import 'package:appgt_offline_subtables/features/formats/payroll_slip_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _contextPayload({
  bool testScenario = false,
  dynamic version = 1,
}) =>
    {
      // El snapshot heredado incluía descanso y licencias dentro del básico.
      // V2 ya entrega el jornal separado y se prueba más abajo.
      'version': version,
      if (testScenario) 'es_prueba': true,
      'periodo': {
        'fecha_inicio': '2026-08-01',
        'fecha_fin': '2026-08-15',
      },
      'trabajador': {
        'dni': '91428367',
        'nombre': 'Trabajador de prueba',
        'puesto': 'SEGURIDAD',
        'sistema_pension': 'ONP',
        'asignacion_familiar': true,
        'fecha_ingreso': '2025-01-15',
        'sueldo': 1500,
      },
      'resumen': {
        'dias_trabajados': 10,
        'descansos_semanales': 2,
        'dias_permisos': 2,
        'faltas': 1,
      },
      'liquidacion': {
        'tipo_remuneracion': 'JORNAL',
        // El valor heredado incluye descanso semanal y licencia; el PDF debe
        // mostrar la remuneracion basica solo por jornales efectivamente
        // trabajados (400 - 60 - 40 = 300).
        'remuneracion_basica': 400,
        'descanso_semanal': 60,
        'licencias_pagadas': 40,
        'compensacion_pagada': 10,
        'asignacion_familiar': 12,
        'horas_extra_25_importe': 15,
        'horas_extra_35_importe': 20,
        'nocturnidad_importe': 18,
        'horas_nocturnas': 3.5,
        'bono_cargo_pagado': 25,
        'bono_movilidad_pagado': 30,
        'beta_pagado': 11,
        'cts_pagada': 13,
        'gratificacion_pagada': 14,
        'bono_extraordinario_gratificacion': 2,
        'onp': 45,
        'essalud_empleador': 54,
        'remuneracion_bruta': 520,
        'total_descuentos': 45,
        'neto_pagar': 475,
      },
      'dias': [
        {'fecha': '2026-08-01', 'horas_totales': 8, 'codigo': ''},
        {'fecha': '2026-08-02', 'horas_totales': 0, 'codigo': 'DS'},
        {'fecha': '2026-08-03', 'horas_totales': 8, 'codigo': ''},
        {'fecha': '2026-08-04', 'horas_totales': 0, 'codigo': 'P'},
        {'fecha': '2026-08-05', 'horas_totales': 0, 'codigo': 'C'},
        {'fecha': '2026-08-06', 'horas_totales': 0, 'codigo': 'F'},
        {'fecha': '2026-08-07', 'horas_totales': 0, 'codigo': 'FE'},
      ],
    };

PayrollSlipAmountLine _line(
  Iterable<PayrollSlipAmountLine> lines,
  String concept,
) =>
    lines.singleWhere((line) => line.concept == concept);

PayrollSlipAmountLine _lineContaining(
  Iterable<PayrollSlipAmountLine> lines,
  String text,
) =>
    lines.singleWhere((line) => line.concept.contains(text));

void main() {
  group('PayrollSlipPdf context', () {
    test('separa jornales, descansos, compensacion y bonos', () {
      final payload = _contextPayload();
      final settlement =
          Map<String, dynamic>.from(payload['liquidacion'] as Map)
            ..['sobretasa_descanso_semanal_100'] = 8;
      payload['liquidacion'] = settlement;
      final context = PayrollSlipPdf.contextFromPayload(payload);

      expect(
        _lineContaining(context.incomeLines, 'jornales trabajados').amount,
        300,
      );
      expect(
        _lineContaining(context.incomeLines, 'Descanso semanal').amount,
        60,
      );
      expect(_lineContaining(context.incomeLines, 'Licencias').amount, 30);
      expect(_lineContaining(context.incomeLines, 'Compens').amount, 10);
      expect(
        _lineContaining(context.incomeLines, 'sobretasa 100%').amount,
        8,
      );
      expect(_line(context.incomeLines, 'Horas nocturnas (3.5 h)').amount, 18);
      expect(_line(context.incomeLines, 'Bono al cargo').amount, 25);
      expect(_line(context.incomeLines, 'Bono movilidad').amount, 30);
      expect(
        context.incomeLines.map((line) => line.concept),
        isNot(contains('Movilidad empresa')),
      );
      expect(context.netPay, 475);
      expect(context.totalEmployerContributions, 54);
    });

    test('solo muestra escenario de prueba cuando el contexto lo indica', () {
      final labeledProduction = _contextPayload();
      labeledProduction['etiqueta_contexto'] = 'Producción';
      final labeledTest = _contextPayload();
      labeledTest['etiqueta_contexto'] = 'Escenario de prueba';

      expect(
        PayrollSlipPdf.contextFromPayload(_contextPayload()).headerLabel,
        isEmpty,
      );
      expect(
        PayrollSlipPdf.contextFromPayload(_contextPayload(testScenario: true))
            .headerLabel,
        'Escenario de prueba',
      );
      expect(
        PayrollSlipPdf.contextFromPayload(labeledProduction).headerLabel,
        isEmpty,
      );
      expect(
        PayrollSlipPdf.contextFromPayload(labeledTest).headerLabel,
        'Escenario de prueba',
      );
    });

    test('respeta los montos ya separados por el contexto V2', () {
      final payload = _contextPayload(version: 'BOLETA_V2');
      final worker = Map<String, dynamic>.from(payload['trabajador'] as Map);
      worker
        ..remove('sistema_pension')
        ..['regimen_codigo'] = 'AFP'
        ..['tipo_remuneracion'] = 'JORNAL';
      payload['trabajador'] = worker;
      final settlement =
          Map<String, dynamic>.from(payload['liquidacion'] as Map)
            ..['remuneracion_basica'] = 300
            ..['movilidad_empresa_costo'] = 999
            ..['bono_movilidad_maestro'] = 30
            ..['remuneracion_bruta'] = 560
            ..['neto_pagar'] = 515;
      payload['liquidacion'] = settlement;

      final context = PayrollSlipPdf.contextFromPayload(payload);

      expect(context.version, PayrollSlipPdf.contextVersion);
      expect(context.worker.pensionSystem, 'AFP');
      expect(context.worker.monthlySalary, 1500);
      expect(
        _lineContaining(context.incomeLines, 'jornales trabajados').amount,
        300,
      );
      expect(
        context.incomeLines.any((line) => line.amount == 999),
        isFalse,
      );
      expect(context.totalIncome, 560);
      expect(context.netPay, 515);
      expect(context.netPay, context.totalIncome - context.totalDiscounts);
    });

    test('no duplica el bono movilidad dentro de otros ingresos afectos', () {
      final payload = _contextPayload(version: 'BOLETA_V2');
      final settlement =
          Map<String, dynamic>.from(payload['liquidacion'] as Map)
            ..['bono_cargo_pagado'] = 0
            ..['bono_cargo_maestro'] = 0
            ..['bono_movilidad_pagado'] = 30
            ..['bono_movilidad_maestro'] = 30
            ..['otros_ingresos_afectos'] = 30;
      payload['liquidacion'] = settlement;

      final context = PayrollSlipPdf.contextFromPayload(payload);

      expect(
        context.incomeLines.where((line) => line.concept == 'Bono movilidad'),
        hasLength(1),
      );
      expect(
        context.incomeLines.any(
          (line) => line.concept == 'Bonos al cargo/labor',
        ),
        isFalse,
      );
    });

    test('organiza el periodo por semanas lunes a domingo y respeta codigos',
        () {
      final context = PayrollSlipPdf.contextFromPayload(_contextPayload());
      final weeks = context.calendarWeeks;

      expect(weeks, hasLength(3));
      expect(weeks.first.start, DateTime(2026, 7, 27));
      expect(weeks.first.cells[5].date, DateTime(2026, 8, 1));
      expect(weeks.first.cells[5].value, '8 h');
      expect(weeks.first.cells[6].value, 'DS');
      expect(weeks[1].cells[0].value, '8 h');
      expect(weeks[1].cells[1].value, 'P');
      expect(weeks[1].cells[2].value, 'C');
      expect(weeks[1].cells[3].value, 'F');
      expect(weeks[1].cells[4].value, 'FE');
    });

    test('acepta arreglos de códigos diarios V2 y conserva horas y condiciones',
        () {
      final payload = _contextPayload(version: 'BOLETA_V2');
      payload['dias'] = [
        {
          'fecha': '2026-08-03',
          'horas_totales': 8,
          'codigos': ['DESCANSO_SEMANAL', 'FERIADO'],
        },
        {
          'fecha': '2026-08-04',
          'horas_totales': 0,
          'codigos': ['PERMISO', 'COMPENSACION'],
        },
        {
          'fecha': '2026-08-05',
          'horas_totales': 0,
          'codigos': ['FALTA'],
        },
      ];
      payload['resumen'] = <String, dynamic>{};
      final context = PayrollSlipPdf.contextFromPayload(payload);
      final cells = context.calendarWeeks[1].cells;

      expect(cells[0].value, '8 h / DS / FE');
      expect(cells[1].value, 'P / C');
      expect(cells[2].value, 'F');
      expect(context.summary.weeklyRestDays, 1);
      expect(context.summary.permissionDays, 1);
      expect(context.summary.absenceDays, 1);
    });

    test('no inventa faltas cuando el detalle oficial viene incompleto', () {
      final payload = _contextPayload();
      payload['dias'] = [
        {'fecha': '2026-08-01', 'horas_totales': 8, 'codigo': ''},
      ];

      final context = PayrollSlipPdf.contextFromPayload(payload);
      expect(context.calendarWeeks.first.cells[6].value, isEmpty);
    });

    test('acepta snapshot y liquidacion anterior si el RPC v2 no existe', () {
      final context = PayrollSlipPdf.contextFromPayload(
        null,
        fallbackSlip: {
          'dni': '91428367',
          'nombres': 'Trabajador historico',
          'puesto': 'OPERARIO',
          'fecha_inicio': '2026-08-01',
          'fecha_fin': '2026-08-15',
        },
        fallbackSnapshot: jsonEncode({
          'remuneracion_basica': 100,
          'neto_pagar': 91,
          'onp': 9,
        }),
      );

      expect(context.usedFallback, isTrue);
      expect(context.worker.name, 'Trabajador historico');
      expect(context.period.start, DateTime(2026, 8, 1));
      expect(context.hasLiquidationData, isTrue);
      expect(context.netPay, 91);
    });

    test('genera un PDF A4 valido a partir del contexto productivo', () async {
      final bytes = await PayrollSlipPdf.build(
        PayrollSlipPdf.contextFromPayload(_contextPayload()),
      );

      expect(bytes.length, greaterThan(100));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('codifica textos españoles en WinAnsi sin depender de una fuente web',
        () async {
      final payload = _contextPayload(version: 'BOLETA_V2');
      final worker = Map<String, dynamic>.from(payload['trabajador'] as Map)
        ..['nombre'] = 'Muñoz Álvarez'
        ..['puesto'] = 'SUPERVISIÓN';
      payload['trabajador'] = worker;
      final bytes = await PayrollSlipPdf.build(
        PayrollSlipPdf.contextFromPayload(payload),
        compress: false,
      );
      final pdfText = latin1.decode(bytes);

      // Helvetica usa WinAnsi para los caracteres españoles (todos dentro de
      // U+0000..U+00FF). La salida sin compresión permite verificar la misma
      // codificación que leerán los extractores PDF, sin red ni TTF añadido.
      expect(pdfText, contains('/WinAnsiEncoding'));
      // El motor fragmenta cada palabra en operadores Tj independientes.
      expect(pdfText, contains('Muñoz'));
      expect(pdfText, contains('Álvarez'));
      expect(pdfText, contains('SUPERVISIÓN'));
      expect(pdfText, contains('Asignación'));
      expect(pdfText, contains('familiar'));
      expect(pdfText, contains('Compensación'));
      expect(pdfText, contains('SUELDO'));
      expect(pdfText, contains('Detalle'));
      expect(pdfText, contains('Horas'));
    });
  });
}
