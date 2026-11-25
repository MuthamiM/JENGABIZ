import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class ProfileImageCacheEntry {
  const ProfileImageCacheEntry({
    required this.file,
    required this.imageType,
    required this.pendingUpload,
    this.mimeType,
  });

  final File file;
  final String imageType;
  final bool pendingUpload;
  final String? mimeType;
}

class ProfileImageCacheService {
  ProfileImageCacheService._();

  static final instance = ProfileImageCacheService._();

  static String? detectMimeType(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71 &&
        bytes[4] == 13 &&
        bytes[5] == 10 &&
        bytes[6] == 26 &&
        bytes[7] == 10) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }

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
      final storedMime = value['mimeType'];
      final mimeType = storedMime is String &&
              const {'image/jpeg', 'image/png', 'image/webp'}
                  .contains(storedMime)
          ? storedMime
          : detectMimeType(await image.readAsBytes());
      return ProfileImageCacheEntry(
        file: image,
        imageType: value['type'] as String,
        pendingUpload: value['pending'] == true,
        mimeType: mimeType,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ProfileImageCacheEntry> save(
    String ownerId, {
    required List<int> bytes,
    required String imageType,
    String? mimeType,
    bool pendingUpload = false,
  }) async {
    if (bytes.isEmpty || bytes.length > 1024 * 1024) {
      throw ArgumentError.value(
          bytes.length, 'bytes', 'Photo must be up to 1 MB.');
    }
    if (!const {'personal', 'shop'}.contains(imageType)) {
      throw ArgumentError.value(
          imageType, 'imageType', 'Unsupported photo type.');
    }
    final resolvedMime = mimeType ?? detectMimeType(bytes);
    final (image, metadata) = await _filesFor(ownerId);
    final temporaryImage = File('${image.path}.tmp');
    final temporaryMetadata = File('${metadata.path}.tmp');
    await temporaryImage.writeAsBytes(bytes, flush: true);
    await temporaryMetadata.writeAsString(
      jsonEncode({
        'type': imageType,
        'pending': pendingUpload,
        if (resolvedMime != null) 'mimeType': resolvedMime,
      }),
      flush: true,
    );
    if (await image.exists()) await image.delete();
    if (await metadata.exists()) await metadata.delete();
    await temporaryImage.rename(image.path);
    await temporaryMetadata.rename(metadata.path);
    return ProfileImageCacheEntry(
      file: image,
      imageType: imageType,
      pendingUpload: pendingUpload,
      mimeType: resolvedMime,
    );
  }

  Future<void> remove(String ownerId) async {
    final (image, metadata) = await _filesFor(ownerId);
    if (await image.exists()) await image.delete();
    if (await metadata.exists()) await metadata.delete();
  }
}
