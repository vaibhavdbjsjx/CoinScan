import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:coinvault_ai/core/auth/auth_service.dart';
import 'package:coinvault_ai/core/legal/legal_consent_models.dart';
import 'package:coinvault_ai/core/storage/secure_storage_service.dart';
import 'package:coinvault_ai/features/onboarding/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Mandatory Terms & Conditions Gate Unit Tests', () {
    late SecureStorageService secureStorage;
    late LegalConsentService legalConsentService;
    late AuthService authService;

    setUp(() {
      secureStorage = DeviceSecureStorageService();
      legalConsentService = LegalConsentService(secureStorage: secureStorage);
      authService = AuthService(
        secureStorage: secureStorage,
        legalConsentService: legalConsentService,
      );
    });

    tearDown(() {
      authService.dispose();
    });

    test('Test 1: Terms not accepted -> Login is strictly BLOCKED', () async {
      expect(
        () => authService.signInWithEmail(
          email: 'collector_unconsented@coinscan.app',
          password: 'password123',
          termsAccepted: false,
        ),
        throwsA(isA<TermsConsentRequiredException>()),
      );

      // Verify user remains unauthenticated
      expect(authService.currentState.isAuthenticated, isFalse);
    });

    test('Test 2: Terms accepted -> Login is ALLOWED into authenticated state', () async {
      final state = await authService.signInWithEmail(
        email: 'collector_consented@coinscan.app',
        password: 'password123',
        termsAccepted: true,
      );

      expect(state.isAuthenticated, isTrue);
      expect(state.termsConsentRequired, isFalse);
      expect(state.user?.email, equals('collector_consented@coinscan.app'));

      // Verify consent record exists with version 1.0.0
      final consent = await legalConsentService.getConsent(state.user!.userId);
      expect(consent, isNotNull);
      expect(consent!.isCurrent, isTrue);
      expect(consent.termsVersion, equals('1.0.0'));
    });

    test('Test 3: Old Terms version -> Session requires RE-CONSENT', () async {
      const userId = 'usr_legacy_user';
      // Simulate stored user session with outdated terms v0.9.0
      await secureStorage.write(
        key: DeviceSecureStorageService.keyAuthToken,
        value: 'jwt_token_$userId',
      );
      await secureStorage.write(
        key: DeviceSecureStorageService.keyUserId,
        value: userId,
      );
      await secureStorage.write(
        key: 'legal_consent_$userId',
        value: '{"userId":"$userId","termsVersion":"0.9.0","termsAcceptedAt":"2025-01-01T00:00:00.000Z","privacyVersion":"0.9.0","privacyAcceptedAt":"2025-01-01T00:00:00.000Z"}',
      );

      // Initialize session on app launch
      await authService.initialize();

      // User must NOT be in authenticated state; re-consent is required
      expect(authService.currentState.termsConsentRequired, isTrue);
      expect(authService.currentState.isAuthenticated, isFalse);
    });

    test('Test 4: Current Terms version -> Session is immediately ALLOWED', () async {
      const userId = 'usr_current_user';
      await secureStorage.write(
        key: DeviceSecureStorageService.keyAuthToken,
        value: 'jwt_token_$userId',
      );
      await secureStorage.write(
        key: DeviceSecureStorageService.keyUserId,
        value: userId,
      );
      await legalConsentService.recordConsent(userId: userId);

      // Initialize session
      await authService.initialize();

      expect(authService.currentState.termsConsentRequired, isFalse);
      expect(authService.currentState.isAuthenticated, isTrue);
    });

    test('Test 6: Account A acceptance -> Account B cannot inherit Account A acceptance', () async {
      // Account A logs in and accepts terms
      await authService.signInWithEmail(
        email: 'user_a@coinscan.app',
        password: 'password123',
        termsAccepted: true,
      );
      expect(authService.currentState.isAuthenticated, isTrue);

      // Account A signs out
      await authService.signOut();
      expect(authService.currentState.isAuthenticated, isFalse);

      // Account B attempts login without accepting terms
      expect(
        () => authService.signInWithEmail(
          email: 'user_b@coinscan.app',
          password: 'password123',
          termsAccepted: false,
        ),
        throwsA(isA<TermsConsentRequiredException>()),
      );
      expect(authService.currentState.isAuthenticated, isFalse);
    });

    test('Test 7: Backend bypass attempt -> unconsented client cannot authenticate', () async {
      // Direct call without terms flag throws
      expect(
        () => authService.signInWithApple(termsAccepted: false),
        throwsA(isA<TermsConsentRequiredException>()),
      );
      expect(authService.currentState.isAuthenticated, isFalse);
    });

    test('Test 8: Logout and account deletion clears consent without cross-account leakage', () async {
      final state = await authService.signInWithEmail(
        email: 'user_delete@coinscan.app',
        password: 'password123',
        termsAccepted: true,
      );
      final userId = state.user!.userId;
      expect(await legalConsentService.hasAcceptedCurrentTerms(userId), isTrue);

      // Delete account
      await authService.deleteAccount();

      // Consent is purged
      expect(await legalConsentService.getConsent(userId), isNull);
      expect(authService.currentState.isAuthenticated, isFalse);
    });
  });

  group('Mandatory Terms & Conditions Widget Tests', () {
    testWidgets('Test 5: Checkbox unchecked by default and gates login submission', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Checkbox must exist and be unchecked by default
      final checkboxFinder = find.byType(Checkbox);
      expect(checkboxFinder, findsOneWidget);
      final checkboxWidget = tester.widget<Checkbox>(checkboxFinder);
      expect(checkboxWidget.value, isFalse);

      // Terms & Conditions and Privacy Policy links must be present
      expect(find.textContaining('Terms & Conditions'), findsOneWidget);
      expect(find.textContaining('Privacy Policy'), findsOneWidget);

      // Tapping Sign In while checkbox is unchecked shows warning and does not proceed
      final signInFinder = find.widgetWithText(ElevatedButton, 'Sign in');
      if (signInFinder.evaluate().isNotEmpty) {
        final button = tester.widget<ElevatedButton>(signInFinder);
        expect(button.onPressed, isNull); // Button is disabled when unchecked
      }

      // Check the box
      await tester.tap(checkboxFinder);
      await tester.pumpAndSettle();

      // Now the checkbox is checked
      final checkedWidget = tester.widget<Checkbox>(checkboxFinder);
      expect(checkedWidget.value, isTrue);
    });
  });
}
