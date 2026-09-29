import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/premium_widgets.dart';
import '../profile/legal_screen.dart';

/// Account entry.
///
/// Kept deliberately quiet after the ink-immersive onboarding — this screen's
/// job is to get out of the way. Validation is inline and on-blur rather than
/// on-submit-only, the form is width-capped so it stays a comfortable reading
/// column on tablets and web, and every field carries autofill hints so the
/// platform password manager can do the typing.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _useBiometrics = false;
  bool _termsAccepted = false;
  bool _isSubmitting = false;

  /// Which provider is mid-flight, so only that button shows a spinner.
  String? _pendingProvider;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _busy => _isSubmitting || _pendingProvider != null;

  Future<void> _handleEmailLogin() async {
    FocusScope.of(context).unfocus();
    if (!_termsAccepted) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.crimson,
          content: Text(
            'Please agree to the Terms & Conditions and acknowledge the Privacy Policy.',
          ),
        ),
      );
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      HapticFeedback.heavyImpact();
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await AuthService.instance.signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        termsAccepted: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: $e')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    HapticFeedback.lightImpact();
    context.go('/');
  }

  Future<void> _handleOAuthLogin(String provider) async {
    FocusScope.of(context).unfocus();
    if (!_termsAccepted) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.crimson,
          content: Text(
            'Please agree to the Terms & Conditions and acknowledge the Privacy Policy.',
          ),
        ),
      );
      return;
    }

    setState(() => _pendingProvider = provider);
    try {
      if (provider == 'Apple') {
        await AuthService.instance.signInWithApple(termsAccepted: true);
      } else {
        await AuthService.instance.signInWithGoogle(termsAccepted: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingProvider = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$provider sign-in failed: $e')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _pendingProvider = null);
    context.go('/');
  }

  void _showForgotPasswordDialog() {
    final resetEmailController = TextEditingController(text: _emailController.text);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reset Password', style: AppTypography.sectionHeader.copyWith(fontSize: 20)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter your account email to receive instructions on resetting your vault password.',
                style: AppTypography.bodyMuted,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: resetEmailController,
                keyboardType: TextInputType.emailAddress,
                style: AppTypography.bodyMedium,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'name@domain.com',
                  prefixIcon: Icon(Icons.alternate_email_rounded, size: 19),
                ),
                validator: (val) {
                  final v = val?.trim() ?? '';
                  if (v.isEmpty) return 'Please enter your email';
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
                    return 'Please enter a valid email address';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          GoldButton(
            text: 'Send Reset Link',
            size: GoldButtonSize.compact,
            expand: false,
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                final email = resetEmailController.text.trim();
                Navigator.of(ctx).pop();
                HapticFeedback.mediumImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppColors.emerald,
                    behavior: SnackBarBehavior.floating,
                    content: Text(
                      'Password reset link sent to $email. Please check your inbox.',
                      style: AppTypography.bodyMedium.copyWith(color: Colors.white),
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.lightOverlay,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.xl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppBreakpoints.maxContentWidth,
                ),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Reveal(index: 0, child: _LoginHeader()),
                      const SizedBox(height: AppSpacing.xxxl),
                      Reveal(index: 1, child: _buildForm()),
                      const SizedBox(height: AppSpacing.xxl),
                      Reveal(index: 2, child: _buildProviders()),
                      const SizedBox(height: AppSpacing.xl),
                      Reveal(index: 3, child: _buildGuestEntry()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _FieldLabel('Email address'),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _emailController,
            enabled: !_busy,
            style: AppTypography.bodyLarge,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
            decoration: const InputDecoration(
              hintText: 'name@domain.com',
              prefixIcon: Icon(Icons.alternate_email_rounded, size: 19),
            ),
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return 'Enter your email address';
              // Deliberately permissive — just enough to catch typos.
              final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
              return valid ? null : 'That doesn’t look like a valid email';
            },
          ),
          const SizedBox(height: AppSpacing.lg),

          Row(
            children: [
              const Expanded(child: _FieldLabel('Password')),
              TextButton(
                onPressed: _busy ? null : _showForgotPasswordDialog,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  minimumSize: const Size(0, 32),
                  textStyle: AppTypography.caption,
                ),
                child: const Text('Forgot?'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          TextFormField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            enabled: !_busy,
            obscureText: _obscurePassword,
            style: AppTypography.bodyLarge,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onFieldSubmitted: (_) => _handleEmailLogin(),
            decoration: InputDecoration(
              hintText: 'At least 8 characters',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 19),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 19,
                ),
                // Screen readers need to know what the toggle will do.
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (value) {
              if ((value ?? '').isEmpty) return 'Enter your password';
              if ((value ?? '').length < 8) {
                return 'Passwords are at least 8 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.base),

          _BiometricToggle(
            value: _useBiometrics,
            enabled: !_busy,
            onChanged: (v) => setState(() => _useBiometrics = v),
          ),
          const SizedBox(height: AppSpacing.lg),

          _buildTermsConsentBox(),
          const SizedBox(height: AppSpacing.lg),

          GoldButton(
            text: 'Sign in',
            isLoading: _isSubmitting,
            onPressed: (_pendingProvider == null && _termsAccepted)
                ? _handleEmailLogin
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildTermsConsentBox() {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xs,
        horizontal: AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 24,
            width: 24,
            child: Checkbox(
              value: _termsAccepted,
              activeColor: AppColors.goldDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              onChanged: _busy
                  ? null
                  : (val) {
                      setState(() => _termsAccepted = val ?? false);
                    },
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'I agree to the CoinScan ',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: 'Terms & Conditions',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.goldDark,
                      fontWeight: FontWeight.w600,
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
                  const TextSpan(text: ' and acknowledge the '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.goldDark,
                      fontWeight: FontWeight.w600,
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviders() {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text('or continue with', style: AppTypography.caption),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: GoldButton(
                text: 'Google',
                icon: Icons.g_mobiledata_rounded,
                variant: GoldButtonVariant.secondary,
                isLoading: _pendingProvider == 'Google',
                onPressed: (!_busy && _termsAccepted)
                    ? () => _handleOAuthLogin('Google')
                    : null,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: GoldButton(
                text: 'Apple',
                icon: Icons.apple_rounded,
                variant: GoldButtonVariant.secondary,
                isLoading: _pendingProvider == 'Apple',
                onPressed: (!_busy && _termsAccepted)
                    ? () => _handleOAuthLogin('Apple')
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGuestEntry() {
    return Column(
      children: [
        TextButton(
          onPressed: _busy ? null : () => context.go('/'),
          child: const Text('Explore as a guest'),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Guest mode provides limited browsing without account sync.',
          style: AppTypography.captionSmall.copyWith(
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _LoginHeader extends StatelessWidget {
  const _LoginHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 60,
          width: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.goldGradient,
            boxShadow: AppShadows.goldGlow(opacity: 0.3),
          ),
          child: const Center(
            child: Text(
              'V',
              style: TextStyle(
                color: AppColors.onGold,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Welcome back',
          style: AppTypography.heroTitle.copyWith(fontSize: 30),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Sign in to reach your vault, valuations and\nmarket activity.',
          style: AppTypography.subtitle,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.titleSmall.copyWith(color: AppColors.textPrimary),
    );
  }
}

class _BiometricToggle extends StatelessWidget {
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _BiometricToggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppDuration.fast,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: value
            ? AppColors.gold.withValues(alpha: 0.07)
            : AppColors.surface,
        borderRadius: AppRadius.allMd,
        border: Border.all(
          color: value
              ? AppColors.gold.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.face_retouching_natural_rounded,
            color: value ? AppColors.goldInk : AppColors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Unlock with Face ID', style: AppTypography.titleSmall),
                const SizedBox(height: 1),
                Text(
                  'Skip the password next time',
                  style: AppTypography.captionSmall,
                ),
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}
