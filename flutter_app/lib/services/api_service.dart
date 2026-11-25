import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'cache_service.dart';

typedef JsonPostTransport = Future<JengaApiResponse?> Function(
    Uri uri, Map<String, dynamic> payload);
typedef JsonRequestTransport = Future<JengaApiResponse?> Function(
    String method, Uri uri, Map<String, dynamic> payload);

class JengaApiResponse {
  const JengaApiResponse(this.statusCode, this.data);

  final int statusCode;
  final Map<String, dynamic> data;
  bool get succeeded =>
      statusCode >= 200 && statusCode < 300 && data['success'] == true;
}

class JengaProfileImage {
  const JengaProfileImage({
    required this.imageType,
    required this.bytes,
    this.mimeType,
  });

  final String imageType;
  final Uint8List bytes;
  final String? mimeType;
}

class JengaProfileImageFetchResult {
  const JengaProfileImageFetchResult({
    this.image,
    this.notFound = false,
  });

  final JengaProfileImage? image;
  final bool notFound;
}

class JengaApiService {
  static final JengaApiService instance = JengaApiService._();
  JengaApiService._()
      : _client = HttpClient()..connectionTimeout = const Duration(seconds: 4),
        _postJsonOverride = null,
        _requestJsonOverride = null,
        _secureStorage = const FlutterSecureStorage();

  /// Test seam for exercising request routing without making network calls.
  JengaApiService.forTesting(this._postJsonOverride)
      : _client = null,
        _requestJsonOverride = null,
        _secureStorage = null;

  JengaApiService.forTestingRequests(this._requestJsonOverride)
      : _client = null,
        _postJsonOverride = null,
        _secureStorage = null;

  final HttpClient? _client;
  final JsonPostTransport? _postJsonOverride;
  final JsonRequestTransport? _requestJsonOverride;
  final FlutterSecureStorage? _secureStorage;

  // Override for local development with --dart-define=JENGABIZ_API_BASE_URL=...
  String baseUrl = const String.fromEnvironment(
    'JENGABIZ_API_BASE_URL',
    defaultValue: 'https://jengabiz.mftechnologies.org',
  );
  String? authToken;
  String? sessionEmail;
  String? shopId;
  static const _sessionBundleKey = 'jengabiz_session_bundle';

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
    authToken = null;
    sessionEmail = null;
    try {
      final encoded = await _secureStorage?.read(key: _sessionBundleKey);
      if (encoded != null) {
        final decoded = jsonDecode(encoded);
        if (decoded is Map &&
            decoded['token'] is String &&
            decoded['email'] is String) {
          authToken = (decoded['token'] as String).trim();
          sessionEmail = (decoded['email'] as String).trim().toLowerCase();
          if (authToken!.isNotEmpty && sessionEmail!.isNotEmpty) return;
        }
      }
    } catch (_) {
      // Fall back to sessions written by earlier app versions.
    }

