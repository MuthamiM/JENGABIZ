import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException, rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'cache_service.dart';
import 'password_hasher.dart';

class JengaUser {
  final String id;
  final String name;
  final String shopName;
  final String phone;
  final String email;
  final String createdAt;
  final String? passwordSalt;
  final String? passwordHash;

  JengaUser({
    required this.id,
    required this.name,
    required this.shopName,
    required this.phone,
    required this.email,
    required this.createdAt,
    this.passwordSalt,
    this.passwordHash,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'shopName': shopName,
        'phone': phone,
        'email': email,
        'createdAt': createdAt,
        if (passwordSalt != null) 'passwordSalt': passwordSalt,
        if (passwordHash != null) 'passwordHash': passwordHash,
      };

  factory JengaUser.fromJson(Map<String, dynamic> json) => JengaUser(
        id: json['id'] as String? ?? 'usr_1',
        name: json['name'] as String? ?? 'Shop Owner',
        shopName: json['shopName'] as String? ?? 'My Duka',
        phone: json['phone'] as String? ?? '+254 700 000 000',
        email: json['email'] as String? ?? 'owner@jengabiz.com',
        createdAt:
            json['createdAt'] as String? ?? DateTime.now().toIso8601String(),
        passwordSalt: json['passwordSalt'] as String?,
        passwordHash: json['passwordHash'] as String?,
      );
}

class StockItem {
  final String id;
  String name;
  String category;
  double price;
  double costPrice;
  int stockRemaining;
  int unitsSold;
  String sku;
  String imageUrl;
  int reorderLevel;

  StockItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.costPrice,
    required this.stockRemaining,
    required this.unitsSold,
    required this.sku,
    required this.imageUrl,
    this.reorderLevel = 10,
  });

  bool get isOutOfStock => stockRemaining <= 0;
  bool get isLowStock => stockRemaining > 0 && stockRemaining <= reorderLevel;
  int get totalStock => stockRemaining + unitsSold;
  double get soldRatio => totalStock > 0 ? (unitsSold / totalStock) : 0.0;
  bool get isHalfSold => totalStock > 0 && unitsSold >= stockRemaining;
  int get soldPercentage => (soldRatio * 100).round();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'price': price,
        'costPrice': costPrice,
        'stockRemaining': stockRemaining,
        'unitsSold': unitsSold,
        'sku': sku,
        'imageUrl': imageUrl,
        'reorderLevel': reorderLevel,
      };

  factory StockItem.fromJson(Map<String, dynamic> json) => StockItem(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Item',
        category: json['category'] as String? ?? 'General',
        price: (json['price'] as num?)?.toDouble() ?? 0.0,
        costPrice: (json['costPrice'] as num?)?.toDouble() ?? 0.0,
        stockRemaining: (json['stockRemaining'] as num?)?.toInt() ?? 0,
        unitsSold: (json['unitsSold'] as num?)?.toInt() ?? 0,
        sku: json['sku'] as String? ?? '',
        imageUrl: json['imageUrl'] as String? ?? '',
        reorderLevel: (json['reorderLevel'] as num?)?.toInt() ?? 10,
      );
}

class JengaDB {
  static final JengaDB instance = JengaDB._();
  static const MethodChannel _stockWidgetChannel =
      MethodChannel('com.dukaledger.duka_ledger/widget');
  JengaDB._();

  List<StockItem> items = [];
  List<JengaUser> users = [];
  JengaUser? currentUser;
  String? inventoryOwnerId;
  bool isInitialized = false;
  String nearestHubName = 'Industrial Area Logistics Point';
  double nearestHubDistanceKm = 4.2;
  double? latitude;
  double? longitude;

