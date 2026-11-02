import 'package:flutter/material.dart';

import '../../core/ai/ai_config.dart';
import '../../core/ai/ai_connection.dart';
import '../../core/ai/ai_models.dart';
import '../../core/ai/ai_provider.dart';
import '../../core/ai/ai_secure_store.dart';
import '../../core/ai/cloud_ai_provider.dart';
import '../../core/ai/local_ai_provider.dart';
import '../../core/ai/soulcare_ai_service.dart';
import '../../data/models/ai_chat.dart';
import '../../data/repositories/ai_chat_repository.dart';
import '../../data/repositories/ai_config_repository.dart';

/// Chat state for the /ai screen: mode switching, streaming, stop,
/// retry/regenerate, conversation management, suggestions, quick actions.
///
/// Switching Local ↔ Cloud rebinds providers only — history, health
/// data, and settings are never touched. Server status is checked on
/// open, on manual request, and before generation when stale.
class AiChatProvider extends ChangeNotifier {
  AiConfig _config = const AiConfig();
  late LocalAiProvider _local;
  late CloudAiProvider _cloud;
  late AiConnectionManager _connection;
  late SoulCareAiService _service;
  final AiChatRepository _chats;
  final AiConfigRepository _configRepo;

  List<AiConversation> _conversations = [];
  String? _activeId;
  List<AiChatMessage> _messages = [];
  bool _loading = false;
  AiTurnState _turn = AiTurnState.idle;
  String _streaming = '';
  String? _error;
  List<String> _suggestions = const [];
  PendingAttachment? _attachment;

  AiChatProvider({
    AiConfigRepository? configRepo,
    AiChatRepository? chats,
    LocalAiProvider? local,
    CloudAiProvider? cloud,
    SoulCareAiService? service,
    AiSecureStore? secure,
  })  : _configRepo =
            configRepo ?? AiConfigRepository(secure: secure),
        _chats = chats ?? const AiChatRepository() {
    _local = local ?? LocalAiProvider(configOf: () => _config);
    _cloud = cloud ??
        CloudAiProvider(
          configOf: () => _config,
          apiKeyOf: () => _configRepo
              .readCloudKey(_config.cloud.provider),
        );
    _connection = AiConnectionManager(
        provider: _activeProvider(),
        ttlOf: () => _config.local.statusTtl);
    _service = service ??
        SoulCareAiService(
          local: _local,
          cloud: _cloud,
          configOf: () => _config,
          connection: _connection,
        );
  }

  AiProvider _activeProvider() =>
      _config.mode == AiMode.local ? _local : _cloud;

  // ---- Exposed state ----

  AiConfig get config => _config;
  AiMode get mode => _config.mode;
  AiConnectionManager get connection => _connection;
  List<AiConversation> get conversations =>
      List.unmodifiable(_conversations);
  String? get activeId => _activeId;
  List<AiChatMessage> get messages =>
      List.unmodifiable(_messages);
  bool get loading => _loading;
  AiTurnState get turn => _turn;
  bool get generating =>
      _turn == AiTurnState.sending || _turn == AiTurnState.streaming;
  String get streaming => _streaming;
  String? get error => _error;
  List<String> get suggestions =>
      List.unmodifiable(_suggestions);
  PendingAttachment? get attachment => _attachment;
  String get lastBasis => _service.lastBasis;
  String get lastContextJson => _service.lastContextJson;

  /// Honest provider indicator for the chatbot header. Never labels
  /// cloud inference as local.
  String get providerIndicator => _config.mode == AiMode.local
      ? 'Local${connection.state?.activeModelId == null ? '' : ' · ${_shortModel(connection.state!.activeModelId!)}'}'
      : 'Cloud · ${_config.cloud.provider.label}';

  /// Short model id for the indicator (last path segment).
  static String _shortModel(String id) {
    var n = id.startsWith('models/') ? id.substring(7) : id;
    final slash = n.lastIndexOf('/');
    if (slash >= 0 && slash < n.length - 1) {
      n = n.substring(slash + 1);
    }
    return n;
  }

