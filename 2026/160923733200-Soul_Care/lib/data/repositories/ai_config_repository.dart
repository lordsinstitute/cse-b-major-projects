import '../../core/ai/ai_config.dart';
import '../../core/ai/ai_models.dart';
import '../../core/ai/ai_secure_store.dart';
import '../../core/errors/app_exceptions.dart';
import '../local/local_database.dart';

/// Persists AI configuration inside the settings box (one JSON record).
/// Cloud API keys are NOT part of the config — they live only in
/// [AiSecureStore] (platform-backed secure storage).
class AiConfigRepository {
  static const _key = 'ai_config';

  final AiSecureStore _secure;

  AiConfigRepository({AiSecureStore? secure})
      : _secure = secure ?? AiSecureStore();

  AiSecureStore get secure => _secure;

  Future<Result<AiConfig>> load() async {
    try {
      final raw = LocalDatabase.settingsBox.get(_key);
      if (raw == null) return Success(const AiConfig());
      final config = AiConfig.fromJson(
          Map<String, dynamic>.from(raw as Map));
      return Success(config);
    } catch (e) {
      return Failure(PersistenceException(
          'Could not load AI settings. Using defaults.',
          originalError: e));
    }
  }

  Future<Result<AiConfig>> save(AiConfig config) async {
    try {
      final local = config.local.copyWith(
          serverUrl: normalizeServerUrl(config.local.serverUrl));
      if (validateServerUrl(local.serverUrl) != null) {
        return const Failure(
            ValidationException('That server URL is invalid.'));
      }
      final cloud = config.cloud.copyWith(
          endpoint: normalizeServerUrl(config.cloud.endpoint));
      final normalized =
          config.copyWith(local: local, cloud: cloud);
      await LocalDatabase.settingsBox.put(_key, normalized.toJson());
      return Success(normalized);
    } catch (e) {
      return Failure(PersistenceException(
          'Could not save AI settings.', originalError: e));
    }
  }

  // ---- Secure cloud credentials (never in Hive, never logged) ----

  Future<String?> readCloudKey(CloudProviderKind kind) =>
      _secure.readKey(kind);

  Future<bool> hasCloudKey(CloudProviderKind kind) =>
      _secure.hasKey(kind);

  Future<String> maskedCloudKey(CloudProviderKind kind) =>
      _secure.maskedKey(kind);

  Future<Result<void>> saveCloudKey(
      CloudProviderKind kind, String key) async {
    try {
      if (key.trim().isEmpty) {
        return const Failure(
            ValidationException('Enter an API key.'));
      }
      await _secure.writeKey(kind, key);
      return const Success(null);
    } catch (e) {
      return Failure(PersistenceException(
          'Could not save the API key securely.',
          originalError: e));
    }
  }

  Future<Result<void>> deleteCloudKey(CloudProviderKind kind) async {
    try {
      await _secure.deleteKey(kind);
      return const Success(null);
    } catch (e) {
      return Failure(PersistenceException(
          'Could not remove the API key.', originalError: e));
    }
  }
}
