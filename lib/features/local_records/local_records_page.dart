import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/services/local_db.dart';
import '../form_runner/form_runner_page.dart';
import '../form_runner/special_form_pages.dart';

class LocalRecordsPage extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onChanged;

  const LocalRecordsPage({super.key, this.embedded = false, this.onChanged});

  @override
  State<LocalRecordsPage> createState() => _LocalRecordsPageState();
}

class _LocalRecordsPageState extends State<LocalRecordsPage> {
  final local = LocalDb.instance;
  List<Map<String, dynamic>> rows = [];
  String filtro = 'pendiente';
  final Set<String> _selectedLocalKeys = <String>{};
  final ScrollController _recordsVerticalCtrl = ScrollController();
  final ScrollController _recordsHorizontalCtrl = ScrollController();
  final ScrollController _dialogVerticalCtrl = ScrollController();
  Map<String, _MasterDetailMeta> _masterDetailByFormat = {};


  @override
  void initState() {
    super.initState();
    _load();
  }

  String _logicalKey(Map<String, dynamic> row) {
    try {
      final payload = jsonDecode(row['payload_json']?.toString() ?? '{}') as Map<String, dynamic>;
      final idRegistro = _payloadValue(payload, ['ID_REGISTRO', 'ID'])?.toString().trim() ?? '';
      if (idRegistro.isNotEmpty) {
        return '${row['estado']}|${row['formato_id']}|${row['tabla_destino']}|$idRegistro';
      }
    } catch (_) {}
    return '${row['id_local']}';
  }

  @override
  void dispose() {
    _recordsVerticalCtrl.dispose();
    _recordsHorizontalCtrl.dispose();
    _dialogVerticalCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await local.allRecords(estado: filtro);
    _masterDetailByFormat = await _loadMasterDetailMetas();

    final grouped = <String, Map<String, dynamic>>{};
    final siblingIds = <String, List<String>>{};
    final groupRows = <String, List<Map<String, dynamic>>>{};

    for (final row in data) {
      final key = _groupKeyForLocalRecord(row);
      final current = grouped[key];
      if (current == null || _isBetterRepresentative(row, current)) {
        grouped[key] = Map<String, dynamic>.from(row);
      }
      siblingIds.putIfAbsent(key, () => <String>[]).add(row['id_local']?.toString() ?? '');
      groupRows.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(Map<String, dynamic>.from(row));
    }

    final visible = grouped.entries.map((entry) {
      final row = Map<String, dynamic>.from(entry.value);
      final children = groupRows[entry.key] ?? <Map<String, dynamic>>[];
      children.sort(_compareLocalChildRows);
      row['__sibling_ids'] = siblingIds[entry.key]?.where((e) => e.isNotEmpty).toList() ?? <String>[];
      row['__sibling_count'] = row['__sibling_ids'].length;
      row['__group_rows'] = children;
      row['__is_master_detail_group'] = _isMasterDetailRow(row) && children.length > 1;
      row['__group_estado'] = children.any((e) => e['estado']?.toString() != 'sincronizado') ? 'pendiente' : 'sincronizado';
      return row;
    }).toList();

    if (!mounted) return;
    final visibleKeys = visible.map(_localRowKey).toSet();
    _selectedLocalKeys.removeWhere((key) => !visibleKeys.contains(key));
    setState(() => rows = visible);
  }

  Future<Map<String, _MasterDetailMeta>> _loadMasterDetailMetas() async {
    final tableRows = await local.getAll('local_format_tables', orderBy: 'orden');
    final byFormat = <String, List<Map<String, dynamic>>>{};
    for (final row in tableRows) {
      final formatoId = row['formato_id']?.toString() ?? '';
      if (formatoId.isEmpty) continue;
      byFormat.putIfAbsent(formatoId, () => <Map<String, dynamic>>[]).add(Map<String, dynamic>.from(row));
    }

    final out = <String, _MasterDetailMeta>{};
    for (final entry in byFormat.entries) {
      Map<String, dynamic>? header;
      Map<String, dynamic>? detail;
      for (final row in entry.value) {
        if (_isHeaderTableConfig(row)) header ??= row;
        if (_isDetailTableConfig(row)) detail ??= row;
      }
      if (header == null || detail == null) continue;
      final headerTable = header['tabla_destino']?.toString() ?? '';
      final detailTable = detail['tabla_destino']?.toString() ?? '';
      if (headerTable.isEmpty || detailTable.isEmpty) continue;
      out[entry.key] = _MasterDetailMeta(
        formatoId: entry.key,
        headerTable: headerTable,
        detailTable: detailTable,
        headerFormatTableId: header['id']?.toString(),
        detailFormatTableId: detail['id']?.toString(),
        fkField: detail['campo_fk_hijo']?.toString().trim().isNotEmpty == true ? detail['campo_fk_hijo'].toString().trim() : 'id_inspeccion',
        iterField: detail['campo_iterador']?.toString().trim().isNotEmpty == true ? detail['campo_iterador'].toString().trim() : null,
      );
    }
    return out;
  }

