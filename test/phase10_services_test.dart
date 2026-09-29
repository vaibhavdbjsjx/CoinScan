import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:coinvault_ai/core/storage/secure_storage_service.dart';
import 'package:coinvault_ai/core/storage/collection_storage_service.dart';
import 'package:coinvault_ai/core/auth/auth_service.dart';
import 'package:coinvault_ai/core/storage/scan_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 10: Secure Storage & Keychain Tests', () {
    late SecureStorageService storage;

    setUp(() {
      storage = DeviceSecureStorageService();
    });

    test('1. Writes, reads, and deletes secure credentials', () async {
      await storage.write(key: 'test_token', value: 'secret_jwt_xyz');
      expect(await storage.read(key: 'test_token'), equals('secret_jwt_xyz'));

      await storage.delete(key: 'test_token');
      expect(await storage.read(key: 'test_token'), isNull);
    });

    test('2. DeleteAll purges all saved tokens', () async {
      await storage.write(key: 'k1', value: 'v1');
      await storage.write(key: 'k2', value: 'v2');
      await storage.deleteAll();

      expect(await storage.read(key: 'k1'), isNull);
      expect(await storage.read(key: 'k2'), isNull);
    });
  });

  group('Phase 10: Collection Storage & Vault Tests', () {
    late CollectionStorageService collectionService;

    setUp(() {
      collectionService = CollectionStorageService();
    });

    test('3. Saves and retrieves vault items with valuation snapshots', () async {
      final item = VaultCoinItem(
        id: 'coin_test_1',
        coinName: '1882-CC Morgan Dollar',
        country: 'United States',
        denomination: '\$1',
        year: 1882,
        grade: 'MS65',
        purchasePrice: 650.0,
        initialValuationSnapshot: 650.0,
        currentEstimatedValue: 720.0,
        dateAdded: DateTime(2026, 8, 29),
      );

      await collectionService.saveItem(item);
      final list = await collectionService.loadCollection();
      expect(list.length, greaterThanOrEqualTo(1));
      expect(list.first.coinName, equals('1882-CC Morgan Dollar'));

      // Export check
      final jsonStr = await collectionService.exportToJson();
      final parsed = jsonDecode(jsonStr) as List<dynamic>;
      expect(parsed.isNotEmpty, isTrue);

      // Deletion check
      await collectionService.deleteItem('coin_test_1');
      final postDelete = await collectionService.loadCollection();
      expect(postDelete.any((i) => i.id == 'coin_test_1'), isFalse);
    });
  });

  group('Phase 10: Auth Service & Session Management Tests', () {
    late AuthService authService;
    late SecureStorageService secureStorage;

    setUp(() {
      secureStorage = DeviceSecureStorageService();
      authService = AuthService(secureStorage: secureStorage);
    });

    test('4. Defaults to honest guest state without stored credentials', () async {
      await authService.initialize();
      expect(authService.currentState.isGuest, isTrue);
      expect(authService.currentState.isAuthenticated, isFalse);
    });

    test('5. Sign in with email updates state and persists tokens', () async {
      await authService.signInWithEmail(
        email: 'collector@coinscan.app',
        password: 'securePassword123',
        termsAccepted: true,
      );
      expect(authService.currentState.isAuthenticated, isTrue);
      expect(authService.currentState.user?.email, equals('collector@coinscan.app'));

      // Verify token persisted in secure storage
      final storedToken = await secureStorage.read(
        key: DeviceSecureStorageService.keyAuthToken,
      );
      expect(storedToken, isNotNull);

      // Sign out clears token
      await authService.signOut();
      expect(authService.currentState.isAuthenticated, isFalse);
      expect(
        await secureStorage.read(key: DeviceSecureStorageService.keyAuthToken),
        isNull,
      );
    });

    test('5b. Session restoration restores verified email and display name across restarts', () async {
      await authService.signInWithEmail(
        email: 'numismatist@example.com',
        password: 'password99',
        termsAccepted: true,
      );
      expect(authService.currentState.user?.email, equals('numismatist@example.com'));
      expect(authService.currentState.user?.displayName, equals('numismatist'));

      // Simulate app restart with a fresh AuthService instance sharing the same secureStorage
      final freshAuthService = AuthService(secureStorage: secureStorage);
      await freshAuthService.initialize();

      expect(freshAuthService.currentState.isAuthenticated, isTrue);
      expect(freshAuthService.currentState.user?.email, equals('numismatist@example.com'));
      expect(freshAuthService.currentState.user?.displayName, equals('numismatist'));

      await freshAuthService.signOut();
      expect(freshAuthService.currentState.isAuthenticated, isFalse);
    });
  });

  group('Phase 10: Scan History Export Tests', () {
    test('6. ScanHistoryService exports valid JSON structure', () async {
      final historyService = ScanHistoryService();
      final jsonStr = await historyService.exportToJson();
      expect(jsonStr.startsWith('['), isTrue);
    });
  });
}
