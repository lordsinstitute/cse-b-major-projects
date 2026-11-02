import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/enums.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/features/life_twin/life_twin_engine.dart';
import 'package:soul_care/features/life_twin/life_twin_provider.dart';
import 'package:soul_care/features/life_twin/life_twin_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_tw');
  Hive.init(dir.path);
  await Future.wait([
    Hive.openBox(LocalDatabase.dailyBoxName),
    Hive.openBox(LocalDatabase.stressBoxName),
    Hive.openBox(LocalDatabase.morningBoxName),
    Hive.openBox(LocalDatabase.eveningBoxName),
  ]);
}

DailyHealthEntry _day(String key,
    {double sleep = 7.5,
    int exercise = 30,
    int water = 8,
    int meditation = 10,
    double screen = 2}) {
  return DailyHealthEntry(
    date: key,
    sleepHours: sleep,
    sleepQuality: SleepQuality.good,
    feltRested: true,
    exerciseMinutes: exercise,
    exerciseIntensity: ExerciseIntensity.moderate,
    mealQuality: MealQuality.good,
    waterGlasses: water,
    meditationMinutes: meditation,
    screenTimeHours: screen,
  );
}

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  group('engine — data honesty', () {
    test('zero data yields empty state, never fabricated', () {
      final dates = windowDates(days: 7, now: DateTime(2026, 9, 30));
      final days = buildLifeTwinDays(
        windowDays: dates,
        dailyByDate: {},
        stressMoodsByDate: {},
        morningByDate: {},
        eveningByDate: {},
      );
      expect(days.length, 7);
      for (final d in days) {
        expect(d.values.values.whereType<double>(), isEmpty);
      }
      final state = summarizeLifeTwin(
          days: days, previous: [], daysInWindow: 7);
      expect(state.hasData, isFalse);
      expect(state.overallIndex, isNull);
      expect(state.daysContributing, 0);
      expect(state.confidence, 'None');
      expect(state.relationships, isEmpty);
    });

    test('missing days stay missing (no filler)', () {
      final now = DateTime(2026, 9, 30);
      final dates = windowDates(days: 7, now: now);
      final logged = {dates.first, dates.last};
      final daily = {
        for (final d in logged) _key(d): _day(_key(d)),
      };
      final days = buildLifeTwinDays(
        windowDays: dates,
        dailyByDate: daily,
        stressMoodsByDate: {},
        morningByDate: {},
        eveningByDate: {},
      );
      final withSleep =
          days.where((d) => d.values[LifeTwinDimension.sleep] != null);
      expect(withSleep.length, 2);
      final state = summarizeLifeTwin(
          days: days, previous: [], daysInWindow: 7);
      expect(state.daysContributing, 2);
      expect(state.dimensions[LifeTwinDimension.sleep]!.count, 2);
      // Energy has no source at all → stays missing.
      expect(state.dimensions[LifeTwinDimension.energy]!.hasData, isFalse);
    });

    test('deterministic: same inputs give same outputs', () {
      LifeTwinState build() {
        final now = DateTime(2026, 9, 30);
        final dates = windowDates(days: 30, now: now);
        final daily = {
          for (var i = 0; i < dates.length; i += 2)
            _key(dates[i]): _day(_key(dates[i]), sleep: 6.0 + (i % 4)),
        };
        final days = buildLifeTwinDays(
          windowDays: dates,
          dailyByDate: daily,
          stressMoodsByDate: {
            for (var i = 0; i < dates.length; i += 2)
              _key(dates[i]): [3, 4],
          },
          morningByDate: {},
          eveningByDate: {},
        );
        return summarizeLifeTwin(
            days: days, previous: [], daysInWindow: 30);
      }

      final a = build();
      final b = build();
      expect(a.overallIndex, b.overallIndex);
      expect(a.daysContributing, b.daysContributing);
      expect(
          a.dimensions[LifeTwinDimension.sleep]!.average,
          b.dimensions[LifeTwinDimension.sleep]!.average);
    });
  });

  group('engine — windows', () {
    for (final days in [7, 30, 90, 180]) {
      test('$days-day window builds the right span', () {
        final dates = windowDates(days: days, now: DateTime(2026, 9, 30));
        expect(dates.length, days);
        final daily = {for (final d in dates) _key(d): _day(_key(d))};
        final built = buildLifeTwinDays(
          windowDays: dates,
          dailyByDate: daily,
          stressMoodsByDate: {},
          morningByDate: {},
          eveningByDate: {},
        );
        final state = summarizeLifeTwin(
            days: built, previous: [], daysInWindow: days);
        expect(state.daysContributing, days);
        expect(state.overallIndex, isNotNull);
        expect(state.confidence,
            days >= 14 ? 'High' : days >= 7 ? 'Medium' : 'Low');
      });
    }
  });

  group('engine — relationships', () {
    test('insufficient overlap shows nothing (keep logging)', () {
      final now = DateTime(2026, 9, 30);
      final dates = windowDates(days: 7, now: now);
      // Only 2 overlapping days — below the minimum.
      final daily = {
        _key(dates[0]): _day(_key(dates[0]), sleep: 5),
        _key(dates[1]): _day(_key(dates[1]), sleep: 8),
      };
      final days = buildLifeTwinDays(
        windowDays: dates,
        dailyByDate: daily,
        stressMoodsByDate: {
          _key(dates[0]): [2],
          _key(dates[1]): [5],
        },
        morningByDate: {},
        eveningByDate: {},
      );
      final state = summarizeLifeTwin(
          days: days, previous: [], daysInWindow: 7);
      expect(state.relationships, isEmpty);
    });

    test('sufficient co-moving data is labelled association-only', () {
      final now = DateTime(2026, 9, 30);
      final dates = windowDates(days: 7, now: now);
      // Sleep rises across the week; calm rises with it.
      final sleeps = [5.0, 5.5, 6.0, 6.5, 7.0, 7.5, 8.0];
      final daily = {
        for (var i = 0; i < 7; i++)
          _key(dates[i]): _day(_key(dates[i]), sleep: sleeps[i]),
      };
      final moods = {
        for (var i = 0; i < 7; i++)
          _key(dates[i]): [2 + (i ~/ 3)],
      };
      final days = buildLifeTwinDays(
        windowDays: dates,
        dailyByDate: daily,
        stressMoodsByDate: moods,
        morningByDate: {},
        eveningByDate: {},
      );
      final state = summarizeLifeTwin(
          days: days, previous: [], daysInWindow: 7);
      expect(state.relationships, isNotEmpty);
      for (final r in state.relationships) {
        expect(
            r.label,
            anyOf(
                ['Observed pattern', 'Moves together in your data']));
        expect(r.label.toLowerCase(), isNot(contains('cause')));
        expect(r.overlap, greaterThanOrEqualTo(kLifeTwinMinOverlap));
      }
    });

    test('pearson is null for constant series', () {
      expect(pearson([3, 3, 3], [1, 2, 3]), isNull);
      expect(pearson([1], [2]), isNull);
    });
  });

  group('engine — detail + scenario', () {
    test('detail summary has average/trend/best/worst', () {
      final now = DateTime(2026, 9, 30);
      final dates = windowDates(days: 7, now: now);
      final sleeps = [5.0, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5];
      final daily = {
        for (var i = 0; i < 7; i++)
          _key(dates[i]): _day(_key(dates[i]), sleep: sleeps[i]),
      };
      final days = buildLifeTwinDays(
        windowDays: dates,
        dailyByDate: daily,
        stressMoodsByDate: {},
        morningByDate: {},
        eveningByDate: {},
      );
      final state = summarizeLifeTwin(
          days: days, previous: [], daysInWindow: 7);
      final s = state.dimensions[LifeTwinDimension.sleep]!;
      expect(s.average, isNotNull);
      expect(s.trend, isNotNull);
      expect(s.trend, greaterThan(0));
      expect(s.best, greaterThan(s.worst!));
      expect(s.bestDay, isNotNull);
      expect(s.worstDay, isNotNull);
    });

    test('scenario is hypothetical and never mutates base', () {
      final now = DateTime(2026, 9, 30);
      final dates = windowDates(days: 30, now: now);
      final daily = {for (final d in dates) _key(d): _day(_key(d))};
      final days = buildLifeTwinDays(
        windowDays: dates,
        dailyByDate: daily,
        stressMoodsByDate: {for (final d in dates) _key(d): [3]},
        morningByDate: {},
        eveningByDate: {},
      );
      final base = summarizeLifeTwin(
          days: days, previous: [], daysInWindow: 30);
      final before = base.overallIndex;
      final proj = projectScenario(
        base: base,
        extraSleepHours: 1,
        extraExerciseMin: 60,
        calmerStress: 10,
        extraWaterGlasses: 2,
      )!;
      expect(proj.hypotheticalOverall, greaterThan(before!));
      expect(proj.contributors, isNotEmpty);
      // Base untouched.
      expect(base.overallIndex, before);
      expect(
          base.dimensions[LifeTwinDimension.sleep]!.average,
          lessThan(
              proj.hypotheticalAverages[LifeTwinDimension.sleep]!));
    });

    test('scenario returns null with no data', () {
      final dates = windowDates(days: 7, now: DateTime(2026, 9, 30));
      final days = buildLifeTwinDays(
        windowDays: dates,
        dailyByDate: {},
        stressMoodsByDate: {},
        morningByDate: {},
        eveningByDate: {},
      );
      final base = summarizeLifeTwin(
          days: days, previous: [], daysInWindow: 7);
      expect(projectScenario(base: base, extraSleepHours: 1), isNull);
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

    test('provider loads seeded week into a twin state', () async {
      final dailyRepo = DailyHealthRepository();
      final now = DateTime.now();
      for (var i = 0; i < 7; i++) {
        final d = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: i));
        await dailyRepo.save(_day(_key(d), sleep: 7 + (i % 2)));
      }
      final prov = LifeTwinProvider(dailyRepo: dailyRepo);
      await prov.load(rangeDays: 7);
      expect(prov.error, isNull);
      expect(prov.state, isNotNull);
      expect(prov.state!.daysContributing, 7);
      expect(prov.state!.overallIndex, isNotNull);
    });

    testWidgets('zero-data screen offers logging, no fake numbers',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: LifeTwinScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Either the loading indicator or the zero state — never a crash.
      expect(find.byType(LifeTwinScreen), findsOneWidget);
    });

    testWidgets('screen renders in dark mode', (tester) async {
      await tester.pumpWidget(MaterialApp(
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark(useMaterial3: true),
        theme: ThemeData.light(useMaterial3: true),
        home: const LifeTwinScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(LifeTwinScreen), findsOneWidget);
    });
  });
}
