import 'package:flutter/foundation.dart';

/// RevenueCat configuration constants and runtime key resolution.
///
/// ## What lives here
/// - Public SDK key placeholders resolved from --dart-define at compile time
/// - Canonical product IDs
/// - Canonical entitlement IDs
/// - Helper booleans for configuration guards
///
/// ## What MUST NOT live here
/// - RevenueCat secret API keys
/// - Webhook shared secrets
/// - App Store Connect private keys (.p8)
/// - Google Play service-account credentials
///
/// ## How to provide keys
///   flutter run \
///     --dart-define=REVENUECAT_APPLE_KEY=appl_xxxxxxxxxx \
///     --dart-define=REVENUECAT_GOOGLE_KEY=goog_xxxxxxxxxx
///
/// Apple key prefix: appl_
/// Google key prefix: goog_
class RevenueCatConfig {
  RevenueCatConfig._();

  // ─── Runtime key resolution ───────────────────────────────────────────────

  /// Public Apple (iOS/macOS) RevenueCat SDK key.
  /// Provided via --dart-define=REVENUECAT_APPLE_KEY=appl_...
  static const String _appleKey =
      String.fromEnvironment('REVENUECAT_APPLE_KEY');

  /// Public Google (Android) RevenueCat SDK key.
  /// Provided via --dart-define=REVENUECAT_GOOGLE_KEY=goog_...
  static const String _googleKey =
      String.fromEnvironment('REVENUECAT_GOOGLE_KEY');

  /// Returns the platform-appropriate public RevenueCat SDK key, or null if
  /// not configured for the current platform.
  ///
  /// Returns null (not empty string) so callers can distinguish
  /// "not provided" from "empty string".
  static String? get resolvedApiKey {
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return _appleKey.isNotEmpty ? _appleKey : null;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _googleKey.isNotEmpty ? _googleKey : null;
    }
    // Web / Linux / Windows: RevenueCat native SDK is not supported.
    return null;
  }

  /// Whether this is a production build.
  static bool get isProductionBuild {
    const env = String.fromEnvironment('APP_ENV', defaultValue: 'development');
    return env == 'production';
  }

  /// Whether the SDK can be initialized (key present and platform supported).
  static bool get isConfigured => resolvedApiKey != null;

  // ─── Entitlement identifiers ──────────────────────────────────────────────
  // These must match the entitlement identifiers configured in the
  // RevenueCat dashboard exactly (case-sensitive).

  /// RevenueCat entitlement identifier for CoinScan Plus.
  static const String entitlementPlus = 'plus';

  /// RevenueCat entitlement identifier for CoinScan Pro.
  static const String entitlementPro = 'pro';

  // ─── Product identifiers ──────────────────────────────────────────────────
  // These must match App Store Connect and Google Play Console exactly.

  static const String productPlusMonthly = 'com.coinscan.plus.monthly';
  static const String productPlusYearly = 'com.coinscan.plus.yearly';
  static const String productProMonthly = 'com.coinscan.pro.monthly';
  static const String productProYearly = 'com.coinscan.pro.yearly';

  /// All product IDs for validation / lookups.
  static const List<String> allProductIds = [
    productPlusMonthly,
    productPlusYearly,
    productProMonthly,
    productProYearly,
  ];
}
