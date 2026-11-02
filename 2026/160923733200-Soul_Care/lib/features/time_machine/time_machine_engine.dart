import '../../core/utils/utils.dart';
import '../../core/wellness/wellness_score.dart';
import '../../data/models/checkins.dart';
import '../../data/models/enums.dart';
import '../../data/models/journal.dart';
import '../../data/models/models.dart';
import '../../features/profile/goal_progress.dart';

/// SoulCare Time Machine engine — pure, deterministic, local-only.
///
/// Replays personal wellness history from logged records. Never fabricates
/// history: dates without logged data are reported as unavailable.
/// Language is factual and association-only; nothing here claims causality
/// or makes medical assessments.
enum TimeEventType {
  healthLog,
  experimentStarted,
  experimentCompleted,
  habitActivity,
  habitMilestone,
  journalEntry,
  documentAdded,
  goalReached,
}

extension TimeEventTypeX on TimeEventType {
  String get label => switch (this) {
        TimeEventType.healthLog => 'Health entry logged',
        TimeEventType.experimentStarted => 'Experiment started',
        TimeEventType.experimentCompleted => 'Experiment completed',
        TimeEventType.habitActivity => 'Experiment check-in',
        TimeEventType.habitMilestone => 'Habit milestone',
        TimeEventType.journalEntry => 'Journal entry',
        TimeEventType.documentAdded => 'Medical document added',
        TimeEventType.goalReached => 'Goal reached',
      };
}

/// One timeline marker on a specific date.
class TimeEvent {
  final String dateKey; // yyyy-MM-dd
  final TimeEventType type;
  final String title;
  final String detail;

  const TimeEvent({
    required this.dateKey,
    required this.type,
    required this.title,
    required this.detail,
  });
}

/// Logging-streak lengths that earn a habit milestone marker.
const List<int> kStreakMilestones = [3, 7, 14, 30, 60, 100, 180, 365];

/// The dashboard state for one date, rebuilt from that date's records.
class DayReplay {
  final String dateKey;
  final DateTime date;
  final bool hasData;
  final int? wellness;
  final double? sleepHours;
  final int? sleepScore;
  final double? calm; // 0..100, higher = calmer
  final double? mood; // 1..5 average across logged sources
  final double? energy; // 1..5 average across logged sources
  final int? exerciseMinutes;
  final int? waterGlasses;
  final int? meditationMinutes;
  final String? activeExperiment;
  final List<String> notes; // journal titles/summaries for the date
  final String? unavailableReason;

  const DayReplay({
    required this.dateKey,
    required this.date,
    required this.hasData,
    this.wellness,
    this.sleepHours,
    this.sleepScore,
    this.calm,
    this.mood,
    this.energy,
    this.exerciseMinutes,
    this.waterGlasses,
    this.meditationMinutes,
    this.activeExperiment,
    this.notes = const [],
    this.unavailableReason,
  });
}

/// Aggregate over a selected period (week/month).
class PeriodSummary {
  final List<DayReplay> days;
  final int loggedDays;
  final double? avgWellness;
  final double? avgSleep;
  final int totalExercise;
  final double? change; // last logged wellness minus first logged wellness

  const PeriodSummary({
    required this.days,
    required this.loggedDays,
    required this.avgWellness,
    required this.avgSleep,
    required this.totalExercise,
    required this.change,
  });
}

/// One compared metric between two dates/periods.
class ComparisonRow {
  final String metric;
  final String sideA;
  final String sideB;
  final String delta; // value or 'unavailable'

  const ComparisonRow({
    required this.metric,
    required this.sideA,
    required this.sideB,
    required this.delta,
  });
}

String _key(DateTime d) => formatDateForStorage(d);

