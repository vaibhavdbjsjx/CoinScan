import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:coinvault_ai/core/network/api_client.dart';
import 'package:coinvault_ai/core/auth/auth_service.dart';
import 'package:coinvault_ai/core/storage/secure_storage_service.dart';
import 'package:coinvault_ai/core/legal/legal_consent_models.dart';

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

  Map<String, String> get data => Map.unmodifiable(_data);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiClient Tests', () {
    test('1. Automatically attaches Bearer token when tokenProvider returns a token', () async {
      http.Request? capturedRequest;

      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(jsonEncode({'status': 'ok'}), 200, headers: {
          'content-type': 'application/json',
          'x-request-id': 'req-test-123',
        });
      });

      final apiClient = ApiClient(
        baseUrl: 'https://api.test.coinscan.app',
        httpClient: mockClient,
        tokenProvider: () async => 'supabase_mock_jwt_access_token',
      );

      final response = await apiClient.get('/v1/account/me');

      expect(response, equals({'status': 'ok'}));
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.headers['authorization'], equals('Bearer supabase_mock_jwt_access_token'));
      expect(capturedRequest!.headers['x-request-id'], isNotEmpty);
      expect(capturedRequest!.headers['accept'], equals('application/json'));
    });

    test('2. Omits Authorization header when tokenProvider returns null', () async {
      http.Request? capturedRequest;

      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(jsonEncode({'healthy': true}), 200, headers: {
          'content-type': 'application/json',
        });
      });

      final apiClient = ApiClient(
        baseUrl: 'https://api.test.coinscan.app',
        httpClient: mockClient,
        tokenProvider: () async => null,
      );

      final response = await apiClient.get('/v1/health');

      expect(response, equals({'healthy': true}));
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.headers.containsKey('authorization'), isFalse);
    });

    test('3. Handles 401 Unauthorized cleanly with typed ApiException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'Unauthorized', 'detail': 'JWT signature invalid or expired'}),
          401,
          headers: {'content-type': 'application/json', 'x-request-id': 'req-401'},
        );
      });

      final apiClient = ApiClient(
        baseUrl: 'https://api.test.coinscan.app',
        httpClient: mockClient,
        tokenProvider: () async => 'invalid_token',
      );

      expect(
        () async => await apiClient.get('/v1/vault/items'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', equals(401))
            .having((e) => e.requestId, 'requestId', equals('req-401'))
            .having((e) => e.message, 'message', contains('JWT signature invalid or expired'))),
      );
    });

    test('4. Handles DELETE requests with JSON body and custom headers', () async {
      http.Request? capturedRequest;

      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({'success': true, 'message': 'Account deleted'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(
        baseUrl: 'https://api.test.coinscan.app',
        httpClient: mockClient,
        tokenProvider: () async => 'valid_supabase_token',
      );

      final result = await apiClient.delete(
        '/v1/account/delete',
        body: {'confirm_phrase': 'DELETE MY ACCOUNT'},
      );

      expect(result['success'], isTrue);
      expect(capturedRequest!.method, equals('DELETE'));
      expect(jsonDecode(capturedRequest!.body), equals({'confirm_phrase': 'DELETE MY ACCOUNT'}));
      expect(capturedRequest!.headers['authorization'], equals('Bearer valid_supabase_token'));
    });
  });

  group('AuthService UUID & Session Resilience Tests', () {
    late MockSecureStorage mockSecureStorage;
    late LegalConsentService legalConsentService;
    late AuthService authService;

    setUp(() {
      mockSecureStorage = MockSecureStorage();
      legalConsentService = LegalConsentService(secureStorage: mockSecureStorage);
      authService = AuthService(
        secureStorage: mockSecureStorage,
        legalConsentService: legalConsentService,
      );
    });

    test('1. User ID generated in fallback mode is strictly an RFC 4122 compliant UUID', () async {
      final state = await authService.signInWithEmail(
        email: 'collector.test@coinscan.app',
        password: 'SecurePassword!123',
        termsAccepted: true,
      );

      expect(state.isAuthenticated, isTrue);
      final uuidRegex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false,
      );

      expect(state.user!.userId, matches(uuidRegex));
      // Verify no legacy synthetic tokens
      expect(state.user!.userId.startsWith('usr_'), isFalse);
      expect(state.token, isNotNull);
      expect(state.token!.startsWith('jwt_token_usr_'), isFalse);
    });

    test('2. Persists session state to secure storage and restores on initialization', () async {
      final originalState = await authService.signInWithEmail(
        email: 'persist.user@coinscan.app',
        password: 'Password123!',
        termsAccepted: true,
      );

      expect(mockSecureStorage.data.containsKey(SecureStorageService.keyAuthToken), isTrue);
      expect(mockSecureStorage.data.containsKey(SecureStorageService.keyUserId), isTrue);

      // Create a brand new AuthService instance with the same storage
      final newAuthService = AuthService(
        secureStorage: mockSecureStorage,
        legalConsentService: legalConsentService,
      );
      expect(newAuthService.currentState.isAuthenticated, isFalse);

      await newAuthService.initialize();

      expect(newAuthService.currentState.isAuthenticated, isTrue);
      expect(newAuthService.currentState.user!.userId, equals(originalState.user!.userId));
      expect(newAuthService.currentState.user!.email, equals(originalState.user!.email));
      expect(newAuthService.currentState.token, equals(originalState.token));
    });

    test('3. deleteAccount flushes session and invokes backend DELETE endpoint', () async {
      http.Request? capturedDeleteRequest;
      final mockClient = MockClient((request) async {
        capturedDeleteRequest = request;
        return http.Response(
          jsonEncode({'success': true, 'message': 'Account and all associated data permanently deleted'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(
        baseUrl: 'https://api.test.coinscan.app',
        httpClient: mockClient,
        tokenProvider: () async => 'auth_token_for_deletion',
      );

      final service = AuthService(
        secureStorage: mockSecureStorage,
        legalConsentService: legalConsentService,
        apiClient: apiClient,
      );

      await service.signInWithEmail(
        email: 'to_be_deleted@coinscan.app',
        password: 'Password123!',
        termsAccepted: true,
      );

      expect(service.currentState.isAuthenticated, isTrue);

      await service.deleteAccount();

      // Verified backend call
      expect(capturedDeleteRequest, isNotNull);
      expect(capturedDeleteRequest!.method, equals('DELETE'));
      expect(capturedDeleteRequest!.url.path, equals('/v1/account/delete'));
      expect(jsonDecode(capturedDeleteRequest!.body)['confirm_phrase'], equals('DELETE MY ACCOUNT'));

      // Verified local state wiped
      expect(service.currentState.isAuthenticated, isFalse);
      expect(mockSecureStorage.data.isEmpty, isTrue);
    });

    test('4. signInWithApple and signInWithGoogle strictly enforce terms acceptance', () async {
      final service = AuthService(
        secureStorage: mockSecureStorage,
        legalConsentService: legalConsentService,
      );

      expect(
        () => service.signInWithApple(termsAccepted: false),
        throwsA(isA<TermsConsentRequiredException>()),
      );
      expect(
        () => service.signInWithGoogle(termsAccepted: false),
        throwsA(isA<TermsConsentRequiredException>()),
      );
    });

    test('5. OAuth in dev mode assigns clean dev identifier without hardcoded production identities', () async {
      final service = AuthService(
        secureStorage: mockSecureStorage,
        legalConsentService: legalConsentService,
      );

      final appleState = await service.signInWithApple(termsAccepted: true);
      expect(appleState.isAuthenticated, isTrue);
      expect(appleState.user?.email, equals('dev.apple@coinscan.app'));
      expect(RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(appleState.user!.userId), isTrue);

      final googleState = await service.signInWithGoogle(termsAccepted: true);
      expect(googleState.isAuthenticated, isTrue);
      expect(googleState.user?.email, equals('dev.google@coinscan.app'));
      expect(RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(googleState.user!.userId), isTrue);
    });
  });
}
