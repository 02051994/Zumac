import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appgt_offline_subtables/features/form_runner/erp_sticky_detail_table.dart';

void main() {
  testWidgets('renderiza encabezado fijo, columna guía y scroll inferior',
      (tester) async {
    final rows = List<int>.generate(20, (index) => index + 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            child: ErpStickyDetailTable<int>(
              rows: rows,
              frozenColumnCount: 1,
              maxBodyHeight: 260,
              columns: [
                ErpDetailColumn(
                  label: 'Artículo código',
                  width: 170,
                  cellBuilder: (_, row, __) => Text('ART-$row'),
                ),
                ErpDetailColumn(
                  label: 'Descripción',
                  width: 500,
                  cellBuilder: (_, row, __) => Text('Artículo $row'),
                ),
                ErpDetailColumn(
                  label: 'Cantidad',
                  width: 180,
                  cellBuilder: (_, row, __) => Text('$row'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Artículo código'), findsOneWidget);
    expect(find.text('ART-1'), findsOneWidget);
    expect(find.byType(Scrollbar), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('erp-detail-body-horizontal')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('erp-detail-body-vertical')),
      findsOneWidget,
    );
    expect(find.byTooltip('Expandir tabla'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('erp-detail-body-vertical')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    final frozenRowY = tester.getTopLeft(find.text('ART-10')).dy;
    final scrollingRowY = tester.getTopLeft(find.text('Artículo 10')).dy;
    expect(frozenRowY, closeTo(scrollingRowY, .1));

    await tester.tap(find.byTooltip('Expandir tabla'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Cerrar vista ampliada'), findsOneWidget);
    expect(find.text('ART-20'), findsOneWidget);
  });
}
