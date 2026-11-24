import 'package:duka_ledger/main.dart';
import 'package:duka_ledger/screens/stock_screen.dart';
import 'package:duka_ledger/services/api_service.dart';
import 'package:duka_ledger/services/db_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final nav = find.byType(FloatingNav);
    final selectedHomeIcon = tester.widget<Icon>(
      find.descendant(of: nav, matching: find.byIcon(Icons.home_outlined)),
    );
    expect(selectedHomeIcon.color, kBlue);
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
    SharedPreferences.setMockInitialValues({});
    JengaDB.instance.isInitialized = false;
    JengaDB.instance.users = [];
    JengaDB.instance.currentUser = null;
    JengaDB.instance.shouldResumeSavedSession = false;
    JengaApiService.instance.authToken = null;
    JengaApiService.instance.sessionEmail = null;

    await tester.pumpWidget(const MaterialApp(home: Root()));
    expect(find.text('Loading JengaBiz…'), findsNothing);

    // Pump both FakeAsync microtasks/timers (SharedPreferences, channels, switcher)
    // and real async I/O until _initializeApp transitions from splash to welcome.
    for (var i = 0;
        i < 15 && find.text('Explore JengaBiz').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
    }
    await tester.pump(const Duration(milliseconds: 300));

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

    expect(find.text('Stock & Inventory Manager'), findsNothing);
    expect(find.text('Restock Dispatch'), findsNothing);
    expect(find.text('QA stock item'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
    expect(wentBack, isTrue);
  });

  testWidgets('stock screen offers product creation', (tester) async {
    final db = JengaDB.instance;
    db.items = [];
    db.currentUser = null;
    db.inventoryOwnerId = null;

    await tester.pumpWidget(
      MaterialApp(home: StockScreen(onBack: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add product'), findsOneWidget);
    await tester.tap(find.text('Add product'));
    await tester.pumpAndSettle();
    expect(find.text('Add Product'), findsOneWidget);
    expect(find.text('Product name'), findsOneWidget);
    expect(find.text('Quantity on hand'), findsOneWidget);
    expect(find.text('Low-stock alert at'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('product editor handles keyboard resize and dialog dismissal',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);

    final db = JengaDB.instance;
    db.items = [];
    await tester.pumpWidget(
      MaterialApp(home: StockScreen(onBack: () {})),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Add product'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Add Product'), findsOneWidget);
    expect(find.text('Upload stock image'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
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
            referralSummaryLoader: () async => const JengaApiResponse(200, {
              'success': true,
              'hasLocation': true,
              'referralCode': 'referral',
              'totalPoints': 0,
              'referralCount': 0,
            }),
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

    await tester.tap(find.text('Refer & Earn'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('https://jengabiz.mftechnologies.org/?ref=referral'),
      findsOneWidget,
    );
    expect(find.text('50–75 pts'), findsNothing);
    expect(find.textContaining('different county or country'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
