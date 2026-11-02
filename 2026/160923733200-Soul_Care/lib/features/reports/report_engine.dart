import '../../core/wellness/wellness_score.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';

/// Minimum logged days for a trustworthy weekly figure.
const int minDaysForReport = 2;

/// One metric delta between two weeks. Display strings keep formatting in
/// one place; [delta] is null when either side lacks data.
class MetricDelta {
  final String label;
  final String current;
  final String previous;
  final String change;
  final double? delta;

  const MetricDelta({
    required this.label,
    required this.current,
    required this.previous,
    required this.change,
    required this.delta,
  });
}

/// A 7-day weekly report. Nulls mean "not enough logged data" — never zeros
/// presented as measurements.
class WeeklyReport {
  final DateTime weekStart;
  final int daysLogged;
  final int? avgWellness;
  final int? wellnessChange;
  final double? sleepAvg;
  final double? sleepConsistency; // 0..1 logged days within 7–9h
  final String? bestSleepDay;
  final String? lowSleepDay;
  final int exerciseTotal;
  final int activeDays; // days with >= 20 min
  final double? waterAvg;
  final double? waterGoalPct; // avg / 8, 0..1+
  final double? moodAvg;
  final String? bestMoodDay;
  final String? lowMoodDay;
  final int meditationTotal;
  final double? screenAvg;

  const WeeklyReport({
    required this.weekStart,
    required this.daysLogged,
    required this.avgWellness,
    required this.wellnessChange,
    required this.sleepAvg,
    required this.sleepConsistency,
    required this.bestSleepDay,
    required this.lowSleepDay,
    required this.exerciseTotal,
    required this.activeDays,
    required this.waterAvg,
    required this.waterGoalPct,
    required this.moodAvg,
    required this.bestMoodDay,
    required this.lowMoodDay,
    required this.meditationTotal,
    required this.screenAvg,
  });

  bool get sufficient => daysLogged >= minDaysForReport;
}

/// Builds a weekly report for the 7 days ending on [end] (inclusive).
/// [previous] (the 7 days before) feeds score change only when present.
WeeklyReport buildWeekly({
  required List<DailyHealthEntry> entries,
  required Map<String, double> calmByDate,
  required DateTime end,
  List<DailyHealthEntry> previous = const [],
}) {
  final start = DateTime(end.year, end.month, end.day)
      .subtract(const Duration(days: 6));
  final inWeek = entries.where((e) {
    final d = DateTime.tryParse(e.date);
    if (d == null) return false;
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }).toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  int? wellnessOf(List<DailyHealthEntry> list) {
    if (list.length < minDaysForReport) return null;
    var sum = 0;
    for (final e in list) {
      sum += WellnessScoreCalculator.scoreForDay(
        e,
        calmScore: calmByDate[e.date]?.round(),
        daysLoggedLast7: list.length,
      );
    }
    return (sum / list.length).round();
  }

  final avg = wellnessOf(inWeek);
  final prevAvg = wellnessOf(previous);

  double? avgOf(List<double> v) =>
      v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;

  final sleeps = [for (final e in inWeek) if (e.sleepHours > 0) e.sleepHours];
  double? consistency;
  if (sleeps.isNotEmpty) {
    final good =
        sleeps.where((s) => s >= 7 && s <= 9).length;
    consistency = good / sleeps.length;
  }
  String? bestDay(List<DailyHealthEntry> list,
      double Function(DailyHealthEntry) f, bool maxWins) {
    final logged =
        list.where((e) => f(e) > 0).toList();
    if (logged.isEmpty) return null;
    logged.sort((a, b) => maxWins
        ? f(b).compareTo(f(a))
        : f(a).compareTo(f(b)));
    return logged.first.date;
  }

  final moodDays = calmByDate.keys
      .where((k) => inWeek.any((e) => e.date == k))
      .toList();
  double? moodAvg;
  if (moodDays.isNotEmpty) {
    final vals = [for (final k in moodDays) calmByDate[k]! / 20];
    moodAvg = vals.reduce((a, b) => a + b) / vals.length;
  }
  String? bestMood;
  String? lowMood;
  if (moodDays.isNotEmpty) {
    final sorted = [...moodDays]..sort(
        (a, b) => calmByDate[b]!.compareTo(calmByDate[a]!));
    bestMood = sorted.first;
    lowMood = sorted.last;
  }

  final waters = [
    for (final e in inWeek)
      if (e.waterGlasses > 0) e.waterGlasses.toDouble()
  ];
  final screens = [
    for (final e in inWeek) e.screenTimeHours,
  ];

  return WeeklyReport(
    weekStart: start,
    daysLogged: inWeek.length,
    avgWellness: avg,
    wellnessChange:
        (avg == null || prevAvg == null) ? null : avg - prevAvg,
    sleepAvg: avgOf(sleeps),
    sleepConsistency: consistency,
    bestSleepDay: bestDay(inWeek, (e) => e.sleepHours, true),
    lowSleepDay: bestDay(inWeek, (e) => e.sleepHours, false),
    exerciseTotal: inWeek.fold(0, (a, e) => a + e.exerciseMinutes),
    activeDays: inWeek.where((e) => e.exerciseMinutes >= 20).length,
    waterAvg: avgOf(waters),
    waterGoalPct: avgOf(waters) == null
        ? null
        : avgOf(waters)! / 8,
    moodAvg: moodAvg,
    bestMoodDay: bestMood,
    lowMoodDay: lowMood,
    meditationTotal:
        inWeek.fold(0, (a, e) => a + e.meditationMinutes),
    screenAvg: screens.isEmpty ? null : avgOf(screens),
  );
}

