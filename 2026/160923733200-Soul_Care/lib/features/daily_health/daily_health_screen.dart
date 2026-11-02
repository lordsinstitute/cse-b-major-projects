import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/providers/daily_health_provider.dart';
import '../../app/providers/health_import_provider.dart';
import '../../app/theme/design_system.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import 'breathing_reset.dart';

const _triggerOptions = ['Work', 'Relationships', 'Health', 'Money', 'Other'];

const _exerciseTypes = [
  'Walk',
  'Run',
  'Cycle',
  'Swim',
  'Yoga',
  'Strength',
  'Other',
];

/// /today — fast mobile logging with per-section partial saves.
/// Each section saves independently; yesterday's values are offered as
/// opt-in suggestions and never silently overwrite today's data.
class DailyHealthScreen extends StatefulWidget {
  const DailyHealthScreen({super.key});

  @override
  State<DailyHealthScreen> createState() => _DailyHealthScreenState();
}

class _DailyHealthScreenState extends State<DailyHealthScreen> {
  bool _seeded = false;
  String? _saving;

  // Sleep
  double _sleep = 7;
  int _sleepQuality = 4;
  bool _rested = true;
  // Movement
  String _exerciseType = 'Walk';
  int _exerciseMin = 30;
  ExerciseIntensity _intensity = ExerciseIntensity.moderate;
  // Nutrition
  int _meal = 4;
  int _water = 6;
  // Mind
  int _meditation = 10;
  double _screen = 2;
  // Stress
  int _mood = 3;
  final Set<String> _triggers = {};
  double _control = 0.5;
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _seed(DailyHealthEntry e) {
    if (e.sleepHours > 0) {
      _sleep = e.sleepHours;
      _sleepQuality = e.sleepQuality.score;
      _rested = e.feltRested;
    }
    if (e.exerciseMinutes > 0) {
      _exerciseMin = e.exerciseMinutes;
      _intensity = e.exerciseIntensity;
      if (e.exerciseType != null && e.exerciseType!.isNotEmpty) {
        _exerciseType = e.exerciseType!;
      }
    }
    if (e.waterGlasses > 0) {
      _water = e.waterGlasses;
      _meal = e.mealQuality.score;
    }
    if (e.meditationMinutes > 0) {
      _meditation = e.meditationMinutes;
      _screen = e.screenTimeHours;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DailyHealthProvider>().loadToday();
      try {
        context.read<HealthImportProvider>().refresh();
      } catch (_) {}
    });
  }

  Future<void> _save(String section, Future<bool> Function() call) async {
    setState(() => _saving = section);
    final ok = await call();
    if (!mounted) return;
    setState(() => _saving = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '$section saved ✓'
              : (context.read<DailyHealthProvider>().error ??
                    'Could not save. Previously saved sections are intact.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DailyHealthProvider>();
    if (provider.today != null && !_seeded) {
      _seed(provider.today!);
      _seeded = true;
    }
    final theme = Theme.of(context);
    final yesterday = provider.yesterday;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        DS.xl,
        DS.huge - DS.xl,
        DS.xl,
        DS.massive,
      ),
      children: [
        Text(
          'Today',
          style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: -0.5),
        ),
        Text(
          provider.todayKey,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: DS.textSecondary(theme.brightness),
          ),
        ),
        const SizedBox(height: DS.l),
        // Completion header.
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Daily Progress', style: theme.textTheme.titleSmall),
                  Text(
                    '${provider.completedSections} / ${DailyHealthProvider.totalSections} sections completed',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value:
                      provider.completedSections /
                      DailyHealthProvider.totalSections,
                  minHeight: 8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Imported platform data (only when connected + present).
        const _ImportedCard(),
        if (provider.loading && provider.today == null)
          const AppLoading(message: 'Loading today…')
        else ...[
          // ---- SLEEP ----
          _SectionCard(
            title: 'Sleep',
            done: provider.sleepDone,
            suggestion: (yesterday != null && yesterday.sleepHours > 0)
                ? 'Yesterday: ${formatHours(yesterday.sleepHours)}'
                : null,
            onUseYesterday: (yesterday != null && yesterday.sleepHours > 0)
                ? () => setState(() {
                    _sleep = yesterday.sleepHours;
                    _sleepQuality = yesterday.sleepQuality.score;
                    _rested = yesterday.feltRested;
                  })
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hours: ${formatHours(_sleep)}',
                  style: theme.textTheme.titleSmall,
                ),
                Slider(
                  min: 0,
                  max: 12,
                  divisions: 24,
                  value: _sleep,
                  label: formatHours(_sleep),
                  onChanged: (v) => setState(() => _sleep = v),
                ),
                Text('Quality', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      ChoiceChip(
                        label: Text('$i'),
                        selected: _sleepQuality == i,
                        onSelected: (_) => setState(() => _sleepQuality = i),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Felt rested'),
                  value: _rested,
                  onChanged: (v) => setState(() => _rested = v),
                ),
                _SaveButton(
                  label: 'Save Sleep',
                  saving: _saving == 'Sleep',
                  onPressed: () => _save(
                    'Sleep',
                    () => context.read<DailyHealthProvider>().saveSleep(
                      hours: _sleep,
                      quality: SleepQualityX.fromScore(_sleepQuality),
                      feltRested: _rested,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ---- MOVEMENT ----
          _SectionCard(
            title: 'Movement',
            done: provider.movementDone,
            suggestion: (yesterday != null && yesterday.exerciseMinutes > 0)
                ? 'Yesterday: ${yesterday.exerciseMinutes} min'
                : null,
            onUseYesterday: (yesterday != null && yesterday.exerciseMinutes > 0)
                ? () => setState(() {
                    _exerciseMin = yesterday.exerciseMinutes;
                    _intensity = yesterday.exerciseIntensity;
                    if (yesterday.exerciseType != null &&
                        yesterday.exerciseType!.isNotEmpty) {
                      _exerciseType = yesterday.exerciseType!;
                    }
                  })
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Type', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in _exerciseTypes)
                      ChoiceChip(
                        label: Text(t),
                        selected: _exerciseType == t,
                        onSelected: (_) => setState(() => _exerciseType = t),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Duration: $_exerciseMin min',
                  style: theme.textTheme.titleSmall,
                ),
                Slider(
                  min: 0,
                  max: 180,
                  divisions: 36,
                  value: _exerciseMin.toDouble(),
                  label: '$_exerciseMin min',
                  onChanged: (v) => setState(() => _exerciseMin = v.round()),
                ),
                Text('Intensity', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final level in ExerciseIntensity.values)
                      ChoiceChip(
                        label: Text(level.label),
                        selected: _intensity == level,
                        onSelected: (_) => setState(() => _intensity = level),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _SaveButton(
                  label: 'Save Movement',
                  saving: _saving == 'Movement',
                  onPressed: () => _save(
                    'Movement',
                    () => context.read<DailyHealthProvider>().saveMovement(
                      type: _exerciseType,
                      minutes: _exerciseMin,
                      intensity: _intensity,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ---- NUTRITION ----
          _SectionCard(
            title: 'Nutrition & Hydration',
            done: provider.nutritionDone,
            suggestion: (yesterday != null && yesterday.waterGlasses > 0)
                ? 'Yesterday: ${yesterday.waterGlasses} glasses'
                : null,
            onUseYesterday: (yesterday != null && yesterday.waterGlasses > 0)
                ? () => setState(() {
                    _water = yesterday.waterGlasses;
                    _meal = yesterday.mealQuality.score;
                  })
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Meal quality', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      ChoiceChip(
                        label: Text('$i'),
                        selected: _meal == i,
                        onSelected: (_) => setState(() => _meal = i),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Water: $_water glasses',
                  style: theme.textTheme.titleSmall,
                ),
                Slider(
                  min: 0,
                  max: 16,
                  divisions: 16,
                  value: _water.toDouble(),
                  label: '$_water',
                  onChanged: (v) => setState(() => _water = v.round()),
                ),
                _SaveButton(
                  label: 'Save Nutrition',
                  saving: _saving == 'Nutrition',
                  onPressed: () => _save(
                    'Nutrition',
                    () => context.read<DailyHealthProvider>().saveNutrition(
                      mealQuality: MealQualityX.fromScore(_meal),
                      waterGlasses: _water,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ---- MIND ----
          _SectionCard(
            title: 'Mind',
            done: provider.mindDone,
            suggestion: (yesterday != null && yesterday.meditationMinutes > 0)
                ? 'Yesterday: ${yesterday.meditationMinutes} min meditation'
                : null,
            onUseYesterday:
                (yesterday != null && yesterday.meditationMinutes > 0)
                ? () => setState(() {
                    _meditation = yesterday.meditationMinutes;
                    _screen = yesterday.screenTimeHours;
                  })
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Meditation: $_meditation min',
                  style: theme.textTheme.titleSmall,
                ),
                Slider(
                  min: 0,
                  max: 60,
                  divisions: 12,
                  value: _meditation.toDouble(),
                  label: '$_meditation min',
                  onChanged: (v) => setState(() => _meditation = v.round()),
                ),
                Text(
                  'Screen time: ${_screen.toStringAsFixed(1)}h',
                  style: theme.textTheme.titleSmall,
                ),
                Slider(
                  min: 0,
                  max: 12,
                  divisions: 24,
                  value: _screen,
                  label: '${_screen.toStringAsFixed(1)}h',
                  onChanged: (v) => setState(() => _screen = v),
                ),
                _SaveButton(
                  label: 'Save Mind',
                  saving: _saving == 'Mind',
                  onPressed: () => _save(
                    'Mind',
                    () => context.read<DailyHealthProvider>().saveMind(
                      meditationMinutes: _meditation,
                      screenTimeHours: _screen,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ---- STRESS ----
          _SectionCard(
            title: 'Stress',
            done: provider.stressDone,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mood (1–5)', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      ChoiceChip(
                        label: Text('$i'),
                        selected: _mood == i,
                        onSelected: (_) => setState(() => _mood = i),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Triggers', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in _triggerOptions)
                      FilterChip(
                        label: Text(t),
                        selected: _triggers.contains(t),
                        onSelected: (sel) => setState(() {
                          if (sel) {
                            _triggers.add(t);
                          } else {
                            _triggers.remove(t);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Controllability', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                SegmentedButton<double>(
                  segments: const [
                    ButtonSegment(value: 1.0, label: Text('Controllable')),
                    ButtonSegment(value: 0.5, label: Text('Partial')),
                    ButtonSegment(value: 0.0, label: Text('Uncontrollable')),
                  ],
                  selected: {_control},
                  onSelectionChanged: (s) => setState(() => _control = s.first),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'Anything worth remembering…',
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _SaveButton(
                        label: 'Save check-in',
                        saving: _saving == 'Stress',
                        onPressed: () => _save(
                          'Stress',
                          () => context
                              .read<DailyHealthProvider>()
                              .saveStressCheck(
                                mood: MoodX.fromScore(_mood),
                                triggers: _triggers.toList(),
                                controllability: _control,
                                notes: _notesController.text,
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => showBreathingReset(context),
                        child: const Text('Breathing reset'),
                      ),
                    ),
                  ],
                ),
                if (provider.todayStress.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Today: ${provider.todayStress.length} check-in${provider.todayStress.length == 1 ? '' : 's'} logged ✓',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        if (provider.error != null) ...[
          Text(
            provider.error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// Section wrapper with subtle check state + opt-in yesterday suggestion.
class _SectionCard extends StatelessWidget {
  final String title;
  final bool done;
  final String? suggestion;
  final VoidCallback? onUseYesterday;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.done,
    required this.child,
    this.suggestion,
    this.onUseYesterday,
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
              if (done)
                Icon(Icons.check_circle, size: 20, color: scheme.primary),
              if (done) const SizedBox(width: 6),
              Text(title, style: theme.textTheme.titleMedium),
            ],
          ),
          if (suggestion != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withAlpha(128),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(suggestion!, style: theme.textTheme.bodySmall),
                  ),
                  TextButton(
                    onPressed: onUseYesterday,
                    child: const Text('Use'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final String label;
  final bool saving;
  final VoidCallback onPressed;

  const _SaveButton({
    required this.label,
    required this.saving,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Key per label keeps the scroll-to-save test reliable per section.
    return FilledButton(
      key: ValueKey('save-$label'),
      onPressed: saving ? null : onPressed,
      child: Text(saving ? 'Saving…' : label.replaceFirst('Save ', 'Save ')),
    );
  }
}

/// Imported platform data for today, shown ALONGSIDE manual logs with
/// clear "Imported" badges. Hidden unless connected with data present.
class _ImportedCard extends StatelessWidget {
  const _ImportedCard();

  @override
  Widget build(BuildContext context) {
    HealthImportProvider? link;
    try {
      link = context.watch<HealthImportProvider>();
    } catch (_) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final day = link.dayFor(context.read<DailyHealthProvider>().todayKey);
    if (link.status != HealthLinkStatus.connected ||
        day == null ||
        !day.hasAny) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('From your device', style: theme.textTheme.titleSmall),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Imported',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (day.sleepHours > 0)
              Text(
                'Sleep: ${formatHours(day.sleepHours)}',
                style: theme.textTheme.bodyMedium,
              ),
            if (day.steps > 0)
              Text('Steps: ${day.steps}', style: theme.textTheme.bodyMedium),
            if (day.exerciseMin > 0)
              Text(
                'Exercise: ${day.exerciseMin} min',
                style: theme.textTheme.bodyMedium,
              ),
            if (day.heartRateAvg != null)
              Text(
                'Heart rate: ${day.heartRateAvg!.round()} bpm avg',
                style: theme.textTheme.bodyMedium,
              ),
            Text(
              'Sources: ${day.sources.join(', ')} · shown next to your manual logs, never merged into them.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
