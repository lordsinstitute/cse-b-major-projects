import 'package:flutter/material.dart';

import '../../app/theme/design_system.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';

/// Trend of the second half of the week vs the first half.
enum GoalTrend { up, down, steady, unknown }

/// Computed progress for one personal target. Only achieved amounts count —
/// missing days contribute nothing (never rewarded).
class GoalProgress {
  final String label;
  final double current;
  final double target;
  final String unit;
  final GoalTrend trend;

  const GoalProgress({
    required this.label,
    required this.current,
    required this.target,
    required this.unit,
    required this.trend,
  });

  double get fraction => target <= 0 ? 0 : (current / target).clamp(0.0, 1.0);
  int get percent => (fraction * 100).round();
  double get remaining =>
      target <= 0 ? 0 : (target - current).clamp(0.0, double.infinity);

  String get trendGlyph {
    switch (trend) {
      case GoalTrend.up:
        return '▲';
      case GoalTrend.down:
        return '▼';
      case GoalTrend.steady:
        return '●';
      case GoalTrend.unknown:
        return '○';
    }
  }
}

/// Pure computation over logged per-day values (oldest → newest).
GoalProgress computeGoalProgress({
  required String label,
  required List<double> weekValues,
  required double target,
  required String unit,
  bool sumInsteadOfAverage = false,
}) {
  final vals = weekValues.where((v) => v.isFinite).toList();
  double current;
  if (vals.isEmpty) {
    current = 0;
  } else if (sumInsteadOfAverage) {
    current = vals.reduce((a, b) => a + b);
  } else {
    current = vals.reduce((a, b) => a + b) / vals.length;
  }
  GoalTrend trend = GoalTrend.unknown;
  if (vals.length >= 3) {
    final half = vals.length ~/ 2;
    final first = vals.take(half).reduce((a, b) => a + b) / half;
    final rest = vals.skip(half).toList();
    final second = rest.reduce((a, b) => a + b) / rest.length;
    final base = first.abs() < 1e-9 ? 1.0 : first.abs();
    final delta = (second - first) / base;
    trend = delta > 0.05
        ? GoalTrend.up
        : delta < -0.05
        ? GoalTrend.down
        : GoalTrend.steady;
  }
  return GoalProgress(
    label: label,
    current: current,
    target: target,
    unit: unit,
    trend: trend,
  );
}

/// Builds the four goal measurements from a logged week (oldest →
/// newest DailyHealthEntry list; unlogged zeros handled per goal).
/// Shared by the dashboard strip and the action center.
List<(String, GoalProgress)> computeGoalItems({
  required List<DailyHealthEntry> entries,
  required double sleepTarget,
  required double exerciseTarget,
  required double waterTarget,
  required double meditationTarget,
}) {
  final sleepVals = [
    for (final e in entries)
      if (e.sleepHours > 0) e.sleepHours,
  ];
  final waterVals = [
    for (final e in entries)
      if (e.waterGlasses > 0) e.waterGlasses.toDouble(),
  ];
  final medVals = [for (final e in entries) e.meditationMinutes.toDouble()];
  final exerciseVals = [for (final e in entries) e.exerciseMinutes.toDouble()];
  return [
    (
      'sleep',
      computeGoalProgress(
        label: 'Sleep Goal',
        weekValues: sleepVals,
        target: sleepTarget,
        unit: 'h',
      ),
    ),
    (
      'exercise',
      computeGoalProgress(
        label: 'Exercise Goal',
        weekValues: exerciseVals,
        target: exerciseTarget,
        unit: ' min',
        sumInsteadOfAverage: true,
      ),
    ),
    (
      'water',
      computeGoalProgress(
        label: 'Water Goal',
        weekValues: waterVals,
        target: waterTarget,
        unit: '',
      ),
    ),
    (
      'meditation',
      computeGoalProgress(
        label: 'Meditation Goal',
        weekValues: medVals,
        target: meditationTarget,
        unit: ' min',
      ),
    ),
  ];
}

String formatGoalValue(double v, String unit) {
  final num = v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
  return '$num$unit';
}

/// Goal key matching a wellness-focus name (for ordering only).
/// Null means no specific goal (general/consistency/unknown).
String? goalKeyForFocusName(String focusName) {
  switch (focusName) {
    case 'betterSleep':
      return 'sleep';
    case 'moreMovement':
      return 'exercise';
    case 'stressManagement':
    case 'mindfulness':
      return 'meditation';
    case 'hydration':
      return 'water';
    default:
      return null;
  }
}

/// Orders goals: focus match first, then lowest completion first.
/// Stable, deterministic, capped by the caller.
List<(String, GoalProgress)> orderGoalsForFocus(
  List<(String, GoalProgress)> goals,
  String? focusKey,
) {
  final sorted = [...goals]
    ..sort((a, b) {
      final aFirst = a.$1 == focusKey ? 0 : 1;
      final bFirst = b.$1 == focusKey ? 0 : 1;
      if (aFirst != bFirst) return aFirst.compareTo(bFirst);
      return a.$2.fraction.compareTo(b.$2.fraction);
    });
  return sorted;
}

/// Compact reusable goal card: current/target, bar, %, trend, remaining.
class GoalProgressCard extends StatelessWidget {
  final GoalProgress progress;
  final bool compact;

  const GoalProgressCard({
    super.key,
    required this.progress,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = progress;
    // Keep the same values and strings — only color changes to the
    // metric's semantic hue (sleep/indigo, movement/green, …).
    final accent = switch (p.label) {
      'Sleep Goal' => DS.metric(theme.brightness, MetricDomain.sleep),
      'Exercise Goal' => DS.metric(theme.brightness, MetricDomain.activity),
      'Water Goal' => DS.metric(theme.brightness, MetricDomain.hydration),
      'Meditation Goal' => DS.metric(theme.brightness, MetricDomain.mood),
      _ => theme.colorScheme.primary,
    };
    return AppCard(
      padding: EdgeInsets.all(compact ? 14 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(p.label, style: theme.textTheme.titleSmall),
              Text(
                '${p.trendGlyph} ${p.percent}%',
                style: theme.textTheme.titleSmall?.copyWith(color: accent),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${formatGoalValue(p.current, p.unit)} / ${formatGoalValue(p.target, p.unit)}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: p.fraction),
            duration: const Duration(milliseconds: 650),
            curve: DS.curveEntrance,
            builder: (context, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 7,
                color: accent,
                backgroundColor: theme.colorScheme.outline.withValues(
                  alpha: 0.12,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            p.remaining <= 0
                ? 'Target reached — based on your logged data ✓'
                : '${formatGoalValue(p.remaining, p.unit)} to go',
            style: theme.textTheme.bodySmall?.copyWith(
              color: DS.textSecondary(theme.brightness),
            ),
          ),
        ],
      ),
    );
  }
}
