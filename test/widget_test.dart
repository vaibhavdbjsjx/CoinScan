import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:coinvault_ai/core/recognition/recognition_models.dart';
import 'package:coinvault_ai/core/subscriptions/subscription_service.dart';
import 'package:coinvault_ai/features/scan/scan_screen.dart';
import 'package:coinvault_ai/main.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

CapturedCoinImage _syntheticImage(CaptureSide side, CaptureSource source) =>
    CapturedCoinImage(
      path: '/tmp/test_${side.name}.jpg',
      source: source,
      side: side,
      capturedAt: DateTime(2026, 1, 1),
      width: 640,
      height: 640,
      fileSizeBytes: 1024,
    );

Future<CapturedCoinImage?> _testImageFactory(
        CaptureSide side, CaptureSource source) async =>
    _syntheticImage(side, source);

/// Returns a minimal valid 1×1 transparent PNG — no real file I/O needed.
Future<Uint8List> _testPreviewLoader(CapturedCoinImage image) async =>
    Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1×1
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
      0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT chunk
      0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
      0x0D, 0x0A, 0x2D, 0xB4,
      0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);

Widget _scanScreen() => const MaterialApp(
      home: ScanScreen(
        testImageFactory: _testImageFactory,
        testPreviewLoader: _testPreviewLoader,
      ),
    );

// ---------------------------------------------------------------------------
// Navigation smoke test (does NOT go into camera — avoids hardware requirement)
// ---------------------------------------------------------------------------

void main() {
  testWidgets('Onboarding → Home smoke test', (WidgetTester tester) async {
    // Use a taller viewport so the login screen content is not off-screen.
    tester.view.physicalSize = const Size(390, 950);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(CoinVaultApp(subscriptionService: DevSubscriptionService()));
    await tester.pumpAndSettle();

    expect(find.text('Every coin\nhas an origin.'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    await tester.tap(find.text('Create your vault'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Welcome back'), findsOneWidget);

    final guestButton = find.text('Explore as a guest');
    await tester.ensureVisible(guestButton);
    await tester.pumpAndSettle();
    await tester.tap(guestButton);
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('What are you\nholding today?'), findsOneWidget);
    expect(find.text('Collector'), findsOneWidget);
    expect(find.text('VAULT VALUE'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Scanner state-machine tests (use testImageFactory — no camera hardware)
  // ---------------------------------------------------------------------------

  testWidgets('1. Initial state shows Front capture step', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_scanScreen());
    await tester.pump();

    expect(find.text('Scan the front'), findsOneWidget);
    expect(find.byKey(const ValueKey('scan_shutter')), findsOneWidget);
  });

  testWidgets('2. Shutter tap shows review screen for Front', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_scanScreen());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('scan_shutter')));
    await tester.pumpAndSettle();

    expect(find.text('Review front'), findsOneWidget);
    expect(find.text('Retake'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('3. Retake dismisses review and returns to camera', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_scanScreen());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('scan_shutter')));
    await tester.pumpAndSettle();
    expect(find.text('Review front'), findsOneWidget);

    await tester.tap(find.text('Retake').first);
    await tester.pumpAndSettle();

    expect(find.text('Scan the front'), findsOneWidget);
    expect(find.text('Review front'), findsNothing);
  });

  testWidgets('4. Accepting Front advances to Reverse capture', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_scanScreen());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('scan_shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Now scan the reverse'), findsOneWidget);
  });

  testWidgets('5. Accepting Reverse advances to optional Edge step',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_scanScreen());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('scan_shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('scan_shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Optional edge scan'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets(
      '6. Skipping Edge shows recognition unavailable — no fake coin result',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_scanScreen());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('scan_shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('scan_shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Coin recognition is not connected yet.'), findsOneWidget);
    // STRICT: no fake coin result must exist in the UI
    expect(find.text('Coin Identification'), findsNothing);
    expect(find.text('Saint-Gaudens'), findsNothing);
    expect(find.text('New scan'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('7. Capturing Edge also completes to recognition unavailable',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_scanScreen());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('scan_shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('scan_shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('scan_shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Coin recognition is not connected yet.'), findsOneWidget);
  });

  testWidgets('8. Gallery path (Photos button) shows review screen',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_scanScreen());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Tap via key — the text label is below the icon's hit-test area.
    await tester.tap(find.byKey(const ValueKey('scan_gallery')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.text('Review front'), findsOneWidget);
  });

  testWidgets('9. New scan resets state back to Front', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_scanScreen());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('scan_shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scan_shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New scan'));
    await tester.pumpAndSettle();

    expect(find.text('Scan the front'), findsOneWidget);
    expect(find.text('Coin recognition is not connected yet.'), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // Unit-level model tests (no widget pump needed)
  // ---------------------------------------------------------------------------

  test('10. CapturedCoinImage carries real path, dimensions, source and side',
      () async {
    final image =
        await _testImageFactory(CaptureSide.front, CaptureSource.camera);
    expect(image, isNotNull);
    expect(image!.path, isNotEmpty);
    expect(image.width, greaterThan(0));
    expect(image.height, greaterThan(0));
    expect(image.fileSizeBytes, greaterThan(0));
    expect(image.source, CaptureSource.camera);
    expect(image.side, CaptureSide.front);
  });

  test('11. CoinScanInput carries real image references to recognition boundary',
      () async {
    final front =
        await _testImageFactory(CaptureSide.front, CaptureSource.camera);
    final reverse =
        await _testImageFactory(CaptureSide.reverse, CaptureSource.gallery);

    final input = CoinScanInput(frontImage: front!, reverseImage: reverse);
    expect(input.images.length, 2);
    expect(input.frontImage.path, contains('front'));
    expect(input.reverseImage!.source, CaptureSource.gallery);
  });

  test(
      '12. UnavailableRecognitionService — zero candidates, no fake coin',
      () async {
    const service = UnavailableRecognitionService();
    final front =
        await _testImageFactory(CaptureSide.front, CaptureSource.camera);

    final result = await service.recognize(CoinScanInput(frontImage: front!));

    expect(result.status, RecognitionStatus.unavailable);
    expect(result.candidates, isEmpty);
    expect(result.candidates.any((c) => c.providerConfidence != null), isFalse);
  });
}
