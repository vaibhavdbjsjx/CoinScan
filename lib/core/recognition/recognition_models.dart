export 'http_recognition_service.dart';
export '../valuation/valuation_models.dart';
export '../valuation/precious_metal.dart';
import 'dart:typed_data';

import '../valuation/precious_metal.dart';
import '../valuation/valuation_models.dart';

/// Physical side of the coin captured.
enum CaptureSide { front, reverse, edge }

/// Source of the image capture.
enum CaptureSource { camera, gallery }

/// Outcome status of the recognition pipeline.
enum RecognitionStatus {
  unavailable,
  insufficientQuality,
  lowConfidence,
  candidate,
  identified,
  unknown,
  error,
}

/// Category of evidentiary signal used to identify or verify a coin.
enum RecognitionEvidenceType {
  visualSimilarity,
  inscription,
  year,
  denomination,
  country,
  mintMark,
  obverseReverseAgreement,
  edge,
  geometry,
  weight,
  diameter,
  composition,
}

/// Qualitative confidence strength of an evidence signal.
enum SignalStrength {
  strong,
  moderate,
  weak,
  inconsistent,
}

/// Confidence rating of an identification candidate.
enum ConfidenceLevel {
  high,
  medium,
  low,
  indeterminate,
}

/// Specific image quality flags detected during preprocessing.
enum ImageQualityIssue {
  tooBlurry,
  tooDark,
  excessiveGlare,
  resolutionTooLow,
  coinNotCentered,
  coinPartiallyCutOff,
  nonCoinDetected,
}

/// Representation of a single captured coin photograph with local metadata.
class CapturedCoinImage {
  final String path;
  final CaptureSource source;
  final CaptureSide side;
  final DateTime capturedAt;
  final int width;
  final int height;
  final int fileSizeBytes;
  final String? mimeType;

  /// The normalized JPEG, kept in memory for upload. Browsers have no file
  /// system, so on the web this is the only copy (`path` is a blob URL there).
  /// Not serialized.
  final Uint8List? bytes;

  const CapturedCoinImage({
    required this.path,
    required this.source,
    required this.side,
    required this.capturedAt,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    this.mimeType,
    this.bytes,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'source': source.name,
    'side': side.name,
    'capturedAt': capturedAt.toIso8601String(),
    'width': width,
    'height': height,
    'fileSizeBytes': fileSizeBytes,
    if (mimeType != null) 'mimeType': mimeType,
  };

  factory CapturedCoinImage.fromJson(Map<String, dynamic> json) =>
      CapturedCoinImage(
        path: json['path'] as String,
        source: CaptureSource.values.byName(json['source'] as String),
        side: CaptureSide.values.byName(json['side'] as String),
        capturedAt: DateTime.parse(json['capturedAt'] as String),
        width: json['width'] as int,
        height: json['height'] as int,
        fileSizeBytes: json['fileSizeBytes'] as int,
        mimeType: json['mimeType'] as String?,
      );
}

/// Payload sent into the recognition boundary consisting of multi-sided coin captures.
class CoinScanInput {
  final CapturedCoinImage frontImage;
  final CapturedCoinImage? reverseImage;
  final CapturedCoinImage? edgeImage;
  final String? preferredCurrency;
  final String? locale;

  const CoinScanInput({
    required this.frontImage,
    this.reverseImage,
    this.edgeImage,
    this.preferredCurrency,
    this.locale,
  });

  List<CapturedCoinImage> get images => [
    frontImage,
    if (reverseImage != null) reverseImage!,
    if (edgeImage != null) edgeImage!,
  ];
}

/// Deterministic quality assessment report for captured photos.
class ImageQualityReport {
  final bool isAcceptable;
  final double overallScore; // 0.0 to 1.0
  final List<ImageQualityIssue> issues;
  final List<String> warnings;
  final List<String> recommendedActions;

  const ImageQualityReport({
    required this.isAcceptable,
    required this.overallScore,
    this.issues = const [],
    this.warnings = const [],
    this.recommendedActions = const [],
  });

  const ImageQualityReport.pass()
    : isAcceptable = true,
      overallScore = 1.0,
      issues = const [],
      warnings = const [],
      recommendedActions = const [];

