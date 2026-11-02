import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/utils.dart';
import '../../core/wellness/wellness_score.dart';
import '../../data/models/checkins.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../data/repositories/checkin_repository.dart';
import '../../data/repositories/daily_health_repository.dart';
import '../../data/repositories/experiment_repository.dart';
import '../../data/repositories/stress_repository.dart';
import 'analytics_engine.dart';

/// Analytics Lab state. All computation is local; loading is read-only.
/// Analysis window: trailing 90 days. Completeness is reported over the
/// trailing 30 days (the "28 / 30 days" style guard against misleading
/// analytics).
class AnalyticsProvider extends ChangeNotifier {
  final DailyHealthRepository _dailyRepo;
  final StressRepository _stressRepo;
  final MorningRepository _morningRepo;
  final EveningRepository _eveningRepo;
  final ExperimentRepository _expRepo;

  AnalyticsProvider({
    DailyHealthRepository? dailyRepo,
    StressRepository? stressRepo,
    MorningRepository? morningRepo,
    EveningRepository? eveningRepo,
    ExperimentRepository? experimentRepo,
  })  : _dailyRepo = dailyRepo ?? DailyHealthRepository(),
        _stressRepo = stressRepo ?? StressRepository(),
        _morningRepo = morningRepo ?? MorningRepository(),
        _eveningRepo = eveningRepo ?? EveningRepository(),
        _expRepo = experimentRepo ?? ExperimentRepository();

  static const int windowDays = 90;
  static const int completenessDays = 30;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  bool _loaded = false;
  bool get loaded => _loaded;

  Map<AnalyticsMetric, MetricSeries> _series = const {};
  Map<AnalyticsMetric, MetricSeries> get series => _series;

  List<CorrelationCell> _matrix = const [];
  List<CorrelationCell> get matrix => _matrix;

  List<Anomaly> _anomalies = const [];
  List<Anomaly> get anomalies => _anomalies;

  List<Experiment> _experiments = const [];
  List<Experiment> get experiments => _experiments;

  List<DailyHealthEntry> _entries = const [];

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final from = today.subtract(const Duration(days: windowDays - 1));

      final entries = (await _dailyRepo.getRange(from, today)).fold(
        onSuccess: (l) => l,
        onFailure: (_) => const <DailyHealthEntry>[],
      );
      _entries = entries;
      final dailyKeys = entries.map((e) => e.date).toSet();

      final moods = <String, List<int>>{};
      (await _stressRepo.getRange(from, today)).fold(
        onSuccess: (checks) {
          for (final c in checks) {
            moods.putIfAbsent(c.date, () => []).add(c.mood.score);
          }
        },
        onFailure: (_) {},
      );

      final morning = <String, MorningCheckIn>{};
      final evening = <String, EveningReflection>{};
      for (var i = 0; i < windowDays; i++) {
        final d = today.subtract(Duration(days: i));
        final key = formatDateForStorage(d);
        final m = await _morningRepo.getByDate(key);
        m.fold(
          onSuccess: (v) {
            if (v != null) morning[key] = v;
          },
          onFailure: (_) {},
        );
        final e = await _eveningRepo.getByDate(key);
        e.fold(
          onSuccess: (v) {
            if (v != null) evening[key] = v;
          },
          onFailure: (_) {},
        );
      }

      _series = _buildSeries(entries, moods, morning, evening, dailyKeys);
      _matrix = correlationMatrix(_series);
      _anomalies = [
        for (final m in AnalyticsMetric.values)
          ...detectAnomalies(_series[m] ?? MetricSeries(m, const [])),
      ]..sort((a, b) => b.deviation.compareTo(a.deviation));

