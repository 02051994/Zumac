import 'package:appgt_offline_subtables/features/metrics/metrics_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el título superior conserva espacio responsive para las acciones', () {
    expect(metricsToolbarTitleMaxWidth(1440), 530);
    expect(metricsToolbarTitleMaxWidth(1024), 114);
    expect(metricsToolbarTitleMaxWidth(760), 90);
    expect(metricsToolbarTitleFontSize(1440), 17);
    expect(metricsToolbarTitleFontSize(900), 14);
  });

  testWidgets('el selector superior lista, selecciona y permite reordenar',
      (tester) async {
    final controller = MetricsToolbarController();
    addTearDown(controller.dispose);
    String? selected;
    (int, int)? reordered;
    var created = false;
    controller.attach(
      owner: Object(),
      title: 'Calidad de agua',
      titleFont: 'Roboto',
      titleColor: Colors.indigo,
      selectedId: 'ce',
      items: const [
        MetricsDashboardItem(id: 'ce', name: 'Conductividad'),
        MetricsDashboardItem(id: 'ph', name: 'Acidez'),
      ],
      allowManagement: true,
      operationInProgress: false,
      onSelectDashboard: (id) async {
        selected = id;
      },
      onReorderDashboards: (oldIndex, newIndex) async {
        reordered = (oldIndex, newIndex);
      },
      onCreateDashboard: () async {
        created = true;
      },
      onCreateWidget: () async {},
      onOpenFilters: () async {},
      onEditDashboard: () async {},
      onManageRelations: () async {},
      onDeleteDashboard: () async {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MetricsDashboardPickerDialog(controller: controller),
        ),
      ),
    );

    expect(find.text('Conductividad'), findsOneWidget);
    expect(find.text('Acidez'), findsOneWidget);
    expect(find.byIcon(Icons.drag_indicator_rounded), findsNWidgets(2));

    await tester.tap(find.text('Acidez'));
    await tester.pumpAndSettle();
    expect(selected, 'ph');

    await controller.reorderDashboards(0, 2);
    expect(reordered, (0, 2));
    await controller.createDashboard();
    expect(created, isTrue);
  });
}
