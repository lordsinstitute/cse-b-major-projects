import 'dart:convert';

import '../../core/utils/utils.dart';
import '../../data/models/ai_chat.dart';
import '../../data/repositories/ai_chat_repository.dart';
import 'ai_config.dart';
import 'ai_connection.dart';
import 'ai_context.dart';
import 'ai_domain_guard.dart';
import 'ai_models.dart';
import 'ai_prompts.dart';
import 'ai_provider.dart';
import 'cloud_ai_provider.dart';
import 'local_ai_provider.dart';

/// Future-compatible medical-document analysis. DISABLED: no implementation
/// exists, the general chat never ingests PDFs, and this throws if called.
abstract class MedicalAiAnalyzer {
  Future<String> analyzeDocument(
      {required String fileName, required String text});
}

class DisabledMedicalAiAnalyzer implements MedicalAiAnalyzer {
  const DisabledMedicalAiAnalyzer();

  @override
  Future<String> analyzeDocument(
          {required String fileName, required String text}) =>
      Future.error(StateError(
          'Medical document analysis is not implemented.'));
}

/// SoulCare AI orchestration: guard → intent → minimal structured context
/// → active provider → persisted turns.
///
/// Read-only toward health records: the model never touches repositories
/// (only [SoulCareContext] does, deterministically). There are NO write
/// tools — the architecture makes mutation impossible, not just the prompt.
///
/// Provider switching rebuilds every request from the system prompt,
/// relevant conversation context, and relevant SoulCare context only.
/// Internal connection/debug details are never forwarded to a provider —
/// which also means local-only details never leak to cloud backends.
class SoulCareAiService {
  final LocalAiProvider local;
  final CloudAiProvider cloud;
  final AiConfig Function() configOf;
  final AiConnectionManager connection;
  final AiChatRepository chats;
  final SoulCareContext soulcare;
  final AiDomainGuard guard;

  String _lastBasis = '';
  String _lastContextJson = '';

  /// Transparency line for the last answer ("Based on 6 logged days").
  String get lastBasis => _lastBasis;

  /// Exact structured context sent with the last answer (shown in the
  /// "What the AI saw" viewer — never contains journal/doc bodies unless
  /// explicitly attached).
  String get lastContextJson => _lastContextJson;

  SoulCareAiService({
    required this.local,
    required this.cloud,
    required this.configOf,
    required this.connection,
    AiChatRepository? chats,
    SoulCareContext? soulcare,
    AiDomainGuard? guard,
  })  : chats = chats ?? const AiChatRepository(),
        soulcare = soulcare ?? SoulCareContext(),
        guard = guard ?? AiDomainGuard();

  AiProvider get activeProvider =>
      configOf().mode == AiMode.local ? local : cloud;

  /// Short provenance tag stored with every assistant turn, e.g.
  /// `local` or `cloud:gemini`. Survives mode switches and restarts.
  String get activeProviderTag => configOf().mode == AiMode.local
      ? 'local'
      : 'cloud:${configOf().cloud.provider.wire}';

  AiGenerationOptions _optionsFor(AiMode mode) {
    final c = configOf();
    if (mode == AiMode.local) {
      return AiGenerationOptions(
        temperature: c.local.temperature,
        maxTokens: c.local.maxTokens,
        topP: c.local.topP,
      );
    }
    return AiGenerationOptions(
      temperature: c.cloud.temperature,
      maxTokens: c.cloud.maxTokens,
      topP: c.cloud.topP,
    );
  }

