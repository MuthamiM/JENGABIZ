import 'dart:convert';

import 'package:duka_ledger/main.dart';
import 'package:duka_ledger/screens/notifications_screen.dart';
import 'package:duka_ledger/services/api_service.dart';
import 'package:duka_ledger/services/app_update_service.dart';
import 'package:duka_ledger/services/db_service.dart';
import 'package:duka_ledger/services/notification_center_service.dart';
import 'package:duka_ledger/services/stock_notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => '/tmp',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _mockPathProvider();
    NotificationCenterService.instance.resetForTesting();
    JengaDB.instance.isInitialized = true;
    JengaDB.instance.currentUser = null;
    JengaDB.instance.users = [];
    JengaDB.instance.items = [];
    JengaDB.instance.shouldResumeSavedSession = false;
    JengaApiService.instance.authToken = null;
    JengaApiService.instance.sessionEmail = null;
  });

  test('unread notification count starts at 0 when there are no notifications',
      () async {
    await NotificationCenterService.instance.ensureInitialized();
    expect(NotificationCenterService.instance.unreadCount, 0);
    expect(NotificationCenterService.instance.notifications, isEmpty);
  });

  test(
      'bell shows live unread count, clears on expand or mark-all-read, and persists',
      () async {
    final store = NotificationCenterService.instance;
    await store.ensureInitialized(accountScope: 'shop@example.com');
    expect(store.unreadCount, 0);

    await StockNotificationService.instance.notifyStockLevel(
      itemId: 'item-maize',
      itemName: 'Maize Flour 2kg',
      remaining: 4,
      reorderLevel: 10,
      previousRemaining: 12,
    );
    expect(store.unreadCount, 1);

    await store.recordRemotePush(
      messageId: 'msg-1',
      title: 'Flash Promo',
      body: 'Weekly business report is ready for review.',
      data: const {
        'route': 'analytics',
        'actionLabel': 'View Analytics',
      },
    );
    expect(store.unreadCount, 2);

    await store.markAsRead('stock_low_stock_item-maize');
    expect(store.unreadCount, 1);

    // Persisted unread count stays accurate across reload from SharedPreferences.
    await store.reloadFromStorage();
    expect(store.unreadCount, 1);

    await store.markAllAsRead();
    expect(store.unreadCount, 0);

    await store.reloadFromStorage();
    expect(store.unreadCount, 0);
  });

  test(
      'remote push notifications only include actions when the payload provides them',
      () {
    final plainPush = JengaNotification.fromRemotePush(
      messageId: 'plain-1',
      title: 'Maintenance Notice',
      body: 'Routine sync maintenance tonight at 23:00 EAT.',
      data: const {},
    );
    expect(plainPush.actions, isEmpty);
    expect(plainPush.route, isNull);
    expect(plainPush.isPush, isTrue);

    final actionPush = JengaNotification.fromRemotePush(
      messageId: 'stock-1',
      title: 'Low stock alert',
      body: 'Sugar 1kg has only 3 left.',
      data: {
        'itemId': 'item-sugar',
        'alertType': 'low_stock',
        'actions': jsonEncode([
          {'label': 'Restock product', 'route': 'stock', 'itemId': 'item-sugar'},
          {'label': 'Open guide', 'url': 'https://jengabiz.mftechnologies.org'},
        ]),
      },
    );
    expect(actionPush.actions, hasLength(2));
    expect(actionPush.actions[0].label, 'Restock product');
    expect(actionPush.actions[0].route, 'stock');
    expect(actionPush.actions[0].itemId, 'item-sugar');
    expect(actionPush.actions[1].url, 'https://jengabiz.mftechnologies.org');
  });

  testWidgets(
      'HomeScreen shows no bell count at 0 unread and live badge when unread > 0',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    // Pre-existing half-sold item must NOT create a hardcoded badge count.
    JengaDB.instance.items = [
      StockItem(
        id: 'existing-half',
        name: 'Cooking Oil 1L',
        category: 'Grocery',
        price: 350,
        costPrice: 300,
        stockRemaining: 5,
        unitsSold: 15,
        sku: 'OIL-1',
        imageUrl: '',
        reorderLevel: 10,
      ),
    ];

    await NotificationCenterService.instance.ensureInitialized();
    expect(NotificationCenterService.instance.unreadCount, 0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            go: (_) {},
            unread: NotificationCenterService.instance.unreadCount,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3'), findsNothing);
    expect(find.text('6'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(go: (_) {}, unread: 2),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'clicking a notification expands full details and shows actions, while plain push shows no fake actions',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    JengaDB.instance.items = [
      StockItem(
        id: 'item-bread',
        name: 'Supa Loaf 400g',
        category: 'Food',
        price: 65,
        costPrice: 55,
        stockRemaining: 2,
        unitsSold: 20,
        sku: 'BRD-1',
        imageUrl: '',
        reorderLevel: 5,
      ),
    ];

    final store = NotificationCenterService.instance;
    await store.ensureInitialized();
    await store.recordRemotePush(
      messageId: 'push-with-actions',
      title: 'Stock running low',
      body:
          'Supa Loaf 400g dropped to 2 units left. Reorder immediately to prevent missed morning sales.',
      data: const {
        'itemId': 'item-bread',
        'alertType': 'low_stock',
        'actionLabel': 'Restock product',
        'route': 'stock',
      },
    );
    await store.recordRemotePush(
      messageId: 'push-no-actions',
      title: 'Welcome Update',
      body: 'Thank you for using JengaBiz to manage your daily shop ledger.',
      data: const {},
    );

    NotificationAction? handledAction;

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          onBack: () {},
          onAction: (action) => handledAction = action,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(store.unreadCount, 2);
    // Actions are hidden while cards are collapsed.
    expect(find.text('Restock product'), findsNothing);
    expect(find.text('View in Stock'), findsNothing);

    // Tap the push notification with actions to expand it.
    await tester.tap(find.text('Stock running low'));
    await tester.pumpAndSettle();

    expect(store.unreadCount, 1);
    expect(find.text('Restock product'), findsOneWidget);
    expect(find.text('View in Stock'), findsOneWidget);
    expect(
      find.text('Supa Loaf 400g · 2 left (Alert at 5)'),
      findsOneWidget,
    );

    // Tap View in Stock action button -> triggers navigation callback.
    await tester.tap(find.text('View in Stock'));
    await tester.pumpAndSettle();
    expect(handledAction?.route, 'stock');
    expect(handledAction?.itemId, 'item-bread');

    // Tap the plain push notification without actions -> expands text only.
    await tester.tap(find.text('Welcome Update'));
    await tester.pumpAndSettle();
    expect(store.unreadCount, 0);
    expect(find.text('Open'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'opening a push notification deep-links directly into the expanded notification with its actions',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({'jengabiz_welcome_seen_v1': true});
    final store = NotificationCenterService.instance;
    await store.ensureInitialized(accountScope: 'owner@example.com');
    await store.handleRemoteMessageOpened(
      messageId: 'opened-analytics-push',
      title: 'Weekly Report Ready',
      body: 'Your shop weekly sales report is ready to inspect and export.',
      data: const {
        'route': 'analytics',
        'actionLabel': 'View Analytics',
      },
    );

    // Simulate opening NotificationsScreen as Root does when pendingOpenNotificationId is set.
    final openId = store.pendingOpenNotificationId;
    expect(openId, 'push_opened-analytics-push');
    expect(store.unreadCount, 0);

    NotificationAction? tappedAction;
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          onBack: () {},
          onAction: (action) => tappedAction = action,
          expandNotificationId: openId,
          openRequestSeq: store.openRequestSeq,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Weekly Report Ready'), findsOneWidget);
    expect(
      find.text('Your shop weekly sales report is ready to inspect and export.'),
      findsOneWidget,
    );
    expect(find.text('View Analytics'), findsOneWidget);

    await tester.tap(find.text('View Analytics'));
    await tester.pumpAndSettle();
    expect(tappedAction?.route, 'analytics');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Root prompts for update after login and dismisses cleanly to Home with 0 bell count',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({'jengabiz_welcome_seen_v1': true});
    final fakeApi = JengaApiService.forTestingRequests((method, uri, payload) async {
      if (uri.path.endsWith('/login')) {
        return const JengaApiResponse(200, {
          'success': true,
          'sessionToken': 'session-tok-1',
          'user': {
            'id': 'usr_update_qa',
            'name': 'QA Shopkeeper',
            'shopName': 'QA Duka',
            'email': 'updateqa@example.com',
            'phone': '',
          },
        });
      }
      if (uri.path.endsWith('/stock/items')) {
        return const JengaApiResponse(200, {'success': true, 'items': []});
      }
      return const JengaApiResponse(200, {'success': true});
    });
    fakeApi.configure(url: 'https://jengabiz.mftechnologies.org');

    final fakeRelease = JengaBizRelease(
      versionName: '1.1.11',
      versionCode: 22,
      apkUrl: Uri.parse(
        'https://jengabiz.mftechnologies.org/downloads/v1.1.11/JengaBiz-1.1.11.apk',
      ),
      sha256: 'a' * 64,
      releaseNotes: const ['Post-login update prompt check.'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Root(
          apiService: fakeApi,
          updateLoader: () async => fakeRelease,
        ),
      ),
    );

    for (var i = 0; i < 15 && find.text('Sign In').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }

    expect(find.text('Update JengaBiz'), findsNothing);

    await tester.tap(find.text('Sign In').first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'updateqa@example.com',
    );
    await tester.enterText(
      find.byType(TextField).at(1),
      'password123',
    );
    await tester.ensureVisible(find.text('Sign In').last);
    await tester.tap(find.text('Sign In').last);

    for (var i = 0;
        i < 80 && find.text('Update JengaBiz').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }

    expect(find.text('Update JengaBiz'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);

    await tester.ensureVisible(find.text('Not now'));
    await tester.tap(find.text('Not now'));
    for (var i = 0;
        i < 15 && find.text('Total Revenue').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }

    expect(find.text('Total Revenue'), findsOneWidget);
    expect(find.text('3'), findsNothing);
    expect(find.text('6'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
