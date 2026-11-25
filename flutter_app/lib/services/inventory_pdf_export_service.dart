import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'api_service.dart';
import 'db_service.dart';
import 'stock_image_cache_service.dart';

typedef PdfHttpImageFetcher = Future<Uint8List?> Function(String url);

class InventoryPdfExportService {
  InventoryPdfExportService._();

  static const int _maxRemoteImageBytes = 4 * 1024 * 1024;
  static const int _maxConcurrentImageLoads = 6;
  static const Duration _remoteImageTimeout = Duration(seconds: 4);

  /// Generates a strictly black-and-white stock report PDF including
  /// grayscale product thumbnails resolved from data URIs, local cache,
  /// backend stock image API, or HTTP(S) URLs.
  static Future<Uint8List> buildInventoryPdfBytes({
    required List<StockItem> items,
    required String shopName,
    required double revenue,
    required double cost,
    required int unitsSold,
    String? ownerId,
    JengaApiService? apiService,
    PdfHttpImageFetcher? httpImageFetcher,
    DateTime? createdAt,
    bool compress = true,
  }) async {
    final logoRaw = (await rootBundle.load('assets/jengabiz_mark.png'))
        .buffer
        .asUint8List();
    final logoBytes = toGrayscaleBytes(logoRaw, maxSize: 128) ?? logoRaw;
    final logo = pw.MemoryImage(logoBytes);

    final resolvedOwnerId = ownerId ??
        JengaDB.instance.currentUser?.id ??
        JengaDB.instance.inventoryOwnerId ??
        '';
    final resolvedApi = apiService ?? JengaApiService.instance;
    final itemImages = await _resolveProductImages(
      items: items,
      ownerId: resolvedOwnerId,
      apiService: resolvedApi,
      httpImageFetcher: httpImageFetcher,
    );

    final reportTime = createdAt ?? DateTime.now();
    final document = pw.Document(compress: compress);
    final totalOnHand =
        items.fold<int>(0, (sum, item) => sum + item.stockRemaining);
    final lowStockCount =
        items.where((item) => item.isLowStock || item.isOutOfStock).length;

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.black, width: 1.5),
            ),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Image(logo, width: 44, height: 44, fit: pw.BoxFit.contain),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'JengaBiz',
                      style: pw.TextStyle(
                        fontSize: 19,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
                      ),
                    ),
                    pw.Text(
                      shopName.isEmpty
                          ? 'Stock and Inventory Report'
                          : shopName,
                      style: const pw.TextStyle(
                        fontSize: 11,
                        color: PdfColors.grey800,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'STOCK REPORT',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                    ),
                  ),
                  pw.Text(
                    _dateLabel(reportTime),
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: PdfColors.grey600, width: 0.75),
            ),
          ),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}  |  info@mftechnologies.org  |  0748329410 / 0712742991',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
        build: (context) => [
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              _summary('Products', '${items.length}'),
              _summary('Units on hand', '$totalOnHand'),
              _summary('Units sold', '$unitsSold'),
              _summary('Low / out of stock', '$lowStockCount'),
              _summary('Sales value', 'KES ${_money(revenue)}'),
              _summary('Cost of goods sold', 'KES ${_money(cost)}',
                  isLast: true),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            'Inventory details',
            style: pw.TextStyle(
              fontSize: 12.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
          pw.SizedBox(height: 6),
          if (items.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                border: pw.Border.all(color: PdfColors.grey600, width: 0.75),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                'No stock items have been added yet.',
                style: const pw.TextStyle(color: PdfColors.black),
              ),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: pw.FixedColumnWidth(48),
                1: pw.FixedColumnWidth(58),
                2: pw.FlexColumnWidth(1.6),
                3: pw.FixedColumnWidth(84),
                4: pw.FixedColumnWidth(72),
                5: pw.FixedColumnWidth(62),
                6: pw.FixedColumnWidth(62),
                7: pw.FixedColumnWidth(46),
                8: pw.FixedColumnWidth(42),
                9: pw.FixedColumnWidth(52),
              },
              children: [
                pw.TableRow(
                  repeat: true,
                  decoration: const pw.BoxDecoration(color: PdfColors.black),
                  children: [
                    _headerCell('Photo', align: pw.TextAlign.center),
                    _headerCell('ID'),
                    _headerCell('Product'),
                    _headerCell('Category'),
                    _headerCell('SKU'),
                    _headerCell('Cost (KES)', align: pw.TextAlign.right),
                    _headerCell('Price (KES)', align: pw.TextAlign.right),
                    _headerCell('On hand', align: pw.TextAlign.right),
                    _headerCell('Sold', align: pw.TextAlign.right),
                    _headerCell('Reorder at', align: pw.TextAlign.right),
                  ],
                ),
                for (var idx = 0; idx < items.length; idx++)
                  _itemRow(
                    items[idx],
                    itemImages[items[idx].imageUrl.trim()],
                    shaded: idx.isOdd,
                  ),
              ],
            ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Prepared by JengaBiz | info@mftechnologies.org | 0748329410 | 0712742991',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    return document.save();
  }

  /// Generates the black-and-white inventory PDF and opens the system share sheet.
  static Future<void> shareInventory({
    required List<StockItem> items,
    required String shopName,
    required double revenue,
    required double cost,
    required int unitsSold,
    String? ownerId,
    JengaApiService? apiService,
    PdfHttpImageFetcher? httpImageFetcher,
  }) async {
    final createdAt = DateTime.now();
    final bytes = await buildInventoryPdfBytes(
      items: items,
      shopName: shopName,
      revenue: revenue,
      cost: cost,
      unitsSold: unitsSold,
      ownerId: ownerId,
      apiService: apiService,
      httpImageFetcher: httpImageFetcher,
      createdAt: createdAt,
    );
    final date =
        '${createdAt.year}${createdAt.month.toString().padLeft(2, '0')}${createdAt.day.toString().padLeft(2, '0')}';
    await Printing.sharePdf(bytes: bytes, filename: 'jengabiz-stock-$date.pdf');
  }

  /// Decodes raw image bytes, resizes them cleanly, and converts all pixels
  /// to monochrome grayscale PNG bytes suitable for black-and-white PDF printing.
  static Uint8List? toGrayscaleBytes(
    Uint8List rawBytes, {
    int maxSize = 96,
    bool cropSquare = false,
  }) {
    if (rawBytes.isEmpty) return null;
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return null;
      final resized = cropSquare
          ? img.copyResizeCropSquare(
              decoded,
              size: maxSize,
              interpolation: img.Interpolation.average,
            )
          : (decoded.width > maxSize || decoded.height > maxSize)
              ? img.copyResize(
                  decoded,
                  width: decoded.width >= decoded.height ? maxSize : null,
                  height: decoded.height > decoded.width ? maxSize : null,
                  interpolation: img.Interpolation.average,
                )
              : decoded;
      final grayscale = img.grayscale(resized);
      return Uint8List.fromList(img.encodePng(grayscale));
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, pw.MemoryImage?>> _resolveProductImages({
    required List<StockItem> items,
    required String ownerId,
    required JengaApiService apiService,
    PdfHttpImageFetcher? httpImageFetcher,
  }) async {
    final uniqueUrls = items
        .map((item) => item.imageUrl.trim())
        .where((url) => url.isNotEmpty)
        .toSet()
        .toList();
    final results = <String, pw.MemoryImage?>{};
    for (var i = 0; i < uniqueUrls.length; i += _maxConcurrentImageLoads) {
      final end = (i + _maxConcurrentImageLoads).clamp(0, uniqueUrls.length);
      final chunk = uniqueUrls.sublist(i, end);
      await Future.wait(
        chunk.map((url) async {
          final rawBytes = await _loadImageBytes(
            url: url,
            ownerId: ownerId,
            apiService: apiService,
            httpImageFetcher: httpImageFetcher,
          );
          if (rawBytes == null || rawBytes.isEmpty) {
            results[url] = null;
            return;
          }
          final gray = toGrayscaleBytes(
            rawBytes,
            maxSize: 96,
            cropSquare: true,
          );
          results[url] = gray == null ? null : pw.MemoryImage(gray);
        }),
      );
    }
    return results;
  }

  static Future<Uint8List?> _loadImageBytes({
    required String url,
    required String ownerId,
    required JengaApiService apiService,
    PdfHttpImageFetcher? httpImageFetcher,
  }) async {
    if (url.startsWith('data:image/')) {
      final comma = url.indexOf(',');
      if (comma < 0) return null;
      try {
        return Uint8List.fromList(base64Decode(url.substring(comma + 1)));
      } catch (_) {
        return null;
      }
    }
    if (url.startsWith('stock-image:')) {
      final itemId = url.substring('stock-image:'.length);
      if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(itemId)) return null;
      if (ownerId.isNotEmpty) {
        try {
          final cached =
              await StockImageCacheService.instance.getImage(ownerId, itemId);
          if (cached != null) {
            final bytes = await cached.readAsBytes();
            if (bytes.isNotEmpty) return bytes;
          }
        } catch (_) {}
      }
      try {
        final remote = await apiService.fetchStockImage(itemId);
        if (remote != null && remote.isNotEmpty) {
          if (ownerId.isNotEmpty) {
            try {
              await StockImageCacheService.instance
                  .saveImage(ownerId, itemId, remote);
            } catch (_) {}
          }
          return remote;
        }
      } catch (_) {}
      return null;
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      if (httpImageFetcher != null) {
        try {
          return await httpImageFetcher(url);
        } catch (_) {
          return null;
        }
      }
      return _fetchHttpImageBytes(url);
    }
    return null;
  }

  static Future<Uint8List?> _fetchHttpImageBytes(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return null;
    final client = HttpClient()..connectionTimeout = _remoteImageTimeout;
    try {
      final request = await client.getUrl(uri).timeout(_remoteImageTimeout);
      request.followRedirects = true;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'image/jpeg, image/png, image/webp, image/*',
      );
      final response = await request.close().timeout(_remoteImageTimeout);
      if (response.statusCode != HttpStatus.ok ||
          response.contentLength > _maxRemoteImageBytes) {
        await response.drain<void>();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_remoteImageTimeout)) {
        if (builder.length + chunk.length > _maxRemoteImageBytes) {
          return null;
        }
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static pw.Widget _headerCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
            color: PdfColors.white,
            fontSize: 7.5,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );

  static pw.TableRow _itemRow(
    StockItem item,
    pw.MemoryImage? image, {
    required bool shaded,
  }) =>
      pw.TableRow(
        decoration: pw.BoxDecoration(
          color: shaded ? PdfColors.grey100 : PdfColors.white,
        ),
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(4),
            alignment: pw.Alignment.center,
            child: image != null
                ? pw.Container(
                    width: 34,
                    height: 34,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      border:
                          pw.Border.all(color: PdfColors.grey600, width: 0.5),
                    ),
                    child: pw.Image(image, fit: pw.BoxFit.cover),
                  )
                : pw.Container(
                    width: 34,
                    height: 34,
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      border:
                          pw.Border.all(color: PdfColors.grey600, width: 0.5),
                    ),
                    child: pw.Text(
                      'No\nphoto',
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(
                        fontSize: 5.5,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ),
          ),
          _bodyCell(item.id),
          _bodyCell(item.name, bold: true),
          _bodyCell(item.category),
          _bodyCell(item.sku),
          _bodyCell(_money(item.costPrice), align: pw.TextAlign.right),
          _bodyCell(_money(item.price), align: pw.TextAlign.right),
          _bodyCell('${item.stockRemaining}', align: pw.TextAlign.right),
          _bodyCell('${item.unitsSold}', align: pw.TextAlign.right),
          _bodyCell('${item.reorderLevel}', align: pw.TextAlign.right),
        ],
      );

  static pw.Widget _bodyCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
            fontSize: 7,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: PdfColors.black,
          ),
        ),
      );

  static pw.Widget _summary(
    String label,
    String value, {
    bool isLast = false,
  }) =>
      pw.Expanded(
        child: pw.Container(
          margin: pw.EdgeInsets.only(right: isLast ? 0 : 6),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(4),
            border: pw.Border.all(color: PdfColors.black, width: 0.75),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label,
                style:
                    const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
            ],
          ),
        ),
      );

  static String _money(num value) => value.toStringAsFixed(2);

  static String _dateLabel(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}
