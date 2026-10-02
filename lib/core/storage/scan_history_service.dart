import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../network/api_client.dart';
import '../recognition/recognition_models.dart';

/// A persisted scan record for the user's history.
class ScanRecord {
  final String id;
  final DateTime scannedAt;
  final String? frontImagePath;
  final String? reverseImagePath;
  final String? coinName;
  final String? country;
  final String? denomination;
  final String? year;
  final double? confidenceScore;
  final String? numistaNumber;
  final String? statusLabel;

  const ScanRecord({
    required this.id,
    required this.scannedAt,
    this.frontImagePath,
    this.reverseImagePath,
    this.coinName,
    this.country,
    this.denomination,
    this.year,
    this.confidenceScore,
    this.numistaNumber,
    this.statusLabel,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'scannedAt': scannedAt.toIso8601String(),
    if (frontImagePath != null) 'frontImagePath': frontImagePath,
    if (reverseImagePath != null) 'reverseImagePath': reverseImagePath,
    if (coinName != null) 'coinName': coinName,
    if (country != null) 'country': country,
    if (denomination != null) 'denomination': denomination,
    if (year != null) 'year': year,
    if (confidenceScore != null) 'confidenceScore': confidenceScore,
    if (numistaNumber != null) 'numistaNumber': numistaNumber,
    if (statusLabel != null) 'statusLabel': statusLabel,
  };

  factory ScanRecord.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate = DateTime.now();
    if (json['scanned_at'] != null) {
      if (json['scanned_at'] is num) {
        parsedDate = DateTime.fromMillisecondsSinceEpoch(
          ((json['scanned_at'] as num) * 1000).toInt(),
        );
      } else {
        parsedDate =
            DateTime.tryParse(json['scanned_at'].toString()) ?? DateTime.now();
      }
    } else if (json['scannedAt'] != null) {
      parsedDate =
          DateTime.tryParse(json['scannedAt'].toString()) ?? DateTime.now();
    }

    return ScanRecord(
      id: json['id']?.toString() ??
          'scan_${DateTime.now().millisecondsSinceEpoch}',
      scannedAt: parsedDate,
      frontImagePath: (json['front_image_url'] ?? json['frontImagePath']) as String?,
      reverseImagePath: (json['reverse_image_url'] ?? json['reverseImagePath']) as String?,
      coinName: (json['coin_name'] ?? json['coinName']) as String?,
      country: json['country'] as String?,
      denomination: json['denomination'] as String?,
      year: json['year']?.toString(),
      confidenceScore: ((json['confidence_score'] ?? json['confidenceScore']) as num?)?.toDouble(),
      numistaNumber: (json['numista_id'] ?? json['numistaNumber'])?.toString(),
      statusLabel: (json['status_label'] ?? json['statusLabel']) as String?,
    );
  }

  /// Create a ScanRecord from a RecognitionResult.
  factory ScanRecord.fromRecognitionResult({
    required String id,
    required RecognitionResult result,
    String? frontImagePath,
    String? reverseImagePath,
  }) {
    final primary = result.candidates.isNotEmpty ? result.candidates.first : null;
    final identity = primary?.identity;
    final coinTitle = identity != null
        ? '${identity.year != null ? "${identity.year} " : ""}${identity.country} ${identity.denomination}'.trim()
        : null;

    return ScanRecord(
      id: id,
      scannedAt: DateTime.now(),
      frontImagePath: frontImagePath,
      reverseImagePath: reverseImagePath,
      coinName: coinTitle?.isNotEmpty == true ? coinTitle : null,
      country: identity?.country,
      denomination: identity?.denomination,
      year: identity?.year?.toString(),
      confidenceScore: primary?.confidence?.overallScore,
      numistaNumber: identity?.numistaId?.toString(),
      statusLabel: result.status.name,
    );
  }
}

/// JSON file-based scan history persistence.
///
/// Uses `path_provider` (already in pubspec) to store scan records
/// as a JSON array in the app's documents directory.
///
/// For a production app with thousands of records, migrate to SQLite
/// via the `sqflite` package.
class ScanHistoryService {
  static final ScanHistoryService instance = ScanHistoryService();
  final ApiClient? _explicitApiClient;
  String? _currentUserId;
  List<ScanRecord>? _cache;

  ScanHistoryService({ApiClient? apiClient}) : _explicitApiClient = apiClient;

