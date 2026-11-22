import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'api_service.dart';
import 'stock_notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (_) {
    return;
  }
}

class FirebasePushService {
  FirebasePushService._();

  static final FirebasePushService instance = FirebasePushService._();
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<String>? _tokenSubscription;
  bool _initialized = false;
  bool _backgroundHandlerRegistered = false;
  Future<bool>? _firebaseReady;
  String? _deviceToken;

  String? get currentToken => _deviceToken;

  Future<void> prepareBackgroundHandling() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (!await _ensureFirebaseInitialized() || _backgroundHandlerRegistered) {
      return;
    }
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _backgroundHandlerRegistered = true;
  }

  Future<bool> initialize() async {
    if (_initialized) return true;
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    try {
      if (!await _ensureFirebaseInitialized()) return false;
      await prepareBackgroundHandling();
      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);
      _foregroundSubscription ??= FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        final title = notification?.title ?? message.data['title']?.toString();
        final body = notification?.body ?? message.data['body']?.toString();
        if (title == null || body == null) return;
        unawaited(StockNotificationService.instance.showRemoteNotification(
          notificationId: (message.messageId ?? title).hashCode & 0x7fffffff,
          title: title,
          body: body,
          payload: message.data['itemId']?.toString(),
        ));
      });
      _tokenSubscription ??= messaging.onTokenRefresh.listen((token) {
        unawaited(_registerToken(token));
      });
      _initialized = true;
      await registerCurrentAccount();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPermission() async {
    try {
      if (!await initialize()) {
        return StockNotificationService.instance.requestPermission();
      }
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final allowed =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      if (allowed) await registerCurrentAccount();
      return allowed;
    } catch (_) {
      return StockNotificationService.instance.requestPermission();
    }
  }

  Future<void> registerCurrentAccount() async {
    if (!_initialized || JengaApiService.instance.authToken == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(token);
    } catch (_) {}
  }

  Future<void> removeCurrentDevice() async {
    if (!_initialized || JengaApiService.instance.authToken == null) return;
    try {
      final token = _deviceToken ?? await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await JengaApiService.instance.removeNotificationDevice(token);
      }
    } catch (_) {}
  }

  Future<bool> _ensureFirebaseInitialized() =>
      _firebaseReady ??= _initializeFirebase();

  Future<bool> _initializeFirebase() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _registerToken(String token) async {
    _deviceToken = token;
    if (JengaApiService.instance.authToken == null) return;
    final preferences = await SharedPreferences.getInstance();
    if (!(preferences.getBool(StockNotificationService.preferenceKey) ??
        true)) {
      return;
    }
    final platform = Platform.isIOS ? 'ios' : 'android';
    await JengaApiService.instance.registerNotificationDevice(
      deviceToken: token,
      platform: platform,
    );
  }
}
