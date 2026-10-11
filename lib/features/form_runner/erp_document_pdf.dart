import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ScaffoldMessenger;
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/platform/pdf_open.dart';
import '../../core/services/evidence_storage.dart';
import '../../core/widgets/zumac_scaffold_messenger.dart';

class ErpDocumentPdf {
  static const bucket = 'documentos-erp';

  static const _titles = <String, String>{
    'ERP_SOLICITUDES_COMPRA_APPGT': 'SOLICITUD DE PEDIDO',
    'ERP_ORDENES_COMPRA_APPGT': 'ORDEN DE COMPRA',
    'ERP_INGRESOS_ALMACEN_APPGT': 'INGRESO EN ALMACÉN',
    'ERP_VALES_DESPACHO_APPGT': 'VALE DE DESPACHO',
  };

  static const _detailContract = <String, ({String table, String foreignKey})>{
    'ERP_SOLICITUDES_COMPRA_APPGT': (
      table: 'ERP_SOLICITUDES_COMPRA_DETALLE_APPGT',
      foreignKey: 'solicitud_numero',
    ),
    'ERP_ORDENES_COMPRA_APPGT': (
      table: 'ERP_ORDENES_COMPRA_DETALLE_APPGT',
      foreignKey: 'orden_numero',
    ),
    'ERP_INGRESOS_ALMACEN_APPGT': (
      table: 'ERP_INGRESOS_ALMACEN_DETALLE_APPGT',
      foreignKey: 'ingreso_numero',
    ),
    'ERP_VALES_DESPACHO_APPGT': (
      table: 'ERP_VALES_DESPACHO_DETALLE_APPGT',
      foreignKey: 'vale_numero',
    ),
  };

  static bool supports(String table) => _titles.containsKey(table.trim());

  static bool mayGenerate(String table, Map<String, dynamic> row) {
    final state = _value(row, 'estado').toUpperCase();
    if (table == 'ERP_INGRESOS_ALMACEN_APPGT') {
      return state == 'CONFIRMADO' || state == 'ANULADO';
    }
    return const {
      'APROBADO',
      'DESPACHADO PARCIALMENTE',
      'DESPACHADO',
    }.contains(state);
  }

  static bool canOpenOrGenerate(String table, Map<String, dynamic> row) =>
      _value(row, 'pdf_url').isNotEmpty || mayGenerate(table, row);

