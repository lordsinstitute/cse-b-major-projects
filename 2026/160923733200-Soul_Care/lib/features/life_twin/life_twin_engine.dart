import 'dart:math' as math;

import '../../core/utils/utils.dart';
import '../../data/models/checkins.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';

/// SoulCare Life Twin engine — pure, deterministic, local-only.
///
/// An interactive visualization of the user's *tracked* wellness state.
/// It is NOT a medical digital twin and must never be described as a
/// clinical model. Every number derives from logged data; missing data is
/// represented as missing (never fabricated). Language is association-only:
/// "Observed pattern" / "Moves together in your data" — never "Causes".
enum LifeTwinDimension {
  sleep,
  energy,
  stress,
  movement,
  hydration,
  mindfulness,
  consistency,
}

/// Display metadata for each dimension (label + icon code point name).
extension LifeTwinDimensionX on LifeTwinDimension {
  String get label => switch (this) {
        LifeTwinDimension.sleep => 'Sleep',
        LifeTwinDimension.energy => 'Energy',
        LifeTwinDimension.stress => 'Stress',
        LifeTwinDimension.movement => 'Movement',
        LifeTwinDimension.hydration => 'Hydration',
        LifeTwinDimension.mindfulness => 'Mindfulness',
        LifeTwinDimension.consistency => 'Consistency',
      };

  /// Short description of what the dimension summarizes (data sources only).
  String get whatItShows => switch (this) {
        LifeTwinDimension.sleep =>
          'Logged sleep hours, quality and rested feeling.',
        LifeTwinDimension.energy =>
          'Logged morning/evening energy (1–5). Higher is more energy.',
        LifeTwinDimension.stress =>
          'Logged calm from mood check-ins. Higher is calmer.',
        LifeTwinDimension.movement => 'Logged exercise minutes and intensity.',
        LifeTwinDimension.hydration =>
          'Logged water glasses and meal quality.',
        LifeTwinDimension.mindfulness =>
          'Logged meditation minutes and screen time.',
        LifeTwinDimension.consistency =>
          'Share of days with logged data in the selected period.',
      };
}

/// Supported time windows (days). 6 months = 180 days.
class LifeTwinRanges {
  static const List<int> options = [7, 30, 90, 180];
  static String label(int days) => switch (days) {
        7 => '7 days',
        30 => '30 days',
        90 => '90 days',
        _ => '6 months',
      };
}

/// Minimum overlapping observations required before a relationship is shown.
const int kLifeTwinMinOverlap = 5;

/// Minimum observations required before a trend is reported.
const int kLifeTwinMinTrend = 3;

/// One calendar day with per-dimension values 0..100 (null = no logged data).
class LifeTwinDay {
  final String key; // yyyy-MM-dd
  final DateTime date;
  final Map<LifeTwinDimension, double?> values;

  const LifeTwinDay({
    required this.key,
    required this.date,
    required this.values,
  });
}

/// Summary for one dimension over the selected window.
class DimensionSummary {
  final LifeTwinDimension dimension;
  final int count;
  final double? average;
  final double? trend; // second-half avg minus first-half avg
  final double? best;
  final String? bestDay;
  final double? worst;
  final String? worstDay;
  final double? changeVsPrevious; // current avg minus previous-window avg
  final List<LifeTwinDay> series;

  const DimensionSummary({
    required this.dimension,
    required this.count,
    required this.average,
    required this.trend,
    required this.best,
    required this.bestDay,
    required this.worst,
    required this.worstDay,
    required this.changeVsPrevious,
    required this.series,
  });

  bool get hasData => count > 0 && average != null;
}

/// An observed co-movement between two dimensions (association only).
class ObservedRelationship {
  final LifeTwinDimension from;
  final LifeTwinDimension to;
  final int overlap;
  final double r; // Pearson correlation, -1..1

  const ObservedRelationship({
    required this.from,
    required this.to,
    required this.overlap,
    required this.r,
  });

  /// Association-only label. Never causal.
  String get label =>
      r >= 0.5 ? 'Moves together in your data' : 'Observed pattern';
}

/// Whole-twin state for one time window.
class LifeTwinState {
  final int daysInWindow;
  final int daysContributing;
  final double? overallIndex;
  final double? recentChange;
  final String confidence; // High / Medium / Low / None
  final String confidenceReason;
  final Map<LifeTwinDimension, DimensionSummary> dimensions;
  final List<ObservedRelationship> relationships;
  bool get hasData => daysContributing > 0 && overallIndex != null;

  const LifeTwinState({
    required this.daysInWindow,
    required this.daysContributing,
    required this.overallIndex,
    required this.recentChange,
    required this.confidence,
    required this.confidenceReason,
    required this.dimensions,
    required this.relationships,
  });
}

