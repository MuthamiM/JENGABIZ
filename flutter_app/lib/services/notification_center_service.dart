import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Categories of notifications shown in JengaBiz.
enum NotificationType {
  stock,
  sales,
  referral,
  security,
  location,
  sync,
  push,
  update,
}

/// An actionable button attached to a notification card.
class NotificationAction {
  const NotificationAction({
    required this.label,
    required this.iconKey,
    this.route,
    this.itemId,
    this.stockFilter,
    this.url,
  });

  final String label;
  final String iconKey;
  final String? route;
  final String? itemId;
  final String? stockFilter;
  final String? url;

  Map<String, dynamic> toJson() => {
        'label': label,
        'iconKey': iconKey,
        if (route != null) 'route': route,
        if (itemId != null) 'itemId': itemId,
        if (stockFilter != null) 'stockFilter': stockFilter,
        if (url != null) 'url': url,
      };

  factory NotificationAction.fromJson(Map<String, dynamic> json) {
    return NotificationAction(
      label: json['label']?.toString() ?? 'Open',
      iconKey: json['iconKey']?.toString() ?? 'open',
      route: json['route']?.toString(),
      itemId: json['itemId']?.toString(),
      stockFilter: json['stockFilter']?.toString(),
      url: json['url']?.toString(),
    );
  }
}

