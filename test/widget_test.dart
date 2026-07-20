import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coinvault_ai/main.dart';

void main() {
  testWidgets('End-to-End User Flow verification test', (WidgetTester tester) async {
    // Set standard phone viewport dimensions
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;

    // 1. Boot up the app
    await tester.pumpWidget(const CoinVaultApp());
    await tester.pumpAndSettle();

    // Verify first onboarding slide renders correctly
    expect(find.text('Discover History.'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    // 2. Click "Continue" button on onboarding slides
    // Slide 1 -> Slide 2
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    // Slide 2 -> Slide 3
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    // Slide 3 -> Slide 4
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    // Slide 4 "Get Started" triggers routing to Login Screen
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 3. Confirm Login screen is loaded
    expect(find.text('Welcome to CoinVault AI'), findsOneWidget);
    
    // Find Guest Bypass button
    final guestBypassFinder = find.text('Bypass and Enter as Guest');
    expect(guestBypassFinder, findsOneWidget);

    // 4. Tap Guest Bypass to load main layout shell
    await tester.tap(guestBypassFinder);
    
    // Step through the route transition frame-by-frame to complete mounting
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // 5. Confirm Home Dashboard loaded correctly
    expect(find.text('Good Morning,'), findsOneWidget);
    expect(find.text('Vaibhav'), findsOneWidget);
    expect(find.text('Vault Value'), findsOneWidget);

    // Reset test viewport setup
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
