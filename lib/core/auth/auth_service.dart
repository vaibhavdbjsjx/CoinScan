import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../legal/legal_consent_models.dart';
import '../network/api_client.dart';
import '../storage/collection_storage_service.dart';
import '../storage/scan_history_service.dart';
import '../storage/secure_storage_service.dart';

/// Exception thrown when an authentication attempt is made without accepting mandatory Terms & Conditions.
class TermsConsentRequiredException implements Exception {
  final String message;
  const TermsConsentRequiredException([
    this.message =
        'Acceptance of the current Terms & Conditions and Privacy Policy is mandatory before entering authenticated state.',
  ]);

  @override
  String toString() => message;
}

/// Thrown when an account operation needs the account service (Supabase) but
/// this build has no account service configured.
class AuthConfigurationException implements Exception {
  final String message;
  const AuthConfigurationException(this.message);

  @override
  String toString() => message;
}

/// Representation of a user's authenticated profile.
class UserProfile {
  final String userId;
  final String email;
  final String displayName;
  final String preferredCurrency;
  final String tier;
  final bool isAnonymous;
  final DateTime createdAt;
  final String? avatarUrl;

  const UserProfile({
    required this.userId,
    required this.email,
    required this.displayName,
    this.preferredCurrency = 'USD',
    this.tier = 'free',
    this.isAnonymous = false,
    required this.createdAt,
    this.avatarUrl,
  });

  /// Default unauthenticated guest profile.
  factory UserProfile.guest() => UserProfile(
    userId: 'guest_user',
    email: '',
    displayName: 'Guest Collector',
    preferredCurrency: 'USD',
    tier: 'free',
    isAnonymous: true,
    createdAt: DateTime.now(),
  );
}

/// Snapshot of authentication state.
class AuthState {
  final UserProfile? user;
  final String? token;
  final bool isLoading;
  final bool termsConsentRequired;
  final bool isEmailVerificationPending;
  final String? pendingVerificationEmail;

  /// A password-reset link was opened: the user must choose a new password
  /// before continuing. The session is only usable for that purpose.
  final bool isPasswordRecovery;

  /// User is authenticated ONLY IF user exists, is not anonymous, AND has satisfied mandatory terms acceptance.
  bool get isAuthenticated =>
      user != null &&
      !user!.isAnonymous &&
      !termsConsentRequired &&
      !isEmailVerificationPending &&
      !isPasswordRecovery &&
      token != null &&
      token != 'pending_verification';

  bool get isGuest =>
      user == null ||
      user!.isAnonymous ||
      termsConsentRequired ||
      isEmailVerificationPending ||
      isPasswordRecovery;

  /// Signed in, but the current Terms / Privacy Policy still need accepting.
  bool get needsTermsConsent =>
      user != null && !user!.isAnonymous && termsConsentRequired && !isPasswordRecovery;

  const AuthState({
    this.user,
    this.token,
    this.isLoading = false,
    this.termsConsentRequired = false,
    this.isEmailVerificationPending = false,
    this.pendingVerificationEmail,
    this.isPasswordRecovery = false,
  });

  const AuthState.unauthenticated()
    : user = null,
      token = null,
      isLoading = false,
      termsConsentRequired = false,
      isEmailVerificationPending = false,
      pendingVerificationEmail = null,
      isPasswordRecovery = false;

  const AuthState.guest()
    : user = null,
      token = null,
      isLoading = false,
      termsConsentRequired = false,
      isEmailVerificationPending = false,
      pendingVerificationEmail = null,
      isPasswordRecovery = false;

  const AuthState.emailVerificationPending({required String email})
    : user = null,
      token = null,
      isLoading = false,
      termsConsentRequired = false,
      isEmailVerificationPending = true,
      pendingVerificationEmail = email,
      isPasswordRecovery = false;

