import 'package:flutter/material.dart';

typedef MobileRecordTextBuilder = String Function(
  Map<String, dynamic> record,
  String column,
);

typedef MobileRecordCellBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> record,
  String column,
);

/// Presentación compacta de una tabla dinámica para pantallas móviles.
///
/// La lista no interpreta reglas ni modifica datos. Recibe las columnas y los
/// valores ya resueltos por el motor dinámico para que dropdowns, fórmulas,
/// matrices y formatos condicionales sigan teniendo una única fuente de verdad.
class MobileRecordsList extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  final List<String> columns;
  final String Function(String column) labelFor;
  final MobileRecordTextBuilder textFor;
  final MobileRecordCellBuilder cellBuilder;
  final void Function(Map<String, dynamic> record)? onEdit;
  final bool selectionEnabled;
  final bool Function(Map<String, dynamic> record, int index)? isSelected;
  final void Function(Map<String, dynamic> record, int index, bool selected)?
      onSelected;
  final int rowNumberOffset;

  const MobileRecordsList({
    super.key,
    required this.records,
    required this.columns,
    required this.labelFor,
    required this.textFor,
    required this.cellBuilder,
    this.onEdit,
    this.selectionEnabled = false,
    this.isSelected,
    this.onSelected,
    this.rowNumberOffset = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const Center(
        child: Text(
          'No hay registros para mostrar',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF4A6075),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return ListView.separated(
      key: const Key('mobile-records-list'),
      padding: const EdgeInsets.only(bottom: 92),
      itemCount: records.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final record = records[index];
        return _MobileRecordCard(
          record: record,
          columns: columns,
          labelFor: labelFor,
          textFor: textFor,
          cellBuilder: cellBuilder,
          recordNumber: rowNumberOffset + index + 1,
          onEdit: onEdit == null ? null : () => onEdit!(record),
          selectionEnabled: selectionEnabled,
          selected: isSelected?.call(record, index) ?? false,
          onSelected: onSelected == null
              ? null
              : (selected) => onSelected!(record, index, selected),
        );
      },
    );
  }
}

class _MobileRecordCard extends StatefulWidget {
  static const int collapsedFieldCount = 4;

  final Map<String, dynamic> record;
  final List<String> columns;
  final String Function(String column) labelFor;
  final MobileRecordTextBuilder textFor;
  final MobileRecordCellBuilder cellBuilder;
  final int recordNumber;
  final VoidCallback? onEdit;
  final bool selectionEnabled;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  const _MobileRecordCard({
    required this.record,
    required this.columns,
    required this.labelFor,
    required this.textFor,
    required this.cellBuilder,
    required this.recordNumber,
    required this.onEdit,
    required this.selectionEnabled,
    required this.selected,
    required this.onSelected,
  });

  @override
  State<_MobileRecordCard> createState() => _MobileRecordCardState();
}

class _MobileRecordCardState extends State<_MobileRecordCard> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final visibleColumns = expanded
        ? widget.columns
        : widget.columns.take(_MobileRecordCard.collapsedFieldCount).toList();
    final remaining = widget.columns.length - visibleColumns.length;
    final firstValue = _firstMeaningfulValue();

    return Card(
      key: ValueKey('mobile-record-${widget.recordNumber}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFDCE6EC)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xFFF3F8FA),
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: const Color(0xFF176B87),
                  foregroundColor: Colors.white,
                  child: Text(
                    '${widget.recordNumber}',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Registro ${widget.recordNumber}',
                        style: const TextStyle(
                          color: Color(0xFF17324D),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (firstValue.isNotEmpty)
                        Text(
                          firstValue,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFF60758A), fontSize: 12),
                        ),
                    ],
                  ),
                ),
                if (widget.onEdit != null)
                  IconButton(
                    key: ValueKey('edit-record-${widget.recordNumber}'),
                    tooltip: 'Editar registro',
                    onPressed: widget.onEdit,
                    icon: const Icon(Icons.edit_outlined,
                        color: Color(0xFF176B87)),
                  ),
                if (widget.selectionEnabled)
                  Checkbox(
                    value: widget.selected,
                    onChanged: widget.onSelected == null
                        ? null
                        : (value) => widget.onSelected!(value ?? false),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Column(
              children: [
                for (var index = 0; index < visibleColumns.length; index++) ...[
                  _fieldRow(context, visibleColumns[index]),
                  if (index < visibleColumns.length - 1)
                    const Divider(height: 15, color: Color(0xFFEDF2F5)),
                ],
              ],
            ),
          ),
          if (remaining > 0 ||
              expanded &&
                  widget.columns.length > _MobileRecordCard.collapsedFieldCount)
            InkWell(
              key: ValueKey('expand-record-${widget.recordNumber}'),
              onTap: () => setState(() => expanded = !expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 5, 14, 11),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 19,
                      color: const Color(0xFF176B87),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      expanded ? 'Ver menos' : 'Ver $remaining campos más',
                      style: const TextStyle(
                        color: Color(0xFF176B87),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _firstMeaningfulValue() {
    for (final column in widget.columns) {
      final value = widget.textFor(widget.record, column).trim();
      if (value.isNotEmpty && value.toUpperCase() != 'NULL') return value;
    }
    return '';
  }

  Widget _fieldRow(BuildContext context, String column) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            widget.labelFor(column),
            style: const TextStyle(
              color: Color(0xFF60758A),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: widget.cellBuilder(context, widget.record, column)),
      ],
    );
  }
}
