import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_service.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/onboarding/login_screen.dart';
import '../../features/home/main_navigation_wrapper.dart';

class AppRouter {
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String main = '/';

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

  static final GoRouter router = GoRouter(
    initialLocation: AuthService.instance.currentState.isAuthenticated ? main : onboarding,
    refreshListenable: AuthService.instance,
    redirect: (context, state) {
      final isAuthenticated = AuthService.instance.currentState.isAuthenticated;
      final isAuthFlow = state.matchedLocation == login || state.matchedLocation == onboarding;

      if (isAuthenticated && isAuthFlow) {
        return main;
      }
      return null;
    },
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
