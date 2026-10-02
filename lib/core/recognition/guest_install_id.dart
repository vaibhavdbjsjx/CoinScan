import 'package:uuid/uuid.dart';

import '../storage/secure_storage_service.dart';

/// Random identifier for this app installation, sent only with signed-out
/// (guest) scan requests as the `X-CoinScan-Install-ID` header.
///
/// It is a rate-limit hint for the server's guest allowance, never an
/// identity: it is not linked to any account, it is never sent with a
/// signed-in request, and the server stores only a keyed hash of it.
class GuestInstallId {
  static const String header = 'X-CoinScan-Install-ID';
  static const String storageKey = 'coinscan_install_id';

  static final GuestInstallId instance = GuestInstallId();

  final SecureStorageService _storage;
  Future<String>? _value;

  GuestInstallId({SecureStorageService? storage})
    : _storage = storage ?? PersistentSecureStorageService();

  /// The stored install ID, created on first use.
  Future<String> value() => _value ??= _loadOrCreate();

  Future<String> _loadOrCreate() async {
    try {
      final stored = await _storage.read(key: storageKey);
      if (stored != null && Uuid.isValidUUID(fromString: stored)) return stored;
    } catch (_) {
      // Unreadable storage: fall through and use a fresh ID.
    }
    final created = const Uuid().v4();
    try {
      await _storage.write(key: storageKey, value: created);
    } catch (_) {
      // Not persisted: the ID still works for this session.
    }
    return created;
  }
}
