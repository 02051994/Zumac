import 'package:appgt_offline_subtables/features/formats/widgets/mobile_records_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget subject({VoidCallback? onEdit}) {
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
          onEdit: onEdit == null ? null : (_) => onEdit(),
        ),
      ),
    );
  }

  testWidgets('muestra cuatro campos y permite expandir los restantes',
      (tester) async {
    await tester.pumpWidget(subject());

    expect(find.text('REG-001'), findsNWidgets(2));
    expect(find.text('Palta'), findsOneWidget);
    expect(find.text('Activo'), findsNothing);
    expect(find.text('Ver 1 campos más'), findsOneWidget);

    await tester.tap(find.text('Ver 1 campos más'));
    await tester.pumpAndSettle();

    expect(find.text('Activo'), findsOneWidget);
    expect(find.text('Ver menos'), findsOneWidget);
  });

  testWidgets('expone la acción de edición sin alterar los valores',
      (tester) async {
    var edits = 0;
    await tester.pumpWidget(subject(onEdit: () => edits++));

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();

    expect(edits, 1);
    expect(find.text('Palta'), findsOneWidget);
  });
}