/// Hypothetical scenario projection (in-memory only, never touches records).
class LifeTwinScenarioResult {
  final Map<LifeTwinDimension, double> hypotheticalAverages;
  final double hypotheticalOverall;
  final double deltaVsActual;
  final List<String> contributors;

  const LifeTwinScenarioResult({
    required this.hypotheticalAverages,
    required this.hypotheticalOverall,
    required this.deltaVsActual,
    required this.contributors,
  });
}

/// Builds per-day dimension values from logged records.
///
/// - [dailyByDate]: DailyHealthEntry keyed by yyyy-MM-dd.
/// - [stressMoodsByDate]: mood scores (1–5) per date from stress check-ins.
/// - [morningByDate]/[eveningByDate]: check-in records per date.
/// - [windowDays]: dates (midnight) ending today, ascending.
List<LifeTwinDay> buildLifeTwinDays({
  required List<DateTime> windowDays,
  required Map<String, DailyHealthEntry> dailyByDate,
  required Map<String, List<int>> stressMoodsByDate,
  required Map<String, MorningCheckIn> morningByDate,
  required Map<String, EveningReflection> eveningByDate,
}) {
  final days = <LifeTwinDay>[];
  for (final d in windowDays) {
    final key = formatDateForStorage(d);
    final entry = dailyByDate[key];
    final morning = morningByDate[key];
    final evening = eveningByDate[key];

    double? sleep;
    if (entry != null && entry.sleepHours > 0) {
      sleep = calculateSleepScore(
        entry.sleepHours,
        entry.sleepQuality.score,
        entry.feltRested,
      ).toDouble();
    } else if (morning != null && morning.sleepHours > 0) {
      sleep = calculateSleepScore(
        morning.sleepHours,
        3,
        morning.rested >= 4,
      ).toDouble();
    }

    double? energy;
    final energies = <int>[];
    if (morning != null) energies.add(morning.energy);
    if (evening != null) energies.add(evening.energy);
    if (energies.isNotEmpty) {
      energy =
          (energies.reduce((a, b) => a + b) / energies.length / 5 * 100);
    }

    double? stress;
    final moods = stressMoodsByDate[key];
    if (moods != null && moods.isNotEmpty) {
      stress = moods.reduce((a, b) => a + b) / moods.length / 5 * 100;
    } else if (evening != null) {
      stress = (6 - evening.stress) / 5 * 100;
    }

    double? movement;
    double? hydration;
    double? mindfulness;
    if (entry != null) {
      movement = calculateExerciseScore(
        entry.exerciseMinutes,
        entry.exerciseIntensity.name,
      ).toDouble();
      hydration = calculateNutritionScore(
        entry.mealQuality.score,
        entry.waterGlasses,
      ).toDouble();
      mindfulness = calculateMindfulnessScore(
        entry.meditationMinutes,
        entry.screenTimeHours,
      ).toDouble();
    }

    // Consistency: 100 when the day has any logged record, else missing.
    final hasAny = entry != null || morning != null || evening != null;
    final consistency = hasAny ? 100.0 : null;

    days.add(LifeTwinDay(
      key: key,
      date: d,
      values: {
        LifeTwinDimension.sleep: sleep,
        LifeTwinDimension.energy: energy,
        LifeTwinDimension.stress: stress,
        LifeTwinDimension.movement: movement,
        LifeTwinDimension.hydration: hydration,
        LifeTwinDimension.mindfulness: mindfulness,
        LifeTwinDimension.consistency: consistency,
      },
    ));
  }
  return days;
}

/// Pearson correlation, null when undefined (empty, constant, or < 2 points).
double? pearson(List<double> xs, List<double> ys) {
  if (xs.length != ys.length || xs.length < 2) return null;
  final n = xs.length;
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  var num = 0.0;
  var dx = 0.0;
  var dy = 0.0;
  for (var i = 0; i < n; i++) {
    final a = xs[i] - mx;
    final b = ys[i] - my;
    num += a * b;
    dx += a * a;
    dy += b * b;
  }
  if (dx == 0 || dy == 0) return null;
  return (num / math.sqrt(dx * dy)).clamp(-1.0, 1.0).toDouble();
}

double _avg(List<double> v) => v.reduce((a, b) => a + b) / v.length;

