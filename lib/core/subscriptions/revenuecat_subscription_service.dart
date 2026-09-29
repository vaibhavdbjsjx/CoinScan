import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../auth/auth_service.dart';
import '../network/api_client.dart';
import 'entitlement_models.dart';
import 'revenuecat_config.dart';

export 'entitlement_models.dart';

/// Production RevenueCat-backed [SubscriptionService].
///
/// All purchase decisions require a verified RevenueCat [CustomerInfo].
/// No subscription is granted solely because a button was tapped.
///
/// ## Identity chain
///   Supabase Auth UUID → RC appUserID → RC entitlement → [EntitlementPlan]
///
/// ## Keys
/// Public SDK keys provided via --dart-define. No secrets ever embedded here.
class RevenueCatSubscriptionService implements SubscriptionService {
  static const String _entitlementPlus = RevenueCatConfig.entitlementPlus;
  static const String _entitlementPro = RevenueCatConfig.entitlementPro;

  EntitlementState _state;
  int _scansToday;
  DateTime _lastResetDate;
  bool _isConfigured = false;

  final StreamController<EntitlementState> _stateController =
      StreamController<EntitlementState>.broadcast();

  Stream<EntitlementState> get stateChanges => _stateController.stream;

  RevenueCatSubscriptionService()
      : _state = const EntitlementState.limited(),
        _scansToday = 0,
        _lastResetDate = _todayUtc();

  // ─── Initialization ───────────────────────────────────────────────────────

  static Future<RevenueCatSubscriptionService> initialize({
    String? appUserId,
  }) async {
    final service = RevenueCatSubscriptionService();
    await service._configure(appUserId: appUserId);
    return service;
  }