  Future<Map<String, dynamic>> _runTools(List<String> tools) async {
    final out = <String, dynamic>{};
    for (final t in tools) {
      try {
        switch (t) {
          case 'today':
            out['today'] = await soulcare.getTodaySummary();
          case 'weekly':
            out['this_week'] =
                await soulcare.getWeeklySummary();
          case 'monthly':
            out['last_30_days'] =
                await soulcare.getMonthlySummary();
          case 'sleepTrend':
            out['sleep_trend'] =
                await soulcare.getSleepTrend();
          case 'stressTrend':
            out['stress_trend'] =
                await soulcare.getStressTrend();
          case 'exerciseTrend':
            out['exercise_trend'] =
                await soulcare.getExerciseTrend();
          case 'hydrationTrend':
            out['hydration_trend'] =
                await soulcare.getHydrationTrend();
          case 'habitProgress':
            out['habits'] = await soulcare.getHabitProgress();
          case 'experimentHistory':
            out['experiments'] =
                await soulcare.getExperimentHistory();
          case 'experimentResult':
            out['latest_experiment'] =
                await soulcare.getExperimentResult();
          case 'wellnessScore':
            out['wellness_score'] =
                await soulcare.getWellnessScore();
          case 'wellnessScoreBreakdown':
            out['score_breakdown'] =
                await soulcare.getWellnessScoreBreakdown();
          case 'recentInsights':
            out['insights'] =
                await soulcare.getRecentInsights();
          case 'calendar':
            out['calendar'] =
                await soulcare.getCalendarSummary();
          case 'goals':
            out['goals'] = await soulcare.getGoals();
        }
      } catch (_) {
        out[t] = {'unavailable': true};
      }
    }
    return out;
  }

  String _basisOf(Map<String, dynamic> context) {
    int days = 0;
    void scan(dynamic v) {
      if (v is Map) {
        for (final e in v.entries) {
          final k = e.key.toString();
          if ((k == 'days_logged' ||
                  k == 'days_logged_last_30') &&
              e.value is num) {
            final n = (e.value as num).toInt();
            if (n > days) days = n;
          } else {
            scan(e.value);
          }
        }
      }
    }

    scan(context);
    return days > 0
        ? 'Based on $days logged day${days == 1 ? '' : 's'}'
        : '';
  }

  Future<List<AiMessage>> _buildMessages({
    required String conversationId,
    required String question,
    required List<String> tools,
    required AiDomain domain,
    PendingAttachment? attachment,
  }) async {
    final context = await _runTools(tools);
    _lastBasis = _basisOf(context);
    try {
      _lastContextJson =
          const JsonEncoder.withIndent('  ').convert(context);
    } catch (_) {
      _lastContextJson = '$context';
    }
    final history = (await chats.getMessages(conversationId)).fold(
        onSuccess: (l) => l, onFailure: (_) => const <AiChatMessage>[]);
    final perSide = configOf().local.contextTurns;
    final recent = history.length <= perSide * 2
        ? history
        : history.sublist(history.length - perSide * 2);
    final messages = <AiMessage>[
      const AiMessage(role: AiRole.system, content: AiPrompts.system),
      AiMessage(
          role: AiRole.system,
          content: AiPrompts.formatContext(context, _lastBasis)),
      if (domain == AiDomain.ambiguous)
        const AiMessage(
            role: AiRole.system,
            content: AiPrompts.ambiguousFraming),
      for (final m in recent)
        AiMessage(role: m.role, content: m.content),
      AiMessage(role: AiRole.user, content: question),
    ];
    if (attachment != null) {
      messages.insert(
          2,
          AiMessage(
              role: AiRole.system,
              content:
                  'The user explicitly shared this ${attachment.kind} for this question only (${attachment.label}):\n${attachment.content}'));
    }
    return messages;
  }

