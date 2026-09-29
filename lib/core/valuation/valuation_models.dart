/// Categorization of distinct valuation dimensions for a numismatic item.
enum ValuationType {
  faceValue,
  metalValue,
  collectorValue,
  marketEstimate,
}

/// Provenance of the pricing data used to construct a valuation estimate.
enum ValuationSourceType {
  auctionHouse,
  dealerIndex,
  collectorTransaction,
  bullionSpotRate,
  numismaticCatalogue,
}

/// Status of the valuation generation.
enum ValuationStatus {
  available,
  partial,
  unavailable,
  insufficientData,
}

/// Standardized numismatic condition grading tiers.
enum CoinGradeTier {
  rawUngraded,
  good,
  veryGood,
  fine,
  veryFine,
  extremelyFine,
  aboutUncirculated,
  mintState,
  proof,
}

/// A single verified market transaction or catalogued sale comparable.
class MarketComparable {
  final String source;
  final String title;
  final String currencyCode;
  final double price;
  final DateTime observedAt;
  final String? url;
  final String? condition;
  final CoinGradeTier? gradeTier;

  const MarketComparable({
    required this.source,
    required this.title,
    required this.currencyCode,
    required this.price,
    required this.observedAt,
    this.url,
    this.condition,
    this.gradeTier,
  });

  Map<String, dynamic> toJson() => {
    'source': source,
    'title': title,
    'currencyCode': currencyCode,
    'price': price,
    'observedAt': observedAt.toIso8601String(),
    if (url != null) 'url': url,
    if (condition != null) 'condition': condition,
    if (gradeTier != null) 'gradeTier': gradeTier!.name,
  };

  factory MarketComparable.fromJson(Map<String, dynamic> json) =>
      MarketComparable(
        source: json['source'] as String? ?? 'Market Data',
        title: json['title'] as String? ?? '',
        currencyCode: json['currencyCode'] as String? ?? 'USD',
        price: (json['price'] as num?)?.toDouble() ?? 0.0,
        observedAt: DateTime.parse(json['observedAt'] as String),
        url: json['url'] as String?,
        condition: json['condition'] as String?,
        gradeTier:
            json['gradeTier'] != null
                ? CoinGradeTier.values.firstWhere(
                  (e) => e.name == json['gradeTier'],
                  orElse: () => CoinGradeTier.rawUngraded,
                )
                : null,
      );
}

/// An estimated value range computed for a single valuation aspect (e.g. melt or collector value).
class ValuationEstimate {
  final ValuationType type;
  final String currencyCode;
  final double? low;
  final double? high;
  final double? mid;
  final DateTime valuedAt;
  final String source;
  final String caveat;
  final List<MarketComparable> comparables;
  final double confidenceScore; // 0.0 to 1.0

  const ValuationEstimate({
    required this.type,
    required this.currencyCode,
    required this.valuedAt,
    required this.source,
    required this.caveat,
    this.low,
    this.high,
    this.mid,
    this.comparables = const [],
    this.confidenceScore = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'currencyCode': currencyCode,
    if (low != null) 'low': low,
    if (high != null) 'high': high,
    if (mid != null) 'mid': mid,
    'valuedAt': valuedAt.toIso8601String(),
    'source': source,
    'caveat': caveat,
    'comparables': comparables.map((e) => e.toJson()).toList(),
    'confidenceScore': confidenceScore,
  };

  factory ValuationEstimate.fromJson(Map<String, dynamic> json) =>
      ValuationEstimate(
        type: ValuationType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => ValuationType.marketEstimate,
        ),
        currencyCode: json['currencyCode'] as String? ?? 'USD',
        low: (json['low'] as num?)?.toDouble(),
        high: (json['high'] as num?)?.toDouble(),
        mid: (json['mid'] as num?)?.toDouble(),
        valuedAt: DateTime.parse(json['valuedAt'] as String),
        source: json['source'] as String? ?? 'Valuation Engine',
        caveat: json['caveat'] as String? ?? '',
        comparables:
            (json['comparables'] as List<dynamic>?)
                ?.map(
                  (e) => MarketComparable.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            const [],
        confidenceScore:
            (json['confidenceScore'] as num?)?.toDouble() ?? 1.0,
      );
}

/// Unified valuation result payload returned from the backend valuation engine.
class ValuationResult {
  final ValuationStatus status;
  final String currencyCode;
  final List<ValuationEstimate> estimates;
  final String? valuationNotes;
  final DateTime updatedAt;

  const ValuationResult({
    required this.status,
    required this.currencyCode,
    this.estimates = const [],
    this.valuationNotes,
    required this.updatedAt,
  });

  ValuationResult.unavailable({
    this.currencyCode = 'USD',
    this.valuationNotes = 'Market valuation is currently unavailable for this item.',
    DateTime? updatedAt,
  }) : status = ValuationStatus.unavailable,
       estimates = const [],
       updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  ValuationEstimate? get collectorEstimate =>
      estimates.cast<ValuationEstimate?>().firstWhere(
        (e) => e?.type == ValuationType.collectorValue,
        orElse: () => null,
      );

  ValuationEstimate? get metalEstimate =>
      estimates.cast<ValuationEstimate?>().firstWhere(
        (e) => e?.type == ValuationType.metalValue,
        orElse: () => null,
      );

  double? get marketLow => collectorEstimate?.low ?? metalEstimate?.low;
  double? get marketHigh => collectorEstimate?.high ?? metalEstimate?.high;
  double? get meltValue => metalEstimate?.mid ?? metalEstimate?.low;
  double? get catalogueValue => collectorEstimate?.mid ?? collectorEstimate?.low;
  double? get marketMid => (marketLow != null && marketHigh != null)
      ? (marketLow! + marketHigh!) / 2.0
      : (marketHigh ?? marketLow ?? catalogueValue ?? meltValue);

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'currencyCode': currencyCode,
    'estimates': estimates.map((e) => e.toJson()).toList(),
    if (valuationNotes != null) 'valuationNotes': valuationNotes,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ValuationResult.fromJson(Map<String, dynamic> json) => ValuationResult(
    status: ValuationStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => ValuationStatus.unavailable,
    ),
    currencyCode: json['currencyCode'] as String? ?? 'USD',
    estimates:
        (json['estimates'] as List<dynamic>?)
            ?.map((e) => ValuationEstimate.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
    valuationNotes: json['valuationNotes'] as String?,
    updatedAt:
        json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : DateTime.now(),
  );
}

/// Provider boundary for retrieving numismatic valuations.
abstract interface class ValuationService {
  Future<List<ValuationEstimate>> estimateForCoin(String coinId);
}

/// Default offline/unavailable valuation service.
class UnavailableValuationService implements ValuationService {
  const UnavailableValuationService();

  @override
  Future<List<ValuationEstimate>> estimateForCoin(String coinId) async {
    return const [];
  }
}
