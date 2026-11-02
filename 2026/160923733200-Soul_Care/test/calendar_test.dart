import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/checkins.dart';
import 'package:soul_care/data/models/enums.dart';
import 'package:soul_care/data/models/journal.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/repositories/checkin_repository.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/data/repositories/experiment_repository.dart';
import 'package:soul_care/data/repositories/journal_repository.dart';
import 'package:soul_care/features/calendar/calendar_engine.dart';
import 'package:soul_care/features/calendar/calendar_provider.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_cal');
  Hive.init(dir.path);
  await Future.wait([
    Hive.openBox(LocalDatabase.dailyBoxName),
    Hive.openBox(LocalDatabase.stressBoxName),
    Hive.openBox(LocalDatabase.morningBoxName),
    Hive.openBox(LocalDatabase.eveningBoxName),
    Hive.openBox(LocalDatabase.experimentsBoxName),
    Hive.openBox(LocalDatabase.journalBoxName),
    Hive.openBox(LocalDatabase.documentsBoxName),
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

Map<String, DailyHealthEntry> _monthEntries(
    int year, int month, List<int> days,
    {double Function(int day)? sleep}) {
  return {
    for (final d in days)
      _key(DateTime(year, month, d)): _day(_key(DateTime(year, month, d)),
          sleep: sleep?.call(d) ?? 7.5),
  };
}

void main() {
  group('engine — day states', () {
    test('thresholds and no-data rule', () {
      expect(stateForScore(95, true), DayState.excellent);
      expect(stateForScore(80, true), DayState.excellent);
      expect(stateForScore(79, true), DayState.good);
      expect(stateForScore(60, true), DayState.good);
      expect(stateForScore(59, true), DayState.mixed);
      expect(stateForScore(40, true), DayState.mixed);
      expect(stateForScore(39, true), DayState.difficult);
      // No data is never a bad day.
      expect(stateForScore(10, false), DayState.insufficient);
      expect(stateForScore(null, false), DayState.insufficient);
      expect(DayState.insufficient.label, 'No data');
    });

    test('every state has an accessible description', () {
      for (final s in DayState.values) {
        expect(s.label.isNotEmpty, isTrue);
        expect(s.description.isNotEmpty, isTrue);
      }
    });
  });

  group('engine — month grid', () {
    test('empty month yields 42 No-data cells', () {
      final grid = buildMonthGrid(
        year: 2026,
        month: 9,
        dailyByDate: {},
        calmByDate: {},
        moodSourcesByDate: {},
        morningByDate: {},
        eveningByDate: {},
        experiments: [],
        journalCountByDate: {},
        documentCountByDate: {},
      );
      expect(grid.length, 42);
      expect(grid.every((d) => d.state == DayState.insufficient), isTrue);
      expect(grid.where((d) => d.inMonth).length, 30);
    });

    test('partial month assigns states, gaps stay No data', () {
      final grid = buildMonthGrid(
        year: 2026,
        month: 9,
        dailyByDate: _monthEntries(2026, 9, [3, 10, 17]),
        calmByDate: {},
        moodSourcesByDate: {},
        morningByDate: {},
        eveningByDate: {},
        experiments: [],
        journalCountByDate: {},
        documentCountByDate: {},
      );
      final logged =
          grid.where((d) => d.inMonth && d.hasData).toList();
      expect(logged.length, 3);
      expect(logged.every((d) => d.wellness != null), isTrue);
      final gaps =
          grid.where((d) => d.inMonth && !d.hasData).toList();
      expect(gaps.length, 27);
      expect(gaps.every((d) => d.state == DayState.insufficient), isTrue);
    });

    test('day carries habits, experiments, journal and document flags', () {
      final now = DateTime(2026, 9, 30);
      final exp = Experiment(
        id: 'e',
        templateId: 'daily-walk',
        title: 'Daily Walk',
        description: 'd',
        targetMetric: 'exerciseMinutes',
        durationDays: 7,
        startDate: DateTime(2026, 9, 28),
        endDate: DateTime(2026, 10, 4),
        status: ExperimentStatus.active,
        checkIns: [_key(DateTime(2026, 9, 30))],
        createdAt: now,
        updatedAt: now,
      );
      final grid = buildMonthGrid(
        year: 2026,
        month: 9,
        dailyByDate: _monthEntries(2026, 9, [30]),
        calmByDate: {},
        moodSourcesByDate: {
          _key(DateTime(2026, 9, 30)): [4]
        },
        morningByDate: {},
        eveningByDate: {},
        experiments: [exp],
        journalCountByDate: {_key(DateTime(2026, 9, 30)): 2},
        documentCountByDate: {_key(DateTime(2026, 9, 30)): 1},
      );
      final day = grid.firstWhere(
          (d) => d.key == _key(DateTime(2026, 9, 30)));
      expect(day.habits, contains('Daily Walk ✓'));
      expect(day.experimentStatus, contains('Daily Walk'));
      expect(day.journalCount, 2);
      expect(day.documentCount, 1);
      expect(day.mood, 4.0);
    });
  });

  group('engine — month summary', () {
    test('full month summarizes from real data only', () {
      final dayNums = [for (var d = 1; d <= 28; d++) d];
      final days = [for (final d in dayNums) _key(DateTime(2026, 9, d))];
      final grid = buildMonthGrid(
        year: 2026,
        month: 9,
        dailyByDate: _monthEntries(2026, 9, dayNums,
            sleep: (d) => 6.0 + (d % 4)),
        calmByDate: {},
        moodSourcesByDate: {},
        morningByDate: {},
        eveningByDate: {},
        experiments: [],
        journalCountByDate: {for (final k in days.take(5)) k: 1},
        documentCountByDate: {},
      );
      final s = summarizeMonth(
          year: 2026, month: 9, days: grid, experiments: []);
      expect(s.daysLogged, 28);
      expect(s.daysInMonth, 30);
      expect(s.avgWellness, isNotNull);
      expect(s.bestDay, isNotNull);
      expect(s.bestScore, isNotNull);
      expect(s.mostConsistentMetric, isNotNull);
      expect(s.journalCount, 5);
    });

    test('empty month reports needs-more-days, never zeros', () {
      final grid = buildMonthGrid(
        year: 2026,
        month: 9,
        dailyByDate: {},
        calmByDate: {},
        moodSourcesByDate: {},
        morningByDate: {},
        eveningByDate: {},
        experiments: [],
        journalCountByDate: {},
        documentCountByDate: {},
      );
      final s = summarizeMonth(
          year: 2026, month: 9, days: grid, experiments: []);
      expect(s.daysLogged, 0);
      expect(s.avgWellness, isNull);
      expect(s.bestDay, isNull);
      expect(s.mostConsistentMetric, isNull);
      expect(s.biggestImprovement, isNull);
    });
  });

  group('engine — navigation and heatmap', () {
    test('month/year rollover', () {
      final jan = nextMonth(2025, 12);
      expect([jan.year, jan.month], [2026, 1]);
      final dec = prevMonth(2026, 1);
      expect([dec.year, dec.month], [2025, 12]);
      expect(nextYear(2025, 6).year, 2026);
      expect(prevYear(2026, 6).year, 2025);
      expect(nextMonth(2026, 9).month, 10);
    });

    test('consistency levels reward fuller logging', () {
      expect(
          consistencyLevel(
              hasEntry: false,
              hasMorning: false,
              hasEvening: false,
              hasStress: false),
          0);
      expect(
          consistencyLevel(
              hasEntry: true,
              hasMorning: false,
              hasEvening: false,
              hasStress: false),
          2);
      expect(
          consistencyLevel(
              hasEntry: true,
              hasMorning: true,
              hasEvening: true,
              hasStress: true),
          4);
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

    test('month loads once and caches; heat is key-based', () async {
      final repo = DailyHealthRepository();
      final now = DateTime.now();
      final today =
          DateTime(now.year, now.month, now.day);
      DateTime at(int ago) =>
          today.subtract(Duration(days: ago));
      // Trailing 20 days (always past, never future).
      for (var i = 0; i < 20; i++) {
        await repo.save(_day(_key(at(i))));
      }
      await MorningRepository().save(MorningCheckIn(
          date: _key(at(5)), updatedAt: DateTime.now()));
      await ExperimentRepository().save(Experiment(
        id: 'e',
        templateId: 'daily-walk',
        title: 'Daily Walk',
        description: 'd',
        targetMetric: 'exerciseMinutes',
        durationDays: 30,
        startDate: at(10),
        status: ExperimentStatus.active,
        createdAt: now,
        updatedAt: now,
      ));
      await const JournalRepository().save(JournalEntry(
        id: 'j',
        date: _key(at(6)),
        body: 'note',
        createdAt: now,
        updatedAt: now,
      ));

      final prov = CalendarProvider();
      final months = {
        for (var i = 0; i < 20; i++)
          '${at(i).year}-${at(i).month}',
      };
      var totalLogged = 0;
      for (final m in months) {
        final parts = m.split('-');
        final y = int.parse(parts[0]);
        final mo = int.parse(parts[1]);
        await prov.ensureMonth(y, mo);
        totalLogged += prov.summary(y, mo)!.daysLogged;
      }
      expect(prov.error, isNull);
      expect(totalLogged, 20);
      // Spot-check one month grid shape.
      final first = prov.month(at(0).year, at(0).month);
      expect(first.length, 42);

      final heat = await prov.ensureHeat(30);
      expect(heat.length, 30);
      // entry (2) + morning (1) = 3 points → level 2.
      expect(heat[_key(at(5))], 2);
      expect(heat[_key(at(0))], 2);
      // Unseeded trailing day → level 0.
      expect(heat[_key(at(25))], 0);
      // Cached: second call returns identical map.
      expect(await prov.ensureHeat(30), same(heat));
    });

    test('large history stays fast and consistent', () async {
      final repo = DailyHealthRepository();
      final now = DateTime.now();
      for (var i = 0; i < 365; i++) {
        final d = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: i));
        await repo.save(_day(_key(d)));
      }
      final prov = CalendarProvider();
      final heat = await prov.ensureHeat(365);
      expect(heat.length, 365);
      expect(heat.values.where((l) => l > 0).length, 365);
    });
  });
}
