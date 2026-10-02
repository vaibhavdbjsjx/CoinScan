import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:coinvault_ai/core/auth/auth_service.dart';
import 'package:coinvault_ai/core/legal/legal_consent_models.dart';
import 'package:coinvault_ai/core/network/api_client.dart';
import 'package:coinvault_ai/core/storage/secure_storage_service.dart';

/// Test accounts: each email signs in as its own Supabase user.
const aliceEmail = 'alice@example.com';
const bobEmail = 'bob@example.com';
const aliceId = '11111111-1111-4111-8111-111111111111';
const bobId = '22222222-2222-4222-8222-222222222222';
const testPassword = 'password123';

/// A real [AuthService] on a real [SupabaseClient] whose HTTP layer is mocked,
/// so GoTrue's own sign-in, session and event code runs in the test.
class AuthHarness {
  static const accounts = {aliceEmail: aliceId, bobEmail: bobId};

  final requests = <http.Request>[];
  late final SupabaseClient supabase;
  late final ApiClient backend;
  late final DeviceSecureStorageService storage;
  late final AuthService auth;

  AuthHarness() {
    supabase = SupabaseClient(
      'https://project.supabase.test',
      'public-anon-key',
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
      httpClient: MockClient((req) async {
        requests.add(req);
        final path = req.url.path;
        if (path.endsWith('/token')) {
          final email = (jsonDecode(req.body) as Map)['email'] as String?;
          final id = accounts[email];
          if (id == null) {
            return http.Response(
              jsonEncode({
                'error': 'invalid_grant',
                'error_description': 'Invalid login credentials',
              }),
              400,
            );
          }
          return http.Response(jsonEncode(_session(id, email!)), 200);
        }
        if (path.endsWith('/logout')) return http.Response('', 204);
        return http.Response('{}', 404);
      }),
    );
    backend = ApiClient(
      baseUrl: 'https://backend.test',
      httpClient: MockClient((req) async {
        requests.add(req);
        if (req.url.path == '/v1/account/legal/consent' &&
            req.method == 'GET') {
          return http.Response(
            jsonEncode({
              'status': 'not_accepted',
              'terms_version': '',
              'privacy_version': '',
            }),
            200,
          );
        }
        if (req.url.path == '/v1/account/legal/consent') {
          return http.Response('{}', 200);
        }
        return http.Response('{}', 404);
      }),
    );
    storage = DeviceSecureStorageService();
    auth = AuthService(
      secureStorage: storage,
      legalConsentService: LegalConsentService(
        secureStorage: storage,
        apiClient: backend,
      ),
      supabaseClient: supabase,
      apiClient: backend,
    );
  }

  /// Signs in with the Terms accepted in the same step, as the sign-in screen does.
  Future<AuthState> signIn(String email) => auth.signInWithEmail(
    email: email,
    password: testPassword,
    termsAccepted: true,
  );

  static Map<String, dynamic> _session(String id, String email) => {
    'access_token': 'access-token-$id',
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at':
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000,
    'refresh_token': 'refresh-token-$id',
    'user': {
      'id': id,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': email,
      'app_metadata': {'provider': 'email'},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-09-30T00:00:00Z',
    },
  };
}
