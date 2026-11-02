import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../utils/utils.dart';

/// Centralized, deterministic wellness-score calculator.
///
/// Pure functions only: same inputs always produce the same outputs.
/// The score is an illustrative summary of *logged* data — never a
/// medical assessment, diagnosis, or validated clinical measure.
class WellnessScore {
  final int totalScore;
  final int sleepScore;
  final int movementScore;
  final int hydrationScore;
  final int mindScore;
  final int stressScore;
  final int consistencyScore;

  /// Score for the previous day, when available.
  final int? previousScore;

  /// totalScore - previousScore, when a previous day exists.
  final int? change;

  /// Data-supported explanation (only references actual logged values).
  final String explanation;

  /// Human-readable per-component data contributions.
  final Map<String, String> contributions;

  const WellnessScore({
    required this.totalScore,
    required this.sleepScore,
    required this.movementScore,
    required this.hydrationScore,
    required this.mindScore,
    required this.stressScore,
    required this.consistencyScore,
    this.previousScore,
    this.change,
    required this.explanation,
    required this.contributions,
  });
}

/// Calm-side stress indicator: average mood score 1..5 mapped to 0..100.
/// Higher = calmer/better. Null when no check-in was logged.
int? calmFromMoods(List<int> moodScores) {
  if (moodScores.isEmpty) return null;
  final avg = moodScores.reduce((a, b) => a + b) / moodScores.length;
  return ((avg / 5) * 100).round().clamp(0, 100);
}

class WellnessScoreCalculator {
  // Fixed weights — part of the deterministic contract.
  static const double _wSleep = 0.20;
  static const double _wMovement = 0.20;
  static const double _wHydration = 0.15;
  static const double _wMind = 0.15;
  static const double _wStress = 0.15;
  static const double _wConsistency = 0.15;

  static const int _neutralStress = 70;

  /// Score components for a single entry (no consistency/previous logic).
  static ({
    int sleep,
    int movement,
    int hydration,
    int mind,
    int stress,
    bool stressLogged,
  }) componentsOf(DailyHealthEntry entry, {int? calmScore}) {
    final sleep = calculateSleepScore(
        entry.sleepHours, entry.sleepQuality.score, entry.feltRested);
    final movement = calculateExerciseScore(
        entry.exerciseMinutes, entry.exerciseIntensity.name);
    final hydration =
        calculateNutritionScore(entry.mealQuality.score, entry.waterGlasses);
    final mind = calculateMindfulnessScore(
        entry.meditationMinutes, entry.screenTimeHours);
    final stress = calmScore ?? _neutralStress;
    return (
      sleep: sleep,
      movement: movement,
      hydration: hydration,
      mind: mind,
      stress: stress,
      stressLogged: calmScore != null,
    );
  }

  static int _total({
    required int sleep,
    required int movement,
    required int hydration,
    required int mind,
    required int stress,
    required int consistency,
  }) {
    final total = sleep * _wSleep +
        movement * _wMovement +
        hydration * _wHydration +
        mind * _wMind +
        stress * _wStress +
        consistency * _wConsistency;
    return total.round().clamp(0, 100);
  }

