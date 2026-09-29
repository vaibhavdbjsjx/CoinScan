import 'package:flutter_test/flutter_test.dart';
import 'package:coinvault_ai/core/storage/collection_storage_service.dart';
import 'package:coinvault_ai/core/storage/scan_history_service.dart';
import 'package:coinvault_ai/core/auth/auth_service.dart';
import 'package:coinvault_ai/core/storage/secure_storage_service.dart';
import 'package:coinvault_ai/core/legal/legal_consent_models.dart';

class MockSecureStorage implements SecureStorageService {
  final Map<String, String> _data = {};

  @override
  Future<void> write({required String key, required String value}) async {
    _data[key] = value;
  }

  @override
  Future<String?> read({required String key}) async {
    return _data[key];
  }

  @override
  Future<void> delete({required String key}) async {
    _data.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _data.clear();
  }

  Future<Map<String, String>> readAll() async {
    return Map.unmodifiable(_data);
  }
}

void main() {
  group('Client Chaos & Data Resilience Tests', () {
    test('1. VaultCoinItem.fromJson recovers safely from missing ID and corrupt dates', () {
      final corruptJson = {
        'id': null,
        'coinName': 'Liberty Head Nickel',
        'country': 'United States',
        'denomination': '5 Cents',
        'year': '1912',
        'dateAdded': 'INVALID_NOT_A_DATE',
        'purchasePrice': double.nan,
        'currentEstimatedValue': double.infinity,
      };

      final item = VaultCoinItem.fromJson(corruptJson);
      expect(item.id, isNotEmpty);
      expect(item.id.startsWith('vault_'), isTrue);
      expect(item.coinName, equals('Liberty Head Nickel'));
      expect(item.year, equals(1912));
      expect(item.dateAdded, isNotNull);
      expect(item.purchasePrice, isNull);
      expect(item.currentEstimatedValue, isNull);
    });

    test('2. CollectionDashboardStats ignores NaN, Infinity, and negative values', () async {
      final storage = CollectionStorageService.instance;
      storage.setCurrentUser('chaos_stats_user');
      storage.resetForUserSwitch();

      final item1 = VaultCoinItem(
        id: 'c1',
        coinName: 'Silver Eagle',
        country: 'United States',
        denomination: '1 Dollar',
        currentEstimatedValue: 35.0,
        dateAdded: DateTime.now(),
      );

      final itemCorrupt = VaultCoinItem(
        id: 'c2',
        coinName: 'Corrupt Coin',
        country: 'United States',
        denomination: '1 Dollar',
        currentEstimatedValue: double.nan,
        dateAdded: DateTime.now(),
      );

      await storage.saveItem(item1);
      await storage.saveItem(itemCorrupt);

      final stats = storage.calculateStats();

      expect(stats.totalEstimatedValue.isNaN, isFalse);
      expect(stats.totalEstimatedValue.isInfinite, isFalse);
      expect(stats.totalEstimatedValue, equals(35.0));
      storage.resetForUserSwitch();
    });

    test('3. ScanRecord.fromJson recovers safely from corrupt dates and missing fields', () {
      final corruptJson = {
        'id': null,
        'scannedAt': 'CORRUPT_TIMESTAMP',
        'coinName': 'Morgan Dollar',
      };

      final record = ScanRecord.fromJson(corruptJson);
      expect(record.id.startsWith('scan_'), isTrue);
      expect(record.scannedAt, isNotNull);
      expect(record.coinName, equals('Morgan Dollar'));
    });
  });

  group('Client Account Isolation & State Reset Tests', () {
    late MockSecureStorage secureStorage;
    late LegalConsentService legalConsentService;
    late AuthService authService;

    setUp(() {
      secureStorage = MockSecureStorage();
      legalConsentService = LegalConsentService(secureStorage: secureStorage);
      authService = AuthService(
        secureStorage: secureStorage,
        legalConsentService: legalConsentService,
      );
      CollectionStorageService.instance.resetForUserSwitch();
      ScanHistoryService.instance.resetForUserSwitch();
    });

    test('4. Sign out completely flushes in-memory collection and history cache', () async {
      // User A signs in
      await authService.signInWithEmail(
        email: 'userA@coinscan.app',
        password: 'password123',
        termsAccepted: true,
      );

      // Add item to User A's collection in memory
      final itemA = VaultCoinItem(
        id: 'item_user_a',
        coinName: 'User A Rare Coin',
        country: 'United States',
        denomination: '1 Dollar',
        dateAdded: DateTime.now(),
      );
      await CollectionStorageService.instance.addItem(itemA);
      expect(CollectionStorageService.instance.items.length, equals(1));

      // User A signs out
      await authService.signOut();

      // In-memory cache must be completely cleared
      expect(CollectionStorageService.instance.items.isEmpty, isTrue);
      expect(ScanHistoryService.instance.cachedRecordCount, equals(0));
    });

    test('5. Account B cannot inherit Account A collection cache after account switch', () async {
      // User A signs in
      await authService.signInWithEmail(
        email: 'userA@coinscan.app',
        password: 'password123',
        termsAccepted: true,
      );

      final itemA = VaultCoinItem(
        id: 'item_user_a_secret',
        coinName: 'User A Secret Coin',
        country: 'United States',
        denomination: '1 Dollar',
        dateAdded: DateTime.now(),
      );
      await CollectionStorageService.instance.addItem(itemA);

      // User A signs out
      await authService.signOut();

      // User B signs in
      await authService.signInWithEmail(
        email: 'userB@coinscan.app',
        password: 'password456',
        termsAccepted: true,
      );

      // User B's vault items must NOT contain User A's items
      final userBItems = CollectionStorageService.instance.items;
      expect(userBItems.any((item) => item.id == 'item_user_a_secret'), isFalse);
    });

    test('6. Permanent account deletion flushes all local data without resurrecting state', () async {
      await authService.signInWithEmail(
        email: 'userToDelete@coinscan.app',
        password: 'password123',
        termsAccepted: true,
      );

      await CollectionStorageService.instance.addItem(
        VaultCoinItem(
          id: 'item_to_delete',
          coinName: 'Ephemeral Coin',
          country: 'Canada',
          denomination: '1 Cent',
          dateAdded: DateTime.now(),
        ),
      );

      await authService.deleteAccount();

      expect(authService.currentState.isAuthenticated, isFalse);
      expect(CollectionStorageService.instance.items.isEmpty, isTrue);
      expect(await secureStorage.readAll(), isEmpty);
    });
  });
}
