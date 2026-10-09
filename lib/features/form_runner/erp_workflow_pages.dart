import 'package:flutter/material.dart' hide ScaffoldMessenger;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/zumac_scaffold_messenger.dart';
import 'erp_document_pdf.dart';

List<Map<String, dynamic>> _erpRows(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

Map<String, dynamic> _erpMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

String _erpText(dynamic value) => value?.toString().trim() ?? '';

String _erpError(Object error) {
  if (error is PostgrestException) return error.message;
  return error.toString().replaceFirst('Exception: ', '');
}

String _today() => DateTime.now().toIso8601String().substring(0, 10);

String _dateOnly(dynamic value, {String fallback = ''}) {
  final text = _erpText(value);
  if (text.isEmpty) return fallback;
  return text.length <= 10 ? text : text.substring(0, 10);
}

Future<void> _pickDate(
  BuildContext context,
  TextEditingController controller,
) async {
  final now = DateTime.now();
  final current = DateTime.tryParse(controller.text) ?? now;
  final picked = await showDatePicker(
    context: context,
    initialDate: current,
    firstDate: DateTime(2020),
    lastDate: DateTime(now.year + 10),
  );
  if (picked != null) {
    controller.text = picked.toIso8601String().substring(0, 10);
  }
}

InputDecoration _erpDecoration(String label, {IconData? icon}) =>
    InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon),
      border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
      isDense: true,
    );

void _erpToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade800 : Colors.green.shade800,
    ),
  );
}

Future<void> _erpOpenPdf(
  BuildContext context,
  SupabaseClient client,
  String table,
  Map<String, dynamic> row,
) async {
  try {
    await ErpDocumentPdf.openOrGenerate(
      context: context,
      client: client,
      table: table,
      row: row,
    );
  } catch (error) {
    if (context.mounted) {
      _erpToast(context, _erpError(error), error: true);
    }
  }
}

class _ArticleSearch extends SearchDelegate<Map<String, dynamic>?> {
  final List<Map<String, dynamic>> articles;

  _ArticleSearch(this.articles);

  @override
  String get searchFieldLabel => 'Código o descripción';

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
              onPressed: () => query = '', icon: const Icon(Icons.clear)),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        onPressed: () => close(context, null),
        icon: const Icon(Icons.arrow_back),
      );

  Widget _results() {
    final needle = query.trim().toUpperCase();
    final rows = articles.where((row) {
      if (needle.isEmpty) return true;
      return '${row['codigo']} ${row['nombre']}'.toUpperCase().contains(needle);
    }).toList();
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return ListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text(_erpText(row['nombre'])),
          subtitle: Text(
            '${_erpText(row['codigo'])} · ${_erpText(row['unidad_medida'])}',
          ),
          onTap: () => close(context, row),
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) => _results();

  @override
  Widget buildSuggestions(BuildContext context) => _results();
}

class _EditableArticleLine {
  final Map<String, dynamic> article;
  final TextEditingController quantity;
  final TextEditingController lot;
  final TextEditingController observation;
  String? warehouse;
  String? provider;

  _EditableArticleLine({
    required this.article,
    required String quantity,
    String lot = '',
    String observation = '',
    this.warehouse,
    this.provider,
  })  : quantity = TextEditingController(text: quantity),
        lot = TextEditingController(text: lot),
        observation = TextEditingController(text: observation);

  void dispose() {
    quantity.dispose();
    lot.dispose();
    observation.dispose();
  }
}

class ErpPurchaseRequestPage extends StatefulWidget {
  final Map<String, dynamic>? initialPayload;
  final VoidCallback? onSavedAndExit;

  const ErpPurchaseRequestPage({
    super.key,
    this.initialPayload,
    this.onSavedAndExit,
  });

  @override
  State<ErpPurchaseRequestPage> createState() => _ErpPurchaseRequestPageState();
}

