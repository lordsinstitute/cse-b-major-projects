import '../../data/models/models.dart';

/// Simulated weekly pattern inputs.
/// - [sleepHours]: nightly average, 4–10.
/// - [exerciseMinWeek]: total movement minutes per week, 0–180.
/// - [strain]: 1 (calm) – 5 (high strain).
/// - [waterGlasses]: daily average, 0–12.
class ScenarioInput {
  final double sleepHours;
  final double exerciseMinWeek;
  final double strain;
  final double waterGlasses;

  const ScenarioInput({
    required this.sleepHours,
    required this.exerciseMinWeek,
    required this.strain,
    required this.waterGlasses,
  });

  ScenarioInput copyWith({
    double? sleepHours,
    double? exerciseMinWeek,
    double? strain,
    double? waterGlasses,
  }) {
    return ScenarioInput(
      sleepHours: sleepHours ?? this.sleepHours,
      exerciseMinWeek: exerciseMinWeek ?? this.exerciseMinWeek,
      strain: strain ?? this.strain,
      waterGlasses: waterGlasses ?? this.waterGlasses,
    );
  }
}

/// Illustrative indices, 0–100 each. Not medical measurements.
class Projection {
  final int physical;
  final int mental;
  final int energy;
  final int overall;

  const Projection({
    required this.physical,
    required this.mental,
    required this.energy,
    required this.overall,
  });
}

/// Deterministic illustrative projection engine.
/// Same inputs always yield the same outputs. Outputs are scenario
/// sketches for reflection — never medical predictions.
class WellnessProjectionEngine {
  static double sleepScore(double h) {
    final x = h.clamp(4.0, 10.0);
    if (x >= 7 && x <= 9) return 100;
    if (x < 7) return 40 + ((x - 4) / 3) * 60; // 4→40 … 7→100
    return 100 - ((x - 9) / 1) * 15; // 9→100 … 10→85
  }

  static double exerciseScore(double minWeek) {
    return (minWeek.clamp(0.0, 180.0) / 150 * 100).clamp(0.0, 100.0);
  }

  static double strainScore(double strain) {
    return ((6 - strain.clamp(1.0, 5.0)) / 5 * 100).clamp(0.0, 100.0);
  }

  static double hydrationScore(double glasses) {
    return (glasses.clamp(0.0, 12.0) / 8 * 100).clamp(0.0, 100.0);
  }

  static Projection project(ScenarioInput input) {
    final sleep = sleepScore(input.sleepHours);
    final exercise = exerciseScore(input.exerciseMinWeek);
    final strain = strainScore(input.strain);
    final hydration = hydrationScore(input.waterGlasses);
    final physical =
        (sleep * 0.35 + exercise * 0.35 + hydration * 0.30).round();
    final mental =
        (sleep * 0.40 + strain * 0.40 + hydration * 0.20).round();
    final energy =
        (sleep * 0.40 + exercise * 0.30 + strain * 0.30).round();
    final overall = ((physical + mental + energy) / 3).round();
    return Projection(
      physical: physical.clamp(0, 100),
      mental: mental.clamp(0, 100),
      energy: energy.clamp(0, 100),
      overall: overall.clamp(0, 100),
    );
  }

  /// Human-readable list of simulated variables that differ, e.g.
  /// "+1.0h sleep · +60 min/week movement". Empty when identical.
  static List<String> changedInputs(
      ScenarioInput from, ScenarioInput to) {
    final out = <String>[];
    final ds = to.sleepHours - from.sleepHours;
    if (ds.abs() >= 0.05) {
      out.add(
          '${ds > 0 ? '+' : ''}${ds.toStringAsFixed(1)}h sleep');
    }
    final de = to.exerciseMinWeek - from.exerciseMinWeek;
    if (de.abs() >= 1) {
      out.add(
          '${de > 0 ? '+' : ''}${de.round()} min/week movement');
    }
    final dt = to.strain - from.strain;
    if (dt.abs() >= 0.05) {
      out.add(dt < 0
          ? 'strain ${from.strain.toStringAsFixed(1)} → ${to.strain.toStringAsFixed(1)} (calmer)'
          : 'strain ${from.strain.toStringAsFixed(1)} → ${to.strain.toStringAsFixed(1)} (higher)');
    }
    final dw = to.waterGlasses - from.waterGlasses;
    if (dw.abs() >= 0.05) {
      out.add(
          '${dw > 0 ? '+' : ''}${dw.toStringAsFixed(1)} glasses water');
    }
    return out;
  }

  /// Flat 10-year illustrative trajectory: assumes the pattern is
  /// sustained. A ±4 band shows it is a sketch, not a forecast.
  static List<int> trajectory(Projection p) =>
      List<int>.filled(10, p.overall);
}

/// Current pattern derived from tracked data — or absent when data is thin.
/// Never invented: [isComplete] is false until minimums are met.
class PatternBaseline {
  final double sleepHours;
  final double exerciseMinWeek;
  final double strain;
  final double waterGlasses;
  final int daysLogged;
  final int checkIns;
  final bool hasEntries;
  final bool hasStress;

  const PatternBaseline({
    required this.sleepHours,
    required this.exerciseMinWeek,
    required this.strain,
    required this.waterGlasses,
    required this.daysLogged,
    required this.checkIns,
    required this.hasEntries,
    required this.hasStress,
  });

  bool get isComplete => hasEntries && hasStress;

  /// Exactly what is missing, for the empty-state explanation.
  List<String> get missing => [
        if (!hasEntries)
          'Log at least 2 days under Today (sleep, movement, water).',
        if (!hasStress) 'Add at least 1 stress check-in under Today.',
      ];

  ScenarioInput toInput() => ScenarioInput(
        sleepHours: sleepHours,
        exerciseMinWeek: exerciseMinWeek,
        strain: strain,
        waterGlasses: waterGlasses,
      );

  /// Builds a baseline from logged entries + check-in moods.
  /// Returns incomplete (never fabricated) when minimums are unmet.
  static PatternBaseline fromLogs({
    required List<DailyHealthEntry> last7,
    required List<int> moodScores,
  }) {
    final hasEntries = last7.length >= 2;
    final hasStress = moodScores.isNotEmpty;
    double avg(double Function(DailyHealthEntry) f) {
      if (last7.isEmpty) return 0;
      return last7.map(f).reduce((a, b) => a + b) / last7.length;
    }
    final sleep = hasEntries ? avg((e) => e.sleepHours) : 7.0;
    final exercise = hasEntries
        ? last7
            .map((e) => e.exerciseMinutes.toDouble())
            .reduce((a, b) => a + b)
        : 0.0;
    final water = hasEntries ? avg((e) => e.waterGlasses.toDouble()) : 0.0;
    final strain = hasStress
        ? 6 -
            (moodScores.reduce((a, b) => a + b) / moodScores.length)
        : 3.0;
    return PatternBaseline(
      sleepHours: sleep.clamp(4.0, 10.0),
      exerciseMinWeek: exercise.clamp(0.0, 180.0),
      strain: strain.clamp(1.0, 5.0),
      waterGlasses: water.clamp(0.0, 12.0),
      daysLogged: last7.length,
      checkIns: moodScores.length,
      hasEntries: hasEntries,
      hasStress: hasStress,
    );
  }
}
