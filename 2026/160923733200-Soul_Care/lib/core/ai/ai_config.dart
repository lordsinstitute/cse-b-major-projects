import 'ai_models.dart';

/// Connection settings for the on-device / LAN LLM server.
class LocalAiSettings {
  /// Base URL of the local OpenAI-compatible server, e.g.
  /// `http://127.0.0.1:11434/v1`. Same-device loopback by default.
  final String serverUrl;

  /// Preferred model id (from `/v1/models`). Null = auto-select.
  final String? activeModelId;

  /// Optional key, only if the local server demands auth.
  /// Stored inside the settings box like any local preference:
  /// it never leaves the configured server.
  final String? apiKey;

  final double temperature;
  final int maxTokens;
  final double topP;
  final Duration connectTimeout;
  final Duration requestTimeout;
  final Duration streamIdleTimeout;
  final int contextTurns;
  final Duration statusTtl;

  const LocalAiSettings({
    this.serverUrl = 'http://127.0.0.1:11434/v1',
    this.activeModelId,
    this.apiKey,
    this.temperature = 0.7,
    this.maxTokens = 512,
    this.topP = 0.9,
    this.connectTimeout = const Duration(seconds: 8),
    this.requestTimeout = const Duration(minutes: 3),
    this.streamIdleTimeout = const Duration(seconds: 120),
    this.contextTurns = 6,
    this.statusTtl = const Duration(seconds: 60),
  });

  LocalAiSettings copyWith({
    String? serverUrl,
    String? Function()? activeModelId,
    String? Function()? apiKey,
    double? temperature,
    int? maxTokens,
    double? topP,
    Duration? connectTimeout,
    Duration? requestTimeout,
    Duration? streamIdleTimeout,
    int? contextTurns,
    Duration? statusTtl,
  }) =>
      LocalAiSettings(
        serverUrl: serverUrl ?? this.serverUrl,
        activeModelId:
            activeModelId != null ? activeModelId() : this.activeModelId,
        apiKey: apiKey != null ? apiKey() : this.apiKey,
        temperature: temperature ?? this.temperature,
        maxTokens: maxTokens ?? this.maxTokens,
        topP: topP ?? this.topP,
        connectTimeout: connectTimeout ?? this.connectTimeout,
        requestTimeout: requestTimeout ?? this.requestTimeout,
        streamIdleTimeout:
            streamIdleTimeout ?? this.streamIdleTimeout,
        contextTurns: contextTurns ?? this.contextTurns,
        statusTtl: statusTtl ?? this.statusTtl,
      );

  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl,
        'activeModelId': activeModelId,
        'apiKey': apiKey,
        'temperature': temperature,
        'maxTokens': maxTokens,
        'topP': topP,
        'connectTimeoutMs': connectTimeout.inMilliseconds,
        'requestTimeoutMs': requestTimeout.inMilliseconds,
        'streamIdleTimeoutMs': streamIdleTimeout.inMilliseconds,
        'contextTurns': contextTurns,
        'statusTtlMs': statusTtl.inMilliseconds,
      };

  factory LocalAiSettings.fromJson(Map<String, dynamic> json) {
    double d(String k, double fallback, double lo, double hi) {
      final v = (json[k] as num?)?.toDouble() ?? fallback;
      return v.clamp(lo, hi);
    }

    int i(String k, int fallback, int lo, int hi) {
      final v = (json[k] as num?)?.toInt() ?? fallback;
      return v.clamp(lo, hi);
    }

    Duration dur(String k, Duration fallback) {
      final ms = (json[k] as num?)?.toInt();
      return ms == null
          ? fallback
          : Duration(milliseconds: ms.clamp(1000, 600000));
    }

    String? clean(String? v) =>
        v == null || v.trim().isEmpty ? null : v.trim();
    final rawUrl = (json['serverUrl'] as String?)?.trim();
    return LocalAiSettings(
      serverUrl: rawUrl == null || rawUrl.isEmpty
          ? const LocalAiSettings().serverUrl
          : rawUrl,
      activeModelId: clean(json['activeModelId'] as String?),
      apiKey: clean(json['apiKey'] as String?),
      temperature: d('temperature', 0.7, 0.0, 2.0),
      maxTokens: i('maxTokens', 512, 32, 4096),
      topP: d('topP', 0.9, 0.0, 1.0),
      connectTimeout:
          dur('connectTimeoutMs', const Duration(seconds: 8)),
      requestTimeout:
          dur('requestTimeoutMs', const Duration(minutes: 3)),
      streamIdleTimeout:
          dur('streamIdleTimeoutMs', const Duration(seconds: 120)),
      contextTurns: i('contextTurns', 6, 1, 20),
      statusTtl: dur('statusTtlMs', const Duration(seconds: 60)),
    );
  }
}

