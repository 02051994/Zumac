import 'dart:math' as math;

import 'package:flutter/material.dart';

class ErpDetailColumn<T> {
  final String label;
  final double width;
  final Widget Function(BuildContext context, T row, int index) cellBuilder;

  const ErpDetailColumn({
    required this.label,
    required this.width,
    required this.cellBuilder,
  });
}

/// A compact ERP grid with a sticky heading, pinned guide columns and an
/// always-visible horizontal scrollbar at the bottom of its viewport.
class ErpStickyDetailTable<T> extends StatefulWidget {
  final List<ErpDetailColumn<T>> columns;
  final List<T> rows;
  final String title;
  final int frozenColumnCount;
  final double rowHeight;
  final double headingHeight;
  final double maxBodyHeight;
  final bool allowExpand;
  final Color bodyColor;
  final Color alternateBodyColor;

  const ErpStickyDetailTable({
    super.key,
    required this.columns,
    required this.rows,
    this.title = 'Detalle',
    this.frozenColumnCount = 1,
    this.rowHeight = 56,
    this.headingHeight = 50,
    this.maxBodyHeight = 360,
    this.allowExpand = true,
    this.bodyColor = Colors.white,
    this.alternateBodyColor = const Color(0xFFF6F9FA),
  }) : assert(frozenColumnCount >= 0);

  @override
  State<ErpStickyDetailTable<T>> createState() =>
      _ErpStickyDetailTableState<T>();
}

class _ErpStickyDetailTableState<T> extends State<ErpStickyDetailTable<T>> {
  final _headingHorizontal = ScrollController();
  final _bodyHorizontal = ScrollController();
  final _frozenVertical = ScrollController();
  final _bodyVertical = ScrollController();
  bool _syncingHorizontal = false;
  bool _syncingVertical = false;
  bool _showingExpanded = false;

  @override
  void initState() {
    super.initState();
    _headingHorizontal.addListener(_syncHeadingToBody);
    _bodyHorizontal.addListener(_syncBodyToHeading);
    _frozenVertical.addListener(_syncFrozenToBody);
    _bodyVertical.addListener(_syncBodyToFrozen);
  }

