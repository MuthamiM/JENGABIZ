import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'api_service.dart';
import 'app_update_service.dart';
import 'notification_center_service.dart';
import 'stock_notification_service.dart';

({String? title, String? body}) _extractRemoteTitleAndBody(
  RemoteMessage message,
) {
  final notification = message.notification;
  final rawTitle = notification?.title ?? message.data['title']?.toString();
  final rawBody = notification?.body ?? message.data['body']?.toString();
  final title = rawTitle?.trim();
  final body = rawBody?.trim();
  if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
    return (title: null, body: null);
  }
  return (
    title: (title == null || title.isEmpty) ? 'JengaBiz' : title,
    body: body ?? '',
  );
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    final extracted = _extractRemoteTitleAndBody(message);
    if (extracted.title == null && extracted.body == null) return;
    await NotificationCenterService.persistBackgroundPush(
      messageId: message.messageId,
      title: extracted.title ?? 'JengaBiz',
      body: extracted.body ?? '',
      data: message.data,
      sentTime: message.sentTime,
    );
  } catch (_) {
    return;
  }
}

class FirebasePushService {
  FirebasePushService._();

  static final FirebasePushService instance = FirebasePushService._();
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;
  StreamSubscription<String>? _tokenSubscription;
  bool _initialized = false;
  bool _backgroundHandlerRegistered = false;
  bool _initialMessageChecked = false;
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
      await StockNotificationService.instance.initialize();
      if (!await _ensureFirebaseInitialized()) return false;
      await prepareBackgroundHandling();
      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);

      _foregroundSubscription ??=
          FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      _openedAppSubscription ??=
          FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);
      _tokenSubscription ??= messaging.onTokenRefresh.listen((token) {
        unawaited(_registerToken(token));
      });

      _initialized = true;
      await checkInitialMessage();
      await registerCurrentAccount();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Checks whether the app was cold-launched by tapping an FCM notification.
  Future<void> checkInitialMessage() async {
    if (_initialMessageChecked) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _initialMessageChecked = true;
    try {
      if (!await _ensureFirebaseInitialized()) return;
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        await _handleOpenedMessage(initialMessage);
      }
    } catch (_) {}
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final extracted = _extractRemoteTitleAndBody(message);
    if (extracted.title == null && extracted.body == null) return;
    if (await _isStaleUpdatePush(message.data)) return;
    final recorded = await NotificationCenterService.instance.recordRemotePush(
      messageId: message.messageId,
      title: extracted.title ?? 'JengaBiz',
      body: extracted.body ?? '',
      data: message.data,
      sentTime: message.sentTime,
    );
    unawaited(StockNotificationService.instance.showRemoteNotification(
      notificationId: recorded.id.hashCode & 0x7fffffff,
      title: recorded.title,
      body: recorded.body,
      payload: recorded.id,
    ));
  }

  Future<bool> _isStaleUpdatePush(Map<String, dynamic> data) async {
    final route = data['route']?.toString().trim();
    final type = data['type']?.toString().trim();
    if (route != 'update' && type != 'update') return false;
    final rawTargetCode = int.tryParse(data['versionCode']?.toString() ?? '');
    if (rawTargetCode == null || rawTargetCode <= 0) return false;
    try {
      final info = await AppUpdateService.instance.installedAppInfo();
      final installed = info['versionCode'];
      final currentCode = installed is int
          ? installed
          : int.tryParse(installed?.toString() ?? '');
      if (currentCode != null && currentCode >= rawTargetCode) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _handleOpenedMessage(RemoteMessage message) async {
    final extracted = _extractRemoteTitleAndBody(message);
    if (extracted.title == null && extracted.body == null) {
      // Fallback: if messageId matches a stored background push, still open it.
      final id = message.messageId?.trim();
      if (id != null && id.isNotEmpty) {
        await NotificationCenterService.instance
            .requestOpenNotification('push_$id');
      }
      return;
    }
    await NotificationCenterService.instance.handleRemoteMessageOpened(
      messageId: message.messageId,
      title: extracted.title ?? 'JengaBiz',
      body: extracted.body ?? '',
      data: message.data,
      sentTime: message.sentTime,
    );
  }

  Future<bool> requestPermission() async {
    try {
      if (!await initialize()) {
        return await StockNotificationService.instance.requestPermission();
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
      return await StockNotificationService.instance.requestPermission();
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
    int? appVersionCode;
    try {
      final info = await AppUpdateService.instance.installedAppInfo();
      final rawCode = info['versionCode'];
      appVersionCode =
          rawCode is int ? rawCode : int.tryParse(rawCode?.toString() ?? '');
    } catch (_) {}
    final platform = Platform.isIOS ? 'ios' : 'android';
    await JengaApiService.instance.registerNotificationDevice(
      deviceToken: token,
      platform: platform,
      appVersionCode: appVersionCode,
    );
  }
}
