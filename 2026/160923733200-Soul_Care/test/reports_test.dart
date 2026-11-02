import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/enums.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/features/reports/report_engine.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_reports');
  Hive.init(dir.path);
  await Future.wait([
    Hive.openBox(LocalDatabase.dailyBoxName),
    Hive.openBox(LocalDatabase.stressBoxName),
    Hive.openBox(LocalDatabase.experimentsBoxName),
    Hive.openBox(LocalDatabase.documentsBoxName),
    Hive.openBox(LocalDatabase.settingsBoxName),
    Hive.openBox(LocalDatabase.gameStatsBoxName),
    Hive.openBox(LocalDatabase.morningBoxName),
    Hive.openBox(LocalDatabase.eveningBoxName),
    Hive.openBox(LocalDatabase.journalBoxName),
  ]);
}

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<void> _seedDay(DateTime day,
    {double sleep = 0,
    int exercise = 0,
    int water = 0,
    int meditation = 0,
    double screen = 0}) async {
  await DailyHealthRepository().save(DailyHealthEntry(
    date: _key(day),
    sleepHours: sleep,
    sleepQuality: SleepQuality.good,
    exerciseMinutes: exercise,
    waterGlasses: water,
    meditationMinutes: meditation,
    screenTimeHours: screen,
  ));
}