class _ErpPurchaseRequestPageState extends State<ErpPurchaseRequestPage> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _date;
  late final TextEditingController _needDate;
  late final TextEditingController _requester;
  late final TextEditingController _area;
  late final TextEditingController _costCenter;
  late final TextEditingController _justification;
  final List<_EditableArticleLine> _lines = [];
  List<Map<String, dynamic>> _articles = [];
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _providers = [];
  bool _loading = true;
  bool _saving = false;

  Map<String, dynamic> get _initial => widget.initialPayload ?? const {};
  String get _number => _erpText(_initial['numero'] ?? _initial['NUMERO']);
  String get _state =>
      _erpText(_initial['estado'] ?? _initial['ESTADO']).toUpperCase();
  bool get _editable =>
      _number.isEmpty || _state == 'PENDIENTE' || _state == 'REVISADO';

  @override
  void initState() {
    super.initState();
    _date = TextEditingController(
      text:
          _dateOnly(_initial['fecha'] ?? _initial['FECHA'], fallback: _today()),
    );
    _needDate = TextEditingController(
      text: _dateOnly(
        _initial['fecha_necesidad'] ?? _initial['FECHA_NECESIDAD'],
        fallback: _today(),
      ),
    );
    _requester = TextEditingController(
      text: _erpText(_initial['solicitante'] ?? _initial['SOLICITANTE']),
    );
    _area = TextEditingController(
      text: _erpText(_initial['area'] ?? _initial['AREA']),
    );
    _costCenter = TextEditingController(
      text: _erpText(_initial['centro_costo'] ?? _initial['CENTRO_COSTO']),
    );
    _justification = TextEditingController(
      text: _erpText(_initial['justificacion'] ?? _initial['JUSTIFICACION']),
    );
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _client
            .from('ERP_ARTICULOS_APPGT')
            .select('codigo,nombre,unidad_medida,almacen_predeterminado_codigo')
            .eq('estado', 'ACTIVO')
            .order('nombre'),
        _client
            .from('ERP_ALMACENES_APPGT')
            .select('codigo,nombre')
            .eq('estado', 'ACTIVO')
            .order('nombre'),
        _client
            .from('ERP_PROVEEDORES_APPGT')
            .select('codigo,razon_social,numero_documento')
            .eq('estado', 'ACTIVO')
            .order('razon_social'),
      ]);
      _articles = _erpRows(results[0]);
      _warehouses = _erpRows(results[1]);
      _providers = _erpRows(results[2]);
      if (_number.isNotEmpty) {
        final raw = await _client
            .from('ERP_SOLICITUDES_COMPRA_DETALLE_APPGT')
            .select()
            .eq('solicitud_numero', _number)
            .order('linea');
        for (final row in _erpRows(raw)) {
          final article = _articles.firstWhere(
            (item) => item['codigo'] == row['articulo_codigo'],
            orElse: () => {
              'codigo': row['articulo_codigo'],
              'nombre': row['descripcion'],
              'unidad_medida': row['unidad_medida'],
            },
          );
          _lines.add(_EditableArticleLine(
            article: article,
            quantity: _erpText(row['cantidad_solicitada']),
            observation: _erpText(row['observacion']),
            warehouse: _erpText(row['almacen_destino_codigo']),
            provider: _erpText(row['proveedor_recomendado_codigo']),
          ));
        }
      }
    } catch (error) {
      if (mounted) _erpToast(context, _erpError(error), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addArticle() async {
    final article = await showSearch<Map<String, dynamic>?>(
      context: context,
      delegate: _ArticleSearch(_articles),
    );
    if (article == null || !mounted) return;
    setState(() {
      _lines.add(_EditableArticleLine(
        article: article,
        quantity: '1',
        warehouse: _erpText(article['almacen_predeterminado_codigo']).isEmpty
            ? (_warehouses.isEmpty
                ? null
                : _erpText(_warehouses.first['codigo']))
            : _erpText(article['almacen_predeterminado_codigo']),
      ));
    });
  }

  Future<void> _save() async {
    if (!_editable || !_formKey.currentState!.validate()) return;
    if (_lines.isEmpty) {
      _erpToast(context, 'Agregue al menos un artículo o insumo.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final details = _lines
          .map((line) => {
                'articulo_codigo': line.article['codigo'],
                'cantidad_solicitada':
                    double.tryParse(line.quantity.text.replaceAll(',', '.')),
                'fecha_necesidad': _needDate.text,
                'proveedor_recomendado_codigo': line.provider,
                'almacen_destino_codigo': line.warehouse,
                'observacion': line.observation.text.trim(),
              })
          .toList();
      final result = await _client.rpc(
        'erp_guardar_solicitud_pedido_v1',
        params: {
          'p_numero': _number.isEmpty ? null : _number,
          'p_fecha': _date.text,
          'p_fecha_necesidad': _needDate.text,
          'p_solicitante': _requester.text.trim(),
          'p_area': _area.text.trim(),
          'p_centro_costo': _costCenter.text.trim(),
          'p_justificacion': _justification.text.trim(),
          'p_detalles': details,
        },
      );
      if (!mounted) return;
      final saved = _erpMap(result);
      _erpToast(context, 'Solicitud ${saved['numero'] ?? _number} guardada.');
      widget.onSavedAndExit?.call();
    } catch (error) {
      if (mounted) _erpToast(context, _erpError(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _date,
      _needDate,
      _requester,
      _area,
      _costCenter,
      _justification,
    ]) {
      controller.dispose();
    }
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_number.isEmpty ? 'Nueva Solicitud de Pedido' : _number),
        actions: [
          if (_number.isNotEmpty &&
              ErpDocumentPdf.canOpenOrGenerate(
                  'ERP_SOLICITUDES_COMPRA_APPGT', _initial))
            IconButton(
              tooltip: _erpText(_initial['pdf_url']).isEmpty
                  ? 'Generar PDF'
                  : 'Ver PDF generado',
              onPressed: _saving
                  ? null
                  : () => _erpOpenPdf(
                        context,
                        _client,
                        'ERP_SOLICITUDES_COMPRA_APPGT',
                        _initial,
                      ),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          if (_editable)
            IconButton(
              tooltip: 'Guardar',
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
            ),
        ],
      ),
      floatingActionButton: _editable
          ? FloatingActionButton.extended(
              onPressed: _addArticle,
              icon: const Icon(Icons.add),
              label: const Text('Artículo'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_number.isNotEmpty)
                    Chip(
                        label: Text(
                            'Estado: ${_state.isEmpty ? 'PENDIENTE' : _state}')),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _dateInput(context, _date, 'Fecha', _editable),
                      _dateInput(context, _needDate, 'Fecha en que se necesita',
                          _editable),
                      _textInput(_requester, 'Solicitante', _editable,
                          isRequired: true),
                      _textInput(_area, 'Área solicitante', _editable),
                      _textInput(_costCenter, 'Centro de costo', _editable),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _justification,
                    readOnly: !_editable,
                    maxLines: 2,
                    decoration: _erpDecoration('Justificación'),
                  ),
                  const SizedBox(height: 18),
                  Text('Artículos e insumos (${_lines.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_lines.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Aún no se agregaron artículos.'),
                      ),
                    ),
                  ..._lines.asMap().entries.map((entry) {
                    final index = entry.key;
                    final line = entry.value;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(
                                  '${line.article['codigo']} · ${line.article['nombre']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (_editable)
                                IconButton(
                                  tooltip: 'Quitar artículo',
                                  onPressed: () => setState(() {
                                    _lines.removeAt(index).dispose();
                                  }),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                            ]),
                            Text('Unidad: ${line.article['unidad_medida']}'),
                            const SizedBox(height: 10),
                            Wrap(spacing: 12, runSpacing: 12, children: [
                              SizedBox(
                                width: 180,
                                child: TextFormField(
                                  controller: line.quantity,
                                  readOnly: !_editable,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: _erpDecoration('Cantidad'),
                                  validator: (value) => (double.tryParse(
                                                  (value ?? '')
                                                      .replaceAll(',', '.')) ??
                                              0) <=
                                          0
                                      ? 'Cantidad inválida'
                                      : null,
                                ),
                              ),
                              _dropdown(
                                value: line.warehouse,
                                label: 'Almacén de destino',
                                rows: _warehouses,
                                valueKey: 'codigo',
                                labelBuilder: (row) =>
                                    '${row['codigo']} · ${row['nombre']}',
                                enabled: _editable,
                                isRequired: true,
                                onChanged: (value) =>
                                    setState(() => line.warehouse = value),
                              ),
                              _dropdown(
                                value: line.provider,
                                label: 'Proveedor recomendado',
                                rows: _providers,
                                valueKey: 'codigo',
                                labelBuilder: (row) =>
                                    '${row['razon_social']} · ${row['numero_documento']}',
                                enabled: _editable,
                                onChanged: (value) =>
                                    setState(() => line.provider = value),
                              ),
                            ]),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: line.observation,
                              readOnly: !_editable,
                              decoration:
                                  _erpDecoration('Observación de línea'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 90),
                ],
              ),
            ),
    );
  }
}

