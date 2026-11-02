import '../../core/utils/utils.dart';
import '../../core/wellness/wellness_score.dart';
import '../../data/models/checkins.dart';
import '../../data/models/models.dart';

/// Visual wellness classifications. These describe how full a logged day
/// looks — never health claims, never diagnoses.
enum DayState { excellent, good, mixed, difficult, insufficient }

extension DayStateX on DayState {
  String get label => switch (this) {
        DayState.excellent => 'Excellent',
        DayState.good => 'Good',
        DayState.mixed => 'Mixed',
        DayState.difficult => 'Difficult',
        DayState.insufficient => 'No data',
      };

  /// Screen-reader / tooltip description (never color-only).
  String get description => switch (this) {
        DayState.excellent =>
          'Excellent logged day: high wellness score from your logs.',
        DayState.good =>
          'Good logged day: solid wellness score from your logs.',
        DayState.mixed =>
          'Mixed logged day: middling wellness score from your logs.',
        DayState.difficult =>
          'Difficult logged day: low wellness score from your logs. A visual classification only.',
        DayState.insufficient =>
          'No data logged on this day. Not a bad day — just no logs.',
      };
}

DayState stateForScore(int? score, bool hasData) {
  if (!hasData || score == null) return DayState.insufficient;
  if (score >= 80) return DayState.excellent;
  if (score >= 60) return DayState.good;
  if (score >= 40) return DayState.mixed;
  return DayState.difficult;
}

/// Metric focus filter for highlighting detail rows.
enum CalendarFocus { all, sleep, stress }

/// One calendar day with its visual state and detail.
class CalendarDay {
  final DateTime date;
  final String key;
  final bool inMonth;
  final bool hasData;
  final int? wellness;
  final DayState state;
  final double? sleepHours;
  final int? exerciseMinutes;
  final int? waterGlasses;
  final double? calm;
  final double? mood;
  final List<String> habits; // experiment check-in titles + logging
  final List<String> experimentStatus; // active experiment titles that day
  final int journalCount;
  final int documentCount;

  const CalendarDay({
    required this.date,
    required this.key,
    required this.inMonth,
    required this.hasData,
    required this.wellness,
    required this.state,
    this.sleepHours,
    this.exerciseMinutes,
    this.waterGlasses,
    this.calm,
    this.mood,
    this.habits = const [],
    this.experimentStatus = const [],
    this.journalCount = 0,
    this.documentCount = 0,
  });
}

/// Monthly summary — only values with actual data behind them.
class MonthSummary {
  final int year;
  final int month;
  final int daysLogged;
  final int daysInMonth;
  final double? avgWellness;
  final String? bestDay;
  final int? bestScore;
  final String? mostConsistentMetric;
  final String? biggestImprovement; // "12 Sep → 13 Sep (+14)"
  final List<String> activeExperiments;
  final List<String> completedExperiments;
  final int journalCount;

  const MonthSummary({
    required this.year,
    required this.month,
    required this.daysLogged,
    required this.daysInMonth,
    required this.avgWellness,
    required this.bestDay,
    required this.bestScore,
    required this.mostConsistentMetric,
    required this.biggestImprovement,
    required this.activeExperiments,
    required this.completedExperiments,
    required this.journalCount,
  });
}

/// Logging-consistency level 0..4 for the heatmap (0 = no logs).
int consistencyLevel({
  required bool hasEntry,
  required bool hasMorning,
  required bool hasEvening,
  required bool hasStress,
}) {
  if (!hasEntry && !hasMorning && !hasEvening && !hasStress) return 0;
  var n = 0;
  if (hasEntry) n += 2;
  if (hasMorning) n++;
  if (hasEvening) n++;
  if (hasStress) n++;
  if (n >= 5) return 4;
  if (n >= 4) return 3;
  if (n >= 2) return 2;
  return 1;
}

