import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/enums.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/features/analytics/analytics_engine.dart';
import 'package:soul_care/features/analytics/analytics_provider.dart';
import 'package:soul_care/features/analytics/analytics_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_an');
  Hive.init(dir.path);
  await Future.wait([
    Hive.openBox(LocalDatabase.dailyBoxName),
    Hive.openBox(LocalDatabase.stressBoxName),
    Hive.openBox(LocalDatabase.morningBoxName),
    Hive.openBox(LocalDatabase.eveningBoxName),
    Hive.openBox(LocalDatabase.experimentsBoxName),
  ]);
}

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DailyHealthEntry _day(String key, {double sleep = 7.5, int exercise = 30}) {
  return DailyHealthEntry(
    date: key,
    sleepHours: sleep,
    sleepQuality: SleepQuality.good,
    feltRested: true,
    exerciseMinutes: exercise,
    exerciseIntensity: ExerciseIntensity.moderate,
    mealQuality: MealQuality.good,
    waterGlasses: 8,
    meditationMinutes: 10,
    screenTimeHours: 2,
  );
}

MetricSeries _series(AnalyticsMetric m, List<double> vals) {
  final base = DateTime(2026, 7, 1);
  return MetricSeries(m, [
    for (var i = 0; i < vals.length; i++)
      MetricPoint(
          _key(base.add(Duration(days: i))), vals[i]),
  ]);
}

