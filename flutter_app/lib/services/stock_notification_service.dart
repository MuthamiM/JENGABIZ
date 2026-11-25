import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_center_service.dart';

/// Displays OS heads-up notifications for stock alerts and foreground pushes,
/// records them in [NotificationCenterService], and routes notification taps
/// to the expanded notification screen.
class StockNotificationService {
  StockNotificationService._();

  static final StockNotificationService instance = StockNotificationService._();
  static const preferenceKey = 'jengabiz_pref_push_notifications';
  static const _channelId = 'jengabiz_stock_alerts';
  static const _channelName = 'Stock alerts';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _launchDetailsChecked = false;

  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      if (!_initialized) {
        const settings = InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        );
        await _notifications.initialize(
          settings,
          onDidReceiveNotificationResponse: _handleNotificationResponse,
        );
        await _notifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: 'Alerts when a product needs restocking.',
              importance: Importance.high,
            ));
        _initialized = true;
      }

      if (!_launchDetailsChecked) {
        _launchDetailsChecked = true;
        final launchDetails =
            await _notifications.getNotificationAppLaunchDetails();
        final payload = launchDetails?.notificationResponse?.payload;
        if (launchDetails?.didNotificationLaunchApp == true &&
            payload != null &&
            payload.trim().isNotEmpty) {
          unawaited(
            NotificationCenterService.instance.requestOpenNotification(payload),
          );
        }
      }
    } catch (_) {}
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload?.trim();
    if (payload == null || payload.isEmpty) return;
    unawaited(
      NotificationCenterService.instance.requestOpenNotification(payload),
    );
  }

  Future<void> showRemoteNotification({
    required int notificationId,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!(preferences.getBool(preferenceKey) ?? true)) return;
      await initialize();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Alerts when a product needs restocking.',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      );
      await _notifications.show(notificationId, title, body, details,
          payload: payload);
    } catch (_) {
      // A notification failure must not interrupt message handling.
    }
  }

  Future<bool> requestPermission() async {
    await initialize();
    final android = await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    final ios = await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    return android ?? ios ?? true;
  }

  Future<void> notifyStockLevel({
    required String itemId,
    required String itemName,
    required int remaining,
    required int reorderLevel,
    int? previousRemaining,
  }) async {
    if (previousRemaining != null &&
        ((remaining <= 0 && previousRemaining <= 0) ||
            (remaining > 0 && previousRemaining <= reorderLevel))) {
      return;
    }
    if (remaining > reorderLevel && remaining > 0) return;

    final outOfStock = remaining <= 0;
    final title = outOfStock ? 'Out of stock' : 'Low stock alert';
    final body = outOfStock
        ? '$itemName has run out. Restock it now.'
        : '$itemName has only $remaining left (alert level: $reorderLevel).';

    final recorded = await NotificationCenterService.instance.recordStockAlert(
      alertKind: outOfStock ? 'out_of_stock' : 'low_stock',
      itemId: itemId,
      title: title,
      body: body,
    );

    try {
      final preferences = await SharedPreferences.getInstance();
      if (!(preferences.getBool(preferenceKey) ?? true)) return;
      await initialize();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Alerts when a product needs restocking.',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      );
      final id = itemId.hashCode & 0x7fffffff;
      await _notifications.show(
        id,
        title,
        body,
        details,
        payload: recorded.id,
      );
    } catch (_) {
      // Notification platform failures must not undo a saved stock change.
    }
  }

  Future<void> notifyHalfSold({
    required String itemId,
    required String itemName,
    required int previousRemaining,
    required int previousUnitsSold,
    required int remaining,
    required int unitsSold,
  }) async {
    if (remaining <= 0 ||
        unitsSold <= 0 ||
        unitsSold < remaining ||
        previousUnitsSold >= previousRemaining) {
      return;
    }

    const title = 'Stock update';
    final body = '$itemName is at least 50% sold. $remaining units remain.';
    final recorded = await NotificationCenterService.instance.recordStockAlert(
      alertKind: 'half_sold',
      itemId: itemId,
      title: title,
      body: body,
    );

    try {
      final preferences = await SharedPreferences.getInstance();
      if (!(preferences.getBool(preferenceKey) ?? true)) return;
      await initialize();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Alerts when a product needs restocking.',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      );
      await _notifications.show(
        (itemId.hashCode ^ 0x40000000) & 0x7fffffff,
        title,
        body,
        details,
        payload: recorded.id,
      );
    } catch (_) {
      // Notification failures must not interrupt a saved sale.
    }
  }
}
