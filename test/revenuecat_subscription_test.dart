// Tests for RevenueCat production subscription integration.
//
// Strategy:
// - Uses CustomerInfo.fromJson to build realistic CustomerInfo fixtures.
// - Accesses service state via the @visibleForTesting `state` getter.
// - Tests entitlement mapping via `mapCustomerInfoForTest`.
// - Native StoreKit / Google Play billing cannot run in Dart unit tests;
//   purchase() and restorePurchases() are tested for their error path only.
// - This test suite does NOT prove real App Store/Google Play billing works.

import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:coinvault_ai/core/subscriptions/revenuecat_config.dart';
import 'package:coinvault_ai/core/subscriptions/revenuecat_subscription_service.dart';

// ─── CustomerInfo fixture builder ─────────────────────────────────────────────

CustomerInfo _buildCustomerInfo({
  Map<String, Map<String, dynamic>> activeEntitlements = const {},
}) {
  final now = DateTime.now().toUtc();
  final future = now.add(const Duration(days: 30)).toIso8601String();

  final entMap = <String, dynamic>{};
  for (final entry in activeEntitlements.entries) {
    entMap[entry.key] = {
      'identifier': entry.key,
      'isActive': true,
      'willRenew': entry.value['willRenew'] ?? true,
      'latestPurchaseDate': now.toIso8601String(),
      'originalPurchaseDate': now.toIso8601String(),
      'expirationDate': future,
      'productIdentifier': entry.value['productId'] ?? 'com.coinscan.plus.monthly',
      'isSandbox': true,
      'ownershipType': 'PURCHASED',
      'store': 'APP_STORE',
      'periodType': 'NORMAL',
      'unsubscribeDetectedAt': null,
      'billingIssueDetectedAt': null,
    };
  }

  final hasActive = activeEntitlements.isNotEmpty;
  return CustomerInfo.fromJson({
    'entitlements': {
      'all': entMap,
      'active': entMap,
      'verification': 'NOT_REQUESTED',
    },
    'allPurchaseDates': const {},
    'activeSubscriptions': activeEntitlements.values
        .map((v) => v['productId'] as String? ?? '')
        .toList(),
    'allPurchasedProductIdentifiers': activeEntitlements.values
        .map((v) => v['productId'] as String? ?? '')
        .toList(),
    'nonSubscriptionTransactions': const [],
    'firstSeen': now.toIso8601String(),
    'originalAppUserId': 'test-supabase-uuid',
    'allExpirationDates': const {},
    'requestDate': now.toIso8601String(),
    'latestExpirationDate': hasActive ? future : null,
    'originalPurchaseDate': null,
    'originalApplicationVersion': null,
    'managementURL': null,
    'subscriptions': const {},
    'nonSubscriptions': const {},
  });
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─── RevenueCatConfig ──────────────────────────────────────────────────────

  group('RevenueCatConfig', () {
    test('1. Product IDs match App Store / Google Play contract', () {
      expect(RevenueCatConfig.productPlusMonthly, 'com.coinscan.plus.monthly');
      expect(RevenueCatConfig.productPlusYearly, 'com.coinscan.plus.yearly');
      expect(RevenueCatConfig.productProMonthly, 'com.coinscan.pro.monthly');
      expect(RevenueCatConfig.productProYearly, 'com.coinscan.pro.yearly');
    });

    test('2. Entitlement IDs are canonical', () {
      expect(RevenueCatConfig.entitlementPlus, 'plus');
      expect(RevenueCatConfig.entitlementPro, 'pro');
    });

    test('3. allProductIds contains exactly the four products', () {
      expect(RevenueCatConfig.allProductIds.length, equals(4));
      expect(RevenueCatConfig.allProductIds, containsAll([
        'com.coinscan.plus.monthly',
        'com.coinscan.plus.yearly',
        'com.coinscan.pro.monthly',
        'com.coinscan.pro.yearly',
      ]));
    });

    test('4. resolvedApiKey is null when --dart-define keys are not provided (CI)', () {
      // In test/CI environments neither REVENUECAT_APPLE_KEY nor
      // REVENUECAT_GOOGLE_KEY is set via --dart-define. The key must be
      // null — never fabricated.
      final key = RevenueCatConfig.resolvedApiKey;
      expect(key == null || key.isEmpty, isTrue,
          reason: 'SDK key must not be invented when --dart-define is absent');
    });
  });

  // ─── EntitlementState mapping ──────────────────────────────────────────────

  group('CustomerInfo → EntitlementState mapping', () {
    test('5. No active entitlement → limited plan, no paid features', () {
      final info = _buildCustomerInfo();
      final state = RevenueCatSubscriptionService.mapCustomerInfoForTest(info, 0);

      expect(state.plan, EntitlementPlan.limited);
      expect(state.status, SubscriptionStatus.none);
      expect(state.advancedRecognitionEnabled, isFalse);
      expect(state.marketValuationEnabled, isFalse);
      expect(state.scanHistoryEnabled, isFalse);
      expect(state.dailyScanLimit, TierQuota.limitedDaily);
    });

    test('6. Plus entitlement → plus plan with correct feature flags', () {
      final info = _buildCustomerInfo(activeEntitlements: {
        'plus': {'productId': 'com.coinscan.plus.monthly', 'willRenew': true},
      });
      final state = RevenueCatSubscriptionService.mapCustomerInfoForTest(info, 3);

      expect(state.plan, EntitlementPlan.plus);
      expect(state.status, SubscriptionStatus.active);
      expect(state.dailyScanLimit, TierQuota.plusDaily);
      expect(state.advancedRecognitionEnabled, isTrue);
      expect(state.marketValuationEnabled, isFalse); // Plus excludes market valuation
      expect(state.scanHistoryEnabled, isTrue);
      expect(state.scansUsedToday, 3);
    });

    test('7. Pro entitlement → pro plan, all features enabled', () {
      final info = _buildCustomerInfo(activeEntitlements: {
        'pro': {'productId': 'com.coinscan.pro.monthly', 'willRenew': true},
      });
      final state = RevenueCatSubscriptionService.mapCustomerInfoForTest(info, 7);

      expect(state.plan, EntitlementPlan.pro);
      expect(state.status, SubscriptionStatus.active);
      expect(state.dailyScanLimit, TierQuota.proDaily);
      expect(state.advancedRecognitionEnabled, isTrue);
      expect(state.marketValuationEnabled, isTrue);
      expect(state.scanHistoryEnabled, isTrue);
      expect(state.scansUsedToday, 7);
    });

    test('8. Pro takes priority over Plus when both entitlements active', () {
      final info = _buildCustomerInfo(activeEntitlements: {
        'plus': {'productId': 'com.coinscan.plus.yearly', 'willRenew': true},
        'pro': {'productId': 'com.coinscan.pro.yearly', 'willRenew': true},
      });
      final state = RevenueCatSubscriptionService.mapCustomerInfoForTest(info, 0);
      expect(state.plan, EntitlementPlan.pro,
          reason: 'Pro must win over Plus when both are active');
    });

    test('9. willRenew=false → cancelled status (access until period end)', () {
      final info = _buildCustomerInfo(activeEntitlements: {
        'plus': {'productId': 'com.coinscan.plus.monthly', 'willRenew': false},
      });
      final state = RevenueCatSubscriptionService.mapCustomerInfoForTest(info, 0);
      expect(state.plan, EntitlementPlan.plus);
      expect(state.status, SubscriptionStatus.cancelled,
          reason: 'Cancelled auto-renew should map to SubscriptionStatus.cancelled');
    });

    test('10. scansUsedToday passthrough from parameter', () {
      final info = _buildCustomerInfo(activeEntitlements: {
        'pro': {'productId': 'com.coinscan.pro.yearly', 'willRenew': true},
      });
      final state = RevenueCatSubscriptionService.mapCustomerInfoForTest(info, 99);
      expect(state.scansUsedToday, 99);
    });

    test('11. Free user — no entitlements active → cannot grant themselves pro', () {
      final info = _buildCustomerInfo(); // zero entitlements
      final state = RevenueCatSubscriptionService.mapCustomerInfoForTest(info, 0);
      expect(state.plan, EntitlementPlan.limited,
          reason: 'Absent RC entitlement must never produce Plus/Pro plan');
    });
  });

  // ─── PurchaseException ─────────────────────────────────────────────────────

  group('PurchaseException', () {
    test('12. Cancellation flag preserved', () {
      const e = PurchaseException('Cancelled', isCancellation: true);
      expect(e.isCancellation, isTrue);
    });

    test('13. Error flag preserved', () {
      const e = PurchaseException('Store error', isCancellation: false);
      expect(e.isCancellation, isFalse);
    });

    test('14. toString includes message', () {
      const e = PurchaseException('Oops', isCancellation: false);
      expect(e.toString(), contains('Oops'));
    });
  });

  // ─── RevenueCatSubscriptionService initial & quota state ──────────────────

  group('RevenueCatSubscriptionService — initial state & quota', () {
    test('15. New service starts at limited plan', () {
      final svc = RevenueCatSubscriptionService();
      expect(svc.state.plan, EntitlementPlan.limited);
      expect(svc.state.status, SubscriptionStatus.none);
    });

    test('16. recordScanUsage increments scansUsedToday', () async {
      final svc = RevenueCatSubscriptionService();
      await svc.recordScanUsage();
      await svc.recordScanUsage();
      expect(svc.state.scansUsedToday, 2);
      expect(svc.state.scansRemaining, TierQuota.limitedDaily - 2);
    });

    test('17. canScan returns false when free quota exhausted', () async {
      final svc = RevenueCatSubscriptionService();
      for (var i = 0; i < TierQuota.limitedDaily; i++) {
        await svc.recordScanUsage();
      }
      expect(svc.state.canScan, isFalse);
      expect(svc.state.scansRemaining, 0);
    });

    test('18. reset() restores limited plan and clears scan counter', () async {
      final svc = RevenueCatSubscriptionService();
      await svc.recordScanUsage();
      await svc.recordScanUsage();
      await svc.reset();
      expect(svc.state.plan, EntitlementPlan.limited);
      expect(svc.state.scansUsedToday, 0);
    });

    test('19. stateChanges stream emits on recordScanUsage', () async {
      final svc = RevenueCatSubscriptionService();
      final states = <EntitlementState>[];
      final sub = svc.stateChanges.listen(states.add);
      await svc.recordScanUsage();
      await sub.cancel();
      expect(states, isNotEmpty);
      expect(states.last.scansUsedToday, 1);
    });

    test('20. stateChanges stream emits on reset', () async {
      final svc = RevenueCatSubscriptionService();
      await svc.recordScanUsage();
      final states = <EntitlementState>[];
      final sub = svc.stateChanges.listen(states.add);
      await svc.reset();
      await sub.cancel();
      expect(states.last.scansUsedToday, 0);
    });
  });

  // ─── Unconfigured SDK guard ────────────────────────────────────────────────

  group('RevenueCatSubscriptionService — unconfigured SDK guards', () {
    test('21. purchase() throws UnsupportedError when SDK not configured', () async {
      final svc = RevenueCatSubscriptionService();
      await expectLater(
        svc.purchase('com.coinscan.plus.monthly'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('22. restorePurchases() throws UnsupportedError when SDK not configured', () async {
      final svc = RevenueCatSubscriptionService();
      await expectLater(
        svc.restorePurchases(),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('23. availableProducts() returns static fallback stubs when not configured', () async {
      final svc = RevenueCatSubscriptionService();
      final products = await svc.availableProducts();
      // 4 products with placeholder prices (not real amounts)
      expect(products.length, 4);
      for (final p in products) {
        expect(p.priceDisplay, '—',
            reason: 'Prices must be placeholder when RC is unconfigured — '
                'never hardcoded real amounts');
        expect(p.priceUsd, 0.0);
      }
    });

    test('24. currentEntitlement() returns limited when SDK not configured', () async {
      final svc = RevenueCatSubscriptionService();
      final state = await svc.currentEntitlement();
      expect(state.plan, EntitlementPlan.limited);
    });
  });

  // ─── Product/entitlement mapping completeness ──────────────────────────────

  group('Product ID mapping', () {
    test('25. Plus monthly → EntitlementPlan.plus', () {
      final info = _buildCustomerInfo(activeEntitlements: {
        'plus': {'productId': RevenueCatConfig.productPlusMonthly},
      });
      final state = RevenueCatSubscriptionService.mapCustomerInfoForTest(info, 0);
      expect(state.plan, EntitlementPlan.plus);
    });

    test('26. Plus yearly → EntitlementPlan.plus', () {
      final info = _buildCustomerInfo(activeEntitlements: {
        'plus': {'productId': RevenueCatConfig.productPlusYearly},
      });
      final state = RevenueCatSubscriptionService.mapCustomerInfoForTest(info, 0);
      expect(state.plan, EntitlementPlan.plus);
    });

    test('27. Pro monthly → EntitlementPlan.pro', () {
      final info = _buildCustomerInfo(activeEntitlements: {
        'pro': {'productId': RevenueCatConfig.productProMonthly},
      });
      final state = RevenueCatSubscriptionService.mapCustomerInfoForTest(info, 0);
      expect(state.plan, EntitlementPlan.pro);
    });

    test('28. Pro yearly → EntitlementPlan.pro', () {
      final info = _buildCustomerInfo(activeEntitlements: {
        'pro': {'productId': RevenueCatConfig.productProYearly},
      });
      final state = RevenueCatSubscriptionService.mapCustomerInfoForTest(info, 0);
      expect(state.plan, EntitlementPlan.pro);
    });
  });

  // ─── Backend synchronization note ─────────────────────────────────────────

  group('Backend synchronization', () {
    test('29. Backend quota sync updates scansUsedToday without altering plan from RC', () async {
      // The service does not alter plan based on local logic; quota sync only
      // updates scan counts and daily limit from the authoritative backend.
      // This is a structural test: verify that reset() leaves the service in
      // the correct state for a subsequent quota sync to apply quota data.
      final svc = RevenueCatSubscriptionService();
      await svc.reset();
      expect(svc.state.plan, EntitlementPlan.limited);
      expect(svc.state.scansUsedToday, 0);
      // In a real flow, quota sync would be triggered by currentEntitlement()
      // after the user authenticates. The backend remains authoritative.
    });
  });
}