void main() {
  group('trends — small data', () {
    test('three points yield nulls, never crashes', () {
      final vals = [7.0, 8.0, 6.5];
      expect(movingAverage(vals, 7), [null, null, null]);
      final change = detectChange(vals);
      expect(change.delta, isNull);
      expect(change.points, 0);
      final weeks = weeklyTrend(_series(AnalyticsMetric.sleep, vals).points);
      expect(weeks.length, 1);
      expect(bucketChange(weeks), isNull);
    });

    test('missing values break moving windows without fabrication', () {
      final ma = movingAverage([7.0, null, 8.0, 7.5, 7.0], 2);
      expect(ma[1], isNull); // gap breaks the window
      expect(ma[3], isNotNull);
    });

    test('incomplete weeks still report bucket counts', () {
      final weeks = weeklyTrend(
          _series(AnalyticsMetric.sleep, [7.0]).points);
      expect(weeks.length, 1);
      expect(weeks.first.count, 1);
      expect(weeks.first.average, 7.0);
    });
  });

  group('correlations — gating', () {
    test('fewer than 5 pairs stays unavailable', () {
      expect(
          pearson([1, 2, 3, 4], [2, 3, 4, 5]), isNull);
      final m = {
        AnalyticsMetric.sleep:
            _series(AnalyticsMetric.sleep, [7, 8, 6]),
        AnalyticsMetric.stress:
            _series(AnalyticsMetric.stress, [2, 3, 4]),
      };
      final cells = correlationMatrix(m);
      expect(cells.every((c) => !c.computed), isTrue);
      expect(cells.first.label, 'Not enough paired data');
    });

    test('constant values and zero variance yield null, never NaN', () {
      expect(pearson([3, 3, 3, 3, 3], [1, 2, 3, 4, 5]), isNull);
      expect(pearson([1, 2, 3, 4, 5], [2, 2, 2, 2, 2]), isNull);
    });

    test('clear co-movement computes with honest labels', () {
      final xs = [5.0, 6.0, 7.0, 8.0, 9.0, 10.0];
      final ys = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0];
      final r = pearson(xs, ys)!;
      expect(r, closeTo(1.0, 0.001));
      final m = {
        AnalyticsMetric.sleep: _series(AnalyticsMetric.sleep, xs),
        AnalyticsMetric.energy: _series(AnalyticsMetric.energy, ys),
      };
      final cell = correlationMatrix(m).firstWhere((c) => c.computed);
      expect(cell.pairs, 6);
      expect(cell.startKey.isNotEmpty && cell.endKey.isNotEmpty, isTrue);
      expect(cell.label, contains('Observed correlation'));
      expect(cell.explanation, contains('does not show that one causes'));
    });

    test('matrix language never claims cause', () {
      final m = {
        for (var i = 0; i < AnalyticsMetric.values.length; i++)
          AnalyticsMetric.values[i]: _series(AnalyticsMetric.values[i],
              [for (var j = 0; j < 8; j++) (j + i).toDouble()]),
      };
      for (final c in correlationMatrix(m)) {
        // Denial of causation must always be present; bare causal claims
        // ("X causes Y", "proves", "because of") must never appear.
        expect(c.explanation, contains('does not show'));
        expect(c.label, contains('Observed correlation'));
        final lower = '${c.label} ${c.explanation}'.toLowerCase();
        expect(lower, isNot(contains('proves')));
        expect(lower, isNot(contains('because of')));
      }
    });
  });

  group('anomalies', () {
    test('too few points or zero spread flag nothing', () {
      expect(
          detectAnomalies(
              _series(AnalyticsMetric.sleep, [7, 8, 7, 8])),
          isEmpty);
      expect(
          detectAnomalies(
              _series(AnalyticsMetric.sleep, [7, 7, 7, 7, 7, 7, 7, 7])),
          isEmpty);
    });

    test('extreme day is flagged with metric and deviation', () {
      final vals = [7.5, 7.6, 7.4, 7.5, 7.6, 7.5, 7.4, 7.5, 7.6, 2.0];
      final found = detectAnomalies(
          _series(AnalyticsMetric.sleep, vals));
      expect(found.length, 1);
      expect(found.first.value, 2.0);
      expect(found.first.metric, AnalyticsMetric.sleep);
      expect(found.first.typical, closeTo(7.5, 0.1));
      expect(found.first.description, contains('unusual day'));
    });
  });

  group('experiment analysis', () {
    test('baseline vs experiment reports mean/median/diff/completion', () {
      final now = DateTime(2026, 9, 30);
      String k(int ago) => _key(DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: ago)));
      final entries = [
        for (var i = 13; i >= 7; i--) _day(k(i), sleep: 5.0),
        for (var i = 6; i >= 0; i--) _day(k(i), sleep: 8.0),
      ];
      final exp = Experiment(
        id: 'e',
        templateId: 'earlier-sleep',
        title: 'Sleep',
        description: 'd',
        targetMetric: 'sleepHours',
        durationDays: 7,
        startDate: DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 6)),
        status: ExperimentStatus.completed,
        checkIns: [for (var i = 6; i >= 2; i--) k(i)],
        createdAt: now,
        updatedAt: now,
      );
      final a =
          analyzeExperiment(exp: exp, entries: entries, now: now);
      expect(a.baselineMean, 5.0);
      expect(a.baselineN, greaterThan(0));
      expect(a.experimentMean, 8.0);
      expect(a.experimentMedian, 8.0);
      expect(a.difference, closeTo(3.0, 0.001));
      expect(a.completionRate, closeTo(5 / 7, 0.001));
      expect(a.summary, contains('observed difference'));
    });

    test('no baseline stays unavailable, honestly', () {
      final now = DateTime(2026, 9, 30);
      final exp = Experiment(
        id: 'e',
        templateId: 'daily-walk',
        title: 'Walk',
        description: 'd',
        targetMetric: 'exerciseMinutes',
        durationDays: 7,
        startDate: DateTime(now.year, now.month, now.day),
        status: ExperimentStatus.active,
        createdAt: now,
        updatedAt: now,
      );
      final a = analyzeExperiment(exp: exp, entries: [], now: now);
      expect(a.baselineMean, isNull);
      expect(a.experimentMean, isNull);
      expect(a.difference, isNull);
      expect(a.summary, contains('No before/during'));
    });
  });

  group('robustness — never NaN or infinity', () {
    test('large dataset completes with finite outputs', () {
      // Deterministic 365-day pattern (no randomness).
      final sleep = [
        for (var i = 0; i < 365; i++) 6.5 + ((i * 37) % 20) / 10,
      ];
      final exercise = [
        for (var i = 0; i < 365; i++) ((i * 53) % 60).toDouble(),
      ];
      final m = {
        AnalyticsMetric.sleep: _series(AnalyticsMetric.sleep, sleep),
        AnalyticsMetric.exercise:
            _series(AnalyticsMetric.exercise, exercise),
      };
      final cells = correlationMatrix(m);
      // All 21 pairs are represented; only the 1 with data computes.
      expect(cells.length, 21);
      expect(cells.where((c) => c.computed).length, 1);
      final weeks =
          weeklyTrend(_series(AnalyticsMetric.sleep, sleep).points);
      expect(weeks.length, greaterThan(50));
      final months =
          monthlyTrend(_series(AnalyticsMetric.sleep, sleep).points);
      expect(months.length, 12);
      expect(bucketChange(weeks)!.isFinite, isTrue);
      final change = detectChange(sleep);
      expect(change.delta == null || change.delta!.isFinite, isTrue);
      final ma = movingAverage(sleep, 7);
      for (final v in ma) {
        expect(v == null || v.isFinite, isTrue);
      }
    });

    test('NaN and infinite inputs produce nulls/empties, and JSON encodes',
        () {
      // Non-finite points are filtered; too few survivors → unavailable.
      final nasty = [1.0, double.nan, double.infinity, 2.0];
      expect(pearson(nasty, [1, 2, 3, 4]), isNull);
      // Enough finite survivors still compute a finite r.
      final filtered =
          pearson([1.0, double.nan, double.infinity, 2.0, 3.0, 4.0, 5.0],
              [1, 2, 3, 4, 5, 6, 7]);
      expect(filtered == null || filtered.isFinite, isTrue);
      expect(
          detectAnomalies(_series(AnalyticsMetric.sleep, nasty)), isEmpty);
      final change = detectChange(nasty);
      expect(change.delta == null || change.delta!.isFinite, isTrue);
      // The export payload must always serialize (JSON rejects NaN/Inf).
      final payload = analyticsReportJson(
        generatedAt: DateTime(2026, 9, 30),
        windowDays: 90,
        completenessList: const [],
        matrix: correlationMatrix({
          AnalyticsMetric.sleep: _series(AnalyticsMetric.sleep, nasty),
          AnalyticsMetric.water:
              _series(AnalyticsMetric.water, [8, 8, 8, 8, 8, 8, 8]),
        }),
        anomalies: const [],
        experiments: const [],
      );
      expect(() => jsonEncode(payload), returnsNormally);
      expect(
          payload['disclaimer'].toString(), contains('never imply causation'));
    });

    test('completeness counts distinct logged dates', () {
      final base = DateTime(2026, 9, 1);
      final points = [
        for (var i = 0; i < 3; i++)
          MetricPoint(_key(base.add(Duration(days: i * 2))), 7.0),
      ];
      final c = completeness(
        series: MetricSeries(AnalyticsMetric.sleep, points),
        start: base,
        end: base.add(const Duration(days: 29)),
      );
      expect(c.label, '3 / 30 days');
      expect(c.fraction, closeTo(0.1, 0.001));
    });
  });

  group('education', () {
    test('all three explainers exist', () {
      expect(analyticsEducation.keys, containsAll([
        'What does correlation mean?',
        'What does sample size mean?',
        'What does an anomaly mean?',
      ]));
      for (final v in analyticsEducation.values) {
        expect(v.isNotEmpty, isTrue);
      }
    });
  });

  group('provider + screen', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await _initTestHive();
    });

    tearDown(() async {
      await LocalDatabase.clearAll();
    });

    test('thirty seeded days build series, matrix and completeness',
        () async {
      final repo = DailyHealthRepository();
      final now = DateTime.now();
      for (var i = 0; i < 30; i++) {
        final d = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: 29 - i));
        await repo.save(_day(_key(d),
            sleep: 6.0 + (i % 5), exercise: (i * 7) % 45));
      }
      final prov = AnalyticsProvider();
      await prov.load();
      expect(prov.error, isNull);
      expect(prov.loaded, isTrue);
      expect(prov.series[AnalyticsMetric.sleep]!.points.length, 30);
      expect(
          prov.matrix.where((c) => c.computed), isNotEmpty);
      final sleep =
          prov.completenessList().firstWhere((c) => c.metric == AnalyticsMetric.sleep);
      expect(sleep.logged, 30);
      expect(sleep.total, AnalyticsProvider.completenessDays);
      for (final a in prov.anomalies) {
        expect(a.deviation.isFinite, isTrue);
      }
    });

    testWidgets('lab renders with empty history, honestly', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AnalyticsScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AnalyticsScreen), findsOneWidget);
      expect(find.text('Data completeness'), findsOneWidget);
    });

    testWidgets('lab renders in dark mode', (tester) async {
      await tester.pumpWidget(MaterialApp(
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark(useMaterial3: true),
        theme: ThemeData.light(useMaterial3: true),
        home: const AnalyticsScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AnalyticsScreen), findsOneWidget);
    });
  });
}
