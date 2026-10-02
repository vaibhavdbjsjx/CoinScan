// Phase 3: signed-out (guest) scanning stays separate from accounts.
//
// Covers the app side of the guest model:
// - the install ID is sent only with guest scans, never with an account's;
// - the server's guest-limit / unavailable responses become clear outcomes;
// - Save to Vault needs an account and never saves silently after sign-in;
// - local caches are cleared across every sign-in / sign-out transition;
// - purchases need a signed-in account and a guest never gets a paid plan.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:coinvault_ai/core/auth/auth_service.dart';
import 'package:coinvault_ai/core/recognition/guest_install_id.dart';
import 'package:coinvault_ai/core/recognition/recognition_models.dart';
import 'package:coinvault_ai/core/storage/collection_storage_service.dart';
import 'package:coinvault_ai/core/storage/scan_history_service.dart';
import 'package:coinvault_ai/core/storage/secure_storage_service.dart';
import 'package:coinvault_ai/core/subscriptions/revenuecat_subscription_service.dart';
import 'package:coinvault_ai/features/onboarding/login_screen.dart';
import 'package:coinvault_ai/features/scan/scan_screen.dart';
import 'package:coinvault_ai/features/subscription/paywall_screen.dart';

import 'support/auth_harness.dart';

const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

CoinScanInput _input() => CoinScanInput(
  frontImage: CapturedCoinImage(
    path: '',
    side: CaptureSide.front,
    source: CaptureSource.camera,
    capturedAt: DateTime(2026, 9, 30),
    width: 500,
    height: 500,
    fileSizeBytes: 1000,
  ),
);

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

const _identified = RecognitionResult(
  status: RecognitionStatus.identified,
  message: 'Identified.',
  candidates: [
    RecognitionCandidate(
      coinId: 'numista_1492',
      providerName: 'CoinScan',
      identity: CoinIdentity(
        country: 'United States',
        denomination: '1 Dollar',
        year: 1882,
        mint: 'CC',
        numistaId: 1492,
      ),
      confidence: RecognitionConfidence(
        level: ConfidenceLevel.high,
        overallScore: 0.9,
        visualScore: 0.9,
        ocrScore: 0.9,
        metadataScore: 0.9,
        explanation: 'Catalogue details agree.',
        corroboratingChecks: 2,
      ),
    ),
  ],
);

class _FixedRecognition implements RecognitionService {
  final RecognitionResult result;
  _FixedRecognition(this.result);

  @override
  Future<RecognitionResult> recognize(CoinScanInput input) async => result;
}

VaultCoinItem _coin(String name) => VaultCoinItem(
  id: '',
  coinName: name,
  country: 'France',
  denomination: '1 Franc',
  dateAdded: DateTime(2026, 9, 30),
);

ScanRecord _scan(String name) => ScanRecord(
  id: 'scan_$name',
  scannedAt: DateTime(2026, 9, 30),
  coinName: name,
);

