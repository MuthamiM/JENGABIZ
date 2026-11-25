import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api_service.dart';

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

class ProfileImageCacheService extends ChangeNotifier {
  ProfileImageCacheService._();

  static final instance = ProfileImageCacheService._();

  String? _activeOwnerId;
  ProfileImageCacheEntry? _activeEntry;
  Uint8List? _activeBytes;
  int _revision = 0;
  String? _syncedOwnerId;
  Future<void>? _inflightSync;
  String? _inflightSyncOwner;

  int get revision => _revision;

  ProfileImageCacheEntry? entryFor(String ownerId) {
    final normalized = ownerId.trim().toLowerCase();
    if (normalized.isEmpty || _activeOwnerId != normalized) return null;
    return _activeEntry;
  }

  Uint8List? bytesFor(String ownerId) {
    final normalized = ownerId.trim().toLowerCase();
    if (normalized.isEmpty || _activeOwnerId != normalized) return null;
    return _activeBytes;
  }

  void clearMemory() {
    final hadState =
        _activeOwnerId != null || _activeEntry != null || _activeBytes != null;
    _activeOwnerId = null;
    _activeEntry = null;
    _activeBytes = null;
    _syncedOwnerId = null;
    _revision++;
    if (hadState) notifyListeners();
  }

  static bool _bytesEqual(Uint8List? left, List<int> right) {
    if (left == null || left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

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
    final normalized = ownerId.trim().toLowerCase();
    final directory = await getApplicationSupportDirectory();
    final imageDirectory = Directory('${directory.path}/profile-images');
    await imageDirectory.create(recursive: true);
    final key = sha256.convert(utf8.encode(normalized)).toString();
    return (
      File('${imageDirectory.path}/$key.img'),
      File('${imageDirectory.path}/$key.json')
    );
  }

  Future<ProfileImageCacheEntry?> read(String ownerId) async {
    final normalized = ownerId.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    try {
      final (image, metadata) = await _filesFor(normalized);
      if (!await image.exists() || !await metadata.exists()) {
        if (_activeOwnerId == normalized && _activeEntry != null) {
          _activeEntry = null;
          _activeBytes = null;
          _revision++;
          notifyListeners();
        }
        return null;
      }
      final size = await image.length();
      if (size == 0 || size > 1024 * 1024) {
        await image.delete();
        await metadata.delete();
        if (_activeOwnerId == normalized && _activeEntry != null) {
          _activeEntry = null;
          _activeBytes = null;
          _revision++;
          notifyListeners();
        }
        return null;
      }
      final value = jsonDecode(await metadata.readAsString());
      if (value is! Map ||
          !const {'personal', 'shop'}.contains(value['type'])) {
        return null;
      }
      final fileBytes = await image.readAsBytes();
      final storedMime = value['mimeType'];
      final mimeType = storedMime is String &&
              const {'image/jpeg', 'image/png', 'image/webp'}
                  .contains(storedMime)
          ? storedMime
          : detectMimeType(fileBytes);
      final entry = ProfileImageCacheEntry(
        file: image,
        imageType: value['type'] as String,
        pendingUpload: value['pending'] == true,
        mimeType: mimeType,
      );
      final changed = _activeOwnerId != normalized ||
          _activeEntry?.imageType != entry.imageType ||
          _activeEntry?.pendingUpload != entry.pendingUpload ||
          !_bytesEqual(_activeBytes, fileBytes);
      _activeOwnerId = normalized;
      _activeEntry = entry;
      _activeBytes = fileBytes;
      if (changed) {
        _revision++;
        notifyListeners();
      }
      return entry;
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
    final normalized = ownerId.trim().toLowerCase();
    if (bytes.isEmpty || bytes.length > 1024 * 1024) {
      throw ArgumentError.value(
          bytes.length, 'bytes', 'Photo must be up to 1 MB.');
    }
    if (!const {'personal', 'shop'}.contains(imageType)) {
      throw ArgumentError.value(
          imageType, 'imageType', 'Unsupported photo type.');
    }
    final resolvedMime = mimeType ?? detectMimeType(bytes);
    final (image, metadata) = await _filesFor(normalized);
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
    final entry = ProfileImageCacheEntry(
      file: image,
      imageType: imageType,
      pendingUpload: pendingUpload,
      mimeType: resolvedMime,
    );
    _activeOwnerId = normalized;
    _activeEntry = entry;
    _activeBytes = Uint8List.fromList(bytes);
    if (!pendingUpload) _syncedOwnerId = normalized;
    _revision++;
    notifyListeners();
    return entry;
  }

  Future<void> remove(String ownerId) async {
    final normalized = ownerId.trim().toLowerCase();
    try {
      final (image, metadata) = await _filesFor(normalized);
      if (await image.exists()) await image.delete();
      if (await metadata.exists()) await metadata.delete();
    } catch (_) {}
    if (_activeOwnerId == normalized || _activeOwnerId == null) {
      _activeOwnerId = normalized;
      _activeEntry = null;
      _activeBytes = null;
      _syncedOwnerId = normalized;
      _revision++;
      notifyListeners();
    }
  }

  Future<void> ensureSynced(
    String ownerId, {
    JengaApiService? api,
    bool forceRemote = false,
  }) async {
    final normalized = ownerId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    if (!forceRemote && _syncedOwnerId == normalized) return;
    if (_inflightSync != null && _inflightSyncOwner == normalized) {
      return _inflightSync!;
    }
    final future = _performSync(
      normalized,
      api: api ?? JengaApiService.instance,
    );
    _inflightSync = future;
    _inflightSyncOwner = normalized;
    try {
      await future;
    } finally {
      if (_inflightSync == future) {
        _inflightSync = null;
        _inflightSyncOwner = null;
      }
    }
  }

  Future<bool> hasPendingUpload(String ownerId) async {
    final normalized = ownerId.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    final entry = entryFor(normalized);
    if (entry != null) return entry.pendingUpload;
    final diskEntry = await read(normalized);
    return diskEntry?.pendingUpload == true;
  }

  Future<void> _performSync(
    String ownerId, {
    required JengaApiService api,
  }) async {
    final saved = await read(ownerId);
    if (api.authToken == null) return;

    if (saved != null && saved.pendingUpload) {
      try {
        final bytes = _activeOwnerId == ownerId && _activeBytes != null
            ? _activeBytes!
            : await saved.file.readAsBytes();
        final mimeType = saved.mimeType ?? detectMimeType(bytes);
        if (bytes.isEmpty || bytes.length > 1024 * 1024 || mimeType == null) {
          await remove(ownerId);
          return;
        }
        final uploaded = await api.uploadProfileImage(
          imageType: saved.imageType,
          mimeType: mimeType,
          imageData: bytes,
        );
        if (uploaded?.succeeded == true) {
          await save(
            ownerId,
            bytes: bytes,
            imageType: saved.imageType,
            mimeType: mimeType,
            pendingUpload: false,
          );
          _syncedOwnerId = ownerId;
        }
      } catch (_) {}
      return;
    }

    final remote = await api.fetchProfileImageStatus();
    if (remote.notFound) {
      if (saved != null) {
        await remove(ownerId);
      }
      _syncedOwnerId = ownerId;
      return;
    }
    final image = remote.image;
    if (image == null) return;
    _syncedOwnerId = ownerId;
    if (saved != null &&
        saved.imageType == image.imageType &&
        _bytesEqual(_activeBytes, image.bytes)) {
      return;
    }
    try {
      await save(
        ownerId,
        bytes: image.bytes,
        imageType: image.imageType,
        mimeType: image.mimeType,
        pendingUpload: false,
      );
    } catch (_) {}
  }
}
