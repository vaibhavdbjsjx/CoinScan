import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../reports/coin_report_service.dart';

/// Generates the CoinScan identification report PDF.
///
/// The document is an identification record, not a certificate: it has no
/// certificate numbering or "issued" language, reports authenticity as not
/// assessed, and labels every figure with where it came from. Fields that were
/// not recorded are shown as "Not recorded" rather than filled with defaults.
class PdfGenerator {
  static const String reportTitle = 'Coin Identification Report';
  static const String authenticityLine =
      'Authenticity: not assessed. Photo recognition cannot authenticate coins '
      'or detect counterfeits.';

  /// Builds the PDF document in memory (used by [generateIdentificationReport]
  /// and by tests; pass `compress: false` to inspect the text content).
  static pw.Document buildIdentificationReport(
    CoinReportData report, {
    double? purchasePrice,
    String? purchaseCurrency,
    String? storageLocation,
    String? notes,
    bool compress = true,
  }) {
    final pdf = pw.Document(compress: compress, title: reportTitle, author: 'CoinScan');
    final generated = report.generatedAt.toLocal().toString().substring(0, 16);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'CoinScan',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#9A7B2F'),
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        reportTitle,
                        style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Text(
                    'Generated $generated',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                  ),
                ],
              ),
              pw.SizedBox(height: 14),
              pw.Divider(thickness: 0.8, color: PdfColors.grey300),
              pw.SizedBox(height: 14),
              pw.Text(
                report.title,
                style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '${report.country} • ${report.denomination}',
                style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 16),
              _section('Identification'),
              _row('Identification confidence', report.identificationConfidence),
              if (report.corroboratingChecks != null)
                _row(
                  'Details cross-checked with catalogue',
                  '${report.corroboratingChecks}',
                ),
              _row('Year (read from photo)', report.year?.toString()),
              _row('Mint mark (read from photo)', report.mintMark),
              _row('Catalogue', report.numistaReference),
              _row('Condition (recorded)', report.conditionGrade),
              pw.SizedBox(height: 6),
              pw.Text(
                authenticityLine,
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
              ),
              pw.SizedBox(height: 16),
              _section('Catalogue specifications (not measured from the coin)'),
              _row('Composition', report.composition),
              _row('Weight', report.weightG != null ? '${report.weightG} g' : null),
              _row(
                'Diameter',
                report.diameterMm != null ? '${report.diameterMm} mm' : null,
              ),
              _row('Catalogue number', report.catalogueNumber),
              pw.SizedBox(height: 16),
              _section('Value'),
              _row('Melt (bullion) value', report.meltValue),
              _row('Collector / market range', report.valuationRange),
              if (report.meltValue == null && report.valuationRange == null)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Text(
                    'No verified valuation was available for this coin.',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                  ),
                ),
              if (report.keyEvidence.isNotEmpty) ...[
                pw.SizedBox(height: 16),
                _section('Evidence'),
                for (final line in report.keyEvidence.take(12))
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 3),
                    child: pw.Text(
                      '• $line',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey900),
                    ),
                  ),
              ],
              if (purchasePrice != null ||
                  (storageLocation != null && storageLocation.isNotEmpty) ||
                  (notes != null && notes.isNotEmpty)) ...[
                pw.SizedBox(height: 16),
                _section('Owner records (entered by you)'),
                if (purchasePrice != null)
                  _row(
                    'Purchase price',
                    '${purchasePrice.toStringAsFixed(2)} ${purchaseCurrency ?? ''}'.trim(),
                  ),
                if (storageLocation != null && storageLocation.isNotEmpty)
                  _row('Storage location', storageLocation),
                if (notes != null && notes.isNotEmpty) _row('Notes', notes),
              ],
              pw.Spacer(),
              pw.Divider(thickness: 0.5, color: PdfColors.grey300),
              pw.SizedBox(height: 6),
              pw.Text(
                kReportLimitationsStatement,
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ],
          );
        },
      ),
    );
    return pdf;
  }

  /// Writes the report to the app documents directory and returns the file.
  static Future<File> generateIdentificationReport(
    CoinReportData report, {
    double? purchasePrice,
    String? purchaseCurrency,
    String? storageLocation,
    String? notes,
    Directory? outputDirectory,
  }) async {
    final pdf = buildIdentificationReport(
      report,
      purchasePrice: purchasePrice,
      purchaseCurrency: purchaseCurrency,
      storageLocation: storageLocation,
      notes: notes,
    );
    final dir = outputDirectory ?? await getApplicationDocumentsDirectory();
    final safeName = report.title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final stamp = report.generatedAt.millisecondsSinceEpoch;
    final file = File('${dir.path}/CoinScan_Identification_${safeName}_$stamp.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static pw.Widget _section(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(
        title,
        style: const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _row(String label, String? value) {
    final shown = (value == null || value.trim().isEmpty) ? 'Not recorded' : value;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 190,
            child: pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
            ),
          ),
          pw.Expanded(
            child: pw.Text(shown, style: const pw.TextStyle(fontSize: 9.5)),
          ),
        ],
      ),
    );
  }
}
