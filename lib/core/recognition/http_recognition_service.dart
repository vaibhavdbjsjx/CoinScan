import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../auth/auth_service.dart';
import '../config/app_config.dart';
import 'package:uuid/uuid.dart';
import 'recognition_models.dart';

/// Configuration for the CoinScan backend recognition service endpoint.
class RecognitionBackendConfig {
  final String baseUrl;
  final Duration timeout;
  final String? apiSecret;
  final String? authToken;

  const RecognitionBackendConfig({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 20),
    this.apiSecret,
    this.authToken,
  });

  /// Factory resolving the base URL from [AppConfig].
  /// Falls back to platform-aware localhost if AppConfig is not initialized.
  factory RecognitionBackendConfig.defaultConfig({String? authToken}) {
    if (AppConfig.isInitialized) {
      return RecognitionBackendConfig(
        baseUrl: AppConfig.instance.backendUrl,
        // Static API keys are a development convenience only; production builds
        // authenticate exclusively with the user's Supabase session token.
        apiSecret: AppConfig.instance.isProduction ? null : AppConfig.instance.apiKey,
        authToken: authToken,
      );
    }

    // Fallback for tests and legacy usage
    String url = 'http://127.0.0.1:8080';
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      url = 'http://10.0.2.2:8080';
    }

    return RecognitionBackendConfig(baseUrl: url, authToken: authToken);
  }
}

/// Real HTTP client implementation of [RecognitionService] that communicates
/// with the CoinScan backend service via multipart/form-data.
class HttpRecognitionService implements RecognitionService {
  final RecognitionBackendConfig config;
  final http.Client _httpClient;

  HttpRecognitionService({
    RecognitionBackendConfig? config,
    http.Client? httpClient,
  })  : config = config ?? RecognitionBackendConfig.defaultConfig(),
        _httpClient = httpClient ?? http.Client();

  @override
  Future<RecognitionResult> recognize(CoinScanInput input) async {
    final uri = Uri.parse('${config.baseUrl}/v1/recognition');

    try {
      final request = http.MultipartRequest('POST', uri);

      // Add Headers
      if (config.apiSecret != null) {
        request.headers['X-API-Secret'] = config.apiSecret!;
      }

      request.headers['X-Request-ID'] = const Uuid().v4();

      final token = config.authToken ?? AuthService.instance.currentState.token;
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // Add Form Fields
      request.fields['preferred_currency'] = input.preferredCurrency ?? 'USD';
      request.fields['locale'] = input.locale ?? 'en-US';

      // 1. Add Front Image
      final front = input.frontImage;
      if (front.path.isNotEmpty) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'front_image',
            front.path,
            filename: 'front.jpg',
          ),
        );
      }

      // 2. Add Optional Reverse Image
      final reverse = input.reverseImage;
      if (reverse != null && reverse.path.isNotEmpty) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'reverse_image',
            reverse.path,
            filename: 'reverse.jpg',
          ),
        );
      }

      // 3. Add Optional Edge Image
      final edge = input.edgeImage;
      if (edge != null && edge.path.isNotEmpty) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'edge_image',
            edge.path,
            filename: 'edge.jpg',
          ),
        );
      }

      // Send Request with Timeout
      final streamedResponse = await _httpClient
          .send(request)
          .timeout(config.timeout);

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final Map<String, dynamic> json =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return RecognitionResult.fromJson(json);
      } else if (response.statusCode == 429) {
        String quotaMessage = 'Too many scan requests. Please wait a moment before trying again.';
        try {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          if (decoded is Map && decoded['detail'] != null) {
            quotaMessage = decoded['detail'].toString();
          }
        } catch (_) {}
        return RecognitionResult(
          status: RecognitionStatus.error,
          message: quotaMessage,
          warnings: [quotaMessage],
        );
      } else if (response.statusCode == 413) {
        return const RecognitionResult(
          status: RecognitionStatus.insufficientQuality,
          message: 'The uploaded image file is too large.',
          warnings: ['Maximum image size is 20MB. Please select a smaller photo.'],
        );
      } else {
        return RecognitionResult(
          status: RecognitionStatus.error,
          message: 'Server error (${response.statusCode}). Please retry your scan.',
          warnings: ['Recognition backend returned an unexpected response code.'],
        );
      }
    } on TimeoutException {
      return const RecognitionResult(
        status: RecognitionStatus.error,
        message: 'The recognition request timed out.',
        warnings: ['Check your internet connection and retry.'],
      );
    } on http.ClientException catch (e) {
      return RecognitionResult(
        status: RecognitionStatus.unavailable,
        message: 'Could not connect to the CoinScan recognition backend.',
        warnings: [
          'Backend is currently offline or unreachable (${e.message}).',
          'Make sure the CoinScan backend server is running.',
        ],
      );
    } catch (e) {
      return RecognitionResult(
        status: RecognitionStatus.error,
        message: 'An unexpected error occurred during coin recognition.',
        warnings: [e.toString()],
      );
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
