import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import 'account_flow_screens.dart';
import 'login_screen.dart';

/// Asks a signed-out user to sign in or create a free account, and opens the
/// chosen screen above the current one. Returns whether the user is signed in
/// once they come back.
///
/// It never performs the action that needed an account: after signing in the
/// user repeats it (e.g. taps Save to Vault again), so nothing from the guest
/// session is moved into the account silently.
Future<bool> promptForAccount(
  BuildContext context, {
  required String title,
  required String message,
  AuthService? authService,
}) async {
  final auth = authService ?? AuthService.instance;
  if (auth.currentState.isAuthenticated) return true;

  final createAccount = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.inkElevated,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: Column(
          key: const ValueKey('account_prompt'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: AppTypography.sectionHeader.copyWith(
                color: Colors.white,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textOnInkMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              key: const ValueKey('account_prompt_signup'),
              onPressed: () => Navigator.of(sheetContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.ink,
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Create free account'),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              key: const ValueKey('account_prompt_signin'),
              onPressed: () => Navigator.of(sheetContext).pop(false),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Sign in'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              key: const ValueKey('account_prompt_dismiss'),
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text(
                'Not now',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (createAccount == null || !context.mounted) return false;

  // Sign-in sits underneath sign-up, so "Already have an account?" leads back
  // to it. Both close themselves once the session is established.
  final navigator = Navigator.of(context);
  final flow = navigator.push<bool>(
    MaterialPageRoute(
      builder: (_) => LoginScreen(popOnSuccess: true, authService: authService),
    ),
  );
  if (createAccount) {
    navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            SignUpScreen(popOnSuccess: true, authService: authService),
      ),
    );
  }
  await flow;
  return auth.currentState.isAuthenticated;
}
