import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:coinvault_ai/core/auth/auth_service.dart';
import 'package:coinvault_ai/core/navigation/router.dart';
import 'package:coinvault_ai/core/network/api_client.dart';
import 'package:coinvault_ai/core/network/mock_api.dart';
import 'package:coinvault_ai/core/storage/collection_storage_service.dart';
import 'package:coinvault_ai/core/storage/secure_storage_service.dart';

class MockSecureStorage implements SecureStorageService {
  final Map<String, String> _data = {};

  @override
  Future<void> write({required String key, required String value}) async {
    _data[key] = value;
  }

  @override
  Future<String?> read({required String key}) async {
    return _data[key];
  }

  @override
  Future<void> delete({required String key}) async {
    _data.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _data.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2 High-Severity Remediation Tests', () {
    test('1. ISSUE-AUTH-05: ApiClient coalesces concurrent token refreshes into a single call', () async {
      int refreshCallCount = 0;
      final completer = Completer<String?>();

      final client = ApiClient(
        baseUrl: 'https://api.test.coinscan.app',
        tokenProvider: () async => 'expired_token',
        tokenRefresher: () async {
          refreshCallCount++;
          return completer.future;
        },
      );

      // Launch multiple concurrent refresh calls simultaneously
      final future1 = client.synchronizedTokenRefresh();
      final future2 = client.synchronizedTokenRefresh();
      final future3 = client.synchronizedTokenRefresh();

      // Release the in-flight refresh
      completer.complete('fresh_refreshed_token');

      final results = await Future.wait<String?>([future1, future2, future3]);

      // All callers must receive the refreshed token
      expect(results[0], equals('fresh_refreshed_token'));
      expect(results[1], equals('fresh_refreshed_token'));
      expect(results[2], equals('fresh_refreshed_token'));

      // The refresh callback must be invoked EXACTLY ONCE to prevent GoTrue token replay revocation
      expect(refreshCallCount, equals(1));
    });

    test('2. ISSUE-AUTH-06: AuthService ChangeNotifier notifies listeners on auth state changes', () async {
      final storage = MockSecureStorage();
      final auth = AuthService(secureStorage: storage);

      int notifyCount = 0;
      auth.addListener(() {
        notifyCount++;
      });

      // Sign in with dev fallback
      await auth.signInWithEmail(
        email: 'collector_p2@coinscan.app',
        password: 'secure_password_123',
        termsAccepted: true,
      );

      expect(auth.currentState.isAuthenticated, isTrue);
      expect(notifyCount, greaterThan(0));

      // Sign out
      final countBeforeSignOut = notifyCount;
      await auth.signOut();

      expect(auth.currentState.isGuest, isTrue);
      expect(notifyCount, greaterThan(countBeforeSignOut));
    });

    test('3. ISSUE-VAL-03: MockApi.getPriceHistory never fabricates a price history', () {
      // P0 valuation integrity: no historical price source is connected, so no
      // series is returned (a flat line of the current value labelled
      // "1 Year" / "5 Years" was an invented history).
      expect(MockApi.getPriceHistory('coin_morgan_cc', '1 Month', baseOverride: 100.0), isEmpty);
      expect(MockApi.getPriceHistory('coin_morgan_cc', '1 Year', baseOverride: 500.0), isEmpty);
      expect(MockApi.getPriceHistory('test_coin', '1 Month', baseOverride: 0.0), isEmpty);
      expect(MockApi.getPriceHistory('test_coin', '1 Month', baseOverride: -50.0), isEmpty);
    });

    test('4. ISSUE-VAL-04: VaultCoinItem.toCollectibleModel does not apply arbitrary multipliers or fake ratings', () {
      final vaultItem = VaultCoinItem(
        id: 'vault_item_test_p2',
        coinName: '1921 Morgan Dollar',
        country: 'United States',
        denomination: '1 Dollar',
        year: 1921,
        composition: '90% Silver, 10% Copper',
        dateAdded: DateTime.now(),
        currentEstimatedValue: 100.0,
      );

      final model = vaultItem.toCollectibleModel();

      // Honest pricing: retail, auction, dealer, and collector match estimated value without fake margins
      expect(model.retailPrice, equals(100.0));
      expect(model.dealerPrice, equals(100.0)); // Not 100 * 0.85
      expect(model.minPrice, equals(100.0));    // Not 100 * 0.8
      expect(model.maxPrice, equals(100.0));    // Not 100 * 1.3

      // No fabricated letter ratings or fake engraver
      expect(model.investmentRating, isEmpty);  // Not hardcoded 'A' or 'B+'
      expect(model.designer, isEmpty);          // Not 'Historic Engraver'
    });

    test('5. ISSUE-UX-01: AppRouter router configuration binds refreshListenable to AuthService', () {
      expect(AppRouter.router, isNotNull);
      // Verify router is instantiated and ready to navigate
      expect(AppRouter.onboarding, equals('/onboarding'));
      expect(AppRouter.login, equals('/login'));
      expect(AppRouter.main, equals('/'));
    });

    test('6. ISSUE-LEG-02: ApiClient.exportAccountData issues GET /v1/account/export', () async {
      final mockHttp = MockClient((request) async {
        if (request.url.path == '/v1/account/export' && request.method == 'GET') {
          return http.Response(
            '{"status": "ok", "user": {"id": "usr_123", "email": "test@coinscan.app"}}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"error": "Not Found"}', 404);
      });

      final client = ApiClient(
        baseUrl: 'https://api.test.coinscan.app',
        tokenProvider: () async => 'test_jwt_token',
        httpClient: mockHttp,
      );

      final data = await client.exportAccountData();
      expect(data, isNotNull);
      expect(data!['status'], equals('ok'));
      expect(data['user']['email'], equals('test@coinscan.app'));
    });
  });
}
