import '../../../core/recognition/recognition_models.dart';
import '../../../core/storage/collection_storage_service.dart';

/// Statement included in every shared report and PDF.
const String kReportLimitationsStatement =
    'This report records an AI-assisted identification of the coin type from '
    'photographs. It is not a certificate, an authentication, or a professional '
    'grade, and it does not confirm that the coin is genuine.';

/// Structured shareable data representation of a coin identification report.
///
/// Every field is either data recorded for this coin or explicitly absent.
/// Nothing is defaulted to make the report look more complete (no default
/// confidence, grade, rarity, "verified" evidence or valuation).
class CoinReportData {
  final String title;
  final String country;
  final int? year;
  final String denomination;
  final String? mintMark;
  final String? composition;
  final double? weightG;
  final double? diameterMm;
  final String? catalogueNumber;
  final String? numistaReference;

  /// Human-readable identification confidence ("High", "Medium", "Low",
  /// "Uncertain") or "Not recorded".
  final String identificationConfidence;

  /// Number of details cross-checked against the catalogue, when known.
  final int? corroboratingChecks;

  /// Evidence lines as recorded (label, detail and source).
  final List<String> keyEvidence;

  /// Bullion (melt) value text, e.g. "23.20 USD (spot as of 2026-09-29)".
  final String? meltValue;

  /// Collector/market range text, only when a verified price source provided one.
  final String? valuationRange;

  /// Condition grade, only when one was actually recorded.
  final String? conditionGrade;
  final String? frontImagePath;
  final String? reverseImagePath;
  final DateTime generatedAt;

  const CoinReportData({
    required this.title,
    required this.country,
    this.year,
    required this.denomination,
    this.mintMark,
    this.composition,
    this.weightG,
    this.diameterMm,
    this.catalogueNumber,
    this.numistaReference,
    required this.identificationConfidence,
    this.corroboratingChecks,
    this.keyEvidence = const [],
    this.meltValue,
    this.valuationRange,
    this.conditionGrade,
    this.frontImagePath,
    this.reverseImagePath,
    required this.generatedAt,
  });

  static String levelLabel(ConfidenceLevel level) => switch (level) {
    ConfidenceLevel.high => 'High',
    ConfidenceLevel.medium => 'Medium',
    ConfidenceLevel.low => 'Low',
    ConfidenceLevel.indeterminate => 'Uncertain',
  };

  factory CoinReportData.fromCandidate(
    RecognitionCandidate candidate, {
    ValuationResult? valuation,
    String? frontPath,
    String? reversePath,
  }) {
    String? range;
    String? melt;
    if (valuation != null) {
      final code = valuation.currencyCode;
      for (final est in valuation.estimates) {
        if ((est.type == ValuationType.marketEstimate ||
                est.type == ValuationType.collectorValue) &&
            est.low != null &&
            est.high != null &&
            range == null) {
          range =
              '${est.low!.toStringAsFixed(0)} – ${est.high!.toStringAsFixed(0)} $code';
        }
        if (est.type == ValuationType.metalValue && est.mid != null) {
          melt = '${est.mid!.toStringAsFixed(2)} $code (${est.source})';
        }
      }
    }

    final evidence = [
      for (final e in candidate.evidence)
        [
          e.label,
          if (e.detail.isNotEmpty) e.detail,
          if (e.source != null && e.source!.isNotEmpty) 'Source: ${e.source}',
        ].join(' — '),
    ];

    final id = candidate.identity;
    return CoinReportData(
      title: candidate.formattedTitle,
      country: id.country,
      year: id.year,
      denomination: id.denomination,
      mintMark: id.mint,
      composition: id.composition,
      weightG: id.weightG,
      diameterMm: id.diameterMm,
      catalogueNumber: id.kmNumber,
      numistaReference: id.numistaId != null ? 'Numista N# ${id.numistaId}' : null,
      identificationConfidence: candidate.confidence != null
          ? levelLabel(candidate.confidence!.level)
          : 'Not recorded',
      corroboratingChecks: candidate.confidence?.corroboratingChecks,
      keyEvidence: evidence,
      meltValue: melt,
      valuationRange: range,
      conditionGrade: (candidate.conditionGrade?.trim().isNotEmpty ?? false)
          ? candidate.conditionGrade
          : null,
      frontImagePath: frontPath,
      reverseImagePath: reversePath,
      generatedAt: DateTime.now(),
    );
  }

  factory CoinReportData.fromVaultItem(VaultCoinItem item) {
    final level = item.confidenceLevel?.trim();
    final grade = (item.conditionEstimate ?? item.grade)?.trim();
    return CoinReportData(
      title: item.coinName,
      country: item.country,
      year: item.year,
      denomination: item.denomination,
      mintMark: item.mintMark,
      composition: item.composition,
      weightG: item.weightG,
      diameterMm: item.diameterMm,
      catalogueNumber: item.kmNumber,
      numistaReference: item.numistaId != null ? 'Numista N# ${item.numistaId}' : null,
      identificationConfidence:
          (level != null && level.isNotEmpty) ? level : 'Not recorded',
      keyEvidence: item.keyEvidence,
      meltValue: item.meltValue != null
          ? '${item.meltValue!.toStringAsFixed(2)} ${item.currencyCode}'
          : null,
      valuationRange: item.valuationRange,
      conditionGrade: (grade != null && grade.isNotEmpty) ? grade : null,
      frontImagePath: item.frontImagePath,
      reverseImagePath: item.reverseImagePath,
      generatedAt: DateTime.now(),
    );
  }

  /// Generates a clean text summary for clipboard or message sharing.
  String toShareableText() {
    final buffer = StringBuffer();
    buffer.writeln('CoinScan identification report');
    buffer.writeln('Coin: $title');
    buffer.writeln('Country: $country');
    if (year != null) buffer.writeln('Year (read from photo): $year');
    buffer.writeln('Denomination: $denomination');
    if (mintMark != null && mintMark!.isNotEmpty) {
      buffer.writeln('Mint mark (read from photo): $mintMark');
    }
    if (composition != null && composition!.isNotEmpty) {
      buffer.writeln('Composition (catalogue): $composition');
    }
    buffer.writeln('Identification confidence: $identificationConfidence');
    buffer.writeln('Authenticity: not assessed');
    if (meltValue != null) buffer.writeln('Melt value: $meltValue');
    if (valuationRange != null) buffer.writeln('Market range: $valuationRange');
    if (conditionGrade != null) buffer.writeln('Condition (recorded): $conditionGrade');
    if (numistaReference != null) buffer.writeln('Catalogue: $numistaReference');

    if (keyEvidence.isNotEmpty) {
      buffer.writeln('\nEvidence:');
      for (final e in keyEvidence) {
        buffer.writeln('• $e');
      }
    }
    buffer.writeln('\n$kReportLimitationsStatement');
    return buffer.toString();
  }
}