DimensionSummary _summarizeDim(
  LifeTwinDimension dim,
  List<LifeTwinDay> days,
  List<LifeTwinDay> previous,
) {
  final pts = <LifeTwinDay>[];
  final vals = <double>[];
  for (final d in days) {
    final v = d.values[dim];
    if (v != null) {
      pts.add(d);
      vals.add(v);
    }
  }
  if (vals.isEmpty) {
    return DimensionSummary(
      dimension: dim,
      count: 0,
      average: null,
      trend: null,
      best: null,
      bestDay: null,
      worst: null,
      worstDay: null,
      changeVsPrevious: null,
      series: const [],
    );
  }
  final avg = _avg(vals);
  double? trend;
  if (vals.length >= kLifeTwinMinTrend) {
    final half = vals.length ~/ 2;
    final first = vals.take(half).toList();
    final second = vals.skip(half).toList();
    if (first.isNotEmpty && second.isNotEmpty) {
      trend = _avg(second) - _avg(first);
    }
  }
  var best = vals.first;
  var worst = vals.first;
  var bestDay = pts.first.key;
  var worstDay = pts.first.key;
  for (var i = 0; i < vals.length; i++) {
    if (vals[i] > best) {
      best = vals[i];
      bestDay = pts[i].key;
    }
    if (vals[i] < worst) {
      worst = vals[i];
      worstDay = pts[i].key;
    }
  }
  double? changeVsPrevious;
  final prevVals = <double>[];
  for (final d in previous) {
    final v = d.values[dim];
    if (v != null) prevVals.add(v);
  }
  if (prevVals.length >= 2 && vals.length >= 2) {
    changeVsPrevious = avg - _avg(prevVals);
  }
  return DimensionSummary(
    dimension: dim,
    count: vals.length,
    average: avg,
    trend: trend,
    best: best,
    bestDay: bestDay,
    worst: worst,
    worstDay: worstDay,
    changeVsPrevious: changeVsPrevious,
    series: pts,
  );
}

/// Summarizes a window of days (plus the previous equal-length window for
/// "change from previous period"). Pure and deterministic.
LifeTwinState summarizeLifeTwin({
  required List<LifeTwinDay> days,
  required List<LifeTwinDay> previous,
  required int daysInWindow,
}) {
  final dims = <LifeTwinDimension, DimensionSummary>{
    for (final dim in LifeTwinDimension.values)
      dim: _summarizeDim(dim, days, previous),
  };

  final contributing = days
      .where((d) => d.values.values.any((v) => v != null))
      .length;

  // Overall index: mean of available dimension averages (logged data only).
  // Consistency is included as the share-of-days-logged signal.
  double? overall;
  final avgs =
      dims.values.where((s) => s.average != null).map((s) => s.average!);
  if (avgs.isNotEmpty && contributing > 0) {
    overall = _avg(avgs.toList());
  }

  // Recent change: second-half vs first-half mean of per-day overall means.
  double? recentChange;
  final dayMeans = <double>[];
  for (final d in days) {
    final vs = d.values.values.whereType<double>().toList();
    if (vs.isNotEmpty) dayMeans.add(_avg(vs));
  }
  if (dayMeans.length >= kLifeTwinMinTrend * 2) {
    final half = dayMeans.length ~/ 2;
    recentChange =
        _avg(dayMeans.skip(half).toList()) - _avg(dayMeans.take(half).toList());
  }

  // Data confidence from contributing days + coverage.
  String confidence;
  String reason;
  if (contributing == 0) {
    confidence = 'None';
    reason = 'No logged days in this period yet.';
  } else {
    final coverage = contributing / daysInWindow;
    if (contributing >= 14 && coverage >= 0.5) {
      confidence = 'High';
      reason =
          '$contributing of $daysInWindow days logged — a solid base for observed patterns.';
    } else if (contributing >= 7) {
      confidence = 'Medium';
      reason =
          '$contributing of $daysInWindow days logged — patterns are emerging.';
    } else {
      confidence = 'Low';
      reason =
          'Only $contributing of $daysInWindow days logged — keep logging to sharpen your twin.';
    }
  }

  // Relationships: Pearson r over overlapping non-null pairs.
  final rels = <ObservedRelationship>[];
  const pairs = [
    (LifeTwinDimension.sleep, LifeTwinDimension.stress),
    (LifeTwinDimension.sleep, LifeTwinDimension.energy),
    (LifeTwinDimension.sleep, LifeTwinDimension.consistency),
    (LifeTwinDimension.sleep, LifeTwinDimension.movement),
    (LifeTwinDimension.sleep, LifeTwinDimension.mindfulness),
    (LifeTwinDimension.sleep, LifeTwinDimension.hydration),
    (LifeTwinDimension.stress, LifeTwinDimension.energy),
    (LifeTwinDimension.movement, LifeTwinDimension.energy),
    (LifeTwinDimension.hydration, LifeTwinDimension.energy),
    (LifeTwinDimension.mindfulness, LifeTwinDimension.stress),
  ];
  for (final (a, b) in pairs) {
    final xs = <double>[];
    final ys = <double>[];
    for (final d in days) {
      final va = d.values[a];
      final vb = d.values[b];
      if (va != null && vb != null) {
        xs.add(va);
        ys.add(vb);
      }
    }
    if (xs.length < kLifeTwinMinOverlap) continue;
    final r = pearson(xs, ys);
    if (r == null || r.abs() < 0.3) continue;
    rels.add(ObservedRelationship(from: a, to: b, overlap: xs.length, r: r));
  }
  rels.sort((x, y) => y.r.abs().compareTo(x.r.abs()));

  return LifeTwinState(
    daysInWindow: daysInWindow,
    daysContributing: contributing,
    overallIndex: overall,
    recentChange: recentChange,
    confidence: confidence,
    confidenceReason: reason,
    dimensions: dims,
    relationships: rels,
  );
}