  Future<void> _configure({String? appUserId}) async {
    final apiKey = RevenueCatConfig.resolvedApiKey;
    if (apiKey == null || apiKey.isEmpty) {
      if (RevenueCatConfig.isProductionBuild) {
        debugPrint(
          '[RevenueCat] CRITICAL: Public SDK key not configured for production. '
          'Provide REVENUECAT_APPLE_KEY or REVENUECAT_GOOGLE_KEY via --dart-define.',
        );
      } else {
        debugPrint(
          '[RevenueCat] SDK key absent. Running in unconfigured dev mode. '
          'Subscriptions unavailable until a key is provided.',
        );
      }
      _isConfigured = false;
      return;
    }

    try {
      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
      }
      final config = PurchasesConfiguration(apiKey)..appUserID = appUserId;
      await Purchases.configure(config);
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdated);
      _isConfigured = true;
      debugPrint('[RevenueCat] SDK configured. appUserId=$appUserId');
      await _refreshFromCustomerInfo();
    } on PlatformException catch (e) {
      debugPrint('[RevenueCat] Configuration error: ${e.message}');
      _isConfigured = false;
    }
  }

  void _onCustomerInfoUpdated(CustomerInfo info) {
    final newState = _mapCustomerInfo(info, _scansToday);
    _applyState(newState);
    debugPrint('[RevenueCat] CustomerInfo push. plan=${newState.plan.name}');
  }

  // ─── User Identity ────────────────────────────────────────────────────────

  Future<void> logIn(String supabaseUuid) async {
    if (!_isConfigured) return;
    try {
      final result = await Purchases.logIn(supabaseUuid);
      _applyState(_mapCustomerInfo(result.customerInfo, _scansToday));
      debugPrint('[RevenueCat] logIn: uuid=$supabaseUuid created=${result.created}');
    } on PlatformException catch (e) {
      debugPrint('[RevenueCat] logIn error: ${e.message}');
    }
  }

  Future<void> logOut() async {
    if (!_isConfigured) return;
    try {
      await Purchases.logOut();
      debugPrint('[RevenueCat] Logged out. Reverted to anonymous.');
    } on PlatformException catch (e) {
      debugPrint('[RevenueCat] logOut error: ${e.message}');
    }
    await reset();
  }

  // ─── SubscriptionService interface ────────────────────────────────────────

  @override
  Future<EntitlementState> currentEntitlement() async {
    _checkDailyReset();
    if (AuthService.instance.currentState.isAuthenticated) {
      await _syncQuotaWithBackend();
    }
    return _state;
  }

  @override
  Future<List<SubscriptionProduct>> availableProducts() async {
    if (!_isConfigured) return _staticFallbackProducts();
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null || current.availablePackages.isEmpty) {
        debugPrint('[RevenueCat] No current offering available.');
        return [];
      }
      return current.availablePackages
          .map(_packageToProduct)
          .whereType<SubscriptionProduct>()
          .toList();
    } on PlatformException catch (e) {
      debugPrint('[RevenueCat] getOfferings error: ${e.message}');
      return [];
    }
  }

  @override
  Future<EntitlementState> purchase(String productId) async {
    if (!_isConfigured) {
      throw UnsupportedError(
        'In-app purchases are not configured for this build. '
        'Provide REVENUECAT_APPLE_KEY or REVENUECAT_GOOGLE_KEY via --dart-define.',
      );
    }

    Package? targetPackage;
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current != null) {
        for (final pkg in current.availablePackages) {
          if (pkg.storeProduct.identifier == productId) {
            targetPackage = pkg;
            break;
          }
        }
      }
    } on PlatformException catch (e) {
      debugPrint('[RevenueCat] Could not fetch offerings before purchase: ${e.message}');
    }

    if (targetPackage == null) {
      throw PurchaseException(
        'Product "$productId" is not available. '
        'Ensure it is configured in RevenueCat dashboard and App Store / Google Play.',
        isCancellation: false,
      );
    }

    try {
      final result =
          await Purchases.purchase(PurchaseParams.package(targetPackage));
      final newState = _mapCustomerInfo(result.customerInfo, _scansToday);
      _applyState(newState);
      debugPrint('[RevenueCat] Purchase success: $productId plan=${newState.plan.name}');
      return newState;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        throw const PurchaseException('Purchase was cancelled.', isCancellation: true);
      }
      throw PurchaseException(
        _userFacingError(code),
        isCancellation: false,
      );
    }
  }

  @override
  Future<EntitlementState> restorePurchases() async {
    if (!_isConfigured) {
      throw UnsupportedError(
        'RevenueCat SDK is not configured. Cannot restore purchases.',
      );
    }
    try {
      final info = await Purchases.restorePurchases();
      final newState = _mapCustomerInfo(info, _scansToday);
      _applyState(newState);
      debugPrint('[RevenueCat] Restore complete. plan=${newState.plan.name}');
      return newState;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      throw PurchaseException(_userFacingError(code), isCancellation: false);
    }
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
    _scansToday = 0;
    _lastResetDate = _todayUtc();
    _state = const EntitlementState.limited();
    _stateController.add(_state);
  }

  void dispose() => _stateController.close();

  // ─── Internal helpers ─────────────────────────────────────────────────────

  Future<void> _refreshFromCustomerInfo() async {
    if (!_isConfigured) return;
    try {
      final info = await Purchases.getCustomerInfo();
      _applyState(_mapCustomerInfo(info, _scansToday));
    } on PlatformException catch (e) {
      debugPrint('[RevenueCat] getCustomerInfo error: ${e.message}');
    }
  }

  void _applyState(EntitlementState s) {
    _state = s;
    _stateController.add(s);
  }

  Future<void> _syncQuotaWithBackend() async {
    final token = await ApiClient.instance.tokenProvider?.call() ??
        AuthService.instance.currentToken;
    if (token == null || token.isEmpty) return;
    try {
      final res = await ApiClient.instance.get('/v1/account/quota');
      if (res is Map<String, dynamic>) {
        final merged = mergeBackendQuota(_state, res);
        _scansToday = merged.scansUsedToday;
        _applyState(merged);
      }
    } catch (e) {
      debugPrint('[RevenueCat] Backend quota sync failed: $e');
    }
  }

  /// Combines the current (RevenueCat-derived) entitlement with the backend's
  /// `/v1/account/quota` response.
  ///
  /// The backend learns about purchases through RevenueCat webhooks, which can
  /// arrive seconds after the store confirms a purchase. While that webhook is
  /// pending the backend still reports the old tier. A verified, active
  /// RevenueCat entitlement is therefore never downgraded by a lower backend
  /// tier; the backend remains authoritative for the scan count and still
  /// enforces quotas server-side. When the backend reports an equal or higher
  /// tier, its plan and limit are used.
  @visibleForTesting
  static EntitlementState mergeBackendQuota(
    EntitlementState current,
    Map<String, dynamic> backend,
  ) {
    final tierStr = backend['tier']?.toString().toLowerCase() ?? 'free';
    final limit =
        (backend['daily_limit'] as num?)?.toInt() ?? TierQuota.limitedDaily;
    final used = (backend['scans_used_today'] as num?)?.toInt() ?? 0;

    final EntitlementPlan backendPlan;
    if (tierStr == 'pro') {
      backendPlan = EntitlementPlan.pro;
    } else if (tierStr == 'plus') {
      backendPlan = EntitlementPlan.plus;
    } else {
      backendPlan = EntitlementPlan.limited;
    }

    final storeEntitlementActive =
        current.plan != EntitlementPlan.limited &&
        (current.status == SubscriptionStatus.active ||
            current.status == SubscriptionStatus.cancelled ||
            current.status == SubscriptionStatus.grace ||
            current.status == SubscriptionStatus.billingRetry);

    if (storeEntitlementActive && current.plan.index > backendPlan.index) {
      // Webhook not processed yet: keep the verified store entitlement.
      return current.copyWith(scansUsedToday: used);
    }

    return current.copyWith(
      plan: backendPlan,
      scansUsedToday: used,
      dailyScanLimit: limit,
      status: backendPlan == EntitlementPlan.limited
          ? SubscriptionStatus.none
          : SubscriptionStatus.active,
    );
  }

  static DateTime _todayUtc() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }

  void _checkDailyReset() {
    final today = _todayUtc();
    if (today.isAfter(_lastResetDate)) {
      _scansToday = 0;
      _lastResetDate = today;
      _state = _state.copyWith(scansUsedToday: 0);
    }
  }

  // ─── CustomerInfo → EntitlementState mapping ──────────────────────────────

  static EntitlementState _mapCustomerInfo(CustomerInfo info, int scansUsed) {
    final active = info.entitlements.active;

    if (active.containsKey(_entitlementPro)) {
      final ent = active[_entitlementPro]!;
      return EntitlementState(
        plan: EntitlementPlan.pro,
        status: _statusFrom(ent),
        scansUsedToday: scansUsed,
        dailyScanLimit: TierQuota.proDaily,
        advancedRecognitionEnabled: true,
        marketValuationEnabled: true,
        scanHistoryEnabled: true,
        expiresAt: _parseDate(info.latestExpirationDate),
      );
    }

    if (active.containsKey(_entitlementPlus)) {
      final ent = active[_entitlementPlus]!;
      return EntitlementState(
        plan: EntitlementPlan.plus,
        status: _statusFrom(ent),
        scansUsedToday: scansUsed,
        dailyScanLimit: TierQuota.plusDaily,
        advancedRecognitionEnabled: true,
        marketValuationEnabled: false,
        scanHistoryEnabled: true,
        expiresAt: _parseDate(info.latestExpirationDate),
      );
    }

    return EntitlementState(
      plan: EntitlementPlan.limited,
      status: SubscriptionStatus.none,
      scansUsedToday: scansUsed,
      dailyScanLimit: TierQuota.limitedDaily,
      advancedRecognitionEnabled: false,
      marketValuationEnabled: false,
      scanHistoryEnabled: false,
    );
  }

  static SubscriptionStatus _statusFrom(EntitlementInfo info) {
    if (!info.isActive) return SubscriptionStatus.expired;
    if (!info.willRenew) return SubscriptionStatus.cancelled;
    return SubscriptionStatus.active;
  }

  static DateTime? _parseDate(String? s) {
    if (s == null) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  // ─── Package → SubscriptionProduct ───────────────────────────────────────

  static SubscriptionProduct? _packageToProduct(Package pkg) {
    final product = pkg.storeProduct;
    final id = product.identifier;

    EntitlementPlan plan;
    if (id.contains('pro')) {
      plan = EntitlementPlan.pro;
    } else if (id.contains('plus')) {
      plan = EntitlementPlan.plus;
    } else {
      return null;
    }

    final period = (id.contains('yearly') ||
            id.contains('annual') ||
            pkg.packageType == PackageType.annual)
        ? BillingPeriod.yearly
        : BillingPeriod.monthly;

    return SubscriptionProduct(
      productId: id,
      title: product.title,
      description: product.description,
      priceDisplay: product.priceString, // store-supplied, never hardcoded
      priceUsd: product.price,
      period: period,
      plan: plan,
    );
  }

  static List<SubscriptionProduct> _staticFallbackProducts() => const [
        SubscriptionProduct(
          productId: RevenueCatConfig.productPlusMonthly,
          title: 'CoinScan Plus',
          description: '30 scans/day · Advanced recognition',
          priceDisplay: '—',
          priceUsd: 0.0,
          period: BillingPeriod.monthly,
          plan: EntitlementPlan.plus,
        ),
        SubscriptionProduct(
          productId: RevenueCatConfig.productPlusYearly,
          title: 'CoinScan Plus',
          description: '30 scans/day · Advanced recognition · Save 33%',
          priceDisplay: '—',
          priceUsd: 0.0,
          period: BillingPeriod.yearly,
          plan: EntitlementPlan.plus,
        ),
        SubscriptionProduct(
          productId: RevenueCatConfig.productProMonthly,
          title: 'CoinScan Pro',
          description: '100 scans/day · Full valuation · Market data',
          priceDisplay: '—',
          priceUsd: 0.0,
          period: BillingPeriod.monthly,
          plan: EntitlementPlan.pro,
        ),
        SubscriptionProduct(
          productId: RevenueCatConfig.productProYearly,
          title: 'CoinScan Pro',
          description: '100 scans/day · Full valuation · Market data · Save 33%',
          priceDisplay: '—',
          priceUsd: 0.0,
          period: BillingPeriod.yearly,
          plan: EntitlementPlan.pro,
        ),
      ];

  static String _userFacingError(PurchasesErrorCode code) {
    switch (code) {
      case PurchasesErrorCode.purchaseCancelledError:
        return 'Purchase was cancelled.';
      case PurchasesErrorCode.purchaseNotAllowedError:
        return 'Purchases are not allowed on this device.';
      case PurchasesErrorCode.networkError:
        return 'A network error occurred. Please check your connection and try again.';
      case PurchasesErrorCode.productNotAvailableForPurchaseError:
        return 'This product is not currently available for purchase.';
      case PurchasesErrorCode.storeProblemError:
        return 'The App Store / Google Play reported an error. Please try again.';
      case PurchasesErrorCode.paymentPendingError:
        return 'Your payment is pending approval.';
      case PurchasesErrorCode.productAlreadyPurchasedError:
        return 'You already have an active subscription. Try "Restore Purchases".';
      default:
        return 'The purchase could not be completed. Please try again.';
    }
  }

  // ─── Test-only accessors ──────────────────────────────────────────────────

  /// Current entitlement state snapshot (read-only, for testing).
  @visibleForTesting
  EntitlementState get state => _state;

  /// Exposes the internal CustomerInfo→EntitlementState mapping for unit tests.
  ///
  /// This is the only function that test code may call directly on private logic.
  /// It is annotated @visibleForTesting so the linter flags non-test usage.
  @visibleForTesting
  static EntitlementState mapCustomerInfoForTest(
    CustomerInfo info,
    int scansUsed,
  ) =>
      _mapCustomerInfo(info, scansUsed);
}

/// Typed exception for purchase/restore failures surfaced to the UI.
///
/// [isCancellation] should be true when the user explicitly dismissed the
/// native purchase sheet — the UI should suppress error dialogs in that case.
class PurchaseException implements Exception {
  final String message;
  final bool isCancellation;

  const PurchaseException(this.message, {required this.isCancellation});

  @override
  String toString() => 'PurchaseException($message)';
}