  static Future<void> openOrGenerate({
    required BuildContext context,
    required SupabaseClient client,
    required String table,
    required Map<String, dynamic> row,
  }) async {
    final number = _value(row, 'numero');
    if (!supports(table) || number.isEmpty) {
      throw StateError('No se pudo identificar el documento ERP.');
    }
    final stored = _value(row, 'pdf_url');
    final state = _value(row, 'estado').toUpperCase();
    final storedState = _value(row, 'pdf_estado').toUpperCase();
    Uint8List bytes;
    if (stored.isNotEmpty && storedState == state) {
      bytes = await _download(client, stored);
    } else {
      if (!mayGenerate(table, row) && stored.isEmpty) {
        throw StateError(
          table == 'ERP_INGRESOS_ALMACEN_APPGT'
              ? 'El ingreso todavía no puede generar un PDF.'
              : 'El PDF se genera desde el estado APROBADO.',
        );
      }
      bytes = await _generate(client: client, table: table, row: row);
      final companyId = _value(row, 'empresa_id');
      if (companyId.isEmpty) {
        throw StateError('El documento no contiene la empresa asociada.');
      }
      final safeNumber = _safe(number);
      final folder = table.toLowerCase().replaceAll('_appgt', '');
      final path = '$companyId/$folder/$safeNumber.pdf';
      await client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions:
                const FileOptions(contentType: 'application/pdf', upsert: true),
          );
      final uri = EvidenceStorage.toStorageUri(path, bucketName: bucket);
      await client.rpc('erp_registrar_pdf_documento_v1', params: {
        'p_tabla': table,
        'p_numero': number,
        'p_pdf_url': uri,
      });
      row['pdf_url'] = uri;
      row['pdf_generado_at'] = DateTime.now().toUtc().toIso8601String();
      row['pdf_estado'] = state;
    }
    await _open('${_safe(number)}.pdf', bytes);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF preparado correctamente.')),
      );
    }
  }

  static Future<Uint8List> _download(
      SupabaseClient client, String storageUri) async {
    final parsed = EvidenceStorage.extractBucketAndPath(storageUri);
    if (parsed == null) {
      throw StateError('La referencia del PDF almacenado no es válida.');
    }
    final bytes =
        await client.storage.from(parsed.bucket).download(parsed.path);
    if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw StateError('El archivo almacenado no es un PDF válido.');
    }
    return bytes;
  }

  static Future<void> _open(String fileName, Uint8List bytes) async {
    if (await openPdfBytes(fileName: fileName, bytes: bytes)) return;
    if (kIsWeb) return;
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await OpenFilex.open(file.path);
  }

  static Future<Uint8List> _generate({
    required SupabaseClient client,
    required String table,
    required Map<String, dynamic> row,
  }) async {
    final contract = _detailContract[table]!;
    final number = _value(row, 'numero');
    final detailsRaw = await client
        .from(contract.table)
        .select()
        .eq(contract.foreignKey, number)
        .eq('eliminado', false)
        .order('linea');
    final details = (detailsRaw as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    final companyId = _value(row, 'empresa_id');
    Map<String, dynamic> company = const {};
    if (companyId.isNotEmpty) {
      final raw = await client
          .from('EMPRESAS_APPGT')
          .select('codigo,nombre,email')
          .eq('id', companyId)
          .maybeSingle();
      if (raw != null) company = Map<String, dynamic>.from(raw);
    }

    Map<String, dynamic> provider = const {};
    final providerCode = _value(row, 'proveedor_codigo');
    if (providerCode.isNotEmpty) {
      final raw = await client
          .from('ERP_PROVEEDORES_APPGT')
          .select('codigo,razon_social,ruc,direccion,telefono,email,contacto')
          .eq('codigo', providerCode)
          .maybeSingle();
      if (raw != null) provider = Map<String, dynamic>.from(raw);
    }

    final actorNames = await _actorNames(client, row);
    final logoData = await rootBundle.load('assets/images/logo_app.png');
    final logo = pw.MemoryImage(logoData.buffer.asUint8List());
    final pdf = pw.Document(
      title: '${_titles[table]} $number',
      author: _value(company, 'nombre').isEmpty
          ? 'Zumac'
          : _value(company, 'nombre'),
    );
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 24),
        header: (_) => _header(
          logo: logo,
          company: company,
          title: _titles[table]!,
          number: number,
        ),
        footer: (page) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: PdfColors.grey500)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Documento generado por Zumac',
                  style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Página ${page.pageNumber} de ${page.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
        ),
        build: (_) => [
          pw.SizedBox(height: 14),
          _summary(table, row, provider),
          pw.SizedBox(height: 14),
          _detailsTable(table, details),
          if (table == 'ERP_ORDENES_COMPRA_APPGT') ...[
            pw.SizedBox(height: 12),
            _purchaseTotals(row),
          ],
          pw.SizedBox(height: 14),
          _observations(row),
          pw.SizedBox(height: 18),
          _workflow(row, actorNames),
        ],
      ),
    );
    return pdf.save();
  }

  static Future<Map<String, String>> _actorNames(
      SupabaseClient client, Map<String, dynamic> row) async {
    final ids = <String>{};
    for (final key in const [
      'revisado_por',
      'aprobado_por',
      'confirmado_por',
      'despachado_por',
      'anulado_por',
    ]) {
      final id = _value(row, key);
      if (id.isNotEmpty) ids.add(id);
    }
    if (ids.isEmpty) return const {};
    try {
      final raw = await client
          .from('PERFILES_DE_USUARIOS_APPGT')
          .select('id,nombres,apellido_paterno,apellido_materno,DNI')
          .inFilter('id', ids.toList());
      return {
        for (final item in (raw as List).whereType<Map>())
          '${item['id']}': [
            item['nombres'],
            item['apellido_paterno'],
            item['apellido_materno'],
          ]
              .map((value) => value?.toString().trim() ?? '')
              .where((value) => value.isNotEmpty)
              .join(' '),
      };
    } catch (_) {
      return const {};
    }
  }

  static pw.Widget _header({
    required pw.MemoryImage logo,
    required Map<String, dynamic> company,
    required String title,
    required String number,
  }) {
    final companyName = _value(company, 'nombre').isEmpty
        ? 'EMPRESA'
        : _value(company, 'nombre');
    final email = _value(company, 'email');
    return pw.Column(children: [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(width: 118, height: 52, child: pw.Image(logo)),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(companyName,
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold)),
              if (_value(company, 'codigo').isNotEmpty)
                pw.Text('Código: ${_value(company, 'codigo')}',
                    style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Correo electrónico: ${email.isEmpty ? '-' : email}',
                  style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
        ),
        pw.Container(
          width: 142,
          padding: const pw.EdgeInsets.all(7),
          decoration: pw.BoxDecoration(border: pw.Border.all()),
          child: pw.Column(children: [
            pw.Text('CÓDIGO',
                style:
                    pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            pw.Text(number,
                textAlign: pw.TextAlign.center,
                style:
                    pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
      ]),
      pw.SizedBox(height: 8),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 7),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(width: 1.2),
            bottom: pw.BorderSide(width: 1.2),
          ),
        ),
        child: pw.Text(title,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      ),
    ]);
  }

  static pw.Widget _summary(
      String table, Map<String, dynamic> row, Map<String, dynamic> provider) {
    final values = <(String, String)>[];
    if (table == 'ERP_SOLICITUDES_COMPRA_APPGT') {
      values.addAll([
        ('Fecha', _date(row, 'fecha')),
        ('Fecha de necesidad', _date(row, 'fecha_necesidad')),
        ('Solicitante', _value(row, 'solicitante')),
        ('Área', _value(row, 'area')),
        ('Proveedor', _value(row, 'proveedor_codigo')),
        ('Almacén', _value(row, 'almacen_codigo')),
      ]);
    } else if (table == 'ERP_ORDENES_COMPRA_APPGT') {
      values.addAll([
        ('Proveedor', _value(provider, 'razon_social')),
        ('RUC', _value(provider, 'ruc')),
        ('Domicilio fiscal', _value(provider, 'direccion')),
        ('Teléfono', _value(provider, 'telefono')),
        ('Correo', _value(provider, 'email')),
        ('Fecha de emisión', _date(row, 'fecha_emision')),
        ('Fecha de entrega programada', _date(row, 'fecha_entrega')),
        ('Forma de pago', _value(row, 'condicion_pago')),
        ('Moneda', _value(row, 'moneda')),
        ('Almacén', _value(row, 'almacen_codigo')),
      ]);
    } else if (table == 'ERP_INGRESOS_ALMACEN_APPGT') {
      values.addAll([
        ('Fecha de ingreso', _date(row, 'fecha_ingreso')),
        ('Orden de compra', _value(row, 'orden_numero')),
        ('Proveedor', _value(provider, 'razon_social')),
        ('RUC', _value(row, 'proveedor_ruc')),
        ('Almacén', _value(row, 'almacen_codigo')),
        ('Tipo de documento', _value(row, 'tipo_documento')),
        ('Número de documento', _value(row, 'guia_remision')),
        ('Usuario', _value(row, 'usuario')),
      ]);
    } else {
      values.addAll([
        ('Fecha', _date(row, 'fecha')),
        ('Usuario', _value(row, 'usuario_nombre')),
        ('DNI', _value(row, 'usuario_dni')),
        ('Tipo de destino', _value(row, 'tipo_destino')),
        ('Centro de costo', _value(row, 'centro_costo')),
        ('Almacén', _value(row, 'almacen_codigo')),
      ]);
    }
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey500, width: .5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(2.8),
      },
      children: values
          .where((item) => item.$2.isNotEmpty)
          .map((item) => pw.TableRow(children: [
                _cell(item.$1, bold: true, shade: true),
                _cell(item.$2),
              ]))
          .toList(),
    );
  }

  static pw.Widget _detailsTable(
      String table, List<Map<String, dynamic>> details) {
    final columns = switch (table) {
      'ERP_ORDENES_COMPRA_APPGT' => const [
          ('Código', 'articulo_codigo'),
          ('Descripción', 'descripcion'),
          ('Unidad', 'unidad_medida'),
          ('Almacén', 'almacen_destino_codigo'),
          ('Solicitado', 'cantidad_solicitada'),
          ('Cantidad OC', 'cantidad'),
          ('Recibido', 'cantidad_recibida'),
          ('Precio', 'precio_unitario'),
          ('% Dcto', 'descuento_porcentaje'),
          ('Importe', 'subtotal'),
        ],
      'ERP_INGRESOS_ALMACEN_APPGT' => const [
          ('OC', 'orden_numero'),
          ('Solicitud', 'solicitud_numero'),
          ('Código', 'articulo_codigo'),
          ('Descripción', 'descripcion'),
          ('Unidad', 'unidad_medida'),
          ('Almacén', 'almacen_codigo'),
          ('Ordenada', 'cantidad_ordenada'),
          ('Pendiente', 'cantidad_pendiente'),
          ('Recibido', 'cantidad_recibida'),
        ],
      'ERP_VALES_DESPACHO_APPGT' => const [
          ('Código', 'articulo_codigo'),
          ('Descripción', 'descripcion'),
          ('Unidad', 'unidad_medida'),
          ('Cantidad', 'cantidad_solicitada'),
          ('Centro costo', 'centro_costo'),
          ('Lote', 'lote'),
        ],
      _ => const [
          ('Código', 'articulo_codigo'),
          ('Descripción', 'descripcion'),
          ('Unidad', 'unidad_medida'),
          ('Cantidad', 'cantidad_solicitada'),
          ('Precio unitario', 'precio_unitario'),
          ('Total', 'total'),
          ('Recibido', 'cantidad_recibida'),
          ('Estado recibido', 'estado_de_recibido'),
          ('OC aprobada', 'fecha_oc_aprobada'),
          ('Recibida', 'fecha_recibida'),
          ('Fecha requerida', 'fecha_necesidad'),
          ('Almacén', 'almacen_destino_codigo'),
        ],
    };
    if (details.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(border: pw.Border.all()),
        child: pw.Text('Sin ítems registrados.'),
      );
    }
    return pw.TableHelper.fromTextArray(
      headers: columns.map((column) => column.$1).toList(),
      data: details
          .map((detail) =>
              columns.map((column) => _display(detail[column.$2])).toList())
          .toList(),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
      headerStyle: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 7.5,
          fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 7.5),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      border: pw.TableBorder.all(color: PdfColors.grey500, width: .45),
    );
  }

  static pw.Widget _purchaseTotals(Map<String, dynamic> row) {
    final money = <(String, String)>[
      ('Importe de ítems', _money(row, 'importe_bruto')),
      (
        'Descuento total',
        _value(row, 'otros_descuentos').isEmpty
            ? _money(row, 'descuento')
            : _money(row, 'otros_descuentos')
      ),
      ('Subtotal', _money(row, 'subtotal')),
      ('Impuesto (IGV 18%)', _money(row, 'impuesto')),
      ('Total', _money(row, 'total')),
    ];
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(
        width: 220,
        child: pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey500, width: .5),
          children: money
              .map((item) => pw.TableRow(children: [
                    _cell(item.$1, bold: item.$1 == 'Total', shade: true),
                    _cell(item.$2,
                        bold: item.$1 == 'Total', align: pw.TextAlign.right),
                  ]))
              .toList(),
        ),
      ),
    );
  }

  static pw.Widget _observations(Map<String, dynamic> row) {
    final text = _value(row, 'observacion').isNotEmpty
        ? _value(row, 'observacion')
        : _value(row, 'justificacion');
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all()),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('OBSERVACIONES',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(text.isEmpty ? '-' : text,
              style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
  }

  static pw.Widget _workflow(
      Map<String, dynamic> row, Map<String, String> actorNames) {
    final state = _value(row, 'estado').toUpperCase();
    final events = <(String, String, String)>[];
    void add(String label, String actorKey, String dateKey) {
      final actorId = _value(row, actorKey);
      final date = _date(row, dateKey, includeTime: true);
      if (actorId.isEmpty && date.isEmpty) return;
      events.add((
        label,
        actorNames[actorId]?.trim().isNotEmpty == true
            ? actorNames[actorId]!
            : actorId,
        date
      ));
    }

    add('Revisado por', 'revisado_por', 'revisado_at');
    add('Aprobado por', 'aprobado_por', 'aprobado_at');
    add('Confirmado por', 'confirmado_por', 'confirmado_at');
    add('Despachado por', 'despachado_por', 'despachado_at');
    add('Anulado por', 'anulado_por', 'anulado_at');
    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: PdfColors.blueGrey800,
            child: pw.Text('ESTADO REAL: $state',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold)),
          ),
          if (events.isNotEmpty)
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey500, width: .5),
              children: events
                  .map((event) => pw.TableRow(children: [
                        _cell(event.$1, bold: true, shade: true),
                        _cell(event.$2),
                        _cell(event.$3),
                      ]))
                  .toList(),
            ),
        ]);
  }

  static pw.Widget _cell(String value,
      {bool bold = false,
      bool shade = false,
      pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Container(
      color: shade ? PdfColors.grey200 : null,
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(value.isEmpty ? '-' : value,
          textAlign: align,
          style: pw.TextStyle(
              fontSize: 8,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
  }

  static String _value(Map<String, dynamic> row, String key) {
    final wanted = key.toLowerCase();
    for (final entry in row.entries) {
      if (entry.key.toLowerCase() == wanted) {
        final text = entry.value?.toString().trim() ?? '';
        return text.toUpperCase() == 'NULL' ? '' : text;
      }
    }
    return '';
  }

  static String _date(Map<String, dynamic> row, String key,
      {bool includeTime = false}) {
    final value = _value(row, key);
    if (value.isEmpty) return '';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final date =
        '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
    if (!includeTime) return date;
    return '$date ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  static String _money(Map<String, dynamic> row, String key) {
    final value = num.tryParse(_value(row, key).replaceAll(',', '.')) ?? 0;
    return '${_value(row, 'moneda').isEmpty ? 'S/' : _value(row, 'moneda')} ${value.toStringAsFixed(2)}';
  }

  static String _display(dynamic value) {
    if (value == null) return '';
    if (value is num) {
      final text = value.toStringAsFixed(6);
      return text.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    final text = value.toString().trim();
    return text.toUpperCase() == 'NULL' ? '' : text;
  }

  static String _safe(String value) => value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
}
