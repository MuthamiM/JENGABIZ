import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'cache_service.dart';

typedef JsonPostTransport = Future<JengaApiResponse?> Function(
    Uri uri, Map<String, dynamic> payload);

class JengaApiResponse {
  const JengaApiResponse(this.statusCode, this.data);

  final int statusCode;
  final Map<String, dynamic> data;
  bool get succeeded =>
      statusCode >= 200 && statusCode < 300 && data['success'] == true;
}

class JengaApiService {
  static final JengaApiService instance = JengaApiService._();
  JengaApiService._()
      : _client = HttpClient()..connectionTimeout = const Duration(seconds: 4),
        _postJsonOverride = null,
        _secureStorage = const FlutterSecureStorage();

  /// Test seam for exercising request routing without making network calls.
  JengaApiService.forTesting(this._postJsonOverride)
      : _client = null,
        _secureStorage = null;

  final HttpClient? _client;
  final JsonPostTransport? _postJsonOverride;
  final FlutterSecureStorage? _secureStorage;

  // Override for local development with --dart-define=JENGABIZ_API_BASE_URL=...
  String baseUrl = const String.fromEnvironment(
    'JENGABIZ_API_BASE_URL',
    defaultValue: 'https://jengabiz-api.mftechnologies.org',
  );
  String? authToken;
  String? sessionEmail;
  String? shopId;
  void configure({required String url, String? token, String? currentShopId}) {
    final parsed = Uri.tryParse(url.trim());
    if (parsed == null ||
        !parsed.hasAuthority ||
        !{'http', 'https'}.contains(parsed.scheme)) {
      throw ArgumentError.value(
          url, 'url', 'A valid HTTP or HTTPS API URL is required.');
    }
    if (parsed.scheme == 'http' && !_isLocalHost(parsed.host)) {
      throw ArgumentError.value(
        url,
        'url',
        'HTTPS is required for non-local API hosts.',
      );
    }
    baseUrl = parsed
        .replace(path: parsed.path.replaceFirst(RegExp(r'/+$'), ''))
        .toString();
    authToken = token;
    sessionEmail = null;
    shopId = currentShopId;
  }

  bool _isLocalHost(String host) {
    if (host == 'localhost' || host.endsWith('.local') || host == '10.0.2.2') {
      return true;
    }
    final octets = host.split('.');
    if (octets.length != 4) return false;
    final address = octets.map(int.tryParse).toList();
    if (address.any((value) => value == null || value < 0 || value > 255)) {
      return false;
    }
    final first = address[0]!;
    final second = address[1]!;
    return first == 10 ||
        first == 127 ||
        (first == 192 && second == 168) ||
        (first == 172 && second >= 16 && second <= 31);
  }

  Future<void> restoreSession() async {
    try {
      authToken = await _secureStorage?.read(key: 'jengabiz_session');
      sessionEmail = await _secureStorage?.read(key: 'jengabiz_session_email');
    } catch (_) {
      authToken = null;
      sessionEmail = null;
    }
  }

  Future<void> saveSession(String token, {required String email}) async {
    authToken = token;
    sessionEmail = email.trim().toLowerCase();
    try {
      await _secureStorage?.write(key: 'jengabiz_session', value: token);
      await _secureStorage?.write(
        key: 'jengabiz_session_email',
        value: sessionEmail,
      );
    } catch (_) {
      // The active session remains available in memory if secure storage is unavailable.
    }
  }

