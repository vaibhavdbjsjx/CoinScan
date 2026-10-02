import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../network/api_client.dart';
import '../storage/secure_storage_service.dart';

/// Current mandatory legal document versions.
/// Incrementing these triggers mandatory re-consent before entering authenticated state.
class LegalVersions {
  const LegalVersions._();

  static const String currentTermsVersion = '1.0.0';
  static const String currentPrivacyVersion = '1.0.0';
}

/// Immutable record of a user's legal acceptance.
class LegalConsentRecord {
  final String userId;
  final String termsVersion;
  final DateTime termsAcceptedAt;
  final String privacyVersion;
  final DateTime privacyAcceptedAt;

  const LegalConsentRecord({
    required this.userId,
    required this.termsVersion,
    required this.termsAcceptedAt,
    required this.privacyVersion,
    required this.privacyAcceptedAt,
  });

  /// Whether this consent satisfies the current mandatory legal versions.
  bool get isCurrent =>
      termsVersion == LegalVersions.currentTermsVersion &&
      privacyVersion == LegalVersions.currentPrivacyVersion;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'termsVersion': termsVersion,
    'termsAcceptedAt': termsAcceptedAt.toIso8601String(),
    'privacyVersion': privacyVersion,
    'privacyAcceptedAt': privacyAcceptedAt.toIso8601String(),
  };

  factory LegalConsentRecord.fromJson(Map<String, dynamic> json) {
    return LegalConsentRecord(
      userId: json['userId'] as String,
      termsVersion: json['termsVersion'] as String? ?? '',
      termsAcceptedAt: DateTime.parse(
        json['termsAcceptedAt'] as String? ?? DateTime.now().toIso8601String(),
      ),
      privacyVersion: json['privacyVersion'] as String? ?? '',
      privacyAcceptedAt: DateTime.parse(
        json['privacyAcceptedAt'] as String? ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}

/// Service managing client-side and backend legal consent records.
/// Consent is strictly isolated by user ID so Account A cannot leak consent to Account B.
class LegalConsentService {
  static final LegalConsentService instance = LegalConsentService();

  final SecureStorageService _secureStorage;
  final ApiClient? _explicitApiClient;

  LegalConsentService({
    SecureStorageService? secureStorage,
    ApiClient? apiClient,
  })  : _secureStorage = secureStorage ?? PersistentSecureStorageService(),
        _explicitApiClient = apiClient;

  ApiClient get _apiClient => _explicitApiClient ?? ApiClient.instance;

  static String _storageKey(String userId) => 'legal_consent_$userId';

  /// Retrieves the consent record for a specific user ID.
  Future<LegalConsentRecord?> getConsent(String userId) async {
    if (userId.isEmpty || userId == 'guest_user') return null;
    final raw = await _secureStorage.read(key: _storageKey(userId));
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return LegalConsentRecord.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// Checks whether a specific user has accepted the CURRENT Terms and Privacy Policy.
  Future<bool> hasAcceptedCurrentTerms(String userId) async {
    final record = await getConsent(userId);
    if (record == null) return false;
    return record.isCurrent;
  }

  /// Records fresh consent for a user locally and transmits it to backend.
  ///
  /// [accessToken] should be passed while a sign-in is still completing, so
  /// the backend call is authenticated with the new session even before the
  /// app-wide auth state has been updated.
  Future<LegalConsentRecord> recordConsent({
    required String userId,
    String termsVersion = LegalVersions.currentTermsVersion,
    String privacyVersion = LegalVersions.currentPrivacyVersion,
    String? accessToken,
  }) async {
    final now = DateTime.now().toUtc();
    final record = LegalConsentRecord(
      userId: userId,
      termsVersion: termsVersion,
      termsAcceptedAt: now,
      privacyVersion: privacyVersion,
      privacyAcceptedAt: now,
    );

    await _secureStorage.write(
      key: _storageKey(userId),
      value: jsonEncode(record.toJson()),
    );

    if (userId.isNotEmpty && userId != 'guest_user') {
      try {
        await _apiClient.post(
          '/v1/account/legal/consent',
          body: {
            'terms_version': termsVersion,
            'privacy_version': privacyVersion,
            'accepted_at': now.millisecondsSinceEpoch / 1000.0,
          },
          headers: accessToken != null
              ? {'Authorization': 'Bearer $accessToken'}
              : null,
        );
      } catch (e) {
        debugPrint('Warning: Could not sync legal consent to backend: $e');
        if (AppConfig.isInitialized && AppConfig.instance.isProduction) {
          rethrow;
        }
      }
    }

    return record;
  }

  /// Syncs legal consent record with backend GET /v1/account/legal/consent.
  Future<LegalConsentRecord?> syncConsentWithBackend(
    String userId, {
    String? accessToken,
  }) async {
    if (userId.isEmpty || userId == 'guest_user') return null;

    try {
      final res = await _apiClient.get(
        '/v1/account/legal/consent',
        headers: accessToken != null
            ? {'Authorization': 'Bearer $accessToken'}
            : null,
      );
      if (res is Map<String, dynamic>) {
        final termsVer = res['terms_version']?.toString() ?? '';
        // "not_accepted" responses carry empty versions; nothing to store.
        if (termsVer.isEmpty) return null;
        final privVer = res['privacy_version']?.toString() ?? '';
        final acceptedAt = res['accepted_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                ((res['accepted_at'] as num) * 1000).toInt(),
                isUtc: true,
              )
            : DateTime.now().toUtc();

        final record = LegalConsentRecord(
          userId: userId,
          termsVersion: termsVer,
          termsAcceptedAt: acceptedAt,
          privacyVersion: privVer,
          privacyAcceptedAt: acceptedAt,
        );

        await _secureStorage.write(
          key: _storageKey(userId),
          value: jsonEncode(record.toJson()),
        );
        return record;
      }
    } catch (e) {
      debugPrint('Could not sync consent from backend: $e');
    }
    return null;
  }

  /// Clears consent for a specific user (e.g. on account deletion).
  Future<void> clearConsent(String userId) async {
    await _secureStorage.delete(key: _storageKey(userId));
  }
}
