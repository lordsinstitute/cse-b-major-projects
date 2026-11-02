import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/providers/milestones_provider.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/app_widgets.dart';
import 'milestone_engine.dart';

/// /milestones — quiet recognition for consistency and progress.
/// No points, no leaderboards, no hidden achievements: every milestone is
/// listed with its state, all derived from real logged data. New unlocks
/// get one brief, calm acknowledgment — never game-like effects.
class MilestonesScreen extends StatefulWidget {
  const MilestonesScreen({super.key});

  @override
  State<MilestonesScreen> createState() => _MilestonesScreenState();
}

class _MilestonesScreenState extends State<MilestonesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<MilestonesProvider>().load();
      if (!mounted) return;
      final fresh =
          context.read<MilestonesProvider>().uncelebrated;
      if (fresh.isNotEmpty) {
        fresh.sort((a, b) {
          final da = a.achievedDate;
          final db = b.achievedDate;
          if (da == null || db == null) return 0;
          return db.compareTo(da);
        });
        await _celebrate(context, fresh.first);
      }
    });
  }

  Future<void> _celebrate(
      BuildContext context, MilestoneStatus m) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (c) => _CalmCelebration(status: m),
    );
    if (context.mounted) {
      await context.read<MilestonesProvider>().celebrate(m.def.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<MilestonesProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final next = prov.next;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Milestones'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => prov.load(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Quiet recognition',
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text(
              'Milestones mark consistency, reflection and finished experiments — computed from your logs, never gamed, never bought.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (prov.loading && prov.all.isEmpty)
              const AppCard(
                  child: AppLoading(message: 'Reading your journey…'))
            else ...[
              if (next != null) ...[
                _NextCard(status: next),
                const SizedBox(height: 12),
              ],
              if (prov.unlocked.isNotEmpty) ...[
                const SectionHeader(title: 'Unlocked'),
                const SizedBox(height: 8),
                for (final m in prov.unlocked) ...[
                  _MilestoneCard(status: m),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
              ],
              const SectionHeader(title: 'In progress'),
              const SizedBox(height: 8),
              if (prov.locked.isEmpty)
                AppCard(
                  child: Text(
                    'Every milestone is unlocked. Beautiful consistency.',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              else
                for (final m in prov.locked) ...[
                  _MilestoneCard(status: m),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}

class _NextCard extends StatelessWidget {
  final MilestoneStatus status;
  const _NextCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = status;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Next milestone',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          Text(m.def.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(m.def.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: m.def.target <= 0
                  ? 0
                  : (m.progress / m.def.target).clamp(0.0, 1.0),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 4),
          Text('${m.progress} / ${m.def.target} days',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  final MilestoneStatus status;
  const _MilestoneCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = status;
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: m.unlocked
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
            ),
            alignment: Alignment.center,
            child: Icon(
              m.unlocked
                  ? Icons.verified_outlined
                  : Icons.lock_outline,
              size: 22,
              color: m.unlocked
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.def.title.toUpperCase(),
                    style: theme.textTheme.titleSmall?.copyWith(
                        letterSpacing: 0.6)),
                Text(m.def.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(
                  m.unlocked
                      ? 'First achieved: ${m.achievedDate == null ? '—' : formatDate(m.achievedDate!)}'
                      : '${m.progress} / ${m.def.target} days',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: m.unlocked
                          ? scheme.primary
                          : scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One brief, calm acknowledgment: slow fade + gentle scale, soft icon,
/// no confetti, no sound, no game effects.
class _CalmCelebration extends StatefulWidget {
  final MilestoneStatus status;
  const _CalmCelebration({required this.status});

  @override
  State<_CalmCelebration> createState() => _CalmCelebrationState();
}

class _CalmCelebrationState extends State<_CalmCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scale = Tween(begin: 0.92, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = widget.status;
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SoulCareMark(size: 72),
              const SizedBox(height: 16),
              Text(m.def.title.toUpperCase(),
                  style: theme.textTheme.titleLarge?.copyWith(
                      letterSpacing: 0.8),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(m.def.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
              if (m.achievedDate != null) ...[
                const SizedBox(height: 4),
                Text(
                    'First achieved: ${formatDate(m.achievedDate!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () =>
                      Navigator.of(context).pop(),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
