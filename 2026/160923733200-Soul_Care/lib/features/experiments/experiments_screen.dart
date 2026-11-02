import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/providers/experiment_provider.dart';
import '../../app/providers/profile_provider.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../data/models/user_profile.dart';
import 'experiment_engine.dart';
import 'experiment_generator.dart';
import 'experiment_templates.dart';

/// /lab — personal wellness experimentation.
/// Templates → confirmed start → daily DONE/MISSED → baseline comparison →
/// results → archive. One active experiment at a time.
class ExperimentsScreen extends StatefulWidget {
  const ExperimentsScreen({super.key});

  @override
  State<ExperimentsScreen> createState() => _ExperimentsScreenState();
}

class _ExperimentsScreenState extends State<ExperimentsScreen> {
  List<ExperimentRecommendation> _recommendations = const [];
  bool _recsLoading = true;
  GeneratorOutput? _generated;
  bool _genLoading = true;
  final Set<String> _dismissed = {};

  /// Focus only reorders data-driven suggestions (reasons untouched).
  List<ExperimentRecommendation> _orderedRecommendations(
      BuildContext context) {
    WellnessFocus? focus;
    try {
      focus = context.watch<ProfileProvider>().profile?.primaryFocus;
    } catch (_) {
      focus = null;
    }
    if (focus == null) return _recommendations;
    return sortByFocus(
        _recommendations, templateForFocusName(focus.name));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<ExperimentProvider>().load();
      if (!mounted) return;
      final recs =
          await context.read<ExperimentProvider>().recommendations();
      if (!mounted) return;
      setState(() {
        _recommendations = recs;
        _recsLoading = false;
      });
      UserProfile? profile;
      try {
        profile = context.read<ProfileProvider>().profile;
      } catch (_) {
        profile = null;
      }
      final gen = await context
          .read<ExperimentProvider>()
          .generatePersonalized(profile: profile);
      if (!mounted) return;
      setState(() {
        _generated = gen;
        _genLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ExperimentProvider>();
    final theme = Theme.of(context);
    final active = prov.activeExperiment;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Lab', style: theme.textTheme.headlineSmall),
        Text('Test small habits against your own logged data',
            style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),

        // 1) Active experiment hero.
        if (prov.loading)
          const AppCard(child: AppLoading(message: 'Loading lab…'))
        else if (active != null)
          _ActiveHero(
            exp: active,
            onChanged: () async {
              final recs =
                  await context.read<ExperimentProvider>().recommendations();
              if (!mounted) return;
              setState(() => _recommendations = recs);
            },
          )
        else
          AppCard(
            child: Row(
              children: [
                Icon(Icons.science_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No active experiment. Start one below — just one at a time.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),

        // 2) Recommended (data-driven, 2–3 max; focus only reorders).
        const SectionHeader(title: 'Recommended for you'),
        const SizedBox(height: 8),
        if (_recsLoading)
          const AppCard(child: AppLoading(message: 'Reading your logs…'))
        else if (_recommendations.isEmpty)
          AppCard(
            child: Text(
              'Log at least 2 days under Today and tailored suggestions will appear here — always with the reason.',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          for (final r in _orderedRecommendations(context)) ...[
            _TemplateCard(
              template: r.template,
              reason: r.reason,
              startable: active == null,
              onStart: () => _startFlow(context, r.template),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 16),

        // 2b) Generated for you (personal, from your logged data).
        const SectionHeader(title: 'Generated for you'),
        const SizedBox(height: 8),
        if (_genLoading)
          const AppCard(
              child: AppLoading(message: 'Analyzing your pattern…'))
        else if (_generated == null || !_generated!.hasSuggestions)
          AppCard(
            child: Text(
              _generated?.insufficientReason ??
                  'Log at least $kGeneratorMinDays days under Today and personal experiments will be generated here from your real pattern.',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          for (final g in _generated!.suggestions.where(
              (s) => !_dismissed.contains(s.title))) ...[
            _GeneratedCard(
              gen: g,
              startable: active == null,
              onApprove: () => _approvalFlow(context, g),
              onDismiss: () =>
                  setState(() => _dismissed.add(g.title)),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 16),

        // 3) All templates.
        const SectionHeader(title: 'All experiments'),
        const SizedBox(height: 8),
        for (final t in experimentTemplates) ...[
          _TemplateCard(
            template: t,
            startable: active == null,
            onStart: () => _startFlow(context, t),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 16),

        // 4) History archive.
        SectionHeader(
          title: 'History',
          actionLabel: 'Custom experiment',
          onAction: () => _customDialog(context),
        ),
        const SizedBox(height: 8),
        if (prov.history.isEmpty)
          AppCard(
            child: Text('No completed or abandoned experiments yet.',
                style: theme.textTheme.bodyMedium),
          )
        else
          for (final e in prov.history) ...[
            _HistoryCard(exp: e),
            const SizedBox(height: 8),
          ],
        if (prov.error != null) ...[
          const SizedBox(height: 8),
          Text(prov.error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _startFlow(
      BuildContext context, ExperimentTemplate template) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StartSheet(template: template),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await context
        .read<ExperimentProvider>()
        .startTemplate(template);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? '"${template.title}" started — Day 1 of ${template.durationDays} ✓'
          : (context.read<ExperimentProvider>().error ??
              'Could not start.')),
    ));
  }

  Future<void> _approvalFlow(
      BuildContext context, GeneratedExperiment gen) async {
    // Explicit approval: the sheet presents everything and only an
    // explicit Start tap begins the experiment. Nothing auto-starts.
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ApprovalSheet(gen: gen),
    );
    if (approved != true || !context.mounted) return;
    final ok =
        await context.read<ExperimentProvider>().startGenerated(gen);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? '"${gen.title}" started — Day 1 of ${gen.durationDays} ✓'
          : (context.read<ExperimentProvider>().error ??
              'Could not start.')),
    ));
    if (ok) {
      setState(() => _dismissed.add(gen.title));
      final recs =
          await context.read<ExperimentProvider>().recommendations();
      if (!mounted) return;
      setState(() => _recommendations = recs);
    }
  }

  Future<void> _customDialog(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Custom experiment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: titleCtrl,
                decoration:
                    const InputDecoration(labelText: 'Title')),
            TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                    labelText: 'What will you try?')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Create')),
        ],
      ),
    );
    titleCtrl.dispose();
    descCtrl.dispose();
    if (ok != true || !context.mounted) return;
    // Custom experiments reuse the generic save path (check-ins only).
    final now = DateTime.now();
    await context.read<ExperimentProvider>().save(Experiment(
      id: generateId(),
      title: titleCtrl.text.trim().isEmpty
          ? 'Custom experiment'
          : titleCtrl.text.trim(),
      description: descCtrl.text.trim(),
      targetMetric: 'personal trend',
      durationDays: 7,
      createdAt: now,
      updatedAt: now,
    ));
  }
}

/// Active experiment hero: Day X of Y, %, streak, DONE/MISSED, baseline peek.
class _ActiveHero extends StatefulWidget {
  final Experiment exp;
  final VoidCallback onChanged;
  const _ActiveHero({required this.exp, required this.onChanged});

  @override
  State<_ActiveHero> createState() => _ActiveHeroState();
}

class _ActiveHeroState extends State<_ActiveHero> {
  bool _busy = false;

  Future<void> _act(Future<bool> Function() call, String doneMsg) async {
    setState(() => _busy = true);
    final ok = await call();
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onChanged();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? doneMsg
          : (context.read<ExperimentProvider>().error ??
              'Could not save.')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final exp = widget.exp;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final day = dayNumber(exp, now);
    final pct = progressFraction(exp, now);
    final streak = currentStreak(exp, now);
    final todayKey = dayKey(now);
    final doneToday = exp.checkIns.contains(todayKey);
    final missedToday = exp.missedDays.contains(todayKey);
    final template = templateById(exp.templateId);

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(template?.icon ?? Icons.science_outlined,
                  color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(exp.title,
                    style: theme.textTheme.titleLarge),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('ACTIVE',
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onPrimaryContainer)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Day $day of ${exp.durationDays} · ${(pct * 100).round()}% complete',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(value: pct, minHeight: 10),
          ),
          const SizedBox(height: 8),
          Text('Current streak: $streak day${streak == 1 ? '' : 's'}',
              style: theme.textTheme.bodyMedium),
          if (doneToday)
            Text('Today: DONE ✓ — tap DONE again to correct a mistake.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.primary)),
          if (missedToday)
            Text('Today: marked MISSED — tap MISSED again to undo.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _act(
                            () => context
                                .read<ExperimentProvider>()
                                .checkInDone(exp),
                            doneToday
                                ? 'Today\'s check-in corrected.'
                                : 'Day $day logged ✓',
                          ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('DONE'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _act(
                            () => context
                                .read<ExperimentProvider>()
                                .checkInMissed(exp),
                            missedToday
                                ? 'Missed mark removed.'
                                : 'Today marked as missed.',
                          ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('MISSED'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Baseline peek.
          FutureBuilder<BaselineComparison?>(
            future: context
                .read<ExperimentProvider>()
                .baselineFor(exp),
            builder: (context, snap) {
              final c = snap.data;
              if (c == null) return const SizedBox.shrink();
              if (!c.hasBaseline) {
                return Text(
                  'No baseline yet — your first logged days will set it.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant),
                );
              }
              return Text(
                'Baseline ${c.metric.label}: ${c.baselineAvg!.toStringAsFixed(1)}${c.metric.unit} '
                '(${c.baselineDays} logged days) · During: '
                '${c.hasCurrent ? '${c.currentAvg!.toStringAsFixed(1)}${c.metric.unit}' : '—'}. '
                'Observed difference only.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant),
              );
            },
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton(
                onPressed: () => _resultsSheet(context, exp),
                child: const Text('View results'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _abandonConfirm(context, exp),
                child: Text('Abandon',
                    style: TextStyle(color: scheme.error)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _abandonConfirm(
      BuildContext context, Experiment exp) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Abandon experiment?'),
        content: Text(
            '"${exp.title}" will move to History. Your logged check-ins stay saved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Keep going')),
          FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Abandon')),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    await context.read<ExperimentProvider>().abandon(exp.id);
    widget.onChanged();
  }

  Future<void> _resultsSheet(
      BuildContext context, Experiment exp) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ResultsSheet(exp: exp),
    );
  }
}

/// Start confirmation: what, duration, tracked, baseline, confirm.
class _StartSheet extends StatelessWidget {
  final ExperimentTemplate template;
  const _StartSheet({required this.template});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(template.icon, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(template.title,
                      style: theme.textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('What you will do', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final step in template.instructions)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• $step',
                    style: theme.textTheme.bodyMedium),
              ),
            const SizedBox(height: 8),
            Text('Duration: ${template.durationDays} days · Effort: ${template.effort.label}',
                style: theme.textTheme.bodyMedium),
            Text('Tracked: ${template.trackedFrom} (your Today logs)',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            FutureBuilder<BaselineComparison?>(
              future: _previewBaseline(context),
              builder: (context, snap) {
                final c = snap.data;
                final text = c == null || !c.hasBaseline
                    ? 'Current baseline: none yet — your first days will set it.'
                    : 'Current baseline: ${c.baselineAvg!.toStringAsFixed(1)}${c.metric.unit} average ${c.metric.label} over ${c.baselineDays} logged days.';
                return AppCard(
                  child: Text(text,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant)),
                );
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                  'Start ${template.durationDays}-day experiment'),
            ),
          ],
        ),
      ),
    );
  }

  /// Baseline over the 7 days before today for this template's metric.
  Future<BaselineComparison?> _previewBaseline(
      BuildContext context) async {
    final now = DateTime.now();
    final preview = Experiment(
      id: 'preview',
      templateId: template.id,
      title: template.title,
      description: template.explanation,
      targetMetric: template.targetMetric,
      durationDays: template.durationDays,
      startDate: DateTime(now.year, now.month, now.day),
      endDate: DateTime(now.year, now.month, now.day),
      status: ExperimentStatus.draft,
      createdAt: now,
      updatedAt: now,
    );
    try {
      return await context
          .read<ExperimentProvider>()
          .baselineFor(preview);
    } catch (_) {
      return null;
    }
  }
}

/// Personal generated-experiment card with data-backed reasoning.
class _GeneratedCard extends StatelessWidget {
  final GeneratedExperiment gen;
  final bool startable;
  final VoidCallback onApprove;
  final VoidCallback onDismiss;

  const _GeneratedCard({
    required this.gen,
    required this.startable,
    required this.onApprove,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final template = templateById(gen.templateId);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(template?.icon ?? Icons.auto_awesome_outlined,
                  color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(gen.title,
                    style: theme.textTheme.titleSmall),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('PERSONAL',
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSecondaryContainer)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Observation', style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant)),
          Text(gen.observation, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text('Hypothesis', style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant)),
          Text(gen.hypothesis, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(gen.baselineText,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.primary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: startable ? onApprove : null,
                  child: Text(startable
                      ? 'Review & approve'
                      : 'Finish current first'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                  onPressed: onDismiss,
                  child: const Text('Not now')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Explicit approval sheet: full details first, Start only on tap.
class _ApprovalSheet extends StatelessWidget {
  final GeneratedExperiment gen;
  const _ApprovalSheet({required this.gen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Approve this experiment?',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(gen.title, style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.primary)),
            const SizedBox(height: 12),
            _Row(label: 'Observation', value: gen.observation),
            _Row(label: 'Hypothesis', value: gen.hypothesis),
            _Row(label: 'Action', value: gen.action),
            _Row(label: 'Duration',
                value: '${gen.durationDays} days'),
            _Row(label: 'Measure', value: gen.measureLabel),
            _Row(label: 'Baseline', value: gen.baselineText),
            _Row(label: 'Success', value: gen.successCriteria),
            _Row(label: 'Daily check-in',
                value: gen.checkInRequirement),
            const SizedBox(height: 8),
            AppCard(
              child: Text(
                'Nothing starts until you tap Start. One experiment runs at a time; results compare your baseline with the experiment period as an observed difference only.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(true),
                    child: const Text('Start experiment'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Template card with optional data-based reason.
class _TemplateCard extends StatelessWidget {
  final ExperimentTemplate template;
  final String? reason;
  final bool startable;
  final VoidCallback onStart;

  const _TemplateCard({
    required this.template,
    this.reason,
    required this.startable,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(template.icon, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(template.title,
                    style: theme.textTheme.titleSmall),
              ),
              Text(
                '${template.durationDays}d · ${template.effort.label}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(template.explanation,
              style: theme.textTheme.bodySmall),
          if (reason != null) ...[
            const SizedBox(height: 4),
            Text(reason!,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.primary)),
          ],
          const SizedBox(height: 8),
          FilledButton.tonal(
            key: ValueKey('template-start-${template.id}'),
            onPressed: startable ? onStart : null,
            child: Text(startable
                ? 'Start'
                : 'Finish current first'),
          ),
        ],
      ),
    );
  }
}

/// Archived experiment with viewable results.
class _HistoryCard extends StatelessWidget {
  final Experiment exp;
  const _HistoryCard({required this.exp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _ResultsSheet(exp: exp),
      ),
      child: Row(
        children: [
          Icon(
            exp.status == ExperimentStatus.completed
                ? Icons.check_circle_outline
                : Icons.cancel_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exp.title,
                    style: theme.textTheme.titleSmall),
                Text(
                  '${exp.status.label} · ${exp.checkIns.length}/${exp.durationDays} days',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

/// Results sheet: rate, streak, baseline, average, change, factual summary.
class _ResultsSheet extends StatelessWidget {
  final Experiment exp;
  const _ResultsSheet({required this.exp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(exp.title, style: theme.textTheme.titleLarge),
            Text('${exp.status.label} · ${exp.durationDays} days',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            FutureBuilder<ExperimentResults?>(
              future: context
                  .read<ExperimentProvider>()
                  .resultsFor(exp),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const AppLoading(
                      message: 'Comparing with your baseline…');
                }
                final r = snap.data!;
                final c = r.comparison;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ResultRow(
                        label: 'Completion rate',
                        value:
                            '${(r.completionRate * 100).round()}% (${r.doneDays}/${exp.durationDays})'),
                    _ResultRow(
                        label: 'Best streak',
                        value:
                            '${r.bestStreak} day${r.bestStreak == 1 ? '' : 's'}'),
                    _ResultRow(
                        label: 'Baseline ${c.metric.label}',
                        value: c.hasBaseline
                            ? '${c.baselineAvg!.toStringAsFixed(1)}${c.metric.unit} (${c.baselineDays} days)'
                            : 'no logged baseline'),
                    _ResultRow(
                        label: 'Experiment average',
                        value: c.hasCurrent
                            ? '${c.currentAvg!.toStringAsFixed(1)}${c.metric.unit} (${c.currentDays} days)'
                            : 'no logged days yet'),
                    _ResultRow(
                        label: 'Change',
                        value: c.delta == null
                            ? '—'
                            : '${c.delta! >= 0 ? '+' : ''}${c.delta!.toStringAsFixed(1)}${c.metric.unit}'),
                    const SizedBox(height: 8),
                    AppCard(
                      child: Text(r.summary,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(
                                  color: scheme.onSurfaceVariant)),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  const _ResultRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(value, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}