    try {
      final legacyToken = await _secureStorage?.read(key: 'jengabiz_session');
      final legacyEmail =
          await _secureStorage?.read(key: 'jengabiz_session_email');
      if (legacyToken != null && legacyEmail != null) {
        authToken = legacyToken.trim();
        sessionEmail = legacyEmail.trim().toLowerCase();
        if (authToken!.isEmpty || sessionEmail!.isEmpty) {
          authToken = null;
          sessionEmail = null;
          return;
        }
        unawaited(_migrateLegacySession(authToken!, sessionEmail!));
      }
    } catch (_) {
      authToken = null;
      sessionEmail = null;
    }
  }

  Future<void> _migrateLegacySession(String token, String email) async {
    try {
      await _secureStorage?.write(
        key: _sessionBundleKey,
        value: jsonEncode({'token': token, 'email': email}),
      );
      await _secureStorage?.delete(key: 'jengabiz_session');
      await _secureStorage?.delete(key: 'jengabiz_session_email');
    } catch (_) {
      // The original secure keys remain available if migration is interrupted.
    }
  }

  Future<void> saveSession(String token, {required String email}) async {
    authToken = token;
    sessionEmail = email.trim().toLowerCase();
    try {
      await _secureStorage?.write(
        key: _sessionBundleKey,
        value: jsonEncode({'token': token, 'email': sessionEmail}),
      );
      await _secureStorage?.delete(key: 'jengabiz_session');
      await _secureStorage?.delete(key: 'jengabiz_session_email');
    } catch (_) {
      // The active session remains available in memory if secure storage is unavailable.
    }
  }

  Future<void> clearSession() async {
    authToken = null;
    sessionEmail = null;
    shopId = null;
    try {
      await _secureStorage?.delete(key: _sessionBundleKey);
      await _secureStorage?.delete(key: 'jengabiz_session');
      await _secureStorage?.delete(key: 'jengabiz_session_email');
    } catch (_) {}
  }

  void _applyHeaders(HttpHeaders headers, {String? authTokenOverride}) {
    headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    headers.set(HttpHeaders.acceptHeader, 'application/json');
    final token = authTokenOverride ?? authToken;
    if (token != null) {
      headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (shopId != null) {
      headers.set('X-Shop-Id', shopId!);
    }
  }

  Future<JengaApiResponse?> _requestJson(
    String method,
    String path, {
    Map<String, dynamic>? payload,
    String? authTokenOverride,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final requestOverride = _requestJsonOverride;
    if (requestOverride != null) {
      return requestOverride(method, uri, payload ?? const {});
    }
    final override = _postJsonOverride;
    if (override != null) {
      if (method != 'POST') return null;
      return override(uri, payload ?? const {});
    }

    try {
      final req = switch (method) {
        'GET' => await _client!.getUrl(uri).timeout(timeout),
        'PUT' => await _client!.putUrl(uri).timeout(timeout),
        'DELETE' => await _client!.deleteUrl(uri).timeout(timeout),
        _ => await _client!.postUrl(uri).timeout(timeout),
      };
      _applyHeaders(req.headers, authTokenOverride: authTokenOverride);
      if (payload != null) req.write(jsonEncode(payload));
      final res = await req.close().timeout(timeout);
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
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
  Future<Map<String, dynamic>?> requestEmailOtp(String email,
          {String purpose = 'account_verification'}) =>
      _postJson('/email-auth/request-otp', {
        'email': email.trim().toLowerCase(),
        'purpose': purpose,
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

  Future<JengaApiResponse?> resetAccountPassword({
    required String email,
    required String verificationToken,
    required String newPassword,
  }) =>
      _requestJson('POST', '/email-auth/reset-password', payload: {
        'email': email.trim().toLowerCase(),
        'verificationToken': verificationToken,
        'newPassword': newPassword,
      });

  Future<JengaApiResponse?> loginAccount(String email, String password) =>
      _requestJson('POST', '/email-auth/login', payload: {
        'email': email.trim().toLowerCase(),
        'password': password,
      });

  Future<JengaApiResponse?> requestSuspendedAccountSupport({
    required String email,
    required String password,
    required String reason,
  }) =>
      _requestJson(
        'POST',
        '/email-auth/support/request',
        payload: {
          'email': email.trim().toLowerCase(),
          'password': password,
          'reason': reason.trim(),
        },
        timeout: const Duration(seconds: 30),
      );

  Future<JengaApiResponse?> fetchAccountProfile() =>
      _requestJson('GET', '/email-auth/me');

  Future<bool> registerNotificationDevice({
    required String deviceToken,
    required String platform,
    int? appVersionCode,
  }) async {
    final response = await _requestJson(
      'POST',
      '/email-auth/notifications/device',
      payload: {
        'deviceToken': deviceToken,
        'platform': platform,
        if (appVersionCode != null && appVersionCode > 0)
          'appVersionCode': appVersionCode,
      },
    );
    return response?.succeeded == true;
  }

  Future<bool> removeNotificationDevice(String deviceToken) async {
    final response = await _requestJson(
      'DELETE',
      '/email-auth/notifications/device',
      payload: {'deviceToken': deviceToken},
    );
    return response?.succeeded == true;
  }

  Future<JengaApiResponse?> createAccount({
    required String email,
    required String verificationToken,
    required String name,
    required String shopName,
    required String phone,
    required String password,
    required List<Map<String, dynamic>> items,
    bool migrate = false,
    String county = '',
    String referralCode = '',
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
          'county': county.trim(),
          'referralCode': referralCode.trim().toUpperCase(),
          'password': password,
          'items': items,
        },
      );

  Future<JengaApiResponse?> fetchReferralSummary() =>
      _requestJson('GET', '/email-auth/referrals');

  Future<JengaApiResponse?> saveReferralLocation({
    required String county,
  }) =>
      _requestJson(
        'PUT',
        '/email-auth/referrals/location',
        payload: {'county': county.trim()},
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

  Future<bool> replaceAccountStock(
    List<Map<String, dynamic>> items, {
    String? sourceDeviceToken,
  }) async {
    final response = await _requestJson(
      'PUT',
      '/email-auth/stock/items',
      payload: {
        'items': items,
        if (sourceDeviceToken != null) 'sourceDeviceToken': sourceDeviceToken,
      },
    );
    return response?.succeeded == true;
  }

  Future<String?> uploadStockImage({
    required String itemId,
    required String mimeType,
    required Uint8List imageData,
  }) async {
    final response = await _requestJson(
      'PUT',
      '/email-auth/stock/images/${Uri.encodeComponent(itemId)}',
      payload: {
        'mimeType': mimeType,
        'imageBase64': base64Encode(imageData),
      },
    );
    final imageUrl = response?.data['imageUrl'];
    if (response?.succeeded != true || imageUrl is! String) return null;
    return imageUrl;
  }

  Future<Uint8List?> fetchStockImage(String itemId) async {
    final client = _client;
    if (client == null || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(itemId)) {
      return null;
    }
    try {
      final uri = Uri.parse(
        '$baseUrl/email-auth/stock/images/${Uri.encodeComponent(itemId)}',
      );
      final request = await client.getUrl(uri);
      request.headers
          .set(HttpHeaders.acceptHeader, 'image/jpeg, image/png, image/webp');
      if (authToken != null) {
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
      }
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok ||
          (response.contentLength > 1024 * 1024)) {
        await response.drain<void>();
        return null;
      }
      final contentType = response.headers.contentType?.mimeType;
      if (!const {'image/jpeg', 'image/png', 'image/webp'}
          .contains(contentType)) {
        await response.drain<void>();
        return null;
      }
      final bytes = await response.fold<List<int>>(<int>[], (all, chunk) {
        if (all.length + chunk.length > 1024 * 1024) {
          throw const FormatException('Stock image is larger than 1 MB.');
        }
        all.addAll(chunk);
        return all;
      });
      return bytes.isEmpty ? null : Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<JengaApiResponse?> uploadProfileImage({
    required String imageType,
    required String mimeType,
    required Uint8List imageData,
  }) =>
      _requestJson(
        'PUT',
        '/email-auth/profile/image',
        payload: {
          'imageType': imageType,
          'mimeType': mimeType,
          'imageBase64': base64Encode(imageData),
        },
        timeout: const Duration(seconds: 20),
      );

  Future<bool> removeProfileImage() async {
    final response = await _requestJson(
      'DELETE',
      '/email-auth/profile/image',
      payload: const {},
    );
    return response?.succeeded == true;
  }

  Future<JengaProfileImageFetchResult> fetchProfileImageStatus() async {
    final client = _client;
    if (client == null) return const JengaProfileImageFetchResult();
    try {
      final request = await client.getUrl(
        Uri.parse('$baseUrl/email-auth/profile/image'),
      );
      request.headers
          .set(HttpHeaders.acceptHeader, 'image/jpeg, image/png, image/webp');
      if (authToken != null) {
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
      }
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode == HttpStatus.notFound) {
        await response.drain<void>();
        return const JengaProfileImageFetchResult(notFound: true);
      }
      if (response.statusCode != HttpStatus.ok ||
          response.contentLength > 1024 * 1024) {
        await response.drain<void>();
        return const JengaProfileImageFetchResult();
      }
      final imageType = response.headers.value('x-profile-image-type');
      final mimeType = response.headers.contentType?.mimeType;
      if (!const {'personal', 'shop'}.contains(imageType) ||
          !const {'image/jpeg', 'image/png', 'image/webp'}.contains(mimeType)) {
        await response.drain<void>();
        return const JengaProfileImageFetchResult();
      }
      final bytes = await response.fold<List<int>>(<int>[], (all, chunk) {
        if (all.length + chunk.length > 1024 * 1024) {
          throw const FormatException('Profile photo is larger than 1 MB.');
        }
        all.addAll(chunk);
        return all;
      }).timeout(const Duration(seconds: 10));
      if (bytes.isEmpty) {
        return const JengaProfileImageFetchResult();
      }
      return JengaProfileImageFetchResult(
        image: JengaProfileImage(
          imageType: imageType!,
          mimeType: mimeType,
          bytes: Uint8List.fromList(bytes),
        ),
      );
    } catch (_) {
      return const JengaProfileImageFetchResult();
    }
  }

  Future<JengaProfileImage?> fetchProfileImage() async =>
      (await fetchProfileImageStatus()).image;

  Future<void> logoutAccount({String? deviceToken}) async {
    final token = authToken;
    final payload = <String, dynamic>{};
    if (deviceToken != null && deviceToken.isNotEmpty) {
      payload['deviceToken'] = deviceToken;
    }
    if (token != null) {
      unawaited(_revokeRemoteSession(token, payload));
    }
    await clearSession();
  }

  Future<void> _revokeRemoteSession(
    String token,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _requestJson(
        'POST',
        '/email-auth/logout',
        payload: payload,
        authTokenOverride: token,
      );
    } catch (_) {
      // Local sign-out is already complete; the server request is best effort.
    }
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
