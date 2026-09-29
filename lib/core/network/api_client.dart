import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';

/// Structured API exception for CoinScan backend interactions.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final dynamic responseBody;
  final String? requestId;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isRateLimited => statusCode == 429;
  bool get isServerError => statusCode >= 500;

  const ApiException({
    required this.statusCode,
    required this.message,
    this.responseBody,
    this.requestId,
  });

  @override
  String toString() =>
      'ApiException(status: $statusCode, message: $message, requestId: $requestId)';
}

/// Token provider callback for retrieving current valid Supabase session tokens.
typedef TokenProvider = Future<String?> Function();

/// Token refresher callback for refreshing an expired Supabase session.
typedef TokenRefresher = Future<String?> Function();

/// Session expiration callback when credentials fail to refresh.
typedef SessionExpiredCallback = Future<void> Function();

/// Unified HTTP client abstraction for communicating with the CoinScan backend.
///
/// Features:
/// 1. Dynamic base URL resolution from [AppConfig].
/// 2. Automatic bearer token attachment from Supabase Auth session.
/// 3. Request correlation tracing via `X-Request-ID`.
/// 4. Sanitized logging (never logs tokens, passwords, or keys).
/// 5. Clean 401 / 403 / 429 / 500 handling with typed exceptions and 401 token refresh retry.
class ApiClient {
  static ApiClient? _instance;

  final String? _explicitBaseUrl;
  final http.Client _httpClient;
  final Duration timeout;
  final TokenProvider? tokenProvider;
  final TokenRefresher? tokenRefresher;
  final SessionExpiredCallback? onSessionExpired;

  ApiClient({
    String? baseUrl,
    http.Client? httpClient,
    Duration? timeout,
    this.tokenProvider,
    this.tokenRefresher,
    this.onSessionExpired,
  })  : _explicitBaseUrl = baseUrl,
        _httpClient = httpClient ?? http.Client(),
        timeout = timeout ?? const Duration(seconds: 20);

  /// Singleton access using default environment configuration.
  static ApiClient get instance {
    _instance ??= ApiClient();
    return _instance!;
  }

  /// Configures the shared ApiClient singleton with specific dependencies.
  static void configure({
    String? baseUrl,
    http.Client? httpClient,
    Duration? timeout,
    TokenProvider? tokenProvider,
    TokenRefresher? tokenRefresher,
    SessionExpiredCallback? onSessionExpired,
  }) {
    _instance = ApiClient(
      baseUrl: baseUrl,
      httpClient: httpClient,
      timeout: timeout,
      tokenProvider: tokenProvider,
      tokenRefresher: tokenRefresher,
      onSessionExpired: onSessionExpired,
    );
  }

  @visibleForTesting
  static void setMockInstance(ApiClient mock) {
    _instance = mock;
  }

  @visibleForTesting
  static void reset() {
    _instance = null;
  }

  String get baseUrl {
    final explicit = _explicitBaseUrl;
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    if (AppConfig.isInitialized) {
      return AppConfig.instance.backendUrl;
    }
    // Safe development fallback
    return 'http://127.0.0.1:8080';
  }

  Uri _buildUri(String path, [Map<String, dynamic>? queryParameters]) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final fullUrl = '$baseUrl$cleanPath';
    final uri = Uri.parse(fullUrl);