  bool _isHeaderTableConfig(Map<String, dynamic> row) {
    final relation = _norm(row['tipo_relacion']?.toString() ?? '');
    final mode = _norm(row['modo_captura']?.toString() ?? '');
    return _asBool(row['es_cabecera']) || relation == 'MAESTRO' || relation == 'CABECERA' || mode == 'CABECERA';
  }

  bool _isDetailTableConfig(Map<String, dynamic> row) {
    final relation = _norm(row['tipo_relacion']?.toString() ?? '');
    final mode = _norm(row['modo_captura']?.toString() ?? '');
    return _asBool(row['es_detalle']) || relation == 'DETALLE' || mode == 'WIZARD_ITERADOR';
  }

  bool _isMasterDetailRow(Map<String, dynamic> row) {
    final formatoId = row['formato_id']?.toString() ?? '';
    final meta = _masterDetailByFormat[formatoId];
    if (meta == null) return false;
    final table = _norm(row['tabla_destino']?.toString() ?? '');
    return table == _norm(meta.headerTable) || table == _norm(meta.detailTable);
  }

  bool _isBetterRepresentative(Map<String, dynamic> candidate, Map<String, dynamic> current) {
    final formatoId = candidate['formato_id']?.toString() ?? '';
    final meta = _masterDetailByFormat[formatoId];
    if (meta == null) return false;
    final candidateIsHeader = _norm(candidate['tabla_destino']?.toString() ?? '') == _norm(meta.headerTable);
    final currentIsHeader = _norm(current['tabla_destino']?.toString() ?? '') == _norm(meta.headerTable);
    if (candidateIsHeader && !currentIsHeader) return true;
    return false;
  }

  String _groupKeyForLocalRecord(Map<String, dynamic> row) {
    final formatoId = row['formato_id']?.toString() ?? '';
    final tableRaw = row['tabla_destino']?.toString() ?? '';
    final tableNorm = _norm(tableRaw);
    try {
      final payload = jsonDecode(row['payload_json']?.toString() ?? '{}') as Map<String, dynamic>;
      if (tableNorm == _norm('GT-ASISTENCIA_PERSONAL')) {
        final fecha = _payloadValue(payload, ['FECHA', 'FECHA_INGRESO'])?.toString().trim() ?? '';
        if (fecha.isNotEmpty) return 'ASISTENCIA|${row['estado']}|$formatoId|$fecha';
      }
      if (tableNorm == _norm('GT-TAREO_PERSONAL')) {
        final idLocal = row['id_local']?.toString() ?? '';
        final base = idLocal.replaceFirst(RegExp(r'_[0-9]+$'), '');
        if (base.isNotEmpty) return 'TAREO|${row['estado']}|$formatoId|$base';
        final fecha = _payloadValue(payload, ['FECHA'])?.toString().trim() ?? '';
        final labor = _payloadValue(payload, ['LABOR'])?.toString().trim() ?? '';
        final cc = _payloadValue(payload, ['CENTRO_COSTO', 'CENTRO COSTO'])?.toString().trim() ?? '';
        if ('$fecha$labor$cc'.isNotEmpty) return 'TAREO|${row['estado']}|$formatoId|$fecha|$cc|$labor';
      }
    } catch (_) {}

    final meta = _masterDetailByFormat[formatoId];
    if (meta == null) return _logicalKey(row);

    try {
      final payload = jsonDecode(row['payload_json']?.toString() ?? '{}') as Map<String, dynamic>;
      final table = _norm(row['tabla_destino']?.toString() ?? '');
      String masterId = '';
      if (table == _norm(meta.headerTable)) {
        masterId = _payloadValue(payload, ['id_local', 'ID_LOCAL'])?.toString().trim() ?? row['id_local']?.toString() ?? '';
      } else if (table == _norm(meta.detailTable)) {
        masterId = _payloadValue(payload, [meta.fkField, 'id_inspeccion', 'ID_INSPECCION'])?.toString().trim() ?? '';
      }
      if (masterId.isNotEmpty) return 'MD|$formatoId|$masterId';
    } catch (_) {}
    return _logicalKey(row);
  }

