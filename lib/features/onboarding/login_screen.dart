import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/premium_widgets.dart';
import 'account_flow_screens.dart';

/// Account entry.
///
/// Kept deliberately quiet after the ink-immersive onboarding — this screen's
/// job is to get out of the way. Validation is inline and on-blur rather than
/// on-submit-only, the form is width-capped so it stays a comfortable reading
/// column on tablets and web, and every field carries autofill hints so the
/// platform password manager can do the typing.
class LoginScreen extends StatefulWidget {
  /// Opened above another screen (see `promptForAccount`): once signed in,
  /// close and return there instead of resetting to the home screen.
  final bool popOnSuccess;
  final AuthService? authService;

  const LoginScreen({super.key, this.popOnSuccess = false, this.authService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _termsAccepted = false;
  String? _error;
  bool _isSubmitting = false;

  /// Which provider is mid-flight, so only that button shows a spinner.
  String? _pendingProvider;
  bool _finished = false;

  AuthService get _auth => widget.authService ?? AuthService.instance;

  @override
  void initState() {
    super.initState();
    // Browser-based sign-in (Google / Apple) completes when the app is reopened
    // via the redirect link: close as soon as that session arrives.
    if (widget.popOnSuccess) _auth.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (_auth.currentState.isAuthenticated) _finish();
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    if (widget.popOnSuccess) {
      closeAccountRoute(context, true);
    } else {
      context.go('/');
    }
  }

  @override
  void dispose() {
    if (widget.popOnSuccess) _auth.removeListener(_onAuthChanged);
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

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await _auth.signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        termsAccepted: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = authErrorMessage(e);
      });
      return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    HapticFeedback.lightImpact();
    _finish();
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

    setState(() {
      _pendingProvider = provider;
      _error = null;
    });
    AuthState state;
    try {
      state = provider == 'Apple'
          ? await _auth.signInWithApple(termsAccepted: true)
          : await _auth.signInWithGoogle(termsAccepted: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingProvider = null;
        _error = authErrorMessage(e);
      });
      return;
    }

    if (!mounted) return;
    setState(() => _pendingProvider = null);
    // Browser-based sign-in finishes when the app is reopened via the redirect
    // link; the router then moves on automatically. Only navigate now if the
    // session is already complete.
    if (state.isAuthenticated) _finish();
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
            key: const ValueKey('login_email'),
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
                onPressed: _busy
                    ? null
                    : () => context.push(
                          '/forgot-password',
                          extra: _emailController.text.trim(),
                        ),
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
            key: const ValueKey('login_password'),
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

          TermsAgreementCheckbox(
            value: _termsAccepted,
            onChanged: _busy ? null : (v) => setState(() => _termsAccepted = v),
          ),
          const SizedBox(height: AppSpacing.lg),

          if (_error != null) ...[
            Container(
              key: const ValueKey('login_error'),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.crimson.withValues(alpha: 0.08),
                borderRadius: AppRadius.allMd,
              ),
              child: Text(_error!, style: AppTypography.bodyMedium),
            ),
            const SizedBox(height: AppSpacing.base),
          ],

          GoldButton(
            key: const ValueKey('login_submit'),
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

  void _openSignUp() {
    if (!widget.popOnSuccess) {
      context.push('/signup');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => SignUpScreen(popOnSuccess: true, authService: widget.authService),
      ),
    );
  }

  Widget _buildGuestEntry() {
    return Column(
      children: [
        TextButton(
          key: const ValueKey('create_account_link'),
          onPressed: _busy ? null : _openSignUp,
          child: const Text('New to CoinScan? Create an account'),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextButton(
          key: const ValueKey('continue_as_guest'),
          onPressed: _busy
              ? null
              : () => widget.popOnSuccess
                    ? closeAccountRoute(context, false)
                    : context.go('/'),
          child: Text(widget.popOnSuccess ? 'Not now' : 'Explore as a guest'),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'As a guest you can scan coins; saving to your vault needs an account.',
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

