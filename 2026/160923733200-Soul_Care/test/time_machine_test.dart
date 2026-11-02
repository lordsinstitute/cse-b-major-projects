import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:soul_care/features/time_machine/time_machine_engine.dart';
import 'package:soul_care/features/time_machine/time_machine_provider.dart';
import 'package:soul_care/features/time_machine/time_machine_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_tm');
  Hive.init(dir.path);
  await Future.wait([
    Hive.openBox(LocalDatabase.dailyBoxName),
    Hive.openBox(LocalDatabase.stressBoxName),
    Hive.openBox(LocalDatabase.morningBoxName),
    Hive.openBox(LocalDatabase.eveningBoxName),
    Hive.openBox(LocalDatabase.experimentsBoxName),
    Hive.openBox(LocalDatabase.journalBoxName),
    Hive.openBox(LocalDatabase.documentsBoxName),
    Hive.openBox(LocalDatabase.settingsBoxName),
  ]);
}

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DailyHealthEntry _day(String key,
    {double sleep = 7.5,
    int exercise = 30,
    int water = 8,
    int meditation = 15}) {
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
    screenTimeHours: 2,
  );
}

void main() {
  group('engine — empty timeline', () {
    test('nothing logged yields honest empty state', () {
      final events = collectEvents(
        dailyKeys: {},
        dailyByDate: {},
        experiments: [],
        journals: [],
        documents: [],
      );
      expect(events, isEmpty);

      final day = buildDayReplay(
        date: DateTime(2026, 9, 30),
        dailyByDate: {},
        stressMoodsByDate: {},
        morningByDate: {},
        eveningByDate: {},
        experiments: [],
        journalsByDate: {},
      );
      expect(day.hasData, isFalse);
      expect(day.wellness, isNull);
      expect(day.unavailableReason, contains('Nothing was logged'));

      final summary = summarizePeriod([]);
      expect(summary.loggedDays, 0);
      expect(summary.avgWellness, isNull);
      expect(summary.change, isNull);
    });
  });

  group('engine — single day', () {
    test('one logged day replays its dashboard state', () {
      final date = DateTime(2026, 9, 30);
      final key = _key(date);
      final day = buildDayReplay(
        date: date,
        dailyByDate: {key: _day(key)},
        stressMoodsByDate: {
          key: [4]
        },
        morningByDate: {
          key: MorningCheckIn(
              date: key, energy: 4, mood: 4, updatedAt: DateTime.now()),
        },
        eveningByDate: {},
        experiments: [],
        journalsByDate: {},
      );
      expect(day.hasData, isTrue);
      expect(day.wellness, isNotNull);
      expect(day.sleepHours, 7.5);
      expect(day.calm, 80);
      expect(day.energy, 4.0);
      expect(day.exerciseMinutes, 30);
      expect(day.activeExperiment, isNull);
    });
  });

  group('engine — months of data', () {
    test('60 consecutive days earn streak milestones, deterministically', () {
      List<TimeEvent> collect() {
        final now = DateTime(2026, 9, 30);
        final keys = {
          for (var i = 0; i < 60; i++)
            _key(DateTime(now.year, now.month, now.day)
                .subtract(Duration(days: 59 - i))),
        };
        return collectEvents(
          dailyKeys: keys,
          dailyByDate: {},
          experiments: [],
          journals: [],
          documents: [],
        );
      }

      final a = collect();
      final b = collect();
      final milestones =
          a.where((e) => e.type == TimeEventType.habitMilestone).toList();
      expect(milestones.map((e) => e.title),
          ['3-day logging streak', '7-day logging streak', '14-day logging streak', '30-day logging streak', '60-day logging streak']);
      expect(
          b.map((e) => '${e.dateKey}:${e.type.name}:${e.title}'),
          a.map((e) => '${e.dateKey}:${e.type.name}:${e.title}'));
    });

    test('missing dates break streaks and stay unavailable', () {
      final now = DateTime(2026, 9, 30);
      DateTime at(int ago) => DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: ago));
      // 5 days, gap, 2 days.
      final keys = {
        _key(at(6)),
        _key(at(5)),
        _key(at(4)),
        _key(at(3)),
        _key(at(2)),
        _key(at(0)),
      };
      final events = collectEvents(
        dailyKeys: keys,
        dailyByDate: {},
        experiments: [],
        journals: [],
        documents: [],
      );
      // Longest run is 5 → milestones at 3 only (7 never reached).
      expect(
          events
              .where((e) => e.type == TimeEventType.habitMilestone)
              .map((e) => e.title),
          ['3-day logging streak']);

      final gap = buildDayReplay(
        date: at(1),
        dailyByDate: {},
        stressMoodsByDate: {},
        morningByDate: {},
        eveningByDate: {},
        experiments: [],
        journalsByDate: {},
      );
      expect(gap.hasData, isFalse);
    });
  });

  group('engine — events', () {
    test('experiment start/complete/check-ins become markers', () {
      final start = DateTime(2026, 9, 20);
      final exp = Experiment(
        id: 'e1',
        title: 'Daily Walk',
        description: 'd',
        targetMetric: 'm',
        durationDays: 7,
        startDate: start,
        endDate: DateTime(2026, 9, 27),
        status: ExperimentStatus.completed,
        checkIns: [_key(DateTime(2026, 9, 21))],
        createdAt: start,
        updatedAt: start,
      );
      final journal = JournalEntry(
        id: 'j1',
        date: _key(DateTime(2026, 9, 22)),
        title: 'Good day',
        body: 'Felt fine.',
        createdAt: start,
        updatedAt: start,
      );
      final events = collectEvents(
        dailyKeys: {},
        dailyByDate: {},
        experiments: [exp],
        journals: [journal],
        documents: [],
      );
      final types = events.map((e) => e.type).toSet();
      expect(types, contains(TimeEventType.experimentStarted));
      expect(types, contains(TimeEventType.experimentCompleted));
      expect(types, contains(TimeEventType.habitActivity));
      expect(types, contains(TimeEventType.journalEntry));
    });

    test('goal reached fires once per completed stretch', () {
      final now = DateTime(2026, 9, 30);
      final daily = <String, DailyHealthEntry>{};
      for (var i = 0; i < 10; i++) {
        final d = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: 9 - i));
        final k = _key(d);
        daily[k] = _day(k, sleep: 8, exercise: 30, water: 8, meditation: 15);
      }
      final events = collectEvents(
        dailyKeys: daily.keys.toSet(),
        dailyByDate: daily,
        experiments: [],
        journals: [],
        documents: [],
      );
      final goals =
          events.where((e) => e.type == TimeEventType.goalReached).toList();
      expect(goals.length, 1);
    });

    test('event copy never claims causality', () {
      final events = collectEvents(
        dailyKeys: {
          _key(DateTime(2026, 9, 28)),
          _key(DateTime(2026, 9, 29)),
          _key(DateTime(2026, 9, 30)),
        },
        dailyByDate: {},
        experiments: [],
        journals: [],
        documents: [],
      );
      for (final e in events) {
        expect(e.title.toLowerCase(), isNot(contains('caus')));
        expect(e.detail.toLowerCase(), isNot(contains('caus')));
        expect(e.type.label.toLowerCase(), isNot(contains('caus')));
      }
    });
  });

  group('engine — replay', () {
    test('important changes flag swings and milestones', () {
      final now = DateTime(2026, 9, 30);
      DateTime at(int ago) => DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: ago));
      final daily = {
        _key(at(2)): _day(_key(at(2)), sleep: 8, exercise: 60),
        _key(at(1)): _day(_key(at(1)), sleep: 4, exercise: 0),
        _key(at(0)): _day(_key(at(0)), sleep: 8, exercise: 60),
      };
      final ordered = [
        for (var i = 2; i >= 0; i--)
          buildDayReplay(
            date: at(i),
            dailyByDate: daily,
            stressMoodsByDate: {},
            morningByDate: {},
            eveningByDate: {},
            experiments: [],
            journalsByDate: {},
          ),
      ];
      final keys = importantChangeKeys(ordered: ordered, eventsByDate: {});
      // Middle day crashes vs day before; last day rebounds vs middle.
      expect(keys, [_key(at(1)), _key(at(0))]);
    });
  });

  group('engine — comparison', () {
    test('two dates show signed changes; missing sides stay unavailable',
        () {
      DayReplay day(String date, DailyHealthEntry? e, List<int>? moods) {
        return buildDayReplay(
          date: DateTime.parse(date),
          dailyByDate: e == null ? {} : {date: e},
          stressMoodsByDate: moods == null ? {} : {date: moods},
          morningByDate: {},
          eveningByDate: {},
          experiments: [],
          journalsByDate: {},
        );
      }

      final a = day('2026-09-28', _day('2026-09-28', sleep: 6), [3]);
      final b = day('2026-09-29', _day('2026-09-29', sleep: 8), [4]);
      final rows = {
        for (final r in compareDays(a, b)) r.metric: r,
      };
      expect(rows['Sleep']!.sideA, isNot('unavailable'));
      expect(rows['Sleep']!.delta.startsWith('+'), isTrue);

      final missing = day('2026-09-30', null, null);
      final rows2 = {
        for (final r in compareDays(a, missing)) r.metric: r,
      };
      expect(rows2['Sleep']!.sideB, 'unavailable');
      expect(rows2['Sleep']!.delta, 'unavailable');
      expect(rows2['Wellness score']!.delta, 'unavailable');
    });

    test('period comparison aggregates honestly', () {
      DayReplay logged(double sleep, int ex) => DayReplay(
            dateKey: 'k',
            date: DateTime(2026, 9, 30),
            hasData: true,
            wellness: 70,
            sleepHours: sleep,
            exerciseMinutes: ex,
          );
      final empty = DayReplay(
          dateKey: 'k', date: DateTime(2026, 9, 30), hasData: false);
      final a = summarizePeriod([logged(8, 30), logged(8, 30)]);
      final b = summarizePeriod([logged(6, 0), empty]);
      final rows = {
        for (final r in comparePeriods(a, b)) r.metric: r,
      };
      expect(rows['Logged days']!.sideA, '2');
      expect(rows['Logged days']!.sideB, '1');
      expect(rows['Avg sleep']!.delta.startsWith('-'), isTrue);
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

    test('index + month load surface seeded history', () async {
      final dailyRepo = DailyHealthRepository();
      final morningRepo = MorningRepository();
      final expRepo = ExperimentRepository();
      final journalRepo = const JournalRepository();
      final now = DateTime.now();
      DateTime at(int ago) => DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: ago));
      for (var i = 0; i < 10; i++) {
        await dailyRepo.save(_day(_key(at(i))));
      }
      await morningRepo.save(MorningCheckIn(
          date: _key(at(0)), energy: 4, updatedAt: DateTime.now()));
      await expRepo.save(Experiment(
        id: 'e1',
        title: 'Daily Walk',
        description: 'd',
        targetMetric: 'm',
        durationDays: 7,
        startDate: at(6),
        status: ExperimentStatus.active,
        createdAt: now,
        updatedAt: now,
      ));
      await journalRepo.save(JournalEntry(
        id: 'j1',
        date: _key(at(1)),
        body: 'A note.',
        createdAt: now,
        updatedAt: now,
      ));

      final prov = TimeMachineProvider();
      await prov.loadIndex();
      expect(prov.error, isNull);
      expect(prov.availableDays.length, greaterThanOrEqualTo(10));
      expect(
          prov.events
              .where((e) => e.type == TimeEventType.experimentStarted),
          isNotEmpty);
      expect(
          prov.events
              .where((e) => e.type == TimeEventType.journalEntry),
          isNotEmpty);

      await prov.ensureMonth(now.year, now.month);
      final replay = prov.dayReplay(at(0));
      expect(replay.hasData, isTrue);
      expect(replay.wellness, isNotNull);

      final future = prov.dayReplay(DateTime(2030, 1, 1));
      expect(future.hasData, isFalse);
      expect(future.unavailableReason, isNotNull);
    });

    testWidgets('empty history explains itself, never fabricates',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TimeMachineScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(TimeMachineScreen), findsOneWidget);
      expect(find.text('No history yet'), findsOneWidget);
    });

    testWidgets('screen renders in dark mode', (tester) async {
      await tester.pumpWidget(MaterialApp(
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark(useMaterial3: true),
        theme: ThemeData.light(useMaterial3: true),
        home: const TimeMachineScreen(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(TimeMachineScreen), findsOneWidget);
    });
  });
}
