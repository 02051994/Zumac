import 'package:flutter/material.dart' hide ScaffoldMessenger;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/zumac_scaffold_messenger.dart';
import 'erp_document_pdf.dart';
import 'erp_purchase_math.dart';

String _text(dynamic value) => value?.toString().trim() ?? '';

String _date(dynamic value, {String fallback = ''}) {
  final text = _text(value);
  if (text.isEmpty) return fallback;
  return text.length <= 10 ? text : text.substring(0, 10);
}

String _todayValue() => DateTime.now().toIso8601String().substring(0, 10);

InputDecoration _decoration(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
    );

class _PurchaseOrderLine {
  final String requestNumber;
  final int requestLine;
  final TextEditingController articleCode;
  final double requestedQuantity;
  final TextEditingController description;
  final TextEditingController unit;
  final TextEditingController quantity;
  final TextEditingController price;
  final TextEditingController discountPercent;
  final String? costCenter;
  final String? agriculturalLot;
  String? warehouse;
  final double receivedQuantity;
  final String requestedDate;
  final String approvedDate;
  final String receivedDate;

  _PurchaseOrderLine({
    required this.requestNumber,
    required this.requestLine,
    required String articleCode,
    required this.requestedQuantity,
    required String description,
    required String unit,
    required String quantity,
    required String price,
    required String discountPercent,
    this.costCenter,
    this.agriculturalLot,
    this.warehouse,
    this.receivedQuantity = 0,
    this.requestedDate = '',
    this.approvedDate = '',
    this.receivedDate = '',
  })  : articleCode = TextEditingController(text: articleCode),
        description = TextEditingController(text: description),
        unit = TextEditingController(text: unit),
        quantity = TextEditingController(text: quantity),
        price = TextEditingController(text: price),
        discountPercent = TextEditingController(text: discountPercent);

  double get amount {
    final qty = double.tryParse(quantity.text.replaceAll(',', '.')) ?? 0;
    final unitPrice = double.tryParse(price.text.replaceAll(',', '.')) ?? 0;
    final discount =
        double.tryParse(discountPercent.text.replaceAll(',', '.')) ?? 0;
    return qty * unitPrice * (1 - discount.clamp(0, 100).toDouble() / 100);
  }

  Map<String, dynamic> toJson() => {
        'solicitud_numero': requestNumber,
        'solicitud_linea': requestLine,
        'articulo_codigo': articleCode.text.trim(),
        'descripcion': description.text.trim(),
        'unidad_medida': unit.text.trim(),
        'cantidad': double.tryParse(quantity.text.replaceAll(',', '.')) ?? 0,
        'cantidad_solicitada': requestedQuantity,
        'precio_unitario':
            double.tryParse(price.text.replaceAll(',', '.')) ?? 0,
        'descuento_porcentaje':
            double.tryParse(discountPercent.text.replaceAll(',', '.')) ?? 0,
        'centro_costo': costCenter,
        'lote_agricola': agriculturalLot,
        'almacen_destino_codigo': warehouse,
      };

  void dispose() {
    articleCode.dispose();
    description.dispose();
    unit.dispose();
    quantity.dispose();
    price.dispose();
    discountPercent.dispose();
  }
}

class ErpPurchaseOrderPage extends StatefulWidget {
  final Map<String, dynamic>? initialPayload;
  final VoidCallback? onSavedAndExit;

  const ErpPurchaseOrderPage({
    super.key,
    this.initialPayload,
    this.onSavedAndExit,
  });

  @override
  State<ErpPurchaseOrderPage> createState() => _ErpPurchaseOrderPageState();
}

