import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:coinvault_ai/core/auth/auth_service.dart';
import 'package:coinvault_ai/core/legal/legal_consent_models.dart';
import 'package:coinvault_ai/core/navigation/router.dart';
import 'package:coinvault_ai/core/network/api_client.dart';
import 'package:coinvault_ai/core/storage/secure_storage_service.dart';
import 'package:coinvault_ai/features/onboarding/account_flow_screens.dart';
import 'package:coinvault_ai/features/onboarding/login_screen.dart';
import 'package:coinvault_ai/core/widgets/premium_widgets.dart';

const _userId = '6b0c3f55-3c52-4d8b-9f4a-0a1b2c3d4e5f';

Map<String, dynamic> _userJson() => {
  'id': _userId,
  'aud': 'authenticated',
  'role': 'authenticated',
  'email': 'collector@example.com',
  'app_metadata': {'provider': 'email'},
  'user_metadata': {'display_name': 'Ada'},
  'created_at': '2026-09-30T00:00:00Z',
};

Map<String, dynamic> _sessionJson() => {
  'access_token': 'header.payload.signature',
  'token_type': 'bearer',
  'expires_in': 3600,
  'expires_at': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
  'refresh_token': 'refresh-token',
  'user': _userJson(),
};

/// A real SupabaseClient whose HTTP layer is mocked, so GoTrue's own sign-in,
/// event and session code runs in the test.
class _Harness {
  final requests = <http.Request>[];
  bool backendHasConsent = false;
  late final SupabaseClient supabase;
  late final ApiClient backend;
  late final DeviceSecureStorageService storage;
  late final AuthService auth;

