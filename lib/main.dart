import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/auth/auth_service.dart';
import 'core/config/app_config.dart';
import 'core/subscriptions/revenuecat_subscription_service.dart';
import 'core/theme/theme.dart';
import 'core/navigation/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize environment-aware configuration
  AppConfig.initialize();

  // Initialize Supabase if configured at runtime/compile-time
  if (AppConfig.instance.isSupabaseConfigured) {
    try {
      await Supabase.initialize(
        url: AppConfig.instance.supabaseUrl!,
        // ignore: deprecated_member_use
        anonKey: AppConfig.instance.supabaseAnonKey!,
      );
    } catch (e) {
      debugPrint('Supabase initialization error: $e');
    }
  }

  // Restore persistent session
  await AuthService.instance.initialize();

  // Initialize RevenueCat subscription service.
  // Uses public SDK key from --dart-define=REVENUECAT_APPLE_KEY / REVENUECAT_GOOGLE_KEY.
  // Falls back gracefully when keys are absent (dev/test mode).
  final authUser = AuthService.instance.currentState.user;
  final currentUserId = AuthService.instance.currentState.isAuthenticated &&
          authUser != null &&
          authUser.userId != 'guest_user'
      ? authUser.userId
      : null;

  final subscriptionService = await RevenueCatSubscriptionService.initialize(
    appUserId: currentUserId,
  );

  // Wire RevenueCat identity to Supabase auth state changes.
  AuthService.instance.authStateChanges.listen((authState) async {
    final uid = authState.user?.userId;
    if (authState.isAuthenticated && uid != null && uid != 'guest_user') {
      await subscriptionService.logIn(uid);
    } else {
      await subscriptionService.logOut();
    }
  });

  runApp(CoinVaultApp(subscriptionService: subscriptionService));
}

class CoinVaultApp extends StatelessWidget {
  final SubscriptionService subscriptionService;

  const CoinVaultApp({super.key, required this.subscriptionService});

  @override
  Widget build(BuildContext context) {
    return SubscriptionProvider(
      service: subscriptionService,
      child: MaterialApp.router(
        title: 'CoinScan',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: AppRouter.router,
      ),
    );
  }
}

/// InheritedWidget providing [SubscriptionService] to the widget tree.
///
/// Access via: `SubscriptionProvider.of(context)`
class SubscriptionProvider extends InheritedWidget {
  final SubscriptionService service;

  const SubscriptionProvider({
    super.key,
    required this.service,
    required super.child,
  });

  static SubscriptionService of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<SubscriptionProvider>();
    assert(provider != null, 'No SubscriptionProvider found in context');
    return provider!.service;
  }

  static SubscriptionService? maybeOf(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<SubscriptionProvider>();
    return provider?.service;
  }

  @override
  bool updateShouldNotify(SubscriptionProvider oldWidget) =>
      service != oldWidget.service;
}

