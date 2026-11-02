import '../../data/models/checkins.dart';
import '../../data/models/journal.dart';
import '../../data/models/models.dart';

/// Milestone categories. Rewards consistency, reflection, healthy routines,
/// learning and finishing — never extremes (no milestone exists for heavy
/// exercise, restrictive eating, skipped meals, excessive tracking,
/// oversleeping or medical outcomes; evaluation ignores such values).
enum MilestoneCategory {
  consistency,
  experiments,
  habits,
  reflection,
  healthData,
}

extension MilestoneCategoryX on MilestoneCategory {
  String get label => switch (this) {
        MilestoneCategory.consistency => 'Consistency',
        MilestoneCategory.experiments => 'Experiments',
        MilestoneCategory.habits => 'Habits',
        MilestoneCategory.reflection => 'Reflection',
        MilestoneCategory.healthData => 'Health Data',
      };
}

/// One achievable milestone definition.
class MilestoneDef {
  final String id;
  final MilestoneCategory category;
  final String title;
  final String description;
  final int target; // days / count that completes it

  const MilestoneDef({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.target,
  });
}

const List<MilestoneDef> milestoneDefs = [
  MilestoneDef(
    id: 'streak-3',
    category: MilestoneCategory.consistency,
    title: '3 Day Streak',
    description: 'You logged your wellness 3 days in a row.',
    target: 3,
  ),
  MilestoneDef(
    id: 'streak-7',
    category: MilestoneCategory.consistency,
    title: '7 Day Streak',
    description: 'You logged your wellness 7 days in a row.',
    target: 7,
  ),
  MilestoneDef(
    id: 'streak-30',
    category: MilestoneCategory.consistency,
    title: '30 Day Streak',
    description: 'You logged your wellness 30 days in a row.',
    target: 30,
  ),
  MilestoneDef(
    id: 'streak-100',
    category: MilestoneCategory.consistency,
    title: '100 Day Streak',
    description: 'You logged your wellness 100 days in a row.',
    target: 100,
  ),
  MilestoneDef(
    id: 'exp-first',
    category: MilestoneCategory.experiments,
    title: 'First Experiment',
    description: 'You started your first self-experiment.',
    target: 1,
  ),
  MilestoneDef(
    id: 'exp-complete-1',
    category: MilestoneCategory.experiments,
    title: 'First Finish',
    description: 'You completed your first experiment.',
    target: 1,
  ),
  MilestoneDef(
    id: 'exp-complete-5',
    category: MilestoneCategory.experiments,
    title: 'Seasoned Experimenter',
    description: 'You completed 5 experiments.',
    target: 5,
  ),
  MilestoneDef(
    id: 'habit-first',
    category: MilestoneCategory.habits,
    title: 'First Habit Done',
    description: 'You completed your first habit check-in.',
    target: 1,
  ),
  MilestoneDef(
    id: 'habit-streak-7',
    category: MilestoneCategory.habits,
    title: '7-Day Consistency',
    description: 'You kept a habit going 7 days in a row.',
    target: 7,
  ),
  MilestoneDef(
    id: 'habit-streak-30',
    category: MilestoneCategory.habits,
    title: '30-Day Consistency',
    description: 'You kept a habit going 30 days in a row.',
    target: 30,
  ),
  MilestoneDef(
    id: 'journal-first',
    category: MilestoneCategory.reflection,
    title: 'First Reflection',
    description: 'You wrote your first journal entry.',
    target: 1,
  ),
  MilestoneDef(
    id: 'reflections-10',
    category: MilestoneCategory.reflection,
    title: '10 Reflections',
    description: 'You logged 10 reflections.',
    target: 10,
  ),
  MilestoneDef(
    id: 'reflections-30',
    category: MilestoneCategory.reflection,
    title: '30 Reflections',
    description: 'You logged 30 reflections.',
    target: 30,
  ),
  MilestoneDef(
    id: 'complete-1',
    category: MilestoneCategory.healthData,
    title: 'First Complete Day',
    description: 'You completed a full healthy tracking routine in one day.',
    target: 1,
  ),
  MilestoneDef(
    id: 'complete-7',
    category: MilestoneCategory.healthData,
    title: '7 Complete Days',
    description: 'You completed full tracking routines on 7 days.',
    target: 7,
  ),
  MilestoneDef(
    id: 'complete-30',
    category: MilestoneCategory.healthData,
    title: '30 Complete Days',
    description: 'You completed full tracking routines on 30 days.',
    target: 30,
  ),
];

