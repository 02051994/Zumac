import 'package:appgt_offline_subtables/features/onboarding/onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> goNext(WidgetTester tester) async {
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
  }

  testWidgets('presenta siete beneficios de negocio en el orden solicitado',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OnboardingPage()),
    );

    final logo = find.byKey(const ValueKey('onboarding-logo'));
    expect(logo, findsOneWidget);
    expect(tester.getSize(logo), const Size(38, 38));
    expect(
      find.text('Toda su operación, conectada y trazable'),
      findsOneWidget,
    );
    expect(find.textContaining('Power BI'), findsOneWidget);
    expect(find.textContaining('Supabase'), findsNothing);
    expect(find.text('Siguiente'), findsOneWidget);

    await goNext(tester);
    expect(find.text('Capture datos incluso sin señal'), findsOneWidget);
    expect(find.text('Atrás'), findsOneWidget);

    await goNext(tester);
    expect(find.text('+100 Formatos listos y editables'), findsOneWidget);
    expect(find.textContaining('costo'), findsNothing);

    await goNext(tester);
    expect(
      find.text('Constructor de Formatos Inteligente'),
      findsOneWidget,
    );
    expect(
      find.text('Agrega nuevas secciones, módulos y formatos'),
      findsOneWidget,
    );

    await goNext(tester);
    expect(find.text('DATOS CONFIABLES'), findsOneWidget);

    await goNext(tester);
    expect(find.text('ALERTAS INTELIGENTES'), findsOneWidget);

    await goNext(tester);
    expect(find.text('Una integración que crece contigo'), findsOneWidget);
    expect(
      find.text('Precio por integración, no por cada usuario'),
      findsOneWidget,
    );
    expect(find.text('Comenzar'), findsOneWidget);
  });

  testWidgets('usa colores solicitados e ilustración compacta en móvil',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: OnboardingPage()),
    );

    final illustration = find.byKey(
      const ValueKey('onboarding-illustration-1'),
    );
    expect(illustration, findsOneWidget);
    expect(tester.getSize(illustration).width, lessThanOrEqualTo(286));
    expect(tester.getSize(illustration).height, lessThanOrEqualTo(170));

    final feature = tester.widget<Text>(
      find.text('Orden y trazabilidad desde el campo hasta la gestión'),
    );
    expect(feature.style?.fontSize, 16);

    await goNext(tester);
    await goNext(tester);
    expect(
      _illustrationColor(tester, 3),
      const Color(0xFFFABF00),
    );

    await goNext(tester);
    expect(
      _illustrationColor(tester, 4),
      const Color(0xFF0FA69D),
    );

    await goNext(tester);
    expect(
      _illustrationColor(tester, 5),
      const Color(0xFF615170),
    );

    await goNext(tester);
    expect(
      _illustrationColor(tester, 6),
      const Color(0xFFEA726D),
    );
  });
}

Color _illustrationColor(WidgetTester tester, int number) {
  final container = tester.widget<Container>(
    find.byKey(ValueKey('onboarding-illustration-$number')),
  );
  final decoration = container.decoration! as BoxDecoration;
  return decoration.color!;
}