Widget _textInput(
  TextEditingController controller,
  String label,
  bool enabled, {
  bool isRequired = false,
}) =>
    SizedBox(
      width: 260,
      child: TextFormField(
        controller: controller,
        readOnly: !enabled,
        decoration: _erpDecoration(label),
        validator: !isRequired
            ? null
            : (value) => _erpText(value).isEmpty ? 'Campo obligatorio' : null,
      ),
    );

Widget _dateInput(
  BuildContext context,
  TextEditingController controller,
  String label,
  bool enabled,
) =>
    SizedBox(
      width: 240,
      child: TextFormField(
        controller: controller,
        readOnly: true,
        onTap: enabled ? () => _pickDate(context, controller) : null,
        decoration: _erpDecoration(label, icon: Icons.calendar_month_outlined),
      ),
    );

Widget _dropdown({
  required String? value,
  required String label,
  required List<Map<String, dynamic>> rows,
  required String valueKey,
  required String Function(Map<String, dynamic>) labelBuilder,
  required bool enabled,
  required ValueChanged<String?> onChanged,
  bool isRequired = false,
}) {
  final values = rows.map((row) => _erpText(row[valueKey])).toSet();
  final safeValue = value != null && values.contains(value) ? value : null;
  return SizedBox(
    width: 300,
    child: DropdownButtonFormField<String>(
      initialValue: safeValue,
      isExpanded: true,
      decoration: _erpDecoration(label),
      items: rows
          .map((row) => DropdownMenuItem(
                value: _erpText(row[valueKey]),
                child: Text(labelBuilder(row), overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: enabled ? onChanged : null,
      validator: !isRequired
          ? null
          : (selected) =>
              _erpText(selected).isEmpty ? 'Campo obligatorio' : null,
    ),
  );
}

class _ReceiptLine {
  final Map<String, dynamic> data;
  final TextEditingController quantity;
  final TextEditingController lot;
  final TextEditingController expiry;
  bool included;

  _ReceiptLine(this.data, {String? received})
      : quantity = TextEditingController(
          text: received ?? _erpText(data['cantidad_pendiente']),
        ),
        lot = TextEditingController(text: _erpText(data['lote'])),
        expiry =
            TextEditingController(text: _erpText(data['fecha_vencimiento'])),
        included = true;

  void dispose() {
    quantity.dispose();
    lot.dispose();
    expiry.dispose();
  }
}

class ErpPurchaseReceiptPage extends StatefulWidget {
  final Map<String, dynamic>? initialPayload;
  final VoidCallback? onSavedAndExit;

  const ErpPurchaseReceiptPage({
    super.key,
    this.initialPayload,
    this.onSavedAndExit,
  });

  @override
  State<ErpPurchaseReceiptPage> createState() => _ErpPurchaseReceiptPageState();
}

class _ErpPurchaseReceiptPageState extends State<ErpPurchaseReceiptPage> {
  final _client = Supabase.instance.client;
  final _date = TextEditingController(text: _today());
  final _guide = TextEditingController();
  final _observation = TextEditingController();
  final List<_ReceiptLine> _lines = [];
  List<Map<String, dynamic>> _orders = [];
  Map<String, dynamic>? _selected;
  bool _loading = true;
  bool _saving = false;

  Map<String, dynamic> get _initial => widget.initialPayload ?? const {};
  String get _receiptNumber =>
      _erpText(_initial['numero'] ?? _initial['NUMERO']);
  bool get _readOnly => _receiptNumber.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_readOnly) {
      _date.text = _dateOnly(
        _initial['fecha_ingreso'] ?? _initial['FECHA_INGRESO'],
        fallback: _today(),
      );
      _guide.text =
          _erpText(_initial['guia_remision'] ?? _initial['GUIA_REMISION']);
      _observation.text =
          _erpText(_initial['observacion'] ?? _initial['OBSERVACION']);
    }
    _load();
  }

  Future<void> _load() async {
    try {
      if (_readOnly) {
        final raw = await _client
            .from('ERP_INGRESOS_ALMACEN_DETALLE_APPGT')
            .select()
            .eq('ingreso_numero', _receiptNumber)
            .order('linea');
        final details = _erpRows(raw);
        _selected = {
          'numero': _initial['orden_numero'] ?? _initial['ORDEN_NUMERO'],
          'proveedor':
              _initial['proveedor_codigo'] ?? _initial['PROVEEDOR_CODIGO'],
          'proveedor_ruc':
              _initial['proveedor_ruc'] ?? _initial['PROVEEDOR_RUC'],
          'almacen_codigo':
              _initial['almacen_codigo'] ?? _initial['ALMACEN_CODIGO'],
        };
        for (final row in details) {
          row['linea'] = row['orden_linea'];
          row['cantidad_oc'] = row['cantidad_ordenada'];
          row['cantidad_pendiente'] = row['cantidad_pendiente_antes'];
          _lines.add(
              _ReceiptLine(row, received: _erpText(row['cantidad_recibida'])));
        }
      } else {
        _orders = _erpRows(
          await _client.rpc('erp_ordenes_pendientes_ingreso_v1'),
        );
      }
    } catch (error) {
      if (mounted) _erpToast(context, _erpError(error), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectOrder(String? number) {
    for (final line in _lines) {
      line.dispose();
    }
    _lines.clear();
    _selected = number == null
        ? null
        : _orders.firstWhere((row) => _erpText(row['numero']) == number);
    for (final detail in _erpRows(_selected?['detalles'])) {
      _lines.add(_ReceiptLine(detail));
    }
    setState(() {});
  }

  Future<void> _save() async {
    if (_selected == null) {
      _erpToast(context, 'Seleccione una orden de compra.', error: true);
      return;
    }
    if (_guide.text.trim().isEmpty) {
      _erpToast(context, 'Ingrese la guía de remisión.', error: true);
      return;
    }
    final details = _lines
        .where((line) => line.included)
        .map((line) => {
              'linea': line.data['linea'],
              'cantidad_recibida':
                  double.tryParse(line.quantity.text.replaceAll(',', '.')) ?? 0,
              'lote': line.lot.text.trim(),
              'fecha_vencimiento': line.expiry.text.trim(),
            })
        .where((row) => (row['cantidad_recibida'] as double) > 0)
        .toList();
    if (details.isEmpty) {
      _erpToast(context, 'Confirme al menos una cantidad recibida.',
          error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final result = _erpMap(await _client.rpc(
        'erp_registrar_ingreso_compra_v1',
        params: {
          'p_orden_numero': _selected!['numero'],
          'p_fecha': _date.text,
          'p_guia_remision': _guide.text.trim(),
          'p_detalles': details,
          'p_observacion': _observation.text.trim(),
        },
      ));
      if (!mounted) return;
      _erpToast(
        context,
        'Ingreso ${result['ingreso_numero'] ?? ''} confirmado. '
        'OC: ${result['estado_orden'] ?? ''}.',
      );
      widget.onSavedAndExit?.call();
    } catch (error) {
      if (mounted) _erpToast(context, _erpError(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _annul() async {
    setState(() => _saving = true);
    try {
      await _client.rpc('erp_anular_ingreso_compra_v1',
          params: {'p_ingreso_numero': _receiptNumber});
      if (!mounted) return;
      _erpToast(context, 'Ingreso anulado y stock revertido.');
      widget.onSavedAndExit?.call();
    } catch (error) {
      if (mounted) _erpToast(context, _erpError(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _date.dispose();
    _guide.dispose();
    _observation.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state =
        _erpText(_initial['estado'] ?? _initial['ESTADO']).toUpperCase();
    return Scaffold(
      appBar: AppBar(
        title: Text(_readOnly
            ? 'Ingreso $_receiptNumber'
            : 'Ingreso por orden de compra'),
        actions: [
          if (_readOnly &&
              ErpDocumentPdf.canOpenOrGenerate(
                  'ERP_INGRESOS_ALMACEN_APPGT', _initial))
            IconButton(
              tooltip: _erpText(_initial['pdf_url']).isEmpty
                  ? 'Generar PDF'
                  : 'Ver PDF generado',
              onPressed: _saving
                  ? null
                  : () => _erpOpenPdf(
                        context,
                        _client,
                        'ERP_INGRESOS_ALMACEN_APPGT',
                        _initial,
                      ),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          if (!_readOnly)
            IconButton(
              tooltip: 'Confirmar ingreso',
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
            ),
          if (_readOnly && state == 'CONFIRMADO')
            IconButton(
              tooltip: 'Anular y revertir stock',
              onPressed: _saving ? null : _annul,
              icon: const Icon(Icons.undo),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!_readOnly)
                  DropdownButtonFormField<String>(
                    initialValue: _erpText(_selected?['numero']).isEmpty
                        ? null
                        : _erpText(_selected?['numero']),
                    isExpanded: true,
                    decoration:
                        _erpDecoration('Número de orden - RUC de proveedor'),
                    items: _orders
                        .map((row) => DropdownMenuItem(
                              value: _erpText(row['numero']),
                              child: Text(_erpText(row['referencia'])),
                            ))
                        .toList(),
                    onChanged: _selectOrder,
                  ),
                if (_readOnly) Chip(label: Text('Estado: $state')),
                const SizedBox(height: 12),
                if (_selected != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(spacing: 24, runSpacing: 8, children: [
                        Text(
                            'Proveedor: ${_selected!['proveedor'] ?? _selected!['proveedor_codigo']}'),
                        Text('RUC: ${_selected!['proveedor_ruc'] ?? ''}'),
                        Text('Almacén: ${_selected!['almacen_codigo'] ?? ''}'),
                      ]),
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  _dateInput(context, _date, 'Fecha de ingreso', !_readOnly),
                  _textInput(_guide, 'Guía de remisión', !_readOnly,
                      isRequired: true),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _observation,
                  readOnly: _readOnly,
                  decoration: _erpDecoration('Observación'),
                ),
                const SizedBox(height: 18),
                Text(
                    'Detalle recibido (${_lines.where((line) => line.included).length})',
                    style: Theme.of(context).textTheme.titleMedium),
                ..._lines.asMap().entries.map((entry) {
                  final line = entry.value;
                  return Card(
                    color: line.included ? null : Colors.grey.shade200,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(
                                '${line.data['articulo_codigo']} · ${line.data['descripcion']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (!_readOnly)
                              Switch(
                                value: line.included,
                                onChanged: (value) =>
                                    setState(() => line.included = value),
                              ),
                          ]),
                          Text(
                            'Unidad: ${line.data['unidad_medida']} · '
                            'Solicitada: ${line.data['cantidad_solicitada'] ?? '-'} · '
                            'OC: ${line.data['cantidad_oc']} · '
                            'Ya despachada: ${line.data['cantidad_despachada'] ?? 0}',
                          ),
                          const SizedBox(height: 10),
                          Wrap(spacing: 12, runSpacing: 12, children: [
                            _textInput(line.quantity, 'Cantidad recibida',
                                !_readOnly && line.included),
                            _textInput(
                                line.lot, 'Lote', !_readOnly && line.included),
                            SizedBox(
                              width: 240,
                              child: TextFormField(
                                controller: line.expiry,
                                readOnly: true,
                                onTap: !_readOnly && line.included
                                    ? () => _pickDate(context, line.expiry)
                                    : null,
                                decoration:
                                    _erpDecoration('Fecha de vencimiento'),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 36),
              ],
            ),
    );
  }
}

class ErpDispatchVoucherPage extends StatefulWidget {
  final Map<String, dynamic>? initialPayload;
  final VoidCallback? onSavedAndExit;

  const ErpDispatchVoucherPage({
    super.key,
    this.initialPayload,
    this.onSavedAndExit,
  });

  @override
  State<ErpDispatchVoucherPage> createState() => _ErpDispatchVoucherPageState();
}

class _ErpDispatchVoucherPageState extends State<ErpDispatchVoucherPage> {
  final _client = Supabase.instance.client;
  final _date = TextEditingController(text: _today());
  final _dni = TextEditingController();
  final _name = TextEditingController();
  final _observation = TextEditingController();
  final List<_EditableArticleLine> _lines = [];
  List<Map<String, dynamic>> _articles = [];
  List<Map<String, dynamic>> _warehouses = [];
  List<String> _lots = [];
  List<String> _areas = [];
  String _type = 'DIRECTO';
  String? _costCenter;
  String? _warehouse;
  bool _loading = true;
  bool _saving = false;

  Map<String, dynamic> get _initial => widget.initialPayload ?? const {};
  String get _number => _erpText(_initial['numero'] ?? _initial['NUMERO']);
  String get _state =>
      _erpText(_initial['estado'] ?? _initial['ESTADO']).toUpperCase();
  bool get _editable =>
      _number.isEmpty || _state == 'PENDIENTE' || _state == 'REVISADO';
  List<String> get _centers =>
      _type == 'DIRECTO' ? _lots : <String>['INVERSION', ..._areas];

  @override
  void initState() {
    super.initState();
    if (_number.isNotEmpty) {
      final rawDate = _erpText(_initial['fecha'] ?? _initial['FECHA']);
      if (rawDate.isNotEmpty) _date.text = _dateOnly(rawDate);
      _dni.text = _erpText(_initial['usuario_dni'] ?? _initial['USUARIO_DNI']);
      _name.text =
          _erpText(_initial['usuario_nombre'] ?? _initial['USUARIO_NOMBRE']);
      _observation.text =
          _erpText(_initial['observacion'] ?? _initial['OBSERVACION']);
      _type = _erpText(_initial['tipo_destino'] ?? _initial['TIPO_DESTINO'])
          .toUpperCase();
      _costCenter =
          _erpText(_initial['centro_costo'] ?? _initial['CENTRO_COSTO']);
      _warehouse =
          _erpText(_initial['almacen_codigo'] ?? _initial['ALMACEN_CODIGO']);
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final catalog =
          _erpMap(await _client.rpc('erp_catalogos_vale_despacho_v1'));
      _articles = _erpRows(catalog['articulos']);
      _warehouses = _erpRows(catalog['almacenes']);
      _lots = (catalog['lotes'] as List? ?? const [])
          .map(_erpText)
          .where((value) => value.isNotEmpty)
          .toList();
      _areas = (catalog['areas'] as List? ?? const [])
          .map(_erpText)
          .where((value) => value.isNotEmpty)
          .toList();
      _warehouse ??=
          _warehouses.isEmpty ? null : _erpText(_warehouses.first['codigo']);
      if (_number.isNotEmpty) {
        final raw = await _client
            .from('ERP_VALES_DESPACHO_DETALLE_APPGT')
            .select()
            .eq('vale_numero', _number)
            .order('linea');
        for (final row in _erpRows(raw)) {
          final article = _articles.firstWhere(
            (item) => item['codigo'] == row['articulo_codigo'],
            orElse: () => {
              'codigo': row['articulo_codigo'],
              'nombre': row['descripcion'],
              'unidad_medida': row['unidad_medida'],
            },
          );
          _lines.add(_EditableArticleLine(
            article: article,
            quantity: _erpText(row['cantidad_solicitada']),
            lot: _erpText(row['lote']),
            observation: _erpText(row['observacion']),
          ));
        }
      }
    } catch (error) {
      if (mounted) _erpToast(context, _erpError(error), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addArticle() async {
    final article = await showSearch<Map<String, dynamic>?>(
      context: context,
      delegate: _ArticleSearch(_articles),
    );
    if (article == null || !mounted) return;
    setState(() => _lines.add(
          _EditableArticleLine(article: article, quantity: '1'),
        ));
  }

  Future<void> _save() async {
    if (_dni.text.trim().isEmpty || _costCenter == null || _warehouse == null) {
      _erpToast(context, 'Complete DNI, centro de costo y almacén.',
          error: true);
      return;
    }
    if (_lines.isEmpty) {
      _erpToast(context, 'Agregue al menos un artículo o insumo.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final result = _erpMap(await _client.rpc(
        'erp_guardar_vale_despacho_v1',
        params: {
          'p_numero': _number.isEmpty ? null : _number,
          'p_fecha': _date.text,
          'p_usuario_dni': _dni.text.trim(),
          'p_usuario_nombre': _name.text.trim(),
          'p_tipo_destino': _type,
          'p_centro_costo': _costCenter,
          'p_almacen_codigo': _warehouse,
          'p_detalles': _lines
              .map((line) => {
                    'articulo_codigo': line.article['codigo'],
                    'cantidad_solicitada': double.tryParse(
                            line.quantity.text.replaceAll(',', '.')) ??
                        0,
                    'lote': line.lot.text.trim(),
                    'observacion': line.observation.text.trim(),
                  })
              .toList(),
          'p_observacion': _observation.text.trim(),
        },
      ));
      if (!mounted) return;
      _erpToast(context, 'Vale ${result['vale_numero'] ?? _number} guardado.');
      widget.onSavedAndExit?.call();
    } catch (error) {
      if (mounted) _erpToast(context, _erpError(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _date.dispose();
    _dni.dispose();
    _name.dispose();
    _observation.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final centers = _centers;
    final safeCenter = centers.contains(_costCenter) ? _costCenter : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_number.isEmpty ? 'Nuevo Vale de Despacho' : _number),
        actions: [
          if (_number.isNotEmpty &&
              ErpDocumentPdf.canOpenOrGenerate(
                  'ERP_VALES_DESPACHO_APPGT', _initial))
            IconButton(
              tooltip: _erpText(_initial['pdf_url']).isEmpty
                  ? 'Generar PDF'
                  : 'Ver PDF generado',
              onPressed: _saving
                  ? null
                  : () => _erpOpenPdf(
                        context,
                        _client,
                        'ERP_VALES_DESPACHO_APPGT',
                        _initial,
                      ),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          if (_editable)
            IconButton(
              tooltip: 'Guardar',
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
            ),
        ],
      ),
      floatingActionButton: _editable
          ? FloatingActionButton.extended(
              onPressed: _addArticle,
              icon: const Icon(Icons.add),
              label: const Text('Artículo'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_number.isNotEmpty) Chip(label: Text('Estado: $_state')),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  _dateInput(context, _date, 'Fecha', _editable),
                  _textInput(_dni, 'Usuario (DNI)', _editable,
                      isRequired: true),
                  _textInput(_name, 'Nombre del usuario', _editable),
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: _erpDecoration('Destino'),
                      items: const [
                        DropdownMenuItem(
                            value: 'DIRECTO', child: Text('DIRECTO')),
                        DropdownMenuItem(
                            value: 'INDIRECTO', child: Text('INDIRECTO')),
                      ],
                      onChanged: !_editable
                          ? null
                          : (value) => setState(() {
                                _type = value ?? 'DIRECTO';
                                _costCenter = null;
                              }),
                    ),
                  ),
                  SizedBox(
                    width: 300,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_type),
                      initialValue: safeCenter,
                      isExpanded: true,
                      decoration: _erpDecoration(_type == 'DIRECTO'
                          ? 'Centro de costo (lote)'
                          : 'Centro de costo (área / inversión)'),
                      items: centers
                          .map((value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ))
                          .toList(),
                      onChanged: !_editable
                          ? null
                          : (value) => setState(() => _costCenter = value),
                    ),
                  ),
                  _dropdown(
                    value: _warehouse,
                    label: 'Almacén',
                    rows: _warehouses,
                    valueKey: 'codigo',
                    labelBuilder: (row) =>
                        '${row['codigo']} · ${row['nombre']}',
                    enabled: _editable,
                    isRequired: true,
                    onChanged: (value) => setState(() => _warehouse = value),
                  ),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _observation,
                  readOnly: !_editable,
                  decoration: _erpDecoration('Observación'),
                ),
                const SizedBox(height: 18),
                Text('Artículos e insumos (${_lines.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                ..._lines.asMap().entries.map((entry) {
                  final index = entry.key;
                  final line = entry.value;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(
                                '${line.article['codigo']} · ${line.article['nombre']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (_editable)
                              IconButton(
                                onPressed: () => setState(() {
                                  _lines.removeAt(index).dispose();
                                }),
                                icon: const Icon(Icons.delete_outline),
                              ),
                          ]),
                          Text('Unidad: ${line.article['unidad_medida']}'),
                          const SizedBox(height: 10),
                          Wrap(spacing: 12, runSpacing: 12, children: [
                            _textInput(
                                line.quantity, 'Cantidad solicitada', _editable,
                                isRequired: true),
                            _textInput(line.lot, 'Lote específico (opcional)',
                                _editable),
                          ]),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: line.observation,
                            readOnly: !_editable,
                            decoration: _erpDecoration('Observación de línea'),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 90),
              ],
            ),
    );
  }
}