  /// Full score for [entry], optionally compared against [previousEntry].
  ///
  /// - [daysLoggedLast7]: number of distinct days with entries in the last 7
  ///   (0..7). Drives the consistency component.
  /// - [calmScore]/[previousCalmScore]: 0..100 calm indicators derived from
  ///   logged stress check-ins. Null = none logged (neutral 70 is used and
  ///   disclosed in the explanation).
  static WellnessScore calculate({
    required DailyHealthEntry entry,
    DailyHealthEntry? previousEntry,
    required int daysLoggedLast7,
    int? calmScore,
    int? previousCalmScore,
  }) {
    final c = componentsOf(entry, calmScore: calmScore);
    final consistency = ((daysLoggedLast7.clamp(0, 7) / 7) * 100).round();
    final total = _total(
      sleep: c.sleep,
      movement: c.movement,
      hydration: c.hydration,
      mind: c.mind,
      stress: c.stress,
      consistency: consistency,
    );

    int? previousScore;
    if (previousEntry != null) {
      final p = componentsOf(previousEntry, calmScore: previousCalmScore);
      previousScore = _total(
        sleep: p.sleep,
        movement: p.movement,
        hydration: p.hydration,
        mind: p.mind,
        stress: p.stress,
        consistency: consistency,
      );
    }
    final change =
        previousScore == null ? null : total - previousScore;

    final contributions = <String, String>{
      'Sleep':
          '${formatHours(entry.sleepHours)} · ${entry.sleepQuality.label}${entry.feltRested ? ' · rested' : ''}',
      'Movement':
          '${entry.exerciseMinutes} min${entry.exerciseType != null && entry.exerciseType!.isNotEmpty ? ' · ${entry.exerciseType}' : ''} · ${entry.exerciseIntensity.label}',
      'Hydration':
          '${entry.waterGlasses} glasses · meals ${entry.mealQuality.label}',
      'Mind':
          '${entry.meditationMinutes} min meditation · ${entry.screenTimeHours.toStringAsFixed(1)}h screen',
      'Stress': c.stressLogged
          ? 'from your logged check-in'
          : 'no check-in logged — neutral placeholder',
      'Consistency': '$daysLoggedLast7 of 7 days logged',
    };

    final explanation = _explain(
      entry: entry,
      total: total,
      components: c,
      change: change,
      daysLogged: daysLoggedLast7,
    );

    return WellnessScore(
      totalScore: total,
      sleepScore: c.sleep,
      movementScore: c.movement,
      hydrationScore: c.hydration,
      mindScore: c.mind,
      stressScore: c.stress,
      consistencyScore: consistency,
      previousScore: previousScore,
      change: change,
      explanation: explanation,
      contributions: contributions,
    );
  }

  /// Lightweight per-day score for charts (deterministic, no explanations).
  static int scoreForDay(
    DailyHealthEntry entry, {
    int? calmScore,
    required int daysLoggedLast7,
  }) {
    final c = componentsOf(entry, calmScore: calmScore);
    final consistency = ((daysLoggedLast7.clamp(0, 7) / 7) * 100).round();
    return _total(
      sleep: c.sleep,
      movement: c.movement,
      hydration: c.hydration,
      mind: c.mind,
      stress: c.stress,
      consistency: consistency,
    );
  }

  static String _explain({
    required DailyHealthEntry entry,
    required int total,
    required ({
      int sleep,
      int movement,
      int hydration,
      int mind,
      int stress,
      bool stressLogged,
    }) components,
    required int? change,
    required int daysLogged,
  }) {
    final parts = <String>[];
    // Strongest / weakest logged areas (data-supported only).
    final ranked = {
      'sleep': components.sleep,
      'movement': components.movement,
      'hydration': components.hydration,
      'mind': components.mind,
    };
    final best = ranked.entries
        .reduce((a, b) => a.value >= b.value ? a : b);
    parts.add(
        'Strongest logged area: ${best.key} (${best.value}). Based on your logged data.');

    if (change != null) {
      if (change > 0) {
        parts.add(
            'Your score increased by $change points vs the previous logged day.');
      } else if (change < 0) {
        parts.add(
            'Your score decreased by ${-change} points vs the previous logged day.');
      } else {
        parts.add('Your score is unchanged vs the previous logged day.');
      }
    } else {
      parts.add('Log another day to see how your score changes.');
    }

    if (!components.stressLogged) {
      parts.add(
          'No stress check-in logged, so stress uses a neutral placeholder.');
    }
    if (daysLogged < 3) {
      parts.add('Logging more days sharpens your personal trend.');
    }
    parts.add('Illustrative wellness score — not a medical assessment.');
    return parts.join(' ');
  }
}
