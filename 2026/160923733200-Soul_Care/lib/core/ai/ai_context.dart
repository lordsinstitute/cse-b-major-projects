import '../../core/utils/utils.dart';
import '../../core/wellness/insights.dart';
import '../../core/wellness/wellness_score.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../data/repositories/daily_health_repository.dart';
import '../../data/repositories/experiment_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/stress_repository.dart';
import '../../features/experiments/experiment_engine.dart';

/// Read-only structured data tools for SoulCare AI. Every method reads
/// repositories and returns small computed summaries — the model receives
/// only what the current question needs, never database dumps. Journal
/// bodies and document contents are NOT reachable from here at all.
class SoulCareContext {
  final DailyHealthRepository _daily;
  final StressRepository _stress;
  final ExperimentRepository _experiments;
  final ProfileRepository _profile;

  SoulCareContext({
    DailyHealthRepository? daily,
    StressRepository? stress,
    ExperimentRepository? experiments,
    ProfileRepository? profile,
  })  : _daily = daily ?? DailyHealthRepository(),
        _stress = stress ?? StressRepository(),
        _experiments = experiments ?? ExperimentRepository(),
        _profile = profile ?? ProfileRepository();

  Future<List<DailyHealthEntry>> _entries(
      DateTime from, DateTime to) async {
    final res = await _daily.getRange(from, to);
    return res.fold(
        onSuccess: (l) => l, onFailure: (_) => const []);
  }

  Future<Map<String, List<int>>> _moods(
      DateTime from, DateTime to) async {
    final out = <String, List<int>>{};
    final res = await _stress.getRange(from, to);
    res.fold(onSuccess: (list) {
      for (final c in list) {
        out.putIfAbsent(c.date, () => []).add(c.mood.score);
      }
    }, onFailure: (_) {});
    return out;
  }

  double? _avg(List<double> v) =>
      v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;

  Map<String, double?> _sleepStats(List<DailyHealthEntry> entries) {
    final vals = [
      for (final e in entries)
        if (e.sleepHours > 0) e.sleepHours,
    ];
    if (vals.isEmpty) return {'avg': null, 'n': 0};
    vals.sort();
    return {
      'avg': _avg(vals),
      'best': vals.last,
      'lowest': vals.first,
      'n': vals.length.toDouble(),
    };
  }

  /// Today: score, sleep, exercise, water, calm, mood.
  Future<Map<String, dynamic>> getTodaySummary() async {
    final now = DateTime.now();
    final key = formatDateForStorage(now);
    final entry = (await _daily.getByDate(key)).fold(
        onSuccess: (e) => e, onFailure: (_) => null);
    final checks = (await _stress.getByDate(key)).fold(
        onSuccess: (l) => l, onFailure: (_) => const <StressEntry>[]);
    if (entry == null && checks.isEmpty) {
      return {'logged': false};
    }
    final calm = checks.isEmpty
        ? null
        : calmFromMoods(checks.map((c) => c.mood.score).toList());
    final score = entry == null
        ? null
        : WellnessScoreCalculator.scoreForDay(entry,
            calmScore: calm, daysLoggedLast7: 1);
    return {
      'logged': true,
      'wellness_score': ?score,
      if (entry case final DailyHealthEntry e) ...{
        'sleep_hours': e.sleepHours,
        'exercise_minutes': e.exerciseMinutes,
        'water_glasses': e.waterGlasses,
        'meditation_minutes': e.meditationMinutes,
      },
      'calm': ?calm,
    };
  }

