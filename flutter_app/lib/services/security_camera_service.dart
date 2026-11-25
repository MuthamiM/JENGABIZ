import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api_service.dart';

class SecurityCameraService {
  static final SecurityCameraService instance = SecurityCameraService._();
  SecurityCameraService._();

  bool _isCapturing = false;
  bool _hasCapturedThisSession = false;
  Directory? _testDirectory;

  @visibleForTesting
  set testDirectory(Directory? dir) => _testDirectory = dir;

  @visibleForTesting
  void resetSession() {
    _hasCapturedThisSession = false;
    _isCapturing = false;
  }

  Future<Directory> _getStorageDirectory() async {
    if (_testDirectory != null) return _testDirectory!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/security-captures');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Triggers 3-photo camera capture and fast TeleDrive sync on app opening.
  Future<void> captureAndUploadOnAppOpen({bool force = false}) async {
    if (_isCapturing) return;
    if (!force && _hasCapturedThisSession) return;
    _isCapturing = true;
    _hasCapturedThisSession = true;

    try {
      List<CameraDescription> cameras = [];
      try {
        cameras = await availableCameras();
      } catch (e) {
        debugPrint('Security camera availableCameras: $e');
      }

      if (cameras.isNotEmpty) {
        final camera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );

        final controller = CameraController(
          camera,
          ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );

        try {
          await controller.initialize();

          final List<Map<String, dynamic>> captures = [];
          for (int i = 0; i < 3; i++) {
            try {
              final xfile = await controller.takePicture();
              final bytes = await xfile.readAsBytes();
              if (bytes.isNotEmpty) {
                captures.add({
                  'seq': i + 1,
                  'capturedAt': DateTime.now().millisecondsSinceEpoch,
                  'mimeType': 'image/jpeg',
                  'imageBase64': base64Encode(bytes),
                });
              }
              if (i < 2) {
                await Future.delayed(const Duration(milliseconds: 300));
              }
            } catch (err) {
              debugPrint('Security camera picture $i error: $err');
            }
          }

          if (captures.isNotEmpty) {
            await _persistCapturesLocally(captures);
          }
        } finally {
          try {
            await controller.dispose();
          } catch (_) {}
        }
      }

      // Fast upload to TeleDrive if authenticated and online
      await syncPendingCaptures();
    } catch (e) {
      debugPrint('Security camera session error: $e');
    } finally {
      _isCapturing = false;
    }
  }

  Future<void> _persistCapturesLocally(List<Map<String, dynamic>> captures) async {
    try {
      final dir = await _getStorageDirectory();
      for (final capture in captures) {
        final nowMs = capture['capturedAt'] ?? DateTime.now().millisecondsSinceEpoch;
        final seq = capture['seq'] ?? 1;
        final file = File('${dir.path}/pending-$nowMs-$seq.json');
        await file.writeAsString(jsonEncode(capture), flush: true);
      }
    } catch (e) {
      debugPrint('Security camera persist error: $e');
    }
  }

  /// Uploads any pending security captures to TeleDrive via backend.
  Future<bool> syncPendingCaptures({JengaApiService? apiService}) async {
    final api = apiService ?? JengaApiService.instance;
    if (api.authToken == null) {
      // Must wait for authenticated session to upload to user's TeleDrive folder
      return false;
    }

    try {
      final dir = await _getStorageDirectory();
      if (!dir.existsSync()) return true;

      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) {
            final name = f.uri.pathSegments.isNotEmpty
                ? f.uri.pathSegments.last
                : f.path.split(Platform.pathSeparator).last;
            return name.startsWith('pending-') && name.endsWith('.json');
          })
          .toList();

      if (files.isEmpty) return true;

      final List<Map<String, dynamic>> batch = [];
      final List<File> uploadedFiles = [];

      for (final file in files) {
        try {
          final content = await file.readAsString();
          final map = jsonDecode(content) as Map<String, dynamic>;
          batch.add(map);
          uploadedFiles.add(file);
        } catch (_) {
          // Bad file, remove it
          try {
            file.deleteSync();
          } catch (_) {}
        }
      }

      if (batch.isEmpty) return true;

      final res = await api.uploadSecurityCaptures(captures: batch);
      if (res?.succeeded == true) {
        for (final file in uploadedFiles) {
          try {
            file.deleteSync();
          } catch (_) {}
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Security camera sync error: $e');
      return false;
    }
  }
}
