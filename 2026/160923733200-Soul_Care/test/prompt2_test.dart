import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/app/providers/daily_health_provider.dart';
import 'package:soul_care/app/providers/checkin_providers.dart';
import 'package:soul_care/app/providers/action_center_provider.dart';
import 'package:soul_care/app/providers/dashboard_provider.dart';
import 'package:soul_care/app/providers/experiment_provider.dart';
import 'package:soul_care/app/theme/app_theme.dart';
import 'package:soul_care/core/wellness/insights.dart';
import 'package:soul_care/core/wellness/wellness_score.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/enums.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/data/repositories/checkin_repository.dart';
import 'package:soul_care/data/repositories/experiment_repository.dart';
import 'package:soul_care/data/repositories/stress_repository.dart';
import 'package:soul_care/features/daily_health/daily_health_screen.dart';
import 'package:soul_care/features/dashboard/dashboard_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_p2');
  Hive.init(dir.path);
  await Future.wait([
    Hive.openBox(LocalDatabase.dailyBoxName),
    Hive.openBox(LocalDatabase.stressBoxName),
    Hive.openBox(LocalDatabase.experimentsBoxName),
    Hive.openBox(LocalDatabase.documentsBoxName),
    Hive.openBox(LocalDatabase.settingsBoxName),
  ]);
}

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await _initTestHive();
  });

  tearDown(() async {
    await LocalDatabase.clearAll();
  });

  group('WellnessScoreCalculator', () {
    DailyHealthEntry entry(String date) => DailyHealthEntry(
          date: date,
          sleepHours: 7.5,
          sleepQuality: SleepQuality.good,
          feltRested: true,
          exerciseType: 'Walk',
          exerciseMinutes: 30,
          exerciseIntensity: ExerciseIntensity.moderate,
          mealQuality: MealQuality.good,
          waterGlasses: 6,
          meditationMinutes: 10,
          screenTimeHours: 2.0,
        );

    test('is deterministic: same inputs, same outputs', () {
      final a = WellnessScoreCalculator.calculate(
          entry: entry('2026-09-28'), daysLoggedLast7: 4, calmScore: 80);
      final b = WellnessScoreCalculator.calculate(
          entry: entry('2026-09-28'), daysLoggedLast7: 4, calmScore: 80);
      expect(a.totalScore, b.totalScore);
      expect(a.sleepScore, b.sleepScore);
      expect(a.movementScore, b.movementScore);
      expect(a.hydrationScore, b.hydrationScore);
      expect(a.mindScore, b.mindScore);
      expect(a.stressScore, b.stressScore);
      expect(a.consistencyScore, b.consistencyScore);
    });

    test('change = total - previous, explanation is data-supported', () {
      final prev = entry('2026-09-27').copyWith(sleepHours: 5);
      final score = WellnessScoreCalculator.calculate(
        entry: entry('2026-09-28'),
        previousEntry: prev,
        daysLoggedLast7: 2,
      );
      expect(score.previousScore, isNotNull);
      expect(score.change, score.totalScore - score.previousScore!);
      expect(score.explanation, contains('logged'));
      expect(score.explanation, contains('not a medical assessment'));
      expect(score.explanation.toLowerCase(), isNot(contains('diagnos')));
      expect(score.contributions.keys,
          containsAll(['Sleep', 'Movement', 'Hydration', 'Mind', 'Stress']));
    });

    test('missing check-in uses disclosed neutral placeholder', () {
      final score = WellnessScoreCalculator.calculate(
          entry: entry('2026-09-28'), daysLoggedLast7: 1);
      expect(score.stressScore, 70);
      expect(score.contributions['Stress'], contains('neutral'));
    });
  });

  group('InsightEngine', () {
    test('detects sleep improvement + exercise count, careful language', () {
      final entries = [
        const DailyHealthEntry(date: '2026-09-22', sleepHours: 5.5),
        const DailyHealthEntry(
            date: '2026-09-23', sleepHours: 6, exerciseMinutes: 30),
        const DailyHealthEntry(
            date: '2026-09-24', sleepHours: 7.5, exerciseMinutes: 20),
        const DailyHealthEntry(
            date: '2026-09-25', sleepHours: 8, exerciseMinutes: 45),
      ];
      final insights =
          InsightEngine.build(last7: entries, calmByDate: const {});
      expect(insights, isNotEmpty);
      final all = insights.map((i) => '${i.title} ${i.body}'.toLowerCase()).join(' ');
      expect(all, contains('logged'));
      expect(all, isNot(contains('prove')));
      expect(all, isNot(contains('cause')));
    });

    test('empty input yields no insights (dashboard shows empty state)', () {
      expect(
          InsightEngine.build(last7: const [], calmByDate: const {}), isEmpty);
    });
  });

  group('partial saving + restart', () {
    test('sleep-only save completes 1/5 and survives provider recreation',
        () async {
      final dailyRepo = DailyHealthRepository();
      final provider = DailyHealthProvider(dailyRepo);
      await provider.loadToday();
      expect(provider.completedSections, 0);

      final ok = await provider.saveSleep(
          hours: 7.5, quality: SleepQuality.good, feltRested: true);
      expect(ok, isTrue);
      expect(provider.sleepDone, isTrue);
      expect(provider.movementDone, isFalse);
      expect(provider.completedSections, 1);

      // Simulate app restart: brand-new provider over the same boxes.
      final restarted = DailyHealthProvider(DailyHealthRepository());
      await restarted.loadToday();
      expect(restarted.sleepDone, isTrue);
      expect(restarted.today?.sleepHours, 7.5);
      expect(restarted.completedSections, 1);
    });

    test('independent section saves never erase each other', () async {
      final provider = DailyHealthProvider(DailyHealthRepository());
      await provider.loadToday();
      await provider.saveSleep(
          hours: 8, quality: SleepQuality.excellent, feltRested: true);
      await provider.saveMovement(
          type: 'Run',
          minutes: 25,
          intensity: ExerciseIntensity.high);
      await provider.saveNutrition(
          mealQuality: MealQuality.good, waterGlasses: 7);
      await provider.saveMind(meditationMinutes: 15, screenTimeHours: 1.5);

      expect(provider.sleepDone, isTrue);
      expect(provider.movementDone, isTrue);
      expect(provider.nutritionDone, isTrue);
      expect(provider.mindDone, isTrue);
      // Sleep values intact after later saves.
      expect(provider.today?.sleepHours, 8);
      expect(provider.today?.exerciseMinutes, 25);
      expect(provider.completedSections, 4); // stress still missing
    });

    test('yesterday entry is exposed as suggestion, never auto-applied',
        () async {
      final repo = DailyHealthRepository();
      final yesterdayKey = _key(DateTime.now().subtract(const Duration(days: 1)));
      await repo.save(
          DailyHealthEntry(date: yesterdayKey, sleepHours: 7.2));

      final provider = DailyHealthProvider(repo);
      await provider.loadToday();
      expect(provider.yesterday?.sleepHours, 7.2);
      // Today untouched until the user accepts + saves.
      expect(provider.today?.sleepHours, 0);
      expect(provider.sleepDone, isFalse);
    });

    test('stress check-in completes the 5th section', () async {
      final provider = DailyHealthProvider(DailyHealthRepository(),
          stressRepo: StressRepository());
      await provider.loadToday();
      final ok = await provider.saveStressCheck(
        mood: Mood.okay,
        triggers: const ['Work'],
        controllability: 0.5,
      );
      expect(ok, isTrue);
      expect(provider.stressDone, isTrue);
    });
  });

  group('weekly dashboard: 7 days + missing days', () {
    test('gaps stay null (no fake points), insights built', () async {
      final repo = DailyHealthRepository();
      final now = DateTime.now();
      // 5 of the last 7 days (missing 2).
      for (final offset in [0, 1, 3, 4, 6]) {
        final d = now.subtract(Duration(days: offset));
        await repo.save(DailyHealthEntry(
          date: _key(d),
          sleepHours: 7 + (offset % 2),
          exerciseMinutes: offset.isEven ? 30 : 0,
          waterGlasses: 6,
          meditationMinutes: 10,
        ));
      }
      final dash = DashboardProvider(repo, stressRepo: StressRepository());
      await dash.load();

      expect(dash.week.length, 7);
      final withData = dash.week.where((d) => d.hasData).length;
      final missing = dash.week.where((d) => !d.hasData).length;
      expect(withData, 5);
      expect(missing, 2);
      // Missing days carry no fabricated values.
      for (final d in dash.week.where((d) => !d.hasData)) {
        expect(d.wellness, isNull);
        expect(d.sleepHours, isNull);
      }
      expect(dash.daysLogged, 5);
      expect(dash.todayScore, isNotNull);
      expect(dash.insights, isNotEmpty);
    });

    test('brand-new user: empty week, no score, no insights', () async {
      final dash = DashboardProvider(DailyHealthRepository());
      await dash.load();
      expect(dash.daysLogged, 0);
      expect(dash.todayScore, isNull);
      expect(dash.insights, isEmpty);
      expect(dash.week.length, 7);
    });
  });

  group('widgets', () {
    testWidgets('brand-new dashboard shows empty state + first action',
        (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
                create: (_) =>
                    DailyHealthProvider(DailyHealthRepository())),
            ChangeNotifierProvider(
                create: (_) => DashboardProvider(DailyHealthRepository())),
            ChangeNotifierProvider(
                create: (_) =>
                    ExperimentProvider(ExperimentRepository())),
            ChangeNotifierProvider(
                create: (_) =>
                    MorningProvider(MorningRepository())),
            ChangeNotifierProvider(
                create: (_) => EveningProvider(EveningRepository())),
            ChangeNotifierProvider(create: (_) => ActionCenterProvider()),
          ],
          child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('No data yet'), findsWidgets);
      expect(find.text('Log your first day'), findsOneWidget);
    });

    testWidgets('today screen has 5 independent section saves',
        (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
                create: (_) => DailyHealthProvider(DailyHealthRepository(),
                    stressRepo: StressRepository())),
          ],
          child:
              const MaterialApp(home: Scaffold(body: DailyHealthScreen())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Daily Progress'), findsOneWidget);
      for (final label in [
        'Save Sleep',
        'Save Movement',
        'Save Nutrition',
        'Save Mind',
        'Save check-in',
      ]) {
        await tester.scrollUntilVisible(
            find.text(label), 500,
            scrollable: find.byType(Scrollable).first);
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Breathing reset'), findsOneWidget);
    });

    testWidgets('dark mode renders dashboard without errors',
        (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
                create: (_) =>
                    DailyHealthProvider(DailyHealthRepository())),
            ChangeNotifierProvider(
                create: (_) => DashboardProvider(DailyHealthRepository())),
            ChangeNotifierProvider(
                create: (_) =>
                    ExperimentProvider(ExperimentRepository())),
            ChangeNotifierProvider(
                create: (_) =>
                    MorningProvider(MorningRepository())),
            ChangeNotifierProvider(
                create: (_) => EveningProvider(EveningRepository())),
            ChangeNotifierProvider(create: (_) => ActionCenterProvider()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.dark,
            home: const Scaffold(body: DashboardScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final ctx = tester.element(find.byType(DashboardScreen));
      expect(Theme.of(ctx).brightness, Brightness.dark);
      expect(tester.takeException(), isNull);
    });
  });
}
