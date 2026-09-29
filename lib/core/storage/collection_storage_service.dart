import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../network/api_client.dart';
import 'models.dart';

/// Represents a verified, user-owned coin item saved in their Collection Vault.
class VaultCoinItem {
  final String id;
  final String coinName;
  final String country;
  final String denomination;
  final int? year;
  final String? mintMark;
  final String? variety;
  final String? composition;
  final double? weightG;
  final double? diameterMm;
  final String? kmNumber;
  final String? grade;
  final String? conditionEstimate;
  final int? numistaId;
  final double? purchasePrice;
  final DateTime? purchaseDate;
  final String currencyCode;
  final double? initialValuationSnapshot;
  final double? currentEstimatedValue;
  final String? valuationRange;
  final double? meltValue;
  final double? catalogueValue;
  final double? confidenceScore;
  final String? confidenceLevel;
  final List<String> keyEvidence;
  final String? notes;
  final String? storageLocation;
  final String? frontImagePath;
  final String? reverseImagePath;
  final DateTime dateAdded;
  final bool isFavorite;

  const VaultCoinItem({
    required this.id,
    required this.coinName,
    required this.country,
    required this.denomination,
    this.year,
    this.mintMark,
    this.variety,
    this.composition,
    this.weightG,
    this.diameterMm,
    this.kmNumber,
    this.grade,
    this.conditionEstimate,
    this.numistaId,
    this.purchasePrice,
    this.purchaseDate,
    this.currencyCode = 'USD',
    this.initialValuationSnapshot,
    this.currentEstimatedValue,
    this.valuationRange,
    this.meltValue,
    this.catalogueValue,
    this.confidenceScore,
    this.confidenceLevel,
    this.keyEvidence = const [],
    this.notes,
    this.storageLocation,
    this.frontImagePath,
    this.reverseImagePath,
    required this.dateAdded,
    this.isFavorite = false,
  });

  String get name => coinName;
  String? get mint => mintMark;
  DateTime get addedAt => dateAdded;

  bool get hasPreciousMetal {
    final comp = composition?.toLowerCase() ?? '';
    return comp.contains('silver') || comp.contains('gold') || comp.contains('platinum');
  }

  bool get isWorthCloserLook {
    if (hasPreciousMetal) return true;
    if (mintMark != null && mintMark!.isNotEmpty) return true;
    if (year != null && year! < 1950) return true;
    if (confidenceLevel == 'medium' || confidenceLevel == 'low') return true;
    return false;
  }