/// Connection settings for user-configured cloud providers.
/// The API key itself is NEVER part of this object — it lives only in
/// the platform secure store ([AiSecureStore]).
class CloudAiSettings {
  final CloudProviderKind provider;
  final String endpoint;
  final String model;
  final double temperature;
  final int maxTokens;
  final double topP;
  final Duration connectTimeout;
  final Duration requestTimeout;
  final Duration streamIdleTimeout;

  const CloudAiSettings({
    this.provider = CloudProviderKind.gemini,
    this.endpoint = CloudAiSettings.geminiDefaultEndpoint,
    this.model = 'gemini-2.0-flash',
    this.temperature = 0.7,
    this.maxTokens = 1024,
    this.topP = 0.9,
    this.connectTimeout = const Duration(seconds: 10),
    this.requestTimeout = const Duration(minutes: 2),
    this.streamIdleTimeout = const Duration(seconds: 60),
  });

  static const geminiDefaultEndpoint =
      'https://generativelanguage.googleapis.com/v1beta';
  static const openAiDefaultEndpoint = 'https://api.openai.com/v1';

  /// Endpoint default for a provider kind.
  static String defaultEndpointFor(CloudProviderKind kind) =>
      switch (kind) {
        CloudProviderKind.openAI => openAiDefaultEndpoint,
        CloudProviderKind.gemini => geminiDefaultEndpoint,
        CloudProviderKind.custom => 'https://',
      };

  /// Model default for a provider kind.
  static String defaultModelFor(CloudProviderKind kind) => switch (kind) {
        CloudProviderKind.openAI => 'gpt-4o-mini',
        CloudProviderKind.gemini => 'gemini-2.0-flash',
        CloudProviderKind.custom => '',
      };

  CloudAiSettings copyWith({
    CloudProviderKind? provider,
    String? endpoint,
    String? model,
    double? temperature,
    int? maxTokens,
    double? topP,
    Duration? connectTimeout,
    Duration? requestTimeout,
    Duration? streamIdleTimeout,
  }) =>
      CloudAiSettings(
        provider: provider ?? this.provider,
        endpoint: endpoint ?? this.endpoint,
        model: model ?? this.model,
        temperature: temperature ?? this.temperature,
        maxTokens: maxTokens ?? this.maxTokens,
        topP: topP ?? this.topP,
        connectTimeout: connectTimeout ?? this.connectTimeout,
        requestTimeout: requestTimeout ?? this.requestTimeout,
        streamIdleTimeout:
            streamIdleTimeout ?? this.streamIdleTimeout,
      );

  Map<String, dynamic> toJson() => {
        'provider': provider.wire,
        'endpoint': endpoint,
        'model': model,
        'temperature': temperature,
        'maxTokens': maxTokens,
        'topP': topP,
        'connectTimeoutMs': connectTimeout.inMilliseconds,
        'requestTimeoutMs': requestTimeout.inMilliseconds,
        'streamIdleTimeoutMs': streamIdleTimeout.inMilliseconds,
      };

  factory CloudAiSettings.fromJson(Map<String, dynamic> json) {
    double d(String k, double fallback, double lo, double hi) {
      final v = (json[k] as num?)?.toDouble() ?? fallback;
      return v.clamp(lo, hi);
    }

    int i(String k, int fallback, int lo, int hi) {
      final v = (json[k] as num?)?.toInt() ?? fallback;
      return v.clamp(lo, hi);
    }

    Duration dur(String k, Duration fallback) {
      final ms = (json[k] as num?)?.toInt();
      return ms == null
          ? fallback
          : Duration(milliseconds: ms.clamp(1000, 600000));
    }

    final provider =
        CloudProviderKindX.fromWire(json['provider'] as String?);
    final rawEndpoint = (json['endpoint'] as String?)?.trim();
    return CloudAiSettings(
      provider: provider,
      endpoint: rawEndpoint == null || rawEndpoint.isEmpty
          ? defaultEndpointFor(provider)
          : rawEndpoint,
      model: (json['model'] as String?)?.trim().isEmpty ?? true
          ? defaultModelFor(provider)
          : (json['model'] as String).trim(),
      temperature: d('temperature', 0.7, 0.0, 2.0),
      maxTokens: i('maxTokens', 1024, 32, 8192),
      topP: d('topP', 0.9, 0.0, 1.0),
      connectTimeout:
          dur('connectTimeoutMs', const Duration(seconds: 10)),
      requestTimeout:
          dur('requestTimeoutMs', const Duration(minutes: 2)),
      streamIdleTimeout:
          dur('streamIdleTimeoutMs', const Duration(seconds: 60)),
    );
  }
}