  ApiClient get _apiClient => _explicitApiClient ?? ApiClient.instance;

  /// Sets the currently active user ID to ensure scan history isolation.
  void setCurrentUser(String? userId) {
    if (_currentUserId != userId) {
      _currentUserId = userId;
      resetForUserSwitch();
    }
  }

  /// Clears in-memory history cache on account switch.
  void resetForUserSwitch() {
    _cache = null;
  }

  /// Deletes the signed-out (guest) scan history file, if any. Account history
  /// files are untouched. Guest history is local-only and is never migrated
  /// into an account.
  Future<void> clearGuestData() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/scan_history.json');
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Could not clear guest scan history: $e');
    }
    if (_currentUserId == null) resetForUserSwitch();
  }

  String get _fileName {
    final uid = _currentUserId;
    if (uid != null && uid.isNotEmpty) {
      final safeUid = uid.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      return 'scan_history_$safeUid.json';
    }
    return 'scan_history.json';
  }

  /// Synchronous count of cached scan records. Returns 0 if not yet loaded.
  int get cachedRecordCount => _cache?.length ?? 0;

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
    if (file == null || !await file.exists()) {
      _cache ??= [];
      return;
    }

    try {
      final content = await file.readAsString();
      final dynamic decoded = jsonDecode(content);
      final validRecords = <ScanRecord>[];
      if (decoded is List) {
        for (final item in decoded) {
          try {
            if (item is Map<String, dynamic>) {
              validRecords.add(ScanRecord.fromJson(item));
            }
          } catch (itemError) {
            debugPrint('Skipping malformed scan history record: $itemError');
          }
        }
      }
      validRecords.sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
      _cache = validRecords;
    } catch (e) {
      debugPrint('ScanHistoryService._loadFromLocalFile error: $e');
      try {
        final backup = File('${file.path}.corrupted_${DateTime.now().millisecondsSinceEpoch}.bak');
        await file.copy(backup.path);
        debugPrint('Created corrupted scan history backup at ${backup.path}');
      } catch (_) {}
      _cache ??= [];
    }
  }

  /// Load all scan records, most recent first.
  /// Authenticated users sync authoritative records from GET /v1/account/history.
  Future<List<ScanRecord>> loadHistory({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) return List.unmodifiable(_cache!);

    await _loadFromLocalFile();

    if (_currentUserId != null && _currentUserId != 'guest_user') {
      try {
        final res = await _apiClient.get('/v1/account/history');
        if (res is List) {
          final serverRecords = <ScanRecord>[];
          for (final raw in res) {
            if (raw is Map<String, dynamic>) {
              serverRecords.add(ScanRecord.fromJson(raw));
            }
          }
          serverRecords.sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
          _cache = serverRecords;
          await _persist();
        }
      } catch (e) {
        debugPrint('Warning: Could not sync scan history from backend: $e');
        if ((_cache == null || _cache!.isEmpty) &&
            AppConfig.isInitialized &&
            AppConfig.instance.isProduction) {
          rethrow;
        }
      }
    }

    _cache ??= [];
    return List.unmodifiable(_cache!);
  }

  /// Save a new scan record.
  Future<void> addRecord(ScanRecord record) async {
    if (kIsWeb) return;

    final records = _cache ?? await loadHistory();
    _cache = [record, ...records];
    await _persist();
  }

  /// Delete a scan record by ID.
  Future<void> deleteRecord(String id) async {
    if (kIsWeb) return;

    final records = _cache ?? await loadHistory();
    _cache = records.where((r) => r.id != id).toList();
    await _persist();
  }

  /// Clear all scan history.
  Future<void> clearHistory() async {
    if (kIsWeb) return;

    _cache = [];
    await _persist();
  }

  /// Get the total number of scan records.
  Future<int> get recordCount async {
    final records = _cache ?? await loadHistory();
    return records.length;
  }

  /// Export all scan history records to a JSON string.
  Future<String> exportToJson() async {
    final records = await loadHistory();
    final list = records.map((r) => r.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert(list);
  }

  Future<void> _persist() async {
    try {
      final file = await _getFile();
      if (file == null) return;
      final jsonStr = jsonEncode(_cache!.map((r) => r.toJson()).toList());
      await file.writeAsString(jsonStr);
    } catch (e) {
      debugPrint('ScanHistoryService._persist error: $e');
    }
  }
}
