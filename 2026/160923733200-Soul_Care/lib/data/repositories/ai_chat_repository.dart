import '../../core/ai/ai_models.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/utils/utils.dart';
import '../local/local_database.dart';
import '../models/ai_chat.dart';

/// Local conversation storage. Two boxes, JSON maps, no cloud.
/// Never stores anything except the user's own chat turns.
/// History survives app restarts, provider switches, and outages.
class AiChatRepository {
  const AiChatRepository();

  Future<Result<List<AiConversation>>> getConversations() async {
    try {
      final out = <AiConversation>[];
      for (final key in LocalDatabase.aiConversationsBox.keys) {
        final raw = LocalDatabase.aiConversationsBox.get(key);
        if (raw == null) continue;
        out.add(AiConversation.fromJson(
            Map<String, dynamic>.from(raw as Map)));
      }
      out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return Success(out);
    } catch (e) {
      return Failure(PersistenceException(
          'Could not load conversations.', originalError: e));
    }
  }

  Future<Result<AiConversation>> createConversation(
    String title, {
    String providerUsed = 'local',
  }) async {
    try {
      final clean =
          title.trim().isEmpty ? 'Conversation' : title.trim();
      final now = DateTime.now();
      final conv = AiConversation(
        id: generateId(),
        title:
            clean.length > 60 ? '${clean.substring(0, 60)}…' : clean,
        createdAt: now,
        updatedAt: now,
        providerUsed: providerUsed,
      );
      await LocalDatabase.aiConversationsBox
          .put(conv.id, conv.toJson());
      return Success(conv);
    } catch (e) {
      return Failure(PersistenceException(
          'Could not start a conversation.', originalError: e));
    }
  }

  Future<Result<void>> renameConversation(
      String id, String title) async {
    try {
      final raw = LocalDatabase.aiConversationsBox.get(id);
      if (raw == null) {
        return const Failure(
            ValidationException('Conversation not found.'));
      }
      final conv = AiConversation.fromJson(
          Map<String, dynamic>.from(raw as Map));
      final clean =
          title.trim().isEmpty ? conv.title : title.trim();
      await LocalDatabase.aiConversationsBox.put(
          id,
          AiConversation(
            id: conv.id,
            title: clean.length > 60
                ? '${clean.substring(0, 60)}…'
                : clean,
            createdAt: conv.createdAt,
            updatedAt: DateTime.now(),
            providerUsed: conv.providerUsed,
          ).toJson());
      return const Success(null);
    } catch (e) {
      return Failure(PersistenceException('Could not rename.',
          originalError: e));
    }
  }

  Future<Result<void>> touchProvider(
      String id, String providerUsed) async {
    try {
      final raw = LocalDatabase.aiConversationsBox.get(id);
      if (raw == null) return const Success(null);
      final conv = AiConversation.fromJson(
          Map<String, dynamic>.from(raw as Map));
      await LocalDatabase.aiConversationsBox.put(
          id,
          AiConversation(
            id: conv.id,
            title: conv.title,
            createdAt: conv.createdAt,
            updatedAt: DateTime.now(),
            providerUsed: providerUsed,
          ).toJson());
      return const Success(null);
    } catch (_) {
      return const Success(null);
    }
  }

  Future<Result<void>> deleteConversation(String id) async {
    try {
      await LocalDatabase.aiConversationsBox.delete(id);
      final box = LocalDatabase.aiMessagesBox;
      final dead = <dynamic>[];
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is Map &&
            (raw['conversationId']?.toString() ?? '') == id) {
          dead.add(key);
        }
      }
      for (final k in dead) {
        await box.delete(k);
      }
      return const Success(null);
    } catch (e) {
      return Failure(PersistenceException('Could not delete.',
          originalError: e));
    }
  }

  Future<Result<List<AiChatMessage>>> getMessages(
      String conversationId) async {
    try {
      final out = <AiChatMessage>[];
      for (final key in LocalDatabase.aiMessagesBox.keys) {
        final raw = LocalDatabase.aiMessagesBox.get(key);
        if (raw == null) continue;
        final m = AiChatMessage.fromJson(
            Map<String, dynamic>.from(raw as Map));
        if (m.conversationId == conversationId) out.add(m);
      }
      out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return Success(out);
    } catch (e) {
      return Failure(PersistenceException(
          'Could not load messages.', originalError: e));
    }
  }

  Future<Result<AiChatMessage>> addMessage({
    required String conversationId,
    required AiRole role,
    required String content,
    String providerUsed = 'local',
  }) async {
    try {
      if (content.trim().isEmpty) {
        return const Failure(
            ValidationException('Empty message.'));
      }
      final now = DateTime.now();
      final rawConv =
          LocalDatabase.aiConversationsBox.get(conversationId);
      DateTime? prev;
      AiConversation? conv;
      if (rawConv != null) {
        conv = AiConversation.fromJson(
            Map<String, dynamic>.from(rawConv as Map));
        prev = conv.updatedAt;
      }
      // Strictly increasing stamps per conversation: same-millisecond
      // turns would otherwise sort arbitrarily on reload.
      final stamp = (prev != null && !now.isAfter(prev))
          ? prev.add(const Duration(microseconds: 1))
          : now;
      final msg = AiChatMessage(
        id: generateId(),
        conversationId: conversationId,
        role: role,
        content: content,
        createdAt: stamp,
        providerUsed: providerUsed,
      );
      await LocalDatabase.aiMessagesBox.put(msg.id, msg.toJson());
      if (conv != null) {
        await LocalDatabase.aiConversationsBox.put(
            conversationId,
            AiConversation(
              id: conv.id,
              title: conv.title,
              createdAt: conv.createdAt,
              updatedAt: stamp,
              providerUsed: providerUsed,
            ).toJson());
      }
      return Success(msg);
    } catch (e) {
      return Failure(PersistenceException('Could not save message.',
          originalError: e));
    }
  }

  Future<Result<void>> clearMessages(String conversationId) async {
    try {
      final box = LocalDatabase.aiMessagesBox;
      final dead = <dynamic>[];
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is Map &&
            (raw['conversationId']?.toString() ?? '') ==
                conversationId) {
          dead.add(key);
        }
      }
      for (final k in dead) {
        await box.delete(k);
      }
      return const Success(null);
    } catch (e) {
      return Failure(PersistenceException('Could not clear.',
          originalError: e));
    }
  }
}
