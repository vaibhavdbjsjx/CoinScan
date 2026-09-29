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

  /// User is authenticated ONLY IF user exists, is not anonymous, AND has satisfied mandatory terms acceptance.
  bool get isAuthenticated =>
      user != null &&
      !user!.isAnonymous &&
      !termsConsentRequired &&
      !isEmailVerificationPending &&
      token != null &&
      token != 'pending_verification';

  bool get isGuest => user == null || user!.isAnonymous || termsConsentRequired || isEmailVerificationPending;

  const AuthState({
    this.user,
    this.token,
    this.isLoading = false,
    this.termsConsentRequired = false,
    this.isEmailVerificationPending = false,
    this.pendingVerificationEmail,
  });

  const AuthState.unauthenticated()
    : user = null,
      token = null,
      isLoading = false,
      termsConsentRequired = false,
      isEmailVerificationPending = false,
      pendingVerificationEmail = null;

  const AuthState.guest()
    : user = null,
      token = null,
      isLoading = false,
      termsConsentRequired = false,
      isEmailVerificationPending = false,
      pendingVerificationEmail = null;

  const AuthState.emailVerificationPending({required String email})
    : user = null,
      token = null,
      isLoading = false,
      termsConsentRequired = false,
      isEmailVerificationPending = true,
      pendingVerificationEmail = email;
}

/// Production-ready Authentication & Session Manager powered by Supabase Auth.
///
/// Features:
/// 1. Real Supabase Auth sessions with cryptographically verified JWT bearer tokens.
/// 2. Strict RFC 4122 UUID user identities matching PostgreSQL `public.users.id`.
/// 3. Persistent Keychain/Keystore session caching via [SecureStorageService].
/// 4. Mandatory Terms & Conditions consent gate with server synchronization.
/// 5. Full GDPR / App Store compliant account deletion cascading to the backend.
class AuthService with ChangeNotifier {
  static AuthService instance = AuthService();

  final SecureStorageService _secureStorage;
  final LegalConsentService _legalConsentService;
  final SupabaseClient? _explicitSupabaseClient;
  final ApiClient? _explicitApiClient;

  AuthState _state = const AuthState.guest();
  final StreamController<AuthState> _authStateController =
      StreamController<AuthState>.broadcast();

