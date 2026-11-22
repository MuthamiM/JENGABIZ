import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Cache Entry with TTL support
class CacheEntry<T> {
  final T data;
  final DateTime expiresAt;

  CacheEntry(this.data, {Duration ttl = const Duration(minutes: 30)})
      : expiresAt = DateTime.now().add(ttl);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// High-performance Multi-Tier Cache with Redis integration
class JengaCacheService {
  static final JengaCacheService instance = JengaCacheService._();
  JengaCacheService._();

  // L1 In-Memory Cache
  final Map<String, CacheEntry<dynamic>> _l1Cache = {};

  // Redis configuration (Local or Remote Redis Cloud/Upstash)
  String redisHost = '127.0.0.1';
  int redisPort = 6379;
  String? redisPassword;
  bool isRedisConnected = false;
  Socket? _redisSocket;

  /// Initialize Redis and Cache connection
  Future<void> init({String host = '127.0.0.1', int port = 6379, String? password}) async {
    redisHost = host;
    redisPort = port;
    redisPassword = password;
    await _tryConnectRedis();
  }

  Future<void> _tryConnectRedis() async {
    try {
      _redisSocket = await Socket.connect(redisHost, redisPort,
          timeout: const Duration(milliseconds: 500));
      isRedisConnected = true;
      if (redisPassword != null && redisPassword!.isNotEmpty) {
        _redisSocket!.write('*2\r\n\$4\r\nAUTH\r\n\$${redisPassword!.length}\r\n$redisPassword\r\n');
      }
    } catch (_) {
      // Graceful fallback to ultra-fast local L1 memory and persistent cache
      isRedisConnected = false;
      _redisSocket = null;
    }
  }

  /// Get value from Cache (L1 Memory -> L2 Redis)
  Future<T?> get<T>(String key) async {
    // 1. Check L1 In-Memory Cache
    final entry = _l1Cache[key];
    if (entry != null) {
      if (!entry.isExpired) {
        return entry.data as T?;
      } else {
        _l1Cache.remove(key);
      }
    }

    // 2. Check L2 Redis Cache
    if (isRedisConnected && _redisSocket != null) {
      try {
        final completer = Completer<String?>();
        StreamSubscription? sub;
        sub = _redisSocket!.listen((data) {
          final res = utf8.decode(data);
          sub?.cancel();
          if (res.startsWith('\$')) {
            final lines = res.split('\r\n');
            if (lines.length > 1 && lines[1] != '-1') {
              completer.complete(lines[1]);
              return;
            }
          }
          completer.complete(null);
        });

        _redisSocket!.write('*2\r\n\$3\r\nGET\r\n\$${key.length}\r\n$key\r\n');
        final raw = await completer.future.timeout(const Duration(milliseconds: 300),
            onTimeout: () => null);

        if (raw != null) {
          final decoded = jsonDecode(raw);
          _l1Cache[key] = CacheEntry(decoded);
          return decoded as T?;
        }
      } catch (_) {
        // Fallback
      }
    }

    return null;
  }

  /// Store value into Cache (L1 Memory and L2 Redis)
  Future<void> set(String key, dynamic value, {Duration ttl = const Duration(minutes: 30)}) async {
    // Save to L1 Memory
    _l1Cache[key] = CacheEntry(value, ttl: ttl);

    // Save to Redis
    if (isRedisConnected && _redisSocket != null) {
      try {
        final payload = jsonEncode(value);
        final cmd = '*3\r\n\$3\r\nSET\r\n\$${key.length}\r\n$key\r\n\$${payload.length}\r\n$payload\r\n';
        _redisSocket!.write(cmd);

        // Set TTL in Redis
        final seconds = ttl.inSeconds;
        final expireCmd =
            '*3\r\n\$6\r\nEXPIRE\r\n\$${key.length}\r\n$key\r\n\$${seconds.toString().length}\r\n$seconds\r\n';
        _redisSocket!.write(expireCmd);
      } catch (_) {
        // Fallback
      }
    }
  }

  /// Invalidate key
  Future<void> invalidate(String key) async {
    _l1Cache.remove(key);
    if (isRedisConnected && _redisSocket != null) {
      try {
        _redisSocket!.write('*2\r\n\$3\r\nDEL\r\n\$${key.length}\r\n$key\r\n');
      } catch (_) {}
    }
  }

  /// Invalidate all keys matching prefix
  Future<void> invalidatePattern(String prefix) async {
    _l1Cache.removeWhere((k, _) => k.startsWith(prefix));
  }

  /// Clear entire cache
  Future<void> clear() async {
    _l1Cache.clear();
    if (isRedisConnected && _redisSocket != null) {
      try {
        _redisSocket!.write('*1\r\n\$7\r\nFLUSHDB\r\n');
      } catch (_) {}
    }
  }
}