      _experiments = (await _expRepo.getAll()).fold(
        onSuccess: (l) => l,
        onFailure: (_) => const <Experiment>[],
      );
      _loaded = true;
    } catch (_) {
      _error = 'Could not build analytics right now. Please try again.';
    }
    _loading = false;
    notifyListeners();
  }

  Map<AnalyticsMetric, MetricSeries> _buildSeries(
    List<DailyHealthEntry> entries,
    Map<String, List<int>> moods,
    Map<String, MorningCheckIn> morning,
    Map<String, EveningReflection> evening,
    Set<String> dailyKeys,
  ) {
    final wellness = <MetricPoint>[];
    final sleep = <MetricPoint>[];
    final stress = <MetricPoint>[];
    final energy = <MetricPoint>[];
    final exercise = <MetricPoint>[];
    final screen = <MetricPoint>[];
    final water = <MetricPoint>[];

    final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));
    for (final e in sorted) {
      final d = DateTime.tryParse(e.date);
      if (d == null) continue;
      var in7 = 0;
      for (var i = 0; i < 7; i++) {
        if (dailyKeys.contains(formatDateForStorage(
            d.subtract(Duration(days: i))))) {
          in7++;
        }
      }
      final ms = moods[e.date];
      final calm = (ms == null || ms.isEmpty)
          ? null
          : (ms.reduce((a, b) => a + b) / ms.length / 5 * 100).round();
      wellness.add(MetricPoint(
          e.date,
          WellnessScoreCalculator.scoreForDay(e,
                  calmScore: calm, daysLoggedLast7: in7)
              .toDouble()));
      if (e.sleepHours > 0 && e.sleepHours.isFinite) {
        sleep.add(MetricPoint(e.date, e.sleepHours));
      }
      exercise.add(MetricPoint(e.date, e.exerciseMinutes.toDouble()));
      if (e.screenTimeHours.isFinite) {
        screen.add(MetricPoint(e.date, e.screenTimeHours));
      }
      water.add(MetricPoint(e.date, e.waterGlasses.toDouble()));
    }

    final allKeys = <String>{
      ...dailyKeys,
      ...morning.keys,
      ...evening.keys,
      ...moods.keys,
    };
    for (final k in allKeys) {
      final ms = moods[k];
      if (ms != null && ms.isNotEmpty) {
        final avg = ms.reduce((a, b) => a + b) / ms.length;
        if (avg.isFinite) {
          stress.add(MetricPoint(k, (6 - avg)));
        }
      } else {
        final v = evening[k];
        if (v != null) stress.add(MetricPoint(k, v.stress.toDouble()));
      }
      final parts = <int>[
        if (morning[k] != null) morning[k]!.energy,
        if (evening[k] != null) evening[k]!.energy,
      ];
      if (parts.isNotEmpty) {
        energy.add(MetricPoint(
            k, parts.reduce((a, b) => a + b) / parts.length));
      }
    }

    MetricSeries s(AnalyticsMetric m, List<MetricPoint> p) {
      final sortedPts = [...p]..sort((a, b) => a.dateKey.compareTo(b.dateKey));
      return MetricSeries(m, sortedPts);
    }

    return {
      AnalyticsMetric.wellness: s(AnalyticsMetric.wellness, wellness),
      AnalyticsMetric.sleep: s(AnalyticsMetric.sleep, sleep),
      AnalyticsMetric.stress: s(AnalyticsMetric.stress, stress),
      AnalyticsMetric.energy: s(AnalyticsMetric.energy, energy),
      AnalyticsMetric.exercise: s(AnalyticsMetric.exercise, exercise),
      AnalyticsMetric.screen: s(AnalyticsMetric.screen, screen),
      AnalyticsMetric.water: s(AnalyticsMetric.water, water),
    };
  }

  List<Completeness> completenessList() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(
        const Duration(days: completenessDays - 1));
    return [
      for (final m in AnalyticsMetric.values)
        completeness(
          series: _series[m] ?? MetricSeries(m, const []),
          start: start,
          end: today,
        ),
    ];
  }

  ExperimentAnalysis? analysisFor(Experiment exp) {
    if (!_loaded) return null;
    return analyzeExperiment(
        exp: exp, entries: _entries, now: DateTime.now());
  }

  /// Writes the analytics report to a temp JSON file and shares it.
  /// Returns the file path, or null on failure.
  Future<String?> shareReport() async {
    try {
      final now = DateTime.now();
      final payload = analyticsReportJson(
        generatedAt: now,
        windowDays: windowDays,
        completenessList: completenessList(),
        matrix: _matrix,
        anomalies: _anomalies,
        experiments: [
          for (final e in _experiments)
            analyzeExperiment(
                exp: e, entries: _entries, now: now),
        ],
      );
      final stamp = now
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File(
          '${Directory.systemTemp.path}/soulcare-analytics-$stamp.json');
      await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(payload));
      await SharePlus.instance.share(ShareParams(
        text: 'My SoulCare analytics report',
        files: [XFile(file.path, mimeType: 'application/json')],
      ));
      return file.path;
    } catch (_) {
      return null;
    }
  }
}