/// Evaluated state of one milestone. Pure derivation from real data:
/// re-evaluating the same data yields the same single result, so
/// duplicates are impossible and nothing is ever awarded without evidence.
class MilestoneStatus {
  final MilestoneDef def;
  final bool unlocked;
  final DateTime? achievedDate;
  final int progress;
  final bool celebrated;

  const MilestoneStatus({
    required this.def,
    required this.unlocked,
    required this.achievedDate,
    required this.progress,
    this.celebrated = false,
  });

  MilestoneStatus markCelebrated() => MilestoneStatus(
        def: def,
        unlocked: unlocked,
        achievedDate: achievedDate,
        progress: progress,
        celebrated: true,
      );
}

/// Everything the evaluator reads. Plain data, no storage access.
class MilestoneInput {
  final Map<String, DailyHealthEntry> entriesByDate;
  final Set<String> stressDates;
  final List<Experiment> experiments;
  final List<JournalEntry> journals;
  final List<EveningReflection> evenings;
  final DateTime now;

  const MilestoneInput({
    required this.entriesByDate,
    required this.stressDates,
    required this.experiments,
    required this.journals,
    required this.evenings,
    required this.now,
  });
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Consecutive-day runs (ascending) from yyyy-MM-dd keys.
List<(DateTime start, DateTime end, int length)> _runs(
    Iterable<String> keys) {
  final days = keys
      .map((k) => DateTime.tryParse(k))
      .whereType<DateTime>()
      .map(_day)
      .toSet()
      .toList()
    ..sort();
  final out = <(DateTime, DateTime, int)>[];
  DateTime? start;
  DateTime? prev;
  for (final d in days) {
    if (prev != null && d.difference(prev).inDays == 1) {
      prev = d;
    } else {
      if (start != null && prev != null) {
        out.add((start, prev, prev.difference(start).inDays + 1));
      }
      start = d;
      prev = d;
    }
  }
  if (start != null && prev != null) {
    out.add((start, prev, prev.difference(start).inDays + 1));
  }
  return out;
}

/// First date on which a run reached [target] (the run's Nth day).
DateTime? _firstReached(
    List<(DateTime start, DateTime end, int length)> runs,
    int target) {
  DateTime? best;
  for (final r in runs) {
    if (r.$3 >= target) {
      final hit = r.$1.add(Duration(days: target - 1));
      if (best == null || hit.isBefore(best)) best = hit;
    }
  }
  return best;
}

/// Current run length ending today (or yesterday when today is unlogged).
int _currentRunLength(Iterable<String> keys, DateTime now) {
  final set = keys
      .map((k) => DateTime.tryParse(k))
      .whereType<DateTime>()
      .map(_day)
      .toSet();
  var cursor = _day(now);
  if (!set.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  var n = 0;
  while (set.contains(cursor)) {
    n++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return n;
}

/// A "complete day": every routine section has real data (sleep, movement,
/// water, meditation logged plus a stress check-in). Extreme values never
/// count extra — consistency only.
bool _isCompleteDay(DailyHealthEntry e, bool hasStress) =>
    e.sleepHours > 0 &&
    e.exerciseMinutes > 0 &&
    e.waterGlasses > 0 &&
    e.meditationMinutes > 0 &&
    hasStress;

/// Evaluates every milestone from real data. Deterministic.
List<MilestoneStatus> evaluateMilestones(MilestoneInput input) {
  final loggedRuns = _runs(input.entriesByDate.keys);
  final currentStreak = _currentRunLength(
      input.entriesByDate.keys, input.now);

  final completeDates = <String>[];
  input.entriesByDate.forEach((key, e) {
    if (_isCompleteDay(e, input.stressDates.contains(key))) {
      completeDates.add(key);
    }
  });
  completeDates.sort();

  final started = [...input.experiments]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final completed = [
    for (final e in input.experiments)
      if (e.status.name == 'completed') e,
  ]..sort((a, b) {
      final da = a.endDate ?? a.updatedAt;
      final db = b.endDate ?? b.updatedAt;
      return da.compareTo(db);
    });

  final doneDates = <String>{};
  for (final e in input.experiments) {
    doneDates.addAll(e.checkIns);
  }
  final habitRuns = _runs(doneDates);
  var habitBest = 0;
  for (final r in habitRuns) {
    if (r.$3 > habitBest) habitBest = r.$3;
  }
  final firstDone = doneDates.isEmpty
      ? null
      : (doneDates.map((k) => DateTime.parse(k)).toList()..sort()).first;

  final reflectionDates = <DateTime>[
    for (final j in input.journals)
      if (DateTime.tryParse(j.date) != null)
        _day(DateTime.parse(j.date)),
    for (final v in input.evenings) _day(v.updatedAt),
  ]..sort();

  DateTime? nthDate(List<DateTime> sorted, int n) =>
      sorted.length >= n ? sorted[n - 1] : null;

  MilestoneStatus build(
    String id, {
    required bool unlocked,
    required DateTime? achieved,
    required int progress,
  }) {
    final def = milestoneDefs.firstWhere((d) => d.id == id);
    return MilestoneStatus(
      def: def,
      unlocked: unlocked,
      achievedDate:
          unlocked && achieved != null ? _day(achieved) : null,
      progress: progress.clamp(0, def.target),
    );
  }

  return [
    for (final n in [3, 7, 30, 100])
      build('streak-$n',
          unlocked: _firstReached(loggedRuns, n) != null,
          achieved: _firstReached(loggedRuns, n),
          progress: currentStreak),
    build('exp-first',
        unlocked: started.isNotEmpty,
        achieved:
            started.isEmpty ? null : started.first.createdAt,
        progress: started.isEmpty ? 0 : 1),
    build('exp-complete-1',
        unlocked: completed.isNotEmpty,
        achieved: completed.isEmpty
            ? null
            : (completed.first.endDate ??
                completed.first.updatedAt),
        progress: completed.isEmpty ? 0 : 1),
    build('exp-complete-5',
        unlocked: completed.length >= 5,
        achieved: completed.length >= 5
            ? (completed[4].endDate ?? completed[4].updatedAt)
            : null,
        progress: completed.length),
    build('habit-first',
        unlocked: firstDone != null,
        achieved: firstDone,
        progress: firstDone == null ? 0 : 1),
    for (final n in [7, 30])
      build('habit-streak-$n',
          unlocked: _firstReached(habitRuns, n) != null,
          achieved: _firstReached(habitRuns, n),
          progress: habitBest),
    build('journal-first',
        unlocked: reflectionDates.isNotEmpty,
        achieved: nthDate(reflectionDates, 1),
        progress:
            reflectionDates.isEmpty ? 0 : 1),
    for (final n in [10, 30])
      build('reflections-$n',
          unlocked: reflectionDates.length >= n,
          achieved: nthDate(reflectionDates, n),
          progress: reflectionDates.length),
    for (final n in [1, 7, 30])
      build('complete-$n',
          unlocked: completeDates.length >= n,
          achieved: completeDates.length >= n
              ? DateTime.parse(completeDates[n - 1])
              : null,
          progress: completeDates.length),
  ];
}

/// Nearest locked milestone by completion fraction (for "Next milestone").
MilestoneStatus? nextMilestone(List<MilestoneStatus> all) {
  final locked = all.where((m) => !m.unlocked).toList();
  if (locked.isEmpty) return null;
  locked.sort((a, b) {
    final fa = a.progress / a.def.target;
    final fb = b.progress / b.def.target;
    final cmp = fb.compareTo(fa);
    return cmp != 0 ? cmp : a.def.target.compareTo(b.def.target);
  });
  return locked.first;
}

/// Most recently unlocked milestone (for the dashboard card).
MilestoneStatus? mostRecentMilestone(List<MilestoneStatus> all) {
  final unlocked = [
    for (final m in all)
      if (m.unlocked && m.achievedDate != null) m,
  ];
  if (unlocked.isEmpty) return null;
  unlocked.sort(
      (a, b) => b.achievedDate!.compareTo(a.achievedDate!));
  return unlocked.first;
}