  Future<void> init() async {
    if (isInitialized) return;

    try {
      await JengaApiService.instance.restoreSession();
      await JengaCacheService.instance.init();
      final prefs = await SharedPreferences.getInstance();

      // 1. Load users
      final usersJson = prefs.getString('jengabiz_users');
      if (usersJson != null) {
        final List list = jsonDecode(usersJson);
        users = list.map((e) => JengaUser.fromJson(e)).toList();
      }

      if (users.isNotEmpty) {
        // Check logged in user
        final currentUserId = prefs.getString('current_user_id');
        if (currentUserId != null) {
          final match = users.where((u) => u.id == currentUserId);
          if (match.isNotEmpty) {
            currentUser = match.first;
          } else {
            currentUser = users.first;
          }
        } else {
          currentUser = users.first;
        }
      }

      // 2. Load Stock Items (from Cache first, then file / seed)
      final cached = await JengaCacheService.instance.get<List>('items:all');
      if (cached != null) {
        items = cached
            .map((e) => StockItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/jengabiz_inventory.json');

        if (await file.exists()) {
          final content = await file.readAsString();
          final List list = jsonDecode(content);
          items = list.map((e) => StockItem.fromJson(e)).toList();
        } else {
          final assetJson = await rootBundle.loadString('assets/items_db.json');
          final List list = jsonDecode(assetJson);
          items = list.map((e) => StockItem.fromJson(e)).toList();
          await file
              .writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()));
        }

        // Cache loaded items into L1/L2 Redis
        await JengaCacheService.instance
            .set('items:all', items.map((e) => e.toJson()).toList());
      }

      inventoryOwnerId =
          prefs.getString('jengabiz_inventory_owner_id') ?? currentUser?.id;
      if (inventoryOwnerId != null) {
        await _saveInventorySnapshot(inventoryOwnerId!, items);
      }
      if (currentUser != null && inventoryOwnerId != currentUser!.id) {
        final savedItems = await _readInventorySnapshot(currentUser!.id);
        items = savedItems ?? <StockItem>[];
        inventoryOwnerId = currentUser!.id;
        await _persistItemsLocally();
      } else if (currentUser != null) {
        inventoryOwnerId = currentUser!.id;
        await prefs.setString('jengabiz_inventory_owner_id', currentUser!.id);
      }
    } catch (e) {
      try {
        final assetJson = await rootBundle.loadString('assets/items_db.json');
        final List list = jsonDecode(assetJson);
        items = list.map((e) => StockItem.fromJson(e)).toList();
      } catch (_) {}
    }

