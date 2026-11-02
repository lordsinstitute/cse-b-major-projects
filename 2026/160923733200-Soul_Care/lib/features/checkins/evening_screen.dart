import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/providers/checkin_providers.dart';
import '../../app/providers/daily_health_provider.dart';
import '../../app/providers/experiment_provider.dart';
import '../../app/theme/design_system.dart';
import '../../core/extensions/extensions.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/checkins.dart';
import '../../features/experiments/experiment_engine.dart';

/// Lightweight evening reflection: mood, energy, strain, two optional
/// notes. Saving shows "Today at a glance" — completion, wellness score,
/// logged metrics, experiment progress, one factual sentence.
class EveningScreen extends StatefulWidget {
  const EveningScreen({super.key});

  @override
  State<EveningScreen> createState() => _EveningScreenState();
}

class _EveningScreenState extends State<EveningScreen> {
  int _mood = 3;
  int _energy = 3;
  int _stress = 3;
  final _well = TextEditingController();
  final _better = TextEditingController();
  bool _seeded = false;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EveningProvider>().loadToday();
      context.read<DailyHealthProvider>().loadToday();
      context.read<ExperimentProvider>().load();
    });
  }

  @override
  void dispose() {
    _well.dispose();
    _better.dispose();
    super.dispose();
  }

  void _seed(EveningReflection r) {
    _mood = r.mood;
    _energy = r.energy;
    _stress = r.stress;
    _well.text = r.wentWell ?? '';
    _better.text = r.improve ?? '';
  }

  Future<void> _save() async {
    final prov = context.read<EveningProvider>();
    setState(() => _saving = true);
    final ok = await prov.save(
      EveningReflection(
        date: prov.todayKey,
        mood: _mood,
        energy: _energy,
        stress: _stress,
        wentWell: _well.text.trim().isEmpty ? null : _well.text.trim(),
        improve: _better.text.trim().isEmpty ? null : _better.text.trim(),
        updatedAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = ok;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(prov.error ?? 'Could not save. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<EveningProvider>();
    if (prov.today != null && !_seeded) {
      _seed(prov.today!);
      _seeded = true;
      _saved = true;
    }
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Evening reflection')),
      body: prov.loading && prov.today == null
          ? const AppLoading(message: 'Loading…')
          : _saved && prov.today != null
          ? _Glance(onEdit: () => setState(() => _saved = false))
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                DS.xl,
                DS.l,
                DS.xl,
                DS.massive,
              ),
              children: [
                Text(
                  'Good evening',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'A quiet minute to close the day.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: DS.textSecondary(theme.brightness),
                  ),
                ),
                const SizedBox(height: DS.l),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mood', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      _ScaleRow(
                        value: _mood,
                        onPick: (v) => setState(() => _mood = v),
                      ),
                      const SizedBox(height: 8),
                      Text('Energy', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      _ScaleRow(
                        value: _energy,
                        onPick: (v) => setState(() => _energy = v),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Stress (1 calm … 5 high)',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      _ScaleRow(
                        value: _stress,
                        onPick: (v) => setState(() => _stress = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reflection (optional)',
                        style: theme.textTheme.titleSmall,
                      ),
                      TextField(
                        controller: _well,
                        maxLines: 2,
                        maxLength: 500,
                        decoration: const InputDecoration(
                          labelText: 'What went well today?',
                        ),
                      ),
                      TextField(
                        controller: _better,
                        maxLines: 2,
                        maxLength: 500,
                        decoration: const InputDecoration(
                          labelText: 'What could have gone better?',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save reflection'),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _ScaleRow extends StatelessWidget {
  final int value;
  final ValueChanged<int> onPick;
  const _ScaleRow({required this.value, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final reduce = DS.reduceMotion(context);
    return Wrap(
      spacing: 8,
      children: [
        for (var i = 1; i <= 5; i++)
          AnimatedScale(
            scale: value == i ? 1.06 : 1.0,
            duration: reduce ? Duration.zero : const Duration(milliseconds: 160),
            curve: DS.curveEntrance,
            child: ChoiceChip(
              label: Text('$i', style: const TextStyle(fontSize: 16)),
              selected: value == i,
              onSelected: (_) => onPick(i),
            ),
          ),
      ],
    );
  }
}

class _Glance extends StatelessWidget {
  final VoidCallback onEdit;
  const _Glance({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final daily = context.watch<DailyHealthProvider>();
    final expProv = context.watch<ExperimentProvider>();
    final active = expProv.activeExperiment;
    final entry = daily.today;
    final score = daily.todayWellnessScore;

    final expLine = active == null
        ? 'No active experiment.'
        : '${active.title}: Day ${dayNumber(active, DateTime.now())} of ${active.durationDays}, '
              '${active.checkIns.length} check-ins.';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Today at a glance', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              _summaryRow(
                'Daily sections',
                '${daily.completedSections} / ${DailyHealthProvider.totalSections}',
              ),
              _summaryRow('Wellness', '$score'),
              _summaryRow('Sleep', '${entry?.sleepHours.toFixed(1) ?? '—'}h'),
              _summaryRow('Exercise', '${entry?.exerciseMinutes ?? '—'} min'),
              _summaryRow('Water', '${entry?.waterGlasses ?? '—'}/8'),
              _summaryRow(
                'Meditation',
                '${entry?.meditationMinutes ?? '—'} min',
              ),
              const SizedBox(height: 8),
              Text(expLine, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(
                _factualSummary(
                  score: score,
                  done: daily.completedSections,
                  total: DailyHealthProvider.totalSections,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: onEdit,
                child: const Text('Edit reflection'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Builder(
      builder: (context) {
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
      },
    );
  }

  static String _factualSummary({
    required int score,
    required int done,
    required int total,
  }) {
    if (done == 0) {
      return 'Nothing logged today yet — tomorrow is a fresh page. Illustrative summary, not a medical assessment.';
    }
    return 'You completed $done of $total daily sections with a wellness score of $score, based on your logged data. Illustrative summary, not a medical assessment.';
  }
}