/// A persisted in-app or push notification with optional inline actions.
class JengaNotification {
  JengaNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.type,
    this.isRead = false,
    this.isPush = false,
    this.route,
    this.itemId,
    this.actions = const [],
    this.payload = const {},
  });

  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  final NotificationType type;
  bool isRead;
  final bool isPush;
  final String? route;
  final String? itemId;
  final List<NotificationAction> actions;
  final Map<String, String> payload;

  static const _allowedRoutes = {
    'stock',
    'analytics',
    'profile',
    'update',
    'home',
  };

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'timestamp': timestamp.toIso8601String(),
        'type': type.name,
        'isRead': isRead,
        'isPush': isPush,
        if (route != null) 'route': route,
        if (itemId != null) 'itemId': itemId,
        'actions': actions.map((a) => a.toJson()).toList(),
        'payload': payload,
      };

  factory JengaNotification.fromJson(Map<String, dynamic> json) {
    final typeName = json['type']?.toString() ?? 'push';
    final parsedType = NotificationType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => NotificationType.push,
    );
    final rawActions = json['actions'];
    final actions = rawActions is List
        ? rawActions
            .whereType<Map>()
            .map((e) => NotificationAction.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <NotificationAction>[];
    final rawPayload = json['payload'];
    final payload = rawPayload is Map
        ? rawPayload.map((k, v) => MapEntry(k.toString(), v.toString()))
        : const <String, String>{};
    return JengaNotification(
      id: json['id']?.toString() ?? 'notif_${DateTime.now().millisecondsSinceEpoch}',
      title: json['title']?.toString() ?? 'Notification',
      body: json['body']?.toString() ?? '',
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      type: parsedType,
      isRead: json['isRead'] == true,
      isPush: json['isPush'] == true,
      route: json['route']?.toString(),
      itemId: json['itemId']?.toString(),
      actions: actions,
      payload: payload,
    );
  }

  /// Creates a notification from an incoming FCM push payload.
  /// Only attaches actions when the payload explicitly carries actions or a
  /// supported deep-link target (`itemId`, `route`, or valid `https` `url`).
  factory JengaNotification.fromRemotePush({
    String? messageId,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
    DateTime? sentTime,
    bool isRead = false,
  }) {
    final payload = <String, String>{
      for (final entry in data.entries)
        if (entry.value != null) entry.key: entry.value.toString(),
    };
    final explicitId = payload['notificationId']?.trim();
    final rawMsgId = messageId?.trim();
    final id = (explicitId != null && explicitId.isNotEmpty)
        ? explicitId
        : (rawMsgId != null && rawMsgId.isNotEmpty)
            ? 'push_$rawMsgId'
            : 'push_${title.hashCode}_${body.hashCode}_${payload['itemId'] ?? ''}_${payload['stockRemaining'] ?? ''}_${sentTime?.millisecondsSinceEpoch ?? 0}';

    final itemId = _nonEmpty(payload['itemId']);
    final rawRoute = _nonEmpty(payload['route']) ?? _nonEmpty(payload['screen']);
    final route = rawRoute != null && _allowedRoutes.contains(rawRoute)
        ? rawRoute
        : (itemId != null ? 'stock' : null);

    final type = _typeFromPushPayload(payload, itemId: itemId, route: route);
    final actions = _actionsFromPushPayload(
      payload,
      itemId: itemId,
      route: route,
    );

    return JengaNotification(
      id: id,
      title: title.trim().isEmpty ? 'JengaBiz Update' : title.trim(),
      body: body.trim(),
      timestamp: sentTime ?? DateTime.now(),
      type: type,
      isRead: isRead,
      isPush: true,
      route: route,
      itemId: itemId,
      actions: actions,
      payload: payload,
    );
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static NotificationType _typeFromPushPayload(
    Map<String, String> payload, {
    String? itemId,
    String? route,
  }) {
    final raw = (payload['type'] ?? payload['alertType'] ?? payload['category'] ?? '')
        .trim()
        .toLowerCase();
    if (raw == 'stock' ||
        raw == 'low_stock' ||
        raw == 'out_of_stock' ||
        raw == 'half_sold' ||
        itemId != null ||
        route == 'stock') {
      return NotificationType.stock;
    }
    if (raw == 'sales' || route == 'analytics') return NotificationType.sales;
    if (raw == 'referral') return NotificationType.referral;
    if (raw == 'security') return NotificationType.security;
    if (raw == 'location') return NotificationType.location;
    if (raw == 'sync') return NotificationType.sync;
    if (raw == 'update' || route == 'update') return NotificationType.update;
    return NotificationType.push;
  }

  static List<NotificationAction> _actionsFromPushPayload(
    Map<String, String> payload, {
    String? itemId,
    String? route,
  }) {
    final actions = <NotificationAction>[];

    // 1. Optional JSON-encoded multi-action list in payload['actions'].
    final rawActions = _nonEmpty(payload['actions']);
    if (rawActions != null) {
      try {
        final decoded = jsonDecode(rawActions);
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is! Map) continue;
            final label = _nonEmpty(entry['label']?.toString());
            if (label == null) continue;
            final aRoute = _nonEmpty(entry['route']?.toString());
            final validRoute =
                aRoute != null && _allowedRoutes.contains(aRoute) ? aRoute : null;
            final aItemId = _nonEmpty(entry['itemId']?.toString());
            final aFilter = _nonEmpty(entry['stockFilter']?.toString());
            final aUrl = _safeHttpsUrl(entry['url']?.toString());
            if (validRoute == null && aItemId == null && aUrl == null) {
              continue;
            }
            actions.add(NotificationAction(
              label: label,
              iconKey: _iconKeyFor(
                route: validRoute ?? (aItemId != null ? 'stock' : null),
                url: aUrl,
              ),
              route: validRoute ?? (aItemId != null ? 'stock' : null),
              itemId: aItemId,
              stockFilter: aFilter,
              url: aUrl,
            ));
          }
        }
      } catch (_) {
        // Ignore malformed custom actions JSON and fall back to simple fields.
      }
    }

    if (actions.isNotEmpty) return actions;

    // 2. Single item / stock push target.
    final customLabel = _nonEmpty(payload['actionLabel']);
    if (itemId != null) {
      final alertType = (payload['alertType'] ?? '').toLowerCase();
      final stockFilter = alertType == 'out_of_stock'
          ? 'Out of Stock'
          : alertType == 'low_stock'
              ? 'Low Stock'
              : alertType == 'half_sold'
                  ? 'Half Sold (50%+)'
                  : null;
      actions.add(NotificationAction(
        label: customLabel ??
            (alertType == 'out_of_stock' || alertType == 'low_stock'
                ? 'Restock product'
                : 'View in Stock'),
        iconKey: 'restock',
        route: 'stock',
        itemId: itemId,
        stockFilter: stockFilter,
      ));
      return actions;
    }

    // 3. Safe external HTTPS link target.
    final url = _safeHttpsUrl(
      payload['actionUrl'] ?? payload['url'] ?? payload['link'],
    );
    if (url != null) {
      actions.add(NotificationAction(
        label: customLabel ?? 'Open link',
        iconKey: 'link',
        url: url,
      ));
      return actions;
    }

    // 4. In-app screen route target.
    if (route != null) {
      actions.add(NotificationAction(
        label: customLabel ?? _defaultRouteLabel(route),
        iconKey: _iconKeyFor(route: route),
        route: route,
        stockFilter: _nonEmpty(payload['stockFilter']),
      ));
    }

    return actions;
  }

  static String? _safeHttpsUrl(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.toLowerCase() != 'https' || !uri.hasAuthority) {
      return null;
    }
    return uri.toString();
  }

  static String _defaultRouteLabel(String route) {
    switch (route) {
      case 'stock':
        return 'Open Stock';
      case 'analytics':
        return 'View Analytics';
      case 'profile':
        return 'Open Profile';
      case 'update':
        return 'Check Update';
      default:
        return 'Open';
    }
  }

  static String _iconKeyFor({String? route, String? url}) {
    if (url != null) return 'link';
    switch (route) {
      case 'stock':
        return 'stock';
      case 'analytics':
        return 'analytics';
      case 'profile':
        return 'profile';
      case 'update':
        return 'update';
      default:
        return 'open';
    }
  }
}