  int _compareLocalChildRows(Map<String, dynamic> a, Map<String, dynamic> b) {
    final formatoId = a['formato_id']?.toString() ?? b['formato_id']?.toString() ?? '';
    final meta = _masterDetailByFormat[formatoId];
    if (meta != null) {
      final aTable = _norm(a['tabla_destino']?.toString() ?? '');
      final bTable = _norm(b['tabla_destino']?.toString() ?? '');
      if (aTable == _norm(meta.headerTable) && bTable != _norm(meta.headerTable)) return -1;
      if (bTable == _norm(meta.headerTable) && aTable != _norm(meta.headerTable)) return 1;
      final ai = _iterationOf(a, meta);
      final bi = _iterationOf(b, meta);
      if (ai != bi) return ai.compareTo(bi);
    }
    return (a['created_at']?.toString() ?? '').compareTo(b['created_at']?.toString() ?? '');
  }

  int _iterationOf(Map<String, dynamic> row, _MasterDetailMeta meta) {
    try {
      final payload = jsonDecode(row['payload_json']?.toString() ?? '{}') as Map<String, dynamic>;
      final value = meta.iterField == null ? null : _payloadValue(payload, [meta.iterField!]);
      return int.tryParse(value?.toString() ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  String _title(Map<String, dynamic> row) {
    final formato = row['formato_id']?.toString() ?? 'formato';
    final count = row['__sibling_count'] is int ? row['__sibling_count'] as int : 1;
    if (row['__is_master_detail_group'] == true) {
      return '$formato · maestro-detalle · $count registros';
    }
    return count > 1 ? '$formato · $count filas' : formato;
  }

  Widget _wrapText(String value, {double width = 160, TextStyle? style, FontWeight? fontWeight, int maxLines = 3}) {
    return SizedBox(
      width: width,
      child: Text(
        value,
        softWrap: true,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style ?? TextStyle(fontWeight: fontWeight),
      ),
    );
  }

  double _adaptiveColumnWidth(String label, List<String> values, {double min = 120, double max = 260}) {
    int longest = label.length;
    for (final value in values) {
      final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (clean.length > longest) longest = clean.length;
    }
    return (longest * 8.2 + 34).clamp(min, max).toDouble();
  }

  bool _asBool(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty || text == 'null') return fallback;
    if (['true', '1', 'si', 'sí', 'yes', 'y'].contains(text)) return true;
    if (['false', '0', 'no', 'n'].contains(text)) return false;
    return fallback;
  }

  Future<List<Map<String, dynamic>>> _visibleFieldsForTable(String table) async {
    final all = await local.getAll('local_form_fields', orderBy: 'orden');
    final fields = all.where((f) {
      final destino = f['tabla_destino']?.toString() ?? '';
      if (destino.trim().isEmpty || _norm(destino) != _norm(table)) return false;
      if (!_asBool(f['activo'], fallback: true)) return false;
      return _asBool(f['visible'], fallback: true);
    }).map((e) => Map<String, dynamic>.from(e)).toList();
    fields.sort((a, b) {
      final ao = int.tryParse(a['orden']?.toString() ?? '') ?? 999999;
      final bo = int.tryParse(b['orden']?.toString() ?? '') ?? 999999;
      return ao.compareTo(bo);
    });
    return fields;
  }

  dynamic _payloadValueByField(Map<String, dynamic> payload, Map<String, dynamic> field) {
    final candidates = <String>[
      field['campo']?.toString() ?? '',
      field['etiqueta']?.toString() ?? '',
      field['id']?.toString() ?? '',
    ].where((e) => e.trim().isNotEmpty).toList();
    return _payloadValue(payload, candidates);
  }

  String _labelForField(Map<String, dynamic> field) {
    final etiqueta = field['etiqueta']?.toString().trim() ?? '';
    if (etiqueta.isNotEmpty && etiqueta.toLowerCase() != 'null') return etiqueta;
    final campo = field['campo']?.toString().trim() ?? '';
    return campo.isNotEmpty ? campo : (field['id']?.toString() ?? 'Campo');
  }


  String _localRowKey(Map<String, dynamic> row) {
    final ids = row['__sibling_ids'];
    if (ids is List && ids.isNotEmpty) return ids.map((e) => e.toString()).join('|');
    return row['id_local']?.toString() ?? _logicalKey(row);
  }


  String _createdBy(Map<String, dynamic> row) {
    final direct = row['created_by']?.toString().trim() ?? '';
    if (direct.isNotEmpty && direct.toLowerCase() != 'null') return direct;
    try {
      final payload = jsonDecode(row['payload_json']?.toString() ?? '{}') as Map<String, dynamic>;
      final value = _payloadValue(payload, ['CREADO POR', 'CREADO_POR', 'TAREADOR', 'MARCADOR_ASISTENCIA', 'USUARIO', 'USUARIO_CREACION']);
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    } catch (_) {}
    return '';
  }

  String _formatDateTime(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (dt == null) return raw.length > 19 ? raw.substring(0, 19).replaceFirst('T', ' ') : raw.replaceFirst('T', ' ');
    String two(int n) => n.toString().padLeft(2, '0');
    final yy = (dt.year % 100).toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/$yy ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  String _cellValue(Map<String, dynamic> payload, Map<String, dynamic> field) {
    return _displayPayloadValue(_labelForField(field), _payloadValueByField(payload, field));
  }

  List<Map<String, dynamic>> _rowsFromLocalGroup(Map<String, dynamic> row) {
    final groupRows = row['__group_rows'];
    if (groupRows is List && groupRows.isNotEmpty) {
      return groupRows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [row];
  }

  Future<void> _openLocalRecord(Map<String, dynamic> row) async {
    final estado = row['__group_estado']?.toString() ?? row['estado']?.toString() ?? 'pendiente';
    if (estado == 'sincronizado') {
      await _showSyncedGroupAsTable(row);
    } else {
      await _edit(row);
    }
  }

  Future<void> _deleteSelected() async {
    final selectedRows = rows.where((r) => _selectedLocalKeys.contains(_localRowKey(r))).toList();
    if (selectedRows.isEmpty) return;
    final hasSynced = selectedRows.any((r) => (r['__group_estado']?.toString() ?? r['estado']?.toString()) == 'sincronizado');
    if (hasSynced) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Solo puedes eliminar registros locales pendientes o con error.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar registros seleccionados'),
        content: Text('Se eliminarán ${selectedRows.length} registro(s) local(es). Esta acción no toca Supabase.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    for (final row in selectedRows) {
      final ids = row['__sibling_ids'];
      if (ids is List && ids.isNotEmpty) {
        for (final id in ids) {
          await local.deleteRecord(id.toString());
        }
      } else {
        await local.deleteRecord(row['id_local'] as String);
      }
    }
    _selectedLocalKeys.clear();
    await _load();
  }

  Future<void> _showSyncedGroupAsTable(Map<String, dynamic> row) async {
    final localRows = _rowsFromLocalGroup(row);
    final byTable = <String, List<Map<String, dynamic>>>{};
    for (final r in localRows) {
      final table = r['tabla_destino']?.toString() ?? 'tabla';
      byTable.putIfAbsent(table, () => <Map<String, dynamic>>[]).add(r);
    }

    final primary = const Color(0xFF123A56);
    final surface = const Color(0xFFF4F8F7);
    await showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.94,
          height: MediaQuery.of(context).size.height * 0.86,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F1EA),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Registro sincronizado', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: primary, fontWeight: FontWeight.w800))),
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
                  ],
                ),
              ),
              Expanded(
                child: Scrollbar(
                  controller: _dialogVerticalCtrl,
                  thumbVisibility: true,
                  child: ListView(
                    controller: _dialogVerticalCtrl,
                    padding: const EdgeInsets.all(16),
                    children: byTable.entries.map((entry) => Card(
                      elevation: 0,
                      color: const Color(0xFFF9FCFA),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFFD8E5DD)),
                      ),
                      margin: const EdgeInsets.only(bottom: 18),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: _syncedPayloadTable(entry.key, entry.value),
                      ),
                    )).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _syncedPayloadTable(String table, List<Map<String, dynamic>> localRows) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _visibleFieldsForTable(table),
      builder: (context, snap) {
        final fields = snap.data ?? <Map<String, dynamic>>[];
        final payloads = localRows.map(_payloadOf).toList();
        final labels = <String>[];
        final fieldByLabel = <String, Map<String, dynamic>>{};
        final representedKeys = <String>{};
        for (final f in fields) {
          final label = _labelForField(f);
          if (!labels.contains(label)) labels.add(label);
          fieldByLabel[label] = f;
          representedKeys.add(_norm(label));
          representedKeys.add(_norm(f['campo']?.toString() ?? ''));
        }
        if (labels.isEmpty) labels.add('Sin campos visibles');
        final valuesByLabel = <String, List<String>>{};
        for (final label in labels) {
          final f = fieldByLabel[label];
          valuesByLabel[label] = payloads.map((payload) => f == null ? _displayPayloadValue(label, payload[label]) : _cellValue(payload, f)).toList();
        }
        final widths = <String, double>{
          for (final label in labels) label: _adaptiveColumnWidth(label, valuesByLabel[label] ?? const <String>[]),
        };
        final tableWidget = DataTable(
          showCheckboxColumn: false,
          columnSpacing: 12,
          dataRowMinHeight: 34,
          dataRowMaxHeight: 56,
          headingRowHeight: 42,
          columns: [
            DataColumn(label: _wrapText('Fila', width: 70, fontWeight: FontWeight.w700)),
            ...labels.map((label) => DataColumn(label: _wrapText(label, width: widths[label] ?? 170, fontWeight: FontWeight.w700))),
          ],
          rows: List.generate(payloads.length, (index) {
            final payload = payloads[index];
            return DataRow(cells: [
              DataCell(_wrapText('${index + 1}', width: 70)),
              ...labels.map((label) {
                final f = fieldByLabel[label];
                final value = f == null ? _displayPayloadValue(label, payload[label]) : _cellValue(payload, f);
                return DataCell(_wrapText(value, width: widths[label] ?? 170));
              }),
            ]);
          }),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(table, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF123A56))),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFD8E5DD)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _HorizontalTableViewport(child: tableWidget),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showRecord(Map<String, dynamic> row) async {
    await _showSyncedGroupAsTable(row);
  }




  bool _looksLikeEvidenceField(String key) {
    final k = _norm(key);
    return k.contains('FOTO') || k.contains('PHOTO') || k.contains('IMAGEN') || k.contains('IMAGE') || k.contains('FIRMA') || k.contains('SIGNATURE');
  }

  String _displayPayloadValue(String key, dynamic value) {
    if (value == null) return '';
    final text = value.toString();
    final k = _norm(key);
    if (_looksLikeEvidenceField(key)) {
      if (k.contains('FIRMA') || k.contains('SIGNATURE')) return '(firma)';
      return '(foto)';
    }
    final lower = text.toLowerCase();
    if (lower.startsWith('http') && (lower.contains('storage') || lower.contains('supabase') || lower.contains('google') || lower.contains('drive'))) {
      return '(archivo)';
    }
    if (text.startsWith('data:image/')) {
      return '(foto)';
    }
    return text;
  }

  String _norm(String value) {
    var s = value.trim().toUpperCase();
    const map = {'Á':'A','É':'E','Í':'I','Ó':'O','Ú':'U','Ü':'U','Ñ':'N'};
    map.forEach((k, v) => s = s.replaceAll(k, v));
    return s.replaceAll(RegExp(r'[^A-Z0-9]+'), '_').replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  }

  dynamic _payloadValue(Map<String, dynamic> payload, List<String> candidates) {
    final wanted = candidates.map(_norm).toSet();
    for (final entry in payload.entries) {
      if (wanted.contains(_norm(entry.key))) return entry.value;
    }
    return null;
  }

  Future<Map<String, dynamic>> _payloadWithSiblingRows(Map<String, dynamic> row, Map<String, dynamic> payload) async {
    final idRegistro = _payloadValue(payload, ['ID_REGISTRO', 'ID'])?.toString().trim() ?? '';
    if (idRegistro.isEmpty) return payload;

    final formatoId = row['formato_id']?.toString() ?? '';
    final tablaDestino = row['tabla_destino']?.toString() ?? '';
    final allPending = await local.allRecords(estado: 'pendiente');
    final siblingPayloads = <Map<String, dynamic>>[];

    for (final candidate in allPending) {
      if ((candidate['formato_id']?.toString() ?? '') != formatoId) continue;
      if ((candidate['tabla_destino']?.toString() ?? '') != tablaDestino) continue;
      final decoded = jsonDecode(candidate['payload_json']?.toString() ?? '{}') as Map<String, dynamic>;
      final candidateId = _payloadValue(decoded, ['ID_REGISTRO', 'ID'])?.toString().trim() ?? '';
      if (candidateId == idRegistro) siblingPayloads.add(decoded);
    }

    if (siblingPayloads.length <= 1) return payload;
    return Map<String, dynamic>.from(payload)..['__plagas_rows'] = siblingPayloads;
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final tableNorm = _norm(row['tabla_destino']?.toString() ?? '');
    if (tableNorm == _norm('GT-TAREO_PERSONAL') && row['__group_rows'] is List && (row['__group_rows'] as List).isNotEmpty) {
      await _editTareoGroup(row);
      await _load();
      return;
    }
    if (tableNorm == _norm('GT-ASISTENCIA_PERSONAL') && row['__group_rows'] is List && (row['__group_rows'] as List).isNotEmpty) {
      await _editSingle(Map<String, dynamic>.from((row['__group_rows'] as List).first as Map));
      await _load();
      return;
    }
    if (row['__is_master_detail_group'] == true || (row['__group_rows'] is List && (row['__group_rows'] as List).length > 1)) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _MasterDetailLocalEditorPage(
            parentState: this,
            groupRow: row,
            rows: (row['__group_rows'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          ),
        ),
      );
      await _load();
      return;
    }
    await _editSingle(row);
  }


  Future<void> _editTareoGroup(Map<String, dynamic> row) async {
    final group = (row['__group_rows'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (group.isEmpty) return;
    final first = group.first;
    final payload = _payloadOf(first);
    final workers = <Map<String, dynamic>>[];
    for (final child in group) {
      final p = _payloadOf(child);
      workers.add({
        'DNI': _payloadValue(p, ['DNI'])?.toString() ?? '',
        'APELLIDOS Y NOMBRES': _payloadValue(p, ['APELLIDOS Y NOMBRES', 'APELLIDOS_NOMBRES'])?.toString() ?? '',
      });
    }
    payload['__tareo_rows'] = workers;
    await _editSingle(Map<String, dynamic>.from(first)..['payload_json'] = jsonEncode(payload));
  }

  Future<void> _editSingle(Map<String, dynamic> row) async {
    if (row['estado'] == 'sincronizado') return;
    var payload = jsonDecode(row['payload_json']?.toString() ?? '{}') as Map<String, dynamic>;
    final formatoId = row['formato_id']?.toString() ?? '';
    final moduloId = row['modulo_id']?.toString() ?? '';
    final idLocal = row['id_local']?.toString() ?? '';
    final formatTableId = row['formato_tabla_id']?.toString();
    final formats = await local.where('local_formats', 'id = ?', [formatoId]);
    if (formats.isEmpty || !mounted) return;
    final specials = await local.where('local_special_formats', 'formato_id = ? and activo = 1', [formatoId]);
    final resolvedSpecials = specials.isNotEmpty
        ? specials
        : ((row['tabla_destino']?.toString() ?? '') == 'GT-TAREO_PERSONAL'
            ? [<String, dynamic>{'tipo_pantalla': 'tareo_personal', 'activo': 1}]
            : ((row['tabla_destino']?.toString() ?? '') == 'GT-ASISTENCIA_PERSONAL'
                ? [<String, dynamic>{'tipo_pantalla': 'asistencia_personal', 'activo': 1}]
                : <Map<String, dynamic>>[]));
    payload = await _payloadWithSiblingRows(row, payload);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => resolvedSpecials.isNotEmpty
            ? SpecialFormRouterPage(
                moduleId: moduloId,
                format: formats.first,
                special: resolvedSpecials.first,
                initialPayload: payload,
                editIdLocal: idLocal,
              )
            : FormRunnerPage(
                moduleId: moduloId,
                format: formats.first,
                initialPayload: payload,
                editIdLocal: idLocal,
                initialFormatTableId: formatTableId,
              ),
      ),
    );
    await _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    if (row['estado'] == 'sincronizado') return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar registro local'),
        content: const Text('Solo se eliminará del celular. Esta acción no toca Supabase.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true) {
      final ids = row['__sibling_ids'];
      if (ids is List && ids.isNotEmpty) {
        for (final id in ids) {
          await local.deleteRecord(id.toString());
        }
      } else {
        await local.deleteRecord(row['id_local'] as String);
      }
      await _load();
    }
  }


  Map<String, dynamic> _payloadOf(Map<String, dynamic> row) {
    try {
      return jsonDecode(row['payload_json']?.toString() ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _payloadText(Map<String, dynamic> row, List<String> keys) {
    final payload = _payloadOf(row);
    final value = _payloadValue(payload, keys);
    if (value == null) return '';
    final text = value.toString();
    return text.length > 80 ? '${text.substring(0, 80)}…' : text;
  }


  Future<void> _showErrorDialog(String error) async {
    final text = error.trim();
    if (text.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFFF4F8F7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Detalle del error', style: TextStyle(color: Color(0xFF0D5F78), fontWeight: FontWeight.w800)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 420),
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Aceptar'))],
      ),
    );
  }

  Widget _errorLink(String error) {
    final text = error.trim();
    if (text.isEmpty) return const SizedBox(width: 80, child: Text(''));
    return SizedBox(
      width: 80,
      child: TextButton(
        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(42, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        onPressed: () => _showErrorDialog(text),
        child: const Text('Error', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _recordsTable() {
    final allSelectable = rows.where((r) => (r['__group_estado']?.toString() ?? r['estado']?.toString()) != 'sincronizado').toList();
    final selectedCount = _selectedLocalKeys.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text('$selectedCount seleccionado(s)'),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: selectedCount == 0 ? null : _deleteSelected,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Eliminar'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _recordsHorizontalCtrl,
            thumbVisibility: true,
            notificationPredicate: (notification) => notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _recordsHorizontalCtrl,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 790),
                child: Scrollbar(
                  controller: _recordsVerticalCtrl,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _recordsVerticalCtrl,
                    child: DataTable(
                      columnSpacing: 10,
                      horizontalMargin: 4,
                      dataRowMinHeight: 36,
                      dataRowMaxHeight: 58,
                      headingRowHeight: 44,
                      showCheckboxColumn: false,
                      headingRowColor: MaterialStateProperty.all(const Color(0xFFE8F1EA)),
                      columns: [
                        DataColumn(label: Checkbox(
                          value: allSelectable.isNotEmpty && allSelectable.every((r) => _selectedLocalKeys.contains(_localRowKey(r))),
                          onChanged: allSelectable.isEmpty ? null : (v) {
                            setState(() {
                              if (v == true) {
                                for (final r in allSelectable) {
                                  _selectedLocalKeys.add(_localRowKey(r));
                                }
                              } else {
                                for (final r in allSelectable) {
                                  _selectedLocalKeys.remove(_localRowKey(r));
                                }
                              }
                            });
                          },
                        )),
                        DataColumn(label: _wrapText('Formato', width: 220, fontWeight: FontWeight.w800, maxLines: 1)),
                        DataColumn(label: _wrapText('Fecha-Hora creación', width: 140, fontWeight: FontWeight.w800, maxLines: 1)),
                        DataColumn(label: _wrapText('Creado por', width: 150, fontWeight: FontWeight.w800, maxLines: 1)),
                        DataColumn(label: _wrapText('Error', width: 80, fontWeight: FontWeight.w800, maxLines: 1)),
                        DataColumn(label: _wrapText('Acciones', width: 110, fontWeight: FontWeight.w800, maxLines: 1)),
                      ],
                      rows: rows.map((row) {
                        final estado = row['__group_estado']?.toString() ?? row['estado']?.toString() ?? 'pendiente';
                        final ok = estado == 'sincronizado';
                        final rowKey = _localRowKey(row);
                        final selected = _selectedLocalKeys.contains(rowKey);
                        return DataRow(
                          selected: selected,
                          onSelectChanged: (_) => _openLocalRecord(row),
                          cells: [
                            DataCell(Checkbox(
                              value: selected,
                              onChanged: ok ? null : (v) {
                                setState(() {
                                  if (v == true) {
                                    _selectedLocalKeys.add(rowKey);
                                  } else {
                                    _selectedLocalKeys.remove(rowKey);
                                  }
                                });
                              },
                            )),
                            DataCell(_wrapText(_title(row), width: 220, maxLines: 2)),
                            DataCell(_wrapText(_formatDateTime(row['created_at']), width: 140, maxLines: 2)),
                            DataCell(_wrapText(_createdBy(row), width: 150, maxLines: 2)),
                            DataCell(_errorLink(row['error_mensaje']?.toString() ?? '')),
                            DataCell(ok
                                ? TextButton(onPressed: () => _showSyncedGroupAsTable(row), child: const Text('Ver'))
                                : Row(mainAxisSize: MainAxisSize.min, children: [
                                    TextButton(onPressed: () => _edit(row), child: const Text('Editar')),
                                    IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(row)),
                                  ])),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    final body = Container(
      color: const Color(0xFFF4F8F7),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pendiente', label: Text('Pendientes')),
                ButtonSegment(value: 'sincronizado', label: Text('Sincronizados')),
              ],
              selected: {filtro},
              onSelectionChanged: (v) async {
                setState(() => filtro = v.first);
                await _load();
              },
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('No hay registros locales.'))
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _recordsTable(),
                  ),
          ),
        ],
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Registros locales')),
      body: body,
    );
  }
}


class _HorizontalTableViewport extends StatefulWidget {
  final Widget child;

  const _HorizontalTableViewport({required this.child});

  @override
  State<_HorizontalTableViewport> createState() => _HorizontalTableViewportState();
}

class _HorizontalTableViewportState extends State<_HorizontalTableViewport> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      notificationPredicate: (notification) => notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 10),
        child: widget.child,
      ),
    );
  }
}