  String? get activeModelId => _config.mode == AiMode.local
      ? (connection.state?.activeModelId ??
          _config.local.activeModelId)
      : _config.cloud.model;

  AiConversation? get activeConversation {
    for (final c in _conversations) {
      if (c.id == _activeId) return c;
    }
    return null;
  }

  Future<void> init() async {
    _loading = true;
    notifyListeners();
    final res = await _configRepo.load();
    res.fold(
      onSuccess: (c) {
        _config = c;
        _rebind();
      },
      onFailure: (_) {},
    );
    await refreshConversations();
    _loading = false;
    notifyListeners();
    await connection.status();
    _suggestions = await _service.suggestions();
    notifyListeners();
  }

  void _rebind() {
    _local = LocalAiProvider(configOf: () => _config);
    _cloud = CloudAiProvider(
      configOf: () => _config,
      apiKeyOf: () =>
          _configRepo.readCloudKey(_config.cloud.provider),
    );
    _connection = AiConnectionManager(
        provider: _activeProvider(),
        ttlOf: () => _config.local.statusTtl);
    _service = SoulCareAiService(
      local: _local,
      cloud: _cloud,
      configOf: () => _config,
      connection: _connection,
    );
    notifyListeners();
  }

  Future<bool> saveConfig(AiConfig next) async {
    final res = await _configRepo.save(next);
    return res.fold(
      onSuccess: (c) {
        _config = c;
        _rebind();
        return true;
      },
      onFailure: (e) {
        _error = e.message;
        notifyListeners();
        return false;
      },
    );
  }

  /// Switches Local ↔ Cloud. Rebinds the active provider and refreshes
  /// its status. History, health data, and settings are untouched.
  Future<void> setMode(AiMode next) async {
    if (next == _config.mode) return;
    if (next == AiMode.cloud &&
        !_config.cloudConsentAcknowledged) {
      _error =
          'Please review and accept the Cloud AI privacy notice first.';
      notifyListeners();
      return;
    }
    await saveConfig(_config.copyWith(mode: next));
    await connection.status(force: true);
  }

  Future<void> acknowledgeCloudConsent() =>
      saveConfig(_config.copyWith(cloudConsentAcknowledged: true));

  // ---- Secure cloud keys (delegated, never held in memory) ----

  Future<bool> hasCloudKey([CloudProviderKind? kind]) =>
      _configRepo.hasCloudKey(kind ?? _config.cloud.provider);

  Future<String> maskedCloudKey([CloudProviderKind? kind]) =>
      _configRepo.maskedCloudKey(kind ?? _config.cloud.provider);

  Future<bool> saveCloudKey(String key,
      [CloudProviderKind? kind]) async {
    final res = await _configRepo.saveCloudKey(
        kind ?? _config.cloud.provider, key);
    if (res.isFailure) {
      _error = res.error?.message;
      notifyListeners();
      return false;
    }
    notifyListeners();
    return true;
  }

  Future<void> deleteCloudKey([CloudProviderKind? kind]) async {
    await _configRepo
        .deleteCloudKey(kind ?? _config.cloud.provider);
    notifyListeners();
  }

  // ---- Conversations ----

  Future<void> refreshConversations() async {
    final res = await _chats.getConversations();
    res.fold(
      onSuccess: (l) => _conversations = l,
      onFailure: (_) {},
    );
    notifyListeners();
  }

  Future<void> openConversation(String? id) async {
    _activeId = id;
    _messages = [];
    _streaming = '';
    _error = null;
    _turn = AiTurnState.idle;
    _attachment = null;
    notifyListeners();
    if (id == null) return;
    final res = await _chats.getMessages(id);
    res.fold(
      onSuccess: (l) => _messages = l,
      onFailure: (e) => _error = e.message,
    );
    notifyListeners();
  }

