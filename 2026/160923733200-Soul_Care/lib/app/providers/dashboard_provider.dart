import 'package:flutter/material.dart';

import '../../core/wellness/insights.dart';
import '../../core/wellness/wellness_score.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../data/repositories/daily_health_repository.dart';
import '../../data/repositories/stress_repository.dart';

/// One plotted day in the 7-day window.
class DayPoint {
  final DateTime date;
  final String key;
  final DailyHealthEntry? entry;
  final int? wellness;
  final double? sleepHours;
  final int? exerciseMinutes;
  final double? calm;

  const DayPoint({
    required this.date,
    required this.key,
    this.entry,
    this.wellness,
    this.sleepHours,
    this.exerciseMinutes,
    this.calm,
  });

  bool get hasData => entry != null;
}

/// Dashboard state: recent trend, weekly scores, insights — all derived
/// from logged data. Missing days are left blank (never fabricated).
class DashboardProvider extends ChangeNotifier {
  final DailyHealthRepository _repo;
  final StressRepository? _stressRepo;

  List<DailyHealthEntry> _recent = [];
  Map<String, double> _calmByDate = {};
  List<DayPoint> _week = const [];
  List<Insight> _insights = const [];
  WellnessScore? _todayScore;
  bool _loading = false;
  String? _error;

  DashboardProvider(this._repo, {StressRepository? stressRepo})
      : _stressRepo = stressRepo;

  List<DailyHealthEntry> get recent => List.unmodifiable(_recent);
  List<DayPoint> get week => List.unmodifiable(_week);
  List<Insight> get insights => List.unmodifiable(_insights);
  WellnessScore? get todayScore => _todayScore;
  bool get loading => _loading;
  String? get error => _error;

  Insight? get topInsight => _insights.isEmpty ? null : _insights.first;

  int get daysLogged => _recent.length;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = today.subtract(const Duration(days: 6));

    final res = await _repo.getRange(from, now);
    var entries = <DailyHealthEntry>[];
    res.fold(
      onSuccess: (list) => entries = list,
      onFailure: (e) => _error = e.message,
    );
    _recent = entries;

    // Stress calm per date.
    _calmByDate = {};
    final stressRepo = _stressRepo;
    if (stressRepo != null) {
      final sres = await stressRepo.getRange(from, now);
      sres.fold(
        onSuccess: (checks) {
          final byDate = <String, List<int>>{};
          for (final c in checks) {
            byDate.putIfAbsent(c.date, () => []).add(c.mood.score);
          }
          _calmByDate = {
            for (final k in byDate.keys)
              k: ((byDate[k]!.reduce((a, b) => a + b) / byDate[k]!.length) /
                      5 *
                      100)
                  .clamp(0, 100),
          };
        },
        onFailure: (_) {},
      );
    }

    final byKey = {for (final e in entries) e.date: e};
    final week = <DayPoint>[];
    for (var i = 0; i < 7; i++) {
      final d = from.add(Duration(days: i));
      final key =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final entry = byKey[key];
      final calm = _calmByDate[key];
      week.add(DayPoint(
        date: d,
        key: key,
        entry: entry,
        wellness: entry == null
            ? null
            : WellnessScoreCalculator.scoreForDay(
                entry,
                calmScore: calm?.round(),
                daysLoggedLast7: entries.length,
              ),
        sleepHours: entry?.sleepHours,
        exerciseMinutes: entry?.exerciseMinutes,
        calm: calm,
      ));
    }
    _week = week;

    _insights = InsightEngine.build(last7: entries, calmByDate: _calmByDate);

    // Today's score with yesterday comparison.
    if (entries.isNotEmpty) {
      final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));
      final todayEntry = sorted.last;
      final prev = sorted.length > 1 ? sorted[sorted.length - 2] : null;
      _todayScore = WellnessScoreCalculator.calculate(
        entry: todayEntry,
        previousEntry: prev,
        daysLoggedLast7: entries.length,
        calmScore: _calmByDate[todayEntry.date]?.round(),
        previousCalmScore:
            prev == null ? null : _calmByDate[prev.date]?.round(),
      );
    } else {
      _todayScore = null;
    }

    _loading = false;
    notifyListeners();
  }
}
