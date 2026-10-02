import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:coinvault_ai/core/recognition/recognition_models.dart';
import 'package:coinvault_ai/features/scan/scan_screen.dart';

void main() {
  final testDateTime = DateTime(2026, 8, 26, 12, 0, 0);

  CapturedCoinImage makeTestImage({
    String path = 'test.jpg',
    CaptureSide side = CaptureSide.front,
    CaptureSource source = CaptureSource.camera,
  }) {
    return CapturedCoinImage(
      path: path,
      side: side,
      source: source,
      capturedAt: testDateTime,
      width: 500,
      height: 500,
      fileSizeBytes: 245000,
    );
  }

  group('HttpRecognitionService Unit Tests', () {
    test('1. Deserializes successful 200 OK JSON recognition response', () async {
      final mockResponse = {
        'status': 'identified',
        'message': 'High certainty match for 1 Dollar Morgan Dollar.',
        'candidates': [
          {
            'coinId': 'numista_1492',
            'identity': {
              'country': 'United States',
              'denomination': '1 Dollar',
              'year': 1882,
              'mint': 'CC',
              'composition': '90% Silver, 10% Copper',
              'weightG': 26.73,
              'diameterMm': 38.1,
              'kmNumber': 'KM# 110',
              'numistaId': 1492,
            },
            'providerName': 'CoinScan Hybrid Engine',
            'confidence': {
              'level': 'high',
              'overallScore': 0.94,
              'visualScore': 0.95,
              'ocrScore': 0.92,
              'metadataScore': 0.96,
              'explanation': 'Obverse and reverse dies confirmed Carson City strike.',
            },
            'evidence': [
              {
                'type': 'visualSimilarity',
                'label': 'Visual Motif Match',
                'detail': 'Liberty head facing left with Phrygian cap.',
                'strength': 'strong',
                'score': 0.95,
              },
              {
                'type': 'year',
                'label': 'Date 1882',
                'detail': 'Date 1882 verified against mintage records.',
                'strength': 'strong',
                'score': 0.92,
              }
            ],
            'rank': 1,
          }
        ],
        'qualityReport': {
          'isAcceptable': true,
          'overallScore': 0.95,
          'issues': [],
          'warnings': [],
          'recommendedActions': [],
        },
        'processingMetadata': {'latency_ms': 420},
        'warnings': [],
      };

      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/recognition');
        return http.Response(jsonEncode(mockResponse), 200, headers: {
          'content-type': 'application/json',
        });
      });

      final service = HttpRecognitionService(
        config: const RecognitionBackendConfig(baseUrl: 'http://127.0.0.1:8080'),
        httpClient: mockClient,
      );

      final input = CoinScanInput(
        frontImage: makeTestImage(path: ''),
      );

      final result = await service.recognize(input);
      expect(result.status, RecognitionStatus.identified);
      expect(result.candidates.length, 1);
      expect(result.primaryCandidate!.identity.country, 'United States');
      expect(result.primaryCandidate!.identity.numistaId, 1492);
      expect(result.primaryCandidate!.confidence!.overallScore, 0.94);
    });

    test('2. Handles HTTP 429 Rate Limit error gracefully', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Too many requests', 429);
      });

      final service = HttpRecognitionService(
        config: const RecognitionBackendConfig(baseUrl: 'http://127.0.0.1:8080'),
        httpClient: mockClient,
      );

      final result = await service.recognize(
        CoinScanInput(
          frontImage: makeTestImage(path: ''),
        ),
      );

      expect(result.status, RecognitionStatus.error);
      expect(result.message, contains('Too many scan requests'));
    });

    test('3. Handles HTTP 413 Payload Too Large gracefully', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Payload too large', 413);
      });

      final service = HttpRecognitionService(
        config: const RecognitionBackendConfig(baseUrl: 'http://127.0.0.1:8080'),
        httpClient: mockClient,
      );

      final result = await service.recognize(
        CoinScanInput(
          frontImage: makeTestImage(path: ''),
        ),
      );

      expect(result.status, RecognitionStatus.insufficientQuality);
      expect(result.message, contains('too large'));
    });
  });

  group('ScanScreen Recognition Result UI Widget Tests', () {
    testWidgets('4. Renders identified coin details and Numista N# attribution badge', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const identifiedResult = RecognitionResult(
        status: RecognitionStatus.identified,
        message: 'High certainty match.',
        candidates: [
          RecognitionCandidate(
            coinId: 'numista_1492',
            providerName: 'CoinScan Hybrid Engine',
            identity: CoinIdentity(
              country: 'United States',
              denomination: '1 Dollar',
              year: 1882,
              mint: 'CC',
              composition: '90% Silver',
              numistaId: 1492,
            ),
            confidence: RecognitionConfidence(
              level: ConfidenceLevel.high,
              overallScore: 0.94,
              visualScore: 0.95,
              ocrScore: 0.92,
              metadataScore: 0.96,
              explanation: 'Carson City die strike verified.',
            ),
            evidence: [
              RecognitionEvidence(
                type: RecognitionEvidenceType.visualSimilarity,
                label: 'Visual Motif Match',
                detail: 'Liberty head verified.',
              ),
            ],
          ),
        ],
      );

      // Create a mock recognition service returning identifiedResult
      final service = _MockService(identifiedResult);

      await tester.pumpWidget(
        MaterialApp(
          home: ScanScreen(
            recognitionService: service,
            testImageFactory: (side, source) async => makeTestImage(
              side: side,
              source: source,
            ),
            testPreviewLoader: (img) async => Uint8List(0),
          ),
        ),
      );
      await tester.pump();

      // Capture front
      await tester.tap(find.byKey(const ValueKey('scan_shutter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Capture reverse
      await tester.tap(find.byKey(const ValueKey('scan_shutter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Skip edge to trigger analysis
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      // Verify UI shows Identified badge, Coin Title, Numista N# badge and the
      // identification confidence level. The uncalibrated score is deliberately
      // not shown as a percentage, and authenticity is reported as not assessed.
      expect(find.text('Identified'), findsOneWidget);
      expect(find.text('1882 United States 1 Dollar'), findsOneWidget);
      expect(find.textContaining('Numista N# 1492'), findsAtLeastNWidgets(1));
      expect(find.text('High identification confidence'), findsOneWidget);
      expect(find.textContaining('94%'), findsNothing);
      expect(find.textContaining('it cannot authenticate coins'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('What supports this identification'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('What supports this identification'), findsOneWidget);
    });

    testWidgets('5. Renders poor quality diagnostics and recapture checklist', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const qualityResult = RecognitionResult(
        status: RecognitionStatus.insufficientQuality,
        message: 'The front image is too blurry.',
        qualityReport: ImageQualityReport(
          isAcceptable: false,
          overallScore: 0.25,
          issues: [ImageQualityIssue.tooBlurry],
          recommendedActions: ['Hold camera steady and tap to focus.'],
        ),
      );

      final service = _MockService(qualityResult);

      await tester.pumpWidget(
        MaterialApp(
          home: ScanScreen(
            recognitionService: service,
            testImageFactory: (side, source) async => makeTestImage(
              side: side,
              source: source,
            ),
            testPreviewLoader: (img) async => Uint8List(0),
          ),
        ),
      );
      await tester.pump();

      // Capture front and skip to analysis
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

      expect(find.text('Poor Quality'), findsOneWidget);
      expect(find.text('The front image is too blurry.'), findsOneWidget);
      expect(find.text('Hold camera steady and tap to focus.'), findsOneWidget);
    });
  });
}

class _MockService implements RecognitionService {
  final RecognitionResult result;
  _MockService(this.result);

  @override
  Future<RecognitionResult> recognize(CoinScanInput input) async => result;
}