/// Builds the 42-cell month grid (leading/trailing days included, flagged
/// with [inMonth] = false). Pure; missing data stays missing.
List<CalendarDay> buildMonthGrid({
  required int year,
  required int month,
  required Map<String, DailyHealthEntry> dailyByDate,
  required Map<String, double> calmByDate,
  required Map<String, List<int>> moodSourcesByDate,
  required Map<String, MorningCheckIn> morningByDate,
  required Map<String, EveningReflection> eveningByDate,
  required List<Experiment> experiments,
  required Map<String, int> journalCountByDate,
  required Map<String, int> documentCountByDate,
}) {
  final first = DateTime(year, month, 1);
  // Monday-first grid.
  final lead = first.weekday - 1;
  final start = first.subtract(Duration(days: lead));
  final days = <CalendarDay>[];
  for (var i = 0; i < 42; i++) {
    final d = start.add(Duration(days: i));
    days.add(_buildDay(
      date: d,
      inMonth: d.month == month,
      dailyByDate: dailyByDate,
      calmByDate: calmByDate,
      moodSourcesByDate: moodSourcesByDate,
      morningByDate: morningByDate,
      eveningByDate: eveningByDate,
      experiments: experiments,
      journalCountByDate: journalCountByDate,
      documentCountByDate: documentCountByDate,
    ));
  }
  return days;
}

CalendarDay _buildDay({
  required DateTime date,
  required bool inMonth,
  required Map<String, DailyHealthEntry> dailyByDate,
  required Map<String, double> calmByDate,
  required Map<String, List<int>> moodSourcesByDate,
  required Map<String, MorningCheckIn> morningByDate,
  required Map<String, EveningReflection> eveningByDate,
  required List<Experiment> experiments,
  required Map<String, int> journalCountByDate,
  required Map<String, int> documentCountByDate,
}) {
  final key = formatDateForStorage(date);
  final entry = dailyByDate[key];
  final morning = morningByDate[key];
  final evening = eveningByDate[key];
  final calm = calmByDate[key];
  final moods = moodSourcesByDate[key] ?? const [];

  final hasData = entry != null ||
      morning != null ||
      evening != null ||
      calm != null ||
      moods.isNotEmpty;

  int? wellness;
  if (entry != null) {
    var in7 = 0;
    for (var i = 0; i < 7; i++) {
      if (dailyByDate.containsKey(formatDateForStorage(
          date.subtract(Duration(days: i))))) {
        in7++;
      }
    }
    wellness = WellnessScoreCalculator.scoreForDay(
      entry,
      calmScore: calm?.round(),
      daysLoggedLast7: in7,
    );
  }

  final habits = <String>[];
  for (final e in experiments) {
    if (e.checkIns.contains(key)) habits.add('${e.title} ✓');
  }
  if (entry != null) habits.add('Logged Today');

  final active = <String>[];
  for (final e in experiments) {
    if (e.startDate == null) continue;
    final s = DateTime(
        e.startDate!.year, e.startDate!.month, e.startDate!.day);
    final end = e.endDate ?? s.add(Duration(days: e.durationDays));
    final day = DateTime(date.year, date.month, date.day);
    if (!day.isBefore(s) && !day.isAfter(end)) active.add(e.title);
  }

  double? mood;
  if (moods.isNotEmpty) {
    mood = moods.reduce((a, b) => a + b) / moods.length;
  }

  return CalendarDay(
    date: date,
    key: key,
    inMonth: inMonth,
    hasData: hasData,
    wellness: wellness,
    state: stateForScore(wellness, hasData),
    sleepHours: entry != null && entry.sleepHours > 0
        ? entry.sleepHours
        : morning?.sleepHours,
    exerciseMinutes: entry?.exerciseMinutes,
    waterGlasses: entry?.waterGlasses,
    calm: calm,
    mood: mood,
    habits: habits,
    experimentStatus: active,
    journalCount: journalCountByDate[key] ?? 0,
    documentCount: documentCountByDate[key] ?? 0,
  );
}

