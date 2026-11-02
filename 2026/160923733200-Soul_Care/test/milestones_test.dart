import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/app/providers/milestones_provider.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/checkins.dart';
import 'package:soul_care/data/models/enums.dart';
import 'package:soul_care/data/models/journal.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/features/milestones/milestone_engine.dart';
import 'package:soul_care/features/milestones/milestones_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_ms');
  Hive.init(dir.path);
  await Future.wait([
    Hive.openBox(LocalDatabase.dailyBoxName),
    Hive.openBox(LocalDatabase.stressBoxName),
    Hive.openBox(LocalDatabase.experimentsBoxName),
    Hive.openBox(LocalDatabase.journalBoxName),
    Hive.openBox(LocalDatabase.eveningBoxName),
    Hive.openBox(LocalDatabase.milestoneBoxName),
  ]);
}

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DailyHealthEntry _day(String key, {int exercise = 30}) {
  return DailyHealthEntry(
    date: key,
    sleepHours: 7.5,
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

MilestoneInput _input({
  List<String> dates = const [],
  Map<String, DailyHealthEntry>? entries,
  Set<String> stress = const {},
  List<Experiment> experiments = const [],
  List<JournalEntry> journals = const [],
  List<EveningReflection> evenings = const [],
  DateTime? now,
}) {
  final map = entries ??
      {for (final k in dates) k: _day(k)};
  return MilestoneInput(
    entriesByDate: map,
    stressDates: stress,
    experiments: experiments,
    journals: journals,
    evenings: evenings,
    now: now ?? DateTime(2026, 10, 4),
  );
}

List<String> _run(DateTime end, int n) => [
      for (var i = n - 1; i >= 0; i--)
        _key(DateTime(end.year, end.month, end.day)
            .subtract(Duration(days: i))),
    ];

Experiment _exp({
  required String id,
  String templateId = 'daily-walk',
  ExperimentStatus status = ExperimentStatus.active,
  DateTime? start,
  DateTime? end,
  List<String> checkIns = const [],
}) {
  final now = DateTime(2026, 10, 4);
  return Experiment(
    id: id,
    templateId: templateId,
    title: 'Test $id',
    description: 'd',
    targetMetric: 'exerciseMinutes',
    durationDays: 7,
    startDate: start ?? DateTime(2026, 9, 27),
    endDate: end,
    status: status,
    checkIns: checkIns,
    createdAt: start ?? DateTime(2026, 9, 27),
    updatedAt: now,
  );
}

void main() {
  group('engine — firsts and streaks', () {
    test('three logged days unlock the first streak milestone', () {
      final days = _run(DateTime(2026, 10, 4), 3);
      final all = evaluateMilestones(_input(dates: days));
      final s3 = all.firstWhere((m) => m.def.id == 'streak-3');
      expect(s3.unlocked, isTrue);
      expect(_key(s3.achievedDate!), days.last);
      expect(all.firstWhere((m) => m.def.id == 'streak-7').unlocked,
          isFalse);
    });

    test('streak ladder 7/30/100 with historical dates', () {
      final days = _run(DateTime(2026, 10, 4), 100);
      final all = evaluateMilestones(_input(dates: days));
      for (final id in ['streak-7', 'streak-30', 'streak-100']) {
        final m = all.firstWhere((d) => d.def.id == id);
        expect(m.unlocked, isTrue, reason: id);
      }
      final s7 = all.firstWhere((d) => d.def.id == 'streak-7');
      expect(_key(s7.achievedDate!), days[6]);
    });

    test('broken streaks do not count', () {
      final days = [
        ..._run(DateTime(2026, 10, 4), 4),
        ..._run(DateTime(2026, 9, 28), 4),
      ];
      final all = evaluateMilestones(_input(dates: days));
      expect(all.firstWhere((m) => m.def.id == 'streak-7').unlocked,
          isFalse);
      expect(all.firstWhere((m) => m.def.id == 'streak-3').unlocked,
          isTrue);
    });
  });

  group('engine — experiments and habits', () {
    test('first start and first completion unlock with dates', () {
      final all = evaluateMilestones(_input(experiments: [
        _exp(id: 'a', status: ExperimentStatus.completed,
            end: DateTime(2026, 10, 2)),
      ]));
      final first = all.firstWhere((m) => m.def.id == 'exp-first');
      expect(first.unlocked, isTrue);
      final done = all.firstWhere((m) => m.def.id == 'exp-complete-1');
      expect(done.unlocked, isTrue);
      expect(_key(done.achievedDate!), '2026-10-02');
      expect(all.firstWhere((m) => m.def.id == 'exp-complete-5').unlocked,
          isFalse);
    });

    test('five completions unlock the fifth-date milestone', () {
      final exps = [
        for (var i = 0; i < 5; i++)
          _exp(
              id: 'e$i',
              status: ExperimentStatus.completed,
              start: DateTime(2026, 8, 1 + i * 8),
              end: DateTime(2026, 8, 7 + i * 8)),
      ];
      final all = evaluateMilestones(_input(experiments: exps));
      final m = all.firstWhere((d) => d.def.id == 'exp-complete-5');
      expect(m.unlocked, isTrue);
      expect(_key(m.achievedDate!), '2026-09-08');
    });

    test('habit check-ins unlock first and streaks', () {
      final run = _run(DateTime(2026, 10, 4), 8);
      final all = evaluateMilestones(_input(experiments: [
        _exp(id: 'a', checkIns: run),
      ]));
      final first = all.firstWhere((m) => m.def.id == 'habit-first');
      expect(first.unlocked, isTrue);
      expect(_key(first.achievedDate!), run.first);
      expect(
          all.firstWhere((m) => m.def.id == 'habit-streak-7').unlocked,
          isTrue);
      expect(
          all.firstWhere((m) => m.def.id == 'habit-streak-30').unlocked,
          isFalse);
    });
  });

  group('engine — reflection and complete days', () {
    test('journal and evening reflections count with dates', () {
      final journals = [
        for (var i = 0; i < 9; i++)
          JournalEntry(
            id: 'j$i',
            date: _key(DateTime(2026, 9, 1 + i)),
            body: 'note $i',
            createdAt: DateTime(2026, 9, 1 + i),
            updatedAt: DateTime(2026, 9, 1 + i),
          ),
      ];
      final evenings = [
        EveningReflection(
            date: '2026-09-15',
            updatedAt: DateTime(2026, 9, 15)),
      ];
      final all = evaluateMilestones(
          _input(journals: journals, evenings: evenings));
      expect(all.firstWhere((m) => m.def.id == 'journal-first').unlocked,
          isTrue);
      final r10 = all.firstWhere((m) => m.def.id == 'reflections-10');
      expect(r10.unlocked, isTrue);
      expect(_key(r10.achievedDate!), '2026-09-15');
      expect(
          all.firstWhere((m) => m.def.id == 'reflections-30').unlocked,
          isFalse);
    });

    test('complete days need every routine section', () {
      final full = _day('2026-10-01');
      final noExercise = _day('2026-10-02', exercise: 0);
      final all = evaluateMilestones(_input(
        entries: {'2026-10-01': full, '2026-10-02': noExercise},
        stress: {'2026-10-01', '2026-10-02'},
      ));
      final c1 = all.firstWhere((m) => m.def.id == 'complete-1');
      expect(c1.unlocked, isTrue);
      expect(_key(c1.achievedDate!), '2026-10-01');
      // Missing stress check-in also breaks completeness.
      final noStress = evaluateMilestones(_input(
        entries: {'2026-10-01': full},
        stress: {},
      ));
      expect(
          noStress.firstWhere((m) => m.def.id == 'complete-1').unlocked,
          isFalse);
    });
  });

  group('engine — honesty guards', () {
    test('evaluation is idempotent: no duplicates possible', () {
      final days = _run(DateTime(2026, 10, 4), 30);
      final a = evaluateMilestones(_input(dates: days));
      final b = evaluateMilestones(_input(dates: days));
      expect(a.map((m) => m.def.id).toSet().length, a.length);
      expect(b.map((m) => '${m.def.id}:${m.unlocked}'),
          a.map((m) => '${m.def.id}:${m.unlocked}'));
    });

    test('no milestone rewards extremes', () {
      final combined = milestoneDefs
          .map((d) => '${d.id} ${d.title} ${d.description}')
          .join(' ')
          .toLowerCase();
      for (final w in [
        'marathon',
        'fasting',
        'skip',
        'starv',
        'purge',
        '1000',
        'diagnos',
      ]) {
        expect(combined.contains(w), isFalse, reason: w);
      }
      // Extreme values earn nothing special: 600-min days behave like
      // ordinary logged days (consistency only).
      final days = _run(DateTime(2026, 10, 4), 3);
      final extreme = {
        for (final k in days)
          k: DailyHealthEntry(
            date: k,
            sleepHours: 24,
            sleepQuality: SleepQuality.excellent,
            feltRested: true,
            exerciseMinutes: 600,
            exerciseIntensity: ExerciseIntensity.high,
            mealQuality: MealQuality.excellent,
            waterGlasses: 30,
            meditationMinutes: 600,
            screenTimeHours: 0,
          ),
      };
      final all = evaluateMilestones(
          _input(entries: extreme, stress: days.toSet()));
      final unlockedIds = {
        for (final m in all)
          if (m.unlocked) m.def.id,
      };
      expect(unlockedIds, {'streak-3', 'complete-1'});
    });

    test('helpers pick next and most-recent', () {
      final days = _run(DateTime(2026, 10, 4), 10);
      final all = evaluateMilestones(_input(dates: days));
      final next = nextMilestone(all)!;
      expect(next.def.id, 'streak-30'); // 10/30 closest fraction
      expect('${next.progress} / ${next.def.target} days', '10 / 30 days');
      expect(mostRecentMilestone(all)!.def.id, 'streak-7');
    });
  });

  group('provider — persistence and restart', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await _initTestHive();
    });

    tearDown(() async {
      await LocalDatabase.clearAll();
    });

    test('unlock, celebrate, restart keeps celebrated state', () async {
      final repo = DailyHealthRepository();
      for (final k in _run(DateTime.now(), 7)) {
        await repo.save(_day(k));
      }
      final prov = MilestonesProvider();
      await prov.load();
      final s7 = prov.all.firstWhere((m) => m.def.id == 'streak-7');
      expect(s7.unlocked, isTrue);
      expect(
          prov.uncelebrated.any((m) => m.def.id == 'streak-7'), isTrue);

      await prov.celebrate('streak-7');
      // Fresh provider over the same boxes (like an app restart).
      final again = MilestonesProvider();
      await again.load();
      final kept = again.all.firstWhere((m) => m.def.id == 'streak-7');
      expect(kept.unlocked, isTrue);
      expect(kept.celebrated, isTrue);
      expect(
          again.uncelebrated.any((m) => m.def.id == 'streak-7'), isFalse);
    });

    testWidgets('milestone cards render, celebration is calm', (tester) async {
      final repo = DailyHealthRepository();
      for (final k in _run(DateTime.now(), 7)) {
        await repo.save(_day(k));
      }
      final prov = MilestonesProvider();
      await prov.load();
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider.value(
          value: prov,
          child: const _MilestonesTestShell(),
        ),
      ));
      await tester.pump();
      expect(find.text('7 DAY STREAK'), findsOneWidget);
      expect(find.text('Next milestone'), findsOneWidget);
    });

    testWidgets('screen renders in dark mode', (tester) async {
      final prov = MilestonesProvider();
      await prov.load();
      await tester.pumpWidget(MaterialApp(
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark(useMaterial3: true),
        theme: ThemeData.light(useMaterial3: true),
        home: ChangeNotifierProvider.value(
          value: prov,
          child: const _MilestonesTestShell(),
        ),
      ));
      await tester.pump();
      expect(find.text('Quiet recognition'), findsOneWidget);
    });
  });
}

/// Pumps the real screen against a preloaded provider (no auto-dialog in
/// these cases: celebration state is asserted through the provider).
class _MilestonesTestShell extends StatelessWidget {
  const _MilestonesTestShell();

  @override
  Widget build(BuildContext context) {
    return const MilestonesScreen();
  }
}
