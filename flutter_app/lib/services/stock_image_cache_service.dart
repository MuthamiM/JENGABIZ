import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class StockImageCacheService {
  StockImageCacheService._();

  static final instance = StockImageCacheService._();
  static const int _maxMemoryEntries = 128;
  static const int _maxDiskImageBytes = 2 * 1024 * 1024;

  final LinkedHashMap<String, Uint8List> _memory =
      LinkedHashMap<String, Uint8List>();
  final Map<String, Future<File>> _inflightWrites = {};
  final Map<String, Future<Uint8List?>> _inflightEnsure = {};
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  int _writeCounter = 0;
  String? _cachedImagesDirPath;

  static String? itemKeyForUrl(String imageUrl) {
    if (imageUrl.startsWith('stock-image:')) {
      final id = imageUrl.substring('stock-image:'.length);
      return RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ? id : null;
    }
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      final digest = sha256.convert(utf8.encode(imageUrl)).toString();
      return 'url_${digest.substring(0, 40)}';
    }
    return null;
  }

  String _cacheKey(String ownerId, String itemId) =>
      ownerId.trim().isEmpty ? itemId : '${ownerId.trim()}:$itemId';

  Uint8List? peekMemory(String ownerId, String itemId) {
    final key = _cacheKey(ownerId, itemId);
    final hit = _memory.remove(key);
    if (hit != null) {
      _memory[key] = hit;
      return hit;
    }
    if (ownerId.trim().isNotEmpty) {
      final fallback = _memory.remove(itemId);
      if (fallback != null) {
        _memory[itemId] = fallback;
        return fallback;
      }
    }
    return null;
  }

  void _remember(String ownerId, String itemId, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > _maxDiskImageBytes) return;
    final key = _cacheKey(ownerId, itemId);
    _memory.remove(key);
    _memory[key] = bytes;
    if (ownerId.trim().isNotEmpty) {
      _memory.remove(itemId);
      _memory[itemId] = bytes;
    }
    while (_memory.length > _maxMemoryEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  void clearMemory() {
    _memory.clear();
  }

  @visibleForTesting
  void resetDirectoryCacheForTesting() {
    _cachedImagesDirPath = null;
  }

  Future<File> _fileFor(String ownerId, String itemId) async {
    var imagesDirPath = _cachedImagesDirPath;
    if (imagesDirPath == null) {
      final directory = await getApplicationSupportDirectory();
      imagesDirPath = '${directory.path}/stock-images';
      final imageDirectory = Directory(imagesDirPath);
      if (!await imageDirectory.exists()) {
        await imageDirectory.create(recursive: true);
      }
      _cachedImagesDirPath = imagesDirPath;
    }
    final key =
        sha256.convert(utf8.encode(_cacheKey(ownerId, itemId))).toString();
    return File('$imagesDirPath/$key.img');
  }

  Future<File?> _readValidFile(
    String memoryKey,
    String ownerId,
    String itemId,
  ) async {
    final file = await _fileFor(ownerId, itemId);
    if (!await file.exists()) return null;
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty && bytes.length <= _maxDiskImageBytes) {
        if (!_memory.containsKey(memoryKey)) {
          _remember(ownerId, itemId, bytes);
        }
        return file;
      }
      await file.delete();
    } catch (_) {}
    return null;
  }

  Future<File?> getImage(String ownerId, String itemId) async {
    final primary = await _readValidFile(
      _cacheKey(ownerId, itemId),
      ownerId,
      itemId,
    );
    if (primary != null) return primary;

    // Fallback: check item-only cache for offline and cross-account access
    if (ownerId.trim().isNotEmpty) {
      return _readValidFile(itemId, '', itemId);
    }
    return null;
  }

  Future<File> _writeAtomically(File target, Uint8List data) {
    final key = target.path;
    final previous = _inflightWrites[key];
    Future<File> run() async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      final suffix = ++_writeCounter;
      final temporary = File('${target.path}.tmp_$suffix');
      try {
        await temporary.writeAsBytes(data, flush: true);
        if (await target.exists()) await target.delete();
        return await temporary.rename(target.path);
      } catch (_) {
        try {
          if (await temporary.exists()) await temporary.delete();
        } catch (_) {}
        rethrow;
      }
    }

    late final Future<File> tracked;
    tracked = run().whenComplete(() {
      if (_inflightWrites[key] == tracked) {
        _inflightWrites.remove(key);
      }
    });
    _inflightWrites[key] = tracked;
    return tracked;
  }

  Future<File> saveImage(String ownerId, String itemId, List<int> bytes) async {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    _remember(ownerId, itemId, data);
    final file = await _fileFor(ownerId, itemId);
    final savedFile = await _writeAtomically(file, data);

    // Also persist to generic item-only cache so offline mode always works
    if (ownerId.trim().isNotEmpty) {
      try {
        final genericFile = await _fileFor('', itemId);
        await _writeAtomically(genericFile, data);
      } catch (_) {}
    }
    revision.value++;
    return savedFile;
  }

  Future<void> removeImage(String ownerId, String itemId) async {
    _memory.remove(_cacheKey(ownerId, itemId));
    _memory.remove(itemId);
    final file = await _fileFor(ownerId, itemId);
    if (await file.exists()) await file.delete();
    if (ownerId.trim().isNotEmpty) {
      final genericFile = await _fileFor('', itemId);
      if (await genericFile.exists()) await genericFile.delete();
    }
    revision.value++;
  }

  Future<Uint8List?> ensureCached({
    required String ownerId,
    required String itemId,
    required Future<Uint8List?> Function() fetcher,
  }) {
    final mem = peekMemory(ownerId, itemId);
    if (mem != null) return Future<Uint8List?>.value(mem);

    final key = _cacheKey(ownerId, itemId);
    final existing = _inflightEnsure[key];
    if (existing != null) return existing;

    final future = _runEnsureCached(
      key: key,
      ownerId: ownerId,
      itemId: itemId,
      fetcher: fetcher,
    );
    _inflightEnsure[key] = future;
    return future;
  }

  Future<Uint8List?> _runEnsureCached({
    required String key,
    required String ownerId,
    required String itemId,
    required Future<Uint8List?> Function() fetcher,
  }) async {
    try {
      final file = await getImage(ownerId, itemId);
      if (file != null) {
        try {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            _remember(ownerId, itemId, bytes);
            return bytes;
          }
        } catch (_) {}
      }
      final remoteBytes = await fetcher();
      if (remoteBytes != null && remoteBytes.isNotEmpty) {
        await saveImage(ownerId, itemId, remoteBytes);
        return remoteBytes;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      _inflightEnsure.remove(key);
    }
  }
}
