import 'dart:convert';

import 'package:appgt_offline_subtables/features/formats/hr_record_document_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('genera constancia PDF imprimible para permiso aprobado', () async {
    final bytes = await HumanResourcesRecordPdf.buildPermission({
      'id_local': 'permiso-1',
      'dni': '12345678',
      'trabajador': 'Persona de prueba',
      'tipo_permiso': 'DESCANSO MEDICO',
      'fecha_inicio': '2026-09-29',
      'fecha_fin': '2026-09-30',
      'con_goce_haber': true,
      'ESTADO_APROBACION': 'APROBADO',
    });

    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(
      HumanResourcesRecordPdf.permissionFileName({
        'id_local': 'permiso-1',
        'dni': '12345678',
      }),
      'permiso_12345678_permiso-1.pdf',
    );
  });

  test('genera comunicacion PDF imprimible para sancion aprobada', () async {
    final bytes = await HumanResourcesRecordPdf.buildSanction({
      'id_local': 'sancion-1',
      'dni': '87654321',
      'trabajador': 'Persona de prueba',
      'tipo_sancion': 'SUSPENSION DE LABORES',
      'bloquea_asistencia': true,
      'ESTADO_APROBACION': 'APROBADO',
    });

    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(
      HumanResourcesRecordPdf.sanctionFileName({
        'id_local': 'sancion-1',
        'dni': '87654321',
      }),
      'sancion_87654321_sancion-1.pdf',
    );
  });

  test('genera comunicacion PDF para un despido aprobado', () async {
    final bytes = await HumanResourcesRecordPdf.buildSanction({
      'id_local': 'despido-1',
      'dni': '87654321',
      'trabajador': 'Persona de prueba',
      'tipo_sancion': 'DESPIDO',
      'fecha_despido': '2026-10-07',
      'ESTADO_APROBACION': 'APROBADO',
    });

    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
  });
}
