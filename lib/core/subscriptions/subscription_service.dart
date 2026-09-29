import 'dart:async';
import 'package:flutter/foundation.dart';

import '../auth/auth_service.dart';
import '../config/app_config.dart';
import '../network/api_client.dart';
import 'entitlement_models.dart';

export 'entitlement_models.dart';

/// Development-only subscription service that provides configurable entitlement
/// without requiring StoreKit, RevenueCat, or any Apple Developer account.
///
/// In production, replace with a real [SubscriptionService] implementation
/// backed by StoreKit 2 (iOS), Google Play Billing (Android), or RevenueCat.
///
/// ## Production Migration Checklist:
/// 1. Create App Store Connect subscription products with these IDs:
///    - `com.coinscan.plus.monthly`  ($4.99/mo)
///    - `com.coinscan.plus.yearly`   ($39.99/yr)
///    - `com.coinscan.pro.monthly`   ($9.99/mo)
///    - `com.coinscan.pro.yearly`    ($79.99/yr)
/// 2. Integrate RevenueCat SDK or StoreKit 2 directly
/// 3. Replace DevSubscriptionService with the real implementation in main.dart
/// 4. Configure server-side receipt validation on the backend
class DevSubscriptionService implements SubscriptionService {
  EntitlementState _state;
  int _scansToday;
  DateTime _lastResetDate;

  final StreamController<EntitlementState> _stateController =
      StreamController<EntitlementState>.broadcast();

  /// Stream of entitlement state changes.
  Stream<EntitlementState> get stateChanges => _stateController.stream;

  DevSubscriptionService({EntitlementPlan initialPlan = EntitlementPlan.limited})
    : _state = _buildState(initialPlan, 0),
      _scansToday = 0,
      _lastResetDate = _todayUtc();