  /// Streams an answer, persisting both turns with the provider tag.
  /// Out-of-scope questions are answered locally with the canned scope
  /// response — no provider is contacted. Stopping preserves the partial
  /// text (also persisted). Throws [AiProviderException] with friendly
  /// messages.
  Stream<String> answer({
    required String conversationId,
    required String question,
    List<String>? forceTools,
    PendingAttachment? attachment,
    bool persistUser = true,
  }) async* {
    if (question.trim().isEmpty) {
      throw const AiProviderException(AiFailureKind.empty);
    }
    final mode = configOf().mode;
    final tag = activeProviderTag;
    // Persist the question FIRST so a failed send never swallows what
    // the user typed (the message stays visible with a retry option).
    if (persistUser) {
      await chats.addMessage(
          conversationId: conversationId,
          role: AiRole.user,
          content: question.trim(),
          providerUsed: tag);
    }
    final domain = guard.classify(question);
    if (domain == AiDomain.outOfScope) {
      _lastBasis = '';
      _lastContextJson = '';
      await chats.addMessage(
          conversationId: conversationId,
          role: AiRole.assistant,
          content: AiDomainGuard.scopeRefusal,
          providerUsed: 'guard');
      yield AiDomainGuard.scopeRefusal;
      return;
    }
    await connection.status();
    if (!connection.isConnected) {
      await connection.checkNow();
    }
    if (!connection.isConnected) {
      throw const AiProviderException(AiFailureKind.unreachable);
    }
    final tools =
        forceTools ?? AiIntentRouter.toolsFor(question);
    final messages = await _buildMessages(
        conversationId: conversationId,
        question: question.trim(),
        tools: tools,
        domain: domain,
        attachment: attachment);
    connection.noteRequest();
    final buf = StringBuffer();
    try {
      await for (final chunk in activeProvider.generateResponse(
          messages: messages, options: _optionsFor(mode))) {
        if (chunk.done) break;
        buf.write(chunk.text);
        yield chunk.text;
      }
    } on AiProviderException catch (e) {
      if (e.kind == AiFailureKind.cancelled) {
        // Keep the partial answer; fall through to persist it.
      } else if (buf.isNotEmpty) {
        // Mid-stream failure: keep what arrived AND report the error,
        // instead of silently dropping generated text.
        await chats.addMessage(
            conversationId: conversationId,
            role: AiRole.assistant,
            content: buf.toString(),
            providerUsed: tag);
        connection.noteError(e.friendly);
        rethrow;
      } else {
        connection.noteError(e.friendly);
        rethrow;
      }
    }
    final full = buf.toString();
    if (full.trim().isEmpty) {
      throw const AiProviderException(AiFailureKind.empty);
    }
    await chats.addMessage(
        conversationId: conversationId,
        role: AiRole.assistant,
        content: full,
        providerUsed: tag);
  }

  Future<void> stop() => activeProvider.cancelGeneration();

  /// Suggested questions, only for data the user actually has.
  Future<List<String>> suggestions() async {
    final out = <String>[];
    final week = await soulcare.getWeeklySummary();
    final days = (week['days_logged'] as num?)?.toInt() ?? 0;
    if (days >= 2) {
      out.add('How was my sleep this week?');
      out.add('What changed from last week?');
    }
    final habits = await soulcare.getHabitProgress();
    if (((habits['total_experiments'] as num?)?.toInt() ?? 0) > 0) {
      out.add('How are my experiments going?');
    }
    if (days >= 2) {
      out.add('What were my most consistent habits?');
    }
    final month = await soulcare.getMonthlySummary();
    if (((month['days_logged'] as num?)?.toInt() ?? 0) >= 2) {
      out.add('What was my best day this month?');
    }
    out.add('What experiments have I completed?');
    return out.take(5).toList();
  }

  /// Quick actions: fixed question + forced minimal tools.
  static const quickActions = [
    ('Analyze My Week', 'Analyze my week',
        ['weekly', 'sleepTrend', 'stressTrend']),
    ('Explain My Wellness Score', 'Explain my wellness score',
        ['wellnessScore', 'wellnessScoreBreakdown']),
    ('Review My Experiments', 'Review my experiments',
        ['experimentHistory', 'experimentResult']),
    ('Find My Patterns', 'Find my patterns',
        ['recentInsights', 'weekly']),
    ('Compare This Week', 'Compare this week to last week',
        ['weekly', 'sleepTrend', 'stressTrend', 'exerciseTrend']),
  ];

  /// Local (non-model) title for a new conversation.
  String titleFor(String firstQuestion) {
    final t = firstQuestion.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return 'Conversation';
    return t.length > 48 ? '${t.substring(0, 48)}…' : t;
  }

  String newId() => generateId();
}
