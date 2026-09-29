import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:coinvault_ai/core/config/app_config.dart';
import 'package:coinvault_ai/core/network/api_client.dart';
import 'package:coinvault_ai/core/network/mock_api.dart';
import 'package:coinvault_ai/core/recognition/recognition_models.dart';
import 'package:coinvault_ai/core/storage/collection_storage_service.dart';
import 'package:coinvault_ai/core/subscriptions/revenuecat_subscription_service.dart';
import 'package:coinvault_ai/features/collection/collection_detail_screen.dart';
import 'package:coinvault_ai/features/market/marketplace_screen.dart';
import 'package:coinvault_ai/features/scan/widgets/evidence_result_widgets.dart';

/// P0 regression tests: credentials and data-integrity guarantees on the client.
void main() {
  group('P0: static API keys are never sent from production builds', () {
    tearDown(() {
      AppConfig.reset();
      ApiClient.reset();
    });

    Future<Map<String, String>> capturedHeadersFor(AppEnvironment env) async {
      AppConfig.setTestConfig(
        environment: env,
        backendUrl: 'https://backend.example',
        apiKey: 'static_dev_key_123',
      );
      late Map<String, String> captured;
      final client = ApiClient(
        httpClient: MockClient((request) async {
          captured = request.headers;
          return http.Response('{}', 200);
        }),
      );
      await client.get('/v1/account/quota');
      return captured;
    }

    test('ApiClient omits X-API-Secret in production', () async {
      final headers = await capturedHeadersFor(AppEnvironment.production);
      expect(headers.containsKey('X-API-Secret'), isFalse);
    });

    test('ApiClient still sends X-API-Secret in local development', () async {
      final headers = await capturedHeadersFor(AppEnvironment.development);
      expect(headers['X-API-Secret'], 'static_dev_key_123');
    });

    test('Recognition backend config drops the static key in production', () {
      AppConfig.setTestConfig(
        environment: AppEnvironment.production,
        backendUrl: 'https://backend.example',
        apiKey: 'static_dev_key_123',
      );
      expect(RecognitionBackendConfig.defaultConfig().apiSecret, isNull);
    });

    test('Recognition backend config keeps the static key in development', () {
      AppConfig.setTestConfig(
        environment: AppEnvironment.development,
        backendUrl: 'http://127.0.0.1:8080',
        apiKey: 'static_dev_key_123',
      );
      expect(
        RecognitionBackendConfig.defaultConfig().apiSecret,
        'static_dev_key_123',
      );
    });
  });

  group('P0: no invented prices are shown as real data', () {
    test('Price history is never fabricated', () {
      expect(MockApi.getPriceHistory('coin_morgan_cc', '5 Years'), isEmpty);
      expect(
        MockApi.getPriceHistory('vault_x', '1 Year', baseOverride: 420.0),
        isEmpty,
      );
    });

    testWidgets('Market tab shows no hardcoded spot prices or daily changes', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: MarketplaceScreen()));
      await tester.pumpAndSettle();

      for (final invented in [
        '\$2,645.50',
        '\$31.85',
        '\$982.00',
        '+0.8%',
        '+1.4%',
        '-0.3%',
      ]) {
        expect(find.text(invented), findsNothing, reason: invented);
      }
      expect(find.text('No live feed'), findsNWidgets(3));
      expect(
        find.text(
          'Live spot prices are not connected yet, so no prices are shown.',
        ),
        findsOneWidget,
      );
    });

    RecognitionCandidate candidateWith(String? composition) =>
        RecognitionCandidate(
          coinId: 'numista_1',
          providerName: 'test',
          identity: CoinIdentity(
            country: 'United States',
            denomination: '1 Dollar',
            composition: composition,
          ),
        );

    Future<void> pumpCard(
      WidgetTester tester,
      ValuationResult? valuation,
      RecognitionCandidate candidate,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TransparentValuationCard(
                valuation: valuation,
                candidate: candidate,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Unavailable melt value is not shown as "calculating"', (
      tester,
    ) async {
      await pumpCard(
        tester,
        ValuationResult(
          status: ValuationStatus.unavailable,
          currencyCode: 'USD',
          valuationNotes: 'No live silver spot price is available right now.',
          updatedAt: DateTime.utc(2026, 9, 29),
        ),
        candidateWith('Silver (.900)'),
      );

      expect(find.text('Calculating bullion spot...'), findsNothing);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(
        find.text('No live silver spot price is available right now.'),
        findsOneWidget,
      );
    });

    testWidgets('Unknown composition is not claimed to be base metal', (
      tester,
    ) async {
      await pumpCard(tester, null, candidateWith(null));

      expect(find.text('Contains no precious gold or silver'), findsNothing);
      expect(find.text('Unknown'), findsOneWidget);
    });

    testWidgets('Values are labelled with their real currency, not \$', (
      tester,
    ) async {
      await pumpCard(
        tester,
        ValuationResult(
          status: ValuationStatus.partial,
          currencyCode: 'EUR',
          estimates: [
            ValuationEstimate(
              type: ValuationType.metalValue,
              currencyCode: 'EUR',
              low: 19.6,
              high: 20.4,
              mid: 20.0,
              valuedAt: DateTime.utc(2026, 9, 29),
              source: 'Test-Metals silver spot',
              caveat: 'Bullion value only',
            ),
          ],
          updatedAt: DateTime.utc(2026, 9, 29),
        ),
        candidateWith('Silver (.900)'),
      );

      expect(find.text('20.00 EUR'), findsOneWidget);
      expect(find.textContaining('\$20.00'), findsNothing);
    });

    testWidgets(
      'Vault detail shows one honest estimate, no retail/auction/dealer split',
      (tester) async {
        final item = VaultCoinItem(
          id: 'vault_test_1',
          coinName: '1882 United States 1 Dollar',
          country: 'United States',
          denomination: '1 Dollar',
          currentEstimatedValue: 25.0,
          meltValue: 23.2,
          dateAdded: DateTime(2026, 9, 29),
        );
        await tester.pumpWidget(
          MaterialApp(home: CollectionDetailScreen(vaultItem: item)),
        );
        await tester.pump();

        expect(find.text('Auction'), findsNothing);
        expect(find.text('Dealer'), findsNothing);
        expect(find.text('Retail'), findsNothing);
        expect(find.text('Saved estimate'), findsOneWidget);
        expect(find.text('\$25.00'), findsOneWidget);
        expect(find.text('\$23.20'), findsOneWidget);
        // Purchase price is never pre-filled with an estimate
        final purchaseFields = tester
            .widgetList<EditableText>(find.byType(EditableText))
            .map((e) => e.controller.text);
        expect(purchaseFields, isNot(contains('25')));
        expect(purchaseFields, isNot(contains('22')));

        // Unmount and let the screen's delayed animations/timers complete.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      },
    );
  });

  group(
    'P0: a just-purchased subscription is not downgraded by a pending webhook',
    () {
      const proFromStore = EntitlementState(
        plan: EntitlementPlan.pro,
        status: SubscriptionStatus.active,
        scansUsedToday: 0,
        dailyScanLimit: TierQuota.proDaily,
        advancedRecognitionEnabled: true,
        marketValuationEnabled: true,
        scanHistoryEnabled: true,
      );

      test(
        'backend still reporting free keeps the verified store entitlement',
        () {
          final merged = RevenueCatSubscriptionService.mergeBackendQuota(
            proFromStore,
            {'tier': 'free', 'daily_limit': 3, 'scans_used_today': 3},
          );
          expect(merged.plan, EntitlementPlan.pro);
          expect(merged.dailyScanLimit, TierQuota.proDaily);
          expect(
            merged.scansUsedToday,
            3,
          ); // count still comes from the backend
          expect(merged.canScan, isTrue);
        },
      );

      test('backend tier is used once the webhook has been processed', () {
        final merged = RevenueCatSubscriptionService.mergeBackendQuota(
          proFromStore,
          {'tier': 'pro', 'daily_limit': 100, 'scans_used_today': 7},
        );
        expect(merged.plan, EntitlementPlan.pro);
        expect(merged.dailyScanLimit, 100);
        expect(merged.scansUsedToday, 7);
      });

      test('without a store entitlement the backend tier is authoritative', () {
        final merged = RevenueCatSubscriptionService.mergeBackendQuota(
          const EntitlementState.limited(),
          {'tier': 'plus', 'daily_limit': 30, 'scans_used_today': 1},
        );
        expect(merged.plan, EntitlementPlan.plus);
        expect(merged.dailyScanLimit, 30);
      });

      test('an expired store entitlement does not override the backend', () {
        final expired = proFromStore.copyWith(
          status: SubscriptionStatus.expired,
        );
        final merged = RevenueCatSubscriptionService.mergeBackendQuota(
          expired,
          {'tier': 'free', 'daily_limit': 3, 'scans_used_today': 0},
        );
        expect(merged.plan, EntitlementPlan.limited);
        expect(merged.dailyScanLimit, 3);
      });
    },
  );
}
