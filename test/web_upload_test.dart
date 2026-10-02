// Web readiness: browsers have no file system, so a scan must be uploadable
// from the normalized image bytes alone (the "path" is only a blob URL there).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:coinvault_ai/core/recognition/guest_install_id.dart';
import 'package:coinvault_ai/core/recognition/image_preprocessing_service.dart';
import 'package:coinvault_ai/core/recognition/recognition_models.dart';
import 'package:coinvault_ai/core/storage/secure_storage_service.dart';

Uint8List _jpeg() {
  final image = img.Image(width: 400, height: 400);
  for (var x = 0; x < 400; x++) {
    for (var y = 0; y < 400; y++) {
      image.setPixelRgb(x, y, (x * 7) % 256, (y * 5) % 256, 120);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a scan is uploaded from in-memory bytes when there is no file on disk',
    () async {
      final jpeg = _jpeg();
      late http.Request sent;
      final service = HttpRecognitionService(
        config: const RecognitionBackendConfig(baseUrl: 'https://api.test'),
        httpClient: MockClient((req) async {
          sent = req;
          return http.Response('{"status":"unknown","message":"ok"}', 200);
        }),
        installId: GuestInstallId(storage: DeviceSecureStorageService()),
      );

      final result = await service.recognize(
        CoinScanInput(
          frontImage: CapturedCoinImage(
            // What a browser gives you: a blob URL, not a readable file path.
            path:
                'blob:https://coinscan.app/6c1f0b7e-5d0e-4f6b-9d6a-2f8e1c3b4a5d',
            source: CaptureSource.camera,
            side: CaptureSide.front,
            capturedAt: DateTime(2026, 9, 30),
            width: 400,
            height: 400,
            fileSizeBytes: jpeg.length,
            mimeType: 'image/jpeg',
            bytes: jpeg,
          ),
        ),
      );

      expect(result.status, RecognitionStatus.unknown); // the request succeeded
      final body = String.fromCharCodes(sent.bodyBytes);
      expect(body, contains('name="front_image"; filename="front.jpg"'));
      expect(body, isNot(contains('name="reverse_image"')));
      expect(_contains(sent.bodyBytes, jpeg), isTrue);
    },
  );

  test(
    'preprocessing keeps the normalized JPEG in memory for upload',
    () async {
      final dir = await Directory.systemTemp.createTemp('coinscan_web_upload_');
      addTearDown(() => dir.delete(recursive: true));

      final result = await ImagePreprocessingService.instance
          .normalizeAndInspect(
            file: XFile.fromData(
              _jpeg(),
              name: 'coin.jpg',
              mimeType: 'image/jpeg',
            ),
            side: CaptureSide.front,
            source: CaptureSource.gallery,
            overrideTempDir: dir,
          );

      expect(result.image.bytes, isNotNull);
      expect(result.image.bytes, result.normalizedBytes);
      expect(result.image.mimeType, 'image/jpeg');
    },
  );
}

bool _contains(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
