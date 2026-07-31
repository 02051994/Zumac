import 'dart:math' as math;

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

/// Tabla horizontal ligera para registros dinámicos en pantallas móviles.
///
/// Este widget solo presenta columnas y valores ya resueltos por el motor del
/// formato. No interpreta matrices ni modifica dropdowns, fórmulas o reglas.
class MobileRecordsList extends StatefulWidget {
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
  State<MobileRecordsList> createState() => _MobileRecordsListState();
}

class _MobileRecordsListState extends State<MobileRecordsList> {
  static const double _numberWidth = 58;
  static const double _selectionWidth = 72;
  static const double _editWidth = 58;
  static const double _columnWidth = 176;
  static const double _headerHeight = 56;
  static const double _rowHeight = 76;

  final ScrollController _horizontalController = ScrollController();
  final ScrollController _numberVerticalController = ScrollController();
  final ScrollController _contentVerticalController = ScrollController();
  bool _syncingVerticalScroll = false;

  @override
  void initState() {
    super.initState();
    _numberVerticalController.addListener(_syncFromNumberColumn);
    _contentVerticalController.addListener(_syncFromContent);
  }

  void _syncFromNumberColumn() => _syncVertical(
        source: _numberVerticalController,
        target: _contentVerticalController,
      );

  void _syncFromContent() => _syncVertical(
        source: _contentVerticalController,
        target: _numberVerticalController,
      );

  void _syncVertical({
    required ScrollController source,
    required ScrollController target,
  }) {
    if (_syncingVerticalScroll || !source.hasClients || !target.hasClients) {
      return;
    }
    final offset = source.offset.clamp(
      target.position.minScrollExtent,
      target.position.maxScrollExtent,
    );
    if ((target.offset - offset).abs() < 0.5) return;
    _syncingVerticalScroll = true;
    target.jumpTo(offset);
    _syncingVerticalScroll = false;
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _numberVerticalController
      ..removeListener(_syncFromNumberColumn)
      ..dispose();
    _contentVerticalController
      ..removeListener(_syncFromContent)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.records.isEmpty) {
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final actionWidth = (widget.selectionEnabled ? _selectionWidth : 0) +
            (widget.onEdit != null ? _editWidth : 0);
        final scrollingContentWidth =
            (widget.columns.length * _columnWidth) + actionWidth;
        final availableScrollingWidth = math.max(
          0.0,
          constraints.maxWidth - _numberWidth,
        );
        final tableWidth = math.max(
          availableScrollingWidth,
          scrollingContentWidth,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: const Key('mobile-table-hint'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F3F5),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Row(
                children: [
                  Icon(Icons.swipe_left_alt,
                      size: 18, color: Color(0xFF176B87)),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Desliza horizontalmente para ver todas las columnas.',
                      style: TextStyle(
                        color: Color(0xFF315B68),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    key: const Key('mobile-table-frozen-number-column'),
                    width: _numberWidth,
                    child: Column(
                      children: [
                        _numberHeader(),
                        Expanded(
                          child: ListView.builder(
                            controller: _numberVerticalController,
                            padding: const EdgeInsets.only(bottom: 84),
                            itemExtent: _rowHeight,
                            itemCount: widget.records.length,
                            itemBuilder: (context, index) => _numberCell(index),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Scrollbar(
                      controller: _horizontalController,
                      thumbVisibility: true,
                      notificationPredicate: (notification) =>
                          notification.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        key: const Key('mobile-records-list'),
                        controller: _horizontalController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: tableWidth,
                          child: Column(
                            children: [
                              _scrollingHeaderRow(),
                              Expanded(
                                child: ListView.builder(
                                  controller: _contentVerticalController,
                                  padding: const EdgeInsets.only(bottom: 84),
                                  itemExtent: _rowHeight,
                                  itemCount: widget.records.length,
                                  itemBuilder: (context, index) =>
                                      _scrollingRecordRow(context, index),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _numberHeader() {
    return Container(
      height: _headerHeight,
      decoration: const BoxDecoration(
        color: Color(0xFF0F5265),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(12)),
      ),
      child: _headerCell('N°', _numberWidth, alignment: Alignment.center),
    );
  }

  Widget _scrollingHeaderRow() {
    return Container(
      key: const Key('mobile-table-header'),
      height: _headerHeight,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F5265), Color(0xFF176B87)],
        ),
        borderRadius: BorderRadius.only(topRight: Radius.circular(12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.selectionEnabled)
            _headerCell('Elegir', _selectionWidth, alignment: Alignment.center),
          for (final column in widget.columns)
            _headerCell(widget.labelFor(column), _columnWidth),
          if (widget.onEdit != null)
            _headerCell('Editar', _editWidth, alignment: Alignment.center),
        ],
      ),
    );
  }

  Widget _headerCell(
    String label,
    double width, {
    Alignment alignment = Alignment.centerLeft,
  }) {
    return Container(
      width: width,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0x33FFFFFF))),
      ),
      child: Text(
        label,
        maxLines: 3,
        softWrap: true,
        overflow: TextOverflow.ellipsis,
        textAlign:
            alignment == Alignment.center ? TextAlign.center : TextAlign.left,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Color _rowColor(int index, bool selected) => selected
      ? const Color(0xFFDDF1F4)
      : index.isEven
          ? Colors.white
          : const Color(0xFFF7FAFB);

  Widget _numberCell(int index) {
    final record = widget.records[index];
    final number = widget.rowNumberOffset + index + 1;
    final selected = widget.isSelected?.call(record, index) ?? false;
    return Container(
      key: ValueKey('mobile-record-number-$number'),
      height: _rowHeight,
      color: _rowColor(index, selected),
      child: _dataCell(
        SizedBox(
          width: 30,
          height: 30,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Color(0xFF176B87),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        _numberWidth,
        alignment: Alignment.center,
      ),
    );
  }

  Widget _scrollingRecordRow(BuildContext context, int index) {
    final record = widget.records[index];
    final number = widget.rowNumberOffset + index + 1;
    final selected = widget.isSelected?.call(record, index) ?? false;
    return Container(
      key: ValueKey('mobile-record-$number'),
      height: _rowHeight,
      color: _rowColor(index, selected),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.selectionEnabled)
            _dataCell(
              Checkbox(
                value: selected,
                activeColor: const Color(0xFF0D5F78),
                onChanged: widget.onSelected == null
                    ? null
                    : (value) => widget.onSelected!(
                          record,
                          index,
                          value ?? false,
                        ),
              ),
              _selectionWidth,
              alignment: Alignment.center,
            ),
          for (final column in widget.columns)
            _dataCell(
              widget.cellBuilder(context, record, column),
              _columnWidth,
            ),
          if (widget.onEdit != null)
            _dataCell(
              IconButton(
                key: ValueKey('edit-record-$number'),
                tooltip: 'Editar registro',
                onPressed: () => widget.onEdit!(record),
                icon: const Icon(
                  Icons.edit_outlined,
                  color: Color(0xFF176B87),
                ),
              ),
              _editWidth,
              alignment: Alignment.center,
            ),
        ],
      ),
    );
  }

  Widget _dataCell(
    Widget child,
    double width, {
    Alignment alignment = Alignment.centerLeft,
  }) {
    return Container(
      width: width,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: Color(0xFFE3EBEE)),
          bottom: BorderSide(color: Color(0xFFDCE6EC)),
        ),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          color: Color(0xFF17324D),
          fontSize: 12.5,
        ),
        child: child,
      ),
    );
  }
}
