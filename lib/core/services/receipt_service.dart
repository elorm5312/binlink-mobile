import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../utils/formatters.dart';

class ReceiptService {
  ReceiptService._();

  static Future<void> shareReceipt(Map<String, dynamic> booking) async {
    final file = await createReceiptFile(booking);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'BinLink Eco Pickup Receipt',
    );
  }

  static Future<File> createReceiptFile(Map<String, dynamic> booking) async {
    final doc = pw.Document();

    final bookingId = booking['id'] as String? ?? 'N/A';
    final status    = booking['status'] as String? ?? '';
    final binSize   = booking['binSize'] as String? ?? '';
    final amount    = Fmt.toDouble(booking['totalAmount']);
    final extra     = (booking['extraBags'] as num?)?.toInt() ?? 0;
    final address   = booking['pickupAddress'] as String? ?? '';
    final method    = booking['paymentMethod'] as String? ?? '';
    final category  = booking['wasteCategory'] as String?;
    final date      = booking['completedAt'] as String? ?? booking['updatedAt'] as String? ?? booking['createdAt'] as String?;
    final payRef    = booking['paystackRef'] as String?;
    final weight    = Fmt.toDouble(booking['actualWeightKg'] ?? booking['estimatedWeightKg']);
    final invoice   = 'INV-${bookingId.substring(0, bookingId.length >= 8 ? 8 : bookingId.length).toUpperCase()}';
    final collectorMap = booking['collector'] as Map<String, dynamic>?;
    final collector = collectorMap?['fullName'] as String?;
    final collectorPhone = collectorMap?['phone'] as String?;
    final collectorVehicle = collectorMap?['vehicleType'] as String?;
    final beforePhotoUrl = booking['beforePhotoUrl'] as String?;
    final afterPhotoUrl = booking['afterPhotoUrl'] as String?;

    final dateStr = date != null
        ? _formatDate(date)
        : DateTime.now().toString().substring(0, 10);

    final basePrice  = _basePrice(binSize);
    final extraPrice = extra * 6.0;
    final beforeImage = await _networkImage(beforePhotoUrl);
    final afterImage = await _networkImage(afterPhotoUrl);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('BinLink Eco',
                        style: pw.TextStyle(
                          fontSize: 24, fontWeight: pw.FontWeight.bold,
                        )),
                    pw.Text('On-Demand Waste Collection',
                        style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('RECEIPT',
                        style: pw.TextStyle(
                          fontSize: 20, fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue800,
                        )),
                    pw.Text('Status: ${status.toUpperCase()}',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),

            pw.Divider(height: 40, color: PdfColors.grey300),

            // Ref + Date
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _labelValue('Invoice', invoice),
                _labelValue('Date', dateStr, align: pw.TextAlign.right),
              ],
            ),

            pw.SizedBox(height: 24),

            // Pickup details
            pw.Text('PICKUP DETAILS',
                style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey600, letterSpacing: 1.5,
                )),
            pw.SizedBox(height: 10),

            _rowItem('Booking ID', bookingId),
            if (payRef != null) _rowItem('Payment Reference', payRef),
            _rowItem('Address', address),
            if (category != null)
              _rowItem('Waste Category', category.replaceAll('_', ' ')),
            _rowItem('Bin Size', _binLabel(binSize)),
            if (weight > 0) _rowItem('Weight Collected', '${weight.toStringAsFixed(1)} kg'),
            if (collector != null)
              _rowItem('Collector', collector),
            if (collectorPhone != null)
              _rowItem('Collector Phone', collectorPhone),
            if (collectorVehicle != null)
              _rowItem('Collector Vehicle', collectorVehicle),
            _rowItem('Payment Method', _methodLabel(method)),

            pw.SizedBox(height: 24),
            if (beforeImage != null || afterImage != null) ...[
              pw.Text('PHOTO RECORD',
                  style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey600, letterSpacing: 1.5,
                  )),
              pw.SizedBox(height: 10),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (beforeImage != null)
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Before Photo', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                          pw.SizedBox(height: 6),
                          pw.Image(beforeImage, height: 120, fit: pw.BoxFit.cover),
                        ],
                      ),
                    ),
                  if (beforeImage != null && afterImage != null) pw.SizedBox(width: 12),
                  if (afterImage != null)
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('After Photo', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                          pw.SizedBox(height: 6),
                          pw.Image(afterImage, height: 120, fit: pw.BoxFit.cover),
                        ],
                      ),
                    ),
                ],
              ),
              pw.SizedBox(height: 24),
            ],
            pw.Divider(color: PdfColors.grey200),
            pw.SizedBox(height: 16),

            // Price breakdown
            pw.Text('AMOUNT BREAKDOWN',
                style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey600, letterSpacing: 1.5,
                )),
            pw.SizedBox(height: 10),

            _amountRow('Base Price (${_binLabel(binSize)})', basePrice),
            if (extra > 0)
              _amountRow('Extra Bags (${extra}x GHC 6)', extraPrice),

            pw.SizedBox(height: 8),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 8),

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('TOTAL PAID',
                    style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold,
                    )),
                pw.Text('GHC ${amount.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue800,
                    )),
              ],
            ),

            pw.Spacer(),

            // Footer
            pw.Divider(color: PdfColors.grey200),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                'Thank you for choosing BinLink Eco. Together we keep Ghana clean.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );

    final dir  = await getTemporaryDirectory();
    final file = File('${dir.path}/binlink_receipt_${bookingId.substring(0, 8)}.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  static pw.Widget _labelValue(String label, String value,
      {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Column(
      crossAxisAlignment: align == pw.TextAlign.right
          ? pw.CrossAxisAlignment.end
          : pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        pw.Text(value,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  static pw.Widget _rowItem(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 140,
            child: pw.Text(label,
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          ),
          pw.Expanded(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _amountRow(String label, double amount) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          pw.Text('GHC ${amount.toStringAsFixed(2)}',
              style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  static double _basePrice(String size) {
    switch (size.toUpperCase()) {
      case 'SMALL':  return 30.0;
      case 'MEDIUM': return 40.0;
      case 'LARGE':  return 50.0;
      default:       return 30.0;
    }
  }

  static String _binLabel(String size) {
    switch (size.toUpperCase()) {
      case 'SMALL':  return 'Small (≤120L) — GHC 30';
      case 'MEDIUM': return 'Medium (180L) — GHC 40';
      case 'LARGE':  return 'Large (240L) — GHC 50';
      default:       return size;
    }
  }

  static String _methodLabel(String method) {
    switch (method.toUpperCase()) {
      case 'MTN_MOMO':      return 'MTN MoMo';
      case 'VODAFONE_CASH': return 'Telecel Cash';
      case 'AIRTELTIGO':    return 'AirtelTigo Money';
      case 'CASH':          return 'Cash on Pickup';
      default:              return method;
    }
  }

  static String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
                'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${m[dt.month - 1]} ${dt.year}';
  }

  static Future<pw.MemoryImage?> _networkImage(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final bytes = await consolidateHttpClientResponseBytes(response);
      if (bytes.isEmpty) return null;
      return pw.MemoryImage(Uint8List.fromList(bytes));
    } catch (_) {
      return null;
    }
  }
}
