import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai_models.dart';

/// Platform-backed secure credential store for cloud API keys.
/// Android: EncryptedSharedPreferences (AES via Android Keystore).
/// Keys never touch source code, SharedPreferences, Hive, chat history,
/// logs, analytics, or exports — only this store.
class AiSecureStore {
  static const _prefix = 'soulcare_cloud_key_';

  final CloudKeyStore _store;

  AiSecureStore({CloudKeyStore? store})
      : _store = store ?? SecureCloudKeyStore();

  String _keyFor(CloudProviderKind kind) => '$_prefix${kind.wire}';

  Future<String?> readKey(CloudProviderKind kind) =>
      _store.read(_keyFor(kind));

  Future<void> writeKey(CloudProviderKind kind, String key) =>
      _store.write(_keyFor(kind), key.trim());

  Future<void> deleteKey(CloudProviderKind kind) =>
      _store.delete(_keyFor(kind));

  Future<bool> hasKey(CloudProviderKind kind) async {
    final v = await readKey(kind);
    return v != null && v.trim().isNotEmpty;
  }

  /// Masked display form, e.g. `sk-••••••••8F3A`. The full key is never
  /// returned for display purposes.
  Future<String> maskedKey(CloudProviderKind kind) async {
    final v = (await readKey(kind) ?? '').trim();
    if (v.isEmpty) return 'Not set';
    final tail = v.length <= 4 ? v : v.substring(v.length - 4);
    final head = v.length > 3 && v[2] == '-' ? '${v[0]}${v[1]}-' : '';
    return '$head••••••••$tail';
  }
}

/// Seam over the platform credential store. Production uses
/// [SecureCloudKeyStore]; tests use [InMemoryCloudKeyStore].
abstract class CloudKeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureCloudKeyStore implements CloudKeyStore {
  final FlutterSecureStorage _storage;

  SecureCloudKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Test-only in-memory key store. Never used in production.
class InMemoryCloudKeyStore implements CloudKeyStore {
  final _map = <String, String>{};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async {
    _map[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _map.remove(key);
  }
}
