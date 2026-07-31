import 'package:appgt_offline_subtables/features/formats/widgets/mobile_records_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget subject({VoidCallback? onEdit, bool selectionEnabled = false}) {
    final rows = [
      {
        'codigo': 'REG-001',
        'producto': 'Palta',
        'fecha': '2026-07-15',
        'cantidad': '12',
        'estado': 'Activo',
      },
    ];
    const columns = ['codigo', 'producto', 'fecha', 'cantidad', 'estado'];

    return MaterialApp(
      home: Scaffold(
        body: MobileRecordsList(
          records: rows,
          columns: columns,
          labelFor: (column) => column.toUpperCase(),
          textFor: (record, column) => record[column]?.toString() ?? '',
          cellBuilder: (context, record, column) => Text('${record[column]}'),
          selectionEnabled: selectionEnabled,
          onEdit: onEdit == null ? null : (_) => onEdit(),
        ),
      ),
    );
  }

  testWidgets('muestra encabezados y todos los valores en una tabla horizontal',
      (tester) async {
    await tester.pumpWidget(subject());

    expect(find.byKey(const Key('mobile-table-header')), findsOneWidget);
    expect(find.text('CODIGO'), findsOneWidget);
    expect(find.text('PRODUCTO'), findsOneWidget);
    expect(find.text('REG-001'), findsOneWidget);
    expect(find.text('Palta'), findsOneWidget);
    expect(find.text('Activo'), findsOneWidget);
    expect(find.byKey(const Key('mobile-table-hint')), findsOneWidget);
  });

  testWidgets('expone la acción de edición sin alterar los valores',
      (tester) async {
    var edits = 0;
    await tester.pumpWidget(subject(onEdit: () => edits++));

    final editButton = find.byKey(const Key('edit-record-1'));
    await tester.ensureVisible(editButton);
    await tester.pumpAndSettle();
    await tester.tap(editButton);
    await tester.pump();

    expect(edits, 1);
    expect(find.text('Palta'), findsOneWidget);
  });

  testWidgets('mantiene fija la columna N° durante el scroll horizontal',
      (tester) async {
    await tester.pumpWidget(subject(selectionEnabled: true));

    final numberCell = find.byKey(const Key('mobile-record-number-1'));
    final initialNumberX = tester.getTopLeft(numberCell).dx;
    final initialValueX = tester.getTopLeft(find.text('REG-001')).dx;

    await tester.drag(
      find.byKey(const Key('mobile-records-list')),
      const Offset(-520, 0),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(numberCell).dx, closeTo(initialNumberX, 0.1));
    expect(tester.getTopLeft(find.text('REG-001')).dx, lessThan(initialValueX));
    expect(find.text('Elegir'), findsOneWidget);
  });
}
