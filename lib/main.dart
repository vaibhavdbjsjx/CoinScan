import 'package:flutter/material.dart';
import 'core/theme/theme.dart';
import 'core/navigation/router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CoinVaultApp());
}

class CoinVaultApp extends StatelessWidget {
  const CoinVaultApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'CoinVault AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: AppRouter.router,
    );
  }
}
