import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class StockImageCacheService {
  StockImageCacheService._();

  static final instance = StockImageCacheService._();
  static const int _maxMemoryEntries = 64;
  final LinkedHashMap<String, Uint8List> _memory =
      LinkedHashMap<String, Uint8List>();

  String _cacheKey(String ownerId, String itemId) => '$ownerId:$itemId';

  Uint8List? peekMemory(String ownerId, String itemId) {
    final key = _cacheKey(ownerId, itemId);
    final hit = _memory.remove(key);
    if (hit == null) return null;
    _memory[key] = hit;
    return hit;
  }

  void _remember(String ownerId, String itemId, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > 1024 * 1024) return;
    final key = _cacheKey(ownerId, itemId);
    _memory.remove(key);
    _memory[key] = bytes;
    while (_memory.length > _maxMemoryEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  void clearMemory() => _memory.clear();

  Future<File> _fileFor(String ownerId, String itemId) async {
    final directory = await getApplicationSupportDirectory();
    final imageDirectory = Directory('${directory.path}/stock-images');
    await imageDirectory.create(recursive: true);
    final key =
        sha256.convert(utf8.encode(_cacheKey(ownerId, itemId))).toString();
    return File('${imageDirectory.path}/$key.img');
  }

  Future<File?> getImage(String ownerId, String itemId) async {
    final file = await _fileFor(ownerId, itemId);
    if (!await file.exists()) return null;
    final size = await file.length();
    if (size == 0 || size > 1024 * 1024) {
      await file.delete();
      _memory.remove(_cacheKey(ownerId, itemId));
      return null;
    }
    if (!_memory.containsKey(_cacheKey(ownerId, itemId))) {
      try {
        _remember(ownerId, itemId, await file.readAsBytes());
      } catch (_) {}
    }
    return file;
  }

  Future<File> saveImage(String ownerId, String itemId, List<int> bytes) async {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    _remember(ownerId, itemId, data);
    final file = await _fileFor(ownerId, itemId);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(data, flush: true);
    if (await file.exists()) await file.delete();
    return temporary.rename(file.path);
  }

  Future<void> removeImage(String ownerId, String itemId) async {
    _memory.remove(_cacheKey(ownerId, itemId));
    final file = await _fileFor(ownerId, itemId);
    if (await file.exists()) await file.delete();
  }
}
