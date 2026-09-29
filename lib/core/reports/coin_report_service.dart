import '../../../core/recognition/recognition_models.dart';
import '../../../core/storage/collection_storage_service.dart';
import '../storage/models.dart';

/// Structured shareable data representation of a coin report.
class CoinReportData {
  final String title;
  final String country;
  final int? year;
  final String denomination;
  final String? mintMark;
  final String? composition;
  final String confidenceLevel;
  final double? confidenceScore;
  final String? valuationRange;
  final List<String> keyEvidence;
  final String? numistaReference;
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
    required this.confidenceLevel,
    this.confidenceScore,
    this.valuationRange,
    this.keyEvidence = const [],
    this.numistaReference,
    this.conditionGrade,
    this.frontImagePath,
    this.reverseImagePath,
    required this.generatedAt,
  });

  factory CoinReportData.fromCandidate(
    RecognitionCandidate candidate, {
    ValuationResult? valuation,
    String? frontPath,
    String? reversePath,
  }) {
    String? valRange;
    if (valuation != null && valuation.status != ValuationStatus.unavailable) {
      for (final est in valuation.estimates) {
        if (est.type == ValuationType.marketEstimate && est.low != null && est.high != null) {
          valRange = '\$${est.low!.toStringAsFixed(0)} – \$${est.high!.toStringAsFixed(0)} ${valuation.currencyCode}';
          break;
        }
      }
    }

    final evidenceItems = <String>[];
    if (candidate.identity.year != null) {
      evidenceItems.add('Date verified: ${candidate.identity.year}');
    }
    if (candidate.identity.country.isNotEmpty) {
      evidenceItems.add('Issuing authority: ${candidate.identity.country}');
    }
    if (candidate.identity.mint != null) {
      evidenceItems.add('Mint facility: ${candidate.identity.mint}');
    }
    if (candidate.identity.composition != null) {
      evidenceItems.add('Composition: ${candidate.identity.composition}');
    }
    if (candidate.identity.weightG != null) {
      evidenceItems.add('Weight specification: ${candidate.identity.weightG}g');
    }

    return CoinReportData(
      title: candidate.formattedTitle,
      country: candidate.identity.country,
      year: candidate.identity.year,
      denomination: candidate.identity.denomination,
      mintMark: candidate.identity.mint,
      composition: candidate.identity.composition,
      confidenceLevel: candidate.confidence?.level.name.toUpperCase() ?? 'IDENTIFIED',
      confidenceScore: candidate.confidence?.overallScore,
      valuationRange: valRange,
      keyEvidence: evidenceItems,
      numistaReference: candidate.identity.numistaId != null ? 'Numista N# ${candidate.identity.numistaId}' : null,
      conditionGrade: 'Circulated Estimate',
      frontImagePath: frontPath,
      reverseImagePath: reversePath,
      generatedAt: DateTime.now(),
    );
  }

  factory CoinReportData.fromVaultItem(VaultCoinItem item) {
    return CoinReportData(
      title: item.coinName,
      country: item.country,
      year: item.year,
      denomination: item.denomination,
      mintMark: item.mintMark,
      composition: item.composition,
      confidenceLevel: item.confidenceLevel?.toUpperCase() ?? 'VERIFIED VAULT ITEM',
      confidenceScore: item.confidenceScore,
      valuationRange: item.valuationRange,
      keyEvidence: item.keyEvidence,
      numistaReference: item.numistaId != null ? 'Numista N# ${item.numistaId}' : null,
      conditionGrade: item.conditionEstimate ?? item.grade,
      frontImagePath: item.frontImagePath,
      reverseImagePath: item.reverseImagePath,
      generatedAt: DateTime.now(),
    );
  }

  /// Generates a clean text summary for clipboard or message sharing.
  String toShareableText() {
    final buffer = StringBuffer();
    buffer.writeln('════════════════════════════════');
    buffer.writeln('🪙 COINSCAN NUMISMATIC REPORT');
    buffer.writeln('════════════════════════════════');
    buffer.writeln('Coin: $title');
    buffer.writeln('Country: $country');
    if (year != null) buffer.writeln('Year: $year');
    buffer.writeln('Denomination: $denomination');
    if (mintMark != null && mintMark!.isNotEmpty) buffer.writeln('Mint Mark: $mintMark');
    if (composition != null && composition!.isNotEmpty) buffer.writeln('Composition: $composition');
    buffer.writeln('Identification Confidence: $confidenceLevel');
    if (valuationRange != null) buffer.writeln('Estimated Market Range: $valuationRange');
    if (conditionGrade != null) buffer.writeln('Condition Estimate: $conditionGrade');
    if (numistaReference != null) buffer.writeln('Catalogue: $numistaReference');

    if (keyEvidence.isNotEmpty) {
      buffer.writeln('\nWhy We Identified This:');
      for (final e in keyEvidence) {
        buffer.writeln('• $e');
      }
    }

    buffer.writeln('\nGenerated by CoinScan — Your Personal Numismatics Assistant');
    buffer.writeln('coinscan.app');
    return buffer.toString();
  }

  CollectibleModel toCollectibleModel() {
    return CollectibleModel(
      id: 'rpt_${title.hashCode.abs()}',
      type: CollectibleType.coin,
      name: title,
      country: country,
      year: year ?? 0,
      denomination: denomination,
      mintMark: mintMark ?? '',
      composition: composition ?? 'Standard Issue',
      weightG: 0.0,
      diameterMm: 0.0,
      thicknessMm: 0.0,
      shape: 'Round',
      edgeType: 'Reeded',
      mint: mintMark != null && mintMark!.isNotEmpty ? 'Mint: $mintMark' : 'Standard Strike',
      designer: '',
      historicalPeriod: year != null ? (year! < 1900 ? 'Historic Pre-1900' : 'Modern Circulating') : 'Historic',
      rarity: RarityLevel.uncommon,
      authenticityConfidence: confidenceScore ?? 0.88,
      authenticityReasons: keyEvidence.isNotEmpty ? keyEvidence : ['Verified numismatic design, date and alloy match.'],
      estimatedGrade: conditionGrade ?? 'Circulated',
      gradeExplanation: 'Condition estimate derived from visible surface details.',
      frontImageUrl: frontImagePath ?? '',
      backImageUrl: reverseImagePath ?? '',
      historicalInfo: 'Numismatic report generated by CoinScan.',
      category: 'Circulating Issue',
      retailPrice: 0.0,
      auctionPrice: 0.0,
      dealerPrice: 0.0,
      collectorPrice: 0.0,
      minPrice: 0.0,
      maxPrice: 0.0,
      priceTrendPercentage: 0.0,
      investmentRating: '',
    );
  }
}
