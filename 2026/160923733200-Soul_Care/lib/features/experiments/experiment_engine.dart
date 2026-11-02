import '../../core/utils/utils.dart';
import '../../data/models/models.dart';
import 'experiment_templates.dart';

/// Which logged metric a template compares.
enum LabMetric { sleepHours, exerciseMinutes, meditationMinutes, waterGlasses, screenTimeHours }

/// Metric + display info per template id.
class MetricInfo {
  final LabMetric metric;
  final String label;
  final String unit;
  final bool lowerIsBetter;

  const MetricInfo({
    required this.metric,
    required this.label,
    required this.unit,
    this.lowerIsBetter = false,
  });
}

const Map<String, MetricInfo> templateMetrics = {
  'earlier-sleep': MetricInfo(
      metric: LabMetric.sleepHours,
      label: 'sleep',
      unit: 'h'),
  'daily-walk': MetricInfo(
      metric: LabMetric.exerciseMinutes,
      label: 'exercise',
      unit: ' min'),
  'breathing-reset': MetricInfo(
      metric: LabMetric.meditationMinutes,
      label: 'meditation',
      unit: ' min'),
  'hydration': MetricInfo(
      metric: LabMetric.waterGlasses,
      label: 'water',
      unit: ' glasses'),
  'screen': MetricInfo(
      metric: LabMetric.screenTimeHours,
      label: 'screen time',
      unit: 'h',
      lowerIsBetter: true),
};

double metricValue(DailyHealthEntry e, LabMetric m) {
  switch (m) {
    case LabMetric.sleepHours:
      return e.sleepHours;
    case LabMetric.exerciseMinutes:
      return e.exerciseMinutes.toDouble();
    case LabMetric.meditationMinutes:
      return e.meditationMinutes.toDouble();
    case LabMetric.waterGlasses:
      return e.waterGlasses.toDouble();
    case LabMetric.screenTimeHours:
      return e.screenTimeHours;
  }
}

/// yyyy-MM-dd key for a date.
String dayKey(DateTime d) => formatDateForStorage(d);

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// 1-based day number within the experiment (clamped to duration).
int dayNumber(Experiment exp, DateTime now) {
  final start = exp.startDate;
  if (start == null) return 0;
  final n = _day(now).difference(_day(start)).inDays + 1;
  return n.clamp(1, exp.durationDays);
}

/// Fraction of days elapsed (0..1).
double progressFraction(Experiment exp, DateTime now) {
  if (exp.startDate == null || exp.durationDays <= 0) return 0;
  return (dayNumber(exp, now) / exp.durationDays).clamp(0.0, 1.0);
}