  Future<void> newConversation() => openConversation(null);

  Future<void> renameConversation(String id, String title) async {
    await _chats.renameConversation(id, title);
    await refreshConversations();
  }

  Future<void> deleteConversation(String id) async {
    await _chats.deleteConversation(id);
    if (_activeId == id) _activeId = null;
    await refreshConversations();
    if (_activeId != null) {
      await openConversation(_activeId);
    } else {
      _messages = [];
      notifyListeners();
    }
  }

  Future<void> clearCurrent() async {
    if (_activeId == null) return;
    await _chats.clearMessages(_activeId!);
    await openConversation(_activeId);
  }

  void attach(PendingAttachment a) {
    _attachment = a;
    notifyListeners();
  }

  void detach() {
    _attachment = null;
    notifyListeners();
  }

  Future<void> send(String text,
      {List<String>? forceTools, bool persistUser = true}) async {
    if (generating || text.trim().isEmpty) return;
    _turn = AiTurnState.sending;
    _streaming = '';
    _error = null;
    notifyListeners();
    var convId = _activeId;
    try {
      if (convId == null) {
        final created = await _chats.createConversation(
            _service.titleFor(text),
            providerUsed: _service.activeProviderTag);
        final conv = created.fold(
            onSuccess: (c) => c, onFailure: (_) => null);
        if (conv == null) {
          _error = 'Could not start a conversation.';
          _turn = AiTurnState.failed;
          return;
        }
        convId = conv.id;
        _activeId = convId;
        await refreshConversations();
      }
      final attachment = _attachment;
      _attachment = null;
      // Optimistic echo: the question is visible while generating, not
      // only after the stream ends. Skipped when already showing (retry).
      final echo = text.trim();
      final already = _messages.isNotEmpty &&
          _messages.last.role == AiRole.user &&
          _messages.last.content == echo;
      if (!already) {
        _messages = [
          ..._messages,
          AiChatMessage(
            id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
            conversationId: convId,
            role: AiRole.user,
            content: echo,
            createdAt: DateTime.now(),
          ),
        ];
        notifyListeners();
      }
      _turn = AiTurnState.streaming;
      notifyListeners();
      await for (final piece in _service.answer(
          conversationId: convId,
          question: text,
          forceTools: forceTools,
          attachment: attachment,
          persistUser: persistUser)) {
        _streaming += piece;
        notifyListeners();
      }
      _turn = AiTurnState.completed;
      _streaming = '';
      await openConversation(convId);
      _turn = AiTurnState.completed;
      await refreshConversations();
    } on AiProviderException catch (e) {
      if (e.kind == AiFailureKind.cancelled) {
        _turn = AiTurnState.cancelled;
        // Partial content already persisted by the service.
        await openConversation(convId);
        _turn = AiTurnState.cancelled;
      } else {
        _error = e.friendly.isEmpty
            ? AiErrors.generation
            : e.friendly;
        _turn = AiTurnState.failed;
        _streaming = '';
      }
    } catch (_) {
      _error = AiErrors.generation;
      _turn = AiTurnState.failed;
      _streaming = '';
    } finally {
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _service.stop();
  }

  Future<void> retry() async {
    // Regenerate from the last user message without saving it twice.
    AiChatMessage? lastUser;
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].role == AiRole.user) {
        lastUser = _messages[i];
        break;
      }
    }
    if (lastUser == null) return;
    await send(lastUser.content, persistUser: false);
  }

  Future<void> checkConnection({bool force = true}) async {
    await connection.status(force: force);
    notifyListeners();
  }

  /// Settings model picker path (provider-owned HTTP, never UI HTTP).
  Future<List<AiModel>> listModels() async {
    try {
      return await _activeProvider().getModels();
    } catch (_) {
      return const [];
    }
  }

  @override
  void dispose() {
    _local.dispose();
    _cloud.dispose();
    _connection.dispose();
    super.dispose();
  }
}
