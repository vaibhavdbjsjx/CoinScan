/// Subscription entitlement model layer for CoinScan.
///
/// Defines the three-tier product line, per-tier scan quotas, subscription
/// lifecycle states, and the abstract [SubscriptionService] contract that
/// platform-specific implementations (StoreKit 2, Google Play Billing,
/// development stub) fulfil.
library;

/// Available subscription tiers.
enum EntitlementPlan { limited, plus, pro }

/// Lifecycle state of a subscription.
enum SubscriptionStatus {
  /// User has never subscribed.
  none,

  /// Subscription is active and paid.
  active,

  /// Subscription expired but within the grace period.
  grace,

  /// Apple/Google is retrying billing.
  billingRetry,

  /// User cancelled; access continues until the current period ends.
  cancelled,

  /// Subscription has fully expired.
  expired,
}

/// Scan quota limits per tier (resets daily at midnight UTC).
class TierQuota {
  const TierQuota._();

  /// Signed-out guests: 2 successful scans per UTC day. The server's guest
  /// allowance is authoritative; the app only uses this to avoid a request
  /// that would be refused.
  static const int guestDaily = 2;

  /// Limited (free) users: 3 scans per day.
  static const int limitedDaily = 3;

  /// Plus subscribers: 30 scans per day.
  static const int plusDaily = 30;

  /// Pro subscribers: 100 scans per day (fair-use ceiling, matches backend).
  static const int proDaily = 100;
}

/// A purchasable subscription product displayed on the paywall.
class SubscriptionProduct {
  final String productId;
  final String title;
  final String description;
  final String priceDisplay;
  final double priceUsd;
  final BillingPeriod period;
  final EntitlementPlan plan;

  const SubscriptionProduct({
    required this.productId,
    required this.title,
    required this.description,
    required this.priceDisplay,
    required this.priceUsd,
    required this.period,
    required this.plan,
  });
}

/// Billing recurrence.
enum BillingPeriod { monthly, yearly }

const Object _sentinel = Object();

/// Immutable snapshot of the user's current entitlement.
class EntitlementState {
  final EntitlementPlan plan;
  final SubscriptionStatus status;
  final int scansUsedToday;
  final int? dailyScanLimit;
  final bool advancedRecognitionEnabled;
  final bool marketValuationEnabled;
  final bool scanHistoryEnabled;
  final DateTime? expiresAt;

  const EntitlementState({
    required this.plan,
    this.status = SubscriptionStatus.none,
    this.scansUsedToday = 0,
    this.dailyScanLimit,
    required this.advancedRecognitionEnabled,
    required this.marketValuationEnabled,
    this.scanHistoryEnabled = false,
    this.expiresAt,
  });

  /// Default free tier state.
  const EntitlementState.limited()
    : plan = EntitlementPlan.limited,
      status = SubscriptionStatus.none,
      scansUsedToday = 0,
      dailyScanLimit = TierQuota.limitedDaily,
      advancedRecognitionEnabled = false,
      marketValuationEnabled = false,
      scanHistoryEnabled = false,
      expiresAt = null;

  /// Whether the user can perform another scan right now.
  bool get canScan {
    if (dailyScanLimit == null || dailyScanLimit! < 0) return true;
    return scansUsedToday < dailyScanLimit!;
  }

  /// Remaining scans today, or -1 for unlimited.
  int get scansRemaining {
    if (dailyScanLimit == null || dailyScanLimit! < 0) return -1;
    final remaining = dailyScanLimit! - scansUsedToday;
    return remaining > 0 ? remaining : 0;
  }

  EntitlementState copyWith({
    EntitlementPlan? plan,
    SubscriptionStatus? status,
    int? scansUsedToday,
    Object? dailyScanLimit = _sentinel,
    bool? advancedRecognitionEnabled,
    bool? marketValuationEnabled,
    bool? scanHistoryEnabled,
    Object? expiresAt = _sentinel,
  }) {
    return EntitlementState(
      plan: plan ?? this.plan,
      status: status ?? this.status,
      scansUsedToday: scansUsedToday ?? this.scansUsedToday,
      dailyScanLimit: identical(dailyScanLimit, _sentinel)
          ? this.dailyScanLimit
          : dailyScanLimit as int?,
      advancedRecognitionEnabled:
          advancedRecognitionEnabled ?? this.advancedRecognitionEnabled,
      marketValuationEnabled:
          marketValuationEnabled ?? this.marketValuationEnabled,
      scanHistoryEnabled: scanHistoryEnabled ?? this.scanHistoryEnabled,
      expiresAt: identical(expiresAt, _sentinel)
          ? this.expiresAt
          : expiresAt as DateTime?,
    );
  }
}

/// Platform-independent subscription service contract.
///
/// Implementations:
/// - [DevSubscriptionService] — local development fallback (always available)
/// - StoreKit 2 / RevenueCat — production iOS (requires Apple Developer account)
abstract interface class SubscriptionService {
  /// Returns the user's current entitlement snapshot.
  Future<EntitlementState> currentEntitlement();

  /// Lists purchasable products for the paywall.
  Future<List<SubscriptionProduct>> availableProducts();

  /// Initiates a purchase flow for the given product.
  Future<EntitlementState> purchase(String productId);

  /// Restores previously purchased subscriptions.
  Future<EntitlementState> restorePurchases();

  /// Records that a scan was consumed against today's quota.
  Future<EntitlementState> recordScanUsage();

  /// Resets entitlement state to the baseline limited plan (e.g. on logout).
  Future<void> reset();
}