void _resetStores() {
  for (final s in [CollectionStorageService.instance]) {
    s.setCurrentUser(null);
    s.resetForUserSwitch();
  }
  ScanHistoryService.instance
    ..setCurrentUser(null)
    ..resetForUserSwitch();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalAuth = AuthService.instance;

  setUp(() {
    AuthService.instance = AuthService(
      secureStorage: DeviceSecureStorageService(),
    );
    _resetStores();
  });
  tearDown(() {
    AuthService.instance = originalAuth;
    _resetStores();
  });

  group('Guest scan requests', () {
    late List<http.Request> sent;
    late http.Response reply;
    late MockClient client;

    setUp(() {
      sent = [];
      reply = _json(_identified.toJson(), 200);
      client = MockClient((req) async {
        sent.add(req);
        return reply;
      });
    });

    HttpRecognitionService service({
      String? token,
      GuestInstallId? installId,
    }) => HttpRecognitionService(
      config: RecognitionBackendConfig(
        baseUrl: 'https://api.test',
        authToken: token,
      ),
      httpClient: client,
      installId:
          installId ?? GuestInstallId(storage: DeviceSecureStorageService()),
    );

    test(
      'a guest scan carries a stable random install ID and no credentials',
      () async {
        final storage = DeviceSecureStorageService();
        final guest = service(installId: GuestInstallId(storage: storage));

        await guest.recognize(_input());
        await guest.recognize(_input());

        final ids = sent.map((r) => r.headers[GuestInstallId.header]).toSet();
        expect(ids, hasLength(1));
        expect(Uuid.isValidUUID(fromString: ids.single!), isTrue);
        expect(await storage.read(key: GuestInstallId.storageKey), ids.single);
        expect(
          sent.every((r) => !r.headers.containsKey('Authorization')),
          isTrue,
        );
      },
    );

    test('a signed-in scan never carries the install ID', () async {
      await service(token: 'account-access-token').recognize(_input());

      expect(
        sent.single.headers['Authorization'],
        'Bearer account-access-token',
      );
      expect(sent.single.headers.containsKey(GuestInstallId.header), isFalse);
    });

    test(
      'an unreadable stored install ID is replaced with a fresh random one',
      () async {
        final storage = DeviceSecureStorageService();
        await storage.write(
          key: GuestInstallId.storageKey,
          value: 'not-a-uuid',
        );

        final id = await GuestInstallId(storage: storage).value();

        expect(Uuid.isValidUUID(fromString: id), isTrue);
        expect(await storage.read(key: GuestInstallId.storageKey), id);
      },
    );

    test(
      'the guest daily limit becomes a sign-in prompt reason, not raw server text',
      () async {
        reply = _json({
          'detail': {
            'error': 'guest_daily_limit_reached',
            'message':
                'You’ve used today’s 2 free guest scans. Create a free account to keep scanning.',
            'limit': 2,
            'resets_at_utc': '2026-09-30T23:59:59Z',
          },
        }, 429);

        final result = await service().recognize(_input());

        expect(result.status, RecognitionStatus.error);
        expect(result.guestLimitReached, isTrue);
        expect(
          result.message,
          startsWith('You’ve used today’s 2 free guest scans'),
        );
        expect(result.message, isNot(contains('{')));
        expect(result.processingMetadata['limit'], 2);
        expect(result.candidates, isEmpty);
      },
    );

    test(
      'an account quota message is shown as text and is not a guest limit',
      () async {
        reply = _json({
          'detail': {
            'error': 'daily_quota_exceeded',
            'message':
                'You have reached your daily limit of 3 scans for the free tier.',
            'limit': 3,
          },
        }, 429);

        final result = await service(token: 't').recognize(_input());

        expect(result.errorCode, 'daily_quota_exceeded');
        expect(result.guestLimitReached, isFalse);
        expect(
          result.message,
          'You have reached your daily limit of 3 scans for the free tier.',
        );
      },
    );

    test(
      'guest scanning switched off on the server is reported as unavailable',
      () async {
        reply = _json({
          'detail': {
            'error': 'guest_scanning_unavailable',
            'message':
                'Scanning without an account is not available right now. Please sign in.',
          },
        }, 503);

        final result = await service().recognize(_input());

        expect(result.status, RecognitionStatus.unavailable);
        expect(result.errorCode, 'guest_scanning_unavailable');
        expect(result.message, contains('Please sign in'));
      },
    );
  });

  group('Save to Vault needs an account', () {
    // No documents directory: vault and history stay in memory, so no real
    // file I/O runs inside the widget test's fake-async zone. Other path
    // lookups (google_fonts' cache) stay pending, exactly as they do in every
    // other widget test in this suite, so no font download is attempted.
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            _pathProvider,
            (call) => call.method == 'getApplicationDocumentsDirectory'
                ? Future<Object?>.value()
                : Completer<Object?>().future,
          );
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathProvider, null);
    });

    Future<void> scanToResult(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: ScanScreen(
            recognitionService: _FixedRecognition(_identified),
            testImageFactory: (side, source) async => CapturedCoinImage(
              path: '',
              side: side,
              source: source,
              capturedAt: DateTime(2026, 9, 30),
              width: 500,
              height: 500,
              fileSizeBytes: 1000,
            ),
            testPreviewLoader: (_) async => Uint8List(0),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('scan_shutter')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Analyze Front Only'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('save_to_vault')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a guest is asked to sign in, and after signing in must tap Save again',
      (tester) async {
        final h = AuthHarness();
        AuthService.instance = h.auth;
        await h.auth.initialize();
        expect(h.auth.currentState.isAuthenticated, isFalse);

        await scanToResult(tester);

        // Guest taps Save: an account prompt, and nothing is saved anywhere.
        await tester.tap(find.byKey(const ValueKey('save_to_vault')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('account_prompt')), findsOneWidget);
        expect(CollectionStorageService.instance.items, isEmpty);

        // Sign in from the prompt.
        await tester.tap(find.byKey(const ValueKey('account_prompt_signin')));
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('login_email')),
          aliceEmail,
        );
        await tester.enterText(
          find.byKey(const ValueKey('login_password')),
          testPassword,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('terms_checkbox')),
        );
        await tester.tap(find.byKey(const ValueKey('terms_checkbox')));
        await tester.pump();
        await tester.ensureVisible(find.byKey(const ValueKey('login_submit')));
        await tester.tap(find.byKey(const ValueKey('login_submit')));
        await tester.pumpAndSettle();

        // Back on the same result, signed in — and still nothing saved.
        expect(h.auth.currentState.isAuthenticated, isTrue);
        expect(h.auth.currentState.user!.userId, aliceId);
        expect(find.byType(LoginScreen), findsNothing);
        expect(
          find.byKey(const ValueKey('signed_in_tap_save_again')),
          findsOneWidget,
        );
        expect(CollectionStorageService.instance.items, isEmpty);

        // The explicit second tap saves into the account.
        await tester.ensureVisible(find.byKey(const ValueKey('save_to_vault')));
        await tester.tap(find.byKey(const ValueKey('save_to_vault')));
        await tester.pumpAndSettle();
        expect(CollectionStorageService.instance.items, hasLength(1));
        expect(find.text('Saved to Vault'), findsOneWidget);

        // The item belongs to that account: signing out leaves an empty guest vault.
        await h.auth.signOut();
        await tester.pumpAndSettle();
        expect(CollectionStorageService.instance.items, isEmpty);
      },
    );

    testWidgets('dismissing the prompt saves nothing', (tester) async {
      await scanToResult(tester);

      await tester.tap(find.byKey(const ValueKey('save_to_vault')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account_prompt_dismiss')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('account_prompt')), findsNothing);
      expect(find.text('Save to Vault'), findsOneWidget);
      expect(CollectionStorageService.instance.items, isEmpty);
    });

    testWidgets(
      'a guest at the daily limit is offered an account, not the paywall',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const limited = RecognitionResult(
          status: RecognitionStatus.error,
          message:
              'You’ve used today’s 2 free guest scans. Create a free account to keep scanning.',
          processingMetadata: {'error_code': 'guest_daily_limit_reached'},
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ScanScreen(
              recognitionService: _FixedRecognition(limited),
              testImageFactory: (side, source) async => CapturedCoinImage(
                path: '',
                side: side,
                source: source,
                capturedAt: DateTime(2026, 9, 30),
                width: 500,
                height: 500,
                fileSizeBytes: 1000,
              ),
              testPreviewLoader: (_) async => Uint8List(0),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('scan_shutter')));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Analyze Front Only'));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('account_prompt')), findsOneWidget);
        expect(find.text('Create free account'), findsOneWidget);
        expect(find.byType(PaywallScreen), findsNothing);
      },
    );
  });

  group('Local data across sign-in and sign-out', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('coinscan_guest_isolation_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathProvider, (_) async => dir.path);
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathProvider, null);
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<List<String>> vault() async =>
        (await CollectionStorageService.instance.loadCollection(
          forceRefresh: true,
        )).map((i) => i.name).toList();
    Future<List<String?>> history() async =>
        (await ScanHistoryService.instance.loadHistory(
          forceRefresh: true,
        )).map((r) => r.coinName).toList();
    bool guestFilesExist() =>
        File('${dir.path}/collection_vault.json').existsSync() ||
        File('${dir.path}/scan_history.json').existsSync();

    test(
      'user A → sign out → guest → user B: nobody sees anyone else’s data',
      () async {
        final h = AuthHarness();
        AuthService.instance = h.auth;
        await h.auth.initialize();

        await h.signIn(aliceEmail);
        await CollectionStorageService.instance.saveItem(_coin('Alice coin'));
        await ScanHistoryService.instance.addRecord(_scan('Alice scan'));
        expect(await vault(), ['Alice coin']);

        await h.auth.signOut();
        expect(await vault(), isEmpty);
        expect(await history(), isEmpty);
        await ScanHistoryService.instance.addRecord(_scan('Guest scan'));
        expect(await history(), ['Guest scan']);

        await h.signIn(bobEmail);
        expect(await vault(), isEmpty);
        expect(
          await history(),
          isEmpty,
        ); // neither Alice's scans nor the guest's
        expect(guestFilesExist(), isFalse);

        // Alice's data is still hers.
        await h.auth.signOut();
        await h.signIn(aliceEmail);
        expect(await vault(), ['Alice coin']);
        expect(await history(), ['Alice scan']);
      },
    );

    test(
      'guest A → sign in → sign out → guest B: guest data is neither merged nor handed on',
      () async {
        final h = AuthHarness();
        AuthService.instance = h.auth;
        await h.auth.initialize();
        final installId = await GuestInstallId(storage: h.storage).value();

        // Guest A leaves local data (an older app version could also have saved a coin).
        await ScanHistoryService.instance.addRecord(_scan('Guest A scan'));
        await CollectionStorageService.instance.saveItem(_coin('Guest A coin'));
        expect(guestFilesExist(), isTrue);

        await h.signIn(aliceEmail);
        expect(await vault(), isEmpty); // never migrated into the account
        expect(await history(), isEmpty);
        expect(guestFilesExist(), isFalse);

        await h.auth.signOut();
        expect(await vault(), isEmpty); // guest B starts empty
        expect(await history(), isEmpty);

        // The install ID is a device-level rate-limit hint, not guest data: signing
        // in and out does not reset it (and it is never sent while signed in).
        expect(await GuestInstallId(storage: h.storage).value(), installId);
      },
    );
  });

  group('Purchases need an account', () {
    final alice = UserProfile(
      userId: aliceId,
      email: aliceEmail,
      displayName: 'Alice',
      createdAt: DateTime(2026, 9, 30),
    );

    test(
      'purchase / restore require a signed-in account RevenueCat is identified with',
      () {
        final requiresAccount = throwsA(
          isA<PurchaseException>().having(
            (e) => e.requiresAccount,
            'requiresAccount',
            isTrue,
          ),
        );
        final signedIn = AuthState(user: alice, token: 'access-token');

        expect(
          () => RevenueCatSubscriptionService.requireAccount(
            const AuthState.guest(),
            null,
          ),
          requiresAccount,
        );
        expect(
          () => RevenueCatSubscriptionService.requireAccount(
            const AuthState.guest(),
            aliceId,
          ),
          requiresAccount,
        );
        // Signed in, but RevenueCat still holds an anonymous (or another) customer.
        expect(
          () => RevenueCatSubscriptionService.requireAccount(signedIn, null),
          requiresAccount,
        );
        expect(
          () => RevenueCatSubscriptionService.requireAccount(signedIn, bobId),
          requiresAccount,
        );
        // Terms not yet accepted is not a usable account either.
        expect(
          () => RevenueCatSubscriptionService.requireAccount(
            AuthState(
              user: alice,
              token: 'access-token',
              termsConsentRequired: true,
            ),
            aliceId,
          ),
          requiresAccount,
        );

        RevenueCatSubscriptionService.requireAccount(
          signedIn,
          aliceId,
        ); // allowed
      },
    );

    test('an anonymous RevenueCat customer never unlocks a paid plan', () {
      final svc = RevenueCatSubscriptionService();
      svc.applyCustomerInfoForTest(_customerInfo(entitlement: 'pro'));

      expect(svc.state.plan, EntitlementPlan.limited);
      expect(svc.state.marketValuationEnabled, isFalse);
      expect(svc.state.advancedRecognitionEnabled, isFalse);
    });

    test('a signed-in account does get its verified plan', () async {
      final h = AuthHarness();
      AuthService.instance = h.auth;
      await h.auth.initialize();
      await h.signIn(aliceEmail);

      final svc = RevenueCatSubscriptionService();
      svc.applyCustomerInfoForTest(_customerInfo(entitlement: 'pro'));

      expect(svc.state.plan, EntitlementPlan.pro);
    });

    testWidgets(
      'a guest choosing a plan or restoring is asked to sign in; nothing is purchased',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = _RecordingSubscriptions();

        await tester.pumpWidget(
          MaterialApp(home: PaywallScreen(subscriptionService: store)),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('paywall_sign_in_note')),
          findsOneWidget,
        );

        await tester.ensureVisible(find.text('CoinScan Pro').first);
        await tester.tap(find.text('CoinScan Pro').first);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('account_prompt')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('account_prompt_dismiss')));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey('paywall_restore')),
        );
        await tester.tap(find.byKey(const ValueKey('paywall_restore')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('account_prompt')), findsOneWidget);

        expect(store.purchases, isEmpty);
        expect(store.restores, 0);
      },
    );
  });
}

