import 'ai_models.dart';

/// Common contract every AI backend implements. The chatbot UI and the
/// [SoulCareAiService] talk only to this — never to HTTP, API keys, or
/// model-specific APIs directly.
abstract class AiProvider {
  /// Short honest label for the provider indicator, e.g.
  /// `Local · gemma 4 e2b it` or `Cloud · Google Gemini`.
  String get providerLabel;

  /// `true` when inference stays on this device with no cloud involved.
  bool get isLocal;

  /// Prepares the provider (reads config, warms clients). Cheap and
  /// idempotent; real connectivity is proven by [testConnection].
  Future<AiProviderStatus> initialize();

  /// Probes the backend for real: lists models, identifies the active
  /// one, measures latency. Never reports success without a response.
  Future<AiConnectionResult> testConnection();

  /// Models the backend currently offers. Ids always come from the
  /// server — never hardcoded.
  Future<List<AiModel>> getModels();

  /// Streams a response for [messages] with [options]. Throws only
  /// [AiProviderException] with user-mappable messages.
  Stream<AiResponseChunk> generateResponse({
    required List<AiMessage> messages,
    required AiGenerationOptions options,
  });

  /// Cancels an in-flight generation. Already-streamed text is kept by
  /// the caller; the stream simply ends.
  Future<void> cancelGeneration();

  Future<void> dispose();
}
