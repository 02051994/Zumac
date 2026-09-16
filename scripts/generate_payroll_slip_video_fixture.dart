import 'dart:convert';
import 'dart:io';

import 'package:appgt_offline_subtables/features/formats/payroll_slip_pdf.dart';

Future<void> main() async {
  final payload = <String, dynamic>{
    'version': PayrollSlipPdf.contextVersion,
    'es_prueba': true,
    'etiqueta_contexto': 'Escenario de prueba',
    'periodo': {
      'fecha_inicio': '2026-08-01',
      'fecha_fin': '2026-08-15',
    },
    'trabajador': {
      'dni': '91428367',
      'nombre': 'Diego Sebastián Vásquez Medina',
      'puesto': 'SEGURIDAD',
      'sistema_pension': 'ONP - SNP',
      'asignacion_familiar': true,
      'fecha_ingreso': '2024-03-15',
      'sueldo': 1500,
      'tipo_remuneracion': 'JORNAL',
    },
    'resumen': {
      'dias_trabajados': 10,
      'descansos_semanales': 2,
      'dias_permisos': 2,
      'faltas': 1,
    },
    'liquidacion': {
      'tipo_remuneracion': 'JORNAL',
      'remuneracion_basica_jornales': 500,
      'descanso_semanal': 91.67,
      'licencias_pagadas_sin_compensacion': 50,
      'compensacion_pagada': 50,
      'asignacion_familiar': 56.50,
      'horas_nocturnas': 8,
      'nocturnidad_importe': 15,
      'horas_extra_25_importe': 31.25,
      'horas_extra_35_importe': 16.88,
      'bono_movilidad_pagado': 150,
      'bono_cargo_pagado': 100,
      'bono_labor_pagado': 40,
      'cts_pagada': 107.05,
      'gratificacion_pagada': 183.45,
      'bono_extraordinario_gratificacion': 16.51,
      'beta_pagado': 169.50,
      'onp': 143.17,
      'essalud_empleador': 66.08,
      'remuneracion_bruta': 1577.81,
      'total_descuentos': 143.17,
      'neto_pagar': 1434.64,
    },
    'dias': [
      {'fecha': '2026-08-01', 'horas_totales': 8, 'codigo': ''},
      {'fecha': '2026-08-02', 'horas_totales': 0, 'codigo': 'DS'},
      {'fecha': '2026-08-03', 'horas_totales': 8, 'codigo': ''},
      {'fecha': '2026-08-04', 'horas_totales': 8, 'codigo': ''},
      {'fecha': '2026-08-05', 'horas_totales': 0, 'codigo': 'C'},
      {'fecha': '2026-08-06', 'horas_totales': 8, 'codigo': ''},
      {'fecha': '2026-08-07', 'horas_totales': 12, 'codigo': ''},
      {'fecha': '2026-08-08', 'horas_totales': 0, 'codigo': 'F'},
      {'fecha': '2026-08-09', 'horas_totales': 0, 'codigo': 'DS'},
      {'fecha': '2026-08-10', 'horas_totales': 8, 'codigo': ''},
      {'fecha': '2026-08-11', 'horas_totales': 0, 'codigo': 'P'},
      {'fecha': '2026-08-12', 'horas_totales': 8, 'codigo': ''},
      {'fecha': '2026-08-13', 'horas_totales': 10, 'codigo': ''},
      {'fecha': '2026-08-14', 'horas_totales': 8, 'codigo': ''},
      {'fecha': '2026-08-15', 'horas_totales': 8, 'codigo': ''},
    ],
  };
  final context = PayrollSlipPdf.contextFromPayload(
    jsonDecode(jsonEncode(payload)),
  );
  final output = File('output/pdf/boleta_prueba_91428367_v3.pdf');
  await output.parent.create(recursive: true);
  await output.writeAsBytes(await PayrollSlipPdf.build(context));
  stdout.writeln(output.absolute.path);
}
