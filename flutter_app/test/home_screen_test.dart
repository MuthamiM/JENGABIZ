import 'dart:convert';
import 'dart:io';

import 'package:duka_ledger/main.dart';
import 'package:duka_ledger/screens/stock_screen.dart';
import 'package:duka_ledger/services/api_service.dart';
import 'package:duka_ledger/services/db_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
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

  testWidgets('profile screen uploads and removes shop photo', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final supportDir = Directory.systemTemp.createTempSync('jengabiz-profile-');
    addTearDown(() {
      if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => supportDir.path,
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
    });

    final requests = <Map<String, Object?>>[];
    final api = JengaApiService.forTestingRequests((method, uri, payload) async {
      requests.add({
        'method': method,
        'path': uri.path,
        'payload': Map<String, dynamic>.from(payload),
      });
      return const JengaApiResponse(200, {
        'success': true,
        'imageType': 'shop',
        'storage': 'teledrive',
      });
    });
    api.configure(
      url: 'https://jengabiz-api.mftechnologies.org',
      token: 'session-token',
    );
    api.sessionEmail = 'shop@example.com';

    // Valid minimal 1x1 transparent PNG so Image.file decodes without error.
    final samplePng = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );

    final db = JengaDB.instance;
    db.currentUser = JengaUser(
      id: 'acc_profile_test',
      name: 'Shop Owner',
      shopName: 'TeleDrive Shop',
      phone: '',
      email: 'shop@example.com',
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
            apiService: api,
            imagePickerOverride: (_) async => XFile.fromData(
              samplePng,
              mimeType: 'image/png',
              name: 'shop.png',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shop photo'), findsNothing);
    await tester.tap(find.byIcon(Icons.camera_alt_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Profile Photo'), findsOneWidget);
    expect(find.text('Personal photo'), findsOneWidget);
    expect(find.text('Shop photo'), findsOneWidget);

    await tester.tap(find.text('Shop photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    for (var i = 0;
        i < 20 && find.text('Shop photo uploaded.').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Shop photo uploaded.'), findsOneWidget);
    expect(find.text('Shop photo'), findsOneWidget);
    final putRequests = requests.where((r) => r['method'] == 'PUT').toList();
    expect(putRequests, hasLength(1));
    expect(putRequests.first['path'], '/email-auth/profile/image');
    final sentPayload = putRequests.first['payload'] as Map<String, dynamic>;
    expect(sentPayload['imageType'], 'shop');
    expect(sentPayload['mimeType'], 'image/png');
    expect(sentPayload['imageBase64'], base64Encode(samplePng));

    // Reopen sheet to remove the uploaded photo.
    await tester.tap(find.byIcon(Icons.camera_alt_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Remove photo'), findsOneWidget);
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove photo').last);
    for (var i = 0;
        i < 20 && find.text('Profile photo removed.').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pump(const Duration(milliseconds: 300));

    final deleteRequests =
        requests.where((r) => r['method'] == 'DELETE').toList();
    expect(deleteRequests, hasLength(1));
    expect(deleteRequests.first['path'], '/email-auth/profile/image');
    expect(find.text('Profile photo removed.'), findsOneWidget);
    expect(find.text('Shop photo'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
