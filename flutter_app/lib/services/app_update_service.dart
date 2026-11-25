import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _updateManifestUrl =
    'https://jengabiz.mftechnologies.org/downloads/latest.json';
const _trustedUpdateHost = 'jengabiz.mftechnologies.org';
const _updateChannel = MethodChannel('com.dukaledger.duka_ledger/app_update');

class JengaBizRelease {
  const JengaBizRelease({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.sha256,
    required this.releaseNotes,
  });

  final String versionName;
  final int versionCode;
  final Uri apkUrl;
  final String sha256;
  final List<String> releaseNotes;
}

class AppUpdateService {
  const AppUpdateService._();
  static const instance = AppUpdateService._();

  Future<Map<String, dynamic>> installedAppInfo() async {
    final result = await _updateChannel.invokeMapMethod<String, dynamic>(
      'getAppVersion',
    );
    if (result == null) {
      throw PlatformException(
        code: 'app_info_unavailable',
        message: 'The installed app version is unavailable.',
      );
    }
    return result;
  }

  Future<JengaBizRelease?> latestRelease() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request = await client
          .getUrl(Uri.parse(_updateManifestUrl))
          .timeout(const Duration(seconds: 5));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response =
          await request.close().timeout(const Duration(seconds: 5));
      if (response.statusCode != HttpStatus.ok ||
          response.contentLength > 64 * 1024) {
        return null;
      }

      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 5))) {
        if (bytes.length + chunk.length > 64 * 1024) return null;
        bytes.add(chunk);
      }
      final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (decoded is! Map) return null;

      final versionName = decoded['version_name'];
      final versionCode = decoded['version_code'];
      final apkUrl = Uri.tryParse(decoded['apk_url']?.toString() ?? '');
      final checksum = decoded['sha256']?.toString().toLowerCase() ?? '';
      if (versionName is! String ||
          versionName.trim().isEmpty ||
          versionCode is! int ||
          versionCode <= 0 ||
          apkUrl == null ||
          apkUrl.scheme != 'https' ||
          apkUrl.host.toLowerCase() != _trustedUpdateHost ||
          !apkUrl.path.endsWith('.apk') ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum)) {
        return null;
      }
      final rawNotes = decoded['release_notes'];
      final notes = rawNotes is List
          ? rawNotes
              .whereType<String>()
              .map((note) => note.trim())
              .where(
                (note) => note.isNotEmpty,
              )
              .take(8)
              .toList(growable: false)
          : const <String>[];
      return JengaBizRelease(
        versionName: versionName.trim(),
        versionCode: versionCode,
        apkUrl: apkUrl,
        sha256: checksum,
        releaseNotes: notes,
      );
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<JengaBizRelease?> availableRelease() async {
    try {
      final installed = await installedAppInfo();
      final currentCode = _asInt(installed['versionCode']);
      final latest = await latestRelease();
      if (latest == null ||
          currentCode == null ||
          latest.versionCode <= currentCode) {
        return null;
      }
      return latest;
    } on Object {
      return null;
    }
  }

  Future<bool> canInstallPackages() async {
    try {
      return await _updateChannel.invokeMethod<bool>('canInstallApk') ?? false;
    } on Object {
      return false;
    }
  }

  Future<void> openInstallSettings() =>
      _updateChannel.invokeMethod<void>('openInstallSettings');

  Future<void> installApk(String path) => _updateChannel.invokeMethod<void>(
        'installApk',
        {'path': path},
      );

  Future<String> downloadAndVerify(
    JengaBizRelease release, {
    required void Function(double progress) onProgress,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    final updateDirectory = Directory(
      '${(await getTemporaryDirectory()).path}/jengabiz_updates',
    );
    await updateDirectory.create(recursive: true);
    final file = File(
        '${updateDirectory.path}/jengabiz-update-${release.versionCode}.apk');
    try {
      final request = await client
          .getUrl(release.apkUrl)
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      request.headers.set(
          HttpHeaders.acceptHeader, 'application/vnd.android.package-archive');
      final response =
          await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.ok ||
          response.contentLength == 0 ||
          response.contentLength > 150 * 1024 * 1024) {
        throw const AppUpdateException('The update download is unavailable.');
      }

      final sink = file.openWrite();
      final digestSink = _SingleDigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      var received = 0;
      var lastReportedProgress = 0.0;
      try {
        await for (final chunk
            in response.timeout(const Duration(seconds: 30))) {
          received += chunk.length;
          if (received > 150 * 1024 * 1024) {
            throw const AppUpdateException('The update file is too large.');
          }
          sink.add(chunk);
          hasher.add(chunk);
          if (response.contentLength > 0) {
            final progress = (received / response.contentLength).clamp(0.0, 1.0);
            if (progress - lastReportedProgress >= 0.01 || progress >= 1.0) {
              lastReportedProgress = progress;
              onProgress(progress);
            }
          }
        }
        await sink.flush();
      } finally {
        hasher.close();
        await sink.close();
      }

      if (received == 0) {
        throw const AppUpdateException('The update file was empty.');
      }
      onProgress(1);
      final actualChecksum = digestSink.digest.toString();
      if (actualChecksum != release.sha256) {
        throw const AppUpdateException(
          'The downloaded update did not pass its security check. Please try again.',
        );
      }
      return file.path;
    } on AppUpdateException {
      if (await file.exists()) await file.delete();
      rethrow;
    } on Object {
      if (await file.exists()) await file.delete();
      throw const AppUpdateException(
        'Could not download the update. Check your connection and try again.',
      );
    } finally {
      client.close(force: true);
    }
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class _SingleDigestSink implements Sink<Digest> {
  late Digest digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}
