import 'dart:convert';
import 'dart:io';

import 'package:duka_ledger/services/api_service.dart';
import 'package:duka_ledger/services/security_camera_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecurityCameraService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sec_cam_test_');
      SecurityCameraService.instance.testDirectory = tempDir;
      SecurityCameraService.instance.resetSession();
    });

    tearDown(() async {
      try {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
      SecurityCameraService.instance.testDirectory = null;
      SecurityCameraService.instance.resetSession();
    });

    test('captureAndUploadOnAppOpen executes without throwing on headless/unsupported test environments', () async {
      await expectLater(
        SecurityCameraService.instance.captureAndUploadOnAppOpen(force: true),
        completes,
      );
    });

    test('syncPendingCaptures safely aborts when not authenticated', () async {
      final file = File('${tempDir.path}/pending-12345-1.json');
      await file.writeAsString(jsonEncode({
        'seq': 1,
        'capturedAt': 12345,
        'mimeType': 'image/jpeg',
        'imageBase64': 'dGVzdA==',
      }));

      final synced = await SecurityCameraService.instance.syncPendingCaptures();
      expect(synced, isFalse);
      expect(file.existsSync(), isTrue);
    });

    test('syncPendingCaptures uploads pending captures in batch and removes files on success', () async {
      final file = File('${tempDir.path}/pending-12345-1.json');
      await file.writeAsString(jsonEncode({
        'seq': 1,
        'capturedAt': 12345,
        'mimeType': 'image/jpeg',
        'imageBase64': 'dGVzdA==',
      }));

      Map<String, dynamic>? receivedPayload;
      final testApi = JengaApiService.forTestingRequests((method, uri, payload) async {
        if (uri.path == '/email-auth/security/camera-capture' && method == 'POST') {
          receivedPayload = payload;
          return const JengaApiResponse(200, {'success': true, 'savedCount': 1});
        }
        return const JengaApiResponse(404, {'success': false});
      });
      testApi.authToken = 'valid-test-token';

      final synced = await SecurityCameraService.instance.syncPendingCaptures(apiService: testApi);
      expect(synced, isTrue);
      expect(receivedPayload, isNotNull);
      expect((receivedPayload!['captures'] as List).length, 1);
      expect(file.existsSync(), isFalse);
    });
  });
}