  void _jumpSafely(ScrollController target, double offset) {
    if (!target.hasClients) return;
    final position = target.position;
    target.jumpTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent));
  }

  void _syncHeadingToBody() {
    if (_syncingHorizontal || !_headingHorizontal.hasClients) return;
    _syncingHorizontal = true;
    _jumpSafely(_bodyHorizontal, _headingHorizontal.offset);
    _syncingHorizontal = false;
  }

  void _syncBodyToHeading() {
    if (_syncingHorizontal || !_bodyHorizontal.hasClients) return;
    _syncingHorizontal = true;
    _jumpSafely(_headingHorizontal, _bodyHorizontal.offset);
    _syncingHorizontal = false;
  }

  void _syncFrozenToBody() {
    if (_syncingVertical || !_frozenVertical.hasClients) return;
    _syncingVertical = true;
    _jumpSafely(_bodyVertical, _frozenVertical.offset);
    _syncingVertical = false;
  }

  void _syncBodyToFrozen() {
    if (_syncingVertical || !_bodyVertical.hasClients) return;
    _syncingVertical = true;
    _jumpSafely(_frozenVertical, _bodyVertical.offset);
    _syncingVertical = false;
  }

  Widget _cell({
    required double width,
    required double height,
    required Widget child,
    required Color color,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 12),
  }) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: color,
        border: Border(
          right: BorderSide(color: Colors.blueGrey.shade200),
          bottom: BorderSide(color: Colors.blueGrey.shade200),
        ),
      ),
      child: child,
    );
  }

  Widget _heading(List<ErpDetailColumn<T>> columns) => Row(
        children: columns
            .map((column) => _cell(
                  width: column.width,
                  height: widget.headingHeight,
                  color: const Color(0xFF42576B),
                  child: Text(
                    column.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ))
            .toList(),
      );

  Widget _rows(
    BuildContext context,
    List<ErpDetailColumn<T>> columns,
    double width,
  ) {
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: widget.rows.asMap().entries.map((entry) {
          final rowColor =
              entry.key.isEven ? widget.bodyColor : widget.alternateBodyColor;
          return Row(
            children: columns
                .map((column) => _cell(
                      width: column.width,
                      height: widget.rowHeight,
                      color: rowColor,
                      child:
                          column.cellBuilder(context, entry.value, entry.key),
                    ))
                .toList(),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _openExpanded() async {
    if (_showingExpanded || !widget.allowExpand) return;
    setState(() => _showingExpanded = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: const RoundedRectangleBorder(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(dialogContext).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar vista ampliada',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_fullscreen),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Align(
                      alignment: Alignment.topCenter,
                      child: ErpStickyDetailTable<T>(
                        columns: widget.columns,
                        rows: widget.rows,
                        title: widget.title,
                        frozenColumnCount: widget.frozenColumnCount,
                        rowHeight: widget.rowHeight,
                        headingHeight: widget.headingHeight,
                        maxBodyHeight: math.max(
                          widget.rowHeight,
                          constraints.maxHeight - widget.headingHeight - 16,
                        ),
                        allowExpand: false,
                        bodyColor: widget.bodyColor,
                        alternateBodyColor: widget.alternateBodyColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _showingExpanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showingExpanded) {
      return Container(
        height: 44,
        color: Colors.white,
        alignment: Alignment.centerRight,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('Tabla abierta en vista ampliada'),
        ),
      );
    }
    final frozenCount =
        widget.frozenColumnCount.clamp(0, widget.columns.length);
    final frozen = widget.columns.take(frozenCount).toList();
    final scrolling = widget.columns.skip(frozenCount).toList();
    final frozenWidth =
        frozen.fold<double>(0, (sum, column) => sum + column.width);
    final scrollingWidth =
        scrolling.fold<double>(0, (sum, column) => sum + column.width);
    final bodyHeight = math.min(
      widget.maxBodyHeight,
      math.max(widget.rowHeight, widget.rows.length * widget.rowHeight),
    );

    return LayoutBuilder(builder: (context, constraints) {
      final availableWidth = constraints.maxWidth.isFinite
          ? math.max(0.0, constraints.maxWidth - 2)
          : frozenWidth + scrollingWidth;
      final safeFrozenWidth = math.min(frozenWidth, availableWidth * .62);
      final remainingWidth = math.max(0.0, availableWidth - safeFrozenWidth);

      final grid = Container(
        height: widget.headingHeight + bodyHeight + 14,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.blueGrey.shade300),
        ),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: safeFrozenWidth,
                  child: ClipRect(child: _heading(frozen)),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _headingHorizontal,
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: SizedBox(
                      width: scrollingWidth,
                      child: _heading(scrolling),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: safeFrozenWidth,
                    child: ClipRect(
                      child: SingleChildScrollView(
                        controller: _frozenVertical,
                        child: _rows(context, frozen, frozenWidth),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: remainingWidth,
                    child: Scrollbar(
                      controller: _bodyHorizontal,
                      thumbVisibility: true,
                      trackVisibility: true,
                      scrollbarOrientation: ScrollbarOrientation.bottom,
                      notificationPredicate: (notification) =>
                          notification.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _bodyHorizontal,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(bottom: 14),
                        child: SizedBox(
                          width: scrollingWidth,
                          child: Scrollbar(
                            controller: _bodyVertical,
                            thumbVisibility: true,
                            trackVisibility: true,
                            scrollbarOrientation: ScrollbarOrientation.right,
                            notificationPredicate: (notification) =>
                                notification.metrics.axis == Axis.vertical,
                            child: SingleChildScrollView(
                              controller: _bodyVertical,
                              child: _rows(context, scrolling, scrollingWidth),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

      if (!widget.allowExpand) return grid;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 42,
            color: Colors.white,
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Expandir tabla',
              onPressed: _openExpanded,
              icon: const Icon(Icons.open_in_full),
            ),
          ),
          grid,
        ],
      );
    });
  }

  @override
  void dispose() {
    _headingHorizontal.dispose();
    _bodyHorizontal.dispose();
    _frozenVertical.dispose();
    _bodyVertical.dispose();
    super.dispose();
  }
}
