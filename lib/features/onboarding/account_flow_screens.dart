import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../../core/auth/auth_service.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/premium_widgets.dart';
import '../profile/legal_screen.dart';

/// Closes the account screen that owns [context], whether or not it is the
/// top-most route: an in-app sign-in can complete while another account screen
/// is open above it.
void closeAccountRoute(BuildContext context, [bool? result]) {
  final route = ModalRoute.of(context);
  if (route == null || !route.isActive) return;
  final navigator = Navigator.of(context);
  if (route.isCurrent) {
    navigator.pop(result);
  } else {
    navigator.removeRoute(route, result);
  }
}

/// Plain-language message for an authentication failure. Never shows raw
/// exception text or internal details.
String authErrorMessage(Object error) {
  if (error is supa.AuthException) {
    final msg = error.message.trim();
    if (msg.toLowerCase().contains('invalid login credentials')) {
      return 'That email and password don’t match an account.';
    }
    if (msg.toLowerCase().contains('email not confirmed')) {
      return 'Please confirm your email address first. Check your inbox for the link.';
    }
    if (msg.toLowerCase().contains('already registered')) {
      return 'An account with this email already exists. Try signing in instead.';
    }
    return msg.isEmpty ? 'Something went wrong. Please try again.' : msg;
  }
  if (error is AuthConfigurationException) return error.message;
  if (error is TermsConsentRequiredException) {
    return 'Please accept the Terms and acknowledge the Privacy Policy to continue.';
  }
  if (error is ApiException) {
    return error.statusCode == 0 || error.statusCode == 408
        ? 'We couldn’t reach CoinScan. Check your connection and try again.'
        : 'CoinScan couldn’t complete that request. Please try again.';
  }
  return 'Something went wrong. Please try again.';
}

bool _looksLikeEmail(String v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

String? validateEmail(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Enter your email address';
  return _looksLikeEmail(v) ? null : 'That doesn’t look like a valid email';
}

String? validateNewPassword(String? value) {
  final v = value ?? '';
  if (v.length < 8) return 'Use at least 8 characters';
  return null;
}

/// Shared layout for the account flow screens.
class _AccountScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool showBack;

  const _AccountScaffold({
    required this.title,
    this.subtitle,
    required this.children,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: showBack
          ? AppBar(backgroundColor: AppColors.background, elevation: 0)
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: AppTypography.heroTitle.copyWith(fontSize: 28)),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(subtitle!, style: AppTypography.bodyMuted),
                  ],
                  const SizedBox(height: AppSpacing.xxl),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('auth_error_banner'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.crimson.withValues(alpha: 0.08),
        borderRadius: AppRadius.allMd,
        border: Border.all(color: AppColors.crimson.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.crimson, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: AppTypography.bodyMedium)),
        ],
      ),
    );
  }
}