class _ErpPurchaseOrderPageState extends State<ErpPurchaseOrderPage> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  late final TextEditingController _issueDate;
  late final TextEditingController _deliveryDate;
  late final TextEditingController _exchangeRate;
  late final TextEditingController _paymentTerms;
  late final TextEditingController _observation;
  late final TextEditingController _discount;
  final List<_PurchaseOrderLine> _lines = [];
  final List<String> _requestNumbers = [];
  List<Map<String, dynamic>> _approvedRequests = [];
  List<Map<String, dynamic>> _providers = [];
  List<Map<String, dynamic>> _warehouses = [];
  String? _provider;
  String? _warehouse;
  String _currency = 'PEN';
  bool _includesIgv = false;
  bool _loading = true;
  bool _saving = false;

  Map<String, dynamic> get _initial => widget.initialPayload ?? const {};
  String get _code => _text(_initial['numero'] ?? _initial['NUMERO']);
  String get _state =>
      _text(_initial['estado'] ?? _initial['ESTADO']).toUpperCase();
  bool get _editable =>
      _code.isEmpty || _state == 'PENDIENTE' || _state == 'REVISADO';

  double get _itemsAmount =>
      _lines.fold<double>(0, (sum, line) => sum + line.amount);
  double get _discountValue =>
      (double.tryParse(_discount.text.replaceAll(',', '.')) ?? 0)
          .clamp(0, double.infinity)
          .toDouble();
  ErpPurchaseTotals get _totals => ErpPurchaseTotals.calculate(
        itemAmount: _itemsAmount,
        discount: _discountValue,
        includesIgv: _includesIgv,
      );

  @override
  void initState() {
    super.initState();
    _issueDate = TextEditingController(
      text: _date(_initial['fecha_emision'] ?? _initial['FECHA_EMISION'],
          fallback: _todayValue()),
    );
    _deliveryDate = TextEditingController(
      text: _date(_initial['fecha_entrega'] ?? _initial['FECHA_ENTREGA']),
    );
    _exchangeRate = TextEditingController(
      text: _text(_initial['tipo_cambio'] ?? _initial['TIPO_CAMBIO']).isEmpty
          ? '1'
          : _text(_initial['tipo_cambio'] ?? _initial['TIPO_CAMBIO']),
    );
    _paymentTerms = TextEditingController(
      text: _text(_initial['condicion_pago'] ?? _initial['CONDICION_PAGO']),
    );
    _observation = TextEditingController(
      text: _text(_initial['observacion'] ?? _initial['OBSERVACION']),
    );
    _discount = TextEditingController(
      text: _text(_initial['descuento'] ?? _initial['DESCUENTO']).isEmpty
          ? '0'
          : _text(_initial['descuento'] ?? _initial['DESCUENTO']),
    );
    _provider =
        _nullable(_initial['proveedor_codigo'] ?? _initial['PROVEEDOR_CODIGO']);
    _warehouse =
        _nullable(_initial['almacen_codigo'] ?? _initial['ALMACEN_CODIGO']);
    _currency = _text(_initial['moneda'] ?? _initial['MONEDA']).toUpperCase();
    if (!const {'PEN', 'USD', 'EUR'}.contains(_currency)) _currency = 'PEN';
    _includesIgv = _bool(_initial['con_igv'] ?? _initial['CON_IGV']);
    _load();
  }

  String? _nullable(dynamic value) {
    final text = _text(value);
    return text.isEmpty || text.toUpperCase() == 'NULL' ? null : text;
  }

  bool _bool(dynamic value) {
    if (value is bool) return value;
    return const {'1', 'TRUE', 'SI', 'SÍ', 'YES'}
        .contains(_text(value).toUpperCase());
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _client.rpc('erp_solicitudes_aprobadas_oc_v1'),
        _client
            .from('ERP_PROVEEDORES_APPGT')
            .select('codigo,razon_social,ruc,email')
            .eq('estado', 'ACTIVO')
            .eq('eliminado', false)
            .order('razon_social'),
        _client
            .from('ERP_ALMACENES_APPGT')
            .select('codigo,nombre')
            .eq('estado', 'ACTIVO')
            .eq('eliminado', false)
            .order('nombre'),
      ]);
      _approvedRequests = _rows(results[0]);
      _providers = _rows(results[1]);
      _warehouses = _rows(results[2]);
      if (_code.isNotEmpty) {
        final existing = await Future.wait<dynamic>([
          _client
              .from('ERP_ORDENES_COMPRA_SOLICITUDES_APPGT')
              .select('solicitud_numero')
              .eq('orden_numero', _code)
              .eq('eliminado', false),
          _client
              .from('ERP_ORDENES_COMPRA_DETALLE_APPGT')
              .select()
              .eq('orden_numero', _code)
              .eq('eliminado', false)
              .order('linea'),
        ]);
        _requestNumbers.addAll(_rows(existing[0])
            .map((row) => _text(row['solicitud_numero']))
            .where((value) => value.isNotEmpty));
        for (final row in _rows(existing[1])) {
          final request = _text(row['solicitud_numero']);
          if (request.isNotEmpty && !_requestNumbers.contains(request)) {
            _requestNumbers.add(request);
          }
          _lines.add(_PurchaseOrderLine(
            requestNumber: request,
            requestLine: int.tryParse(_text(row['solicitud_linea'])) ?? 0,
            articleCode: _text(row['articulo_codigo']),
            requestedQuantity:
                double.tryParse(_text(row['cantidad_solicitada'])) ?? 0,
            description: _text(row['descripcion']),
            unit: _text(row['unidad_medida']),
            quantity: _text(row['cantidad']),
            price: _text(row['precio_unitario']),
            discountPercent: _text(row['descuento_porcentaje']),
            costCenter: _nullable(row['centro_costo']),
            agriculturalLot: _nullable(row['lote_agricola']),
            warehouse: _nullable(row['almacen_destino_codigo']) ?? _warehouse,
            receivedQuantity:
                double.tryParse(_text(row['cantidad_recibida'])) ?? 0,
            requestedDate: _date(row['fecha_solicitada']),
            approvedDate: _date(row['fecha_oc_aprobada']),
            receivedDate: _date(row['fecha_recibida']),
          ));
        }
      }
    } catch (error) {
      if (mounted) _toast('No se pudo cargar la orden: $error', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade800 : Colors.green.shade800,
    ));
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(controller.text) ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      controller.text = picked.toIso8601String().substring(0, 10);
    }
  }

  Future<void> _addRequest() async {
    final available = _approvedRequests
        .where((row) => !_requestNumbers.contains(_text(row['numero'])))
        .toList();
    if (available.isEmpty) {
      _toast('No hay solicitudes aprobadas pendientes de agregar.',
          error: true);
      return;
    }
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        title: const Text('Agregar solicitud aprobada'),
        content: SizedBox(
          width: 620,
          height: 420,
          child: ListView.builder(
            itemCount: available.length,
            itemBuilder: (_, index) {
              final row = available[index];
              return ListTile(
                title: Text(_text(row['numero'])),
                subtitle: Text([
                  _text(row['solicitante']),
                  _text(row['area']),
                  _date(row['fecha']),
                ].where((value) => value.isNotEmpty).join(' · ')),
                onTap: () => Navigator.pop(dialogContext, row),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final requestNumber = _text(selected['numero']);
    final details = _rows(selected['detalles']);
    setState(() {
      _requestNumbers.add(requestNumber);
      for (final detail in details) {
        _lines.add(_PurchaseOrderLine(
          requestNumber: requestNumber,
          requestLine: int.tryParse(_text(detail['linea'])) ?? 0,
          articleCode: _text(detail['articulo_codigo']),
          requestedQuantity:
              double.tryParse(_text(detail['cantidad_solicitada'])) ?? 0,
          description: _text(detail['descripcion']),
          unit: _text(detail['unidad_medida']),
          quantity: _text(detail['cantidad_solicitada']),
          price: _text(detail['precio_referencial']).isEmpty
              ? '0'
              : _text(detail['precio_referencial']),
          discountPercent: '0',
          costCenter: _nullable(selected['centro_costo']),
          warehouse: _nullable(detail['almacen_destino_codigo']) ?? _warehouse,
          receivedQuantity:
              double.tryParse(_text(detail['cantidad_recibida'])) ?? 0,
          requestedDate: _date(detail['fecha_solicitada'],
              fallback: _date(selected['fecha'])),
          approvedDate: _date(detail['fecha_oc_aprobada']),
          receivedDate: _date(detail['fecha_recibida']),
        ));
        _provider ??= _nullable(detail['proveedor_recomendado_codigo']);
        _warehouse ??= _nullable(detail['almacen_destino_codigo']);
      }
    });
  }

  void _removeRequest(String requestNumber) {
    setState(() {
      _requestNumbers.remove(requestNumber);
      final removed =
          _lines.where((line) => line.requestNumber == requestNumber).toList();
      _lines.removeWhere((line) => line.requestNumber == requestNumber);
      for (final line in removed) {
        line.dispose();
      }
    });
  }

  Future<void> _save() async {
    if (!_editable || !_formKey.currentState!.validate()) return;
    if (_requestNumbers.isEmpty || _lines.isEmpty) {
      _toast('Agregue al menos una solicitud aprobada.', error: true);
      return;
    }
    if (_provider == null || _warehouse == null) {
      _toast('Seleccione proveedor y almacén.', error: true);
      return;
    }
    if (_discountValue > _itemsAmount) {
      _toast('El descuento no puede superar el importe de los ítems.',
          error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final raw = await _client.rpc('erp_guardar_orden_compra_v1', params: {
        'p_codigo': _code.isEmpty ? null : _code,
        'p_proveedor_codigo': _provider,
        'p_fecha_emision': _issueDate.text,
        'p_fecha_entrega':
            _deliveryDate.text.trim().isEmpty ? null : _deliveryDate.text,
        'p_moneda': _currency,
        'p_tipo_cambio':
            double.tryParse(_exchangeRate.text.replaceAll(',', '.')) ?? 1,
        'p_condicion_pago': _paymentTerms.text.trim(),
        'p_almacen_codigo': _warehouse,
        'p_observacion': _observation.text.trim(),
        'p_con_igv': _includesIgv,
        'p_descuento': _discountValue,
        'p_solicitudes':
            _requestNumbers.map((number) => {'numero': number}).toList(),
        'p_detalles': _lines.map((line) => line.toJson()).toList(),
      });
      final result = raw is Map ? Map<String, dynamic>.from(raw) : const {};
      if (!mounted) return;
      _toast('Orden ${result['codigo'] ?? _code} guardada correctamente.');
      widget.onSavedAndExit?.call();
    } catch (error) {
      if (mounted) _toast('No se pudo guardar la orden: $error', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pdf() async {
    setState(() => _saving = true);
    try {
      await ErpDocumentPdf.openOrGenerate(
        context: context,
        client: _client,
        table: 'ERP_ORDENES_COMPRA_APPGT',
        row: _initial,
      );
    } catch (error) {
      if (mounted) {
        _toast(error.toString().replaceFirst('Bad state: ', ''), error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController controller, String label,
      {double width = 230,
      bool required = false,
      bool readOnly = false,
      TextInputType? keyboardType,
      ValueChanged<String>? onChanged}) {
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: controller,
        readOnly: readOnly || !_editable,
        keyboardType: keyboardType,
        decoration: _decoration(label),
        onChanged: onChanged,
        validator: !required
            ? null
            : (value) => _text(value).isEmpty ? 'Campo obligatorio' : null,
      ),
    );
  }

  Widget _dateField(TextEditingController controller, String label) {
    return SizedBox(
      width: 210,
      child: TextFormField(
        controller: controller,
        readOnly: true,
        onTap: _editable ? () => _pickDate(controller) : null,
        decoration: _decoration(label)
            .copyWith(prefixIcon: const Icon(Icons.calendar_month_outlined)),
      ),
    );
  }

  Widget _catalogDropdown({
    required String label,
    required String? value,
    required List<Map<String, dynamic>> rows,
    required String Function(Map<String, dynamic>) labelBuilder,
    required ValueChanged<String?> onChanged,
  }) {
    final values = rows.map((row) => _text(row['codigo'])).toSet();
    return SizedBox(
      width: 310,
      child: DropdownButtonFormField<String>(
        initialValue: value != null && values.contains(value) ? value : null,
        isExpanded: true,
        decoration: _decoration(label),
        items: rows
            .map((row) => DropdownMenuItem(
                  value: _text(row['codigo']),
                  child:
                      Text(labelBuilder(row), overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: _editable ? onChanged : null,
        validator: (selected) =>
            _text(selected).isEmpty ? 'Campo obligatorio' : null,
      ),
    );
  }

  Widget _moneySummary() {
    Widget line(String label, double value, {bool total = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontWeight:
                            total ? FontWeight.w800 : FontWeight.w500))),
            Text('$_currency ${value.toStringAsFixed(2)}',
                style: TextStyle(
                    fontWeight: total ? FontWeight.w800 : FontWeight.w600)),
          ]),
        );
    return Container(
      width: 320,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF607D8B)),
      ),
      child: Column(children: [
        line('Importe bruto', _totals.importeBruto),
        line('Descuento', _discountValue),
        line('Subtotal', _totals.subtotal),
        line('Impuesto (IGV)', _totals.impuesto),
        const Divider(),
        line('Total', _totals.total, total: true),
      ]),
    );
  }

  Widget _itemsTable() {
    if (_lines.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(border: Border.all(color: Colors.blueGrey)),
        child: const Center(
          child: Text('Use el botón + para agregar una solicitud aprobada.'),
        ),
      );
    }
    Widget input(TextEditingController controller,
        {double width = 120, bool numeric = false}) {
      return SizedBox(
        width: width,
        child: TextFormField(
          controller: controller,
          readOnly: !_editable,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.zero),
          ),
          onChanged: (_) => setState(() {}),
        ),
      );
    }

    Widget warehouseInput(_PurchaseOrderLine line) {
      final values = _warehouses.map((row) => _text(row['codigo'])).toSet();
      return SizedBox(
        width: 210,
        child: DropdownButtonFormField<String>(
          initialValue: values.contains(line.warehouse) ? line.warehouse : null,
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.zero),
          ),
          items: _warehouses
              .map((row) => DropdownMenuItem(
                    value: _text(row['codigo']),
                    child: Text('${row['codigo']} · ${row['nombre']}',
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: !_editable
              ? null
              : (value) => setState(() => line.warehouse = value),
          validator: (value) =>
              _text(value).isEmpty ? 'Seleccione almacén' : null,
        ),
      );
    }

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFF42576B)),
          headingTextStyle:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          columns: const [
            DataColumn(label: Text('Solicitud')),
            DataColumn(label: Text('Fecha solicitada')),
            DataColumn(label: Text('Código')),
            DataColumn(label: Text('Descripción')),
            DataColumn(label: Text('Unidad')),
            DataColumn(label: Text('Almacén')),
            DataColumn(label: Text('Cant. solicitada')),
            DataColumn(label: Text('Cant. OC')),
            DataColumn(label: Text('Cant. recibida')),
            DataColumn(label: Text('Fecha OC aprobada')),
            DataColumn(label: Text('Fecha recibida')),
            DataColumn(label: Text('Precio')),
            DataColumn(label: Text('% Dcto.')),
            DataColumn(label: Text('Importe')),
          ],
          rows: _lines
              .map((line) => DataRow(cells: [
                    DataCell(Text(line.requestNumber)),
                    DataCell(Text(line.requestedDate.isEmpty
                        ? 'Pendiente'
                        : line.requestedDate)),
                    DataCell(input(line.articleCode, width: 130)),
                    DataCell(input(line.description, width: 260)),
                    DataCell(input(line.unit, width: 90)),
                    DataCell(warehouseInput(line)),
                    DataCell(Text(line.requestedQuantity.toStringAsFixed(2))),
                    DataCell(input(line.quantity, numeric: true)),
                    DataCell(Text(line.receivedQuantity.toStringAsFixed(2))),
                    DataCell(Text(line.approvedDate.isEmpty
                        ? 'Pendiente'
                        : line.approvedDate)),
                    DataCell(Text(line.receivedDate.isEmpty
                        ? 'Pendiente'
                        : line.receivedDate)),
                    DataCell(input(line.price, numeric: true)),
                    DataCell(
                        input(line.discountPercent, width: 90, numeric: true)),
                    DataCell(Text(line.amount.toStringAsFixed(2))),
                  ]))
              .toList(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _issueDate,
      _deliveryDate,
      _exchangeRate,
      _paymentTerms,
      _observation,
      _discount,
    ]) {
      controller.dispose();
    }
    for (final line in _lines) {
      line.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_code.isEmpty ? 'Nueva Orden de Compra' : _code),
        actions: [
          if (_code.isNotEmpty &&
              ErpDocumentPdf.canOpenOrGenerate(
                  'ERP_ORDENES_COMPRA_APPGT', _initial))
            IconButton(
              tooltip: _text(_initial['pdf_url']).isEmpty
                  ? 'Generar PDF'
                  : 'Ver PDF generado',
              onPressed: _saving ? null : _pdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          if (_editable)
            IconButton(
              tooltip: 'Agregar otra solicitud de pedido',
              onPressed: _saving ? null : _addRequest,
              icon: const Icon(Icons.add),
            ),
          if (_editable)
            IconButton(
              tooltip: 'Guardar',
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: ListView(
                  controller: _scrollController,
                  primary: false,
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_code.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(label: Text('Estado: $_state')),
                      ),
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      SizedBox(
                        width: 210,
                        child: TextFormField(
                          initialValue: _code.isEmpty
                              ? 'Automático al guardar (OC-10001...)'
                              : _code,
                          readOnly: true,
                          decoration: _decoration('Código'),
                        ),
                      ),
                      _catalogDropdown(
                        label: 'Proveedor',
                        value: _provider,
                        rows: _providers,
                        labelBuilder: (row) =>
                            '${row['ruc'] ?? ''} · ${row['razon_social']}',
                        onChanged: (value) => setState(() => _provider = value),
                      ),
                      _dateField(_issueDate, 'Fecha de emisión'),
                      _dateField(_deliveryDate, 'Fecha de entrega'),
                      SizedBox(
                        width: 140,
                        child: DropdownButtonFormField<String>(
                          initialValue: _currency,
                          decoration: _decoration('Moneda'),
                          items: const [
                            DropdownMenuItem(value: 'PEN', child: Text('PEN')),
                            DropdownMenuItem(value: 'USD', child: Text('USD')),
                            DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                          ],
                          onChanged: !_editable
                              ? null
                              : (value) =>
                                  setState(() => _currency = value ?? 'PEN'),
                        ),
                      ),
                      _field(_exchangeRate, 'Tipo de cambio',
                          width: 160,
                          required: true,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true)),
                      const SizedBox(
                        width: 250,
                        child: Text(
                          'Tipo de cambio: valor en soles (PEN) de 1 unidad de la moneda seleccionada. Para PEN use 1.',
                          style:
                              TextStyle(fontSize: 12, color: Colors.blueGrey),
                        ),
                      ),
                      _field(_paymentTerms, 'Condición de pago'),
                      _catalogDropdown(
                        label: 'Almacén',
                        value: _warehouse,
                        rows: _warehouses,
                        labelBuilder: (row) =>
                            '${row['codigo']} · ${row['nombre']}',
                        onChanged: (value) =>
                            setState(() => _warehouse = value),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _observation,
                      readOnly: !_editable,
                      maxLines: 2,
                      decoration: _decoration('Observaciones'),
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Checkbox(
                        value: _includesIgv,
                        onChanged: !_editable
                            ? null
                            : (value) =>
                                setState(() => _includesIgv = value ?? false),
                      ),
                      const Text('Con IGV'),
                      const SizedBox(width: 18),
                      _field(
                        _discount,
                        'Descuento',
                        width: 180,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ]),
                    if (_requestNumbers.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _requestNumbers
                            .map((number) => InputChip(
                                  label: Text(number),
                                  onDeleted: _editable
                                      ? () => _removeRequest(number)
                                      : null,
                                ))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text('Ítems de la orden de compra',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _itemsTable(),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _moneySummary(),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }
}
