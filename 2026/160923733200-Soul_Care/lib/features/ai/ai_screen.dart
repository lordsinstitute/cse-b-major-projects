import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/providers/ai_chat_provider.dart';
import '../../app/theme/design_system.dart';
import '../../core/ai/ai_config.dart';
import '../../core/ai/ai_models.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/ai_chat.dart';

/// /ai — SoulCare AI chat. One UI for both backends; only the active
/// provider changes. Streaming markdown, stop, retry, regenerate,
/// conversation management, and an always-visible provider indicator.
class AiScreen extends StatelessWidget {
  const AiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _AiBody();
  }
}

class _AiBody extends StatefulWidget {
  const _AiBody();

  @override
  State<_AiBody> createState() => _AiBodyState();
}

class _AiBodyState extends State<_AiBody> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov = context.read<AiChatProvider>();
      prov.init();
      prov.checkConnection();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await context.read<AiChatProvider>().send(text);
    _scrollDown();
  }

  Future<void> _conversationsSheet() async {
    final prov = context.read<AiChatProvider>();
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: prov,
        child: const _ConversationSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AiChatProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final connected = prov.connection.isConnected;
    final isLocal = prov.mode == AiMode.local;
    final placement = isLocal
        ? classifyServerUrl(prov.config.local.serverUrl)
        : ServerPlacement.remote;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SoulCare AI'),
            Text(
              prov.providerIndicator,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        actions: [
          Chip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(
              Icons.circle,
              size: 10,
              color: connected ? scheme.primary : scheme.outline,
            ),
            label: Text(
              isLocal
                  ? (connected ? 'Local' : 'Offline')
                  : (connected ? 'Cloud' : 'Offline'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.forum_outlined),
            tooltip: 'Conversations',
            onPressed: _conversationsSheet,
          ),
          IconButton(
            icon: const Icon(Icons.data_object_outlined),
            tooltip: 'What the AI saw',
            onPressed: () {
              final json = context.read<AiChatProvider>().lastContextJson;
              showModalBottomSheet(
                context: context,
                showDragHandle: true,
                builder: (_) => SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'What the AI saw',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'The exact structured data sent with your last question. Journal bodies and document contents never appear here unless you explicitly attached them.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          json.isEmpty
                              ? 'Nothing sent yet — ask something first.'
                              : json,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _ModeStrip(onSent: _scrollDown),
          if (isLocal && placement != ServerPlacement.onDevice)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: scheme.secondaryContainer,
              child: Text(
                placement == ServerPlacement.lan
                    ? 'LAN server — traffic stays on your network, not on this device alone.'
                    : 'Remote server configured — this is not on-device AI. Review the URL in Settings → SoulCare AI.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (!isLocal)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: scheme.secondaryContainer,
              child: Text(
                'Cloud AI (${prov.config.cloud.provider.label}) — messages leave this device under that provider\u2019s policies. Switch back to Local AI anytime.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: prov.loading
                ? const AppLoading(message: 'Opening SoulCare AI…')
                : prov.messages.isEmpty && !prov.generating
                ? _EmptyState(
                    onAsk: (q) {
                      _input.text = q;
                      _send();
                    },
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount:
                        prov.messages.length +
                        (prov.generating ? 1 : 0) +
                        (prov.error != null ? 1 : 0),
                    itemBuilder: (c, i) {
                      if (i < prov.messages.length) {
                        final m = prov.messages[i];
                        final isLast = i == prov.messages.length - 1;
                        return _Bubble(
                          message: m,
                          showRetry:
                              isLast &&
                              m.role == AiRole.assistant &&
                              !prov.generating,
                        );
                      }
                      if (prov.generating) {
                        return const _StreamingBubble();
                      }
                      return const _ErrorCard();
                    },
                  ),
          ),
          if (prov.generating)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                isLocal
                    ? 'Local AI — your message is processed through the local AI server on this device. No cloud provider is used.'
                    : 'Cloud AI (${prov.config.cloud.provider.label}) — your message is processed by your selected cloud provider.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          if (prov.lastBasis.isNotEmpty && prov.messages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                prov.lastBasis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          if (prov.attachment != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Chip(
                label: Text(
                  'Attached: ${prov.attachment!.label} (this message only)',
                ),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => context.read<AiChatProvider>().detach(),
                visualDensity: VisualDensity.compact,
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(DS.l, 0, DS.l, DS.l),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: DS.backgroundSecondary(
                            Theme.of(context).brightness),
                        borderRadius:
                            BorderRadius.circular(DS.rXLarge - DS.m),
                      ),
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Ask about your week, sleep, experiments…',
                          fillColor: Colors.transparent,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: DS.l + 2,
                            vertical: DS.l,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              DS.rXLarge - DS.m,
                            ),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              DS.rXLarge - DS.m,
                            ),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: DS.s),
                  if (prov.generating)
                    FilledButton(
                      onPressed: () => context.read<AiChatProvider>().stop(),
                      child: const Text('Stop'),
                    )
                  else
                    IconButton.filledTonal(
                      icon: Icon(
                        Icons.arrow_upward,
                        size: 22,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                      ),
                      tooltip: 'Send',
                      onPressed: _send,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Always-visible mode switch. Changing backends never touches history.
class _ModeStrip extends StatelessWidget {
  final VoidCallback onSent;
  const _ModeStrip({required this.onSent});

  Future<void> _pick(BuildContext context, AiMode next) async {
    final prov = context.read<AiChatProvider>();
    if (next == prov.mode) return;
    if (next == AiMode.cloud && !prov.config.cloudConsentAcknowledged) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Cloud AI privacy notice'),
          content: const Text(
            'Messages sent to a cloud provider will leave your device and be processed according to that provider\u2019s policies.\n\nSoulCare will only send the information required for your request.\n\nYou can switch back to Local AI at any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: const Text('I understand'),
            ),
          ],
        ),
      );
      if (accepted != true || !context.mounted) return;
      await prov.acknowledgeCloudConsent();
    }
    await prov.setMode(next);
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AiChatProvider>();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Text('AI Mode', style: theme.textTheme.labelLarge),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Local AI'),
            selected: prov.mode == AiMode.local,
            onSelected: (_) => _pick(context, AiMode.local),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Cloud AI'),
            selected: prov.mode == AiMode.cloud,
            onSelected: (_) => _pick(context, AiMode.cloud),
            visualDensity: VisualDensity.compact,
          ),
          const Spacer(),
          if (prov.connection.checking)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ValueChanged<String> onAsk;
  const _EmptyState({required this.onAsk});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLocal = context.watch<AiChatProvider>().mode == AiMode.local;
    final suggestions = context.watch<AiChatProvider>().suggestions;
    final items = suggestions.isEmpty
        ? const [
            'How was my sleep this week?',
            'What changed compared with last week?',
            'What is sleep hygiene?',
            'What experiments have I completed?',
          ]
        : suggestions;
    return ListView(
      padding: const EdgeInsets.all(DS.xxl),
      children: [
        const SizedBox(height: DS.xxxl),
        Center(
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: 0.10),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.psychology_outlined,
              size: 38,
              color: scheme.primary,
            ),
          ),
        ),
        const SizedBox(height: DS.l),
        Text(
          'SoulCare AI',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: DS.s),
        Text(
          'Your personal wellness assistant.\nSoulCare provides general wellness information and is not a replacement for professional medical care.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: DS.textSecondary(theme.brightness),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: DS.xxxl),
        Text('Ask about:', style: theme.textTheme.titleSmall),
        const SizedBox(height: DS.xs),
        Text(
          'Sleep · Exercise · Stress · Nutrition · Hydration · Mindfulness · Habits · Wellness · Your SoulCare data · General health information',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: DS.textSecondary(theme.brightness),
          ),
        ),
        if (!isLocal) ...[
          const SizedBox(height: 8),
          Text(
            'Cloud mode: messages leave this device under your provider\u2019s policies.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text('Try asking:', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: DS.s,
          runSpacing: DS.s,
          children: [
            for (final q in items)
              ActionChip(
                label: Text(q, style: theme.textTheme.bodySmall),
                onPressed: () => onAsk(q),
                backgroundColor: DS.backgroundSecondary(theme.brightness),
                side: BorderSide(
                    color: DS.divider(theme.brightness).withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DS.rPill)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _QuickActions(onAsk: onAsk),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  final ValueChanged<String> onAsk;
  const _QuickActions({required this.onAsk});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick actions', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in _actions)
              FilledButton.tonal(
                onPressed: () => _run(context, a),
                child: Text(a.$1),
              ),
          ],
        ),
      ],
    );
  }

  static const _actions = [
    (
      'Analyze My Week',
      'Analyze my week',
      ['weekly', 'sleepTrend', 'stressTrend'],
    ),
    (
      'Explain My Wellness Score',
      'Explain my wellness score',
      ['wellnessScore', 'wellnessScoreBreakdown'],
    ),
    (
      'Review My Experiments',
      'Review my experiments',
      ['experimentHistory', 'experimentResult'],
    ),
    ('Find My Patterns', 'Find my patterns', ['recentInsights', 'weekly']),
    (
      'Compare This Week',
      'Compare this week to last week',
      ['weekly', 'sleepTrend', 'stressTrend', 'exerciseTrend'],
    ),
  ];

  Future<void> _run(
    BuildContext context,
    (String, String, List<String>) a,
  ) async {
    final prov = context.read<AiChatProvider>();
    await prov.send(a.$2, forceTools: a.$3);
  }
}