class _RecordingSubscriptions implements SubscriptionService {
  final purchases = <String>[];
  int restores = 0;

  @override
  Future<List<SubscriptionProduct>> availableProducts() async => const [
    SubscriptionProduct(
      productId: 'com.coinscan.plus.yearly',
      title: 'CoinScan Plus',
      description: '30 scans/day',
      priceDisplay: '\$39.99/year',
      priceUsd: 39.99,
      period: BillingPeriod.yearly,
      plan: EntitlementPlan.plus,
    ),
    SubscriptionProduct(
      productId: 'com.coinscan.pro.yearly',
      title: 'CoinScan Pro',
      description: '100 scans/day',
      priceDisplay: '\$79.99/year',
      priceUsd: 79.99,
      period: BillingPeriod.yearly,
      plan: EntitlementPlan.pro,
    ),
  ];

  @override
  Future<EntitlementState> purchase(String productId) async {
    purchases.add(productId);
    return const EntitlementState.limited();
  }

  @override
  Future<EntitlementState> restorePurchases() async {
    restores++;
    return const EntitlementState.limited();
  }

  @override
  Future<EntitlementState> currentEntitlement() async =>
      const EntitlementState.limited();

  @override
  Future<EntitlementState> recordScanUsage() async =>
      const EntitlementState.limited();

