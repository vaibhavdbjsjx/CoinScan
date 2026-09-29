import 'package:flutter/foundation.dart';

/// Deployment environment for CoinScan.
enum AppEnvironment { development, staging, production }

/// Centralized application configuration.
///
/// Backend URL is resolved automatically based on environment and platform:
/// - Development: localhost (127.0.0.1 for iOS/Web, 10.0.2.2 for Android)
/// - Staging/Production: configured via `--dart-define=BACKEND_URL=...`
///
/// Usage:
///   flutter run --dart-define=APP_ENV=production --dart-define=BACKEND_URL=https://coinscan-backend-xxx.run.app
class AppConfig {
  static AppConfig? _instance;

  final AppEnvironment environment;
  final String backendUrl;
  final String? apiKey;
  final String? supabaseUrl;
  final String? supabaseAnonKey;

  AppConfig._({
    required this.environment,
    required this.backendUrl,
    this.apiKey,
    this.supabaseUrl,
    this.supabaseAnonKey,
  });

  /// Singleton instance. Call [initialize] before accessing.
  static AppConfig get instance {
    assert(_instance != null, 'AppConfig.initialize() must be called first');
    return _instance!;
  }

  /// Whether the singleton has been initialized.
  static bool get isInitialized => _instance != null;

  /// Whether Supabase credentials have been configured at compile-time.
  bool get isSupabaseConfigured =>
      supabaseUrl != null &&
      supabaseUrl!.trim().isNotEmpty &&
      supabaseAnonKey != null &&
      supabaseAnonKey!.trim().isNotEmpty;

  /// Initialize configuration from compile-time defines and platform detection.
  ///
  /// Compile-time defines (set via `--dart-define`):
  /// - `APP_ENV`: "development", "staging", or "production"
  /// - `BACKEND_URL`: full URL to the backend service
  /// - `API_KEY`: optional API key for authenticated requests
  /// - `SUPABASE_URL`: HTTPS endpoint for Supabase project Auth & DB
  /// - `SUPABASE_ANON_KEY`: public anonymous key for client requests
  static void initialize() {
    if (_instance != null) return;

    const envString = String.fromEnvironment('APP_ENV', defaultValue: 'development');
    final environment = AppEnvironment.values.firstWhere(
      (e) => e.name == envString,
      orElse: () => AppEnvironment.development,
    );

    const definedUrl = String.fromEnvironment('BACKEND_URL');
    const apiKey = String.fromEnvironment('API_KEY');
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

    final backendUrl = definedUrl.isNotEmpty
        ? definedUrl
        : _resolveDefaultUrl(environment);

    _instance = AppConfig._(
      environment: environment,
      backendUrl: backendUrl,
      apiKey: apiKey.isNotEmpty ? apiKey : null,
      supabaseUrl: supabaseUrl.isNotEmpty ? supabaseUrl : null,
      supabaseAnonKey: supabaseAnonKey.isNotEmpty ? supabaseAnonKey : null,
    );
  }

  /// Reset for testing.
  @visibleForTesting
  static void reset() {
    _instance = null;
  }

  /// Override for testing.
  @visibleForTesting
  static void setTestConfig({
    AppEnvironment environment = AppEnvironment.development,
    String backendUrl = 'http://127.0.0.1:8080',
    String? apiKey,
    String? supabaseUrl,
    String? supabaseAnonKey,
  }) {
    _instance = AppConfig._(
      environment: environment,
      backendUrl: backendUrl,
      apiKey: apiKey,
      supabaseUrl: supabaseUrl,
      supabaseAnonKey: supabaseAnonKey,
    );
  }

  static String _resolveDefaultUrl(AppEnvironment env) {
    switch (env) {
      case AppEnvironment.development:
        // Android emulator uses 10.0.2.2 to reach host localhost
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          return 'http://10.0.2.2:8080';
        }
        return 'http://127.0.0.1:8080';
      case AppEnvironment.staging:
        // Override via --dart-define=BACKEND_URL in practice
        return 'https://coinscan-staging.run.app';
      case AppEnvironment.production:
        // Override via --dart-define=BACKEND_URL in practice
        return 'https://api.coinscan.app';
    }
  }

  bool get isDevelopment => environment == AppEnvironment.development;
  bool get isProduction => environment == AppEnvironment.production;
}