  Map<String, dynamic> toJson() => {
    'isAcceptable': isAcceptable,
    'overallScore': overallScore,
    'issues': issues.map((e) => e.name).toList(),
    'warnings': warnings,
    'recommendedActions': recommendedActions,
  };

  factory ImageQualityReport.fromJson(Map<String, dynamic> json) =>
      ImageQualityReport(
        isAcceptable: json['isAcceptable'] as bool? ?? true,
        overallScore: (json['overallScore'] as num?)?.toDouble() ?? 1.0,
        issues:
            (json['issues'] as List<dynamic>?)
                ?.map(
                  (e) => ImageQualityIssue.values.firstWhere(
                    (item) => item.name == e,
                    orElse: () => ImageQualityIssue.resolutionTooLow,
                  ),
                )
                .toList() ??
            const [],
        warnings:
            (json['warnings'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        recommendedActions:
            (json['recommendedActions'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}

/// Discrete evidentiary signal contributing to a candidate identification.
class RecognitionEvidence {
  final RecognitionEvidenceType type;
  final String label;
  final String detail;
  final String? source;
  final SignalStrength strength;
  final double? score; // Normalized 0.0 to 1.0

  const RecognitionEvidence({
    required this.type,
    required this.label,
    required this.detail,
    this.source,
    this.strength = SignalStrength.strong,
    this.score,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'label': label,
    'detail': detail,
    if (source != null) 'source': source,
    'strength': strength.name,
    if (score != null) 'score': score,
  };

  factory RecognitionEvidence.fromJson(Map<String, dynamic> json) =>
      RecognitionEvidence(
        type: RecognitionEvidenceType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => RecognitionEvidenceType.visualSimilarity,
        ),
        label: json['label'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        source: json['source'] as String?,
        strength: SignalStrength.values.firstWhere(
          (e) => e.name == json['strength'],
          orElse: () => SignalStrength.moderate,
        ),
        score: (json['score'] as num?)?.toDouble(),
      );
}

/// Comprehensive physical and historical identity of a numismatic type.
class CoinIdentity {
  final String country;
  final String denomination;
  final String? currency;
  final int? year;
  final String? mint;
  final String? variety;
  final String? composition;
  final double? weightG;
  final double? diameterMm;
  final double? thicknessMm;
  final String? edgeType;
  final String? kmNumber;
  final int? numistaId;
  final String? pcgsNumber;
  final String? historicalPeriod;
  final String? designer;

  const CoinIdentity({
    required this.country,
    required this.denomination,
    this.currency,
    this.year,
    this.mint,
    this.variety,
    this.composition,
    this.weightG,
    this.diameterMm,
    this.thicknessMm,
    this.edgeType,
    this.kmNumber,
    this.numistaId,
    this.pcgsNumber,
    this.historicalPeriod,
    this.designer,
  });

  Map<String, dynamic> toJson() => {
    'country': country,
    'denomination': denomination,
    if (currency != null) 'currency': currency,
    if (year != null) 'year': year,
    if (mint != null) 'mint': mint,
    if (variety != null) 'variety': variety,
    if (composition != null) 'composition': composition,
    if (weightG != null) 'weightG': weightG,
    if (diameterMm != null) 'diameterMm': diameterMm,
    if (thicknessMm != null) 'thicknessMm': thicknessMm,
    if (edgeType != null) 'edgeType': edgeType,
    if (kmNumber != null) 'kmNumber': kmNumber,
    if (numistaId != null) 'numistaId': numistaId,
    if (pcgsNumber != null) 'pcgsNumber': pcgsNumber,
    if (historicalPeriod != null) 'historicalPeriod': historicalPeriod,
    if (designer != null) 'designer': designer,
  };

  factory CoinIdentity.fromJson(Map<String, dynamic> json) => CoinIdentity(
    country: json['country'] as String? ?? 'Unknown',
    denomination: json['denomination'] as String? ?? 'Unknown',
    currency: json['currency'] as String?,
    year: json['year'] as int?,
    mint: json['mint'] as String?,
    variety: json['variety'] as String?,
    composition: json['composition'] as String?,
    weightG: (json['weightG'] as num?)?.toDouble(),
    diameterMm: (json['diameterMm'] as num?)?.toDouble(),
    thicknessMm: (json['thicknessMm'] as num?)?.toDouble(),
    edgeType: json['edgeType'] as String?,
    kmNumber: json['kmNumber'] as String?,
    numistaId: json['numistaId'] as int?,
    pcgsNumber: json['pcgsNumber'] as String?,
    historicalPeriod: json['historicalPeriod'] as String?,
    designer: json['designer'] as String?,
  );
}

/// Detailed multi-signal confidence metric with transparent component scoring.
class RecognitionConfidence {
  final ConfidenceLevel level;
  final double overallScore; // 0.0 to 1.0 (weighted composite)
  final double visualScore;
  final double ocrScore;
  final double metadataScore;
  final String explanation;

  /// How many details read from the photo were independently confirmed against
  /// the catalogue record (year range, mint mark, denomination legend).
  final int corroboratingChecks;

  const RecognitionConfidence({
    required this.level,
    required this.overallScore,
    this.visualScore = 0.0,
    this.ocrScore = 0.0,
    this.metadataScore = 0.0,
    required this.explanation,
    this.corroboratingChecks = 0,
  });

  /// Derives qualitative confidence tier from weighted score.
  factory RecognitionConfidence.fromScores({
    required double visualScore,
    required double ocrScore,
    required double metadataScore,
    String? customExplanation,
  }) {
    // Weighted formula: Visual (45%), OCR (30%), Metadata agreement (25%)
    final composite =
        (visualScore * 0.45) + (ocrScore * 0.30) + (metadataScore * 0.25);
    final clamped = composite.clamp(0.0, 1.0);

    final ConfidenceLevel level;
    final String explanation;

    if (clamped >= 0.85) {
      level = ConfidenceLevel.high;
      explanation =
          customExplanation ??
          'Strong visual and inscription agreement across both sides.';
    } else if (clamped >= 0.60) {
      level = ConfidenceLevel.medium;
      explanation =
          customExplanation ??
          'Likely match. Visual characteristics align, but some variety details require verification.';
    } else if (clamped >= 0.35) {
      level = ConfidenceLevel.low;
      explanation =
          customExplanation ??
          'Possible match with partial evidence. Multiple candidate varieties exist.';
    } else {
      level = ConfidenceLevel.indeterminate;
      explanation =
          customExplanation ??
          'Insufficient evidence to distinguish this coin with certainty.';
    }

    return RecognitionConfidence(
      level: level,
      overallScore: clamped,
      visualScore: visualScore,
      ocrScore: ocrScore,
      metadataScore: metadataScore,
      explanation: explanation,
    );
  }

  /// Plain-language honest explanation of the confidence level without AI exaggeration.
  String get honestExplanation {
    switch (level) {
      case ConfidenceLevel.high:
        return 'Strong match: several details read from your photos agree with the catalogue record. This identifies the coin type only; it does not authenticate the coin.';
      case ConfidenceLevel.medium:
        return 'Probable match: some details agree with the catalogue record, but the variety or mint still needs confirmation.';
      case ConfidenceLevel.low:
        return 'Possible match only: little or none of what was read from the photo could be cross-checked against the catalogue.';
      case ConfidenceLevel.indeterminate:
        return 'Uncertain: the photo does not contain enough readable detail to identify a specific coin type.';
    }
  }

  /// The server's explanation when present, otherwise the plain-language fallback.
  String get displayExplanation =>
      explanation.trim().isNotEmpty ? explanation : honestExplanation;

  Map<String, dynamic> toJson() => {
    'level': level.name,
    'overallScore': overallScore,
    'visualScore': visualScore,
    'ocrScore': ocrScore,
    'metadataScore': metadataScore,
    'explanation': explanation,
    'corroboratingChecks': corroboratingChecks,
  };

  factory RecognitionConfidence.fromJson(Map<String, dynamic> json) =>
      RecognitionConfidence(
        level: ConfidenceLevel.values.firstWhere(
          (e) => e.name == json['level'],
          orElse: () => ConfidenceLevel.indeterminate,
        ),
        overallScore: (json['overallScore'] as num?)?.toDouble() ?? 0.0,
        visualScore: (json['visualScore'] as num?)?.toDouble() ?? 0.0,
        ocrScore: (json['ocrScore'] as num?)?.toDouble() ?? 0.0,
        metadataScore: (json['metadataScore'] as num?)?.toDouble() ?? 0.0,
        explanation: json['explanation'] as String? ?? '',
        corroboratingChecks:
            (json['corroboratingChecks'] as num?)?.toInt() ?? 0,
      );
}

/// A ranked candidate match returned by the recognition pipeline.
class RecognitionCandidate {
  final String coinId;
  final CoinIdentity identity;
  final String providerName;
  final RecognitionConfidence? confidence;
  final List<RecognitionEvidence> evidence;
  final int rank;
  final String? conditionGrade;

  // Direct backwards-compatible getters
  String get country => identity.country;
  String get denomination => identity.denomination;
  String? get currency => identity.currency;
  int? get year => identity.year;
  String? get mint => identity.mint;
  double? get providerConfidence => confidence?.overallScore;

  /// Cleanly formatted numismatic title (e.g. "1957 United Kingdom 1 Penny")
  String get formattedTitle {
    final yearStr = identity.year != null ? '${identity.year} ' : '';
    return '$yearStr${identity.country} ${identity.denomination}';
  }

  /// Explicitly stated precious-metal content of the composition, if any.
  /// Keyword matches ("Nordic gold", "nickel silver", plated) do not count.
  PreciousMetalContent? get preciousMetal =>
      PreciousMetalContent.parse(identity.composition);

  /// Whether the composition explicitly states gold, silver or platinum content.
  bool get hasPreciousMetal => preciousMetal != null;

  /// Name of the explicitly stated precious metal, if any.
  String? get preciousMetalType => preciousMetal?.displayName;

  /// Flag indicating potential collectible/rarity interest (scarce mint mark, precious metal, or vintage)
  bool get isWorthCloserLook {
    if (hasPreciousMetal) return true;
    if (identity.mint != null && identity.mint!.isNotEmpty) return true;
    if (identity.year != null && identity.year! < 1950) return true;
    if (confidence?.level == ConfidenceLevel.medium) return true;
    return false;
  }

  const RecognitionCandidate({
    required this.coinId,
    required this.identity,
    required this.providerName,
    this.confidence,
    this.evidence = const [],
    this.rank = 1,
    this.conditionGrade,
  });

  /// Convenient backward-compatible constructor for flat fields
  RecognitionCandidate.flat({
    required String coinId,
    required String country,
    required String denomination,
    required String providerName,
    String? currency,
    int? year,
    String? mint,
    double? providerConfidence,
    List<RecognitionEvidence> evidence = const [],
    int rank = 1,
  }) : this(
         coinId: coinId,
         identity: CoinIdentity(
           country: country,
           denomination: denomination,
           currency: currency,
           year: year,
           mint: mint,
         ),
         providerName: providerName,
         confidence:
             providerConfidence != null
                 ? RecognitionConfidence.fromScores(
                   visualScore: providerConfidence,
                   ocrScore: providerConfidence,
                   metadataScore: providerConfidence,
                 )
                 : null,
         evidence: evidence,
         rank: rank,
       );

  Map<String, dynamic> toJson() => {
    'coinId': coinId,
    'identity': identity.toJson(),
    'providerName': providerName,
    if (confidence != null) 'confidence': confidence!.toJson(),
    'evidence': evidence.map((e) => e.toJson()).toList(),
    'rank': rank,
    if (conditionGrade != null) 'conditionGrade': conditionGrade,
  };

  factory RecognitionCandidate.fromJson(Map<String, dynamic> json) {
    final identityJson = json['identity'];
    final identity =
        identityJson != null
            ? CoinIdentity.fromJson(identityJson as Map<String, dynamic>)
            : CoinIdentity(
              country: json['country'] as String? ?? 'Unknown',
              denomination: json['denomination'] as String? ?? 'Unknown',
              currency: json['currency'] as String?,
              year: json['year'] as int?,
              mint: json['mint'] as String?,
            );

    final confidenceJson = json['confidence'];
    final confidence =
        confidenceJson != null
            ? RecognitionConfidence.fromJson(
              confidenceJson as Map<String, dynamic>,
            )
            : (json['providerConfidence'] != null
                ? RecognitionConfidence.fromScores(
                  visualScore:
                      (json['providerConfidence'] as num).toDouble(),
                  ocrScore:
                      (json['providerConfidence'] as num).toDouble(),
                  metadataScore:
                      (json['providerConfidence'] as num).toDouble(),
                )
                : null);

    return RecognitionCandidate(
      coinId: json['coinId'] as String? ?? '',
      identity: identity,
      providerName: json['providerName'] as String? ?? 'CoinScan Recognition',
      confidence: confidence,
      evidence:
          (json['evidence'] as List<dynamic>?)
              ?.map(
                (e) =>
                    RecognitionEvidence.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      rank: json['rank'] as int? ?? 1,
      conditionGrade: json['conditionGrade'] as String?,
    );
  }
}

/// Unified domain response from the recognition boundary.
class RecognitionResult {
  final RecognitionStatus status;
  final String message;
  final List<RecognitionCandidate> candidates;
  final ImageQualityReport? qualityReport;
  final ValuationResult? valuation;
  final Map<String, dynamic> processingMetadata;
  final List<String> warnings;

  RecognitionCandidate? get primaryCandidate =>
      candidates.isNotEmpty ? candidates.first : null;

  String? get queryId =>
      processingMetadata['query_id'] as String? ??
      processingMetadata['queryId'] as String?;

  /// Why the service declined the scan, when it did
  /// (e.g. `guest_daily_limit_reached`, `daily_quota_exceeded`).
  String? get errorCode => processingMetadata['error_code'] as String?;

  /// The signed-out daily allowance is used up: signing in continues scanning.
  bool get guestLimitReached => errorCode == 'guest_daily_limit_reached';

  const RecognitionResult({
    required this.status,
    required this.message,
    this.candidates = const [],
    this.qualityReport,
    this.valuation,
    this.processingMetadata = const {},
    this.warnings = const [],
  });

  const RecognitionResult.unavailable({
    this.message = 'Coin recognition is not connected yet.',
  }) : status = RecognitionStatus.unavailable,
       candidates = const [],
       qualityReport = null,
       valuation = null,
       processingMetadata = const {},
       warnings = const [];

  const RecognitionResult.unknown({
    this.message =
        'We could not confidently identify this coin. Try scanning in better light with a clear view of both sides.',
    this.qualityReport,
    this.warnings = const [],
  }) : status = RecognitionStatus.unknown,
       candidates = const [],
       valuation = null,
       processingMetadata = const {};

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'message': message,
    'candidates': candidates.map((e) => e.toJson()).toList(),
    if (qualityReport != null) 'qualityReport': qualityReport!.toJson(),
    if (valuation != null) 'valuation': valuation!.toJson(),
    'processingMetadata': processingMetadata,
    'warnings': warnings,
  };

  factory RecognitionResult.fromJson(Map<String, dynamic> json) =>
      RecognitionResult(
        status: RecognitionStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => RecognitionStatus.unavailable,
        ),
        message: json['message'] as String? ?? '',
        candidates:
            (json['candidates'] as List<dynamic>?)
                ?.map(
                  (e) =>
                      RecognitionCandidate.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            const [],
        qualityReport:
            json['qualityReport'] != null
                ? ImageQualityReport.fromJson(
                  json['qualityReport'] as Map<String, dynamic>,
                )
                : null,
        valuation:
            json['valuation'] != null
                ? ValuationResult.fromJson(
                  json['valuation'] as Map<String, dynamic>,
                )
                : null,
        processingMetadata:
            (json['processingMetadata'] as Map<String, dynamic>?) ?? const {},
        warnings:
            (json['warnings'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}

/// Abstract provider interface for coin recognition.
abstract interface class RecognitionService {
  Future<RecognitionResult> recognize(CoinScanInput input);
}

/// Null provider used when no remote recognition service is configured.
class UnavailableRecognitionService implements RecognitionService {
  const UnavailableRecognitionService();

  @override
  Future<RecognitionResult> recognize(CoinScanInput input) async {
    return const RecognitionResult.unavailable();
  }
}