/// Central, account-scoped store for both push and local notifications.
/// Drives the notification bell badge count and notification tap deep-links
/// with zero hardcoded counts.
class NotificationCenterService extends ChangeNotifier {
  NotificationCenterService._();

  static final NotificationCenterService instance = NotificationCenterService._();

  static const _activeScopeKey = 'jengabiz_active_notification_scope_v2';
  static const _storePrefix = 'jengabiz_notifications_v2_';
  static const _pendingPushKey = 'jengabiz_notifications_v2_pending_push';
  static const _maxStored = 80;

  final List<JengaNotification> _notifications = [];
  String _scope = 'guest';
  bool _initialized = false;
  String? _pendingOpenNotificationId;
  int _openRequestSeq = 0;

  List<JengaNotification> get notifications =>
      List<JengaNotification>.unmodifiable(_notifications);

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  String? get pendingOpenNotificationId => _pendingOpenNotificationId;

  int get openRequestSeq => _openRequestSeq;

  String get currentScope => _scope;

  static String normalizeScope(String? rawScope) {
    final cleaned = (rawScope ?? '').trim().toLowerCase();
    if (cleaned.isEmpty) return 'guest';
    return cleaned.replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
  }

  String _storageKeyForScope(String scope) => '$_storePrefix$scope';