  Future<Map<String, dynamic>> _weekSummary(int weeksAgo) async {
    final now = DateTime.now();
    final end =
        DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: weeksAgo * 7));
    final start = end.subtract(const Duration(days: 6));
    final entries = await _entries(start, end);
    final moods = await _moods(start, end);
    if (entries.isEmpty) {
      return {'days_logged': 0};
    }
    final sleep = _sleepStats(entries);
    final exercise =
        entries.map((e) => e.exerciseMinutes).fold(0, (a, b) => a + b);
    final waters = [
      for (final e in entries)
        if (e.waterGlasses > 0) e.waterGlasses.toDouble(),
    ];
    final scores = [
      for (final e in entries)
        WellnessScoreCalculator.scoreForDay(e,
            calmScore: moods[e.date] == null
                ? null
                : ((moods[e.date]!.reduce((a, b) => a + b) /
                            moods[e.date]!.length) /
                        5 *
                        100)
                    .round(),
            daysLoggedLast7: entries.length),
    ];
    return {
      'days_logged': entries.length,
      'avg_wellness': _avg(scores.map((s) => s.toDouble()).toList())
          ?.toStringAsFixed(0),
      'avg_sleep_hours': sleep['avg']?.toStringAsFixed(2),
      'best_sleep_hours': sleep['best'],
      'lowest_sleep_hours': sleep['lowest'],
      'exercise_total_min': exercise,
      'avg_water_glasses':
          _avg(waters)?.toStringAsFixed(1),
    };
  }

  Future<Map<String, dynamic>> getWeeklySummary() =>
      _weekSummary(0);

  Future<Map<String, dynamic>> getMonthlySummary() async {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final start = end.subtract(const Duration(days: 29));
    final entries = await _entries(start, end);
    if (entries.isEmpty) return {'days_logged': 0};
    final best = [...entries]..sort((a, b) =>
        b.exerciseMinutes.compareTo(a.exerciseMinutes));
    return {
      'days_logged': entries.length,
      'avg_sleep_hours':
          _avg([for (final e in entries) if (e.sleepHours > 0) e.sleepHours])
              ?.toStringAsFixed(2),
      'most_active_day': best.first.date,
      'most_active_minutes': best.first.exerciseMinutes,
    };
  }

  Future<Map<String, dynamic>> getSleepTrend() async {
    final cur = await _weekSummary(0);
    final prev = await _weekSummary(1);
    final a = double.tryParse('${cur['avg_sleep_hours'] ?? ''}');
    final b = double.tryParse('${prev['avg_sleep_hours'] ?? ''}');
    return {
      'this_week_avg_hours': cur['avg_sleep_hours'] ?? 'unavailable',
      'last_week_avg_hours': prev['avg_sleep_hours'] ?? 'unavailable',
      'difference_minutes': (a == null || b == null)
          ? 'unavailable'
          : ((a - b) * 60).round(),
      'days_logged': cur['days_logged'],
    };
  }

  Future<Map<String, dynamic>> getStressTrend() async {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final cur = await _moods(end.subtract(const Duration(days: 6)), end);
    final prev = await _moods(end.subtract(const Duration(days: 13)),
        end.subtract(const Duration(days: 7)));
    double? avg(Map<String, List<int>> m) {
      final vals = <double>[];
      for (final l in m.values) {
        vals.add(l.reduce((a, b) => a + b) / l.length);
      }
      return _avg(vals);
    }

    final n = cur.values.fold(0, (a, b) => a + b.length);
    return {
      'this_week_avg_mood_1to5':
          avg(cur)?.toStringAsFixed(1) ?? 'unavailable',
      'last_week_avg_mood_1to5':
          avg(prev)?.toStringAsFixed(1) ?? 'unavailable',
      'check_ins': n,
    };
  }

  Future<Map<String, dynamic>> getExerciseTrend() async {
    final cur = await _weekSummary(0);
    final prev = await _weekSummary(1);
    return {
      'this_week_total_min': cur['exercise_total_min'] ?? 0,
      'last_week_total_min': prev['exercise_total_min'] ?? 0,
      'days_logged': cur['days_logged'],
    };
  }

  Future<Map<String, dynamic>> getHydrationTrend() async {
    final cur = await _weekSummary(0);
    final prev = await _weekSummary(1);
    return {
      'this_week_avg_glasses': cur['avg_water_glasses'] ?? 'unavailable',
      'last_week_avg_glasses':
          prev['avg_water_glasses'] ?? 'unavailable',
      'days_logged': cur['days_logged'],
    };
  }

  /// Active experiment + completion counts (habit progress signal).
  Future<Map<String, dynamic>> getHabitProgress() async {
    final all = (await _experiments.getAll())
        .fold(onSuccess: (l) => l, onFailure: (_) => const <Experiment>[]);
    Experiment? active;
    for (final e in all) {
      if (e.status == ExperimentStatus.active) active = e;
    }
    return {
      'active_experiment': active?.title ?? 'none',
      'active_check_ins': active?.checkIns.length ?? 0,
      'completed_experiments':
          all.where((e) => e.status == ExperimentStatus.completed).length,
      'total_experiments': all.length,
    };
  }

  Future<Map<String, dynamic>> getExperimentHistory() async {
    final all = (await _experiments.getAll())
        .fold(onSuccess: (l) => l, onFailure: (_) => const <Experiment>[]);
    return {
      'experiments': [
        for (final e in all.take(10))
          '${e.title} (${e.status.name}, ${e.checkIns.length}/${e.durationDays} check-ins)',
      ],
    };
  }

  Future<Map<String, dynamic>> getExperimentResult(
      {int index = 0}) async {
    final all = (await _experiments.getAll())
        .fold(onSuccess: (l) => l, onFailure: (_) => const <Experiment>[]);
    if (all.isEmpty) return {'available': false};
    final exp = all[index.clamp(0, all.length - 1)];
    final now = DateTime.now();
    final start = exp.startDate ?? now;
    final entries = await _entries(
        start.subtract(const Duration(days: 7)), now);
    final results =
        buildResults(exp: exp, entries: entries, now: now);
    return {
      'available': true,
      'title': exp.title,
      'completion_rate':
          (results.completionRate * 100).round(),
      'summary': results.summary,
    };
  }

  Future<Map<String, dynamic>> getWellnessScore() async {
    final today = await getTodaySummary();
    return {
      'wellness_score': today['wellness_score'] ?? 'unavailable',
      'logged': today['logged'],
    };
  }

  Future<Map<String, dynamic>> getWellnessScoreBreakdown() async {
    final now = DateTime.now();
    final key = formatDateForStorage(now);
    final entry = (await _daily.getByDate(key)).fold(
        onSuccess: (e) => e, onFailure: (_) => null);
    if (entry == null) {
      return {'logged': false};
    }
    final c = WellnessScoreCalculator.componentsOf(entry);
    return {
      'logged': true,
      'sleep': c.sleep,
      'movement': c.movement,
      'hydration': c.hydration,
      'mind': c.mind,
      'stress': c.stress,
      'note':
          'Illustrative components of a wellness score — not a clinical measurement.',
    };
  }

  Future<Map<String, dynamic>> getRecentInsights() async {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final entries =
        await _entries(end.subtract(const Duration(days: 6)), end);
    final moods = await _moods(end.subtract(const Duration(days: 6)), end);
    final calm = {
      for (final k in moods.keys)
        k: (moods[k]!.reduce((a, b) => a + b) / moods[k]!.length) /
            5 *
            100,
    };
    final insights =
        InsightEngine.build(last7: entries, calmByDate: calm);
    return {
      'insights': [
        for (final i in insights.take(3)) '${i.title}: ${i.body}',
      ],
    };
  }

  Future<Map<String, dynamic>> getCalendarSummary() async {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final entries =
        await _entries(end.subtract(const Duration(days: 29)), end);
    return {
      'days_logged_last_30': entries.length,
    };
  }

  Future<Map<String, dynamic>> getGoals() async {
    final profile = (await _profile.load()).fold(
        onSuccess: (p) => p, onFailure: (_) => null);
    if (profile == null) return {'set': false};
    return {
      'set': true,
      'sleep_hours': profile.sleepGoal,
      'water_glasses': profile.waterGoal,
      'exercise_min_per_week': profile.exerciseGoalWeek,
      'meditation_min': profile.meditationGoal,
    };
  }
}

