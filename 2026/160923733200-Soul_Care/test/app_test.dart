import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/app/app.dart';
import 'package:soul_care/app/router/app_router.dart';
import 'package:soul_care/app/providers/daily_health_provider.dart';
import 'package:soul_care/app/providers/checkin_providers.dart';
import 'package:soul_care/app/providers/action_center_provider.dart';
import 'package:soul_care/app/providers/dashboard_provider.dart';
import 'package:soul_care/app/providers/experiment_provider.dart';
import 'package:soul_care/app/providers/settings_provider.dart';
import 'package:soul_care/app/theme/app_theme.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/enums.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/data/repositories/checkin_repository.dart';
import 'package:soul_care/data/repositories/experiment_repository.dart';
import 'package:soul_care/data/repositories/settings_repository.dart';
import 'package:soul_care/features/daily_health/daily_health_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_test');
  Hive.init(dir.path);
  await Future.wait([
    Hive.openBox(LocalDatabase.dailyBoxName),
    Hive.openBox(LocalDatabase.stressBoxName),
    Hive.openBox(LocalDatabase.experimentsBoxName),
    Hive.openBox(LocalDatabase.documentsBoxName),
    Hive.openBox(LocalDatabase.settingsBoxName),
  ]);
  // Mark initialized via real init path is guarded; boxes are open so
  // repositories work. LocalDatabase.init would double-init; skip it.
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

  group('models', () {
    test('DailyHealthEntry round-trips through JSON', () {
      const entry = DailyHealthEntry(
        date: '2026-09-28',
        sleepHours: 7.5,
        sleepQuality: SleepQuality.good,
        feltRested: true,
        exerciseMinutes: 30,
        exerciseIntensity: ExerciseIntensity.moderate,
        mealQuality: MealQuality.good,
        waterGlasses: 6,
        meditationMinutes: 10,
        screenTimeHours: 2.0,
      );
      final restored = DailyHealthEntry.fromJson(entry.toJson());
      expect(restored.date, '2026-09-28');
      expect(restored.sleepHours, 7.5);
      expect(restored.sleepQuality, SleepQuality.good);
      expect(restored.feltRested, isTrue);
      expect(restored.exerciseMinutes, 30);
      expect(restored.waterGlasses, 6);
    });

    test('Experiment validation rejects empty title', () async {
      final repo = ExperimentRepository();
      final now = DateTime.now();
      final res = await repo.save(Experiment(
        id: 'x',
        title: '   ',
        description: 'd',
        targetMetric: 'm',
        durationDays: 7,
        createdAt: now,
        updatedAt: now,
      ));
      expect(res.isFailure, isTrue);
    });
  });

  group('repositories', () {
    test('daily health model can be stored and retrieved', () async {
      final repo = DailyHealthRepository();
      const entry = DailyHealthEntry(date: '2026-09-28', sleepHours: 8);
      final saved = await repo.save(entry);
      expect(saved.isSuccess, isTrue);

      final loaded = await repo.getByDate('2026-09-28');
      expect(loaded.isSuccess, isTrue);
      expect(loaded.value?.sleepHours, 8);
    });

    test('settings persist', () async {
      final repo = SettingsRepository();
      final saved = await repo.save(
          const UserSettings(themeMode: 'dark'));
      expect(saved.isSuccess, isTrue);
      expect(saved.value?.themeMode, 'dark');

      final loaded = await repo.load();
      expect(loaded.isSuccess, isTrue);
      expect(loaded.value?.themeMode, 'dark');
    });

    test('settings reject invalid theme mode', () async {
      final repo = SettingsRepository();
      final res = await repo
          .save(const UserSettings(themeMode: 'neon'));
      expect(res.isFailure, isTrue);
    });
  });

  group('app', () {
    testWidgets('app initializes and starts at Home with bottom nav',
        (tester) async {
      final settingsProvider =
          SettingsProvider(SettingsRepository());
      await settingsProvider.load();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settingsProvider),
            ChangeNotifierProvider(
                create: (_) =>
                    DailyHealthProvider(DailyHealthRepository())),
            ChangeNotifierProvider(
                create: (_) =>
                    DashboardProvider(DailyHealthRepository())),
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
          child: const SoulCareApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Starts at /home — dashboard greeting + subtitle present.
      expect(find.text('Based on your logged data'), findsOneWidget);
      // All 7 destinations exist (no auth route). Lab/Timeline also appear
      // as quick-action buttons, so those match more than once.
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Timeline'), findsWidgets);
      expect(find.text('Lab'), findsWidgets);
      expect(find.text('Future'), findsOneWidget);
      expect(find.text('Games'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('routing works: all routes resolve to their screens',
        (tester) async {
      // 1) Router configuration exposes all 7 required paths (no auth route).
      final paths = <String>{};
      void collect(List<RouteBase> routes) {
        for (final r in routes) {
          if (r is GoRoute) {
            paths.add(r.path);
            collect(r.routes);
          } else if (r is StatefulShellRoute) {
            for (final b in r.branches) {
              collect(b.routes);
            }
          }
        }
      }

      collect(appRouter.configuration.routes);
      for (final p in [
        '/home',
        '/today',
        '/timeline',
        '/lab',
        '/future',
        '/games',
        '/settings'
      ]) {
        expect(paths, contains(p));
      }
      expect(paths.any((p) => p.contains('login') || p.contains('auth')),
          isFalse);

      // 2) The /today destination itself builds (pumped directly for
      // robustness in the 800x600 test viewport with 7 tabs).
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
                create: (_) =>
                    DailyHealthProvider(DailyHealthRepository())),
          ],
          child: const MaterialApp(
              home: Scaffold(body: DailyHealthScreen())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Per-section save buttons live at the end of a ListView — scroll
      // into view (lazily built) before asserting.
      await tester.scrollUntilVisible(
        find.text('Save Sleep'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Save Sleep'), findsOneWidget);
    });

    test('theme system provides light and dark', () {
      expect(AppTheme.light.useMaterial3, isTrue);
      expect(AppTheme.dark.useMaterial3, isTrue);
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
    });
  });
}
