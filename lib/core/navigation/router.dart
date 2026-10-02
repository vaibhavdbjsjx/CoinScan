import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_service.dart';
import '../../features/onboarding/account_flow_screens.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/onboarding/login_screen.dart';
import '../../features/home/main_navigation_wrapper.dart';

class AppRouter {
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String signUp = '/signup';
  static const String forgotPassword = '/forgot-password';
  static const String setNewPassword = '/set-new-password';
  static const String termsConsent = '/terms-consent';
  static const String main = '/';

  static const Set<String> _signedOutFlow = {onboarding, login, signUp, forgotPassword};

  // Custom slide/fade transition page creator
  static Page<void> customTransitionPage({
    required BuildContext context,
    required GoRouterState state,
    required Widget child,
  }) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurveTween(curve: Curves.easeInOutCubic).animate(animation),
          child: child,
        );
      },
    );
  }

  /// Redirect rules, in priority order:
  /// 1. A password-reset link was opened: only the set-new-password screen.
  /// 2. Signed in but the current Terms are not accepted: only the consent screen
  ///    (never a dead end: it offers "Accept" and "Sign out").
  /// 3. Fully signed in: leave the signed-out flow for the app.
  /// Guests may use the main app (scanning); vault saving asks them to sign in.
  static String? redirectFor(AuthState auth, String location) {
    if (auth.isPasswordRecovery) {
      return location == setNewPassword ? null : setNewPassword;
    }
    if (auth.needsTermsConsent) {
      return location == termsConsent ? null : termsConsent;
    }
    if (location == setNewPassword || location == termsConsent) return main;
    if (auth.isAuthenticated && _signedOutFlow.contains(location)) return main;
    return null;
  }

  static final GoRouter router = GoRouter(
    initialLocation: AuthService.instance.currentState.isAuthenticated ? main : onboarding,
    refreshListenable: AuthService.instance,
    redirect: (context, state) =>
        redirectFor(AuthService.instance.currentState, state.matchedLocation),
    routes: [
      GoRoute(
        path: onboarding,
        pageBuilder: (context, state) => customTransitionPage(
          context: context,
          state: state,
          child: const OnboardingScreen(),
        ),
      ),
      GoRoute(
        path: login,
        pageBuilder: (context, state) => customTransitionPage(
          context: context,
          state: state,
          child: const LoginScreen(),
        ),
      ),
      GoRoute(
        path: signUp,
        pageBuilder: (context, state) => customTransitionPage(
          context: context,
          state: state,
          child: const SignUpScreen(),
        ),
      ),
      GoRoute(
        path: forgotPassword,
        pageBuilder: (context, state) => customTransitionPage(
          context: context,
          state: state,
          // Email is passed in memory (extra), never in the route URL.
          child: ForgotPasswordScreen(initialEmail: state.extra is String ? state.extra as String : null),
        ),
      ),
      GoRoute(
        path: setNewPassword,
        pageBuilder: (context, state) => customTransitionPage(
          context: context,
          state: state,
          child: const SetNewPasswordScreen(),
        ),
      ),
      GoRoute(
        path: termsConsent,
        pageBuilder: (context, state) => customTransitionPage(
          context: context,
          state: state,
          child: const TermsConsentScreen(),
        ),
      ),
      GoRoute(
        path: main,
        pageBuilder: (context, state) => customTransitionPage(
          context: context,
          state: state,
          child: const MainNavigationWrapper(),
        ),
      ),
    ],
  );
}