/// Consecutive DONE days ending today (or yesterday if today is unchecked).
/// Explicit MISSED days break the streak.
int currentStreak(Experiment exp, DateTime now) {
  final done = exp.checkIns.toSet();
  final missed = exp.missedDays.toSet();
  var cursor = _day(now);
  // If today is neither done nor missed, streak counts back from yesterday.
  final todayKey = dayKey(cursor);
  if (!done.contains(todayKey) && !missed.contains(todayKey)) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while (done.contains(dayKey(cursor)) &&
      !missed.contains(dayKey(cursor))) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

/// Longest DONE run anywhere in the experiment.
int bestStreak(Experiment exp) {
  final done = exp.checkIns.toSet();
  final missed = exp.missedDays.toSet();
  final days = done.map((k) => DateTime.tryParse(k)).whereType<DateTime>().toList()
    ..sort();
  var best = 0;
  var run = 0;
  DateTime? prev;
  for (final d in days) {
    final k = dayKey(d);
    if (missed.contains(k)) {
      run = 0;
      prev = null;
      continue;
    }
    if (prev != null && d.difference(prev).inDays == 1) {
      run++;
    } else {
      run = 1;
    }
    if (run > best) best = run;
    prev = d;
  }
  return best;
}

/// Applies a DONE toggle for [date]: adds the day if absent (clearing any
/// accidental MISSED), removes it if already DONE (corrects accidents).
/// Returns the updated experiment.
Experiment toggleDone(Experiment exp, DateTime date) {
  final key = dayKey(date);
  final done = [...exp.checkIns];
  final missed = [...exp.missedDays];
  if (done.contains(key)) {
    done.remove(key); // correction
  } else {
    done.add(key);
    missed.remove(key);
  }
  return exp.copyWith(checkIns: done, missedDays: missed);
}

/// Records an explicit MISSED for [date] (or clears it if already missed).
Experiment toggleMissed(Experiment exp, DateTime date) {
  final key = dayKey(date);
  final done = [...exp.checkIns];
  final missed = [...exp.missedDays];
  if (missed.contains(key)) {
    missed.remove(key); // correction
  } else {
    missed.add(key);
    done.remove(key);
  }
  return exp.copyWith(checkIns: done, missedDays: missed);
}

/// Factual baseline-vs-experiment comparison. Averages only logged days.
/// Never claims causation.
class BaselineComparison {
  final MetricInfo metric;
  final double? baselineAvg;
  final int baselineDays;
  final double? currentAvg;
  final int currentDays;
  final double? delta;

  const BaselineComparison({
    required this.metric,
    required this.baselineAvg,
    required this.baselineDays,
    required this.currentAvg,
    required this.currentDays,
    required this.delta,
  });

  bool get hasBaseline => baselineAvg != null && baselineDays > 0;
  bool get hasCurrent => currentAvg != null && currentDays > 0;
}

BaselineComparison compareBaseline({
  required Experiment exp,
  required List<DailyHealthEntry> entries,
  required DateTime now,
}) {
  final info = templateMetrics[exp.templateId] ??
      const MetricInfo(
          metric: LabMetric.sleepHours, label: 'sleep', unit: 'h');
  final start = exp.startDate == null ? _day(now) : _day(exp.startDate!);
  final today = _day(now);

  double? avg(Iterable<DailyHealthEntry> list) {
    final vals = [
      for (final e in list)
        if (metricValue(e, info.metric) > 0 ||
            info.metric == LabMetric.screenTimeHours)
          metricValue(e, info.metric),
    ];
    // Screen time of 0 is meaningful (logged); others need > 0 to count.
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  final byDay = {for (final e in entries) e.date: e};
  final baselineVals = <DailyHealthEntry>[];
  for (var i = 1; i <= 7; i++) {
    final e = byDay[dayKey(start.subtract(Duration(days: i)))];
    if (e != null) baselineVals.add(e);
  }
  final currentVals = <DailyHealthEntry>[];
  for (var d = start;
      !d.isAfter(today);
      d = d.add(const Duration(days: 1))) {
    final e = byDay[dayKey(d)];
    if (e != null) currentVals.add(e);
  }

  final b = avg(baselineVals);
  final c = avg(currentVals);
  return BaselineComparison(
    metric: info,
    baselineAvg: b,
    baselineDays: baselineVals.length,
    currentAvg: c,
    currentDays: currentVals.length,
    delta: (b == null || c == null) ? null : c - b,
  );
}

/// Completion results for a finished (or viewed) experiment.
class ExperimentResults {
  final double completionRate; // 0..1 DONE / durationDays
  final int doneDays;
  final int bestStreak;
  final BaselineComparison comparison;
  final String summary;

  const ExperimentResults({
    required this.completionRate,
    required this.doneDays,
    required this.bestStreak,
    required this.comparison,
    required this.summary,
  });
}

ExperimentResults buildResults({
  required Experiment exp,
  required List<DailyHealthEntry> entries,
  required DateTime now,
}) {
  final comparison =
      compareBaseline(exp: exp, entries: entries, now: now);
  final done = exp.checkIns.length;
  final rate = exp.durationDays <= 0
      ? 0.0
      : (done / exp.durationDays).clamp(0.0, 1.0);
  final summary = _summarize(exp, comparison, rate, done);
  return ExperimentResults(
    completionRate: rate,
    doneDays: done,
    bestStreak: bestStreak(exp),
    comparison: comparison,
    summary: summary,
  );
}

String _summarize(Experiment exp, BaselineComparison c, double rate,
    int done) {
  final buf = StringBuffer()
    ..write(
        'You completed $done of ${exp.durationDays} days (${(rate * 100).round()}%). ');
  if (c.hasBaseline && c.hasCurrent && c.delta != null) {
    final dir = c.delta! > 0.005
        ? 'higher'
        : c.delta! < -0.005
            ? 'lower'
            : 'about the same as';
    final mag = c.delta!.abs().toStringAsFixed(1);
    buf.write(
        'Your average ${c.metric.label} during this experiment was $mag${c.metric.unit} $dir than your baseline period '
        '(${c.currentAvg!.toStringAsFixed(1)} vs ${c.baselineAvg!.toStringAsFixed(1)}${c.metric.unit}, '
        'from ${c.currentDays} logged experiment days and ${c.baselineDays} logged baseline days). ');
    buf.write(
        'This is an observed difference in your logs — many factors can influence it.');
  } else if (!c.hasBaseline) {
    buf.write(
        'There was no logged baseline before this experiment, so no before/during comparison is available.');
  } else {
    buf.write(
        'No experiment days were logged yet, so no before/during comparison is available.');
  }
  return buf.toString();
}

/// A template suggestion with its data-based reason.
class ExperimentRecommendation {
  final ExperimentTemplate template;
  final String reason;

  const ExperimentRecommendation(
      {required this.template, required this.reason});
}

/// Sorts data-driven recommendations so a focus-matching template comes
/// first. Reasons are untouched — ordering only, never new suggestions.
List<ExperimentRecommendation> sortByFocus(
    List<ExperimentRecommendation> recs, String? focusTemplateId) {
  if (focusTemplateId == null) return recs;
  final sorted = [...recs]..sort((a, b) {
      final aMatch = a.template.id == focusTemplateId ? 0 : 1;
      final bMatch = b.template.id == focusTemplateId ? 0 : 1;
      return aMatch.compareTo(bMatch);
    });
  return sorted;
}

/// Template id matching a wellness focus name (for ordering only).
String? templateForFocusName(String focusName) {
  switch (focusName) {
    case 'betterSleep':
      return 'earlier-sleep';
    case 'moreMovement':
      return 'daily-walk';
    case 'stressManagement':
      return 'breathing-reset';
    case 'hydration':
      return 'hydration';
    case 'mindfulness':
      return 'breathing-reset';
    case 'consistency':
      return 'daily-walk';
    default:
      return null;
  }
}

/// Recommends 2–3 templates from actual logged data. Empty data or healthy
/// patterns yield fewer (or zero) recommendations — never without a reason.
List<ExperimentRecommendation> recommend({
  required List<DailyHealthEntry> last7,
}) {
  if (last7.length < 2) return const [];
  final out = <ExperimentRecommendation>[];

  double avgNum(double Function(DailyHealthEntry) f) {
    final vals = last7.map(f).toList();
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  // Low sleep consistency: short average or ragged pattern.
  final sleeps = last7.map((e) => e.sleepHours).toList();
  final sleepAvg = avgNum((e) => e.sleepHours);
  final sleepRange = sleeps.reduce((a, b) => a > b ? a : b) -
      sleeps.reduce((a, b) => a < b ? a : b);
  if (sleepAvg < 7 || sleepRange >= 2) {
    out.add(ExperimentRecommendation(
      template: experimentTemplates[0],
      reason:
          'Your logged sleep averaged ${sleepAvg.toStringAsFixed(1)}h with a ${sleepRange.toStringAsFixed(1)}h spread — a steadier wind-down may show up in your logs.',
    ));
  }

  // Low activity.
  final activeDays = last7.where((e) => e.exerciseMinutes >= 20).length;
  if (activeDays <= 2) {
    out.add(ExperimentRecommendation(
      template: experimentTemplates[1],
      reason:
          'You logged 20+ minutes of movement on $activeDays of your last ${last7.length} logged days.',
    ));
  }

  // Inconsistent hydration.
  final waterAvg = avgNum((e) => e.waterGlasses.toDouble());
  if (waterAvg < 6) {
    out.add(ExperimentRecommendation(
      template: experimentTemplates[3],
      reason:
          'Your logged water averaged ${waterAvg.toStringAsFixed(1)} glasses per day.',
    ));
  }

  // Low mindfulness or heavy screens.
  final medDays = last7.where((e) => e.meditationMinutes > 0).length;
  final screenAvg = avgNum((e) => e.screenTimeHours);
  if (medDays <= 1 && out.length < 3) {
    out.add(ExperimentRecommendation(
      template: experimentTemplates[2],
      reason:
          'You logged meditation on $medDays of your last ${last7.length} logged days.',
    ));
  }
  if (screenAvg >= 4 && out.length < 3) {
    out.add(ExperimentRecommendation(
      template: experimentTemplates[4],
      reason:
          'Your logged screen time averaged ${screenAvg.toStringAsFixed(1)}h per day.',
    ));
  }

  return out.take(3).toList();
}
