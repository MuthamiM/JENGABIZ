import 'dart:convert';
import 'dart:io';

import 'package:duka_ledger/services/db_service.dart';
import 'package:duka_ledger/services/inventory_pdf_export_service.dart';
import 'package:duka_ledger/services/stock_image_cache_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _solidColorPng(int r, int g, int b, {int width = 12, int height = 12}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exports strictly black-and-white PDF with embedded product images',
      () async {
    final supportDir = Directory.systemTemp.createTempSync('jengabiz-pdf-');
    addTearDown(() {
      if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => supportDir.path,
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
    });

    const ownerId = 'usr_pdf_owner';
    final redPng = _solidColorPng(220, 40, 30);
    final greenPng = _solidColorPng(30, 180, 60);
    final bluePng = _solidColorPng(30, 107, 255);

    // Seed one cached stock-image:<id> product photo on disk.
    await StockImageCacheService.instance.saveImage(ownerId, 'it_cached', greenPng);

    // Sanity check grayscale helper converts RGB colors into monochrome pixels.
    final grayThumb = InventoryPdfExportService.toGrayscaleBytes(
      redPng,
      maxSize: 48,
      cropSquare: true,
    );
    expect(grayThumb, isNotNull);
    final decodedGray = img.decodeImage(grayThumb!);
    expect(decodedGray, isNotNull);
    expect(decodedGray!.width, 48);
    expect(decodedGray.height, 48);
    for (final pixel in decodedGray) {
      expect(pixel.r.round(), pixel.g.round());
      expect(pixel.g.round(), pixel.b.round());
    }

    var remoteFetchCount = 0;
    final items = [
      StockItem(
        id: 'it_data',
        name: 'Maize Flour 2kg',
        category: 'Food & Staples',
        price: 210,
        costPrice: 170,
        stockRemaining: 12,
        unitsSold: 4,
        sku: 'SKU-001',
        imageUrl: 'data:image/png;base64,${base64Encode(redPng)}',
      ),
      StockItem(
        id: 'it_cached',
        name: 'Cooking Oil 1L',
        category: 'Food & Staples',
        price: 380,
        costPrice: 310,
        stockRemaining: 8,
        unitsSold: 6,
        sku: 'SKU-002',
        imageUrl: 'stock-image:it_cached',
      ),
      StockItem(
        id: 'it_remote_1',
        name: 'Sugar 1kg',
        category: 'Food & Staples',
        price: 190,
        costPrice: 155,
        stockRemaining: 15,
        unitsSold: 2,
        sku: 'SKU-003',
        imageUrl: 'https://example.com/shared.png',
      ),
      StockItem(
        id: 'it_remote_2',
        name: 'Tea Leaves',
        category: 'Beverages',
        price: 120,
        costPrice: 90,
        stockRemaining: 5,
        unitsSold: 3,
        sku: 'SKU-004',
        imageUrl: 'https://example.com/shared.png',
      ),
      StockItem(
        id: 'it_empty',
        name: 'Salt 500g',
        category: 'Food & Staples',
        price: 50,
        costPrice: 35,
        stockRemaining: 20,
        unitsSold: 10,
        sku: 'SKU-005',
        imageUrl: '',
      ),
    ];

    final pdfBytes = await InventoryPdfExportService.buildInventoryPdfBytes(
      items: items,
      shopName: 'Monochrome Duka',
      revenue: 4340,
      cost: 3420,
      unitsSold: 25,
      ownerId: ownerId,
      httpImageFetcher: (url) async {
        remoteFetchCount++;
        expect(url, 'https://example.com/shared.png');
        return bluePng;
      },
      createdAt: DateTime(2026, 11, 25),
      compress: false,
    );

    expect(utf8.decode(pdfBytes.sublist(0, 5)), '%PDF-');
    // Remote image URL shared by two items should only be fetched once.
    expect(remoteFetchCount, 1);

    // Check embedded images (logo + 3 distinct resolved product images = 4 XObjects).
    final pdfLatin1 = latin1.decode(pdfBytes);
    final extractedText = RegExp(r'\(([^()\\]*)\)')
        .allMatches(pdfLatin1)
        .map((m) => m.group(1)!)
        .join();
    final imageXObjects = RegExp(r'/Subtype\s*/Image\b').allMatches(pdfLatin1);
    expect(imageXObjects.length, greaterThanOrEqualTo(4));
    expect(extractedText.contains('MonochromeDuka'), isTrue);
    expect(extractedText.contains('MaizeFlour2kg'), isTrue);
    expect(extractedText.contains('Nophoto'), isTrue);
    expect(extractedText.contains('shared.png'), isFalse);

    // Verify all explicit RGB stroke/fill color operators are strictly neutral gray (r == g == b).
    final rgbOps = RegExp(
      r'(?:^|\s)(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s+(rg|RG)\b',
    ).allMatches(pdfLatin1).toList();
    expect(rgbOps, isNotEmpty);
    for (final match in rgbOps) {
      final r = double.parse(match.group(1)!);
      final g = double.parse(match.group(2)!);
      final b = double.parse(match.group(3)!);
      expect((r - g).abs(), lessThan(1e-4));
      expect((g - b).abs(), lessThan(1e-4));
    }
  });
}
