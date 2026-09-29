import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:coinvault_ai/core/auth/auth_service.dart';
import 'package:coinvault_ai/core/legal/legal_consent_models.dart';
import 'package:coinvault_ai/core/network/api_client.dart';
import 'package:coinvault_ai/core/storage/collection_storage_service.dart';
import 'package:coinvault_ai/core/storage/scan_history_service.dart';
import 'package:coinvault_ai/core/storage/secure_storage_service.dart';
import 'package:coinvault_ai/core/subscriptions/subscription_service.dart';

class MockSecureStorageService implements SecureStorageService {
  final Map<String, String> data = {};

  @override
  Future<void> write({required String key, required String value}) async {
    data[key] = value;
  }

  @override
  Future<String?> read({required String key}) async {
    return data[key];
  }

  @override
  Future<void> delete({required String key}) async {
    data.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    data.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CoinScan Backend ↔ Flutter Client Integration Tests', () {
    late MockSecureStorageService secureStorage;
    late LegalConsentService legalConsentService;

    setUp(() {
      secureStorage = MockSecureStorageService();
      legalConsentService = LegalConsentService(secureStorage: secureStorage);
    });

    test('1. Account Profile: GET /v1/account/me populates authoritative user profile', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/account/me') {
          expect(request.headers['authorization'], contains('Bearer mock_jwt_token'));
          return http.Response(
            jsonEncode({
              'id': 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d',
              'email': 'collector_pro@coinscan.app',
              'display_name': 'Pro Numismatist',
              'preferred_currency': 'EUR',
              'tier': 'pro',
              'created_at': 1711200000.0,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(
        baseUrl: 'http://127.0.0.1:8080',
        httpClient: mockClient,
        tokenProvider: () async => 'mock_jwt_token',
      );

      final service = AuthService(
        secureStorage: secureStorage,
        legalConsentService: legalConsentService,
        apiClient: apiClient,
      );

      await service.signInWithEmail(
        email: 'collector_pro@coinscan.app',
        password: 'Password123!',
        termsAccepted: true,
      );

      final profile = await service.fetchAuthoritativeProfile();
      expect(profile, isNotNull);
      expect(profile!.userId, equals('a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d'));
      expect(profile.displayName, equals('Pro Numismatist'));
      expect(profile.tier, equals('pro'));
      expect(profile.preferredCurrency, equals('EUR'));
    });

    test('2. Collection Vault Sync: GET /v1/collection fetches and deduplicates authoritative items', () async {
      final serverItems = [
        {
          'id': '11111111-1111-1111-1111-111111111111',
          'user_id': 'u1',
          'coin_name': '1921 Morgan Silver Dollar',
          'country': 'United States',
          'denomination': '1 Dollar',
          'year': 1921,
          'mint_mark': 'D',
          'composition': '90% Silver',
          'grade': 'MS63',
          'purchase_price': 45.0,
          'currency_code': 'USD',
          'initial_valuation_snapshot': 45.0,
          'current_estimated_value': 65.0,
          'is_favorite': true,
          'created_at': 1711200000.0,
          'updated_at': 1711200000.0,
        },
        {
          'id': '22222222-2222-2222-2222-222222222222',
          'user_id': 'u1',
          'coin_name': '1909-S VDB Lincoln Cent',
          'country': 'United States',
          'denomination': '1 Cent',
          'year': 1909,
          'mint_mark': 'S',
          'composition': 'Bronze',
          'grade': 'VF30',
          'purchase_price': 800.0,
          'currency_code': 'USD',
          'initial_valuation_snapshot': 800.0,
          'current_estimated_value': 1200.0,
          'is_favorite': false,
          'created_at': 1711201000.0,
          'updated_at': 1711201000.0,
        },
      ];

      int getCount = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/collection') {
          getCount++;
          return http.Response(
            jsonEncode(serverItems),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(
        baseUrl: 'http://127.0.0.1:8080',
        httpClient: mockClient,
      );

      final collectionStorage = CollectionStorageService(apiClient: apiClient);
      collectionStorage.setCurrentUser('user_test_uuid');
      collectionStorage.resetForUserSwitch();

      // First sync
      final items1 = await collectionStorage.loadCollection(forceRefresh: true);
      expect(items1.length, equals(2));
      expect(items1[0].coinName, equals('1921 Morgan Silver Dollar'));
      expect(items1[0].isFavorite, isTrue);
      expect(items1[1].grade, equals('VF30'));

      // Repeated sync must not duplicate items
      final items2 = await collectionStorage.loadCollection(forceRefresh: true);
      expect(items2.length, equals(2));
      expect(getCount, equals(2));
    });

    test('3. Collection Vault Sync: POST /v1/collection saves and DELETE /v1/collection/<id> removes item', () async {
      http.Request? capturedPost;
      http.Request? capturedDelete;

      final mockClient = MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/v1/collection') {
          capturedPost = request;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'id': body['id'] ?? '33333333-3333-3333-3333-333333333333',
              'user_id': 'u1',
              'coin_name': body['coin_name'],
              'country': body['country'],
              'denomination': body['denomination'],
              'year': body['year'],
              'currency_code': 'USD',
              'created_at': 1711202000.0,
              'updated_at': 1711202000.0,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.method == 'DELETE' && request.url.path.startsWith('/v1/collection/')) {
          capturedDelete = request;
          return http.Response(
            jsonEncode({'status': 'success', 'message': 'Item deleted'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(
        baseUrl: 'http://127.0.0.1:8080',
        httpClient: mockClient,
      );

      final collectionStorage = CollectionStorageService(apiClient: apiClient);
      collectionStorage.setCurrentUser('user_test_uuid');
      collectionStorage.resetForUserSwitch();

      final newItem = VaultCoinItem(
        id: '33333333-3333-3333-3333-333333333333',
        coinName: '1893 Isabella Quarter',
        country: 'United States',
        denomination: '25 Cents',
        year: 1893,
        dateAdded: DateTime.now(),
      );

      await collectionStorage.saveItem(newItem);
      expect(capturedPost, isNotNull);
      final postBody = jsonDecode(capturedPost!.body);
      expect(postBody['coin_name'], equals('1893 Isabella Quarter'));
      expect(collectionStorage.items.length, equals(1));

      // Delete item
      await collectionStorage.deleteItem('33333333-3333-3333-3333-333333333333');
      expect(capturedDelete, isNotNull);
      expect(capturedDelete!.url.path, equals('/v1/collection/33333333-3333-3333-3333-333333333333'));
      expect(collectionStorage.items.isEmpty, isTrue);
    });

    test('4. Scan History: GET /v1/account/history retrieves and parses server-side scan history', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/account/history') {
          return http.Response(
            jsonEncode([
              {
                'id': 'scan_uuid_001',
                'user_id': 'u1',
                'scanned_at': 1711200000.0,
                'coin_name': '1943 Steel Penny',
                'country': 'United States',
                'denomination': '1 Cent',
                'year': '1943',
                'confidence_score': 0.96,
                'numista_id': 3163,
                'status_label': 'identified',
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(baseUrl: 'http://127.0.0.1:8080', httpClient: mockClient);
      final historyService = ScanHistoryService(apiClient: apiClient);
      historyService.setCurrentUser('user_test_uuid');
      historyService.resetForUserSwitch();

      final history = await historyService.loadHistory(forceRefresh: true);
      expect(history.length, equals(1));
      expect(history[0].coinName, equals('1943 Steel Penny'));
      expect(history[0].confidenceScore, equals(0.96));
      expect(history[0].numistaNumber, equals('3163'));
    });

    test('5. Daily Quota: GET /v1/account/quota synchronizes authoritative backend quota', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/account/quota') {
          return http.Response(
            jsonEncode({
              'user_id': 'user_quota_uuid',
              'tier': 'plus',
              'daily_limit': 30,
              'scans_used_today': 12,
              'scans_remaining_today': 18,
              'resets_at_utc': '2026-09-28T00:00:00Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      ApiClient.configure(
        baseUrl: 'http://127.0.0.1:8080',
        httpClient: mockClient,
        tokenProvider: () async => 'active_session_token',
      );

      final subService = DevSubscriptionService();
      final quotaState = await subService.syncQuotaWithBackend();

      expect(quotaState.plan, equals(EntitlementPlan.plus));
      expect(quotaState.dailyScanLimit, equals(30));
      expect(quotaState.scansUsedToday, equals(12));
      expect(quotaState.status, equals(SubscriptionStatus.active));
    });

    test('6. User Feedback: POST /v1/feedback transmits structured report', () async {
      http.Request? capturedFeedback;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/feedback' && request.method == 'POST') {
          capturedFeedback = request;
          return http.Response(
            jsonEncode({
              'status': 'success',
              'message': 'Thank you for your feedback!',
              'feedback_id': 'fb_12345',
              'received_at': 1711200000.0,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(
        baseUrl: 'http://127.0.0.1:8080',
        httpClient: mockClient,
        tokenProvider: () async => 'mock_token',
      );

      final res = await apiClient.post(
        '/v1/feedback',
        body: {
          'category': 'recognition_incorrect',
          'title': 'Reverse mint mark misread',
          'description': 'The coin is an S mint mark but was recognized as D.',
          'app_version': '1.0.0',
          'platform': 'ios',
        },
      );

      expect(res['status'], equals('success'));
      expect(capturedFeedback, isNotNull);
      final body = jsonDecode(capturedFeedback!.body);
      expect(body['category'], equals('recognition_incorrect'));
      expect(body['title'], equals('Reverse mint mark misread'));
    });

    test('7. Legal Consent: POST /v1/account/legal/consent records server record', () async {
      http.Request? capturedConsent;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/account/legal/consent' && request.method == 'POST') {
          capturedConsent = request;
          return http.Response(
            jsonEncode({
              'user_id': 'consent_user_uuid',
              'terms_version': '1.0.0',
              'privacy_version': '1.0.0',
              'accepted_at': 1711200000.0,
              'consent_status': 'active',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(
        baseUrl: 'http://127.0.0.1:8080',
        httpClient: mockClient,
      );

      final consentService = LegalConsentService(
        secureStorage: secureStorage,
        apiClient: apiClient,
      );

      final record = await consentService.recordConsent(userId: 'consent_user_uuid');
      expect(record.termsVersion, equals('1.0.0'));
      expect(capturedConsent, isNotNull);
      final body = jsonDecode(capturedConsent!.body);
      expect(body['terms_version'], equals('1.0.0'));
      expect(body['privacy_version'], equals('1.0.0'));
    });

    test('8. ApiClient: 401 triggers token refresher and retries request safely', () async {
      int requestCount = 0;
      int refreshCount = 0;

      final mockClient = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          // Initial request with expired token
          expect(request.headers['authorization'], equals('Bearer expired_token'));
          return http.Response(jsonEncode({'detail': 'Token expired'}), 401);
        } else {
          // Retry with refreshed token
          expect(request.headers['authorization'], equals('Bearer fresh_token'));
          return http.Response(jsonEncode({'profile': 'valid_data'}), 200);
        }
      });

      final apiClient = ApiClient(
        baseUrl: 'http://127.0.0.1:8080',
        httpClient: mockClient,
        tokenProvider: () async => 'expired_token',
        tokenRefresher: () async {
          refreshCount++;
          return 'fresh_token';
        },
      );

      final res = await apiClient.get('/v1/account/me');
      expect(res['profile'], equals('valid_data'));
      expect(requestCount, equals(2));
      expect(refreshCount, equals(1));
    });

    test('9. ApiClient: repeated 401 triggers session expiration callback', () async {
      bool sessionExpiredFired = false;
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Invalid token'}), 401);
      });

      final apiClient = ApiClient(
        baseUrl: 'http://127.0.0.1:8080',
        httpClient: mockClient,
        tokenProvider: () async => 'bad_token',
        tokenRefresher: () async => null, // refresh failed
        onSessionExpired: () async {
          sessionExpiredFired = true;
        },
      );

      await expectLater(
        apiClient.get('/v1/account/me'),
        throwsA(isA<ApiException>()),
      );
      expect(sessionExpiredFired, isTrue);
    });

    test('10. Account Deletion: Server failure rejects deletion without clearing local data', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/account/delete') {
          return http.Response(
            jsonEncode({'detail': 'Server database transaction error'}),
            500,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(
        baseUrl: 'http://127.0.0.1:8080',
        httpClient: mockClient,
        tokenProvider: () async => 'token_for_delete',
      );

      final service = AuthService(
        secureStorage: secureStorage,
        legalConsentService: legalConsentService,
        apiClient: apiClient,
      );

      await service.signInWithEmail(
        email: 'user_safeguard@coinscan.app',
        password: 'Password123!',
        termsAccepted: true,
      );

      expect(service.currentState.isAuthenticated, isTrue);

      // Calling deleteAccount must throw ApiException on server error
      expect(() => service.deleteAccount(), throwsA(isA<ApiException>()));

      // Session must remain intact because server rejected deletion
      expect(service.currentState.isAuthenticated, isTrue);
    });

    test('11. Account Deletion: Successful deletion cascades server call and wipes local state', () async {
      http.Request? capturedDelete;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/account/delete') {
          capturedDelete = request;
          return http.Response(
            jsonEncode({
              'status': 'success',
              'message': 'Account and all associated records permanently deleted',
              'user_id': 'user_deleted_uuid',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(
        baseUrl: 'http://127.0.0.1:8080',
        httpClient: mockClient,
        tokenProvider: () async => 'token_for_delete',
      );

      final service = AuthService(
        secureStorage: secureStorage,
        legalConsentService: legalConsentService,
        apiClient: apiClient,
      );

      await service.signInWithEmail(
        email: 'user_to_delete@coinscan.app',
        password: 'Password123!',
        termsAccepted: true,
      );

      await service.deleteAccount();

      expect(capturedDelete, isNotNull);
      expect(capturedDelete!.method, equals('DELETE'));
      final deleteBody = jsonDecode(capturedDelete!.body);
      expect(deleteBody['confirm_phrase'], equals('DELETE MY ACCOUNT'));

      // Local session wiped
      expect(service.currentState.isAuthenticated, isFalse);
      expect(secureStorage.data.isEmpty, isTrue);
    });

    test('12. Guest vs Authenticated Data Separation: Guest data is never automatically leaked into user account', () async {
      final collectionStorage = CollectionStorageService.instance;
      final historyService = ScanHistoryService.instance;

      // 1. Guest creates records in guest mode
      collectionStorage.setCurrentUser(null);
      collectionStorage.resetForUserSwitch();
      historyService.setCurrentUser(null);
      historyService.resetForUserSwitch();

      final guestItem = VaultCoinItem(
        id: 'guest_coin_123',
        coinName: 'Guest Secret Coin',
        country: 'United Kingdom',
        denomination: '1 Penny',
        dateAdded: DateTime.now(),
      );
      await collectionStorage.addItem(guestItem);
      expect(collectionStorage.items.length, equals(1));
      expect(collectionStorage.items.first.id, equals('guest_coin_123'));

      // 2. User signs into an authenticated account
      const userUuid = 'uuid_user_authenticated_999';
      collectionStorage.setCurrentUser(userUuid);
      historyService.setCurrentUser(userUuid);

      // Authenticated vault cache MUST be isolated; guest item must not appear in user cache
      expect(collectionStorage.items.isEmpty, isTrue);
      expect(historyService.cachedRecordCount, equals(0));

      // 3. User signs out -> restores guest state
      collectionStorage.setCurrentUser(null);
      collectionStorage.resetForUserSwitch();
      historyService.setCurrentUser(null);
      historyService.resetForUserSwitch();
    });
  });
}
