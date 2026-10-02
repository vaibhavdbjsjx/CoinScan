import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:coinvault_ai/core/storage/collection_storage_service.dart';
import 'package:coinvault_ai/core/storage/models.dart';
import 'package:coinvault_ai/core/reports/coin_report_service.dart';
import 'package:coinvault_ai/core/utils/pdf_generator.dart';
import 'package:coinvault_ai/core/network/mock_api.dart';

import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return Directory.systemTemp.path;
    });
  });

  group('CollectionStorageService & Vault Statistics Tests', () {
    late CollectionStorageService service;

    setUp(() {
      service = CollectionStorageService();
    });

    test('1. Empty collection produces zeroed authentic statistics', () {
      final stats = service.calculateStats();
      expect(stats.totalCoins, equals(0));
      expect(stats.totalEstimatedValue, equals(0.0));
      expect(stats.silverCoinsCount, equals(0));
      expect(stats.goldCoinsCount, equals(0));
      expect(stats.uniqueCountries, equals(0));
      expect(service.generateInsights(), isEmpty);
    });

    test('2. Vault item properties, metal detection, and closer look logic', () async {
      final silverCoin = VaultCoinItem(
        id: 'silver_1',
        coinName: 'Morgan Dollar',
        country: 'United States',
        denomination: '1 Dollar',
        year: 1881,
        mintMark: 'S',
        composition: '90% Silver, 10% Copper',
        conditionEstimate: 'MS-63 Choice Uncirculated',
        currentEstimatedValue: 125.0,
        initialValuationSnapshot: 110.0,
        keyEvidence: ['San Francisco S mint mark verified', 'Denticles intact'],
        dateAdded: DateTime(2026, 1, 15),
      );

      expect(silverCoin.hasPreciousMetal, isTrue);
      expect(silverCoin.isWorthCloserLook, isTrue); // Pre-1950, Silver, Mint Mark

      final modernClad = VaultCoinItem(
        id: 'clad_1',
        coinName: 'Kennedy Half Dollar',
        country: 'United States',
        denomination: '50 Cents',
        year: 1980,
        composition: 'Copper-Nickel Clad',
        conditionEstimate: 'Circulated',
        currentEstimatedValue: 0.50,
        dateAdded: DateTime(2026, 2, 1),
      );

      expect(modernClad.hasPreciousMetal, isFalse);
      expect(modernClad.isWorthCloserLook, isFalse);
    });

    test('3. Saves items, computes genuine stats and non-fabricated insights', () async {
      final item1 = VaultCoinItem(
        id: 'coin_gold_1',
        coinName: 'Saint-Gaudens Double Eagle',
        country: 'United States',
        denomination: '20 Dollars',
        year: 1924,
        composition: '90% Gold, 10% Copper',
        currentEstimatedValue: 2400.0,
        dateAdded: DateTime(2026, 3, 1),
      );

      final item2 = VaultCoinItem(
        id: 'coin_silver_1',
        coinName: 'British Sovereign Silver Token',
        country: 'United Kingdom',
        denomination: '1 Crown',
        year: 1890,
        composition: 'Sterling Silver',
        currentEstimatedValue: 80.0,
        dateAdded: DateTime(2026, 3, 5),
      );

      await service.saveItem(item1);
      await service.saveItem(item2);

      final stats = service.calculateStats();
      expect(stats.totalCoins, equals(2));
      expect(stats.uniqueCountries, equals(2));
      expect(stats.goldCoinsCount, equals(1));
      expect(stats.silverCoinsCount, equals(1));
      expect(stats.totalEstimatedValue, equals(2480.0));

      final insights = service.generateInsights();
      expect(insights.any((i) => i.contains('2 countries')), isTrue);
      expect(insights.any((i) => i.contains('gold')), isTrue);
      expect(insights.any((i) => i.contains('silver')), isTrue);

      // Verify toCollectibleModel compatibility
      final collectible = item1.toCollectibleModel();
      expect(collectible.id, equals(item1.id));
      expect(collectible.name, equals(item1.coinName));
      expect(collectible.retailPrice, equals(2400.0));
      // Rarity is never inferred from metal content: no rarity data source exists.
      expect(collectible.rarity, equals(RarityLevel.notAssessed));

      // Cleanup
      await service.deleteItem(item1.id);
      await service.deleteItem(item2.id);
    });

    test('4. Duplicate detection finds identical denomination, country and year', () async {
      final coinA = VaultCoinItem(
        id: 'dupe_1',
        coinName: 'Lincoln Cent',
        country: 'United States',
        denomination: '1 Cent',
        year: 1909,
        mintMark: 'S',
        dateAdded: DateTime(2026, 1, 1),
      );

      final coinB = VaultCoinItem(
        id: 'dupe_2',
        coinName: 'Lincoln Cent Dupe',
        country: 'United States',
        denomination: '1 Cent',
        year: 1909,
        mintMark: 'S',
        dateAdded: DateTime(2026, 1, 2),
      );

      await service.saveItem(coinA);
      await service.saveItem(coinB);

      final dupes = service.findDuplicates(
        country: 'United States',
        denomination: '1 Cent',
        year: 1909,
        mintMark: 'S',
      );

      expect(dupes.length, equals(2));

      await service.deleteItem(coinA.id);
      await service.deleteItem(coinB.id);
    });
  });

  group('CoinReportData & PDF Generation Tests', () {
    test('5. CoinReportData produces an accurate, non-certificate text summary', () {
      final report = CoinReportData(
        title: '1921 Morgan Silver Dollar',
        country: 'United States',
        year: 1921,
        denomination: '1 Dollar',
        mintMark: 'D',
        composition: '90% Silver',
        identificationConfidence: 'High',
        valuationRange: '35 – 65 USD',
        keyEvidence: ['Denver D mint mark identified', 'Liberty headband inscription readable'],
        conditionGrade: 'VF-30 Very Fine',
        generatedAt: DateTime.now(),
      );

      final shareText = report.toShareableText();
      expect(shareText, contains('1921 Morgan Silver Dollar'));
      expect(shareText, contains('Denver D mint mark identified'));
      expect(shareText, contains('Identification confidence: High'));
      expect(shareText, contains('Authenticity: not assessed'));
      expect(shareText, contains(kReportLimitationsStatement));
      expect(shareText.toLowerCase(), isNot(contains('certificate of')));
    });

    test('6. PdfGenerator writes a valid identification report file', () async {
      final report = CoinReportData(
        title: '1794 Flowing Hair Dollar',
        country: 'United States',
        year: 1794,
        denomination: '1 Dollar',
        composition: '89.2% Silver, 10.8% Copper',
        weightG: 26.96,
        diameterMm: 39.5,
        identificationConfidence: 'Medium',
        keyEvidence: ['Original lettered edge'],
        generatedAt: DateTime(2026, 9, 30),
      );
      final dir = await Directory.systemTemp.createTemp('coinscan_pdf_test');

      final File pdfFile = await PdfGenerator.generateIdentificationReport(
        report,
        notes: 'Bought at a coin show.',
        storageLocation: 'Bank Safety Deposit Box #4',
        outputDirectory: dir,
      );

      expect(pdfFile.existsSync(), isTrue);
      expect(pdfFile.lengthSync(), greaterThan(1000));
      expect(pdfFile.path.endsWith('.pdf'), isTrue);
      expect(String.fromCharCodes(pdfFile.readAsBytesSync().take(5)), '%PDF-');

      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('7. CollectionStorageService.items getter reflects live cache and is unmodifiable', () async {
      final testService = CollectionStorageService();
      final item = VaultCoinItem(
        id: 'getter_test_1',
        coinName: 'Buffalo Nickel',
        country: 'United States',
        denomination: '5 Cents',
        year: 1936,
        composition: '75% Copper, 25% Nickel',
        dateAdded: DateTime.now(),
      );

      await testService.saveItem(item);
      expect(testService.items.length, equals(1));
      expect(testService.items.first.coinName, equals('Buffalo Nickel'));

      // Attempting to modify the unmodifiable list directly must throw an UnsupportedError
      expect(() => (testService.items as dynamic).add(item), throwsUnsupportedError);

      await testService.deleteItem(item.id);
      expect(testService.items.isEmpty, isTrue);
    });

    test('8. MockApi.getPriceHistory returns no invented series and prevents FlSpot crashes', () {
      // Empty for every input, so the chart shows its honest "unavailable" state
      // instead of plotting a fabricated history (and never feeds FlSpot bad data).
      expect(MockApi.getPriceHistory('unknown_id_999', '1 Month', baseOverride: 0.0), isEmpty);
      expect(MockApi.getPriceHistory('unknown_id_999', '1 Year', baseOverride: -10.0), isEmpty);
      expect(MockApi.getPriceHistory('coin_morgan_cc', '6 Months'), isEmpty);
      expect(MockApi.getPriceHistory('vault_custom_coin', '1 Month', baseOverride: 250.0), isEmpty);
    });
  });
}