/// Applies a hypothetical scenario to current averages (in-memory only).
///
/// All deltas are transparent, fixed, illustrative adjustments — not
/// predictions. Returns null when there is no actual data to start from.
LifeTwinScenarioResult? projectScenario({
  required LifeTwinState base,
  double extraSleepHours = 0, // e.g. +1h
  double extraExerciseMin = 0, // per logged active day, e.g. +30
  double calmerStress = 0, // calm points 0..30, e.g. +10
  double extraWaterGlasses = 0, // e.g. +2
}) {
  if (!base.hasData) return null;
  final hypo = <LifeTwinDimension, double>{
    for (final dim in LifeTwinDimension.values)
      dim: base.dimensions[dim]?.average ?? 0,
  };
  final contributors = <String>[];

  if (extraSleepHours != 0 &&
      base.dimensions[LifeTwinDimension.sleep]?.average != null) {
    hypo[LifeTwinDimension.sleep] =
        (hypo[LifeTwinDimension.sleep]! + extraSleepHours * 8).clamp(0, 100);
    contributors.add(
        '${extraSleepHours >= 0 ? '+' : ''}${extraSleepHours.toStringAsFixed(1)}h sleep (simulated)');
    // Observed-association carry-over, clearly hypothetical:
    if (base.dimensions[LifeTwinDimension.energy]?.average != null) {
      hypo[LifeTwinDimension.energy] =
          (hypo[LifeTwinDimension.energy]! + extraSleepHours * 4)
              .clamp(0, 100);
    }
  }
  if (extraExerciseMin != 0 &&
      base.dimensions[LifeTwinDimension.movement]?.average != null) {
    hypo[LifeTwinDimension.movement] =
        (hypo[LifeTwinDimension.movement]! + extraExerciseMin / 30 * 6)
            .clamp(0, 100);
    contributors.add(
        '${extraExerciseMin >= 0 ? '+' : ''}${extraExerciseMin.toStringAsFixed(0)} min movement (simulated)');
    if (base.dimensions[LifeTwinDimension.energy]?.average != null) {
      hypo[LifeTwinDimension.energy] =
          (hypo[LifeTwinDimension.energy]! + extraExerciseMin / 30 * 2)
              .clamp(0, 100);
    }
  }
  if (calmerStress != 0 &&
      base.dimensions[LifeTwinDimension.stress]?.average != null) {
    hypo[LifeTwinDimension.stress] =
        (hypo[LifeTwinDimension.stress]! + calmerStress).clamp(0, 100);
    contributors.add(
        '${calmerStress >= 0 ? '+' : ''}${calmerStress.toStringAsFixed(0)} calm (simulated)');
  }
  if (extraWaterGlasses != 0 &&
      base.dimensions[LifeTwinDimension.hydration]?.average != null) {
    hypo[LifeTwinDimension.hydration] =
        (hypo[LifeTwinDimension.hydration]! + extraWaterGlasses * 5)
            .clamp(0, 100);
    contributors.add(
        '${extraWaterGlasses >= 0 ? '+' : ''}${extraWaterGlasses.toStringAsFixed(1)} glasses water (simulated)');
  }

  // Hypothetical overall = mean over dimensions that actually have data.
  final withData = [
    for (final dim in LifeTwinDimension.values)
      if (base.dimensions[dim]?.average != null) hypo[dim]!,
  ];
  if (withData.isEmpty) return null;
  final hypoOverall = _avg(withData);
  final delta = hypoOverall - (base.overallIndex ?? hypoOverall);
  return LifeTwinScenarioResult(
    hypotheticalAverages: hypo,
    hypotheticalOverall: hypoOverall,
    deltaVsActual: delta,
    contributors: contributors,
  );
}

/// Window dates ending today (ascending, midnight). Pure helper for tests.
List<DateTime> windowDates({required int days, DateTime? now}) {
  final base = now ?? DateTime.now();
  final today = DateTime(base.year, base.month, base.day);
  return [
    for (var i = days - 1; i >= 0; i--)
      today.subtract(Duration(days: i)),
  ];
}