  Future<void> clearSession() async {
    authToken = null;
    sessionEmail = null;
    shopId = null;
    try {
      await _secureStorage?.delete(key: 'jengabiz_session');
      await _secureStorage?.delete(key: 'jengabiz_session_email');
    } catch (_) {}
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

  Future<JengaApiResponse?> _requestJson(
    String method,
    String path, {
    Map<String, dynamic>? payload,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final override = _postJsonOverride;
    if (override != null) {
      if (method != 'POST') return null;
      return override(uri, payload ?? const {});
    }

    try {
      final req = switch (method) {
        'GET' => await _client!.getUrl(uri),
        'PUT' => await _client!.putUrl(uri),
        'DELETE' => await _client!.deleteUrl(uri),
        _ => await _client!.postUrl(uri),
      };
      _applyHeaders(req.headers);
      if (payload != null) req.write(jsonEncode(payload));
      final res = await req.close().timeout(const Duration(seconds: 10));
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      if (body.isEmpty) {
        return JengaApiResponse(res.statusCode, const {});
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return JengaApiResponse(
        res.statusCode,
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _postJson(
          String path, Map<String, dynamic> payload) async =>
      (await _requestJson('POST', path, payload: payload))?.data;

  /// Send the account verification code to the address entered at sign-up.
  Future<Map<String, dynamic>?> requestEmailOtp(String email) =>
      _postJson('/email-auth/request-otp', {
        'email': email.trim().toLowerCase(),
      });

  /// Verify a one-time email code and receive a short-lived registration grant.
  Future<String?> verifyEmailOtp(String email, String otp) async {
    final result =
        await _requestJson('POST', '/email-auth/verify-otp', payload: {
      'email': email.trim().toLowerCase(),
      'otp': otp.trim(),
    });
    final token = result?.data['verificationToken'];
    if (result?.succeeded != true ||
        result?.data['verified'] != true ||
        token is! String) {
      return null;
    }
    return token;
  }

  Future<JengaApiResponse?> loginAccount(String email, String password) =>
      _requestJson('POST', '/email-auth/login', payload: {
        'email': email.trim().toLowerCase(),
        'password': password,
      });

  Future<JengaApiResponse?> createAccount({
    required String email,
    required String verificationToken,
    required String name,
    required String shopName,
    required String phone,
    required String password,
    required List<Map<String, dynamic>> items,
    bool migrate = false,
  }) =>
      _requestJson(
        'POST',
        migrate ? '/email-auth/migrate' : '/email-auth/register',
        payload: {
          'email': email.trim().toLowerCase(),
          'verificationToken': verificationToken,
          'name': name,
          'shopName': shopName,
          'phone': phone,
          'password': password,
          'items': items,
        },
      );

  Future<List<Map<String, dynamic>>?> fetchAccountStock() async {
    final response = await _requestJson('GET', '/email-auth/stock/items');
    if (response?.succeeded != true || response?.data['items'] is! List) {
      return null;
    }
    return (response!.data['items'] as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<bool> replaceAccountStock(List<Map<String, dynamic>> items) async {
    final response = await _requestJson(
      'PUT',
      '/email-auth/stock/items',
      payload: {'items': items},
    );
    return response?.succeeded == true;
  }

  Future<void> logoutAccount() async {
    if (authToken != null) {
      await _requestJson('POST', '/email-auth/logout', payload: const {});
    }
    await clearSession();
  }

  /// Fetch Catalog items from C# API (with Cache-aside pattern)
  Future<List<Map<String, dynamic>>?> fetchCatalogItems(
      {String? targetShopId}) async {
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
      final req = await _client!.getUrl(Uri.parse(url));
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
      final req = await _client!.postUrl(Uri.parse('$baseUrl/catalog/items'));
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
  Future<Map<String, dynamic>?> fetchDailySummary(
      {String? targetShopId}) async {
    final sId = targetShopId ?? shopId;
    try {
      final req = await _client!
          .getUrl(Uri.parse('$baseUrl/summary/daily?shopId=${sId ?? ''}'));
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
  Future<Map<String, dynamic>?> syncPull(DateTime since,
      {String? targetShopId}) async {
    final sId = targetShopId ?? shopId;
    try {
      final iso = since.toIso8601String();
      final req = await _client!.getUrl(
          Uri.parse('$baseUrl/sync/pull?shopId=${sId ?? ''}&since=$iso'));
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