  Stream<AuthState> get authStateChanges => _authStateController.stream;
  AuthState get currentState => _state;
  String? get currentToken => _state.token;

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
          email: res['email'] as String? ?? _state.user?.email ?? '',
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
      final session = data.session;
      if (session != null && !session.isExpired) {
        final userId = session.user.id;
        final token = session.accessToken;
        final email = session.user.email ?? '';
        final displayName = session.user.userMetadata?['full_name'] as String? ??
            session.user.userMetadata?['name'] as String? ??
            session.user.userMetadata?['display_name'] as String? ??
            (email.isNotEmpty ? email.split('@').first : 'Collector');

        await _persistSession(
          token: token,
          userId: userId,
          email: email,
          displayName: displayName,
        );

        final hasAccepted =
            await _legalConsentService.hasAcceptedCurrentTerms(userId);
        CollectionStorageService.instance.setCurrentUser(userId);
        ScanHistoryService.instance.setCurrentUser(userId);

        final profile = UserProfile(
          userId: userId,
          email: email,
          displayName: displayName,
          isAnonymous: false,
          createdAt: DateTime.tryParse(session.user.createdAt) ?? DateTime.now(),
        );

        _configureApiClient();
        _updateState(AuthState(
          user: profile,
          token: token,
          termsConsentRequired: !hasAccepted,
        ));
        unawaited(fetchAuthoritativeProfile());
      }
    });
  }

  /// Restores session on app startup, validating terms version adherence.
  Future<void> initialize() async {
    // 1. Try restoring from active Supabase session if initialized
    final client = _supabaseClient;
    if (client != null) {
      _listenToAuthChanges(client);
      final session = client.auth.currentSession;
      if (session != null && !session.isExpired) {
        final userId = session.user.id;
        final token = session.accessToken;
        final email = session.user.email ?? '';
        final displayName =
            session.user.userMetadata?['display_name'] as String? ??
            (email.isNotEmpty ? email.split('@').first : 'Collector');

        await _persistSession(
          token: token,
          userId: userId,
          email: email,
          displayName: displayName,
        );

        final hasAccepted =
            await _legalConsentService.hasAcceptedCurrentTerms(userId);
        CollectionStorageService.instance.setCurrentUser(userId);
        ScanHistoryService.instance.setCurrentUser(userId);

        final profile = UserProfile(
          userId: userId,
          email: email,
          displayName: displayName,
          isAnonymous: false,
          createdAt: DateTime.tryParse(session.user.createdAt) ?? DateTime.now(),
        );

        _configureApiClient();
        _updateState(AuthState(
          user: profile,
          token: token,
          termsConsentRequired: !hasAccepted,
        ));
        unawaited(fetchAuthoritativeProfile());
        return;
      }
    }

    // 2. Fall back to secure local storage (e.g. cold start before network)
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

  /// Sign up with Email and Password using Supabase Auth.
  Future<AuthState> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
    bool termsAccepted = false,
  }) async {
    final client = _supabaseClient;
    String userId;
    String token;
    final resolvedDisplayName =
        displayName ?? (email.isNotEmpty ? email.split('@').first : 'Collector');

    if (client != null) {
      final res = await client.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': resolvedDisplayName},
      );
      final user = res.user;
      final session = res.session;
      if (user == null) {
        throw const AuthException('Could not create account in Supabase.');
      }
      if (session == null) {
        // Supabase requires email verification. Do not persist invalid pending token.
        _updateState(AuthState.emailVerificationPending(email: email));
        return _state;
      }
      userId = user.id;
      token = session.accessToken;
    } else {
      if (AppConfig.isInitialized && AppConfig.instance.isProduction) {
        throw StateError(
          'Supabase authentication is not configured in production. '
          'Please specify SUPABASE_URL and SUPABASE_ANON_KEY.',
        );
      }
      // Non-production test/offline fallback: Generate RFC 4122 UUID v5
      userId = const Uuid().v5(Namespace.url.value, 'mailto:$email');
      token = 'mock_jwt_token_$userId';
    }

    if (!termsAccepted) {
      throw const TermsConsentRequiredException();
    }
    await _legalConsentService.recordConsent(userId: userId);

    _updateState(const AuthState(isLoading: true));

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

    CollectionStorageService.instance.setCurrentUser(userId);
    ScanHistoryService.instance.setCurrentUser(userId);

    _configureApiClient();
    _updateState(AuthState(user: profile, token: token, termsConsentRequired: false));
    unawaited(fetchAuthoritativeProfile());
    return _state;
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
      if (user.userMetadata?['display_name'] != null) {
        displayName = user.userMetadata!['display_name'] as String;
      }
    } else {
      if (AppConfig.isInitialized && AppConfig.instance.isProduction) {
        throw StateError(
          'Supabase authentication is not configured in production. '
          'Please specify SUPABASE_URL and SUPABASE_ANON_KEY.',
        );
      }
      // Non-production test/offline fallback: Generate RFC 4122 UUID v5
      userId = const Uuid().v5(Namespace.url.value, 'mailto:$email');
      token = 'mock_jwt_token_$userId';
    }

    // Gate: Must be explicitly accepted in this flow OR current version was already accepted for this account
    final alreadyAccepted =
        await _legalConsentService.hasAcceptedCurrentTerms(userId);
    if (!termsAccepted && !alreadyAccepted) {
      throw const TermsConsentRequiredException();
    }

    if (termsAccepted) {
      await _legalConsentService.recordConsent(userId: userId);
    }

    _updateState(const AuthState(isLoading: true));

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

    CollectionStorageService.instance.setCurrentUser(userId);
    ScanHistoryService.instance.setCurrentUser(userId);

    _configureApiClient();
    _updateState(AuthState(user: profile, token: token, termsConsentRequired: false));
    unawaited(fetchAuthoritativeProfile());
    return _state;
  }

  /// Sign in with Apple with mandatory Terms & Conditions gate.
  Future<AuthState> signInWithApple({bool termsAccepted = false}) async {
    final client = _supabaseClient;
    String userId;
    String token;
    String email;
    String displayName;

    if (client != null) {
      if (!termsAccepted) {
        throw const TermsConsentRequiredException();
      }
      final success = await client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: kIsWeb ? null : 'com.coinvault.coinvaultai://login-callback',
      );
      if (!success) {
        throw const AuthException('Apple sign in was aborted.');
      }
      final session = client.auth.currentSession;
      if (session == null) {
        // Asynchronous OAuth redirect launched; authentication completes via onAuthStateChange.
        _state = const AuthState(isLoading: true);
        _authStateController.add(_state);
        return _state;
      }
      final user = session.user;
      userId = user.id;
      token = session.accessToken;
      email = user.email ?? '';
      displayName = user.userMetadata?['full_name'] as String? ??
          user.userMetadata?['name'] as String? ??
          user.userMetadata?['display_name'] as String? ??
          (email.isNotEmpty ? email.split('@').first : 'Apple Collector');
    } else {
      if (AppConfig.isInitialized && AppConfig.instance.isProduction) {
        throw StateError(
          'Supabase authentication is not configured in production.',
        );
      }
      email = 'dev.apple@coinscan.app';
      displayName = 'Apple Collector';
      userId = const Uuid().v5(Namespace.url.value, 'mailto:$email');
      token = 'mock_jwt_token_apple_$userId';

      final alreadyAccepted =
          await _legalConsentService.hasAcceptedCurrentTerms(userId);
      if (!termsAccepted && !alreadyAccepted) {
        throw const TermsConsentRequiredException();
      }
    }

    if (termsAccepted) {
      await _legalConsentService.recordConsent(userId: userId);
    }

    _updateState(const AuthState(isLoading: true));

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

    CollectionStorageService.instance.setCurrentUser(userId);
    ScanHistoryService.instance.setCurrentUser(userId);

    _configureApiClient();
    _updateState(AuthState(user: profile, token: token, termsConsentRequired: false));
    unawaited(fetchAuthoritativeProfile());
    return _state;
  }

  /// Sign in with Google with mandatory Terms & Conditions gate.
  Future<AuthState> signInWithGoogle({bool termsAccepted = false}) async {
    final client = _supabaseClient;
    String userId;
    String token;
    String email;
    String displayName;

    if (client != null) {
      if (!termsAccepted) {
        throw const TermsConsentRequiredException();
      }
      final success = await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : 'com.coinvault.coinvaultai://login-callback',
      );
      if (!success) {
        throw const AuthException('Google sign in was aborted.');
      }
      final session = client.auth.currentSession;
      if (session == null) {
        // Asynchronous OAuth redirect launched; authentication completes via onAuthStateChange.
        _updateState(const AuthState(isLoading: true));
        return _state;
      }
      final user = session.user;
      userId = user.id;
      token = session.accessToken;
      email = user.email ?? '';
      displayName = user.userMetadata?['full_name'] as String? ??
          user.userMetadata?['name'] as String? ??
          user.userMetadata?['display_name'] as String? ??
          (email.isNotEmpty ? email.split('@').first : 'Google Collector');
    } else {
      if (AppConfig.isInitialized && AppConfig.instance.isProduction) {
        throw StateError(
          'Supabase authentication is not configured in production.',
        );
      }
      email = 'dev.google@coinscan.app';
      displayName = 'Google Collector';
      userId = const Uuid().v5(Namespace.url.value, 'mailto:$email');
      token = 'mock_jwt_token_google_$userId';

      final alreadyAccepted =
          await _legalConsentService.hasAcceptedCurrentTerms(userId);
      if (!termsAccepted && !alreadyAccepted) {
        throw const TermsConsentRequiredException();
      }
    }

    if (termsAccepted) {
      await _legalConsentService.recordConsent(userId: userId);
    }

    _updateState(const AuthState(isLoading: true));

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

    CollectionStorageService.instance.setCurrentUser(userId);
    ScanHistoryService.instance.setCurrentUser(userId);

    _configureApiClient();
    _updateState(AuthState(user: profile, token: token, termsConsentRequired: false));
    unawaited(fetchAuthoritativeProfile());
    return _state;
  }

  /// Re-consents to updated legal documents for an existing session.
  Future<void> recordTermsReConsent(String userId) async {
    await _legalConsentService.recordConsent(userId: userId);
    if (_state.user?.userId == userId) {
      _updateState(AuthState(
        user: _state.user,
        token: _state.token,
        termsConsentRequired: false,
      ));
    }
  }

  /// Sign out and clear stored session tokens. Vault stays isolated per user ID.
  Future<void> signOut() async {
    try {
      await _supabaseClient?.auth.signOut();
    } catch (e) {
      debugPrint('Supabase signOut error: $e');
    }

    await _secureStorage.delete(key: SecureStorageService.keyAuthToken);
    await _secureStorage.delete(key: SecureStorageService.keyUserId);
    await _secureStorage.delete(key: SecureStorageService.keyUserEmail);
    await _secureStorage.delete(key: SecureStorageService.keyUserDisplayName);

    CollectionStorageService.instance.setCurrentUser(null);
    CollectionStorageService.instance.resetForUserSwitch();
    ScanHistoryService.instance.setCurrentUser(null);
    ScanHistoryService.instance.resetForUserSwitch();

    _updateState(const AuthState.guest());
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

    try {
      await _supabaseClient?.auth.signOut();
    } catch (_) {}

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