  const AuthState.passwordRecovery({required this.user, required this.token})
    : isLoading = false,
      termsConsentRequired = false,
      isEmailVerificationPending = false,
      pendingVerificationEmail = null,
      isPasswordRecovery = true;
}

/// Production-ready Authentication & Session Manager powered by Supabase Auth.
///
/// Features:
/// 1. Real Supabase Auth sessions with cryptographically verified JWT bearer tokens.
/// 2. Strict RFC 4122 UUID user identities matching PostgreSQL `public.users.id`.
/// 3. Persistent Keychain/Keystore session caching via [SecureStorageService].
/// 4. Mandatory Terms & Conditions consent gate with server synchronization.
/// 5. Full GDPR / App Store compliant account deletion cascading to the backend.
/// 6. Real password reset (email link + set new password) and sign-up confirmation.
///
/// When Supabase is configured it is the only source of truth for sessions:
/// a token cached in secure storage is never resurrected on its own.
class AuthService with ChangeNotifier {
  static AuthService instance = AuthService();

  /// Deep link Supabase redirects to after OAuth, email confirmation and
  /// password-reset links. Registered in Info.plist and AndroidManifest.xml,
  /// and must be in the Supabase "Redirect URLs" allow-list.
  static const String authRedirectUrl = 'com.coinvault.coinvaultai://login-callback';

  /// Set when the user accepted the Terms before a flow that completes later
  /// (OAuth redirect, email confirmation), so consent can be recorded as soon as
  /// the session arrives instead of asking again.
  static const String _pendingConsentKey = 'coinscan_pending_terms_consent';

  final SecureStorageService _secureStorage;
  final LegalConsentService _legalConsentService;
  final SupabaseClient? _explicitSupabaseClient;
  final ApiClient? _explicitApiClient;

  AuthState _state = const AuthState.guest();
  final StreamController<AuthState> _authStateController =
      StreamController<AuthState>.broadcast();

  /// >0 while an explicit sign-in / sign-up call is completing; the auth-event
  /// listener then leaves state handling to that call.
  int _explicitAuthInProgress = 0;
  bool _signingOut = false;

  Stream<AuthState> get authStateChanges => _authStateController.stream;
  AuthState get currentState => _state;
  String? get currentToken => _state.token;

  bool get isAccountServiceConfigured => _supabaseClient != null;

  void _updateState(AuthState newState) {
    _state = newState;
    _authStateController.add(_state);
    notifyListeners();
  }

  void _configureApiClient() {
    ApiClient.configure(
      tokenProvider: () async => currentToken,
      tokenRefresher: () async => refreshToken(),
      onSessionExpired: () async => signOut(),
    );
  }

  /// Refreshes the active Supabase Auth session token when expired.
  Future<String?> refreshToken() async {
    final client = _supabaseClient;
    if (client != null) {
      try {
        final res = await client.auth.refreshSession();
        final session = res.session;
        if (session != null) {
          final newToken = session.accessToken;
          await _secureStorage.write(
            key: SecureStorageService.keyAuthToken,
            value: newToken,
          );
          _updateState(AuthState(
            user: _state.user,
            token: newToken,
            termsConsentRequired: _state.termsConsentRequired,
            isPasswordRecovery: _state.isPasswordRecovery,
          ));
          return newToken;
        }
      } catch (e) {
        debugPrint('Supabase session refresh failed: $e');
      }
    }
    return null;
  }

