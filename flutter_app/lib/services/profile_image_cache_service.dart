import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class ProfileImageCacheEntry {
  const ProfileImageCacheEntry({
    required this.file,
    required this.imageType,
    required this.pendingUpload,
  });

  final File file;
  final String imageType;
  final bool pendingUpload;
}

class ProfileImageCacheService {
  ProfileImageCacheService._();

  static final instance = ProfileImageCacheService._();

  Future<(File image, File metadata)> _filesFor(String ownerId) async {
    final directory = await getApplicationSupportDirectory();
    final imageDirectory = Directory('${directory.path}/profile-images');
    await imageDirectory.create(recursive: true);
    final key = sha256.convert(utf8.encode(ownerId)).toString();
    return (
      File('${imageDirectory.path}/$key.img'),
      File('${imageDirectory.path}/$key.json')
    );
  }

  Future<ProfileImageCacheEntry?> read(String ownerId) async {
    final (image, metadata) = await _filesFor(ownerId);
    if (!await image.exists() || !await metadata.exists()) return null;
    final size = await image.length();
    if (size == 0 || size > 1024 * 1024) {
      await image.delete();
      await metadata.delete();
      return null;
    }
    try {
      final value = jsonDecode(await metadata.readAsString());
      if (value is! Map ||
          !const {'personal', 'shop'}.contains(value['type'])) {
        return null;
      }
      return ProfileImageCacheEntry(
        file: image,
        imageType: value['type'] as String,
        pendingUpload: value['pending'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ProfileImageCacheEntry> save(
    String ownerId, {
    required List<int> bytes,
    required String imageType,
  }) async {
    if (bytes.isEmpty || bytes.length > 1024 * 1024) {
      throw ArgumentError.value(
          bytes.length, 'bytes', 'Photo must be up to 1 MB.');
    }
    if (!const {'personal', 'shop'}.contains(imageType)) {
      throw ArgumentError.value(
          imageType, 'imageType', 'Unsupported photo type.');
    }
    final (image, metadata) = await _filesFor(ownerId);
    final temporaryImage = File('${image.path}.tmp');
    final temporaryMetadata = File('${metadata.path}.tmp');
    await temporaryImage.writeAsBytes(bytes, flush: true);
    await temporaryMetadata.writeAsString(
      jsonEncode({'type': imageType, 'pending': false}),
      flush: true,
    );
    if (await image.exists()) await image.delete();
    if (await metadata.exists()) await metadata.delete();
    await temporaryImage.rename(image.path);
    await temporaryMetadata.rename(metadata.path);
    return ProfileImageCacheEntry(
      file: image,
      imageType: imageType,
      pendingUpload: false,
    );
  }

  Future<void> remove(String ownerId) async {
    final (image, metadata) = await _filesFor(ownerId);
    if (await image.exists()) await image.delete();
    if (await metadata.exists()) await metadata.delete();
  }
}
