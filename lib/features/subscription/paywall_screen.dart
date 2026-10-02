import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/auth/auth_service.dart';
import '../../core/subscriptions/revenuecat_subscription_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../onboarding/account_prompt.dart';
import '../profile/legal_screen.dart';

/// Premium paywall screen showing tier comparison and purchase CTAs.
///
/// Matches the existing CoinScan dark/gold design language. Triggered when
/// a free-tier user exhausts their daily scan quota or taps "Upgrade".
class PaywallScreen extends StatefulWidget {
  final SubscriptionService subscriptionService;
  final VoidCallback? onDismiss;
  final AuthService? authService;

  const PaywallScreen({
    super.key,
    required this.subscriptionService,
    this.onDismiss,
    this.authService,
  });

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  List<SubscriptionProduct> _products = [];
  bool _isLoading = true;
  bool _isPurchasing = false;
  bool _showYearly = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final products = await widget.subscriptionService.availableProducts();
    if (mounted) {
      setState(() {
        _products = products;
        _isLoading = false;
      });
    }
  }

  AuthService get _auth => widget.authService ?? AuthService.instance;

  bool get _signedIn => _auth.currentState.isAuthenticated;

  /// Subscriptions belong to an account: guests sign in first, then choose a
  /// plan again themselves.
  Future<void> _promptSignIn() async {
    await promptForAccount(
      context,
      title: 'Sign in to subscribe',
      message:
          'Subscriptions belong to your CoinScan account, so they work on your '
          'other devices and can be restored. Sign in or create a free account, '
          'then choose your plan.',
      authService: widget.authService,
    );
    if (mounted) setState(() {});
  }

  Future<void> _handlePurchase(SubscriptionProduct product) async {
    if (!_signedIn) return _promptSignIn();
    setState(() => _isPurchasing = true);
    try {
      await widget.subscriptionService.purchase(product.productId);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on PurchaseException catch (e) {
      if (mounted) {
        setState(() => _isPurchasing = false);
        if (e.requiresAccount) {
          await _promptSignIn();
          return;
        }
        // Silently dismiss on user cancellation — don't show an error
        if (!e.isCancellation) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.crimson,
              content: Text(
                e.message,
                style: AppTypography.bodyMedium.copyWith(color: Colors.white),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPurchasing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.crimson,
            content: Text(
              'Purchase could not be completed. Please try again.',
              style: AppTypography.bodyMedium.copyWith(color: Colors.white),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleRestore() async {
    if (!_signedIn) return _promptSignIn();
    setState(() => _isPurchasing = true);
    try {
      final state = await widget.subscriptionService.restorePurchases();
      if (mounted) {
        if (state.plan != EntitlementPlan.limited) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.inkElevated,
              content: Text(
                'Your subscription has been restored.',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.gold,
                ),
              ),
            ),
          );
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.amber,
              content: Text(
                'No active subscriptions found for this account.',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.onGold,
                ),
              ),
            ),
          );
          setState(() => _isPurchasing = false);
        }
      }
    } on PurchaseException catch (e) {
      if (mounted) {
        setState(() => _isPurchasing = false);
        if (e.requiresAccount) {
          await _promptSignIn();
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.crimson,
            content: Text(
              e.message,
              style: AppTypography.bodyMedium.copyWith(color: Colors.white),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  List<SubscriptionProduct> get _filteredProducts {
    final period = _showYearly ? BillingPeriod.yearly : BillingPeriod.monthly;
    return _products.where((p) => p.period == period).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.gold),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: AppSpacing.lg),
                          _buildHero(),
                          const SizedBox(height: AppSpacing.xxl),
                          _buildPeriodToggle(),
                          const SizedBox(height: AppSpacing.xl),
                          if (!_signedIn) ...[
                            _buildSignInNote(),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          _buildTierCards(),
                          const SizedBox(height: AppSpacing.xxl),
                          _buildFeatureComparison(),
                          const SizedBox(height: AppSpacing.xl),
                          _buildRestoreLink(),
                          const SizedBox(height: AppSpacing.md),
                          _buildLegalText(),
                          const SizedBox(height: AppSpacing.xxxl),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            key: const ValueKey('paywall_close'),
            icon: const Icon(Icons.close, color: AppColors.textOnInk),
            onPressed: widget.onDismiss ?? () => Navigator.of(context).pop(),
          ),
          Text(
            'COINSCAN PRO',
            style: AppTypography.goldLabel.copyWith(
              color: AppColors.gold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 48), // balance the close button
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.goldGradient,
            boxShadow: AppShadows.goldGlow(),
          ),
          child: const Icon(
            Icons.workspace_premium_rounded,
            color: AppColors.onGold,
            size: 40,
          ),
        )
            .animate()
            .scale(
              begin: const Offset(0.8, 0.8),
              end: const Offset(1.0, 1.0),
              duration: AppDuration.base,
              curve: AppCurves.overshoot,
            )
            .fadeIn(duration: AppDuration.fast),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Unlock Full\nCoin Recognition',
          textAlign: TextAlign.center,
          style: AppTypography.heroTitle.copyWith(color: AppColors.textOnInk),
        ).animate().fadeIn(delay: 100.ms, duration: AppDuration.base),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Advanced AI identification, unlimited scans,\nmarket valuations and full scan history.',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMuted.copyWith(
            color: AppColors.textOnInkMuted,
          ),
        ).animate().fadeIn(delay: 200.ms, duration: AppDuration.base),
      ],
    );
  }

  Widget _buildPeriodToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: AppColors.inkElevated,
        borderRadius: AppRadius.allPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: _periodTab('Monthly', !_showYearly, () {
              setState(() => _showYearly = false);
            }),
          ),
          Flexible(
            child: _periodTab('Yearly — Save 33%', _showYearly, () {
              setState(() => _showYearly = true);
            }),
          ),
        ],
      ),
    );
  }

  Widget _periodTab(String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDuration.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isActive ? AppColors.gold : Colors.transparent,
          borderRadius: AppRadius.allPill,
        ),
        child: Text(
          label,
          style: AppTypography.buttonTextSmall.copyWith(
            color: isActive ? AppColors.onGold : AppColors.textOnInkMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildSignInNote() {
    return Container(
      key: const ValueKey('paywall_sign_in_note'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.inkElevated,
        borderRadius: AppRadius.allLg,
        border: Border.all(color: AppColors.borderOnInk),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline_rounded, color: AppColors.gold),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Subscriptions belong to your CoinScan account. Sign in or create '
              'a free account to subscribe.',
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textOnInk,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierCards() {
    final products = _filteredProducts;
    return Column(
      children: products.map((product) {
        final isPro = product.plan == EntitlementPlan.pro;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _buildTierCard(product, isPro),
        );
      }).toList(),
    );
  }

  Widget _buildTierCard(SubscriptionProduct product, bool isHighlighted) {
    return GestureDetector(
      onTap: _isPurchasing ? null : () => _handlePurchase(product),
      child: AnimatedContainer(
        duration: AppDuration.fast,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: isHighlighted ? AppColors.goldGradient : null,
          color: isHighlighted ? null : AppColors.inkElevated,
          borderRadius: AppRadius.allLg,
          border: isHighlighted
              ? null
              : Border.all(color: AppColors.borderOnInk, width: 1),
          boxShadow: isHighlighted ? AppShadows.goldGlow(opacity: 0.25) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isHighlighted)
                        Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.onGold.withValues(alpha: 0.15),
                            borderRadius: AppRadius.allPill,
                          ),
                          child: Text(
                            'MOST POPULAR',
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.onGold,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      Text(
                        product.title,
                        style: AppTypography.titleMedium.copyWith(
                          color: isHighlighted
                              ? AppColors.onGold
                              : AppColors.textOnInk,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  product.priceDisplay,
                  style: AppTypography.numericMedium.copyWith(
                    color: isHighlighted
                        ? AppColors.onGold
                        : AppColors.gold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              product.description,
              style: AppTypography.bodyMuted.copyWith(
                color: isHighlighted
                    ? AppColors.onGold.withValues(alpha: 0.7)
                    : AppColors.textOnInkMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: BoxDecoration(
                color: isHighlighted
                    ? AppColors.onGold
                    : AppColors.gold,
                borderRadius: AppRadius.allSm,
              ),
              child: _isPurchasing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.gold,
                        ),
                      ),
                    )
                  : Text(
                      isHighlighted ? 'Subscribe Now' : 'Choose Plan',
                      textAlign: TextAlign.center,
                      style: AppTypography.buttonText.copyWith(
                        color: isHighlighted
                            ? AppColors.gold
                            : AppColors.onGold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: AppDuration.base).slideY(
      begin: 0.1,
      end: 0,
      duration: AppDuration.base,
      curve: AppCurves.standard,
    );
  }

  Widget _buildFeatureComparison() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: const BoxDecoration(
        color: AppColors.inkElevated,
        borderRadius: AppRadius.allMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Compare Plans',
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.textOnInk,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _featureRow('Daily scans', '3', '30', '100'),
          _featureRow('AI Recognition', '●', '●', '●'),
          _featureRow('Advanced analysis', '—', '●', '●'),
          _featureRow('Market valuation', '—', '—', '●'),
          _featureRow('Scan history', '—', '●', '●'),
          _featureRow('Priority support', '—', '—', '●'),
        ],
      ),
    );
  }

  Widget _featureRow(
    String feature,
    String limited,
    String plus,
    String pro,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              feature,
              style: AppTypography.caption.copyWith(
                color: AppColors.textOnInkMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              limited,
              textAlign: TextAlign.center,
              style: AppTypography.captionSmall.copyWith(
                color: limited == '—'
                    ? AppColors.textMutedDark
                    : AppColors.textOnInkMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              plus,
              textAlign: TextAlign.center,
              style: AppTypography.captionSmall.copyWith(
                color: plus == '—'
                    ? AppColors.textMutedDark
                    : AppColors.gold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              pro,
              textAlign: TextAlign.center,
              style: AppTypography.captionSmall.copyWith(
                color: pro == '—'
                    ? AppColors.textMutedDark
                    : AppColors.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestoreLink() {
    return GestureDetector(
      key: const ValueKey('paywall_restore'),
      onTap: _isPurchasing ? null : _handleRestore,
      child: Text(
        'Restore Purchases',
        style: AppTypography.bodyMuted.copyWith(
          color: AppColors.gold,
          decoration: TextDecoration.underline,
          decorationColor: AppColors.gold.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildLegalText() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      child: Text.rich(
        TextSpan(
          text:
              'Subscriptions are billed through the App Store or Google Play and '
              'automatically renew unless cancelled at least 24 hours before the end '
              'of the current period. Manage your subscription in your device account '
              'settings. By subscribing, you agree to our ',
          style: AppTypography.captionSmall.copyWith(
            color: AppColors.textOnInkMuted.withValues(alpha: 0.6),
          ),
          children: [
            TextSpan(
              text: 'Terms of Use',
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.gold,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LegalScreen(
                        document: CoinScanLegalDocs.termsOfService,
                      ),
                    ),
                  );
                },
            ),
            const TextSpan(text: ' and '),
            TextSpan(
              text: 'Privacy Policy',
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.gold,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LegalScreen(
                        document: CoinScanLegalDocs.privacyPolicy,
                      ),
                    ),
                  );
                },
            ),
            const TextSpan(text: '.'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
