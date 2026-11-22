import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class StockImageCacheService {
  StockImageCacheService._();

  static final instance = StockImageCacheService._();

  Future<File> _fileFor(String ownerId, String itemId) async {
    final directory = await getApplicationSupportDirectory();
    final imageDirectory = Directory('${directory.path}/stock-images');
    await imageDirectory.create(recursive: true);
    final key = sha256.convert(utf8.encode('$ownerId:$itemId')).toString();
    return File('${imageDirectory.path}/$key.img');
  }

  Future<File?> getImage(String ownerId, String itemId) async {
    final file = await _fileFor(ownerId, itemId);
    if (!await file.exists()) return null;
    final size = await file.length();
    if (size == 0 || size > 1024 * 1024) {
      await file.delete();
      return null;
    }
    return file;
  }

  Future<File> saveImage(String ownerId, String itemId, List<int> bytes) async {
    final file = await _fileFor(ownerId, itemId);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await file.exists()) await file.delete();
    return temporary.rename(file.path);
  }

  Future<void> removeImage(String ownerId, String itemId) async {
    final file = await _fileFor(ownerId, itemId);
    if (await file.exists()) await file.delete();
  }
}
