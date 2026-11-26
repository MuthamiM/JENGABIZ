import 'dart:io';

import 'package:duka_ledger/services/api_service.dart';
import 'package:duka_ledger/services/stock_image_cache_service.dart';
import 'package:duka_ledger/widgets/cached_stock_image.dart';
import 'package:duka_ledger/widgets/shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Valid 1x1 transparent PNG
final _samplePng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String tempDir;
  setUp(() {
    tempDir =
        '${Directory.systemTemp.path}/stock_test_${DateTime.now().microsecondsSinceEpoch}';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir,
    );
    StockImageCacheService.instance.clearMemory();
    StockImageCacheService.instance.resetDirectoryCacheForTesting();
    JengaApiService.instance.isOnline.value = true;
    JengaApiService.instance.authToken = null;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    try {
      final dir = Directory(tempDir);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('saves stock image locally and retrieves it offline', () async {
    final service = StockImageCacheService.instance;

    // Save with ownerId
    final savedFile =
        await service.saveImage('usr_owner123', 'item_test_01', _samplePng);
    expect(savedFile.existsSync(), isTrue);

    // Verify memory peek
    expect(service.peekMemory('usr_owner123', 'item_test_01'), isNotNull);
    // Verify fallback peek by itemId alone
    expect(service.peekMemory('', 'item_test_01'), isNotNull);

    // Clear memory to simulate fresh offline app launch
    service.clearMemory();
    expect(service.peekMemory('usr_owner123', 'item_test_01'), isNull);

    // Retrieve from disk cache
    final diskFile = await service.getImage('usr_owner123', 'item_test_01');
    expect(diskFile, isNotNull);
    expect(diskFile!.existsSync(), isTrue);
    expect(await diskFile.readAsBytes(), equals(_samplePng));

    // Fallback retrieval when ownerId is unknown or empty
    final genericDiskFile = await service.getImage('', 'item_test_01');
    expect(genericDiskFile, isNotNull);
    expect(genericDiskFile!.existsSync(), isTrue);
    expect(await genericDiskFile.readAsBytes(), equals(_samplePng));
  });

  test('concurrent saves on same key do not collide on temp files', () async {
    final service = StockImageCacheService.instance;
    final files = await Future.wait(
      List.generate(
        8,
        (_) => service.saveImage('usr_race', 'item_race', _samplePng),
      ),
    );
    expect(files.every((file) => file.existsSync()), isTrue);
  });

  test('ensureCached deduplicates concurrent fetchers and caches locally',
      () async {
    final service = StockImageCacheService.instance;
    int fetchCount = 0;

    Future<Uint8List?> mockFetcher() async {
      fetchCount++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return _samplePng;
    }

    final results = await Future.wait([
      service.ensureCached(
        ownerId: 'usr_owner456',
        itemId: 'item_sample_99',
        fetcher: mockFetcher,
      ),
      service.ensureCached(
        ownerId: 'usr_owner456',
        itemId: 'item_sample_99',
        fetcher: mockFetcher,
      ),
    ]);
    expect(results[0], equals(_samplePng));
    expect(results[1], equals(_samplePng));
    expect(fetchCount, 1);

    // Next call comes from memory/disk cache without invoking fetcher.
    final bytes2 = await service.ensureCached(
      ownerId: 'usr_owner456',
      itemId: 'item_sample_99',
      fetcher: mockFetcher,
    );
    expect(bytes2, equals(_samplePng));
    expect(fetchCount, 1);
  });

  testWidgets('CachedStockImage renders local cache offline without shimmer',
      (tester) async {
    JengaApiService.instance.isOnline.value = false;
    await tester.runAsync(() async {
      await StockImageCacheService.instance
          .saveImage('usr_offline', 'sample_offline_01', _samplePng);
      StockImageCacheService.instance.clearMemory();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CachedStockImage(
            imageUrl: 'stock-image:sample_offline_01',
            ownerId: 'usr_offline',
          ),
        ),
      ),
    );
    for (var i = 0; i < 16; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (find.byType(ShimmerBox).evaluate().isEmpty) break;
    }

    expect(find.byType(ShimmerBox), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets(
      'CachedStockImage shows placeholder instead of infinite shimmer when uncached offline',
      (tester) async {
    JengaApiService.instance.isOnline.value = false;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CachedStockImage(
            imageUrl: 'stock-image:missing_offline_item',
            ownerId: 'usr_offline',
          ),
        ),
      ),
    );
    for (var i = 0; i < 16; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (find.byType(ShimmerBox).evaluate().isEmpty) break;
    }

    expect(find.byType(ShimmerBox), findsNothing);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });
}
