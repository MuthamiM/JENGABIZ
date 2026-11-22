import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cache_service.dart';

class JengaUser {
  final String id;
  final String name;
  final String shopName;
  final String phone;
  final String email;
  final String createdAt;

  JengaUser({
    required this.id,
    required this.name,
    required this.shopName,
    required this.phone,
    required this.email,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'shopName': shopName,
        'phone': phone,
        'email': email,
        'createdAt': createdAt,
      };

  factory JengaUser.fromJson(Map<String, dynamic> json) => JengaUser(
        id: json['id'] as String? ?? 'usr_1',
        name: json['name'] as String? ?? 'Shop Owner',
        shopName: json['shopName'] as String? ?? 'My Duka',
        phone: json['phone'] as String? ?? '+254 700 000 000',
        email: json['email'] as String? ?? 'owner@jengabiz.com',
        createdAt: json['createdAt'] as String? ?? DateTime.now().toIso8601String(),
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
  JengaDB._();

  List<StockItem> items = [];
  List<JengaUser> users = [];
  JengaUser? currentUser;
  bool isInitialized = false;
  String nearestHubName = 'Industrial Area Logistics Point';
  double nearestHubDistanceKm = 4.2;
  double? latitude;
  double? longitude;

  Future<void> init() async {
    if (isInitialized) return;

    try {
      await JengaCacheService.instance.init();
      final prefs = await SharedPreferences.getInstance();

      // 1. Load users
      final usersJson = prefs.getString('jengabiz_users');
      if (usersJson != null) {
        final List list = jsonDecode(usersJson);
        users = list.map((e) => JengaUser.fromJson(e)).toList();
      }

      if (users.isEmpty) {
        final defaultUser = JengaUser(
          id: 'user_default',
          name: 'Musa Mwangi',
          shopName: 'Musa Wholesale Duka',
          phone: '+254 712 345 678',
          email: 'musamwangi@gmail.com',
          createdAt: DateTime.now().toIso8601String(),
        );
        users.add(defaultUser);
        currentUser = defaultUser;
        await prefs.setString(
            'jengabiz_users', jsonEncode(users.map((u) => u.toJson()).toList()));
        await prefs.setString('current_user_id', defaultUser.id);
      } else {
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
        items = cached.map((e) => StockItem.fromJson(Map<String, dynamic>.from(e))).toList();
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
          await file.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()));
        }

        // Cache loaded items into L1/L2 Redis
        await JengaCacheService.instance
            .set('items:all', items.map((e) => e.toJson()).toList());
      }
    } catch (e) {
      try {
        final assetJson = await rootBundle.loadString('assets/items_db.json');
        final List list = jsonDecode(assetJson);
        items = list.map((e) => StockItem.fromJson(e)).toList();
      } catch (_) {}
    }

    isInitialized = true;
  }

  Future<void> saveItems() async {
    try {
      final jsonList = items.map((e) => e.toJson()).toList();
      // Update Cache immediately
      await JengaCacheService.instance.set('items:all', jsonList);

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/jengabiz_inventory.json');
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      // ignore
    }
  }

  Future<JengaUser> createAccount({
    required String name,
    required String shopName,
    required String phone,
    required String email,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final newUser = JengaUser(
      id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Shop Owner' : name.trim(),
      shopName: shopName.trim().isEmpty ? 'My Duka' : shopName.trim(),
      phone: phone.trim().isEmpty ? '+254 700 000 000' : phone.trim(),
      email: email.trim().isEmpty ? 'owner@jengabiz.com' : email.trim(),
      createdAt: DateTime.now().toIso8601String(),
    );

    users.add(newUser);
    currentUser = newUser;

    await prefs.setString('jengabiz_users', jsonEncode(users.map((u) => u.toJson()).toList()));
    await prefs.setString('current_user_id', newUser.id);
    await JengaCacheService.instance.set('user:${newUser.id}', newUser.toJson());

    return newUser;
  }

  Future<bool> login(String emailOrPhone) async {
    final query = emailOrPhone.trim().toLowerCase();
    final found = users.where((u) =>
        u.email.toLowerCase() == query || u.phone.replaceAll(' ', '') == query.replaceAll(' ', ''));
    if (found.isNotEmpty) {
      currentUser = found.first;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_user_id', currentUser!.id);
      return true;
    }
    return false;
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