/// Summarizes one month of built days + experiments overlapping it.
MonthSummary summarizeMonth({
  required int year,
  required int month,
  required List<CalendarDay> days,
  required List<Experiment> experiments,
}) {
  final inMonth = days.where((d) => d.inMonth).toList();
  final logged = inMonth.where((d) => d.hasData).toList();
  final scores = [
    for (final d in logged)
      if (d.wellness != null) d,
  ];
  double? avg;
  String? bestDay;
  int? bestScore;
  if (scores.isNotEmpty) {
    avg = scores.map((d) => d.wellness!.toDouble()).reduce((a, b) => a + b) /
        scores.length;
    final best = scores.reduce(
        (a, b) => (a.wellness ?? 0) >= (b.wellness ?? 0) ? a : b);
    bestDay = best.key;
    bestScore = best.wellness;
  }

  // Most consistent metric: lowest coefficient of variation (needs 3+).
  String? mostConsistent;
  {
    final series = <String, List<double>>{
      'Sleep': [
        for (final d in logged)
          if (d.sleepHours != null && d.sleepHours! > 0) d.sleepHours!,
      ],
      'Exercise': [
        for (final d in logged)
          if (d.exerciseMinutes != null) d.exerciseMinutes!.toDouble(),
      ],
      'Water': [
        for (final d in logged)
          if (d.waterGlasses != null) d.waterGlasses!.toDouble(),
      ],
    };
    var bestCv = double.infinity;
    series.forEach((label, vals) {
      if (vals.length < 3) return;
      final mean = vals.reduce((a, b) => a + b) / vals.length;
      if (mean <= 0) return;
      final variance =
          vals.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
              vals.length;
      final cv = variance <= 0 ? 0.0 : _sqrt(variance) / mean;
      if (cv.isFinite && cv < bestCv) {
        bestCv = cv;
        mostConsistent = label;
      }
    });
  }

  // Biggest improvement: largest positive jump between consecutive logged
  // days (both with scores).
  String? biggest;
  {
    var bestJump = 0;
    for (var i = 1; i < scores.length; i++) {
      final jump = scores[i].wellness! - scores[i - 1].wellness!;
      if (jump > bestJump) {
        bestJump = jump;
        biggest = '${scores[i - 1].key} → ${scores[i].key} (+$jump)';
      }
    }
  }

  final monthStart = DateTime(year, month, 1);
  final monthEnd = DateTime(year, month + 1, 0);
  final active = <String>[];
  final completed = <String>[];
  for (final e in experiments) {
    final s = e.startDate == null
        ? null
        : DateTime(
            e.startDate!.year, e.startDate!.month, e.startDate!.day);
    final end = e.endDate ??
        (s?.add(Duration(days: e.durationDays)));
    final overlaps = s != null &&
        end != null &&
        !s.isAfter(monthEnd) &&
        !end.isBefore(monthStart);
    if (!overlaps) continue;
    if (e.status.name == 'completed') {
      completed.add(e.title);
    } else {
      active.add(e.title);
    }
  }

  return MonthSummary(
    year: year,
    month: month,
    daysLogged: logged.length,
    daysInMonth: monthEnd.day,
    avgWellness: avg != null && avg.isFinite ? avg : null,
    bestDay: bestDay,
    bestScore: bestScore,
    mostConsistentMetric: mostConsistent,
    biggestImprovement: biggest,
    activeExperiments: active,
    completedExperiments: completed,
    journalCount: inMonth.map((d) => d.journalCount).fold(0, (a, b) => a + b),
  );
}

double _sqrt(double v) {
  if (v <= 0) return 0.0;
  var x = v > 1 ? v / 2 : 1.0;
  for (var i = 0; i < 20; i++) {
    x = (x + v / x) / 2;
  }
  return x.isFinite ? x : 0.0;
}

/// Month arithmetic helpers (navigation). Pure and testable.
DateTime nextMonth(int year, int month) =>
    month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);

DateTime prevMonth(int year, int month) =>
    month == 1 ? DateTime(year - 1, 12, 1) : DateTime(year, month - 1, 1);

DateTime nextYear(int year, int month) => DateTime(year + 1, month, 1);

DateTime prevYear(int year, int month) => DateTime(year - 1, month, 1);