/// Builds one day's replay from records. Pure; missing data stays missing.
DayReplay buildDayReplay({
  required DateTime date,
  required Map<String, DailyHealthEntry> dailyByDate,
  required Map<String, List<int>> stressMoodsByDate,
  required Map<String, MorningCheckIn> morningByDate,
  required Map<String, EveningReflection> eveningByDate,
  required List<Experiment> experiments,
  required Map<String, List<JournalEntry>> journalsByDate,
}) {
  final key = _key(date);
  final entry = dailyByDate[key];
  final morning = morningByDate[key];
  final evening = eveningByDate[key];
  final moods = stressMoodsByDate[key];
  final journals = journalsByDate[key] ?? const [];

  final hasAny = entry != null ||
      morning != null ||
      evening != null ||
      (moods != null && moods.isNotEmpty) ||
      journals.isNotEmpty;
  if (!hasAny) {
    return DayReplay(
      dateKey: key,
      date: date,
      hasData: false,
      unavailableReason:
          'Nothing was logged on $key. History is only shown for dates with logged data — nothing is filled in.',
    );
  }

  int? wellness;
  int? sleepScore;
  if (entry != null) {
    sleepScore = calculateSleepScore(
      entry.sleepHours,
      entry.sleepQuality.score,
      entry.feltRested,
    );
    // Trailing-7-day logging count for the consistency component.
    var logged7 = 0;
    for (var i = 0; i < 7; i++) {
      if (dailyByDate.containsKey(_key(date.subtract(Duration(days: i))))) {
        logged7++;
      }
    }
    wellness = WellnessScoreCalculator.scoreForDay(
      entry,
      calmScore: (moods != null && moods.isNotEmpty)
          ? (moods.reduce((a, b) => a + b) / moods.length / 5 * 100).round()
          : null,
      daysLoggedLast7: logged7,
    );
  }

  double? calm;
  if (moods != null && moods.isNotEmpty) {
    calm = moods.reduce((a, b) => a + b) / moods.length / 5 * 100;
  }

  final moodSrc = <int>[
    if (moods != null) ...moods,
    if (morning != null) morning.mood,
    if (evening != null) evening.mood,
  ];
  final energySrc = <int>[
    if (morning != null) morning.energy,
    if (evening != null) evening.energy,
  ];

  String? active;
  for (final e in experiments) {
    if (e.startDate == null) continue;
    final start = DateTime(
        e.startDate!.year, e.startDate!.month, e.startDate!.day);
    final end = e.endDate ??
        start.add(Duration(days: e.durationDays));
    final day = DateTime(date.year, date.month, date.day);
    if (!day.isBefore(start) && !day.isAfter(end)) {
      active = e.title;
      break;
    }
  }

  return DayReplay(
    dateKey: key,
    date: date,
    hasData: true,
    wellness: wellness,
    sleepHours: entry != null && entry.sleepHours > 0
        ? entry.sleepHours
        : morning?.sleepHours,
    sleepScore: sleepScore,
    calm: calm,
    mood: moodSrc.isEmpty
        ? null
        : moodSrc.reduce((a, b) => a + b) / moodSrc.length,
    energy: energySrc.isEmpty
        ? null
        : energySrc.reduce((a, b) => a + b) / energySrc.length,
    exerciseMinutes: entry?.exerciseMinutes,
    waterGlasses: entry?.waterGlasses,
    meditationMinutes: entry?.meditationMinutes,
    activeExperiment: active,
    notes: [
      for (final j in journals)
        (j.title == null || j.title!.isEmpty)
            ? 'Note: ${_truncate(j.body, 120)}'
            : '${j.title}: ${_truncate(j.body, 120)}',
    ],
  );
}

String _truncate(String s, int n) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.length <= n ? t : '${t.substring(0, n)}…';
}

