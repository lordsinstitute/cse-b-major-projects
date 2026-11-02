import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_config.dart';
import 'ai_models.dart';
import 'ai_provider.dart';
import 'openai_compat_client.dart';

/// Cloud backend using the user's own API credentials.
/// No keys are hardcoded and none are logged: the key arrives per call
/// from secure storage (via [apiKeyOf]) and travels only in the
/// transport's auth mechanism.
///
/// Supported transports:
/// - [CloudProviderKind.openAI] / [CloudProviderKind.custom]:
///   OpenAI-compatible `/models` + SSE `/chat/completions`.
/// - [CloudProviderKind.gemini]: Google AI REST `v1beta`
///   (`GET /v1beta/models`, `POST :streamGenerateContent` with SSE).
///   Current official REST surface; no SDK required.
class CloudAiProvider implements AiProvider {
  final AiConfig Function() configOf;
  final Future<String?> Function() apiKeyOf;
  late final OpenAiCompatClient _openAi;

  http.Client? _geminiClient;
  bool _geminiCancelled = false;

  CloudAiProvider({
    required this.configOf,
    required this.apiKeyOf,
  }) {
    final cfg = configOf;
    final key = apiKeyOf;
    _openAi = OpenAiCompatClient(
      baseUrlOf: () => cfg().cloud.endpoint,
      headersOf: () => {'Content-Type': 'application/json'},
      extraHeadersOf: () async {
        final k = await key();
        return k == null || k.isEmpty
            ? const <String, String>{}
            : {'Authorization': 'Bearer $k'};
      },
      connectTimeoutOf: () => cfg().cloud.connectTimeout,
      requestTimeoutOf: () => cfg().cloud.requestTimeout,
      streamIdleTimeoutOf: () => cfg().cloud.streamIdleTimeout,
    );
  }

  CloudProviderKind get kind => configOf().cloud.provider;

  @override
  String get providerLabel => 'Cloud · ${kind.label}';

  @override
  bool get isLocal => false;

  @override
  Future<AiProviderStatus> initialize() async {
    final key = await apiKeyOf();
    if (key == null || key.isEmpty) {
      return AiProviderStatus.unavailable;
    }
    final result = await testConnection();
    return result.ok
        ? AiProviderStatus.ready
        : AiProviderStatus.unavailable;
  }

