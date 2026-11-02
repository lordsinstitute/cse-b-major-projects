import 'ai_config.dart';
import 'ai_models.dart';
import 'ai_provider.dart';
import 'openai_compat_client.dart';

/// Local backend: the user's own OpenAI-compatible LLM server
/// (llama.cpp, typically serving Gemma) on loopback or LAN.
///
/// Inference never requires internet and never touches a cloud API:
/// this class only ever talks to the configured server URL.
class LocalAiProvider implements AiProvider {
  final AiConfig Function() configOf;
  late final OpenAiCompatClient _client;

  LocalAiProvider({required this.configOf}) {
    final cfg = configOf;
    _client = OpenAiCompatClient(
      baseUrlOf: () => cfg().local.serverUrl,
      headersOf: () {
        final headers = {'Content-Type': 'application/json'};
        final key = cfg().local.apiKey;
        if (key != null && key.isNotEmpty) {
          headers['Authorization'] = 'Bearer $key';
        }
        return headers;
      },
      connectTimeoutOf: () => cfg().local.connectTimeout,
      requestTimeoutOf: () => cfg().local.requestTimeout,
      streamIdleTimeoutOf: () => cfg().local.streamIdleTimeout,
    );
  }

  @override
  String get providerLabel => 'Local';

  @override
  bool get isLocal => true;

  @override
  Future<AiProviderStatus> initialize() async {
    final result = await testConnection();
    return result.ok
        ? AiProviderStatus.ready
        : AiProviderStatus.unavailable;
  }

  @override
  Future<AiConnectionResult> testConnection() async {
    final started = DateTime.now();
    try {
      final models = await _client.fetchModels();
      final active = resolveActiveModel(models);
      return AiConnectionResult(
        ok: true,
        checkedAt: DateTime.now(),
        latencyMs:
            DateTime.now().difference(started).inMilliseconds,
        modelCount: models.length,
        activeModelId: active?.id,
      );
    } on AiProviderException catch (e) {
      return AiConnectionResult(
        ok: false,
        checkedAt: DateTime.now(),
        latencyMs:
            DateTime.now().difference(started).inMilliseconds,
        error: e.friendly.isEmpty
            ? AiErrors.serverUnreachable
            : e.friendly,
      );
    } catch (_) {
      return AiConnectionResult(
        ok: false,
        checkedAt: DateTime.now(),
        latencyMs:
            DateTime.now().difference(started).inMilliseconds,
        error: AiErrors.serverUnreachable,
      );
    }
  }

  @override
  Future<List<AiModel>> getModels() => _client.fetchModels();

  /// Preferred configured model when the server still lists it;
  /// otherwise the single model, otherwise the first listed.
  /// Model ids always come from `/v1/models` — never hardcoded.
  AiModel? resolveActiveModel(List<AiModel> models) {
    if (models.isEmpty) return null;
    final preferred = configOf().local.activeModelId;
    if (preferred != null) {
      for (final m in models) {
        if (m.id == preferred) return m;
      }
    }
    return models.first;
  }

  Future<AiModel?> getActiveModel() async {
    try {
      return resolveActiveModel(await _client.fetchModels());
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<AiResponseChunk> generateResponse({
    required List<AiMessage> messages,
    required AiGenerationOptions options,
  }) async* {
    final model = await getActiveModel();
    if (model == null) {
      throw const AiProviderException(AiFailureKind.modelMissing);
    }
    yield* _client.streamChat(
        model: model.id, messages: messages, options: options);
  }

  @override
  Future<void> cancelGeneration() => _client.cancel();

  @override
  Future<void> dispose() async => _client.dispose();
}