  @override
  Future<void> reset() async {}
}

CustomerInfo _customerInfo({required String entitlement}) {
  final now = DateTime.now().toUtc();
  final expires = now.add(const Duration(days: 30)).toIso8601String();
  final ent = {
    entitlement: {
      'identifier': entitlement,
      'isActive': true,
      'willRenew': true,
      'latestPurchaseDate': now.toIso8601String(),
      'originalPurchaseDate': now.toIso8601String(),
      'expirationDate': expires,
      'productIdentifier': 'com.coinscan.$entitlement.monthly',
      'isSandbox': true,
      'ownershipType': 'PURCHASED',
      'store': 'APP_STORE',
      'periodType': 'NORMAL',
      'unsubscribeDetectedAt': null,
      'billingIssueDetectedAt': null,
    },
  };
  return CustomerInfo.fromJson({
    'entitlements': {
      'all': ent,
      'active': ent,
      'verification': 'NOT_REQUESTED',
    },
    'allPurchaseDates': const {},
    'activeSubscriptions': ['com.coinscan.$entitlement.monthly'],
    'allPurchasedProductIdentifiers': ['com.coinscan.$entitlement.monthly'],
    'nonSubscriptionTransactions': const [],
    'firstSeen': now.toIso8601String(),
    'originalAppUserId': r'$RCAnonymousID:test',
    'allExpirationDates': const {},
    'requestDate': now.toIso8601String(),
    'latestExpirationDate': expires,
    'originalPurchaseDate': null,
    'originalApplicationVersion': null,
    'managementURL': null,
    'subscriptions': const {},
    'nonSubscriptions': const {},
  });
}