/// "I agree to the Terms … Privacy Policy" checkbox with working links.
class TermsAgreementCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const TermsAgreementCheckbox({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    void open(LegalDocument doc) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => LegalScreen(document: doc)),
        );
    final linkStyle = AppTypography.caption.copyWith(
      color: AppColors.goldDark,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            key: const ValueKey('terms_checkbox'),
            value: value,
            activeColor: AppColors.goldDark,
            onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: AppTypography.caption.copyWith(color: AppColors.textPrimary, height: 1.4),
              children: [
                const TextSpan(text: 'I agree to the CoinScan '),
                TextSpan(
                  text: 'Terms & Conditions',
                  style: linkStyle,
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => open(CoinScanLegalDocs.termsOfService),
                ),
                const TextSpan(text: ' and acknowledge the '),
                TextSpan(
                  text: 'Privacy Policy',
                  style: linkStyle,
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => open(CoinScanLegalDocs.privacyPolicy),
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Sign up ────────────────────────────────────────────────────────────────

class SignUpScreen extends StatefulWidget {
  final AuthService? authService;

  /// Opened above another screen (see `promptForAccount`): once signed in,
  /// close and return there instead of resetting to the home screen.
  final bool popOnSuccess;

  const SignUpScreen({super.key, this.authService, this.popOnSuccess = false});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _termsAccepted = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _verificationEmail;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  AuthService get _auth => widget.authService ?? AuthService.instance;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    // An emailed confirmation link can complete sign-up while this screen is open.
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

  void _backToSignIn() {
    if (widget.popOnSuccess) {
      closeAccountRoute(context, false);
    } else {
      context.go('/login');
    }
  }

  @override
  void dispose() {
    if (widget.popOnSuccess) _auth.removeListener(_onAuthChanged);
    _cooldownTimer?.cancel();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_termsAccepted) {
      setState(() => _error = authErrorMessage(const TermsConsentRequiredException()));
      return;
    }
    setState(() => _busy = true);
    try {
      final state = await _auth.signUpWithEmail(
        email: _email.text.trim(),
        password: _password.text,
        displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        termsAccepted: true,
      );
      if (!mounted) return;
      if (state.isEmailVerificationPending) {
        setState(() => _verificationEmail = state.pendingVerificationEmail);
        _startCooldown();
      } else if (state.isAuthenticated) {
        _finish();
      }
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = 30);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendCooldown--);
      if (_resendCooldown <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    final email = _verificationEmail;
    if (email == null) return;
    setState(() => _error = null);
    try {
      await _auth.resendSignUpConfirmation(email);
      if (!mounted) return;
      _startCooldown();
      AppSnack.show(context, 'Confirmation email sent again.', tone: SnackTone.success);
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_verificationEmail != null) {
      return _AccountScaffold(
        title: 'Check your email',
        subtitle:
            'We sent a confirmation link to $_verificationEmail. Open it on this device to finish creating your account.',
        children: [
          if (_error != null) ...[_ErrorBanner(_error!), const SizedBox(height: AppSpacing.base)],
          GoldButton(
            text: _resendCooldown > 0 ? 'Resend email (${_resendCooldown}s)' : 'Resend email',
            variant: GoldButtonVariant.secondary,
            onPressed: _resendCooldown > 0 ? null : _resend,
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: _backToSignIn,
            child: const Text('Back to sign in'),
          ),
        ],
      );
    }

    return _AccountScaffold(
      title: 'Create your account',
      subtitle: 'Save coins to your vault and keep them in sync across devices.',
      children: [
        AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(labelText: 'Name (optional)'),
                ),
                const SizedBox(height: AppSpacing.base),
                TextFormField(
                  key: const ValueKey('signup_email'),
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email address'),
                  validator: validateEmail,
                ),
                const SizedBox(height: AppSpacing.base),
                TextFormField(
                  key: const ValueKey('signup_password'),
                  controller: _password,
                  enabled: !_busy,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText: 'At least 8 characters',
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: validateNewPassword,
                ),
                const SizedBox(height: AppSpacing.base),
                TextFormField(
                  key: const ValueKey('signup_confirm'),
                  controller: _confirm,
                  enabled: !_busy,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'Confirm password'),
                  validator: (v) => v == _password.text ? null : 'Passwords don’t match',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TermsAgreementCheckbox(
          value: _termsAccepted,
          onChanged: _busy ? null : (v) => setState(() => _termsAccepted = v),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_error != null) ...[_ErrorBanner(_error!), const SizedBox(height: AppSpacing.base)],
        GoldButton(
          key: const ValueKey('signup_submit'),
          text: 'Create account',
          isLoading: _busy,
          onPressed: _busy ? null : _submit,
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton(
          onPressed: _busy ? null : _backToSignIn,
          child: const Text('Already have an account? Sign in'),
        ),
      ],
    );
  }
}

// ─── Forgot password ────────────────────────────────────────────────────────

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmail;
  final AuthService? authService;

  const ForgotPasswordScreen({super.key, this.initialEmail, this.authService});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email =
      TextEditingController(text: widget.initialEmail ?? '');
  bool _busy = false;
  bool _sent = false;
  String? _error;

  AuthService get _auth => widget.authService ?? AuthService.instance;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await _auth.sendPasswordReset(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return _AccountScaffold(
        title: 'Check your email',
        // Does not reveal whether an account exists for this address.
        subtitle:
            'If an account exists for ${_email.text.trim()}, we’ve sent a link to reset your password. Open it on this device.',
        children: [
          GoldButton(text: 'Back to sign in', onPressed: () => context.go('/login')),
        ],
      );
    }
    return _AccountScaffold(
      title: 'Reset your password',
      subtitle: 'Enter the email for your CoinScan account and we’ll send you a reset link.',
      children: [
        Form(
          key: _formKey,
          child: TextFormField(
            key: const ValueKey('reset_email'),
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email address'),
            validator: validateEmail,
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_error != null) ...[_ErrorBanner(_error!), const SizedBox(height: AppSpacing.base)],
        GoldButton(
          key: const ValueKey('reset_submit'),
          text: 'Send reset link',
          isLoading: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}

// ─── Set new password (opened from the reset link) ───────────────────────────

class SetNewPasswordScreen extends StatefulWidget {
  final AuthService? authService;

  const SetNewPasswordScreen({super.key, this.authService});

  @override
  State<SetNewPasswordScreen> createState() => _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends State<SetNewPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  AuthService get _auth => widget.authService ?? AuthService.instance;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await _auth.completePasswordRecovery(_password.text);
      if (mounted) AppSnack.show(context, 'Your password has been updated.', tone: SnackTone.success);
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AccountScaffold(
      title: 'Choose a new password',
      subtitle: 'Enter a new password for ${_auth.currentState.user?.email ?? 'your account'}.',
      showBack: false,
      children: [
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: 'New password',
                  helperText: 'At least 8 characters',
                ),
                validator: validateNewPassword,
              ),
              const SizedBox(height: AppSpacing.base),
              TextFormField(
                controller: _confirm,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm new password'),
                validator: (v) => v == _password.text ? null : 'Passwords don’t match',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_error != null) ...[_ErrorBanner(_error!), const SizedBox(height: AppSpacing.base)],
        GoldButton(text: 'Update password', isLoading: _busy, onPressed: _busy ? null : _submit),
        const SizedBox(height: AppSpacing.md),
        TextButton(
          onPressed: _busy ? null : () => _auth.signOut(),
          child: const Text('Cancel and sign out'),
        ),
      ],
    );
  }
}

// ─── Terms consent (signed in, but current Terms not yet accepted) ──────────

class TermsConsentScreen extends StatefulWidget {
  final AuthService? authService;

  const TermsConsentScreen({super.key, this.authService});

  @override
  State<TermsConsentScreen> createState() => _TermsConsentScreenState();
}

class _TermsConsentScreenState extends State<TermsConsentScreen> {
  bool _accepted = false;
  bool _busy = false;
  String? _error;

  AuthService get _auth => widget.authService ?? AuthService.instance;

  Future<void> _accept() async {
    final userId = _auth.currentState.user?.userId;
    if (userId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.recordTermsReConsent(userId);
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _auth.currentState.user?.email;
    return _AccountScaffold(
      title: 'Before you continue',
      subtitle:
          'To use your CoinScan account${email != null && email.isNotEmpty ? ' ($email)' : ''}, please review and accept the current Terms & Conditions and Privacy Policy.',
      showBack: false,
      children: [
        TermsAgreementCheckbox(
          value: _accepted,
          onChanged: _busy ? null : (v) => setState(() => _accepted = v),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_error != null) ...[_ErrorBanner(_error!), const SizedBox(height: AppSpacing.base)],
        GoldButton(
          key: const ValueKey('consent_accept'),
          text: 'Accept and continue',
          isLoading: _busy,
          onPressed: (_accepted && !_busy) ? _accept : null,
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton(
          key: const ValueKey('consent_sign_out'),
          onPressed: _busy ? null : () => _auth.signOut(),
          child: const Text('Don’t accept and sign out'),
        ),
      ],
    );
  }
}
