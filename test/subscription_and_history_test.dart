import 'package:flutter_test/flutter_test.dart';

import 'package:coinvault_ai/core/config/app_config.dart';
import 'package:coinvault_ai/core/recognition/recognition_models.dart';
import 'package:coinvault_ai/core/storage/scan_history_service.dart';
import 'package:coinvault_ai/core/subscriptions/subscription_service.dart';

void main() {
  group('Phase 7: Subscription & Entitlement Service Tests', () {
    late DevSubscriptionService subService;

    setUp(() {
      subService = DevSubscriptionService();
    });

    tearDown(() {
      subService.dispose();
    });

    test('1. Default entitlement is limited with 3 daily scans', () async {
      final entitlement = await subService.currentEntitlement();
      expect(entitlement.plan, equals(EntitlementPlan.limited));
      expect(entitlement.dailyScanLimit, equals(3));
      expect(entitlement.scansUsedToday, equals(0));
      expect(entitlement.scansRemaining, equals(3));
      expect(entitlement.canScan, isTrue);
      expect(entitlement.advancedRecognitionEnabled, isFalse);
      expect(entitlement.marketValuationEnabled, isFalse);
    });

    test('2. Scan usage correctly decrements remaining quota and blocks at limit', () async {
      // Use 1 scan
      await subService.recordScanUsage();
      var entitlement = await subService.currentEntitlement();
      expect(entitlement.scansUsedToday, equals(1));
      expect(entitlement.scansRemaining, equals(2));
      expect(entitlement.canScan, isTrue);

      // Use 2nd and 3rd scans
      await subService.recordScanUsage();
      await subService.recordScanUsage();
      entitlement = await subService.currentEntitlement();
      expect(entitlement.scansUsedToday, equals(3));
      expect(entitlement.scansRemaining, equals(0));
      expect(entitlement.canScan, isFalse);
    });

    test('3. Upgrading to Plus tier grants 30 daily scans and advanced recognition', () async {
      final state = await subService.purchase('com.coinscan.plus.monthly');
      expect(state.plan, equals(EntitlementPlan.plus));
      expect(state.dailyScanLimit, equals(30));
      expect(state.advancedRecognitionEnabled, isTrue);
      expect(state.marketValuationEnabled, isFalse);
      expect(state.canScan, isTrue);
    });

    test('4. Upgrading to Pro tier grants 100 daily scans (fair-use) and market valuation', () async {
      final state = await subService.purchase('com.coinscan.pro.yearly');
      expect(state.plan, equals(EntitlementPlan.pro));
      expect(state.dailyScanLimit, equals(100));
      expect(state.scansRemaining, equals(100));
      expect(state.canScan, isTrue);
      expect(state.advancedRecognitionEnabled, isTrue);
      expect(state.marketValuationEnabled, isTrue);
    });

    test('5. Available products catalog contains all 4 standard subscription tiers', () async {
      final products = await subService.availableProducts();
      expect(products.length, equals(4));

      final productIds = products.map((p) => p.productId).toSet();
      expect(productIds, contains('com.coinscan.plus.monthly'));
      expect(productIds, contains('com.coinscan.plus.yearly'));
      expect(productIds, contains('com.coinscan.pro.monthly'));
      expect(productIds, contains('com.coinscan.pro.yearly'));
    });

    test('5b. reset() clears active subscription back to limited plan with fresh quota', () async {
      // 1. Upgrade to Pro
      await subService.purchase('com.coinscan.pro.monthly');
      var state = await subService.currentEntitlement();
      expect(state.plan, equals(EntitlementPlan.pro));

      // 2. Reset (simulates logout or account switch)
      await subService.reset();
      state = await subService.currentEntitlement();
      expect(state.plan, equals(EntitlementPlan.limited));
      expect(state.dailyScanLimit, equals(3));
      expect(state.scansUsedToday, equals(0));
      expect(state.canScan, isTrue);
      expect(state.marketValuationEnabled, isFalse);
    });

    test('5c. EntitlementState.copyWith correctly distinguishes omitted arguments from explicit null clearing (F-5)', () {
      final expiry = DateTime(2026, 12, 31);
      final initial = EntitlementState(
        plan: EntitlementPlan.pro,
        status: SubscriptionStatus.active,
        scansUsedToday: 5,
        dailyScanLimit: 100,
        advancedRecognitionEnabled: true,
        marketValuationEnabled: true,
        scanHistoryEnabled: true,
        expiresAt: expiry,
      );

      // 1. Omitted expiresAt preserves existing expiry
      final updatedScans = initial.copyWith(scansUsedToday: 6);
      expect(updatedScans.scansUsedToday, equals(6));
      expect(updatedScans.expiresAt, equals(expiry));
      expect(updatedScans.dailyScanLimit, equals(100));

      // 2. Explicitly supplied null clears expiresAt back to null
      final clearedExpiry = initial.copyWith(expiresAt: null);
      expect(clearedExpiry.expiresAt, isNull);
      expect(clearedExpiry.dailyScanLimit, equals(100));
      expect(clearedExpiry.plan, equals(EntitlementPlan.pro));

      // 3. Supplied new DateTime replaces existing expiry
      final newExpiry = DateTime(2027, 1, 15);
      final replacedExpiry = initial.copyWith(expiresAt: newExpiry);
      expect(replacedExpiry.expiresAt, equals(newExpiry));

      // 4. Explicitly supplied null clears dailyScanLimit to null
      final clearedLimit = initial.copyWith(dailyScanLimit: null);
      expect(clearedLimit.dailyScanLimit, isNull);
      expect(clearedLimit.expiresAt, equals(expiry));
    });

    test('5d. Full subscription state-machine lifecycle (FREE -> PLUS -> PRO -> CANCEL -> EXPIRE -> DOWNGRADE -> RESTORE -> LOGOUT -> SWITCH)', () async {
      // 1. Initial FREE state
      var state = await subService.currentEntitlement();
      expect(state.plan, equals(EntitlementPlan.limited));
      expect(state.status, equals(SubscriptionStatus.none));
      expect(state.expiresAt, isNull);
      expect(state.dailyScanLimit, equals(3));

      // 2. Purchase PLUS
      state = await subService.purchase('com.coinscan.plus.monthly');
      expect(state.plan, equals(EntitlementPlan.plus));
      expect(state.status, equals(SubscriptionStatus.active));
      expect(state.dailyScanLimit, equals(30));
      expect(state.expiresAt, isNotNull);

      // 3. Upgrade to PRO
      state = await subService.purchase('com.coinscan.pro.yearly');
      expect(state.plan, equals(EntitlementPlan.pro));
      expect(state.status, equals(SubscriptionStatus.active));
      expect(state.dailyScanLimit, equals(100));

      // 4. Cancellation (user cancels auto-renew; active until expiresAt)
      state = state.copyWith(status: SubscriptionStatus.cancelled);
      expect(state.status, equals(SubscriptionStatus.cancelled));
      expect(state.plan, equals(EntitlementPlan.pro));
      expect(state.canScan, isTrue);

      // 5. Expiration (grace period ends -> back to limited)
      state = state.copyWith(
        plan: EntitlementPlan.limited,
        status: SubscriptionStatus.expired,
        dailyScanLimit: TierQuota.limitedDaily,
        expiresAt: null,
      );
      expect(state.plan, equals(EntitlementPlan.limited));
      expect(state.status, equals(SubscriptionStatus.expired));
      expect(state.expiresAt, isNull);
      expect(state.dailyScanLimit, equals(3));

      // 6. Restore purchases
      final restoredState = await subService.restorePurchases();
      expect(restoredState, isNotNull);

      // 7. Logout / Account switch resets all state cleanly
      await subService.reset();
      state = await subService.currentEntitlement();
      expect(state.plan, equals(EntitlementPlan.limited));
      expect(state.status, equals(SubscriptionStatus.none));
      expect(state.expiresAt, isNull);
      expect(state.scansUsedToday, equals(0));
      expect(state.dailyScanLimit, equals(3));
      expect(state.marketValuationEnabled, isFalse);
    });
  });


  group('Phase 7: Scan History & Serialization Tests', () {
    test('6. ScanRecord serializes and deserializes accurately with JSON roundtrip', () {
      final now = DateTime(2026, 8, 26, 12, 0, 0);
      final record = ScanRecord(
        id: 'scan_123',
        scannedAt: now,
        frontImagePath: '/data/front.jpg',
        reverseImagePath: '/data/reverse.jpg',
        coinName: '1882 Morgan Dollar',
        country: 'United States',
        denomination: '1 Dollar',
        year: '1882',
        confidenceScore: 0.88,
        numistaNumber: '1492',
        statusLabel: 'identified',
      );

      final json = record.toJson();
      final reconstituted = ScanRecord.fromJson(json);

      expect(reconstituted.id, equals('scan_123'));
      expect(reconstituted.scannedAt, equals(now));
      expect(reconstituted.frontImagePath, equals('/data/front.jpg'));
      expect(reconstituted.reverseImagePath, equals('/data/reverse.jpg'));
      expect(reconstituted.coinName, equals('1882 Morgan Dollar'));
      expect(reconstituted.country, equals('United States'));
      expect(reconstituted.denomination, equals('1 Dollar'));
      expect(reconstituted.year, equals('1882'));
      expect(reconstituted.confidenceScore, closeTo(0.88, 0.001));
      expect(reconstituted.numistaNumber, equals('1492'));
      expect(reconstituted.statusLabel, equals('identified'));
    });

    test('7. ScanRecord.fromRecognitionResult constructs proper record from domain result', () {
      const candidate = RecognitionCandidate(
        coinId: 'numista_1492',
        identity: CoinIdentity(
          country: 'United States',
          denomination: '1 Dollar',
          year: 1882,
          mint: 'CC',
          numistaId: 1492,
        ),
        providerName: 'numista',
        confidence: RecognitionConfidence(
          level: ConfidenceLevel.high,
          overallScore: 0.92,
          explanation: 'Strong visual and inscription agreement.',
        ),
      );

      const result = RecognitionResult(
        status: RecognitionStatus.identified,
        message: 'High certainty match.',
        candidates: [candidate],
      );

      final record = ScanRecord.fromRecognitionResult(
        id: 'rec_456',
        result: result,
        frontImagePath: '/tmp/front.jpg',
        reverseImagePath: '/tmp/rev.jpg',
      );

      expect(record.id, equals('rec_456'));
      expect(record.coinName, equals('1882 United States 1 Dollar'));
      expect(record.country, equals('United States'));
      expect(record.denomination, equals('1 Dollar'));
      expect(record.year, equals('1882'));
      expect(record.numistaNumber, equals('1492'));
      expect(record.confidenceScore, closeTo(0.92, 0.001));
      expect(record.statusLabel, equals('identified'));
    });
  });

  group('Phase 7: AppConfig & Environment Configuration Tests', () {
    tearDown(() {
      AppConfig.reset();
    });

    test('8. AppConfig resolves local default URL in development', () {
      AppConfig.setTestConfig(
        environment: AppEnvironment.development,
        backendUrl: 'http://127.0.0.1:8080',
      );

      expect(AppConfig.instance.isDevelopment, isTrue);
      expect(AppConfig.instance.isProduction, isFalse);
      expect(AppConfig.instance.backendUrl, equals('http://127.0.0.1:8080'));
    });

    test('9. AppConfig resolves production URL in production', () {
      AppConfig.setTestConfig(
        environment: AppEnvironment.production,
        backendUrl: 'https://coinscan-backend-xyz.a.run.app',
        apiKey: 'sk_prod_key123',
      );

      expect(AppConfig.instance.isProduction, isTrue);
      expect(AppConfig.instance.backendUrl, equals('https://coinscan-backend-xyz.a.run.app'));
      expect(AppConfig.instance.apiKey, equals('sk_prod_key123'));
    });
  });
}