MarkdownStyleSheet _sheet(BuildContext context) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  return MarkdownStyleSheet(
    p: theme.textTheme.bodyMedium,
    h1: theme.textTheme.titleLarge,
    h2: theme.textTheme.titleMedium,
    h3: theme.textTheme.titleSmall,
    listBullet: theme.textTheme.bodyMedium,
    blockquote: theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      fontStyle: FontStyle.italic,
    ),
    code: theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      backgroundColor: scheme.surfaceContainerHighest,
    ),
    tableHead: theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.bold,
    ),
    tableBody: theme.textTheme.bodyMedium,
    a: TextStyle(color: scheme.primary, decoration: TextDecoration.underline),
  );
}

class _Bubble extends StatelessWidget {
  final AiChatMessage message;
  final bool showRetry;
  const _Bubble({required this.message, this.showRetry = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mine = message.role == AiRole.user;
    if (message.role == AiRole.system) {
      return const SizedBox.shrink();
    }
    // Assistant: calm plain text on the canvas with a small sender label
    // (Apple Intelligence style). User: solid accent bubble, asymmetric
    // corners. Both keep identical content and actions.
    if (mine) {
      return Align(
        alignment: Alignment.centerRight,
        child: AnimatedContainer(
          duration: DS.durFast,
          margin: const EdgeInsets.only(bottom: DS.m, left: DS.xxl + DS.xl),
          padding: const EdgeInsets.symmetric(
            horizontal: DS.l + 2,
            vertical: DS.m - 2,
          ),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(DS.rMedium + 2),
              topRight: Radius.circular(DS.rMedium + 2),
              bottomLeft: Radius.circular(DS.rMedium + 2),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: SelectableText(
            message.content,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onPrimary,
            ),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: DS.m, right: DS.xxl + DS.xl),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.providerUsed.startsWith('cloud')
                  ? 'SoulCare AI · Cloud'
                  : 'SoulCare AI · Local',
              style: theme.textTheme.labelSmall?.copyWith(
                color: DS.textTertiary(theme.brightness),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: DS.xs),
            MarkdownBody(
              data: message.content,
              selectable: true,
              styleSheet: _sheet(context),
            ),
            const SizedBox(height: DS.xs),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _time(message.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: DS.textTertiary(theme.brightness),
                  ),
                ),
                if (message.providerUsed != 'local' &&
                    message.providerUsed != 'guard') ...[
                  const SizedBox(width: 6),
                  Text(
                    message.providerUsed,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: DS.textTertiary(theme.brightness),
                    ),
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.copy, size: 15),
                  tooltip: 'Copy',
                  visualDensity: VisualDensity.compact,
                  splashRadius: 16,
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: message.content)),
                ),
                if (showRetry)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 15),
                    tooltip: 'Regenerate',
                    visualDensity: VisualDensity.compact,
                    splashRadius: 16,
                    onPressed: () => context.read<AiChatProvider>().retry(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Streaming answer. Only this widget rebuilds per token — the rest of
/// the list is untouched, keeping long generations smooth.
class _StreamingBubble extends StatelessWidget {
  const _StreamingBubble();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: DS.m, right: DS.xxl + DS.xl),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SoulCare AI',
              style: theme.textTheme.labelSmall?.copyWith(
                color: DS.textTertiary(theme.brightness),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: DS.xs),
            Selector<AiChatProvider, String>(
              selector: (_, p) => p.streaming,
              builder: (_, text, _) => text.isEmpty
                  ? const _ThinkingDots()
                  : MarkdownBody(
                      data: text,
                      selectable: true,
                      styleSheet: _sheet(context),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gentle three-dot thinking indicator used while the first tokens arrive.
class _ThinkingDots extends StatelessWidget {
  const _ThinkingDots();

  @override
  Widget build(BuildContext context) {
    final color = DS.textSecondary(Theme.of(context).brightness);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (context, v, _) => Opacity(
        opacity: 0.55 + 0.45 * v,
        child: Row(
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(right: DS.xs),
                child: Transform.translate(
                  offset: Offset(0, -3 * (1 - v)),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: DS.xs),
            Text(
              'Thinking…',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard();

  @override
  Widget build(BuildContext context) {
    final prov = context.read<AiChatProvider>();
    final isLocal = context.watch<AiChatProvider>().mode == AiMode.local;
    final theme = Theme.of(context);
    final message = context.watch<AiChatProvider>().error ?? '';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.isEmpty
                ? 'Something went wrong while generating the response.'
                : message,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () => prov.retry(),
                child: const Text('Retry'),
              ),
              if (isLocal) ...[
                TextButton(
                  onPressed: () => context.push('/settings/ai'),
                  child: const Text('Open AI Settings'),
                ),
                TextButton(
                  onPressed: () => prov.setMode(AiMode.cloud),
                  child: const Text('Switch to Cloud AI'),
                ),
              ] else
                TextButton(
                  onPressed: () => prov.setMode(AiMode.local),
                  child: const Text('Switch to Local AI'),
                ),
            ],
          ),
          Text(
            isLocal
                ? 'If the local server is stopped, start it and try again. The app never falls back to cloud silently.'
                : 'Cloud AI could not respond. The app never switches backends without telling you.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationSheet extends StatefulWidget {
  const _ConversationSheet();

  @override
  State<_ConversationSheet> createState() => _ConversationSheetState();
}

class _ConversationSheetState extends State<_ConversationSheet> {
  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AiChatProvider>();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Conversations',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: () async {
                    await prov.newConversation();
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('New'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (prov.conversations.isEmpty) const Text('No conversations yet.'),
            for (final c in prov.conversations)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(c.title),
                subtitle: Text(
                  '${c.updatedAt.year}-${c.updatedAt.month.toString().padLeft(2, '0')}-${c.updatedAt.day.toString().padLeft(2, '0')} · ${_providerName(c.providerUsed)}',
                ),
                selected: c.id == prov.activeId,
                onTap: () async {
                  await prov.openConversation(c.id);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      tooltip: 'Rename',
                      onPressed: () => _rename(context, prov, c),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: 'Delete',
                      onPressed: () => prov.deleteConversation(c.id),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                await prov.clearCurrent();
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Clear current conversation'),
            ),
          ],
        ),
      ),
    );
  }

  static String _providerName(String tag) => switch (tag) {
    'local' => 'Local',
    'guard' => 'SoulCare',
    _ when tag.startsWith('cloud:') => 'Cloud · ${tag.substring(6)}',
    _ => tag,
  };

  Future<void> _rename(
    BuildContext context,
    AiChatProvider prov,
    AiConversation c,
  ) async {
    final ctrl = TextEditingController(text: c.title);
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Rename conversation'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(d).pop(ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null) await prov.renameConversation(c.id, name);
  }
}
