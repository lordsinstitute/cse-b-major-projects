import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_models.dart';

/// Shared low-level client for any OpenAI-compatible chat backend
/// (`GET /models`, `POST /chat/completions` with SSE streaming).
/// Used by [LocalAiProvider] (loopback/LAN llama.cpp server) and by
/// [CloudAiProvider] for OpenAI / custom OpenAI-compatible endpoints.
/// The UI never touches this — only providers do.
///
/// Carries no secrets itself: callers supply per-request headers.
/// Nothing sensitive is ever logged.
class OpenAiCompatClient {
  final String Function() baseUrlOf;
  final Map<String, String> Function() headersOf;

  /// Optional async headers (e.g. an API key loaded from secure storage
  /// per call, so rotation never uses a stale cached key).
  final Future<Map<String, String>> Function()? extraHeadersOf;
  final Duration Function() connectTimeoutOf;
  final Duration Function() requestTimeoutOf;
  final Duration Function() streamIdleTimeoutOf;

  http.Client? _streamClient;
  bool _cancelled = false;

  OpenAiCompatClient({
    required this.baseUrlOf,
    required this.headersOf,
    this.extraHeadersOf,
    required this.connectTimeoutOf,
    required this.requestTimeoutOf,
    required this.streamIdleTimeoutOf,
  });

  String get _base =>
      baseUrlOf().trim().replaceAll(RegExp(r'/+$'), '');

  Future<Map<String, String>> _headers() async => {
        ...headersOf(),
        if (extraHeadersOf != null) ...await extraHeadersOf!(),
      };

  Future<List<AiModel>> fetchModels() async {
    final uri = Uri.parse('$_base/models');
    http.Response res;
    try {
      res = await http
          .get(uri, headers: await _headers())
          .timeout(connectTimeoutOf());
    } on TimeoutException {
      throw const AiProviderException(AiFailureKind.timeout);
    } catch (_) {
      throw const AiProviderException(AiFailureKind.unreachable);
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const AiProviderException(AiFailureKind.unauthorized);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AiProviderException(
          AiFailureKind.unreachable, 'HTTP ${res.statusCode}');
    }
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = body['data'];
      if (data is! List) {
        throw const AiProviderException(AiFailureKind.malformed);
      }
      return [
        for (final m in data)
          if (m is Map && (m['id']?.toString() ?? '').isNotEmpty)
            AiModel(
              id: m['id'].toString(),
              ownedBy: m['owned_by']?.toString(),
            ),
      ];
    } catch (e) {
      if (e is AiProviderException) rethrow;
      throw const AiProviderException(AiFailureKind.malformed);
    }
  }

  /// Streams tokens until `[DONE]`, the idle timeout, or cancellation.
  Stream<AiResponseChunk> streamChat({
    required String model,
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
    _cancelled = false;
    _streamClient?.close();
    _streamClient = http.Client();
    final uri = Uri.parse('$_base/chat/completions');
    final payload = {
      'model': model,
      'messages': [for (final m in messages) m.toWire()],
      'temperature': options.temperature,
      'max_tokens': options.maxTokens,
      'top_p': options.topP,
      'stream': true,
    };
    http.StreamedResponse res;
    try {
      final req = http.Request('POST', uri)
        ..headers.addAll(await _headers())
        ..body = jsonEncode(payload);
      res = await _streamClient!
          .send(req)
          .timeout(requestTimeoutOf());
    } on TimeoutException {
      throw const AiProviderException(AiFailureKind.timeout);
    } catch (_) {
      if (_cancelled) {
        throw const AiProviderException(AiFailureKind.cancelled);
      }
      throw const AiProviderException(AiFailureKind.unreachable);
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
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
          .timeout(streamIdleTimeoutOf(), onTimeout: (sink) {
        sink.addError(_cancelled
            ? const AiProviderException(AiFailureKind.cancelled)
            : const AiProviderException(
                AiFailureKind.timeout, 'stream went quiet'));
        sink.close();
      }).takeWhile((_) => !_cancelled);
      await for (final line in lines) {
        if (_cancelled) break;
        final t = line.trim();
        if (!t.startsWith('data:')) continue;
        final data = t.substring(5).trim();
        if (data == '[DONE]') break;
        String? piece;
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'];
          if (choices is List && choices.isNotEmpty) {
            final first = choices.first;
            if (first is Map) {
              final delta = first['delta'];
              if (delta is Map && delta['content'] is String) {
                piece = delta['content'] as String;
              } else if (first['text'] is String) {
                piece = first['text'] as String; // legacy shape
              } else if (first['message'] is Map &&
                  (first['message'] as Map)['content'] is String) {
                piece = (first['message'] as Map)['content']
                    as String; // non-stream fallback
              }
            }
          }
        } catch (_) {
          continue; // skip malformed SSE frames, keep streaming
        }
        if (piece != null && piece.isNotEmpty) {
          emitted = true;
          yield AiResponseChunk(piece);
        }
      }
    } on AiProviderException {
      rethrow;
    } catch (_) {
      if (_cancelled) return;
      throw const AiProviderException(AiFailureKind.unreachable);
    } finally {
      try {
        _streamClient?.close();
      } catch (_) {}
      _streamClient = null;
    }
    if (_cancelled) return;
    if (!emitted) {
      throw const AiProviderException(AiFailureKind.empty);
    }
    yield const AiResponseChunk('', done: true);
  }

  Future<void> cancel() async {
    _cancelled = true;
    try {
      _streamClient?.close();
    } catch (_) {}
    _streamClient = null;
  }

  void dispose() {
    _cancelled = true;
    try {
      _streamClient?.close();
    } catch (_) {}
    _streamClient = null;
  }
}
