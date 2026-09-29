import 'package:flutter_test/flutter_test.dart';

import 'package:coinvault_ai/core/currency/currency_models.dart';
import 'package:coinvault_ai/core/recognition/recognition_models.dart';

void main() {
  group('Recognition Domain & Confidence Tests', () {
    test('1. RecognitionConfidence derives High confidence from strong scores', () {
      final confidence = RecognitionConfidence.fromScores(
        visualScore: 0.92,
        ocrScore: 0.88,
        metadataScore: 0.90,
      );

      expect(confidence.level, ConfidenceLevel.high);
      expect(confidence.overallScore, greaterThanOrEqualTo(0.85));
      expect(confidence.visualScore, 0.92);
      expect(confidence.ocrScore, 0.88);
      expect(confidence.metadataScore, 0.90);
      expect(confidence.explanation, isNotEmpty);
    });

    test('2. RecognitionConfidence derives Medium confidence when variety details vary', () {
      final confidence = RecognitionConfidence.fromScores(
        visualScore: 0.80,
        ocrScore: 0.50,
        metadataScore: 0.60,
      );

      expect(confidence.level, ConfidenceLevel.medium);
      expect(confidence.overallScore, greaterThanOrEqualTo(0.60));
      expect(confidence.overallScore, lessThan(0.85));
    });

    test('3. RecognitionConfidence derives Low/Indeterminate when evidence is weak', () {
      final lowConfidence = RecognitionConfidence.fromScores(
        visualScore: 0.50,
        ocrScore: 0.40,
        metadataScore: 0.40,
      );
      expect(lowConfidence.level, ConfidenceLevel.low);
      expect(lowConfidence.overallScore, greaterThanOrEqualTo(0.35));
      expect(lowConfidence.overallScore, lessThan(0.60));

      final indeterminate = RecognitionConfidence.fromScores(
        visualScore: 0.20,
        ocrScore: 0.10,
        metadataScore: 0.10,
      );
      expect(indeterminate.level, ConfidenceLevel.indeterminate);
      expect(indeterminate.overallScore, lessThan(0.35));
    });

    test('4. Candidate ranking and primary candidate selection', () {
      final candidate1 = RecognitionCandidate(
        coinId: 'us_morgan_1882_cc',
        identity: const CoinIdentity(
          country: 'United States',
          denomination: '\$1',
          currency: 'USD',
          year: 1882,
          mint: 'Carson City',
          composition: '90% Silver, 10% Copper',
          weightG: 26.73,
          diameterMm: 38.1,
        ),
        providerName: 'CoinScan Hybrid Engine',
        confidence: RecognitionConfidence.fromScores(
          visualScore: 0.95,
          ocrScore: 0.90,
          metadataScore: 0.95,
        ),
        evidence: const [
          RecognitionEvidence(
            type: RecognitionEvidenceType.visualSimilarity,
            label: 'Obverse / Reverse Match',
            detail: 'Matches George T. Morgan Liberty head and eagle design.',
            strength: SignalStrength.strong,
            score: 0.95,
          ),
          RecognitionEvidence(
            type: RecognitionEvidenceType.year,
            label: 'Date 1882',
            detail: 'OCR isolated clear date 1882 on obverse rim.',
            strength: SignalStrength.strong,
            score: 0.98,
          ),
          RecognitionEvidence(
            type: RecognitionEvidenceType.mintMark,
            label: 'CC Mint Mark',
            detail: 'Carson City CC mint mark confirmed below wreath.',
            strength: SignalStrength.strong,
            score: 0.92,
          ),
        ],
        rank: 1,
      );

      final candidate2 = RecognitionCandidate(
        coinId: 'us_morgan_1882_o',
        identity: const CoinIdentity(
          country: 'United States',
          denomination: '\$1',
          currency: 'USD',
          year: 1882,
          mint: 'New Orleans',
        ),
        providerName: 'CoinScan Hybrid Engine',
        confidence: RecognitionConfidence.fromScores(
          visualScore: 0.70,
          ocrScore: 0.90,
          metadataScore: 0.60,
        ),
        rank: 2,
      );

      final result = RecognitionResult(
        status: RecognitionStatus.identified,
        message: 'Coin identified with high confidence.',
        candidates: [candidate1, candidate2],
      );

      expect(result.primaryCandidate, isNotNull);
      expect(result.primaryCandidate!.coinId, 'us_morgan_1882_cc');
      expect(result.primaryCandidate!.country, 'United States');
      expect(result.primaryCandidate!.year, 1882);
      expect(result.primaryCandidate!.mint, 'Carson City');
      expect(result.primaryCandidate!.evidence.length, 3);
      expect(result.candidates.length, 2);
    });

    test('5. Ambiguous result representation with multiple plausible varieties', () {
      final result = RecognitionResult(
        status: RecognitionStatus.candidate,
        message: 'Multiple candidate varieties detected. Scan the reverse or edge to resolve.',
        candidates: [
          RecognitionCandidate(
            coinId: 'gb_victoria_crown_1845_cinquefoil',
            identity: const CoinIdentity(
              country: 'United Kingdom',
              denomination: '1 Crown',
              year: 1845,
              edgeType: 'Lettered edge with cinquefoil stops',
            ),
            providerName: 'CoinScan Hybrid Engine',
            confidence: RecognitionConfidence.fromScores(
              visualScore: 0.75,
              ocrScore: 0.85,
              metadataScore: 0.65,
            ),
            rank: 1,
          ),
          RecognitionCandidate(
            coinId: 'gb_victoria_crown_1845_clover',
            identity: const CoinIdentity(
              country: 'United Kingdom',
              denomination: '1 Crown',
              year: 1845,
              edgeType: 'Lettered edge with clover leaf stops',
            ),
            providerName: 'CoinScan Hybrid Engine',
            confidence: RecognitionConfidence.fromScores(
              visualScore: 0.72,
              ocrScore: 0.85,
              metadataScore: 0.60,
            ),
            rank: 2,
          ),
        ],
        warnings: const ['Edge lettering required to distinguish varieties VIII vs XI.'],
      );

      expect(result.status, RecognitionStatus.candidate);
      expect(result.candidates.length, 2);
      expect(result.warnings.length, 1);
      expect(result.warnings.first, contains('Edge lettering'));
    });

    test('6. Unknown result creation and user guidance', () {
      const result = RecognitionResult.unknown(
        warnings: ['Low lighting on obverse', 'Coin rotated 45 degrees'],
      );

      expect(result.status, RecognitionStatus.unknown);
      expect(result.candidates, isEmpty);
      expect(result.primaryCandidate, isNull);
      expect(result.message, contains('could not confidently identify'));
      expect(result.warnings.length, 2);
    });

    test('7. ImageQualityReport validation and issue tracking', () {
      const badQuality = ImageQualityReport(
        isAcceptable: false,
        overallScore: 0.35,
        issues: [
          ImageQualityIssue.tooBlurry,
          ImageQualityIssue.excessiveGlare,
        ],
        warnings: ['Image is out of focus', 'Direct glare on coin center'],
        recommendedActions: ['Hold device steady', 'Diffuse strong direct lighting'],
      );

      expect(badQuality.isAcceptable, isFalse);
      expect(badQuality.issues.contains(ImageQualityIssue.tooBlurry), isTrue);
      expect(badQuality.issues.contains(ImageQualityIssue.excessiveGlare), isTrue);
      expect(badQuality.recommendedActions.length, 2);

      const passQuality = ImageQualityReport.pass();
      expect(passQuality.isAcceptable, isTrue);
      expect(passQuality.issues, isEmpty);
    });

    test('8. JSON Serialization & Deserialization round-trip for RecognitionResult', () {
      final original = RecognitionResult(
        status: RecognitionStatus.identified,
        message: 'Identified successfully',
        candidates: [
          RecognitionCandidate(
            coinId: 'grc_athens_owl_tetradrachm',
            identity: const CoinIdentity(
              country: 'Ancient Greece (Athens)',
              denomination: 'Tetradrachm',
              year: -440,
              composition: '98% Silver',
              weightG: 17.2,
              diameterMm: 24.0,
              historicalPeriod: 'Classical Athens',
            ),
            providerName: 'CoinScan Vision + Numista',
            confidence: RecognitionConfidence.fromScores(
              visualScore: 0.95,
              ocrScore: 0.70,
              metadataScore: 0.90,
            ),
            evidence: const [
              RecognitionEvidence(
                type: RecognitionEvidenceType.visualSimilarity,
                label: 'Helmeted Athena & Owl with olive sprig',
                detail: 'Full incuse square and crescent moon matches standard Attica dies.',
                strength: SignalStrength.strong,
                score: 0.96,
              ),
            ],
            rank: 1,
          ),
        ],
        qualityReport: const ImageQualityReport.pass(),
        processingMetadata: {'latencyMs': 240, 'engine': 'v1.4'},
        warnings: const [],
      );

      final json = original.toJson();
      final decoded = RecognitionResult.fromJson(json);

      expect(decoded.status, original.status);
      expect(decoded.message, original.message);
      expect(decoded.candidates.length, 1);
      expect(decoded.primaryCandidate!.coinId, 'grc_athens_owl_tetradrachm');
      expect(decoded.primaryCandidate!.identity.country, 'Ancient Greece (Athens)');
      expect(decoded.primaryCandidate!.identity.year, -440);
      expect(decoded.primaryCandidate!.confidence?.level, ConfidenceLevel.high);
      expect(decoded.primaryCandidate!.evidence.first.label, contains('Athena'));
      expect(decoded.qualityReport?.isAcceptable, isTrue);
      expect(decoded.processingMetadata['engine'], 'v1.4');
    });
  });

  group('Valuation & Market Data Tests', () {
    test('9. ValuationResult separation of collector vs melt value and comparables', () {
      final now = DateTime(2026, 8, 26);
      final valuation = ValuationResult(
        status: ValuationStatus.available,
        currencyCode: 'USD',
        updatedAt: now,
        estimates: [
          ValuationEstimate(
            type: ValuationType.metalValue,
            currencyCode: 'USD',
            low: 24.50,
            high: 25.10,
            mid: 24.80,
            valuedAt: now,
            source: 'Live Spot Feed (0.7734 oz ASW @ \$32.10/oz)',
            caveat: 'Melt value based on fine silver content only.',
            confidenceScore: 0.99,
          ),
          ValuationEstimate(
            type: ValuationType.collectorValue,
            currencyCode: 'USD',
            low: 320.0,
            high: 450.0,
            mid: 385.0,
            valuedAt: now,
            source: 'Auction Realized Indices (MS64 Grade Tier)',
            caveat: 'Collector premium depends significantly on surface strike and eye appeal.',
            comparables: [
              MarketComparable(
                source: 'Heritage Auctions',
                title: '1882-CC \$1 Morgan MS64 NGC',
                currencyCode: 'USD',
                price: 390.0,
                observedAt: DateTime(2026, 5, 14),
                gradeTier: CoinGradeTier.mintState,
              ),
              MarketComparable(
                source: 'Stack\'s Bowers',
                title: '1882-CC \$1 Morgan MS64 PCGS',
                currencyCode: 'USD',
                price: 410.0,
                observedAt: DateTime(2026, 6, 2),
                gradeTier: CoinGradeTier.mintState,
              ),
            ],
            confidenceScore: 0.88,
          ),
        ],
      );

      expect(valuation.status, ValuationStatus.available);
      expect(valuation.metalEstimate, isNotNull);
      expect(valuation.metalEstimate!.mid, 24.80);
      expect(valuation.collectorEstimate, isNotNull);
      expect(valuation.collectorEstimate!.low, 320.0);
      expect(valuation.collectorEstimate!.high, 450.0);
      expect(valuation.collectorEstimate!.comparables.length, 2);
      expect(valuation.collectorEstimate!.comparables.first.source, 'Heritage Auctions');
    });

    test('10. ValuationResult.unavailable provides truthful fallback', () {
      final unavailable = ValuationResult.unavailable(currencyCode: 'EUR');
      expect(unavailable.status, ValuationStatus.unavailable);
      expect(unavailable.estimates, isEmpty);
      expect(unavailable.collectorEstimate, isNull);
      expect(unavailable.metalEstimate, isNull);
      expect(unavailable.valuationNotes, contains('unavailable'));
    });

    test('11. ValuationResult JSON serialization round-trip', () {
      final now = DateTime(2026, 8, 26, 12, 0);
      final original = ValuationResult(
        status: ValuationStatus.available,
        currencyCode: 'USD',
        updatedAt: now,
        estimates: [
          ValuationEstimate(
            type: ValuationType.collectorValue,
            currencyCode: 'USD',
            low: 150.0,
            high: 220.0,
            mid: 185.0,
            valuedAt: now,
            source: 'Numismatic Catalogue Guide',
            caveat: 'Guide price for VF condition.',
          ),
        ],
      );

      final json = original.toJson();
      final decoded = ValuationResult.fromJson(json);

      expect(decoded.status, ValuationStatus.available);
      expect(decoded.currencyCode, 'USD');
      expect(decoded.estimates.length, 1);
      expect(decoded.collectorEstimate!.low, 150.0);
      expect(decoded.collectorEstimate!.high, 220.0);
      expect(decoded.collectorEstimate!.mid, 185.0);
    });
  });

  group('Currency Rate Service & FX Caching Tests', () {
    test('12. InMemoryCachedCurrencyService respects identity and caches conversion rates', () async {
      final service = InMemoryCachedCurrencyService(
        cacheTtl: const Duration(hours: 1),
      );

      // Identity conversion
      final identityRate = await service.getRate(
        baseCurrencyCode: 'USD',
        quoteCurrencyCode: 'USD',
      );
      expect(identityRate, isNotNull);
      expect(identityRate!.rate, 1.0);

      // Initially uncached
      final missingRate = await service.getRate(
        baseCurrencyCode: 'USD',
        quoteCurrencyCode: 'EUR',
      );
      expect(missingRate, isNull);

      // Put rate into cache
      service.putRate(
        CurrencyRate(
          baseCurrencyCode: 'USD',
          quoteCurrencyCode: 'EUR',
          rate: 0.92,
          fetchedAt: DateTime.now(),
          source: 'ECB Reference Rates',
        ),
      );

      // Cached rate retrieved
      final cachedRate = await service.getRate(
        baseCurrencyCode: 'USD',
        quoteCurrencyCode: 'EUR',
      );
      expect(cachedRate, isNotNull);
      expect(cachedRate!.rate, 0.92);

      // Conversion math
      final conversion = await service.convert(
        amount: 100.0,
        fromCurrency: 'USD',
        toCurrency: 'EUR',
      );
      expect(conversion, isNotNull);
      expect(conversion!.originalAmount, 100.0);
      expect(conversion.convertedAmount, 92.0);
      expect(conversion.fromCurrency, 'USD');
      expect(conversion.toCurrency, 'EUR');
    });

    test('13. Expired currency rate is not returned', () async {
      final service = InMemoryCachedCurrencyService(
        cacheTtl: const Duration(seconds: 1),
      );

      service.putRate(
        CurrencyRate(
          baseCurrencyCode: 'USD',
          quoteCurrencyCode: 'GBP',
          rate: 0.78,
          fetchedAt: DateTime.now().subtract(const Duration(seconds: 5)),
          source: 'Expired Feed',
        ),
      );

      final expired = await service.getRate(
        baseCurrencyCode: 'USD',
        quoteCurrencyCode: 'GBP',
      );
      expect(expired, isNull);
    });
  });
}