/// Collects timeline events from records (small metadata only — no bodies).
///
/// [dailyKeys] drives habit-milestone streak detection; [profile] targets
/// drive goal-reached detection over trailing 7-day windows.
List<TimeEvent> collectEvents({
  required Set<String> dailyKeys,
  required Map<String, DailyHealthEntry> dailyByDate,
  required List<Experiment> experiments,
  required List<JournalEntry> journals,
  required List<MedicalDocument> documents,
  double sleepTarget = 7.5,
  double exerciseTarget = 150,
  double waterTarget = 8,
  double meditationTarget = 10,
}) {
  final events = <TimeEvent>[];

  for (final e in experiments) {
    if (e.startDate != null) {
      final k = _key(e.startDate!);
      events.add(TimeEvent(
        dateKey: k,
        type: TimeEventType.experimentStarted,
        title: 'Started: ${e.title}',
        detail:
            '${e.durationDays}-day experiment began. Tracked start — outcomes depend on many factors.',
      ));
    }
    if (e.status == ExperimentStatus.completed) {
      final doneDate = e.endDate ??
          (e.checkIns.isNotEmpty
              ? DateTime.tryParse(e.checkIns.last)
              : null) ??
          e.startDate;
      if (doneDate != null) {
        events.add(TimeEvent(
          dateKey: _key(doneDate),
          type: TimeEventType.experimentCompleted,
          title: 'Completed: ${e.title}',
          detail:
              '${e.checkIns.length} check-ins over ${e.durationDays} days. Results reflect your logs.',
        ));
      }
    }
    for (final c in e.checkIns) {
      events.add(TimeEvent(
        dateKey: c,
        type: TimeEventType.habitActivity,
        title: '${e.title} — done',
        detail: 'Daily check-in completed.',
      ));
    }
  }

  for (final j in journals) {
    events.add(TimeEvent(
      dateKey: j.date,
      type: TimeEventType.journalEntry,
      title: (j.title == null || j.title!.isEmpty)
          ? 'Journal note'
          : j.title!,
      detail: j.tags.isEmpty
          ? 'Private entry.'
          : 'Tagged: ${j.tags.join(', ')}.',
    ));
  }

  for (final d in documents) {
    final when = d.documentDate ?? d.importedAt;
    events.add(TimeEvent(
      dateKey: _key(when),
      type: TimeEventType.documentAdded,
      title: 'Document: ${d.fileName}',
      detail: 'Category: ${d.category.name}. Stored on this device.',
    ));
  }

  // Habit milestones: logging streaks reaching milestone lengths.
  final days = dailyKeys
      .map((k) => DateTime.tryParse(k))
      .whereType<DateTime>()
      .map((d) => DateTime(d.year, d.month, d.day))
      .toList()
    ..sort();
  var run = 0;
  DateTime? prev;
  for (final d in days) {
    if (prev != null && d.difference(prev).inDays == 1) {
      run++;
    } else {
      run = 1;
    }
    if (kStreakMilestones.contains(run)) {
      events.add(TimeEvent(
        dateKey: _key(d),
        type: TimeEventType.habitMilestone,
        title: '$run-day logging streak',
        detail:
            'You logged $run days in a row. Consistency builds your history.',
      ));
    }
    prev = d;
  }

  // Goal reached: trailing-7-day windows where every goal hits 100%,
  // edge-triggered (emitted only when the previous day was not complete).
  final sortedKeys = days.map(_key).toList();
  var wasComplete = false;
  for (final k in sortedKeys) {
    final day = DateTime.parse(k);
    final window = <DailyHealthEntry>[];
    for (var i = 6; i >= 0; i--) {
      final e = dailyByDate[_key(day.subtract(Duration(days: i)))];
      if (e != null) window.add(e);
    }
    if (window.length < 2) {
      wasComplete = false;
      continue;
    }
    final items = computeGoalItems(
      entries: window,
      sleepTarget: sleepTarget,
      exerciseTarget: exerciseTarget,
      waterTarget: waterTarget,
      meditationTarget: meditationTarget,
    );
    final complete = items.every((g) => g.$2.fraction >= 1.0);
    if (complete && !wasComplete) {
      events.add(TimeEvent(
        dateKey: k,
        type: TimeEventType.goalReached,
        title: 'Goals reached',
        detail:
            'Sleep, movement, water and meditation targets all met over the last 7 logged days.',
      ));
    }
    wasComplete = complete;
  }

  events.sort((a, b) => a.dateKey.compareTo(b.dateKey));
  return events;
}

/// Summarizes a period of day replays (missing days left out, never filled).
PeriodSummary summarizePeriod(List<DayReplay> days) {
  final logged = days.where((d) => d.hasData).toList();
  final wellnessVals = [
    for (final d in logged)
      if (d.wellness != null) d.wellness!.toDouble(),
  ];
  final sleepVals = [
    for (final d in logged)
      if (d.sleepHours != null && d.sleepHours! > 0) d.sleepHours!,
  ];
  var exercise = 0;
  for (final d in logged) {
    exercise += d.exerciseMinutes ?? 0;
  }
  double? change;
  if (wellnessVals.length >= 2) {
    change = wellnessVals.last - wellnessVals.first;
  }
  double avg(List<double> v) => v.reduce((a, b) => a + b) / v.length;
  return PeriodSummary(
    days: days,
    loggedDays: logged.length,
    avgWellness: wellnessVals.isEmpty ? null : avg(wellnessVals),
    avgSleep: sleepVals.isEmpty ? null : avg(sleepVals),
    totalExercise: exercise,
    change: change,
  );
}

String _fmt(double? v, [int digits = 1]) =>
    v == null ? 'unavailable' : v.toStringAsFixed(digits);