  @override
  Future<AiConnectionResult> testConnection() async {
    final started = DateTime.now();
    final key = await apiKeyOf();
    if (key == null || key.isEmpty) {
      return AiConnectionResult(
        ok: false,
        checkedAt: DateTime.now(),
        latencyMs:
            DateTime.now().difference(started).inMilliseconds,
        error: AiErrors.missingKey,
      );
    }
    try {
      final models = await getModels();
      final active = _resolveActive(models);
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
            ? AiErrors.cloudUnavailable
            : e.friendly,
      );
    } catch (_) {
      return AiConnectionResult(
        ok: false,
        checkedAt: DateTime.now(),
        latencyMs:
            DateTime.now().difference(started).inMilliseconds,
        error: AiErrors.cloudUnavailable,
      );
    }
  }

  @override
  Future<List<AiModel>> getModels() async {
    if (kind == CloudProviderKind.gemini) {
      return _geminiModels(await _requireKey());
    }
    return _openAi.fetchModels();
  }

  AiModel? _resolveActive(List<AiModel> models) {
    if (models.isEmpty) return null;
    final preferred = configOf().cloud.model.trim();
    if (preferred.isNotEmpty) {
      for (final m in models) {
        if (m.id == preferred ||
            m.id == 'models/$preferred' ||
            m.id.endsWith('/$preferred')) {
          return m;
        }
      }
    }
    return models.first;
  }

  @override
  Stream<AiResponseChunk> generateResponse({
    required List<AiMessage> messages,
    required AiGenerationOptions options,
  }) async* {
    final key = await apiKeyOf();
    if (key == null || key.isEmpty) {
      throw const AiProviderException(AiFailureKind.unauthorized);
    }
    if (kind == CloudProviderKind.gemini) {
      yield* _geminiStream(
          key: key, messages: messages, options: options);
      return;
    }
    final models = await _openAi.fetchModels();
    final active = _resolveActive(models);
    if (active == null) {
      throw const AiProviderException(AiFailureKind.modelMissing);
    }
    yield* _openAi
        .streamChat(model: active.id, messages: messages, options: options);
  }

  Future<String> _requireKey() async {
    final key = await apiKeyOf();
    if (key == null || key.isEmpty) {
      throw const AiProviderException(AiFailureKind.unauthorized);
    }
    return key;
  }

  String get _geminiBase =>
      configOf().cloud.endpoint.trim().replaceAll(RegExp(r'/+$'), '');

  Future<List<AiModel>> _geminiModels(String key) async {
    final uri = Uri.parse('$_geminiBase/models?key=$key');
    http.Response res;
    try {
      res = await http
          .get(uri)
          .timeout(configOf().cloud.connectTimeout);
    } on TimeoutException {
      throw const AiProviderException(AiFailureKind.timeout);
    } catch (_) {
      throw const AiProviderException(AiFailureKind.unreachable);
    }
    if (res.statusCode == 400 ||
        res.statusCode == 401 ||
        res.statusCode == 403) {
      throw const AiProviderException(AiFailureKind.unauthorized);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AiProviderException(
          AiFailureKind.unreachable, 'HTTP ${res.statusCode}');
    }
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = body['models'];
      if (data is! List) {
        throw const AiProviderException(AiFailureKind.malformed);
      }
      return [
        for (final m in data)
          if (m is Map && (m['name']?.toString() ?? '').isNotEmpty)
            AiModel(id: m['name'].toString()),
      ];
    } catch (e) {
      if (e is AiProviderException) rethrow;
      throw const AiProviderException(AiFailureKind.malformed);
    }
  }

  /// Gemini streaming generation over REST SSE.
  Stream<AiResponseChunk> _geminiStream({
    required String key,
    required List<AiMessage> messages,
    required AiGenerationOptions options,
  }) async* {
    if (messages.isEmpty ||
        messages.every((m) => m.content.trim().isEmpty)) {
      throw const AiProviderException(AiFailureKind.empty);
    }
    final totalChars =
        messages.fold(0, (n, m) => n + m.content.length);
    if (totalChars > 60000) {
      throw const AiProviderException(AiFailureKind.tooLong);
    }
    _geminiCancelled = false;
    _geminiClient?.close();
    _geminiClient = http.Client();
    final configured = configOf().cloud.model.trim();
    final model =
        configured.isEmpty ? 'gemini-2.0-flash' : configured;
    final uri = Uri.parse(
        '$_geminiBase/models/$model:streamGenerateContent?alt=sse&key=$key');
    final payload = {
      'system_instruction': {
        'parts': [
          {
            'text': messages
                .where((m) => m.role == AiRole.system)
                .map((m) => m.content)
                .join('\n\n')
          },
        ],
      },
      'contents': [
        for (final m in messages)
          if (m.role != AiRole.system)
            {
              'role': m.role == AiRole.assistant
                  ? 'model'
                  : 'user',
              'parts': [
                {'text': m.content}
              ],
            },
      ],
      'generationConfig': {
        'temperature': options.temperature,
        'maxOutputTokens': options.maxTokens,
        'topP': options.topP,
      },
    };
    http.StreamedResponse res;
    try {
      final req = http.Request('POST', uri)
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(payload);
      res = await _geminiClient!
          .send(req)
          .timeout(configOf().cloud.requestTimeout);
    } on TimeoutException {
      throw const AiProviderException(AiFailureKind.timeout);
    } catch (_) {
      if (_geminiCancelled) {
        throw const AiProviderException(AiFailureKind.cancelled);
      }
      throw const AiProviderException(AiFailureKind.unreachable);
    }
    if (res.statusCode == 400 ||
        res.statusCode == 401 ||
        res.statusCode == 403) {
      throw const AiProviderException(AiFailureKind.unauthorized);
    }
    if (res.statusCode == 404) {
      throw const AiProviderException(AiFailureKind.modelMissing);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AiProviderException(
          AiFailureKind.unreachable, 'HTTP ${res.statusCode}');
    }
    var emitted = false;
    try {
      final lines = res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(configOf().cloud.streamIdleTimeout,
              onTimeout: (sink) {
        sink.addError(_geminiCancelled
            ? const AiProviderException(AiFailureKind.cancelled)
            : const AiProviderException(
                AiFailureKind.timeout, 'stream went quiet'));
        sink.close();
      }).takeWhile((_) => !_geminiCancelled);
      await for (final line in lines) {
        if (_geminiCancelled) break;
        final t = line.trim();
        if (!t.startsWith('data:')) continue;
        final data = t.substring(5).trim();
        if (data == '[DONE]') break;
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final candidates = json['candidates'];
          if (candidates is List) {
            for (final c in candidates) {
              final content = (c as Map?)?['content'];
              final parts = (content as Map?)?['parts'];
              if (parts is List) {
                for (final p in parts) {
                  final text = (p as Map?)?['text'];
                  if (text is String && text.isNotEmpty) {
                    emitted = true;
                    yield AiResponseChunk(text);
                  }
                }
              }
            }
          }
        } catch (_) {
          continue;
        }
      }
    } on AiProviderException {
      rethrow;
    } catch (_) {
      if (_geminiCancelled) return;
      throw const AiProviderException(AiFailureKind.unreachable);
    } finally {
      try {
        _geminiClient?.close();
      } catch (_) {}
      _geminiClient = null;
    }
    if (_geminiCancelled) return;
    if (!emitted) {
      throw const AiProviderException(AiFailureKind.empty);
    }
    yield const AiResponseChunk('', done: true);
  }

  @override
  Future<void> cancelGeneration() async {
    await _openAi.cancel();
    _geminiCancelled = true;
    try {
      _geminiClient?.close();
    } catch (_) {}
    _geminiClient = null;
  }

  @override
  Future<void> dispose() async {
    _openAi.dispose();
    _geminiCancelled = true;
    try {
      _geminiClient?.close();
    } catch (_) {}
    _geminiClient = null;
  }
}
