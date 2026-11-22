import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'cache_service.dart';

class JengaApiService {
  static final JengaApiService instance = JengaApiService._();
  JengaApiService._();

  // Android emulator uses 10.0.2.2, physical devices can use local network IP or reverse tunnel
  String baseUrl = 'http://10.0.2.2:5080';
  String? authToken;
  String? shopId;
  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 4);

  void configure({required String url, String? token, String? currentShopId}) {
    baseUrl = url;
    authToken = token;
    shopId = currentShopId;
  }

  void _applyHeaders(HttpHeaders headers) {
    headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (authToken != null) {
      headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
    }
    if (shopId != null) {
      headers.set('X-Shop-Id', shopId!);
    }
  }

  /// Request OTP for mobile authentication
  Future<Map<String, dynamic>?> requestOtp(String phone) async {
    try {
      final req = await _client.postUrl(Uri.parse('$baseUrl/auth/request-otp'));
      _applyHeaders(req.headers);
      req.write(jsonEncode({'phone': phone}));
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        return jsonDecode(body);
      }
    } catch (_) {}
    return null;
  }

  /// Verify OTP and receive JWT Bearer Token
  Future<String?> verifyOtp(String phone, String otp) async {
    try {
      final req = await _client.postUrl(Uri.parse('$baseUrl/auth/verify-otp'));
      _applyHeaders(req.headers);
      req.write(jsonEncode({'phone': phone, 'otp': otp}));
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        authToken = data['token'] as String?;
        return authToken;
      }
    } catch (_) {}
    return null;
  }

  /// Fetch Catalog items from C# API (with Cache-aside pattern)
  Future<List<Map<String, dynamic>>?> fetchCatalogItems({String? targetShopId}) async {
    final sId = targetShopId ?? shopId;
    final cacheKey = 'api:catalog:${sId ?? 'default'}';

    // 1. Check Cache
    final cached = await JengaCacheService.instance.get<List>(cacheKey);
    if (cached != null) {
      return List<Map<String, dynamic>>.from(cached);
    }

    // 2. Fetch from C# Backend API
    try {
      final url = sId != null
          ? '$baseUrl/catalog/items?shopId=$sId'
          : '$baseUrl/catalog/items';
      final req = await _client.getUrl(Uri.parse(url));
      _applyHeaders(req.headers);
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final List list = jsonDecode(body);
        final result = List<Map<String, dynamic>>.from(list);
        // Save to Cache
        await JengaCacheService.instance.set(cacheKey, result);
        return result;
      }
    } catch (_) {}
    return null;
  }

  /// Add new Item to C# API
  Future<bool> addItem(Map<String, dynamic> item) async {
    try {
      final req = await _client.postUrl(Uri.parse('$baseUrl/catalog/items'));
      _applyHeaders(req.headers);
      req.write(jsonEncode(item));
      final res = await req.close();
      if (res.statusCode == 200 || res.statusCode == 201) {
        await JengaCacheService.instance.invalidatePattern('api:catalog:');
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Fetch Daily Summary and Business Analytics
  Future<Map<String, dynamic>?> fetchDailySummary({String? targetShopId}) async {
    final sId = targetShopId ?? shopId;
    try {
      final req = await _client.getUrl(Uri.parse('$baseUrl/summary/daily?shopId=${sId ?? ''}'));
      _applyHeaders(req.headers);
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        return jsonDecode(body);
      }
    } catch (_) {}
    return null;
  }

  /// Sync pull updates from C# API since timestamp
  Future<Map<String, dynamic>?> syncPull(DateTime since, {String? targetShopId}) async {
    final sId = targetShopId ?? shopId;
    try {
      final iso = since.toIso8601String();
      final req = await _client.getUrl(Uri.parse('$baseUrl/sync/pull?shopId=${sId ?? ''}&since=$iso'));
      _applyHeaders(req.headers);
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        return jsonDecode(body);
      }
    } catch (_) {}
    return null;
  }
}
