import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class HumanResourcesRecordPdf {
  static final PdfColor _primary = PdfColor(0.027, 0.231, 0.298);
  static final PdfColor _soft = PdfColor(0.93, 0.97, 0.97);
  static final PdfColor _border = PdfColor(0.75, 0.82, 0.84);

  static Future<Uint8List> buildPermission(Map<String, dynamic> row) async {
    return _build(
      title: 'CONSTANCIA DE PERMISO O LICENCIA',
      subtitle: 'Documento emitido después de la aprobación de la solicitud',
      rows: [
        (
          'N.° de registro',
          _value(row, ['numero', 'numero_permiso', 'id_local', 'id'])
        ),
        (
          'Empresa',
          _value(
              row, ['empresa', 'razon_social', 'empresa_nombre', 'empresa_id'])
        ),
        (
          'Trabajador',
          _value(row, ['trabajador', 'nombre_completo', 'nombres', 'nombre'])
        ),
        ('DNI', _value(row, ['dni', 'documento', 'numero_documento'])),
        ('Cargo / puesto', _value(row, ['cargo', 'puesto'])),
        ('Área', _value(row, ['area', 'unidad', 'sede'])),
        (
          'Tipo de permiso o licencia',
          _value(row, ['tipo_permiso', 'tipo_ausencia'])
        ),
        ('Desde', _value(row, ['fecha_inicio', 'desde'])),
        ('Hasta', _value(row, ['fecha_fin', 'hasta'])),
        (
          'Con goce de haber',
          _yesNo(_raw(row, ['con_goce_haber', 'goce_haber']))
        ),
        ('Motivo', _value(row, ['motivo', 'detalle', 'descripcion'])),
        ('Observaciones', _value(row, ['observaciones', 'comentario'])),
        ('Estado', _value(row, ['estado_aprobacion'], fallback: 'APROBADO')),
        ('Fecha de aprobación', _value(row, ['fecha_aprobacion'])),
      ],
    );
  }

  static Future<Uint8List> buildSanction(Map<String, dynamic> row) async {
    final dismissal = _norm(_value(row, ['tipo_sancion'])) == 'DESPIDO';
    return _build(
      title: dismissal
          ? 'COMUNICACIÓN DE DESPIDO DE PERSONAL'
          : 'COMUNICACIÓN DE SANCIÓN DE PERSONAL',
      subtitle: dismissal
          ? 'Documento emitido después de la aprobación del despido'
          : 'Documento emitido después de la aprobación de la sanción',
      rows: [
        (
          'N.° de registro',
          _value(row, ['numero', 'numero_sancion', 'id_local', 'id'])
        ),
        (
          'Empresa',
          _value(
              row, ['empresa', 'razon_social', 'empresa_nombre', 'empresa_id'])
        ),
        (
          'Trabajador',
          _value(row, ['trabajador', 'nombre_completo', 'nombres', 'nombre'])
        ),
        ('DNI', _value(row, ['dni', 'documento', 'numero_documento'])),
        ('Cargo / puesto', _value(row, ['cargo', 'puesto'])),
        ('Sanción/Despido', _value(row, ['tipo_sancion'])),
        if (dismissal)
          ('Fecha de despido', _value(row, ['fecha_despido']))
        else ...[
          ('Fecha de inicio', _value(row, ['fecha_inicio'])),
          ('Fecha de fin', _value(row, ['fecha_fin'])),
        ],
        ('Motivo', _value(row, ['motivo', 'detalle', 'descripcion'])),
        ('Bloqueo de asistencia', _yesNo(_raw(row, ['bloquea_asistencia']))),
        ('Estado', _value(row, ['estado_aprobacion'], fallback: 'APROBADO')),
        ('Fecha de aprobación', _value(row, ['fecha_aprobacion'])),
      ],
    );
  }

  static String permissionFileName(Map<String, dynamic> row) =>
      'permiso_${_safe(_value(row, ['dni'], fallback: 'registro'))}_${_safe(_value(row, [
            'id_local',
            'id'
          ], fallback: 'aprobado'))}.pdf';

  static String sanctionFileName(Map<String, dynamic> row) =>
      'sancion_${_safe(_value(row, ['dni'], fallback: 'registro'))}_${_safe(_value(row, [
            'id_local',
            'id'
          ], fallback: 'aprobada'))}.pdf';

  static Future<Uint8List> _build({
    required String title,
    required String subtitle,
    required List<(String, String)> rows,
  }) async {
    final pdf = pw.Document(
      title: title,
      author: 'Zumac',
      subject: 'Gestión Humana',
    );
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 44, 42, 42),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (_) => [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(
              color: _soft,
              border: pw.Border.all(color: _border),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              children: [
                pw.Text(
                  'ZUMAC',
                  style: pw.TextStyle(
                    color: _primary,
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 7),
                pw.Text(
                  title,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    color: _primary,
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  subtitle,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 22),
          pw.Table(
            border: pw.TableBorder.all(color: _border, width: 0.7),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.25),
              1: pw.FlexColumnWidth(2.75),
            },
            children: [
              for (final row in rows)
                pw.TableRow(
                  children: [
                    pw.Container(
                      color: _soft,
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        row.$1,
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(row.$2,
                          style: const pw.TextStyle(fontSize: 9)),
                    ),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 65),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _signature('Firma del trabajador'),
              _signature('Firma y sello del responsable'),
            ],
          ),
          pw.SizedBox(height: 28),
          pw.Text(
            'Documento generado por Zumac a partir de un registro aprobado.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  static pw.Widget _signature(String label) => pw.SizedBox(
        width: 190,
        child: pw.Column(
          children: [
            pw.Container(height: 1, color: PdfColors.grey700),
            pw.SizedBox(height: 6),
            pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      );

  static dynamic _raw(Map<String, dynamic> row, List<String> candidates) {
    final wanted = candidates.map(_norm).toSet();
    for (final entry in row.entries) {
      if (wanted.contains(_norm(entry.key))) return entry.value;
    }
    return null;
  }

  static String _value(
    Map<String, dynamic> row,
    List<String> candidates, {
    String fallback = 'No registrado',
  }) {
    final raw = _raw(row, candidates);
    final value = raw?.toString().trim() ?? '';
    return value.isEmpty || value.toUpperCase() == 'NULL' ? fallback : value;
  }

  static String _yesNo(dynamic value) {
    if (value == true || value == 1) return 'Sí';
    final normalized = _norm(value?.toString() ?? '');
    return {'SI', 'S', 'TRUE', '1', 'YES'}.contains(normalized) ? 'Sí' : 'No';
  }

  static String _norm(String value) => value
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  static String _safe(String value) => value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
}