Future<List<DailyHealthEntry>> _all() async {
  final now = DateTime.now();
  return (await DailyHealthRepository().getRange(
          now.subtract(const Duration(days: 60)), now))
      .value!;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await _initTestHive();
  });

  tearDown(() async {
    await LocalDatabase.clearAll();
  });

  group('weekly report', () {
    test('one day is insufficient, never faked', () async {
      final now = DateTime.now();
      await _seedDay(now, sleep: 7.5, water: 6);
      final w = buildWeekly(
          entries: await _all(), calmByDate: const {}, end: now);
      expect(w.sufficient, isFalse);
      expect(w.daysLogged, 1);
      expect(w.avgWellness, isNull);
    });

    test('seven full days produce every section', () async {
      final now = DateTime.now();
      for (var i = 0; i < 7; i++) {
        await _seedDay(now.subtract(Duration(days: i)),
            sleep: 7 + (i % 2),
            exercise: 30,
            water: 6 + (i % 3),
            meditation: 10,
            screen: 2);
      }
      final calm = {
        for (var i = 0; i < 7; i++)
          _key(now.subtract(Duration(days: i))): 70.0
      };
      final w = buildWeekly(
          entries: await _all(), calmByDate: calm, end: now);
      expect(w.sufficient, isTrue);
      expect(w.daysLogged, 7);
      expect(w.avgWellness, isNotNull);
      expect(w.sleepAvg, closeTo(7.43, 0.01));
      expect(w.sleepConsistency, closeTo(1.0, 0.01));
      expect(w.bestSleepDay, isNotNull);
      expect(w.lowSleepDay, isNotNull);
      expect(w.exerciseTotal, 210);
      expect(w.activeDays, 7);
      expect(w.waterAvg, closeTo(7.0, 0.01));
      expect(w.moodAvg, closeTo(3.5, 0.01));
      expect(w.meditationTotal, 70);
      expect(w.screenAvg, 2.0);
    });

    test('incomplete week + missing metrics yield honest nulls', () async {
      final now = DateTime.now();
      await _seedDay(now, sleep: 8, exercise: 0, water: 0);
      await _seedDay(now.subtract(const Duration(days: 2)),
          sleep: 6, water: 4);
      final w = buildWeekly(
          entries: await _all(), calmByDate: const {}, end: now);
      expect(w.sufficient, isTrue);
      expect(w.daysLogged, 2);
      expect(w.moodAvg, isNull);
      expect(w.bestMoodDay, isNull);
      expect(w.exerciseTotal, 0);
      expect(w.activeDays, 0);
      expect(w.waterAvg, closeTo(4.0, 0.01));
    });
  });

  group('comparison', () {
    test('deltas compute only with sufficient sides', () async {
      final now = DateTime.now();
      for (var i = 0; i < 7; i++) {
        await _seedDay(now.subtract(Duration(days: i)), sleep: 7.1);
      }
      for (var i = 7; i < 14; i++) {
        await _seedDay(now.subtract(Duration(days: i)), sleep: 6.7);
      }
      final entries = await _all();
      final cur = buildWeekly(entries: entries, calmByDate: const {}, end: now);
      final prevStart =
          DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7));
      final prev = buildWeekly(
          entries: entries, calmByDate: const {}, end: prevStart.subtract(const Duration(days: 1)));
      final deltas = compareWeeks(cur, prev);
      final sleep = deltas.firstWhere((d) => d.label == 'Sleep');
      expect(sleep.current, '7.1h');
      expect(sleep.previous, '6.7h');
      expect(sleep.change, '+0.4h');

      final summary = summarizeWeeks(cur, prev);
      expect(summary, contains('24 minutes'));
      final lower = summary.toLowerCase();
      expect(lower, isNot(contains('diagnos')));
      expect(lower, isNot(contains('prove')));
    });

    test('thin previous week skips comparison honestly', () async {
      final now = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await _seedDay(now.subtract(Duration(days: i)), sleep: 7.0);
      }
      final entries = await _all();
      final cur = buildWeekly(entries: entries, calmByDate: const {}, end: now);
      final prev = buildWeekly(
          entries: const [], calmByDate: const {},
          end: now.subtract(const Duration(days: 7)));
      expect(compareWeeks(cur, prev), isEmpty);
      expect(summarizeWeeks(cur, prev), contains('Logged 3 of 7 days'));
    });
  });

  group('monthly report', () {
    test('full month aggregates counts + trends', () async {
      final now = DateTime.now();
      for (var i = 0; i < 20; i++) {
        await _seedDay(now.subtract(Duration(days: i)),
            sleep: i < 10 ? 8.0 : 6.5,
            water: 8,
            exercise: 20,
            meditation: 5);
      }
      final m = buildMonthly(
        entries: await _all(),
        calmByDate: const {},
        experiments: [
          Experiment(
            id: 'e1',
            title: 't',
            description: 'd',
            targetMetric: 'm',
            durationDays: 7,
            status: ExperimentStatus.completed,
            checkIns: const ['2026-09-01', '2026-09-02'],
            createdAt: now,
            updatedAt: now,
          ),
        ],
        journalCount: 5,
        documentsAdded: 2,
        end: now,
      );
      expect(m.daysLogged, 20);
      expect(m.sleepGoalPct, closeTo(0.5, 0.01));
      expect(m.waterGoalPct, 1.0);
      expect(m.experimentsCompleted, 1);
      expect(m.habitCheckIns, 2);
      expect(m.journalCount, 5);
      expect(m.documentsAdded, 2);
      expect(m.wellnessTrend, isNotNull);
      expect(m.avgWellness, isNotNull);
    });
  });

  group('export payload', () {
    test('structured, JSON-encodable, no binaries', () async {
      final now = DateTime.now();
      await _seedDay(now, sleep: 7.5, water: 6);
      final entries = await _all();
      final cur =
          buildWeekly(entries: entries, calmByDate: const {}, end: now);
      final payload = {
        'app': 'SoulCare',
        'type': 'wellness-report',
        'weekStart': cur.weekStart.toIso8601String(),
        'daysLogged': cur.daysLogged,
        'avgWellness': cur.avgWellness,
        'sleepAvg': cur.sleepAvg,
        'exerciseTotal': cur.exerciseTotal,
        'summary': summarizeWeeks(
            cur,
            buildWeekly(
                entries: const [],
                calmByDate: const {},
                end: now.subtract(const Duration(days: 7)))),
      };
      final encoded = jsonEncode(payload);
      expect(encoded.contains('SoulCare'), isTrue);
      expect(RegExp(r'base64|%PDF').hasMatch(encoded), isFalse);
    });
  });
}