/// Week-over-week deltas. Entries appear only when both sides are measured.
List<MetricDelta> compareWeeks(WeeklyReport current, WeeklyReport previous) {
  final out = <MetricDelta>[];
  void add(String label, double? c, double? p, String unit,
      {int decimals = 1}) {
    if (c == null || p == null) return;
    final d = c - p;
    final sign = d > 0 ? '+' : '';
    out.add(MetricDelta(
      label: label,
      current: '${c.toStringAsFixed(decimals)}$unit',
      previous: '${p.toStringAsFixed(decimals)}$unit',
      change: '$sign${d.toStringAsFixed(decimals)}$unit',
      delta: d,
    ));
  }

  add('Sleep', current.sleepAvg, previous.sleepAvg, 'h');
  add('Exercise', current.exerciseTotal.toDouble(),
      previous.exerciseTotal.toDouble(), ' min',
      decimals: 0);
  add('Water', current.waterAvg, previous.waterAvg, '');
  add('Mood', current.moodAvg, previous.moodAvg, '');
  add('Screen time', current.screenAvg, previous.screenAvg, 'h');
  return out;
}

/// Factual summary sentences. No medical conclusions, ever.
String summarizeWeeks(WeeklyReport current, WeeklyReport previous) {
  if (!current.sufficient) {
    return 'Not enough logged days this week for a summary — log at least $minDaysForReport days under Today.';
  }
  final parts = <String>[];
  final deltas = {
    for (final d in compareWeeks(current, previous)) d.label: d
  };
  final sleep = deltas['Sleep'];
  if (sleep?.delta != null) {
    final mins = (sleep!.delta! * 60).round().abs();
    final dir = sleep.delta! > 0.005
        ? 'increased'
        : sleep.delta! < -0.005
            ? 'decreased'
            : 'stayed approximately the same';
    parts.add(
        'Your sleep average $dir by $mins minutes compared with last week.');
  }
  final ex = deltas['Exercise'];
  if (ex?.delta != null) {
    final dir = ex!.delta!.abs() < 10
        ? 'stayed approximately the same'
        : ex.delta! > 0
            ? 'rose'
            : 'dipped';
    parts.add(
        'Exercise $dir (${ex.current} vs ${ex.previous} total minutes).');
  }
  if (current.wellnessChange != null) {
    final c = current.wellnessChange!;
    parts.add(c == 0
        ? 'Your average wellness score was unchanged.'
        : 'Your average wellness score moved ${c > 0 ? '+' : ''}$c points.');
  }
  parts.add(
      'Logged ${current.daysLogged} of 7 days. Patterns only — no medical conclusions.');
  return parts.join(' ');
}

/// Monthly roll-up across repositories (counts + trends).
class MonthlyReport {
  final int daysLogged;
  final double? wellnessTrend; // second-half avg − first-half avg
  final double? sleepGoalPct; // days meeting 7–9h / logged days
  final double? waterGoalPct; // days meeting 8+ glasses / logged days
  final int experimentsCompleted;
  final int habitCheckIns; // total DONE check-ins in month
  final int journalCount;
  final int documentsAdded;
  final int? avgWellness;

  const MonthlyReport({
    required this.daysLogged,
    required this.wellnessTrend,
    required this.sleepGoalPct,
    required this.waterGoalPct,
    required this.experimentsCompleted,
    required this.habitCheckIns,
    required this.journalCount,
    required this.documentsAdded,
    required this.avgWellness,
  });
}

MonthlyReport buildMonthly({
  required List<DailyHealthEntry> entries,
  required Map<String, double> calmByDate,
  required List<Experiment> experiments,
  required int journalCount,
  required int documentsAdded,
  required DateTime end,
}) {
  final start =
      DateTime(end.year, end.month, end.day).subtract(const Duration(days: 29));
  final inMonth = entries.where((e) {
    final d = DateTime.tryParse(e.date);
    if (d == null) return false;
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }).toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  int? wellness(List<DailyHealthEntry> list) {
    if (list.length < minDaysForReport) return null;
    var sum = 0;
    for (final e in list) {
      sum += WellnessScoreCalculator.scoreForDay(
        e,
        calmScore: calmByDate[e.date]?.round(),
        daysLoggedLast7: inMonth.length.clamp(0, 7),
      );
    }
    return (sum / list.length).round();
  }

  double? trend;
  final avg = wellness(inMonth);
  if (inMonth.length >= 4) {
    final half = inMonth.length ~/ 2;
    final a = wellness(inMonth.take(half).toList());
    final b = wellness(inMonth.skip(half).toList());
    if (a != null && b != null) trend = (b - a).toDouble();
  }

  double? pct(bool Function(DailyHealthEntry) met) {
    if (inMonth.isEmpty) return null;
    return inMonth.where(met).length / inMonth.length;
  }

  var doneCheckIns = 0;
  var completed = 0;
  for (final e in experiments) {
    if (e.status == ExperimentStatus.completed) completed++;
    doneCheckIns += e.checkIns.length;
  }

  return MonthlyReport(
    daysLogged: inMonth.length,
    wellnessTrend: trend,
    sleepGoalPct: pct((e) => e.sleepHours >= 7 && e.sleepHours <= 9),
    waterGoalPct: pct((e) => e.waterGlasses >= 8),
    experimentsCompleted: completed,
    habitCheckIns: doneCheckIns,
    journalCount: journalCount,
    documentsAdded: documentsAdded,
    avgWellness: avg,
  );
}