  _Harness() {
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
        if (path.endsWith('/token')) return http.Response(jsonEncode(_sessionJson()), 200);
        if (path.endsWith('/logout')) return http.Response('', 204);
        if (path.endsWith('/recover')) return http.Response('{}', 200);
        if (path.endsWith('/user')) return http.Response(jsonEncode(_userJson()), 200);
        return http.Response('{}', 404);
      }),
    );
    backend = ApiClient(
      baseUrl: 'https://backend.test',
      httpClient: MockClient((req) async {
        requests.add(req);
        if (req.url.path == '/v1/account/legal/consent' && req.method == 'GET') {
          return http.Response(
            jsonEncode(
              backendHasConsent
                  ? {
                      'status': 'accepted',
                      'user_id': _userId,
                      'terms_version': LegalVersions.currentTermsVersion,
                      'privacy_version': LegalVersions.currentPrivacyVersion,
                      'is_current': true,
                      'accepted_at': 1790000000.0,
                    }
                  : {'status': 'not_accepted', 'terms_version': '', 'privacy_version': ''},
            ),
            200,
          );
        }
        if (req.url.path == '/v1/account/legal/consent') return http.Response('{}', 200);
        if (req.url.path == '/v1/account/me') {
          return http.Response(jsonEncode({'id': _userId, 'tier': 'free'}), 200);
        }
        return http.Response('{}', 200);
      }),
    );
    storage = DeviceSecureStorageService();
    auth = AuthService(
      secureStorage: storage,
      legalConsentService: LegalConsentService(secureStorage: storage, apiClient: backend),
      supabaseClient: supabase,
      apiClient: backend,
    );
  }
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Supabase-backed auth lifecycle', () {
    test('first sign-in without prior consent is resolvable, not a dead end', () async {
      final h = _Harness();
      await h.auth.initialize();

      await expectLater(
        h.auth.signInWithEmail(email: 'collector@example.com', password: 'password123'),
        throwsA(isA<TermsConsentRequiredException>()),
      );
      expect(h.auth.currentState.needsTermsConsent, isTrue);
      expect(h.auth.currentState.isAuthenticated, isFalse);
      expect(AppRouter.redirectFor(h.auth.currentState, AppRouter.main), AppRouter.termsConsent);

      await h.auth.recordTermsReConsent(_userId);
      expect(h.auth.currentState.isAuthenticated, isTrue);
      final consentPost = h.requests.where(
        (r) => r.url.path == '/v1/account/legal/consent' && r.method == 'POST',
      );
      expect(consentPost, isNotEmpty);
      expect(consentPost.last.headers['Authorization'], 'Bearer header.payload.signature');
    });

    test('consent already on the server (new device) does not re-prompt', () async {
      final h = _Harness()..backendHasConsent = true;
      await h.auth.initialize();
      final state = await h.auth.signInWithEmail(
        email: 'collector@example.com',
        password: 'password123',
      );
      expect(state.isAuthenticated, isTrue);
    });

    test('consent given before an OAuth / email-confirmation round trip is recorded when the session arrives', () async {
      final h = _Harness();
      await h.auth.initialize();
      // What signInWithGoogle/signUp store before handing off to the browser / inbox.
      await h.storage.write(key: 'coinscan_pending_terms_consent', value: 'oauth');

      // The session then arrives through Supabase's own auth events.
      await h.supabase.auth.signInWithPassword(email: 'collector@example.com', password: 'x');
      await _settle();

      expect(h.auth.currentState.isAuthenticated, isTrue);
      expect(await h.storage.read(key: 'coinscan_pending_terms_consent'), isNull);
    });

    test('a sign-out that happens outside the app clears the local identity', () async {
      final h = _Harness()..backendHasConsent = true;
      await h.auth.initialize();
      await h.auth.signInWithEmail(email: 'collector@example.com', password: 'password123');
      expect(h.auth.currentState.isAuthenticated, isTrue);

      await h.supabase.auth.signOut();
      await _settle();

      expect(h.auth.currentState.user, isNull);
      expect(await h.storage.read(key: SecureStorageService.keyAuthToken), isNull);
    });

    test('a cached token is never resurrected without a Supabase session', () async {
      final h = _Harness();
      await h.storage.write(key: SecureStorageService.keyAuthToken, value: 'stale-token');
      await h.storage.write(key: SecureStorageService.keyUserId, value: _userId);

      await h.auth.initialize();

      expect(h.auth.currentState.isAuthenticated, isFalse);
      expect(h.auth.currentToken, isNull);
      expect(await h.storage.read(key: SecureStorageService.keyAuthToken), isNull);
    });

    test('password reset really calls the account service', () async {
      final h = _Harness();
      await h.auth.sendPasswordReset('collector@example.com');
      expect(h.requests.any((r) => r.url.path.endsWith('/recover')), isTrue);
    });

    test('sign-up requires consent before any account is created', () async {
      final h = _Harness();
      await expectLater(
        h.auth.signUpWithEmail(email: 'a@example.com', password: 'password123'),
        throwsA(isA<TermsConsentRequiredException>()),
      );
      expect(h.requests.where((r) => r.url.path.endsWith('/signup')), isEmpty);
    });
  });

  group('Router redirects', () {
    final user = UserProfile(
      userId: _userId,
      email: 'a@example.com',
      displayName: 'A',
      createdAt: DateTime(2026),
    );

    test('password recovery always lands on the set-new-password screen', () {
      final s = AuthState.passwordRecovery(user: user, token: 't');
      expect(AppRouter.redirectFor(s, AppRouter.main), AppRouter.setNewPassword);
      expect(AppRouter.redirectFor(s, AppRouter.setNewPassword), isNull);
    });

    test('guests may use the app; signed-in users leave the auth flow', () {
      expect(AppRouter.redirectFor(const AuthState.guest(), AppRouter.main), isNull);
      final signedIn = AuthState(user: user, token: 't');
      expect(AppRouter.redirectFor(signedIn, AppRouter.login), AppRouter.main);
      expect(AppRouter.redirectFor(signedIn, AppRouter.termsConsent), AppRouter.main);
    });
  });

  group('Auth screens', () {
    Future<void> pumpRouted(WidgetTester tester, Widget login) async {
      final router = GoRouter(
        initialLocation: '/login',
        routes: [
          GoRoute(path: '/login', builder: (_, __) => login),
          GoRoute(
            path: '/forgot-password',
            builder: (_, s) => ForgotPasswordScreen(initialEmail: s.extra as String?),
          ),
          GoRoute(path: '/signup', builder: (_, __) => const SignUpScreen()),
          GoRoute(path: '/', builder: (_, __) => const SizedBox()),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
    }

    testWidgets('login offers real account flows and no fake Face ID', (tester) async {
      await pumpRouted(tester, const LoginScreen());
      expect(find.textContaining('Face ID'), findsNothing);
      expect(find.byKey(const ValueKey('create_account_link')), findsOneWidget);

      await tester.tap(find.text('Forgot?'));
      await tester.pumpAndSettle();
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    });

    testWidgets('forgot password never claims success when accounts are unavailable', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ForgotPasswordScreen(authService: AuthService())),
      );
      await tester.enterText(find.byKey(const ValueKey('reset_email')), 'a@example.com');
      await tester.tap(find.byKey(const ValueKey('reset_submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('auth_error_banner')), findsOneWidget);
      expect(find.textContaining('we’ve sent a link'), findsNothing);
    });

    testWidgets('terms consent screen needs an explicit tick and offers sign-out', (tester) async {
      await tester.pumpWidget(MaterialApp(home: TermsConsentScreen(authService: AuthService())));
      final accept = tester.widget<GoldButton>(find.byKey(const ValueKey('consent_accept')));
      expect(accept.onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('terms_checkbox')));
      await tester.pump();
      expect(
        tester.widget<GoldButton>(find.byKey(const ValueKey('consent_accept'))).onPressed,
        isNotNull,
      );
      expect(find.byKey(const ValueKey('consent_sign_out')), findsOneWidget);
    });

    testWidgets('sign-up refuses to submit without consent', (tester) async {
      await tester.pumpWidget(MaterialApp(home: SignUpScreen(authService: AuthService())));
      await tester.enterText(find.byKey(const ValueKey('signup_email')), 'a@example.com');
      await tester.enterText(find.byKey(const ValueKey('signup_password')), 'password123');
      await tester.enterText(find.byKey(const ValueKey('signup_confirm')), 'password123');
      await tester.ensureVisible(find.byKey(const ValueKey('signup_submit')));
      await tester.tap(find.byKey(const ValueKey('signup_submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auth_error_banner')), findsOneWidget);
    });
  });
}