  Future<void> ensureInitialized({String? accountScope}) async {
    if (accountScope != null) {
      await setAccountScope(accountScope);
      return;
    }
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedScope = prefs.getString(_activeScopeKey);
      if (savedScope != null && savedScope.isNotEmpty) {
        _scope = savedScope;
      }
      await _loadCurrentScopeLocked(prefs);
      _initialized = true;
      notifyListeners();
    } catch (_) {
      _initialized = true;
    }
  }

  /// Switches storage scope to the signed-in account (or `'guest'` on logout)
  /// and absorbs any background pushes stored while the app wasn't in foreground.
  Future<void> setAccountScope(String? rawScope) async {
    final nextScope = normalizeScope(rawScope);
    final changed = nextScope != _scope || !_initialized;
    _scope = nextScope;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activeScopeKey, _scope);
      if (changed) {
        await _loadCurrentScopeLocked(prefs);
        _initialized = true;
        notifyListeners();
      } else {
        final merged = await _drainPendingPushes(prefs);
        if (merged) {
          await _persistCurrentScope(prefs);
          notifyListeners();
        }
      }
    } catch (_) {
      _initialized = true;
      if (changed) {
        _notifications.clear();
        notifyListeners();
      }
    }
  }

  /// Reloads notifications from storage (for example on app resume after a
  /// background FCM isolate wrote a new push notification).
  Future<void> reloadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      await _loadCurrentScopeLocked(prefs);
      _initialized = true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadCurrentScopeLocked(SharedPreferences prefs) async {
    final raw = prefs.getStringList(_storageKeyForScope(_scope)) ?? const [];
    final loaded = _decodeList(raw);
    _notifications
      ..clear()
      ..addAll(loaded);
    final drained = await _drainPendingPushes(prefs);
    if (drained) {
      await _persistCurrentScope(prefs);
    }
  }

  List<JengaNotification> _decodeList(List<String> raw) {
    final list = <JengaNotification>[];
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map) {
          list.add(JengaNotification.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (_) {}
    }
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  Future<bool> _drainPendingPushes(SharedPreferences prefs) async {
    final pendingRaw = prefs.getStringList(_pendingPushKey);
    if (pendingRaw == null || pendingRaw.isEmpty) return false;
    final pending = _decodeList(pendingRaw);
    for (final notif in pending.reversed) {
      _upsertInMemory(notif, preserveReadIfExists: true);
    }
    await prefs.remove(_pendingPushKey);
    return true;
  }

  void _upsertInMemory(
    JengaNotification notification, {
    bool preserveReadIfExists = false,
  }) {
    final existingIdx = _notifications.indexWhere((n) => n.id == notification.id);
    if (existingIdx >= 0) {
      final existing = _notifications[existingIdx];
      if (preserveReadIfExists && existing.isRead && !notification.isRead) {
        notification.isRead = true;
      }
      _notifications.removeAt(existingIdx);
    }
    _notifications.insert(0, notification);
    if (_notifications.length > _maxStored) {
      _notifications.removeRange(_maxStored, _notifications.length);
    }
  }

  Future<void> _persistCurrentScope(SharedPreferences prefs) async {
    await prefs.setStringList(
      _storageKeyForScope(_scope),
      _notifications.map((n) => jsonEncode(n.toJson())).toList(),
    );
  }

  /// Persists a push notification from a background FCM isolate without
  /// assuming the foreground isolate's in-memory state is present.
  static Future<void> persistBackgroundPush({
    String? messageId,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
    DateTime? sentTime,
  }) async {
    final notification = JengaNotification.fromRemotePush(
      messageId: messageId,
      title: title,
      body: body,
      data: data,
      sentTime: sentTime,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final pending = prefs.getStringList(_pendingPushKey) ?? const <String>[];
      final decoded = <JengaNotification>[];
      for (final raw in pending) {
        try {
          final map = jsonDecode(raw);
          if (map is Map) {
            decoded.add(JengaNotification.fromJson(Map<String, dynamic>.from(map)));
          }
        } catch (_) {}
      }
      decoded.removeWhere((n) => n.id == notification.id);
      decoded.insert(0, notification);
      if (decoded.length > _maxStored) {
        decoded.removeRange(_maxStored, decoded.length);
      }
      await prefs.setStringList(
        _pendingPushKey,
        decoded.map((n) => jsonEncode(n.toJson())).toList(),
      );
    } catch (_) {}
  }

  /// Records a foreground remote FCM push notification.
  Future<JengaNotification> recordRemotePush({
    String? messageId,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
    DateTime? sentTime,
    bool markRead = false,
  }) async {
    await ensureInitialized();
    final notif = JengaNotification.fromRemotePush(
      messageId: messageId,
      title: title,
      body: body,
      data: data,
      sentTime: sentTime,
      isRead: markRead,
    );
    _upsertInMemory(notif, preserveReadIfExists: !markRead);
    try {
      final prefs = await SharedPreferences.getInstance();
      await _persistCurrentScope(prefs);
    } catch (_) {}
    notifyListeners();
    return notif;
  }

  /// Records a genuine stock alert notification when an item crosses an alert
  /// threshold locally.
  Future<JengaNotification> recordStockAlert({
    required String alertKind, // 'out_of_stock', 'low_stock', 'half_sold'
    required String itemId,
    required String title,
    required String body,
  }) async {
    await ensureInitialized();
    final id = 'stock_${alertKind}_$itemId';
    final stockFilter = alertKind == 'out_of_stock'
        ? 'Out of Stock'
        : alertKind == 'low_stock'
            ? 'Low Stock'
            : 'Half Sold (50%+)';
    final notif = JengaNotification(
      id: id,
      title: title,
      body: body,
      timestamp: DateTime.now(),
      type: NotificationType.stock,
      isRead: false,
      isPush: false,
      route: 'stock',
      itemId: itemId,
      actions: [
        NotificationAction(
          label: alertKind == 'half_sold' ? 'View in Stock' : 'Restock product',
          iconKey: 'restock',
          route: 'stock',
          itemId: itemId,
          stockFilter: stockFilter,
        ),
      ],
      payload: {
        'itemId': itemId,
        'alertType': alertKind,
        'route': 'stock',
      },
    );
    _upsertInMemory(notif, preserveReadIfExists: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await _persistCurrentScope(prefs);
    } catch (_) {}
    notifyListeners();
    return notif;
  }

  /// Called when the user taps an FCM push notification (background/terminated)
  /// so the app opens directly onto that expanded notification and its actions.
  Future<JengaNotification> handleRemoteMessageOpened({
    String? messageId,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
    DateTime? sentTime,
  }) async {
    await ensureInitialized();
    await reloadFromStorage();
    final notif = JengaNotification.fromRemotePush(
      messageId: messageId,
      title: title,
      body: body,
      data: data,
      sentTime: sentTime,
      isRead: true,
    );
    _upsertInMemory(notif, preserveReadIfExists: false);
    _pendingOpenNotificationId = notif.id;
    _openRequestSeq++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await _persistCurrentScope(prefs);
    } catch (_) {}
    notifyListeners();
    return notif;
  }

  /// Requests the UI to navigate to the notifications screen and expand the
  /// notification identified by [notificationId] (for local or heads-up taps).
  Future<void> requestOpenNotification(String notificationId) async {
    final trimmed = notificationId.trim();
    if (trimmed.isEmpty) return;
    await ensureInitialized();
    await reloadFromStorage();
    final idx = _notifications.indexWhere((n) => n.id == trimmed);
    if (idx >= 0) {
      _notifications[idx].isRead = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        await _persistCurrentScope(prefs);
      } catch (_) {}
    }
    _pendingOpenNotificationId = trimmed;
    _openRequestSeq++;
    notifyListeners();
  }

  void clearPendingOpenNotification() {
    _pendingOpenNotificationId = null;
  }

  Future<void> markAsRead(String id) async {
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx < 0 || _notifications[idx].isRead) return;
    _notifications[idx].isRead = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await _persistCurrentScope(prefs);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> markAllAsRead() async {
    final hadUnread = _notifications.any((n) => !n.isRead);
    if (!hadUnread) return;
    for (final n in _notifications) {
      n.isRead = true;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await _persistCurrentScope(prefs);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> removeNotification(String id) async {
    final before = _notifications.length;
    _notifications.removeWhere((n) => n.id == id);
    if (_notifications.length == before) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await _persistCurrentScope(prefs);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> clearAll() async {
    if (_notifications.isEmpty) return;
    _notifications.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await _persistCurrentScope(prefs);
    } catch (_) {}
    notifyListeners();
  }

  @visibleForTesting
  void resetForTesting() {
    _notifications.clear();
    _scope = 'guest';
    _initialized = false;
    _pendingOpenNotificationId = null;
    _openRequestSeq = 0;
  }
}
