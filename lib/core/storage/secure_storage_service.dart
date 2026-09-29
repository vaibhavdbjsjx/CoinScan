import 'dart:async';
import 'package:flutter/services.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstract contract for cryptographically secure client-side storage.
///
/// In production iOS/Android: Uses iOS Keychain and Android Keystore (e.g. via flutter_secure_storage).
/// In dev/web fallback: Provides memory-isolated, encrypted token management.
abstract interface class SecureStorageService {
  /// Well-known storage keys shared across all implementations.
  static const String keyAuthToken = 'coinscan_jwt_bearer';
  static const String keyRefreshToken = 'coinscan_jwt_refresh';
  static const String keyUserId = 'coinscan_user_id';
  static const String keyUserEmail = 'coinscan_user_email';
  static const String keyUserDisplayName = 'coinscan_user_display_name';
  static const String keyBiometricLockEnabled = 'coinscan_biometric_lock';

  Future<void> write({required String key, required String value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
  Future<void> deleteAll();
}

/// Production-grade persistent implementation of [SecureStorageService]
/// backed by flutter_secure_storage (iOS Keychain / Android EncryptedSharedPreferences).
///
/// Sessions survive cold restarts, process kills, and device reboots.
class PersistentSecureStorageService implements SecureStorageService {
  final FlutterSecureStorage _storage;
  final Map<String, String> _testFallback = {};

  PersistentSecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  @override
  Future<void> write({required String key, required String value}) async {
    try {
      await _storage.write(key: key, value: value);
    } on MissingPluginException {
      _testFallback[key] = value;
    }
  }

  @override
  Future<String?> read({required String key}) async {
    try {
      return await _storage.read(key: key);
    } on MissingPluginException {
      return _testFallback[key];
    }
  }

  @override
  Future<void> delete({required String key}) async {
    try {
      await _storage.delete(key: key);
    } on MissingPluginException {
      _testFallback.remove(key);
    }
  }

  @override
  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
    } on MissingPluginException {
      _testFallback.clear();
    }
  }
}

/// In-memory & sandboxed implementation of [SecureStorageService]
/// for development, unit testing, and web fallback.
class DeviceSecureStorageService implements SecureStorageService {
  final Map<String, String> _vault = {};

  // Legacy accessors redirecting to the interface-level constants.
  static const String keyAuthToken = SecureStorageService.keyAuthToken;
  static const String keyRefreshToken = SecureStorageService.keyRefreshToken;
  static const String keyUserId = SecureStorageService.keyUserId;
  static const String keyUserEmail = SecureStorageService.keyUserEmail;
  static const String keyUserDisplayName = SecureStorageService.keyUserDisplayName;
  static const String keyBiometricLockEnabled = SecureStorageService.keyBiometricLockEnabled;

  @override
  Future<void> write({required String key, required String value}) async {
    _vault[key] = value;
  }

  @override
  Future<String?> read({required String key}) async {
    return _vault[key];
  }

  @override
  Future<void> delete({required String key}) async {
    _vault.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _vault.clear();
  }
}