/// Compares two day replays (or two period summaries) side by side.
/// Unavailable on either side is reported honestly as 'unavailable'.
List<ComparisonRow> compareDays(DayReplay a, DayReplay b) {
  String delta(String sa, String sb, double? va, double? vb,
      [int digits = 1]) {
    if (va == null || vb == null) return 'unavailable';
    final d = vb - va;
    return '${d >= 0 ? '+' : ''}${d.toStringAsFixed(digits)}';
  }

  return [
    ComparisonRow(
      metric: 'Wellness score',
      sideA: a.wellness?.toString() ?? 'unavailable',
      sideB: b.wellness?.toString() ?? 'unavailable',
      delta: delta('', '', a.wellness?.toDouble(), b.wellness?.toDouble(), 0),
    ),
    ComparisonRow(
      metric: 'Sleep',
      sideA: a.sleepHours == null ? 'unavailable' : formatHours(a.sleepHours!),
      sideB: b.sleepHours == null ? 'unavailable' : formatHours(b.sleepHours!),
      delta: delta('', '', a.sleepHours, b.sleepHours),
    ),
    ComparisonRow(
      metric: 'Calm',
      sideA: _fmt(a.calm, 0),
      sideB: _fmt(b.calm, 0),
      delta: delta('', '', a.calm, b.calm, 0),
    ),
    ComparisonRow(
      metric: 'Mood (1–5)',
      sideA: _fmt(a.mood),
      sideB: _fmt(b.mood),
      delta: delta('', '', a.mood, b.mood),
    ),
    ComparisonRow(
      metric: 'Exercise',
      sideA: a.exerciseMinutes == null
          ? 'unavailable'
          : '${a.exerciseMinutes} min',
      sideB: b.exerciseMinutes == null
          ? 'unavailable'
          : '${b.exerciseMinutes} min',
      delta: delta('', '', a.exerciseMinutes?.toDouble(),
          b.exerciseMinutes?.toDouble(), 0),
    ),
    ComparisonRow(
      metric: 'Water',
      sideA: a.waterGlasses == null
          ? 'unavailable'
          : '${a.waterGlasses} glasses',
      sideB: b.waterGlasses == null
          ? 'unavailable'
          : '${b.waterGlasses} glasses',
      delta: delta('', '', a.waterGlasses?.toDouble(),
          b.waterGlasses?.toDouble(), 0),
    ),
  ];
}

/// Compares two period summaries.
List<ComparisonRow> comparePeriods(PeriodSummary a, PeriodSummary b) {
  String delta(double? va, double? vb, [int digits = 1]) {
    if (va == null || vb == null) return 'unavailable';
    final d = vb - va;
    return '${d >= 0 ? '+' : ''}${d.toStringAsFixed(digits)}';
  }

  return [
    ComparisonRow(
      metric: 'Avg wellness',
      sideA: _fmt(a.avgWellness, 0),
      sideB: _fmt(b.avgWellness, 0),
      delta: delta(a.avgWellness, b.avgWellness, 0),
    ),
    ComparisonRow(
      metric: 'Avg sleep',
      sideA: a.avgSleep == null ? 'unavailable' : formatHours(a.avgSleep!),
      sideB: b.avgSleep == null ? 'unavailable' : formatHours(b.avgSleep!),
      delta: delta(a.avgSleep, b.avgSleep),
    ),
    ComparisonRow(
      metric: 'Total exercise',
      sideA: '${a.totalExercise} min',
      sideB: '${b.totalExercise} min',
      delta: delta(
          a.totalExercise.toDouble(), b.totalExercise.toDouble(), 0),
    ),
    ComparisonRow(
      metric: 'Logged days',
      sideA: '${a.loggedDays}',
      sideB: '${b.loggedDays}',
      delta: delta(
          a.loggedDays.toDouble(), b.loggedDays.toDouble(), 0),
    ),
  ];
}

/// Days with important changes for replay narration: wellness swings of
/// 10+ points vs the previous logged day, or days carrying milestone-type
/// events. Pure helper so replay narration is testable.
List<String> importantChangeKeys({
  required List<DayReplay> ordered,
  required Map<String, List<TimeEvent>> eventsByDate,
}) {
  final out = <String>[];
  DayReplay? prevLogged;
  for (final d in ordered) {
    var important = false;
    if (d.hasData &&
        d.wellness != null &&
        prevLogged?.wellness != null) {
      if ((d.wellness! - prevLogged!.wellness!).abs() >= 10) {
        important = true;
      }
    }
    final evs = eventsByDate[d.dateKey] ?? const [];
    if (evs.any((e) =>
        e.type == TimeEventType.experimentStarted ||
        e.type == TimeEventType.experimentCompleted ||
        e.type == TimeEventType.habitMilestone ||
        e.type == TimeEventType.goalReached)) {
      important = true;
    }
    if (important) out.add(d.dateKey);
    if (d.hasData) prevLogged = d;
  }
  return out;
}