  /// Fetches authoritative user profile from backend GET /v1/account/me.
  Future<UserProfile?> fetchAuthoritativeProfile() async {
    if (!_state.isAuthenticated) return null;
    try {
      final res = await _apiClient.get('/v1/account/me');
      if (res is Map<String, dynamic> && res['id'] != null) {
        final profile = UserProfile(
          userId: res['id'].toString(),
          email: _state.user?.email.isNotEmpty == true
              ? _state.user!.email
              : (res['email'] as String? ?? ''),
          displayName: res['display_name'] as String? ?? _state.user?.displayName ?? 'Collector',
          preferredCurrency: res['preferred_currency'] as String? ?? 'USD',
          tier: res['tier'] as String? ?? 'free',
          isAnonymous: false,
          createdAt: res['created_at'] != null
              ? DateTime.fromMillisecondsSinceEpoch(((res['created_at'] as num) * 1000).toInt())
              : (_state.user?.createdAt ?? DateTime.now()),
        );
        _updateState(AuthState(
          user: profile,
          token: _state.token,
          termsConsentRequired: _state.termsConsentRequired,
        ));
        return profile;
      }
    } catch (e) {
      debugPrint('Could not fetch authoritative backend profile: $e');
    }
    return _state.user;
  }

  AuthService({
    SecureStorageService? secureStorage,
    LegalConsentService? legalConsentService,
    SupabaseClient? supabaseClient,
    ApiClient? apiClient,
  })  : _secureStorage = secureStorage ?? PersistentSecureStorageService(),
        _legalConsentService =
            legalConsentService ?? LegalConsentService.instance,
        _explicitSupabaseClient = supabaseClient,
        _explicitApiClient = apiClient;