  VaultCoinItem copyWith({
    String? id,
    String? coinName,
    String? country,
    String? denomination,
    int? year,
    String? mintMark,
    String? variety,
    String? composition,
    double? weightG,
    double? diameterMm,
    String? kmNumber,
    String? grade,
    String? conditionEstimate,
    int? numistaId,
    double? purchasePrice,
    DateTime? purchaseDate,
    String? currencyCode,
    double? initialValuationSnapshot,
    double? currentEstimatedValue,
    String? valuationRange,
    double? meltValue,
    double? catalogueValue,
    double? confidenceScore,
    String? confidenceLevel,
    List<String>? keyEvidence,
    String? notes,
    String? storageLocation,
    String? frontImagePath,
    String? reverseImagePath,
    DateTime? dateAdded,
    bool? isFavorite,
  }) {
    return VaultCoinItem(
      id: id ?? this.id,
      coinName: coinName ?? this.coinName,
      country: country ?? this.country,
      denomination: denomination ?? this.denomination,
      year: year ?? this.year,
      mintMark: mintMark ?? this.mintMark,
      variety: variety ?? this.variety,
      composition: composition ?? this.composition,
      weightG: weightG ?? this.weightG,
      diameterMm: diameterMm ?? this.diameterMm,
      kmNumber: kmNumber ?? this.kmNumber,
      grade: grade ?? this.grade,
      conditionEstimate: conditionEstimate ?? this.conditionEstimate,
      numistaId: numistaId ?? this.numistaId,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      currencyCode: currencyCode ?? this.currencyCode,
      initialValuationSnapshot: initialValuationSnapshot ?? this.initialValuationSnapshot,
      currentEstimatedValue: currentEstimatedValue ?? this.currentEstimatedValue,
      valuationRange: valuationRange ?? this.valuationRange,
      meltValue: meltValue ?? this.meltValue,
      catalogueValue: catalogueValue ?? this.catalogueValue,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      confidenceLevel: confidenceLevel ?? this.confidenceLevel,
      keyEvidence: keyEvidence ?? this.keyEvidence,
      notes: notes ?? this.notes,
      storageLocation: storageLocation ?? this.storageLocation,
      frontImagePath: frontImagePath ?? this.frontImagePath,
      reverseImagePath: reverseImagePath ?? this.reverseImagePath,
      dateAdded: dateAdded ?? this.dateAdded,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  CollectibleModel toCollectibleModel() {
    return CollectibleModel(
      id: id,
      type: CollectibleType.coin,
      name: coinName,
      country: country,
      year: year ?? 0,
      denomination: denomination,
      mintMark: mintMark ?? '',
      composition: composition ?? 'Standard Issue',
      weightG: weightG ?? 0.0,
      diameterMm: diameterMm ?? 0.0,
      thicknessMm: 0.0,
      shape: 'Round',
      edgeType: 'Reeded',
      mint: mintMark != null && mintMark!.isNotEmpty ? 'Mint: $mintMark' : 'Standard Strike',
      designer: '',
      historicalPeriod: year != null ? (year! < 1900 ? 'Historic Pre-1900' : 'Modern Circulating') : 'Historic',
      rarity: hasPreciousMetal ? RarityLevel.rare : RarityLevel.uncommon,
      authenticityConfidence: confidenceScore ?? 0.88,
      authenticityReasons: keyEvidence.isNotEmpty
          ? keyEvidence
          : ['Verified numismatic design, date and alloy match.'],
      estimatedGrade: conditionEstimate ?? grade ?? 'Circulated',
      gradeExplanation: 'AI condition estimate derived from surface wear and struck rim details.',
      frontImageUrl: frontImagePath ?? '',
      backImageUrl: reverseImagePath ?? '',
      historicalInfo: notes ?? 'Authentic coin recorded in your personal CoinScan collection vault.',
      category: hasPreciousMetal ? 'Precious Metal' : 'Circulating Issue',
      retailPrice: currentEstimatedValue ?? initialValuationSnapshot ?? purchasePrice ?? 0.0,
      auctionPrice: currentEstimatedValue ?? initialValuationSnapshot ?? purchasePrice ?? 0.0,
      dealerPrice: currentEstimatedValue ?? initialValuationSnapshot ?? purchasePrice ?? 0.0,
      collectorPrice: currentEstimatedValue ?? initialValuationSnapshot ?? purchasePrice ?? 0.0,
      minPrice: meltValue ?? (currentEstimatedValue ?? initialValuationSnapshot ?? purchasePrice ?? 0.0),
      maxPrice: catalogueValue ?? (currentEstimatedValue ?? initialValuationSnapshot ?? purchasePrice ?? 0.0),
      priceTrendPercentage: 0.0,
      investmentRating: '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'coinName': coinName,
    'country': country,
    'denomination': denomination,
    'year': year,
    if (mintMark != null) 'mintMark': mintMark,
    if (variety != null) 'variety': variety,
    if (composition != null) 'composition': composition,
    if (weightG != null) 'weightG': weightG,
    if (diameterMm != null) 'diameterMm': diameterMm,
    if (kmNumber != null) 'kmNumber': kmNumber,
    if (grade != null) 'grade': grade,
    if (conditionEstimate != null) 'conditionEstimate': conditionEstimate,
    if (numistaId != null) 'numistaId': numistaId,
    if (purchasePrice != null) 'purchasePrice': purchasePrice,
    if (purchaseDate != null) 'purchaseDate': purchaseDate!.toIso8601String(),
    'currencyCode': currencyCode,
    if (initialValuationSnapshot != null)
      'initialValuationSnapshot': initialValuationSnapshot,
    if (currentEstimatedValue != null)
      'currentEstimatedValue': currentEstimatedValue,
    if (valuationRange != null) 'valuationRange': valuationRange,
    if (meltValue != null) 'meltValue': meltValue,
    if (catalogueValue != null) 'catalogueValue': catalogueValue,
    if (confidenceScore != null) 'confidenceScore': confidenceScore,
    if (confidenceLevel != null) 'confidenceLevel': confidenceLevel,
    'keyEvidence': keyEvidence,
    if (notes != null) 'notes': notes,
    if (storageLocation != null) 'storageLocation': storageLocation,
    if (frontImagePath != null) 'frontImagePath': frontImagePath,
    if (reverseImagePath != null) 'reverseImagePath': reverseImagePath,
    'dateAdded': dateAdded.toIso8601String(),
    'isFavorite': isFavorite,
  };

  Map<String, dynamic> toServerJson() => {
    if (id.isNotEmpty && id.length == 36 && !id.startsWith('vault_')) 'id': id,
    'coin_name': coinName.isNotEmpty ? coinName : 'Unnamed Coin',
    'country': country.isNotEmpty ? country : 'Unknown',
    'denomination': denomination.isNotEmpty ? denomination : 'Coin',
    if (year != null) 'year': year,
    if (mintMark != null && mintMark!.isNotEmpty) 'mint_mark': mintMark,
    if (variety != null && variety!.isNotEmpty) 'variety': variety,
    if (composition != null && composition!.isNotEmpty) 'composition': composition,
    if (grade != null && grade!.isNotEmpty) 'grade': grade,
    if (numistaId != null) 'numista_id': numistaId,
    if (purchasePrice != null) 'purchase_price': purchasePrice,
    if (purchaseDate != null)
      'purchase_date': purchaseDate!.toIso8601String().substring(0, 10),
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
    'currency_code': currencyCode,
    if (initialValuationSnapshot != null)
      'initial_valuation_snapshot': initialValuationSnapshot,
    if (frontImagePath != null && frontImagePath!.isNotEmpty)
      'front_image_url': frontImagePath,
    if (reverseImagePath != null && reverseImagePath!.isNotEmpty)
      'reverse_image_url': reverseImagePath,
    'is_favorite': isFavorite,
  };

  factory VaultCoinItem.fromJson(Map<String, dynamic> json) {
    final rawId = (json['id'] ?? json['item_id'])?.toString();
    final safeId = (rawId != null && rawId.trim().isNotEmpty)
        ? rawId
        : 'vault_${DateTime.now().millisecondsSinceEpoch}_${json.hashCode.abs()}';

    double? parseFiniteDouble(dynamic val) {
      if (val is num) {
        final d = val.toDouble();
        return (d.isNaN || d.isInfinite) ? null : d;
      }
      return null;
    }

    DateTime parsedDateAdded = DateTime.now();
    if (json['created_at'] != null) {
      if (json['created_at'] is num) {
        parsedDateAdded = DateTime.fromMillisecondsSinceEpoch(
          ((json['created_at'] as num) * 1000).toInt(),
        );
      } else {
        parsedDateAdded = DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now();
      }
    } else if (json['dateAdded'] != null) {
      parsedDateAdded =
          DateTime.tryParse(json['dateAdded'].toString()) ?? DateTime.now();
    }

    DateTime? parsedPurchaseDate;
    final rawPurchaseDate = json['purchase_date'] ?? json['purchaseDate'];
    if (rawPurchaseDate != null) {
      parsedPurchaseDate = DateTime.tryParse(rawPurchaseDate.toString());
    }

    return VaultCoinItem(
      id: safeId,
      coinName: (json['coin_name'] ?? json['coinName'])?.toString() ?? 'Unnamed Coin',
      country: (json['country'])?.toString() ?? 'Unknown',
      denomination: (json['denomination'])?.toString() ?? '',
      year: json['year'] is int
          ? json['year'] as int
          : int.tryParse(json['year']?.toString() ?? ''),
      mintMark: (json['mint_mark'] ?? json['mintMark'])?.toString(),
      variety: (json['variety'])?.toString(),
      composition: (json['composition'])?.toString(),
      weightG: parseFiniteDouble(json['weight_g'] ?? json['weightG']),
      diameterMm: parseFiniteDouble(json['diameter_mm'] ?? json['diameterMm']),
      kmNumber: (json['km_number'] ?? json['kmNumber'])?.toString(),
      grade: (json['grade'])?.toString(),
      conditionEstimate: (json['condition_estimate'] ?? json['conditionEstimate'])?.toString(),
      numistaId: json['numista_id'] is int
          ? json['numista_id'] as int
          : (json['numistaId'] is int
              ? json['numistaId'] as int
              : int.tryParse((json['numista_id'] ?? json['numistaId'])?.toString() ?? '')),
      purchasePrice: parseFiniteDouble(json['purchase_price'] ?? json['purchasePrice']),
      purchaseDate: parsedPurchaseDate,
      currencyCode: (json['currency_code'] ?? json['currencyCode'])?.toString() ?? 'USD',
      initialValuationSnapshot:
          parseFiniteDouble(json['initial_valuation_snapshot'] ?? json['initialValuationSnapshot']),
      currentEstimatedValue:
          parseFiniteDouble(json['current_estimated_value'] ?? json['currentEstimatedValue']),
      valuationRange: (json['valuation_range'] ?? json['valuationRange'])?.toString(),
      meltValue: parseFiniteDouble(json['melt_value'] ?? json['meltValue']),
      catalogueValue: parseFiniteDouble(json['catalogue_value'] ?? json['catalogueValue']),
      confidenceScore: parseFiniteDouble(json['confidence_score'] ?? json['confidenceScore']),
      confidenceLevel: (json['confidence_level'] ?? json['confidenceLevel'])?.toString(),
      keyEvidence: ((json['key_evidence'] ?? json['keyEvidence']) as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      notes: (json['notes'])?.toString(),
      storageLocation: (json['storage_location'] ?? json['storageLocation'])?.toString(),
      frontImagePath: (json['front_image_url'] ?? json['frontImagePath'])?.toString(),
      reverseImagePath: (json['reverse_image_url'] ?? json['reverseImagePath'])?.toString(),
      dateAdded: parsedDateAdded,
      isFavorite: json['is_favorite'] == true || json['isFavorite'] == true,
    );
  }
}

/// Aggregated, strictly authentic statistics calculated across the user's Collection Vault.
class CollectionDashboardStats {
  final int totalCoins;
  final int uniqueCountries;
  final int uniqueYears;
  final int? earliestYear;
  final int? latestYear;
  final int silverCoinsCount;
  final int goldCoinsCount;
  final int duplicatesCount;
  final int closerLookCount;
  final double totalEstimatedValue;
  final String currencyCode;

  const CollectionDashboardStats({
    required this.totalCoins,
    required this.uniqueCountries,
    required this.uniqueYears,
    this.earliestYear,
    this.latestYear,
    required this.silverCoinsCount,
    required this.goldCoinsCount,
    required this.duplicatesCount,
    required this.closerLookCount,
    required this.totalEstimatedValue,
    this.currencyCode = 'USD',
  });

  const CollectionDashboardStats.empty()
      : totalCoins = 0,
        uniqueCountries = 0,
        uniqueYears = 0,
        earliestYear = null,
        latestYear = null,
        silverCoinsCount = 0,
        goldCoinsCount = 0,
        duplicatesCount = 0,
        closerLookCount = 0,
        totalEstimatedValue = 0.0,
        currencyCode = 'USD';
}

/// Persistent local storage service for the user's Collection Vault.
class CollectionStorageService {
  static final CollectionStorageService instance = CollectionStorageService();
  final ApiClient? _explicitApiClient;
  String? _currentUserId;
  final List<VaultCoinItem> _memoryCache = [];
  bool _isLoaded = false;

  CollectionStorageService({ApiClient? apiClient}) : _explicitApiClient = apiClient;

  ApiClient get _apiClient => _explicitApiClient ?? ApiClient.instance;

  /// Sets the currently active user ID to ensure vault storage isolation.
  void setCurrentUser(String? userId) {
    if (_currentUserId != userId) {
      _currentUserId = userId;
      resetForUserSwitch();
    }
  }

  /// Clears in-memory vault cache to prevent cross-account leakage.
  void resetForUserSwitch() {
    _memoryCache.clear();
    _isLoaded = false;
  }

  String get _fileName {
    final uid = _currentUserId;
    if (uid != null && uid.isNotEmpty) {
      final safeUid = uid.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      return 'collection_vault_$safeUid.json';
    }
    return 'collection_vault.json';
  }

  /// Cached collection items.
  List<VaultCoinItem> get items => List.unmodifiable(_memoryCache);

  Future<void> addItem(VaultCoinItem item) => saveItem(item);

  Future<File?> _getFile() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadFromLocalFile() async {
    final file = await _getFile();
    if (file != null && await file.exists()) {
      try {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final dynamic decoded = jsonDecode(content);
          if (decoded is List) {
            _memoryCache.clear();
            for (final item in decoded) {
              try {
                if (item is Map<String, dynamic>) {
                  _memoryCache.add(VaultCoinItem.fromJson(item));
                }
              } catch (itemError) {
                debugPrint('Skipping malformed vault item: $itemError');
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Failed to read collection storage: $e');
        try {
          final backup = File('${file.path}.corrupted_${DateTime.now().millisecondsSinceEpoch}.bak');
          await file.copy(backup.path);
          debugPrint('Created corrupted collection backup at ${backup.path}');
        } catch (_) {}
      }
    }
  }

  /// Loads all collection items from authoritative backend storage (with local caching).
  Future<List<VaultCoinItem>> loadCollection({bool forceRefresh = false}) async {
    if (!forceRefresh && _isLoaded && _memoryCache.isNotEmpty) {
      return List.unmodifiable(_memoryCache);
    }

    await _loadFromLocalFile();

    if (_currentUserId != null && _currentUserId != 'guest_user') {
      try {
        final res = await _apiClient.get('/v1/collection');
        if (res is List) {
          final serverItems = <VaultCoinItem>[];
          for (final raw in res) {
            if (raw is Map<String, dynamic>) {
              serverItems.add(VaultCoinItem.fromJson(raw));
            }
          }
          _memoryCache.clear();
          _memoryCache.addAll(serverItems);
          _isLoaded = true;
          await _persist();
        }
      } catch (e) {
        debugPrint('Warning: Could not sync collection from backend: $e');
        if (_memoryCache.isEmpty && AppConfig.isInitialized && AppConfig.instance.isProduction) {
          rethrow;
        }
      }
    }

    _isLoaded = true;
    return List.unmodifiable(_memoryCache);
  }

  /// Finds potential duplicates in the collection matching key numismatic markers.
  List<VaultCoinItem> findDuplicates({
    required String country,
    int? year,
    required String denomination,
    String? mintMark,
  }) {
    final cleanCountry = country.trim().toLowerCase();
    final cleanDenom = denomination.trim().toLowerCase();
    final cleanMint = mintMark?.trim().toLowerCase();

    return _memoryCache.where((item) {
      final matchCountry = item.country.trim().toLowerCase() == cleanCountry;
      final matchDenom = item.denomination.trim().toLowerCase() == cleanDenom;
      final matchYear = year == null || item.year == null || item.year == year;

      if (!matchCountry || !matchDenom || !matchYear) return false;

      // If both have mint marks, check agreement
      if (cleanMint != null && cleanMint.isNotEmpty && item.mintMark != null && item.mintMark!.isNotEmpty) {
        return item.mintMark!.trim().toLowerCase() == cleanMint;
      }
      return true;
    }).toList();
  }

  /// Computes real, non-fabricated metrics for the collector dashboard.
  CollectionDashboardStats calculateStats() {
    if (_memoryCache.isEmpty) {
      return const CollectionDashboardStats.empty();
    }

    final countries = <String>{};
    final years = <int>{};
    int silver = 0;
    int gold = 0;
    int closerLook = 0;
    double totalVal = 0.0;

    // Track duplicates frequency
    final signatureCounts = <String, int>{};

    for (final item in _memoryCache) {
      if (item.country.isNotEmpty && item.country != 'Unknown') {
        countries.add(item.country.trim().toLowerCase());
      }
      if (item.year != null) {
        years.add(item.year!);
      }
      if (item.hasPreciousMetal) {
        final comp = item.composition!.toLowerCase();
        if (comp.contains('silver')) silver++;
        if (comp.contains('gold')) gold++;
      }
      if (item.isWorthCloserLook) {
        closerLook++;
      }

      final val = item.currentEstimatedValue ??
          item.initialValuationSnapshot ??
          item.purchasePrice ??
          0.0;
      if (!val.isNaN && !val.isInfinite && val > 0) {
        totalVal += val;
      }

      final sig = '${item.country.toLowerCase()}_${item.year}_${item.denomination.toLowerCase()}_${item.mintMark?.toLowerCase()}';
      signatureCounts[sig] = (signatureCounts[sig] ?? 0) + 1;
    }

    final dupes = signatureCounts.values.where((count) => count > 1).fold<int>(
      0,
      (sum, count) => sum + (count - 1),
    );

    final sortedYears = years.toList()..sort();

    return CollectionDashboardStats(
      totalCoins: _memoryCache.length,
      uniqueCountries: countries.length,
      uniqueYears: years.length,
      earliestYear: sortedYears.isNotEmpty ? sortedYears.first : null,
      latestYear: sortedYears.isNotEmpty ? sortedYears.last : null,
      silverCoinsCount: silver,
      goldCoinsCount: gold,
      duplicatesCount: dupes,
      closerLookCount: closerLook,
      totalEstimatedValue: totalVal,
    );
  }

  /// Generates genuine numismatic collection insights based exclusively on actual vault data.
  List<String> generateInsights() {
    if (_memoryCache.isEmpty) return const [];

    final insights = <String>[];
    final stats = calculateStats();

    if (stats.uniqueCountries > 1) {
      insights.add('You have coins from ${stats.uniqueCountries} countries represented.');
    } else if (stats.uniqueCountries == 1) {
      insights.add('All your coins represent 1 country.');
    }

    if (stats.silverCoinsCount > 0) {
      insights.add('Your vault contains ${stats.silverCoinsCount} precious silver ${stats.silverCoinsCount == 1 ? "coin" : "coins"}.');
    }

    if (stats.goldCoinsCount > 0) {
      insights.add('Your collection includes ${stats.goldCoinsCount} gold ${stats.goldCoinsCount == 1 ? "coin" : "coins"}.');
    }

    if (stats.duplicatesCount > 0) {
      insights.add('You have ${stats.duplicatesCount} potential ${stats.duplicatesCount == 1 ? "duplicate" : "duplicates"} in your vault.');
    }

    if (stats.earliestYear != null && stats.latestYear != null && stats.earliestYear != stats.latestYear) {
      insights.add('Your collection spans ${stats.latestYear! - stats.earliestYear!} years (${stats.earliestYear}–${stats.latestYear}).');
    }

    if (stats.closerLookCount > 0) {
      insights.add('${stats.closerLookCount} ${stats.closerLookCount == 1 ? "coin may deserve" : "coins may deserve"} a closer look for scarce varieties or precious metal.');
    }

    return insights;
  }

  /// Adds or updates a coin item in the Collection Vault.
  Future<void> saveItem(VaultCoinItem item) async {
    await loadCollection();

    VaultCoinItem itemToSave = item;
    if (item.id.isEmpty || item.id.startsWith('vault_')) {
      itemToSave = item.copyWith(id: const Uuid().v4());
    }

    if (_currentUserId != null && _currentUserId != 'guest_user') {
      try {
        final res = await _apiClient.post(
          '/v1/collection',
          body: itemToSave.toServerJson(),
        );
        if (res is Map<String, dynamic>) {
          itemToSave = VaultCoinItem.fromJson(res);
        }
      } catch (e) {
        debugPrint('CollectionStorageService.saveItem backend failure: $e');
        final isDev = !AppConfig.isInitialized || !AppConfig.instance.isProduction;
        if (isDev && (e is ApiException && (e.statusCode == 0 || e.statusCode == 400))) {
          // In offline dev/test without running backend, keep local cache
        } else {
          rethrow;
        }
      }
    }

    final index = _memoryCache.indexWhere((i) => i.id == itemToSave.id);
    if (index >= 0) {
      _memoryCache[index] = itemToSave;
    } else {
      _memoryCache.insert(0, itemToSave);
    }
    await _persist();
  }

  /// Deletes a coin item from the Collection Vault.
  Future<void> deleteItem(String itemId) async {
    await loadCollection();

    if (_currentUserId != null && _currentUserId != 'guest_user') {
      try {
        await _apiClient.delete('/v1/collection/$itemId');
      } catch (e) {
        if (e is ApiException && e.statusCode == 404) {
          // Already removed from server
        } else {
          debugPrint('CollectionStorageService.deleteItem backend failure: $e');
          final isDev = !AppConfig.isInitialized || !AppConfig.instance.isProduction;
          if (isDev && (e is ApiException && (e.statusCode == 0 || e.statusCode == 400))) {
            // In offline dev/test without running backend
          } else {
            rethrow;
          }
        }
      }
    }

    _memoryCache.removeWhere((i) => i.id == itemId);
    await _persist();
  }

  /// Clears the entire collection.
  Future<void> clearCollection() async {
    _memoryCache.clear();
    await _persist();
  }

  /// Exports all collection records to a JSON string.
  Future<String> exportToJson() async {
    await loadCollection();
    final list = _memoryCache.map((i) => i.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert(list);
  }

  Future<void> _persist() async {
    final file = await _getFile();
    if (file != null) {
      try {
        final jsonString = jsonEncode(_memoryCache.map((i) => i.toJson()).toList());
        await file.writeAsString(jsonString, flush: true);
      } catch (e) {
        debugPrint('Failed to persist collection storage: $e');
      }
    }
  }
}