    if (queryParameters != null && queryParameters.isNotEmpty) {
      final stringParams = queryParameters.map(
        (key, value) => MapEntry(key, value.toString()),
      );
      return uri.replace(queryParameters: stringParams);
    }
    return uri;
  }

  Future<Map<String, String>> _buildHeaders({
    Map<String, String>? additionalHeaders,
    bool isJson = true,
    String? explicitToken,
  }) async {
    final headers = <String, String>{};

    if (isJson) {
      headers['Content-Type'] = 'application/json';
      headers['Accept'] = 'application/json';
    }

    // Attach unique request tracing ID
    headers['X-Request-ID'] = const Uuid().v4();

    // Attach API Key if configured in AppConfig. Never in production builds:
    // anything compiled into the app binary can be extracted, and the backend
    // refuses static keys in production anyway.
    if (AppConfig.isInitialized &&
        !AppConfig.instance.isProduction &&
        AppConfig.instance.apiKey != null) {
      final apiKey = AppConfig.instance.apiKey;
      if (apiKey != null) {
        headers['X-API-Secret'] = apiKey;
      }
    }

    // Retrieve and attach current Supabase Auth bearer token
    String? token = explicitToken;
    if (token == null && tokenProvider != null) {
      token = await tokenProvider!();
    }
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    if (additionalHeaders != null) {
      headers.addAll(additionalHeaders);
    }

    return headers;
  }

  Future<String?>? _inFlightRefresh;

  Future<String?> _synchronizedTokenRefresh() async {
    if (_inFlightRefresh != null) {
      return await _inFlightRefresh!;
    }
    if (tokenRefresher == null) return null;

    final refreshFuture = tokenRefresher!();
    _inFlightRefresh = refreshFuture;
    try {
      final token = await refreshFuture;
      return token;
    } finally {
      _inFlightRefresh = null;
    }
  }

  @visibleForTesting
  Future<String?> synchronizedTokenRefresh() => _synchronizedTokenRefresh();

  Future<dynamic> _sendWithRetry(
    Future<http.Response> Function(Map<String, String> headers) requestFn, {
    Map<String, String>? additionalHeaders,
    bool isJson = true,
  }) async {
    final initialHeaders = await _buildHeaders(
      additionalHeaders: additionalHeaders,
      isJson: isJson,
    );

    try {
      final response = await requestFn(initialHeaders).timeout(timeout);

      // Handle 401 Unauthorized: Attempt single synchronized token refresh across concurrent requests
      if (response.statusCode == 401 && tokenRefresher != null) {
        final refreshedToken = await _synchronizedTokenRefresh();
        if (refreshedToken != null && refreshedToken.isNotEmpty) {
          final retryHeaders = await _buildHeaders(
            additionalHeaders: additionalHeaders,
            isJson: isJson,
            explicitToken: refreshedToken,
          );
          final retryResponse = await requestFn(retryHeaders).timeout(timeout);
          if (retryResponse.statusCode == 401) {
            await onSessionExpired?.call();
          }
          return _processResponse(retryResponse);
        } else {
          await onSessionExpired?.call();
        }
      }

      return _processResponse(response);
    } on TimeoutException {
      throw const ApiException(
        statusCode: 408,
        message: 'Request timed out. Please check your network connection.',
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        statusCode: 0,
        message: 'Network error communicating with backend: $e',
      );
    }
  }

  /// Sends a GET request.
  Future<dynamic> get(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    final uri = _buildUri(path, queryParameters);
    return _sendWithRetry(
      (h) => _httpClient.get(uri, headers: h),
      additionalHeaders: headers,
    );
  }

  /// Calls GET /v1/account/export to obtain the machine-readable GDPR data archive.
  Future<Map<String, dynamic>?> exportAccountData() async {
    final res = await get('/v1/account/export');
    if (res is Map<String, dynamic>) {
      return res;
    }
    return null;
  }

  /// Sends a POST request with JSON body.
  Future<dynamic> post(
    String path, {
    dynamic body,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    final uri = _buildUri(path, queryParameters);
    final encodedBody = body != null ? jsonEncode(body) : null;
    return _sendWithRetry(
      (h) => _httpClient.post(uri, headers: h, body: encodedBody),
      additionalHeaders: headers,
    );
  }

  /// Sends a PUT request with JSON body.
  Future<dynamic> put(
    String path, {
    dynamic body,
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(path);
    final encodedBody = body != null ? jsonEncode(body) : null;
    return _sendWithRetry(
      (h) => _httpClient.put(uri, headers: h, body: encodedBody),
      additionalHeaders: headers,
    );
  }

  /// Sends a DELETE request with optional JSON body.
  Future<dynamic> delete(
    String path, {
    dynamic body,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    final uri = _buildUri(path, queryParameters);
    final encodedBody = body != null ? jsonEncode(body) : null;
    return _sendWithRetry(
      (h) => _httpClient.delete(uri, headers: h, body: encodedBody),
      additionalHeaders: headers,
    );
  }

  /// Parses HTTP response, validating status code and parsing JSON payload.
  dynamic _processResponse(http.Response response) {
    final statusCode = response.statusCode;
    final requestId = response.headers['x-request-id'];

    dynamic parsedBody;
    try {
      if (response.body.isNotEmpty) {
        parsedBody = jsonDecode(response.body);
      }
    } catch (_) {
      parsedBody = response.body;
    }

    if (statusCode >= 200 && statusCode < 300) {
      return parsedBody;
    }

    String errorMessage = 'Request failed with status $statusCode';
    if (parsedBody is Map && parsedBody.containsKey('detail')) {
      final detail = parsedBody['detail'];
      if (detail is Map && detail.containsKey('message')) {
        errorMessage = detail['message'].toString();
      } else {
        errorMessage = detail.toString();
      }
    } else if (parsedBody is Map && parsedBody.containsKey('message')) {
      errorMessage = parsedBody['message'].toString();
    } else if (statusCode == 401) {
      errorMessage = 'Session expired or invalid. Please sign in again.';
    } else if (statusCode == 403) {
      errorMessage = 'Access denied. You do not have permission for this resource.';
    } else if (statusCode == 429) {
      errorMessage = 'Scan quota or rate limit exceeded.';
    } else if (statusCode >= 500) {
      errorMessage = 'CoinScan server error ($statusCode). Please retry shortly.';
    }

    throw ApiException(
      statusCode: statusCode,
      message: errorMessage,
      responseBody: parsedBody,
      requestId: requestId,
    );
  }

  void dispose() {
    _httpClient.close();
  }
}
