import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/app/providers/checkin_providers.dart';
import 'package:soul_care/app/providers/action_center_provider.dart';
import 'package:soul_care/app/providers/daily_health_provider.dart';
import 'package:soul_care/app/providers/dashboard_provider.dart';
import 'package:soul_care/app/providers/experiment_provider.dart';
import 'package:soul_care/app/theme/app_theme.dart';
import 'package:soul_care/core/utils/utils.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/checkins.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/repositories/checkin_repository.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/data/repositories/experiment_repository.dart';
import 'package:soul_care/features/checkins/evening_screen.dart';
import 'package:soul_care/features/checkins/morning_screen.dart';
import 'package:soul_care/features/dashboard/dashboard_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_checkin');
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
  ]);
}

String _todayKey() => formatDateForStorage(DateTime.now());

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await _initTestHive();
  });

  tearDown(() async {
    await LocalDatabase.clearAll();
  });

  group('morning model + repo', () {
    test('first-day save, one record per date', () async {
      final repo = MorningRepository();
      expect((await repo.getByDate('2099-01-01')).value, isNull);
      final saved = await repo.save(MorningCheckIn(
        date: '2099-01-01',
        sleepHours: 7.3,
        rested: 4,
        mood: 4,
        energy: 3,
        intention: 'Stay hydrated',
        updatedAt: DateTime.now(),
      ));
      expect(saved.isSuccess, isTrue);
      expect(saved.value!.intention, 'Stay hydrated');

      // Re-saving the same date overwrites (still exactly one record).
      await repo.save(MorningCheckIn(
        date: '2099-01-01',
        sleepHours: 6.5,
        updatedAt: DateTime.now(),
      ));
      expect((await repo.getByDate('2099-01-01')).value!.sleepHours, 6.5);
    });

    test('partial completion allowed (no intention)', () async {
      final repo = MorningRepository();
      final saved = await repo.save(MorningCheckIn(
        date: '2099-01-02',
        updatedAt: DateTime.now(),
      ));
      expect(saved.isSuccess, isTrue);
      expect(saved.value!.intention, isNull);
    });
  });

  group('evening model + repo', () {
    test('save + edit same date keeps one editable record', () async {
      final repo = EveningRepository();
      await repo.save(EveningReflection(
        date: '2099-01-01',
        mood: 2,
        energy: 2,
        stress: 4,
        updatedAt: DateTime.now(),
      ));
      final edited = await repo.save(EveningReflection(
        date: '2099-01-01',
        mood: 4,
        energy: 4,
        stress: 2,
        wentWell: 'Walk at lunch',
        improve: 'Less late coffee',
        updatedAt: DateTime.now(),
      ));
      expect(edited.isSuccess, isTrue);
      final loaded = (await repo.getByDate('2099-01-01')).value!;
      expect(loaded.mood, 4);
      expect(loaded.wentWell, 'Walk at lunch');
    });
  });

  group('providers', () {
    test('morning restart restores check-in; prefills unlogged sleep only',
        () async {
      final p = MorningProvider(MorningRepository(),
          dailyRepo: DailyHealthRepository());
      await p.loadToday();
      expect(p.done, isFalse);
      expect(
          await p.save(MorningCheckIn(
            date: _todayKey(),
            sleepHours: 7.25,
            rested: 4,
            mood: 4,
            energy: 4,
            updatedAt: DateTime.now(),
          )),
          isTrue);
      expect(p.done, isTrue);

      // Restart: fresh provider sees the check-in.
      final restarted = MorningProvider(MorningRepository(),
          dailyRepo: DailyHealthRepository());
      await restarted.loadToday();
      expect(restarted.today?.sleepHours, 7.25);

      // Sleep prefilled into today's entry (was unlogged).
      final daily = await DailyHealthRepository().getByDate(_todayKey());
      expect(daily.value?.sleepHours, 7.25);

      // Existing logged sleep is never overwritten.
      await DailyHealthRepository().save(
          DailyHealthEntry(date: _todayKey(), sleepHours: 5.5));
      expect(
          await restarted.save(MorningCheckIn(
            date: _todayKey(),
            sleepHours: 9,
            updatedAt: DateTime.now(),
          )),
          isTrue);
      final kept =
          await DailyHealthRepository().getByDate(_todayKey());
      expect(kept.value?.sleepHours, 5.5);
    });

    test('evening restart restores reflection', () async {
      final p = EveningProvider(EveningRepository());
      await p.loadToday();
      expect(p.done, isFalse);
      await p.save(EveningReflection(
        date: _todayKey(),
        mood: 4,
        energy: 3,
        stress: 2,
        updatedAt: DateTime.now(),
      ));
      final restarted = EveningProvider(EveningRepository());
      await restarted.loadToday();
      expect(restarted.done, isTrue);
      expect(restarted.today?.stress, 2);
    });
  });

  group('widgets', () {
    MultiProvider wrap(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider(
                create: (_) => MorningProvider(MorningRepository(),
                    dailyRepo: DailyHealthRepository())),
            ChangeNotifierProvider(
                create: (_) =>
                    EveningProvider(EveningRepository())),
            ChangeNotifierProvider(create: (_) => ActionCenterProvider()),
            ChangeNotifierProvider(
                create: (_) =>
                    DailyHealthProvider(DailyHealthRepository())),
            ChangeNotifierProvider(
                create: (_) =>
                    DashboardProvider(DailyHealthRepository())),
            ChangeNotifierProvider(
                create: (_) =>
                    ExperimentProvider(ExperimentRepository())),
          ],
          child: MaterialApp(home: Scaffold(body: child)),
        );

    testWidgets('morning flow saves and shows summary', (tester) async {
      await tester.pumpWidget(wrap(const MorningScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Morning check-in'), findsOneWidget);
      await tester.tap(find.text('Save check-in'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Good morning.'), findsOneWidget);
      expect(find.text("Go to today's health screen"), findsOneWidget);

      // Repeated opening shows the saved summary, not a blank form.
      await tester.pumpWidget(wrap(const MorningScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Good morning.'), findsOneWidget);
    });

    testWidgets('evening flow saves and shows glance', (tester) async {
      await DailyHealthRepository().save(DailyHealthEntry(
          date: _todayKey(),
          sleepHours: 7.3,
          exerciseMinutes: 32,
          waterGlasses: 7,
          meditationMinutes: 10));
      await tester.pumpWidget(wrap(const EveningScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Save reflection'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Today at a glance'), findsOneWidget);
      expect(find.text('Wellness'), findsWidgets);
      expect(find.textContaining('based on your logged data'),
          findsOneWidget);
    });

    testWidgets('dashboard prompts missing routine items', (tester) async {
      await tester.pumpWidget(wrap(const DashboardScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Start your morning check-in'), findsOneWidget);
    });

    testWidgets('morning screen dark mode renders', (tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(
              create: (_) => MorningProvider(MorningRepository(),
                  dailyRepo: DailyHealthRepository())),
          ChangeNotifierProvider(
              create: (_) => EveningProvider(EveningRepository())),
          ChangeNotifierProvider(
              create: (_) =>
                  DailyHealthProvider(DailyHealthRepository())),
          ChangeNotifierProvider(
              create: (_) =>
                  DashboardProvider(DailyHealthRepository())),
          ChangeNotifierProvider(
              create: (_) =>
                  ExperimentProvider(ExperimentRepository())),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: const Scaffold(body: MorningScreen()),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  });
}