class _MasterDetailMeta {
  final String formatoId;
  final String headerTable;
  final String detailTable;
  final String? headerFormatTableId;
  final String? detailFormatTableId;
  final String fkField;
  final String? iterField;

  const _MasterDetailMeta({
    required this.formatoId,
    required this.headerTable,
    required this.detailTable,
    required this.headerFormatTableId,
    required this.detailFormatTableId,
    required this.fkField,
    required this.iterField,
  });
}

class _MasterDetailLocalEditorPage extends StatelessWidget {
  final _LocalRecordsPageState parentState;
  final Map<String, dynamic> groupRow;
  final List<Map<String, dynamic>> rows;

  const _MasterDetailLocalEditorPage({
    required this.parentState,
    required this.groupRow,
    required this.rows,
  });

  String _norm(String value) => parentState._norm(value);

  String _titleForRow(Map<String, dynamic> row) {
    final formatoId = row['formato_id']?.toString() ?? '';
    final meta = parentState._masterDetailByFormat[formatoId];
    final table = row['tabla_destino']?.toString() ?? '';
    if (meta != null && _norm(table) == _norm(meta.headerTable)) return 'Cabecera';
    if (meta != null && _norm(table) == _norm(meta.detailTable)) {
      final iter = parentState._iterationOf(row, meta);
      return iter > 0 ? 'Muestra $iter' : 'Muestra';
    }
    return table;
  }

