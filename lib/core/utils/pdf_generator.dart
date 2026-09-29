import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../storage/models.dart';

class PdfGenerator {
  static Future<File> generateCollectibleReport(
    CollectibleModel item, {
    double? purchasePrice,
    String? storageLocation,
    String? notes,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header logo banner
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'COINSCAN',
                        style: pw.TextStyle(
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#D4AF37'),
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Official Numismatic & Collectible Certificate',
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Report ID: CV-${item.id.toUpperCase().hashCode.abs()}',
                        style: const pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Issued: ${DateTime.now().toLocal().toString().substring(0, 10)}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Divider(thickness: 1, color: PdfColor.fromHex('#E5E5EA')),
              pw.SizedBox(height: 20),

              // Title Summary block
              pw.Text(
                item.name,
                style: const pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Category: ${item.category} | Origin: ${item.country} | Mint Year: ${item.year < 0 ? "${item.year.abs()} BC" : item.year}',
                style: const pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 24),

              // Stats Row
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatCell('Sheldon Grade', item.estimatedGrade),
                  _buildStatCell('Rarity Level', item.rarity.displayName),
                  _buildStatCell(
                    'Authenticity',
                    '${(item.authenticityConfidence * 100).toStringAsFixed(0)}% Match',
                  ),
                  _buildStatCell(
                    'Est. Retail',
                    '\$${item.retailPrice >= 1000 ? "${(item.retailPrice / 1000).toStringAsFixed(1)}k" : item.retailPrice}',
                  ),
                ],
              ),
              pw.SizedBox(height: 32),

              // Technical specs title
              pw.Text(
                'Technical Specifications',
                style: const pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 12),

              // Specs list table
              pw.Table(
                border: const pw.TableBorder(
                  bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                  horizontalInside: pw.BorderSide(
                    color: PdfColors.grey200,
                    width: 0.5,
                  ),
                ),
                children: [
                  _buildPdfSpecRow('Composition', item.composition),
                  _buildPdfSpecRow('Actual Weight', '${item.weightG} g'),
                  _buildPdfSpecRow('Diameter', '${item.diameterMm} mm'),
                  _buildPdfSpecRow('Thickness', '${item.thicknessMm} mm'),
                  _buildPdfSpecRow('Edge Structure', item.edgeType),
                  _buildPdfSpecRow('Mint Mark', item.mintMark),
                  _buildPdfSpecRow('Master Engraver', item.designer),
                ],
              ),
              pw.SizedBox(height: 32),

              // Historical Background
              pw.Text(
                'Historical Background',
                style: const pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                item.historicalInfo,
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey800,
                  lineSpacing: 1.5,
                ),
              ),
              pw.SizedBox(height: 32),

              // Vault / Insurance metadata block
              if (purchasePrice != null ||
                  storageLocation != null ||
                  (notes != null && notes.isNotEmpty)) ...[
                pw.Text(
                  'Owner Vault Records',
                  style: const pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#FAFAFA'),
                    border: pw.Border.all(color: PdfColor.fromHex('#E5E5EA')),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(8),
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (purchasePrice != null)
                        _buildRecordRow(
                          'Acquisition Price',
                          '\$${purchasePrice.toStringAsFixed(2)}',
                        ),
                      if (storageLocation != null)
                        _buildRecordRow(
                          'Registered Vault Storage',
                          storageLocation,
                        ),
                      if (notes != null && notes.isNotEmpty)
                        _buildRecordRow('Collector Notes', notes),
                    ],
                  ),
                ),
              ],

              // Footer page indicator and note
              pw.Spacer(),
              pw.Divider(thickness: 0.5, color: PdfColors.grey300),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'CoinScan is an estimation protocol. Catalog valuations are not financial guarantees.',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey500,
                    ),
                  ),
                  pw.Text(
                    'Page 1 of 1',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey500,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    // Save PDF to documents directory
    final outputDir = await getApplicationDocumentsDirectory();
    final file = File('${outputDir.path}/CoinScan_Report_${item.id}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static pw.Widget _buildStatCell(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: const pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static pw.TableRow _buildPdfSpecRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 6.0),
          child: pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 6.0),
          child: pw.Text(
            value,
            style: const pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
            textAlign: pw.TextAlign.right,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildRecordRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4.0),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
          pw.Text(
            value,
            style: const pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