/// Deterministic intent router: question → minimal tool set.
/// Keyword scoring only — no model involved in the choice.
class AiIntentRouter {
  static List<String> toolsFor(String question) {
    final q = question.toLowerCase();
    final tools = <String>{};

    final wantsCompare =
        q.contains('compar') || q.contains('vs') || q.contains('versus');
    final wantsWeek = q.contains('week');
    final wantsMonth =
        q.contains('month') || q.contains('30 days');
    final wantsToday = q.contains('today') || q.contains('my day');

    if (q.contains('sleep')) {
      tools.add(wantsMonth ? 'monthly' : 'sleepTrend');
      if (wantsToday) tools.add('today');
    }
    if (q.contains('stress') ||
        q.contains('mood') ||
        q.contains('calm') ||
        q.contains('anxious')) {
      tools.add('stressTrend');
    }
    if (q.contains('exercis') ||
        q.contains('walk') ||
        q.contains('movement') ||
        q.contains('active')) {
      tools.add('exerciseTrend');
    }
    if (q.contains('water') ||
        q.contains('hydrat') ||
        q.contains('drink')) {
      tools.add('hydrationTrend');
    }
    if (q.contains('experiment')) {
      tools.add('experimentHistory');
      if (q.contains('result') ||
          q.contains('going') ||
          q.contains('review')) {
        tools.add('experimentResult');
      }
    }
    if (q.contains('habit') || q.contains('streak')) {
      tools.add('habitProgress');
    }
    if (q.contains('score')) {
      tools.add('wellnessScore');
      if (q.contains('explain') ||
          q.contains('breakdown') ||
          q.contains('why')) {
        tools.add('wellnessScoreBreakdown');
      }
    }
    if (q.contains('pattern') ||
        q.contains('insight') ||
        q.contains('trend') ||
        q.contains('find')) {
      tools.add('recentInsights');
    }
    if (q.contains('best day') ||
        q.contains('calendar') ||
        q.contains('month')) {
      tools.addAll(['monthly', 'calendar']);
    }
    if (wantsWeek || wantsCompare || q.contains('change')) {
      tools.addAll(['weekly', 'sleepTrend', 'stressTrend']);
    }
    if (wantsToday || tools.isEmpty) {
      tools.add('today');
    }
    if (q.contains('goal')) tools.add('goals');
    return tools.take(4).toList();
  }
}
