import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:coinvault_ai/features/market/marketplace_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Marketplace Safety & Compliance Tests', () {
    testWidgets('1. Displays "Market Explorer" title and no fake transactional actions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MarketplaceScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Title must be Market Explorer
      expect(find.text('Market Explorer'), findsOneWidget);

      // Must prominently disclose upcoming marketplace release
      expect(find.text('COMING IN UPCOMING RELEASE'), findsOneWidget);
      expect(find.text('Verified Collector Marketplace'), findsOneWidget);

      // Prohibited mock transactional strings MUST NOT exist
      expect(find.text('BUY IT NOW'), findsNothing);
      expect(find.text('LIVE AUCTIONS'), findsNothing);
      expect(find.text('Place Secure Offer'), findsNothing);
      expect(find.text('Initialize Escrow Offer'), findsNothing);
      expect(find.text('TOTAL SALES (30D)'), findsNothing);
      expect(find.text('\$142,500'), findsNothing);
      expect(find.text('Dealer Hub Controls'), findsNothing);
      expect(find.text('Bulk Inventory Upload'), findsNothing);
      expect(find.text('Confirm Bid Lot'), findsNothing);
      expect(find.text('Place Bid'), findsNothing);
    });

    testWidgets('2. Displays real numismatic benchmarks and price guide categories', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MarketplaceScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Spot benchmarks
      expect(find.text('PRECIOUS METALS SPOT BENCHMARKS'), findsOneWidget);
      expect(find.text('Gold Spot Benchmark'), findsOneWidget);
      expect(find.text('Silver Spot Benchmark'), findsOneWidget);
      expect(find.text('Platinum Benchmark'), findsOneWidget);

      // Educational price guides
      expect(find.text('NUMISMATIC PRICE GUIDES & CATALOG TRENDS'), findsOneWidget);
      expect(find.text('Morgan Silver Dollar'), findsOneWidget);
      expect(find.text('Saint-Gaudens \$20 Double Eagle'), findsOneWidget);

      // Numismatic grading scale reference
      expect(find.text('Numismatic Grading Scale Reference'), findsOneWidget);
    });

    testWidgets('3. Allows user to toggle notification interest safely', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MarketplaceScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final notifyBtn = find.text('Notify Me When Available');
      expect(notifyBtn, findsOneWidget);

      await tester.tap(notifyBtn);
      await tester.pumpAndSettle();

      expect(find.text('Notification Saved'), findsOneWidget);
      expect(find.text('You will be notified when verified peer-to-peer trading launches.'), findsOneWidget);
    });
  });
}