    await _refreshStockWidget();
    isInitialized = true;
  }

  Future<void> saveItems() async {
    try {
      await _persistItemsLocally();
      final api = JengaApiService.instance;
      final owner = currentUser?.id;
      if (owner != null) {
        final prefs = await SharedPreferences.getInstance();
        final syncKey = _stockSyncKey(owner);
        if (api.authToken == null ||
            api.sessionEmail != currentUser?.email.toLowerCase()) {
          await prefs.setBool(syncKey, true);
          return;
        }
        final synced = await api.replaceAccountStock(
          items.map((item) => item.toJson()).toList(),
        );
        await prefs.setBool(syncKey, !synced);
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _persistItemsLocally() async {
    final jsonList = items.map((item) => item.toJson()).toList();
    final ownerId = inventoryOwnerId ?? currentUser?.id;
    if (ownerId != null && currentUser != null && ownerId != currentUser!.id) {
      await _saveInventorySnapshot(ownerId, items);
      return;
    }
    if (ownerId != null) {
      inventoryOwnerId = ownerId;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jengabiz_inventory_owner_id', ownerId);
      await _saveInventorySnapshot(ownerId, items);
    }
    await JengaCacheService.instance.set('items:all', jsonList);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/jengabiz_inventory.json');
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(jsonList), flush: true);
    await temporary.rename(file.path);
    await _refreshStockWidget();
  }

  Future<File> _inventorySnapshotFile(String ownerId) async {
    final dir = await getApplicationDocumentsDirectory();
    final safeId = ownerId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}/jengabiz_inventory_$safeId.json');
  }

  Future<void> _saveInventorySnapshot(
    String ownerId,
    List<StockItem> stock,
  ) async {
    final file = await _inventorySnapshotFile(ownerId);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(stock.map((item) => item.toJson()).toList()),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<List<StockItem>?> _readInventorySnapshot(String ownerId) async {
    final file = await _inventorySnapshotFile(ownerId);
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) return null;
    return decoded
        .map((item) => StockItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<Map<String, dynamic>>> stockForAccount(String userId) async {
    final stock = inventoryOwnerId == userId
        ? items
        : await _readInventorySnapshot(userId) ?? <StockItem>[];
    return stock.map((item) => item.toJson()).toList();
  }

  Future<void> _activateLocalUser(JengaUser user) async {
    if (inventoryOwnerId != user.id) {
      if (inventoryOwnerId != null) {
        await _saveInventorySnapshot(inventoryOwnerId!, items);
      }
      items = await _readInventorySnapshot(user.id) ?? <StockItem>[];
      inventoryOwnerId = user.id;
    }
    currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_user_id', user.id);
    await _persistItemsLocally();
  }

  /// Pull a user's database inventory, or upload the local copy for a new account.
  Future<bool> syncStockWithServer() async {
    final api = JengaApiService.instance;
    if (api.authToken == null ||
        api.sessionEmail != currentUser?.email.toLowerCase()) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    final syncKey = _stockSyncKey(currentUser!.id);
    final hasPendingLocalChanges = prefs.getBool(syncKey) ?? false;
    if (hasPendingLocalChanges && inventoryOwnerId == currentUser!.id) {
      final saved = await api.replaceAccountStock(
        items.map((item) => item.toJson()).toList(),
      );
      if (!saved) return false;
      await prefs.setBool(syncKey, false);
    }
    final remoteItems = await api.fetchAccountStock();
    if (remoteItems == null) return false;

    if (remoteItems.isEmpty &&
        items.isNotEmpty &&
        inventoryOwnerId == currentUser?.id) {
      final saved = await api.replaceAccountStock(
        items.map((item) => item.toJson()).toList(),
      );
      if (saved) {
        await prefs.setBool(syncKey, false);
      }
      return saved;
    }

    items = remoteItems.map(StockItem.fromJson).toList();
    inventoryOwnerId = currentUser?.id;
    await _persistItemsLocally();
    await prefs.setBool(syncKey, false);
    return true;
  }

  String _stockSyncKey(String userId) {
    final safeId = userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'jengabiz_stock_sync_pending_$safeId';
  }

  Future<void> _refreshStockWidget() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final unitsInStock =
          items.fold<int>(0, (total, item) => total + item.stockRemaining);
      final lowStockCount =
          items.where((item) => item.isLowStock || item.isOutOfStock).length;
      await preferences.setString(
        'jengabiz_widget_summary',
        jsonEncode({
          'shopName': currentUser?.shopName ?? 'Your shop',
          'itemCount': items.length,
          'unitsInStock': unitsInStock,
          'lowStockCount': lowStockCount,
        }),
      );
      await _stockWidgetChannel.invokeMethod<void>('refresh');
    } on MissingPluginException {
      // Non-Android test targets don't have the native home-screen widget.
    } on PlatformException {
      // Widget refresh failure should not block inventory changes.
    } catch (_) {
      // Keep the app usable if widget summary storage is unavailable.
    }
  }

  Future<JengaUser> createAccount({
    required String name,
    required String shopName,
    required String phone,
    required String email,
    required String password,
    String? accountId,
    String? accountCreatedAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw const FormatException('A valid email address is required.');
    }
    if (users.any((user) => user.email.toLowerCase() == normalizedEmail)) {
      throw const FormatException('An account with this email already exists.');
    }
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final newUser = JengaUser(
      id: accountId ?? 'usr_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Shop Owner' : name.trim(),
      shopName: shopName.trim().isEmpty ? 'My Duka' : shopName.trim(),
      phone: phone.trim().isEmpty ? '+254 700 000 000' : phone.trim(),
      email: normalizedEmail,
      createdAt: accountCreatedAt ?? DateTime.now().toIso8601String(),
      passwordSalt: salt,
      passwordHash: await hashPassword(password, salt),
    );

    users.add(newUser);
    await _activateLocalUser(newUser);

    await prefs.setString(
        'jengabiz_users', jsonEncode(users.map((u) => u.toJson()).toList()));
    await prefs.setString('current_user_id', newUser.id);
    await JengaCacheService.instance
        .set('user:${newUser.id}', newUser.toJson());

    return newUser;
  }

  Future<JengaUser> persistAuthenticatedAccount({
    required Map<String, dynamic> profile,
    required String password,
  }) async {
    final email = (profile['email'] as String? ?? '').trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      throw const FormatException('The server returned an invalid account.');
    }
    final existingLocalUser = findUser(email);
    if (inventoryOwnerId != null) {
      await _saveInventorySnapshot(inventoryOwnerId!, items);
    }
    List<StockItem>? existingLocalStock;
    if (existingLocalUser != null) {
      existingLocalStock = inventoryOwnerId == existingLocalUser.id
          ? List<StockItem>.from(items)
          : await _readInventorySnapshot(existingLocalUser.id);
    }

    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final user = JengaUser(
      id: profile['id'] as String? ??
          'usr_${DateTime.now().millisecondsSinceEpoch}',
      name: profile['name'] as String? ?? 'Shop Owner',
      shopName: profile['shopName'] as String? ?? 'My Duka',
      phone: profile['phone'] as String? ?? '',
      email: email,
      createdAt:
          profile['createdAt'] as String? ?? DateTime.now().toIso8601String(),
      passwordSalt: salt,
      passwordHash: await hashPassword(password, salt),
    );
    users.removeWhere((saved) => saved.email.toLowerCase() == email);
    users.add(user);
    currentUser = user;
    if (existingLocalStock != null) {
      items = existingLocalStock;
    } else {
      items = await _readInventorySnapshot(user.id) ?? <StockItem>[];
    }
    inventoryOwnerId = user.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'jengabiz_users',
      jsonEncode(users.map((saved) => saved.toJson()).toList()),
    );
    await prefs.setString('current_user_id', user.id);
    await _persistItemsLocally();
    return user;
  }

  JengaUser? findUser(String emailOrPhone) {
    final query = emailOrPhone.trim().toLowerCase();
    final found = users.where((u) =>
        u.email.toLowerCase() == query ||
        u.phone.replaceAll(' ', '') == query.replaceAll(' ', ''));
    return found.isEmpty ? null : found.first;
  }

  Future<bool> login(String emailOrPhone, String password) async {
    final valid = await verifyLocalPassword(emailOrPhone, password);
    if (!valid) return false;
    final user = findUser(emailOrPhone);
    if (user == null) return false;
    await _activateLocalUser(user);
    return true;
  }

  Future<bool> verifyLocalPassword(String emailOrPhone, String password) async {
    final user = findUser(emailOrPhone);
    if (user == null ||
        user.passwordSalt == null ||
        user.passwordHash == null) {
      return false;
    }
    final candidate = await hashPassword(password, user.passwordSalt!);
    return _constantTimeEquals(candidate, user.passwordHash!);
  }

  Future<bool> loginWithBiometrics() async {
    if (users.isEmpty) return false;
    final user = currentUser ?? users.first;
    await _activateLocalUser(user);
    return true;
  }

  Future<bool> setPasswordForLegacyAccount(
      String emailOrPhone, String password) async {
    final index =
        users.indexWhere((user) => user.id == findUser(emailOrPhone)?.id);
    if (index < 0) return false;
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final oldUser = users[index];
    users[index] = JengaUser(
      id: oldUser.id,
      name: oldUser.name,
      shopName: oldUser.shopName,
      phone: oldUser.phone,
      email: oldUser.email,
      createdAt: oldUser.createdAt,
      passwordSalt: salt,
      passwordHash: await hashPassword(password, salt),
    );
    await _activateLocalUser(users[index]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'jengabiz_users', jsonEncode(users.map((u) => u.toJson()).toList()));
    await prefs.setString('current_user_id', currentUser!.id);
    return true;
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }

  Future<void> logout() async {
    currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_user_id');
  }

  Future<void> adjustStock(String itemId, int delta) async {
    final idx = items.indexWhere((it) => it.id == itemId);
    if (idx != -1) {
      final it = items[idx];
      it.stockRemaining = (it.stockRemaining + delta).clamp(0, 99999);
      if (delta < 0) {
        it.unitsSold += (-delta);
      }
      await saveItems();
    }
  }

  Future<void> setStock(String itemId, int newQuantity) async {
    final idx = items.indexWhere((it) => it.id == itemId);
    if (idx != -1) {
      items[idx].stockRemaining = newQuantity.clamp(0, 99999);
      await saveItems();
    }
  }

  List<String> getCategories() {
    final set = <String>{'All'};
    for (final it in items) {
      set.add(it.category);
    }
    return set.toList();
  }
}
