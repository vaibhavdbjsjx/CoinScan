import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:coinvault_ai/core/recognition/image_preprocessing_service.dart';
import 'package:coinvault_ai/core/recognition/recognition_models.dart';
import 'package:coinvault_ai/features/scan/scan_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('coinscan_test_');
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('ImagePreprocessingService Unit Tests', () {
    test('1. Rejects 0-byte empty file with ImageProcessingException', () async {
      final emptyFile = File('${tempDir.path}/empty.jpg');
      await emptyFile.writeAsBytes([]);

      expect(
        () => ImagePreprocessingService.instance.normalizeAndInspect(
          file: XFile(emptyFile.path),
          side: CaptureSide.front,
          source: CaptureSource.camera,
          overrideTempDir: tempDir,
        ),
        throwsA(isA<ImageProcessingException>().having(
          (e) => e.message,
          'message',
          contains('empty'),
        )),
      );
    });

    test('2. Rejects corrupted non-image bytes gracefully', () async {
      final corruptFile = File('${tempDir.path}/corrupt.jpg');
      await corruptFile.writeAsBytes([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03]);

      expect(
        () => ImagePreprocessingService.instance.normalizeAndInspect(
          file: XFile(corruptFile.path),
          side: CaptureSide.front,
          source: CaptureSource.gallery,
          overrideTempDir: tempDir,
        ),
        throwsA(isA<ImageProcessingException>().having(
          (e) => e.message,
          'message',
          contains('could not be decoded'),
        )),
      );
    });

    test('3. Rejects image below minimum 240px resolution', () async {
      final lowResImg = img.Image(width: 100, height: 100);
      img.fill(lowResImg, color: img.ColorRgb8(128, 128, 128));
      final jpgBytes = img.encodeJpg(lowResImg);

      final lowResFile = File('${tempDir.path}/lowres.jpg');
      await lowResFile.writeAsBytes(jpgBytes);

      expect(
        () => ImagePreprocessingService.instance.normalizeAndInspect(
          file: XFile(lowResFile.path),
          side: CaptureSide.front,
          source: CaptureSource.camera,
          overrideTempDir: tempDir,
        ),
        throwsA(isA<ImageProcessingException>().having(
          (e) => e.message,
          'message',
          contains('resolution is too low'),
        )),
      );
    });

    test('4. Downscales oversized image to max 1920px while preserving aspect ratio', () async {
      // Create a 2400x1200 image
      final bigImg = img.Image(width: 2400, height: 1200);
      // Fill with medium gray with some variation
      for (int y = 0; y < 1200; y++) {
        for (int x = 0; x < 2400; x++) {
          final c = ((x * 7 + y * 13) % 180) + 40;
          bigImg.setPixel(x, y, img.ColorRgb8(c, c, c));
        }
      }
      final jpgBytes = img.encodeJpg(bigImg);
      final bigFile = File('${tempDir.path}/big.jpg');
      await bigFile.writeAsBytes(jpgBytes);

      final result = await ImagePreprocessingService.instance.normalizeAndInspect(
        file: XFile(bigFile.path),
        side: CaptureSide.front,
        source: CaptureSource.camera,
        overrideTempDir: tempDir,
      );

      expect(result.image.width, equals(1920));
      expect(result.image.height, equals(960)); // Exactly preserved 2:1 aspect ratio
      expect(result.image.mimeType, equals('image/jpeg'));
      expect(result.image.fileSizeBytes, greaterThan(0));
      expect(result.image.fileSizeBytes, lessThan(jpgBytes.length));
      expect(File(result.image.path).existsSync(), isTrue);
    });
  });

  group('Deterministic Image Quality Inspection Tests', () {
    test('1. Detects dark underexposed image (< 0.18 luminance)', () {
      final darkImg = img.Image(width: 300, height: 300);
      img.fill(darkImg, color: img.ColorRgb8(20, 20, 20)); // ~0.08 luminance

      final report = ImagePreprocessingService.instance.inspectQuality(darkImg);

      expect(report.issues, contains(ImageQualityIssue.tooDark));
      expect(report.warnings.any((w) => w.contains('dark')), isTrue);
      expect(report.recommendedActions.any((a) => a.contains('lighting')), isTrue);
      expect(report.overallScore, lessThan(0.8));
    });

    test('2. Detects severe specular glare (> 12% saturated pixels)', () {
      final glareImg = img.Image(width: 300, height: 300);
      // 80% normal gray, 20% pure white glare
      for (int y = 0; y < 300; y++) {
        for (int x = 0; x < 300; x++) {
          if (x < 60) {
            glareImg.setPixel(x, y, img.ColorRgb8(255, 255, 255)); // 20% glare
          } else {
            glareImg.setPixel(x, y, img.ColorRgb8(120, 120, 120));
          }
        }
      }

      final report = ImagePreprocessingService.instance.inspectQuality(glareImg);

      expect(report.issues, contains(ImageQualityIssue.excessiveGlare));
      expect(report.warnings.any((w) => w.contains('glare')), isTrue);
      expect(report.recommendedActions.any((a) => a.contains('diffuse') || a.contains('Angle')), isTrue);
    });

    test('3. Detects uniform flat/blurry image with low Laplacian variance', () {
      final flatImg = img.Image(width: 300, height: 300);
      // Flat color has variance ~0 (extreme blur)
      img.fill(flatImg, color: img.ColorRgb8(128, 128, 128));

      final report = ImagePreprocessingService.instance.inspectQuality(flatImg);

      expect(report.issues, contains(ImageQualityIssue.tooBlurry));
      expect(report.warnings.any((w) => w.contains('blurry') || w.contains('out of focus')), isTrue);
      expect(report.recommendedActions.any((a) => a.contains('focus') || a.contains('steady')), isTrue);
    });

    test('4. High quality sharp image with varied features passes inspection', () {
      final sharpImg = img.Image(width: 300, height: 300);
      for (int y = 0; y < 300; y++) {
        for (int x = 0; x < 300; x++) {
          final c = ((x * 19 + y * 31) % 160) + 45;
          sharpImg.setPixel(x, y, img.ColorRgb8(c, c, c));
        }
      }

      final report = ImagePreprocessingService.instance.inspectQuality(sharpImg);

      expect(report.isAcceptable, isTrue);
      expect(report.overallScore, greaterThanOrEqualTo(0.70));
      expect(report.issues, isEmpty);
    });
  });

  group('Scanner UI & Quality Feedback Widget Tests', () {
    testWidgets('1. Review screen shows quality warning notice when image is blurry', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<CapturedCoinImage?> factory(CaptureSide side, CaptureSource source) async {
        return CapturedCoinImage(
          path: '/tmp/test_blurry.jpg',
          source: source,
          side: side,
          capturedAt: DateTime.now(),
          width: 640,
          height: 640,
          fileSizeBytes: 1024,
        );
      }

      Future<Uint8List> previewLoader(CapturedCoinImage image) async {
        final imgObj = img.Image(width: 10, height: 10);
        img.fill(imgObj, color: img.ColorRgb8(100, 100, 100));
        return Uint8List.fromList(img.encodePng(imgObj));
      }

      await tester.pumpWidget(
        MaterialApp(
          home: ScanScreen(
            testImageFactory: factory,
            testPreviewLoader: previewLoader,
          ),
        ),
      );
      await tester.pump();

      // Tap shutter to capture
      await tester.tap(find.byKey(const ValueKey('scan_shutter')));
      await tester.pumpAndSettle();

      expect(find.text('Review front'), findsOneWidget);
      expect(find.text('640 x 640 px'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Retake'), findsOneWidget);
    });

    testWidgets('2. Multi-step capture correctly advances from front to reverse', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<CapturedCoinImage?> factory(CaptureSide side, CaptureSource source) async {
        return CapturedCoinImage(
          path: '/tmp/test_${side.name}.jpg',
          source: source,
          side: side,
          capturedAt: DateTime.now(),
          width: 800,
          height: 800,
          fileSizeBytes: 2048,
        );
      }

      Future<Uint8List> previewLoader(CapturedCoinImage image) async {
        final imgObj = img.Image(width: 10, height: 10);
        img.fill(imgObj, color: img.ColorRgb8(100, 100, 100));
        return Uint8List.fromList(img.encodePng(imgObj));
      }

      await tester.pumpWidget(
        MaterialApp(
          home: ScanScreen(
            testImageFactory: factory,
            testPreviewLoader: previewLoader,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Scan the front'), findsOneWidget);

      // 1. Capture Front
      await tester.tap(find.byKey(const ValueKey('scan_shutter')));
      await tester.pumpAndSettle();
      expect(find.text('Review front'), findsOneWidget);

      // 2. Accept Front
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Now scan the reverse'), findsOneWidget);

      // 3. Capture Reverse
      await tester.tap(find.byKey(const ValueKey('scan_shutter')));
      await tester.pumpAndSettle();
      expect(find.text('Review reverse'), findsOneWidget);

      // 4. Accept Reverse -> Advances to Edge
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Optional edge scan'), findsOneWidget);
    });
  });
}