/// Root AI configuration. Persisted as JSON in the settings box.
/// Contains NO cloud API keys — those live only in secure storage.
class AiConfig {
  final AiMode mode;
  final LocalAiSettings local;
  final CloudAiSettings cloud;

  /// Explicit acknowledgement of the cloud privacy notice, required
  /// before first cloud use.
  final bool cloudConsentAcknowledged;

  const AiConfig({
    this.mode = AiMode.local,
    this.local = const LocalAiSettings(),
    this.cloud = const CloudAiSettings(),
    this.cloudConsentAcknowledged = false,
  });

  AiConfig copyWith({
    AiMode? mode,
    LocalAiSettings? local,
    CloudAiSettings? cloud,
    bool? cloudConsentAcknowledged,
  }) =>
      AiConfig(
        mode: mode ?? this.mode,
        local: local ?? this.local,
        cloud: cloud ?? this.cloud,
        cloudConsentAcknowledged:
            cloudConsentAcknowledged ?? this.cloudConsentAcknowledged,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'local': local.toJson(),
        'cloud': cloud.toJson(),
        'cloudConsentAcknowledged': cloudConsentAcknowledged,
      };

  factory AiConfig.fromJson(Map<String, dynamic> json) {
    var local = const LocalAiSettings();
    final rawLocal = json['local'];
    if (rawLocal is Map) {
      local = LocalAiSettings.fromJson(
          Map<String, dynamic>.from(rawLocal));
    } else {
      // Tolerate the pre-rebuild flat schema: migrate server URL and
      // generation options instead of dropping user settings.
      local = LocalAiSettings.fromJson(json);
    }
    var cloud = const CloudAiSettings();
    final rawCloud = json['cloud'];
    if (rawCloud is Map) {
      cloud = CloudAiSettings.fromJson(
          Map<String, dynamic>.from(rawCloud));
    }
    // Migrate the pre-1.1 default port (server moved to :11434).
    if (local.serverUrl == 'http://127.0.0.1:8080/v1') {
      local = local.copyWith(
          serverUrl: const LocalAiSettings().serverUrl);
    }
    return AiConfig(
      mode: AiModeX.fromWire(json['mode'] as String?),
      local: local,
      cloud: cloud,
      cloudConsentAcknowledged:
          (json['cloudConsentAcknowledged'] as bool?) ?? false,
    );
  }
}

/// Where a server URL lives, for honest labeling.
enum ServerPlacement { onDevice, lan, remote }

/// Classifies a server URL without any network access.
ServerPlacement classifyServerUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return ServerPlacement.remote;
  final host = uri.host.toLowerCase();
  if (host == '127.0.0.1' ||
      host == 'localhost' ||
      host == '::1' ||
      host == '[::1]') {
    return ServerPlacement.onDevice;
  }
  if (_isPrivateLan(host)) return ServerPlacement.lan;
  return ServerPlacement.remote;
}

bool _isPrivateLan(String host) {
  if (host.startsWith('192.168.') || host.startsWith('10.')) {
    return true;
  }
  final m = RegExp(r'^172\.(\d+)\.').firstMatch(host);
  if (m != null) {
    final second = int.tryParse(m.group(1) ?? '') ?? -1;
    if (second >= 16 && second <= 31) return true;
  }
  if (host.endsWith('.local') || host == 'localhost') return true;
  return false;
}

/// URL validation for settings fields. Returns an error string or null.
String? validateServerUrl(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return 'Enter a server URL.';
  final uri = Uri.tryParse(v);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return 'That does not look like a URL (need http(s)://host).';
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return 'Only http or https URLs are supported.';
  }
  return null;
}

/// Normalizes a user-typed URL: trims, drops trailing slashes, and appends
/// `/v1` when no API path is given (bare `http://host:port` 404s otherwise —
/// both llama.cpp and Ollama serve the OpenAI API under `/v1`).
/// Cloud endpoints (Gemini/OpenAI hosts) are returned trimmed but otherwise
/// untouched — their paths are part of the provider API.
String normalizeServerUrl(String raw) {
  final v = raw.trim().replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(v);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return v;
  final host = uri.host.toLowerCase();
  if (host.contains('googleapis.com') ||
      host.contains('openai.com')) {
    return v;
  }
  final path = uri.path;
  if (path.isEmpty || path == '/') {
    return '${uri.scheme}://${uri.authority}/v1';
  }
  return v;
}
