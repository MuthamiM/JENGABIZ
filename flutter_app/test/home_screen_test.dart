import 'package:duka_ledger/main.dart';
import 'package:duka_ledger/screens/stock_screen.dart';
import 'package:duka_ledger/services/db_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home dashboard renders and scrolls its quick stats',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final db = JengaDB.instance;
    db.currentUser = null;
    db.items = [
      StockItem(
        id: 'qa-item',
        name: 'QA item',
        category: 'General',
        price: 25,
        costPrice: 10,
        stockRemaining: 4,
        unitsSold: 3,
        sku: 'QA-1',
        imageUrl: '',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(go: (_) {}, unread: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total Revenue'), findsOneWidget);
    expect(find.text('In Stock'), findsOneWidget);
    expect(find.text('Low Stock'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final quickStatsScroll = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    await tester.drag(quickStatsScroll, const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(find.text('Out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('welcome screen appears without an intermediate loading page',
      (tester) async {
    JengaDB.instance.isInitialized = false;
    await tester.pumpWidget(const MaterialApp(home: Root()));

    expect(find.text('Loading JengaBiz…'), findsNothing);
    expect(find.text('Explore JengaBiz'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('stock inventory renders and its back button returns',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final db = JengaDB.instance;
    db.items = [
      StockItem(
        id: 'qa-stock-item',
        name: 'QA stock item',
        category: 'General',
        price: 25,
        costPrice: 10,
        stockRemaining: 4,
        unitsSold: 3,
        sku: 'QA-1',
        imageUrl: '',
      ),
    ];
    var wentBack = false;

    await tester.pumpWidget(
      MaterialApp(
        home: StockScreen(onBack: () => wentBack = true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stock & Inventory Manager'), findsOneWidget);
    expect(find.text('QA stock item'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
    expect(wentBack, isTrue);
  });

  testWidgets('JengaBiz landing page starts sign-in when continued',
      (tester) async {
    var continued = false;
    await tester.pumpWidget(
      MaterialApp(home: WelcomeScreen(onStart: () => continued = true)),
    );
    await tester.pumpAndSettle();

    expect(
        find.text('Your shop, stock and sales — all in view.'), findsOneWidget);
    await tester.tap(find.text('Explore JengaBiz'));
    expect(continued, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('referral link stays hidden until expanded and uses JengaBiz URL',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final db = JengaDB.instance;
    db.currentUser = JengaUser(
      id: 'qa-referral-user',
      name: 'QA User',
      shopName: 'QA Shop',
      phone: '',
      email: 'referral@example.com',
      createdAt: DateTime.now().toIso8601String(),
    );
    db.items = [];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileScreen(
            go: (_) {},
            unread: 0,
            onLogout: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('https://jengabiz.mftechnologies.org/?ref=referral'),
      findsNothing,
    );
    expect(find.text('WhatsApp'), findsNothing);
    expect(find.text('X (Twitter)'), findsNothing);

    await tester.tap(find.text('Refer & Earn (KES 100)'));
    await tester.pumpAndSettle();

    expect(
      find.text('https://jengabiz.mftechnologies.org/?ref=referral'),
      findsOneWidget,
    );
    expect(find.textContaining('Tap the link to share'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
