import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'db_service.dart';

class InventoryPdfExportService {
  InventoryPdfExportService._();

  static Future<void> shareInventory({
    required List<StockItem> items,
    required String shopName,
    required double revenue,
    required double cost,
    required int unitsSold,
  }) async {
    final logoBytes = (await rootBundle.load('assets/jengabiz_mark.png'))
        .buffer
        .asUint8List();
    final logo = pw.MemoryImage(logoBytes);
    final createdAt = DateTime.now();
    final document = pw.Document();
    final totalOnHand =
        items.fold<int>(0, (sum, item) => sum + item.stockRemaining);
    final lowStockCount =
        items.where((item) => item.isLowStock || item.isOutOfStock).length;

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(26),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.blue700, width: 1.5)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Image(logo, width: 48, height: 48, fit: pw.BoxFit.contain),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('JengaBiz',
                        style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue800)),
                    pw.Text(
                        shopName.isEmpty
                            ? 'Stock and Inventory Report'
                            : shopName,
                        style: const pw.TextStyle(fontSize: 11)),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('STOCK REPORT',
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue800)),
                  pw.Text(_dateLabel(createdAt),
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey700)),
                ],
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300))),
          child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}  |  info@mftechnologies.org  |  0748329410 / 0712742991',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ),
        build: (context) => [
          pw.SizedBox(height: 14),
          pw.Row(
            children: [
              _summary('Products', '${items.length}'),
              _summary('Units on hand', '$totalOnHand'),
              _summary('Units sold', '$unitsSold'),
              _summary('Low / out of stock', '$lowStockCount'),
              _summary('Sales value', 'KES ${_money(revenue)}'),
              _summary('Cost of goods sold', 'KES ${_money(cost)}'),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text('Inventory details',
              style:
                  pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 7),
          if (items.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Text('No stock items have been added yet.'),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'ID',
                'Product',
                'Category',
                'SKU',
                'Cost (KES)',
                'Price (KES)',
                'On hand',
                'Sold',
                'Reorder at',
                'Image URL'
              ],
              data: items
                  .map((item) => [
                        item.id,
                        item.name,
                        item.category,
                        item.sku,
                        _money(item.costPrice),
                        _money(item.price),
                        '${item.stockRemaining}',
                        '${item.unitsSold}',
                        '${item.reorderLevel}',
                        item.imageUrl,
                      ])
                  .toList(),
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.blue800),
              headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 6.5),
              cellPadding:
                  const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              columnWidths: const {
                0: pw.FixedColumnWidth(58),
                1: pw.FixedColumnWidth(100),
                2: pw.FixedColumnWidth(65),
                3: pw.FixedColumnWidth(65),
                4: pw.FixedColumnWidth(58),
                5: pw.FixedColumnWidth(58),
                6: pw.FixedColumnWidth(45),
                7: pw.FixedColumnWidth(40),
                8: pw.FixedColumnWidth(50),
                9: pw.FlexColumnWidth(1.5),
              },
            ),
          pw.SizedBox(height: 10),
          pw.Text(
              'Prepared by JengaBiz | info@mftechnologies.org | 0748329410 | 0712742991',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ],
      ),
    );

    final bytes = await document.save();
    final date =
        '${createdAt.year}${createdAt.month.toString().padLeft(2, '0')}${createdAt.day.toString().padLeft(2, '0')}';
    await Printing.sharePdf(bytes: bytes, filename: 'jengabiz-stock-$date.pdf');
  }

  static pw.Widget _summary(String label, String value) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 6),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.blue50,
            borderRadius: pw.BorderRadius.circular(5),
            border: pw.Border.all(color: PdfColors.blue100),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label,
                  style: const pw.TextStyle(
                      fontSize: 7, color: PdfColors.grey700)),
              pw.SizedBox(height: 4),
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
      );

  static String _money(num value) => value.toStringAsFixed(2);

  static String _dateLabel(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}
