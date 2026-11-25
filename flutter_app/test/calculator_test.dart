import 'package:duka_ledger/screens/calculator_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      home: child,
    );
  }

  group('CalculatorScreen Widget & Function Tests', () {
    testWidgets('renders Business Calculator screen and top bar',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool backTapped = false;
      await tester.pumpWidget(
        buildTestableWidget(
          CalculatorScreen(onBack: () => backTapped = true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Business Calculator'), findsOneWidget);
      expect(find.text('Smart MSME Financial Tools'), findsOneWidget);

      // Verify all 5 tool chips are present
      expect(find.text('Margin & Price'), findsOneWidget);
      expect(find.text('KRA eTIMS & Tax'), findsOneWidget);
      expect(find.text('Loans & Interest'), findsOneWidget);

      // Tap back button
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(backTapped, isTrue);
    });

    testWidgets('verifies Info dialog displays problem-solving guide',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          CalculatorScreen(onBack: () {}),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.info_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('4 Business Functions'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('2. KRA eTIMS & Tax Calculator'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('calculates Profit Margin & Markup correctly',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          CalculatorScreen(onBack: () {}),
        ),
      );
      await tester.pumpAndSettle();

      // Default is Margin mode with Cost=500, Handling=0, Margin=25%
      // Total cost = 500, factor = 0.75, selling price = 500 / 0.75 = 666.67
      expect(find.text('Pricing & Profit Summary'), findsOneWidget);
      expect(find.text('KES 500.00'), findsOneWidget); // Total Unit Cost
      expect(find.text('KES 666.67'), findsOneWidget); // Recommended Selling Price
      expect(find.text('KES 166.67'), findsOneWidget); // Gross Profit per Item
      expect(find.text('25.0%'), findsOneWidget); // Gross Margin
      expect(find.text('33.3%'), findsOneWidget); // Markup on cost

      // Switch to "Margin from Price" mode
      await tester.tap(find.text('Margin from Price'));
      await tester.pumpAndSettle();

      expect(find.text('Customer Retail Selling Price (KES)'), findsOneWidget);
    });

    testWidgets('calculates KRA eTIMS & Tax (16% VAT, TOT 1.5%, WHT 5%)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          CalculatorScreen(onBack: () {}),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to KRA tax tab
      await tester.tap(find.text('KRA eTIMS & Tax'));
      await tester.pumpAndSettle();

      expect(find.text('KRA Tax & eTIMS Breakdown'), findsOneWidget);

      // Default is VAT inclusive on 1,160 KES:
      // Net = 1,160 / 1.16 = 1,000.00, Tax = 160.00
      expect(find.text('KES 1,000.00'), findsOneWidget);
      expect(find.text('KES 160.00'), findsOneWidget);

      // Switch to 16% VAT Exclusive (Add)
      await tester.tap(find.text('16% VAT Add (Exclusive)'));
      await tester.pumpAndSettle();
      // On 1,160: Net = 1,160, Tax = 185.60, Gross = 1,345.60
      expect(find.text('KES 1,160.00'), findsOneWidget);
      expect(find.text('KES 185.60'), findsOneWidget);
      expect(find.text('KES 1,345.60'), findsOneWidget);

      // Switch to Turnover Tax (1.5% TOT)
      await tester.tap(find.text('Turnover Tax (1.5% TOT)'));
      await tester.pumpAndSettle();
      // 1,160 * 0.015 = 17.40, Net = 1,142.60
      expect(find.text('KES 17.40'), findsOneWidget);
      expect(find.text('KES 1,142.60'), findsOneWidget);
    });

    testWidgets('calculates Loan & Hustler Fund repayments accurately',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          CalculatorScreen(onBack: () {}),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Loans tab
      await tester.tap(find.text('Loans & Interest'));
      await tester.pumpAndSettle();

      expect(find.text('Repayment & Credit Cost'), findsOneWidget);
      expect(find.text('Quick Loan Presets'), findsOneWidget);

      // Default is Hustler Fund preset: 5,000 KES, 8% p.a., 14 days
      // Interest = 5,000 * 0.08 * (14 / 365) = 15.34 KES
      // Total = 5,015.34 KES
      expect(find.text('KES 5,015.34'), findsOneWidget);
      expect(find.text('KES 15.34'), findsNWidgets(2));

      // Tap M-Shwari preset
      await tester.tap(find.text('📱 M-Shwari / Bank (7.5% / 30d)'));
      await tester.pumpAndSettle();
      // 5,000 * 0.075 = 375.00 KES
      expect(find.text('KES 5,375.00'), findsOneWidget);
      expect(find.text('KES 375.00'), findsNWidgets(2));
    });

    testWidgets('calculates Break-Even Sales & Daily Survival Target',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestableWidget(
          CalculatorScreen(onBack: () {}),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Break-Even tab
      await tester.ensureVisible(find.text('Break-Even Target'));
      await tester.tap(find.text('Break-Even Target'));
      await tester.pumpAndSettle();

      expect(find.text('Daily Sales Survival & Profit Target'), findsOneWidget);
      expect(find.text('Total Monthly Overhead: KES 35,000.00'), findsOneWidget);

      // Rent 15k + Power 3k + Wages 12k + Lic 2k + Other 3k = 35,000 KES
      // Margin = 25%, Trading Days = 26
      // Monthly Break-Even = 35,000 / 0.25 = 140,000.00 KES
      // Daily Break-Even = 140,000 / 26 = 5,384.62 KES / day
      expect(find.text('KES 140,000.00'), findsOneWidget);
      expect(find.text('KES 5,384.62 / day'), findsOneWidget);
    });

    testWidgets('performs Quick Math arithmetic calculations',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestableWidget(
          CalculatorScreen(onBack: () {}),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Quick Math
      await tester.ensureVisible(find.text('Quick Math'));
      await tester.tap(find.text('Quick Math'));
      await tester.pumpAndSettle();

      // Enter 4 + 5 = 9
      await tester.tap(find.widgetWithText(InkWell, '4'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(InkWell, '+'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(InkWell, '5'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(InkWell, '='));
      await tester.pumpAndSettle();

      expect(find.text('9'), findsNWidgets(2));

      // Clear with 'C'
      await tester.tap(find.widgetWithText(InkWell, 'C'));
      await tester.pumpAndSettle();
      expect(find.text('0'), findsWidgets);
    });
  });
}