  static DateTime _todayUtc() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }

  static EntitlementState _buildState(EntitlementPlan plan, int scansUsed) {
    switch (plan) {
      case EntitlementPlan.limited:
        return EntitlementState(
          plan: plan,
          status: SubscriptionStatus.none,
          scansUsedToday: scansUsed,
          dailyScanLimit: TierQuota.limitedDaily,
          advancedRecognitionEnabled: false,
          marketValuationEnabled: false,
          scanHistoryEnabled: false,
        );
      case EntitlementPlan.plus:
        return EntitlementState(
          plan: plan,
          status: SubscriptionStatus.active,
          scansUsedToday: scansUsed,
          dailyScanLimit: TierQuota.plusDaily,
          advancedRecognitionEnabled: true,
          marketValuationEnabled: false,
          scanHistoryEnabled: true,
          expiresAt: DateTime.now().add(const Duration(days: 30)),
        );
      case EntitlementPlan.pro:
        return EntitlementState(
          plan: plan,
          status: SubscriptionStatus.active,
          scansUsedToday: scansUsed,
          dailyScanLimit: TierQuota.proDaily,
          advancedRecognitionEnabled: true,
          marketValuationEnabled: true,
          scanHistoryEnabled: true,
          expiresAt: DateTime.now().add(const Duration(days: 30)),
        );
    }
  }

  void _checkDailyReset() {
    final today = _todayUtc();
    if (today.isAfter(_lastResetDate)) {
      _scansToday = 0;
      _lastResetDate = today;
      _state = _state.copyWith(scansUsedToday: 0);
    }
  }

  /// Synchronizes daily scan quota and subscription tier with authoritative backend QuotaEngine.
  Future<EntitlementState> syncQuotaWithBackend() async {
    final token = await ApiClient.instance.tokenProvider?.call() ??
        AuthService.instance.currentToken;
    if (token == null || token.isEmpty) {
      return _state;
    }

    try {
      final res = await ApiClient.instance.get('/v1/account/quota');
      if (res is Map<String, dynamic>) {
        final tierStr = res['tier']?.toString().toLowerCase() ?? 'free';
        final limit = (res['daily_limit'] as num?)?.toInt() ?? TierQuota.limitedDaily;
        final used = (res['scans_used_today'] as num?)?.toInt() ?? 0;

        EntitlementPlan plan;
        if (tierStr == 'pro') {
          plan = EntitlementPlan.pro;
        } else if (tierStr == 'plus') {
          plan = EntitlementPlan.plus;
        } else {
          plan = EntitlementPlan.limited;
        }

        _scansToday = used;
        _state = _buildState(plan, used).copyWith(
          dailyScanLimit: limit,
          status: plan == EntitlementPlan.limited
              ? SubscriptionStatus.none
              : SubscriptionStatus.active,
        );
        _stateController.add(_state);
        return _state;
      }
    } catch (e) {
      debugPrint('Could not synchronize quota with backend: $e');
    }
    return _state;
  }

  @override
  Future<EntitlementState> currentEntitlement() async {
    _checkDailyReset();
    if (AuthService.instance.currentState.isAuthenticated) {
      await syncQuotaWithBackend();
    }
    return _state;
  }

  @override
  Future<List<SubscriptionProduct>> availableProducts() async {
    // These product IDs must match App Store Connect / Google Play Console
    // configuration when moving to production.
    return const [
      SubscriptionProduct(
        productId: 'com.coinscan.plus.monthly',
        title: 'CoinScan Plus',
        description: '30 scans/day · Advanced recognition',
        priceDisplay: '\$4.99/month',
        priceUsd: 4.99,
        period: BillingPeriod.monthly,
        plan: EntitlementPlan.plus,
      ),
      SubscriptionProduct(
        productId: 'com.coinscan.plus.yearly',
        title: 'CoinScan Plus',
        description: '30 scans/day · Advanced recognition · Save 33%',
        priceDisplay: '\$39.99/year',
        priceUsd: 39.99,
        period: BillingPeriod.yearly,
        plan: EntitlementPlan.plus,
      ),
      SubscriptionProduct(
        productId: 'com.coinscan.pro.monthly',
        title: 'CoinScan Pro',
        description: '100 scans/day · Full valuation · Market data',
        priceDisplay: '\$9.99/month',
        priceUsd: 9.99,
        period: BillingPeriod.monthly,
        plan: EntitlementPlan.pro,
      ),
      SubscriptionProduct(
        productId: 'com.coinscan.pro.yearly',
        title: 'CoinScan Pro',
        description: '100 scans/day · Full valuation · Market data · Save 33%',
        priceDisplay: '\$79.99/year',
        priceUsd: 79.99,
        period: BillingPeriod.yearly,
        plan: EntitlementPlan.pro,
      ),
    ];
  }

  @override
  Future<EntitlementState> purchase(String productId) async {
    // In production builds, block simulated purchases to prevent misleading users
    if (AppConfig.isInitialized && AppConfig.instance.isProduction) {
      throw UnsupportedError(
        'In-app purchases are not configured for this build. '
        'Please link an active Apple Developer account and RevenueCat credentials.',
      );
    }

    // In development/test mode, simulate a successful purchase
    EntitlementPlan plan;
    if (productId.contains('pro')) {
      plan = EntitlementPlan.pro;
    } else if (productId.contains('plus')) {
      plan = EntitlementPlan.plus;
    } else {
      plan = EntitlementPlan.limited;
    }

    _state = _buildState(plan, _scansToday);
    _stateController.add(_state);
    return _state;
  }

  @override
  Future<EntitlementState> restorePurchases() async {
    // In development, nothing to restore — keep current state
    return _state;
  }

  @override
  Future<EntitlementState> recordScanUsage() async {
    _checkDailyReset();
    _scansToday++;
    _state = _state.copyWith(scansUsedToday: _scansToday);
    _stateController.add(_state);
    return _state;
  }

  @override
  Future<void> reset() async {
    _state = _buildState(EntitlementPlan.limited, 0);
    _scansToday = 0;
    _lastResetDate = _todayUtc();
    _stateController.add(_state);
  }

  /// Dev-only method to switch tiers for testing.
  Future<void> setTier(EntitlementPlan plan) async {
    _state = _buildState(plan, _scansToday);
    _stateController.add(_state);
  }

  void dispose() {
    _stateController.close();
  }
}