  String _subtitleForRow(Map<String, dynamic> row) {
    final parts = <String>[
      row['tabla_destino']?.toString() ?? '',
      row['created_at']?.toString() ?? '',
    ].where((e) => e.trim().isNotEmpty).toList();
    final error = row['error_mensaje']?.toString() ?? '';
    if (error.trim().isNotEmpty) parts.add(error);
    return parts.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final allSynced = rows.every((row) => row['estado']?.toString() == 'sincronizado');
    return Scaffold(
      appBar: AppBar(title: const Text('Inspección local')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Estado')),
                DataColumn(label: Text('Tipo')),
                DataColumn(label: Text('Tabla')),
                DataColumn(label: Text('Fecha-Hora creación')),
                DataColumn(label: Text('Error')),
                DataColumn(label: Text('Acción')),
              ],
              rows: rows.map((row) {
                final synced = row['estado']?.toString() == 'sincronizado';
                return DataRow(cells: [
                  DataCell(Icon(synced ? Icons.lock_outline : Icons.edit_note, color: synced ? Colors.green : Colors.orange)),
                  DataCell(Text(_titleForRow(row))),
                  DataCell(Text(row['tabla_destino']?.toString() ?? '')),
                  DataCell(Text(parentState._formatDateTime(row['created_at']))),
                  DataCell(parentState._errorLink(row['error_mensaje']?.toString() ?? '')),
                  DataCell(synced
                      ? TextButton(onPressed: () => parentState._showSyncedGroupAsTable(groupRow), child: const Text('Ver tabla'))
                      : TextButton(onPressed: () async { await parentState._editSingle(row); if (context.mounted) Navigator.pop(context); }, child: const Text('Editar'))),
                ]);
              }).toList(),
            ),
          ),
        ),
      ),
      bottomNavigationBar: allSynced
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Edita cabecera o muestras por separado. Se mantiene un solo grupo local para la inspección.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
    );
  }
}
