/// Unified AI domain models. Pure data, no networking, no UI.
/// Both [LocalAiProvider] and [CloudAiProvider] speak this language;
/// the UI never sees provider-specific types.
library;

/// Which backend answers the user. Switchable at any time without
/// touching conversation history or health data.
enum AiMode { local, cloud }

extension AiModeX on AiMode {
  String get label => this == AiMode.local ? 'Local AI' : 'Cloud AI';

  static AiMode fromWire(String? raw) =>
      raw == 'cloud' ? AiMode.cloud : AiMode.local;
}

/// Cloud backends the user can configure. New providers are added here
/// plus one branch in [CloudAiProvider] — the chatbot UI never changes.
enum CloudProviderKind { openAI, gemini, custom }

extension CloudProviderKindX on CloudProviderKind {
  String get label => switch (this) {
        CloudProviderKind.openAI => 'OpenAI',
        CloudProviderKind.gemini => 'Google Gemini',
        CloudProviderKind.custom => 'Custom OpenAI-Compatible',
      };

  String get wire => name;

  static CloudProviderKind fromWire(String? raw) => switch (raw) {
        'openAI' => CloudProviderKind.openAI,
        'gemini' => CloudProviderKind.gemini,
        'custom' => CloudProviderKind.custom,
        _ => CloudProviderKind.gemini,
      };
}

enum AiRole { system, user, assistant }

extension AiRoleX on AiRole {
  String get wire => name;

  static AiRole fromWire(String? raw) => switch (raw) {
        'system' => AiRole.system,
        'assistant' => AiRole.assistant,
        _ => AiRole.user,
      };
}

class AiMessage {
  final AiRole role;
  final String content;
  const AiMessage({required this.role, required this.content});

  Map<String, dynamic> toWire() =>
      {'role': role.wire, 'content': content};
}

class AiModel {
  final String id;
  final String? ownedBy;
  const AiModel({required this.id, this.ownedBy});

  /// Friendly display name: strips path/extension noise but the request
  /// always uses the intact [id].
  String get displayName {
    var n = id.startsWith('models/') ? id.substring(7) : id;
    final slash = n.lastIndexOf('/');
    if (slash >= 0 && slash < n.length - 1) {
      n = n.substring(slash + 1);
    }
    for (final ext in ['.gguf', '.bin']) {
      if (n.toLowerCase().endsWith(ext)) {
        n = n.substring(0, n.length - ext.length);
      }
    }
    return n.replaceAll('_', ' ').replaceAll('-', ' ').trim();
  }
}

/// Lifecycle of a provider instance.
enum AiProviderStatus { idle, initializing, ready, unavailable, error }

/// Result of a real connection probe. A configured URL is never treated
/// as a successful connection — only a live server response counts.
class AiConnectionResult {
  final bool ok;
  final int? latencyMs;
  final int modelCount;
  final String? activeModelId;
  final String? error;
  final DateTime checkedAt;

  const AiConnectionResult({
    required this.ok,
    required this.checkedAt,
    this.latencyMs,
    this.modelCount = 0,
    this.activeModelId,
    this.error,
  });
}

/// One streamed generation chunk. [done] marks the final frame.
class AiResponseChunk {
  final String text;
  final bool done;
  const AiResponseChunk(this.text, {this.done = false});
}

class AiGenerationOptions {
  final double temperature;
  final int maxTokens;
  final double topP;
  const AiGenerationOptions({
    required this.temperature,
    required this.maxTokens,
    required this.topP,
  });
}

/// UI-visible state of the active turn. The chat list behaves correctly
/// in every state (input locked while sending/streaming, Stop offered,
/// Retry offered after failure).
enum AiTurnState { idle, sending, streaming, completed, cancelled, failed }

/// One-shot explicit attachment (journal entry or document). Exists only
/// because the user confirmed it, used for the next message only — never
/// stored, never reused silently.
class PendingAttachment {
  final String kind; // 'journal' | 'document'
  final String label;
  final String content;
  const PendingAttachment({
    required this.kind,
    required this.label,
    required this.content,
  });
}

/// Failure kinds for provider errors. Only safe, user-mappable detail
/// ever leaves the provider layer — never request bodies, never keys.
enum AiFailureKind {
  unreachable,
  unauthorized,
  modelMissing,
  timeout,
  empty,
  cancelled,
  tooLong,
  malformed,
}

class AiProviderException implements Exception {
  final AiFailureKind kind;
  final String detail;
  const AiProviderException(this.kind, [this.detail = '']);

  String get friendly {
    switch (kind) {
      case AiFailureKind.unreachable:
        return AiErrors.serverUnreachable;
      case AiFailureKind.unauthorized:
        return AiErrors.unauthorized;
      case AiFailureKind.modelMissing:
        return AiErrors.modelUnavailable;
      case AiFailureKind.timeout:
        return AiErrors.timeout;
      case AiFailureKind.empty:
        return AiErrors.empty;
      case AiFailureKind.cancelled:
        return '';
      case AiFailureKind.tooLong:
        return AiErrors.tooLong;
      case AiFailureKind.malformed:
        return AiErrors.generation;
    }
  }
}

/// User-facing strings. Never raw stack traces, never secrets.
class AiErrors {
  static const serverUnreachable =
      "Couldn't reach the AI server. Check the URL and that the server is running.";
  static const localUnavailable =
      'Local AI server is unavailable. Start your local AI server and try again.';
  static const cloudUnavailable =
      'Cloud AI could not respond. Check your connection, API key, and model, then try again.';
  static const unauthorized =
      'The API key was rejected. Check the key and try again.';
  static const missingKey =
      'No API key saved for this cloud provider yet. Add one in Settings → SoulCare AI.';
  static const modelUnavailable =
      "The configured model isn't available on the server.";
  static const timeout = 'The AI took too long to respond.';
  static const empty = 'No response was generated.';
  static const generation =
      'Something went wrong while generating the response.';
  static const tooLong =
      'That message is too long for the current model. Try shortening it or asking one part at a time.';
}
