/// Representation of an exchange rate between two ISO 4217 currency codes.
class CurrencyRate {
  final String baseCurrencyCode;
  final String quoteCurrencyCode;
  final double rate;
  final DateTime fetchedAt;
  final String source;

  const CurrencyRate({
    required this.baseCurrencyCode,
    required this.quoteCurrencyCode,
    required this.rate,
    required this.fetchedAt,
    required this.source,
  });

  bool isExpired({Duration ttl = const Duration(hours: 4)}) {
    return DateTime.now().difference(fetchedAt) > ttl;
  }

  Map<String, dynamic> toJson() => {
    'baseCurrencyCode': baseCurrencyCode,
    'quoteCurrencyCode': quoteCurrencyCode,
    'rate': rate,
    'fetchedAt': fetchedAt.toIso8601String(),
    'source': source,
  };

  factory CurrencyRate.fromJson(Map<String, dynamic> json) => CurrencyRate(
    baseCurrencyCode: json['baseCurrencyCode'] as String? ?? 'USD',
    quoteCurrencyCode: json['quoteCurrencyCode'] as String? ?? 'USD',
    rate: (json['rate'] as num?)?.toDouble() ?? 1.0,
    fetchedAt: DateTime.parse(json['fetchedAt'] as String),
    source: json['source'] as String? ?? 'FX Provider',
  );
}

/// The outcome of an exchange rate conversion operation.
class FxConversionResult {
  final double originalAmount;
  final double convertedAmount;
  final String fromCurrency;
  final String toCurrency;
  final double effectiveRate;
  final DateTime rateTimestamp;

  const FxConversionResult({
    required this.originalAmount,
    required this.convertedAmount,
    required this.fromCurrency,
    required this.toCurrency,
    required this.effectiveRate,
    required this.rateTimestamp,
  });
}

/// Service interface for retrieving FX rates.
abstract interface class CurrencyRateService {
  Future<CurrencyRate?> getRate({
    required String baseCurrencyCode,
    required String quoteCurrencyCode,
  });

  Future<FxConversionResult?> convert({
    required double amount,
    required String fromCurrency,
    required String toCurrency,
  });
}

/// In-memory cached implementation of [CurrencyRateService] that protects against excessive FX API calls.
class InMemoryCachedCurrencyService implements CurrencyRateService {
  final Map<String, CurrencyRate> _cache = {};
  final Duration cacheTtl;

  InMemoryCachedCurrencyService({
    this.cacheTtl = const Duration(hours: 4),
  });

  String _cacheKey(String base, String quote) => '${base.toUpperCase()}_${quote.toUpperCase()}';

  void putRate(CurrencyRate rate) {
    _cache[_cacheKey(rate.baseCurrencyCode, rate.quoteCurrencyCode)] = rate;
  }

  @override
  Future<CurrencyRate?> getRate({
    required String baseCurrencyCode,
    required String quoteCurrencyCode,
  }) async {
    final base = baseCurrencyCode.toUpperCase();
    final quote = quoteCurrencyCode.toUpperCase();

    if (base == quote) {
      return CurrencyRate(
        baseCurrencyCode: base,
        quoteCurrencyCode: quote,
        rate: 1.0,
        fetchedAt: DateTime.now(),
        source: 'Identity',
      );
    }

    final key = _cacheKey(base, quote);
    final cached = _cache[key];
    if (cached != null && !cached.isExpired(ttl: cacheTtl)) {
      return cached;
    }

    return null;
  }

  @override
  Future<FxConversionResult?> convert({
    required double amount,
    required String fromCurrency,
    required String toCurrency,
  }) async {
    final rate = await getRate(
      baseCurrencyCode: fromCurrency,
      quoteCurrencyCode: toCurrency,
    );
    if (rate == null) return null;

    return FxConversionResult(
      originalAmount: amount,
      convertedAmount: amount * rate.rate,
      fromCurrency: fromCurrency.toUpperCase(),
      toCurrency: toCurrency.toUpperCase(),
      effectiveRate: rate.rate,
      rateTimestamp: rate.fetchedAt,
    );
  }
}
