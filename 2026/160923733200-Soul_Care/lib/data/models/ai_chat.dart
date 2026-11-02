import '../../core/ai/ai_models.dart';

/// One persistent conversation. Titles are local (first user message),
/// never model-generated. [providerUsed] records which backend produced
/// the latest turn (`local`, `cloud:gemini`, …) for transparency — it
/// never affects history, which survives every mode switch.
class AiConversation {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String providerUsed;

  const AiConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.providerUsed = 'local',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'providerUsed': providerUsed,
      };

  factory AiConversation.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return AiConversation(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'Conversation',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
      // Migration: conversations stored before provider tags existed
      // came only from the local backend.
      providerUsed:
          (json['providerUsed'] as String?) ?? 'local',
    );
  }
}

/// One stored chat turn. Visible history is never silently trimmed;
/// the bounded *model* context is a separate projection. [providerUsed]
/// marks which backend generated an assistant turn.
class AiChatMessage {
  final String id;
  final String conversationId;
  final AiRole role;
  final String content;
  final DateTime createdAt;
  final String providerUsed;

  const AiChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.providerUsed = 'local',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'role': role.wire,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'providerUsed': providerUsed,
      };

  factory AiChatMessage.fromJson(Map<String, dynamic> json) {
    return AiChatMessage(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String? ?? '',
      role: AiRoleX.fromWire(json['role'] as String?),
      content: (json['content'] as String?) ?? '',
      createdAt: DateTime.tryParse(
              json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      providerUsed:
          (json['providerUsed'] as String?) ?? 'local',
    );
  }
}