  SupabaseClient? get _supabaseClient {
    if (_explicitSupabaseClient != null) {
      return _explicitSupabaseClient;
    }
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  ApiClient get _apiClient => _explicitApiClient ?? ApiClient.instance;

  StreamSubscription? _authSubscription;

  void _listenToAuthChanges(SupabaseClient client) {
    if (_authSubscription != null) return;
    _authSubscription = client.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.signedOut || session == null) {
        // Session ended outside an explicit signOut() (revoked, refresh failed,
        // signed out elsewhere): drop local state so no stale identity remains.
        if (!_signingOut && _state.user != null) {
          await _clearLocalSession();
          _updateState(const AuthState.guest());
        }
        return;
      }
      if (session.isExpired) return;

      if (event == AuthChangeEvent.passwordRecovery) {
        await _adoptSession(session, recovery: true);
        return;
      }
      if (_explicitAuthInProgress > 0 && event == AuthChangeEvent.signedIn) {
        return; // the in-flight sign-in call sets the final state itself
      }
      await _adoptSession(session);
    });
  }

  String _displayNameFor(User user) {
    final email = user.email ?? '';
    return user.userMetadata?['full_name'] as String? ??
        user.userMetadata?['name'] as String? ??
        user.userMetadata?['display_name'] as String? ??
        (email.isNotEmpty ? email.split('@').first : 'Collector');
  }

  /// Adopts a verified Supabase session as the app's identity.
  Future<void> _adoptSession(Session session, {bool recovery = false}) async {
    final user = session.user;
    final userId = user.id;
    final token = session.accessToken;
    final email = user.email ?? '';
    final displayName = _displayNameFor(user);

    final isNewIdentity = _state.user?.userId != userId;
    await _persistSession(
      token: token,
      userId: userId,
      email: email,
      displayName: displayName,
    );

    final profile = UserProfile(
      userId: userId,
      email: email,
      displayName: displayName,
      isAnonymous: false,
      createdAt: DateTime.tryParse(user.createdAt) ?? DateTime.now(),
    );

    if (isNewIdentity) await _enterAccountStorage(userId);
    _configureApiClient();

    if (recovery) {
      _updateState(AuthState.passwordRecovery(user: profile, token: token));
      return;
    }

    final hasAccepted = await _resolveConsent(userId, token);
    _updateState(AuthState(
      user: profile,
      token: token,
      termsConsentRequired: !hasAccepted,
    ));
    if (hasAccepted) unawaited(fetchAuthoritativeProfile());
  }

  /// Whether [userId] has accepted the current Terms, recording consent the
  /// user already gave before an OAuth / email-confirmation round trip, or
  /// restoring it from the backend (e.g. on a new device).
  Future<bool> _resolveConsent(String userId, String token) async {
    if (await _legalConsentService.hasAcceptedCurrentTerms(userId)) return true;

    final pending = await _secureStorage.read(key: _pendingConsentKey);
    if (pending != null) {
      try {
        await _legalConsentService.recordConsent(userId: userId, accessToken: token);
        await _secureStorage.delete(key: _pendingConsentKey);
        return true;
      } catch (e) {
        debugPrint('Could not record pending consent: $e');
      }
    }

    final synced = await _legalConsentService.syncConsentWithBackend(
      userId,
      accessToken: token,
    );
    return synced?.isCurrent ?? false;
  }

  /// Switches local storage to [userId] and removes signed-out (guest) data so
  /// it can never be shown to, or merged into, an account.
  Future<void> _enterAccountStorage(String userId) async {
    await CollectionStorageService.instance.clearGuestData();
    await ScanHistoryService.instance.clearGuestData();
    CollectionStorageService.instance.setCurrentUser(userId);
    ScanHistoryService.instance.setCurrentUser(userId);
  }

  /// Restores session on app startup, validating terms version adherence.
  Future<void> initialize() async {
    final client = _supabaseClient;
    if (client != null) {
      _listenToAuthChanges(client);
      Session? session = client.auth.currentSession;
      if (session != null && session.isExpired) {
        try {
          session = (await client.auth.refreshSession()).session;
        } catch (e) {
          debugPrint('Stored session could not be refreshed: $e');
          session = null;
        }
      }
      if (session != null && !session.isExpired) {
        await _adoptSession(session);
        return;
      }
      // Supabase is the source of truth: never resurrect a cached token.
      await _clearLocalSession();
      _configureApiClient();
      _updateState(const AuthState.guest());
      return;
    }

    // Local development / tests without an account service: restore the
    // development session cached in secure storage.
    final token = await _secureStorage.read(
      key: SecureStorageService.keyAuthToken,
    );
    final userId = await _secureStorage.read(
      key: SecureStorageService.keyUserId,
    );
    final email = await _secureStorage.read(
      key: SecureStorageService.keyUserEmail,
    );
    final displayName = await _secureStorage.read(
      key: SecureStorageService.keyUserDisplayName,
    );

    if (token != null && userId != null) {
      final profile = UserProfile(
        userId: userId,
        email: email ?? '$userId@coinscan.app',
        displayName: displayName ?? 'Collector',
        isAnonymous: false,
        createdAt: DateTime.now(),
      );

      final hasAccepted =
          await _legalConsentService.hasAcceptedCurrentTerms(userId);
      CollectionStorageService.instance.setCurrentUser(userId);
      ScanHistoryService.instance.setCurrentUser(userId);
      _configureApiClient();
      _updateState(AuthState(
        user: profile,
        token: token,
        termsConsentRequired: !hasAccepted,
      ));
      unawaited(fetchAuthoritativeProfile());
    } else {
      CollectionStorageService.instance.setCurrentUser(null);
      ScanHistoryService.instance.setCurrentUser(null);
      _configureApiClient();
      _updateState(const AuthState.guest());
    }
  }

  void _requireAccountServiceInProduction() {
    if (AppConfig.isInitialized && AppConfig.instance.isProduction) {
      throw const AuthConfigurationException(
        'Accounts are not available in this build: the account service is not configured.',
      );
    }
  }

  /// Sign up with Email and Password using Supabase Auth.
  Future<AuthState> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
    bool termsAccepted = false,
  }) async {
    // Consent is required before an account is created, not after.
    if (!termsAccepted) {
      throw const TermsConsentRequiredException();
    }

    final client = _supabaseClient;
    String userId;
    String token;
    final resolvedDisplayName =
        displayName ?? (email.isNotEmpty ? email.split('@').first : 'Collector');

    _explicitAuthInProgress++;
    try {
      if (client != null) {
        final res = await client.auth.signUp(
          email: email,
          password: password,
          data: {'display_name': resolvedDisplayName},
          emailRedirectTo: kIsWeb ? null : authRedirectUrl,
        );
        final user = res.user;
        final session = res.session;
        if (user == null) {
          throw const AuthException('Could not create account.');
        }
        if (session == null) {
          // Email confirmation required. Remember the consent given here so it
          // is recorded when the confirmed session arrives.
          await _secureStorage.write(key: _pendingConsentKey, value: 'signup');
          _updateState(AuthState.emailVerificationPending(email: email));
          return _state;
        }
        userId = user.id;
        token = session.accessToken;
      } else {
        _requireAccountServiceInProduction();
        // Non-production test/offline fallback: Generate RFC 4122 UUID v5
        userId = const Uuid().v5(Namespace.url.value, 'mailto:$email');
        token = 'mock_jwt_token_$userId';
      }

      await _legalConsentService.recordConsent(userId: userId, accessToken: token);
      await _persistSession(
        token: token,
        userId: userId,
        email: email,
        displayName: resolvedDisplayName,
      );
      final profile = UserProfile(
        userId: userId,
        email: email,
        displayName: resolvedDisplayName,
        isAnonymous: false,
        createdAt: DateTime.now(),
      );
      await _enterAccountStorage(userId);
      _configureApiClient();
      _updateState(AuthState(user: profile, token: token, termsConsentRequired: false));
      unawaited(fetchAuthoritativeProfile());
      return _state;
    } finally {
      _explicitAuthInProgress--;
    }
  }

  /// Resends the sign-up confirmation email.
  Future<void> resendSignUpConfirmation(String email) async {
    final client = _supabaseClient;
    if (client == null) {
      throw const AuthConfigurationException('The account service is not configured in this build.');
    }
    await client.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: kIsWeb ? null : authRedirectUrl,
    );
  }

  /// Sign in with Email and Password with mandatory Terms & Conditions gate.
  Future<AuthState> signInWithEmail({
    required String email,
    required String password,
    bool termsAccepted = false,
  }) async {
    final client = _supabaseClient;
    String userId;
    String token;
    String displayName = email.isNotEmpty ? email.split('@').first : 'Collector';

    _explicitAuthInProgress++;
    try {
      if (client != null) {
        final res = await client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        final user = res.user;
        final session = res.session;
        if (user == null || session == null) {
          throw const AuthException('Invalid email or password.');
        }
        userId = user.id;
        token = session.accessToken;
        displayName = _displayNameFor(user);
      } else {
        _requireAccountServiceInProduction();
        // Non-production test/offline fallback: Generate RFC 4122 UUID v5
        userId = const Uuid().v5(Namespace.url.value, 'mailto:$email');
        token = 'mock_jwt_token_$userId';
      }

      // Gate: accepted in this flow, or the current version was already accepted
      // for this account (locally or on the server).
      var alreadyAccepted =
          await _legalConsentService.hasAcceptedCurrentTerms(userId);
      if (!alreadyAccepted && !termsAccepted && client != null) {
        final synced = await _legalConsentService.syncConsentWithBackend(
          userId,
          accessToken: token,
        );
        alreadyAccepted = synced?.isCurrent ?? false;
      }
      if (!termsAccepted && !alreadyAccepted) {
        if (client != null) {
          // The Supabase session exists: keep it, and let the consent screen
          // resolve it instead of leaving the user in limbo.
          await _adoptSession(client.auth.currentSession!);
        }
        throw const TermsConsentRequiredException();
      }

      if (termsAccepted) {
        await _legalConsentService.recordConsent(userId: userId, accessToken: token);
      }

      await _persistSession(
        token: token,
        userId: userId,
        email: email,
        displayName: displayName,
      );

      final profile = UserProfile(
        userId: userId,
        email: email,
        displayName: displayName,
        isAnonymous: false,
        createdAt: DateTime.now(),
      );

      await _enterAccountStorage(userId);
      _configureApiClient();
      _updateState(AuthState(user: profile, token: token, termsConsentRequired: false));
      unawaited(fetchAuthoritativeProfile());
      return _state;
    } finally {
      _explicitAuthInProgress--;
    }
  }

  Future<AuthState> _signInWithProvider(
    OAuthProvider provider,
    String devEmail,
    String devDisplayName,
    bool termsAccepted,
  ) async {
    final client = _supabaseClient;
    if (client != null) {
      if (!termsAccepted) {
        throw const TermsConsentRequiredException();
      }
      // The provider sign-in completes in the browser; remember that the user
      // already accepted the Terms so consent is recorded when the session
      // arrives (no second prompt, no dead end).
      await _secureStorage.write(key: _pendingConsentKey, value: 'oauth');
      final success = await client.auth.signInWithOAuth(
        provider,
        redirectTo: kIsWeb ? null : authRedirectUrl,
      );
      if (!success) {
        await _secureStorage.delete(key: _pendingConsentKey);
        throw AuthException('${provider.name} sign in was cancelled.');
      }
      final session = client.auth.currentSession;
      if (session != null && !session.isExpired) {
        await _adoptSession(session);
      } else {
        _updateState(const AuthState(isLoading: true));
      }
      return _state;
    }

    _requireAccountServiceInProduction();
    final userId = const Uuid().v5(Namespace.url.value, 'mailto:$devEmail');
    final token = 'mock_jwt_token_${provider.name}_$userId';
    final alreadyAccepted =
        await _legalConsentService.hasAcceptedCurrentTerms(userId);
    if (!termsAccepted && !alreadyAccepted) {
      throw const TermsConsentRequiredException();
    }
    if (termsAccepted) {
      await _legalConsentService.recordConsent(userId: userId, accessToken: token);
    }
    await _persistSession(
      token: token,
      userId: userId,
      email: devEmail,
      displayName: devDisplayName,
    );
    final profile = UserProfile(
      userId: userId,
      email: devEmail,
      displayName: devDisplayName,
      isAnonymous: false,
      createdAt: DateTime.now(),
    );
    await _enterAccountStorage(userId);
    _configureApiClient();
    _updateState(AuthState(user: profile, token: token, termsConsentRequired: false));
    unawaited(fetchAuthoritativeProfile());
    return _state;
  }

  /// Sign in with Apple with mandatory Terms & Conditions gate.
  Future<AuthState> signInWithApple({bool termsAccepted = false}) =>
      _signInWithProvider(
        OAuthProvider.apple,
        'dev.apple@coinscan.app',
        'Apple Collector',
        termsAccepted,
      );

  /// Sign in with Google with mandatory Terms & Conditions gate.
  Future<AuthState> signInWithGoogle({bool termsAccepted = false}) =>
      _signInWithProvider(
        OAuthProvider.google,
        'dev.google@coinscan.app',
        'Google Collector',
        termsAccepted,
      );

  /// Records acceptance of the current Terms for the signed-in user.
  Future<void> recordTermsReConsent(String userId) async {
    await _legalConsentService.recordConsent(
      userId: userId,
      accessToken: _state.token,
    );
    if (_state.user?.userId == userId) {
      _updateState(AuthState(
        user: _state.user,
        token: _state.token,
        termsConsentRequired: false,
      ));
      unawaited(fetchAuthoritativeProfile());
    }
  }

  /// Sends a password-reset email. The link opens the app, which then asks
  /// for a new password (see [completePasswordRecovery]).
  Future<void> sendPasswordReset(String email) async {
    final client = _supabaseClient;
    if (client == null) {
      throw const AuthConfigurationException(
        'Password reset is not available: the account service is not configured in this build.',
      );
    }
    await client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: kIsWeb ? null : authRedirectUrl,
    );
  }

  /// Sets a new password during password recovery, then continues normally.
  Future<void> completePasswordRecovery(String newPassword) async {
    final client = _supabaseClient;
    if (client == null || !_state.isPasswordRecovery) {
      throw const AuthConfigurationException('No password reset is in progress.');
    }
    await client.auth.updateUser(UserAttributes(password: newPassword));
    final session = client.auth.currentSession;
    if (session != null) {
      await _adoptSession(session);
    }
  }

  /// Sign out and clear stored session tokens. Vault stays isolated per user ID.
  Future<void> signOut() async {
    _signingOut = true;
    try {
      try {
        await _supabaseClient?.auth.signOut();
      } catch (e) {
        debugPrint('Supabase signOut error: $e');
      }
      await _clearLocalSession();
      await _secureStorage.delete(key: _pendingConsentKey);
      _updateState(const AuthState.guest());
    } finally {
      _signingOut = false;
    }
  }

  Future<void> _clearLocalSession() async {
    await _secureStorage.delete(key: SecureStorageService.keyAuthToken);
    await _secureStorage.delete(key: SecureStorageService.keyUserId);
    await _secureStorage.delete(key: SecureStorageService.keyUserEmail);
    await _secureStorage.delete(key: SecureStorageService.keyUserDisplayName);

    CollectionStorageService.instance.setCurrentUser(null);
    CollectionStorageService.instance.resetForUserSwitch();
    ScanHistoryService.instance.setCurrentUser(null);
    ScanHistoryService.instance.resetForUserSwitch();
    // A new guest session starts empty: never show a previous guest's scans.
    await CollectionStorageService.instance.clearGuestData();
    await ScanHistoryService.instance.clearGuestData();
  }

  /// Permanent Account Deletion: Invokes backend server deletion then cascades local wipe.
  Future<void> deleteAccount() async {
    final currentUserId = _state.user?.userId;
    final token = _state.token;

    // 1. Invoke backend account deletion endpoint if user is authenticated
    if (currentUserId != null && token != null && token.isNotEmpty) {
      try {
        await _apiClient.delete(
          '/v1/account/delete',
          body: {
            'confirm_phrase': 'DELETE MY ACCOUNT',
            'reason': 'User requested permanent account deletion',
          },
          headers: {'Authorization': 'Bearer $token'},
        );
      } catch (e) {
        final isSyntheticMock = token.startsWith('mock_jwt_token');
        final isDev = !AppConfig.isInitialized || !AppConfig.instance.isProduction;
        if (isSyntheticMock && isDev && (e is ApiException && (e.statusCode == 0 || e.statusCode == 400))) {
          debugPrint('Backend deletion warning in offline dev: $e');
        } else {
          rethrow;
        }
      }
    }

    // 2. Cascade local device wipe
    if (currentUserId != null) {
      await _legalConsentService.clearConsent(currentUserId);
    }
    await _secureStorage.deleteAll();

    await CollectionStorageService.instance.clearCollection();
    await ScanHistoryService.instance.clearHistory();
    CollectionStorageService.instance.setCurrentUser(null);
    CollectionStorageService.instance.resetForUserSwitch();
    ScanHistoryService.instance.setCurrentUser(null);
    ScanHistoryService.instance.resetForUserSwitch();

    _signingOut = true;
    try {
      await _supabaseClient?.auth.signOut();
    } catch (_) {
    } finally {
      _signingOut = false;
    }

    _updateState(const AuthState.guest());
  }

  Future<void> _persistSession({
    required String token,
    required String userId,
    required String email,
    required String displayName,
  }) async {
    await _secureStorage.write(
      key: SecureStorageService.keyAuthToken,
      value: token,
    );
    await _secureStorage.write(
      key: SecureStorageService.keyUserId,
      value: userId,
    );
    await _secureStorage.write(
      key: SecureStorageService.keyUserEmail,
      value: email,
    );
    await _secureStorage.write(
      key: SecureStorageService.keyUserDisplayName,
      value: displayName,
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _authStateController.close();
    super.dispose();
  }
}
