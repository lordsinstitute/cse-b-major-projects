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
import 'package:soul_care/app/providers/profile_provider.dart';
import 'package:soul_care/app/providers/settings_provider.dart';
import 'package:soul_care/app/theme/app_theme.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/models/user_profile.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/data/repositories/checkin_repository.dart';
import 'package:soul_care/data/repositories/experiment_repository.dart';
import 'package:soul_care/data/repositories/profile_repository.dart';
import 'package:soul_care/data/repositories/settings_repository.dart';
import 'package:soul_care/features/dashboard/dashboard_screen.dart';
import 'package:soul_care/features/experiments/experiment_engine.dart';
import 'package:soul_care/features/experiments/experiment_templates.dart';
import 'package:soul_care/features/profile/goal_progress.dart';
import 'package:soul_care/features/profile/profile_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_profile');
  Hive.init(dir.path);
  await Future.wait([
    Hive.openBox(LocalDatabase.dailyBoxName),
    Hive.openBox(LocalDatabase.stressBoxName),
    Hive.openBox(LocalDatabase.experimentsBoxName),
    Hive.openBox(LocalDatabase.documentsBoxName),
    Hive.openBox(LocalDatabase.settingsBoxName),
    Hive.openBox(LocalDatabase.gameStatsBoxName),
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

  group('model', () {
    test('fresh profile is unset with healthy defaults', () {
      final p = UserProfile.fresh();
      expect(p.isUnset, isTrue);
      expect(p.sleepGoal, 7.5);
      expect(p.waterGoal, 8);
      expect(p.exerciseGoalWeek, 150);
      expect(p.meditationGoal, 10);
      expect(p.primaryFocus, WellnessFocus.general);
      expect(p.profileVersion, UserProfile.currentVersion);
      expect(p.updatedAt.isAfter(p.createdAt) ||
          p.updatedAt.isAtSameMomentAs(p.createdAt), isTrue);
    });

    test('round-trips through JSON incl. timestamps', () {
      final p = UserProfile.fresh().copyWith(
        displayName: () => 'Ava',
        ageRange: () => '30–39',
        wakeTime: () => '06:30',
        primaryFocus: WellnessFocus.betterSleep,
        secondaryFocus: () => WellnessFocus.hydration,
      );
      final restored = UserProfile.fromJson(p.toJson());
      expect(restored.displayName, 'Ava');
      expect(restored.ageRange, '30–39');
      expect(restored.primaryFocus, WellnessFocus.betterSleep);
      expect(restored.secondaryFocus, WellnessFocus.hydration);
      expect(restored.isUnset, isFalse);
      expect(
          restored.createdAt
              .difference(p.createdAt)
              .inMilliseconds
              .abs(),
          lessThan(1000));
    });

    test('legacy/partial payloads migrate non-destructively', () {
      final legacy = UserProfile.fromJson({
        'displayName': '  Bo  ',
        // no version, no timestamps, no goals
      });
      expect(legacy.displayName, 'Bo');
      expect(legacy.sleepGoal, 7.5);
      expect(legacy.profileVersion, UserProfile.currentVersion);

      final unknownFocus = UserProfile.fromJson({'primaryFocus': 'telepathy'});
      expect(unknownFocus.primaryFocus, WellnessFocus.general);
    });

    test('nullable fields can be cleared via copyWith', () {
      final p = UserProfile.fresh()
          .copyWith(displayName: () => 'Ava', wakeTime: () => '07:00');
      final cleared = p.copyWith(
          displayName: () => null, wakeTime: () => null);
      expect(cleared.displayName, isNull);
      expect(cleared.wakeTime, isNull);
      expect(cleared.isUnset, isTrue);
    });
  });

  group('repository', () {
    test('new user gets defaults + timestamps', () async {
      final res = await ProfileRepository().load();
      expect(res.isSuccess, isTrue);
      expect(res.value!.isUnset, isTrue);
    });

    test('partial profile saves and survives restart', () async {
      final repo = ProfileRepository();
      final base = (await repo.load()).value!;
      final saved = await repo.save(base.copyWith(
        displayName: () => 'Ava',
        waterGoal: 10,
      ));
      expect(saved.isSuccess, isTrue);
      expect(saved.value!.displayName, 'Ava');

      // Simulate app restart.
      final fresh = ProfileRepository();
      final reloaded = await fresh.load();
      expect(reloaded.value!.displayName, 'Ava');
      expect(reloaded.value!.waterGoal, 10);
      expect(reloaded.value!.sleepGoal, 7.5); // untouched default
    });

    test('edited goals persist; invalid values rejected', () async {
      final repo = ProfileRepository();
      final base = (await repo.load()).value!;
      final ok = await repo.save(base.copyWith(
        sleepGoal: 8.0,
        exerciseGoalWeek: 200,
        meditationGoal: 15,
      ));
      expect(ok.isSuccess, isTrue);
      expect(ok.value!.sleepGoal, 8.0);

      expect((await repo.save(base.copyWith(exactAge: () => 200))).isFailure,
          isTrue);
      expect(
          (await repo.save(base.copyWith(wakeTime: () => '25:00')))
              .isFailure,
          isTrue);
      expect(
          (await repo.save(base.copyWith(waterGoal: 99))).isFailure,
          isTrue);
      expect(
          (await repo.save(base.copyWith(
            primaryFocus: WellnessFocus.hydration,
            secondaryFocus: () => WellnessFocus.hydration,
          )))
              .isFailure,
          isTrue);
    });

    test('legacy reminder time adopted once', () async {
      await SettingsRepository().save(
          const UserSettings(dailyReminderTime: '21:15'));
      final loaded = await ProfileRepository().load();
      expect(loaded.value!.reminderTime, '21:15');
    });
  });

  group('goal progress math', () {
    test('current/target/percent/remaining from example', () {
      final g = computeGoalProgress(
        label: 'Sleep Goal',
        weekValues: const [7.0, 7.2],
        target: 7.5,
        unit: 'h',
      );
      expect(g.current, closeTo(7.1, 0.01));
      expect(g.percent, 95);
      expect(g.remaining, closeTo(0.4, 0.01));
      expect(g.fraction, closeTo(0.95, 0.01));
    });

    test('unlogged days never rewarded; empty is zero + unknown trend', () {
      final empty = computeGoalProgress(
          label: 'x', weekValues: const [], target: 8, unit: '');
      expect(empty.current, 0);
      expect(empty.percent, 0);
      expect(empty.remaining, 8);
      expect(empty.trend, GoalTrend.unknown);
    });

    test('weekly sums use totals; trend from halves', () {
      final g = computeGoalProgress(
        label: 'Exercise Goal',
        weekValues: const [10, 10, 10, 40, 40, 40],
        target: 150,
        unit: ' min',
        sumInsteadOfAverage: true,
      );
      expect(g.current, 150);
      expect(g.percent, 100);
      expect(g.remaining, 0);
      expect(g.trend, GoalTrend.up);
    });
  });

  group('focus ordering', () {
    GoalProgress mk(double fraction) => GoalProgress(
        label: 'g',
        current: fraction * 100,
        target: 100,
        unit: '',
        trend: GoalTrend.steady);

    test('focus match first, rest by completion; reasons intact', () {
      final goals = [('sleep', mk(0.9)), ('water', mk(0.2))];
      final ordered = orderGoalsForFocus(goals, 'water');
      expect(ordered.first.$1, 'water');
      expect(ordered.last.$1, 'sleep');

      final general = orderGoalsForFocus(goals, null);
      expect(general.first.$1, 'water'); // lowest completion first

      expect(goalKeyForFocusName('betterSleep'), 'sleep');
      expect(goalKeyForFocusName('general'), isNull);
      expect(templateForFocusName('hydration'), 'hydration');
      expect(templateForFocusName('general'), isNull);
    });

    test('lab ordering keeps data reasons, moves focus match first', () {
      final recs = [
        ExperimentRecommendation(
            template: experimentTemplates[0], reason: 'sleep reason'),
        ExperimentRecommendation(
            template: experimentTemplates[3], reason: 'water reason'),
      ];
      final sorted = sortByFocus(recs, 'hydration');
      expect(sorted.first.template.id, 'hydration');
      expect(sorted.first.reason, 'water reason');
    });
  });

  group('provider', () {
    test('load → save → reload keeps edits', () async {
      final p = ProfileProvider(ProfileRepository());
      await p.load();
      expect(p.isUnset, isTrue);
      expect(
          await p.save(p.profile!.copyWith(
            displayName: () => 'Bo',
            primaryFocus: WellnessFocus.moreMovement,
          )),
          isTrue);
      expect(p.isUnset, isFalse);

      final restarted = ProfileProvider(ProfileRepository());
      await restarted.load();
      expect(restarted.profile!.displayName, 'Bo');
      expect(restarted.profile!.primaryFocus,
          WellnessFocus.moreMovement);
    });
  });

  group('widgets', () {
    MultiProvider wrap(Widget child,
        {ProfileProvider? profile,
        SettingsProvider? settings,
        bool dark = false}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider.value(
              value: profile ?? ProfileProvider(ProfileRepository())),
          ChangeNotifierProvider.value(
              value: settings ?? SettingsProvider(SettingsRepository())),
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
              create: (_) => MorningProvider(MorningRepository())),
          ChangeNotifierProvider(
              create: (_) => EveningProvider(EveningRepository())),
          ChangeNotifierProvider(create: (_) => ActionCenterProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: dark ? ThemeMode.dark : ThemeMode.system,
          home: Scaffold(body: child),
        ),
      );
    }

    testWidgets('profile form renders, saves, dark mode', (tester) async {
      final profile = ProfileProvider(ProfileRepository());
      await profile.load();
      final settings = SettingsProvider(SettingsRepository());
      await settings.load();
      await tester.pumpWidget(
          wrap(const ProfileScreen(), profile: profile, settings: settings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Primary wellness focus'), findsOneWidget);
      expect(find.text('Personal targets (editable any time)'),
          findsOneWidget);
      await tester.enterText(
          find.byType(TextField).first, 'Ava');
      await tester.tap(find.text('Save profile'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(profile.profile!.displayName, 'Ava');

      // Dark mode renders without errors.
      await tester.pumpWidget(wrap(const ProfileScreen(),
          profile: profile, settings: settings, dark: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('dashboard shows focus-ordered goal strip', (tester) async {
      final now = DateTime.now();
      await DailyHealthRepository().save(DailyHealthEntry(
          date: _key(now.subtract(const Duration(days: 1))),
          sleepHours: 8,
          waterGlasses: 8,
          exerciseMinutes: 30,
          meditationMinutes: 10));
      await DailyHealthRepository().save(DailyHealthEntry(
          date: _key(now),
          sleepHours: 8,
          waterGlasses: 2,
          exerciseMinutes: 30,
          meditationMinutes: 10));
      final profile = ProfileProvider(ProfileRepository());
      await profile.load();
      await profile.save(profile.profile!.copyWith(
        primaryFocus: WellnessFocus.hydration,
      ));

      await tester.pumpWidget(wrap(const DashboardScreen(),
          profile: profile,
          settings: SettingsProvider(SettingsRepository())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('My goals', skipOffstage: false), findsOneWidget);
      expect(find.text('Water Goal', skipOffstage: false), findsOneWidget);
      expect(find.text('Sleep Goal', skipOffstage: false), findsOneWidget);
      // Hydration focus orders the water goal first.
      final waterDy =
          tester.getTopLeft(find.text('Water Goal', skipOffstage: false)).dy;
      final sleepDy =
          tester.getTopLeft(find.text('Sleep Goal', skipOffstage: false)).dy;
      expect(waterDy, lessThan(sleepDy));
    });

    testWidgets('empty profile never blocks the app', (tester) async {
      final profile = ProfileProvider(ProfileRepository());
      await profile.load();
      expect(profile.isUnset, isTrue);
      await tester.pumpWidget(wrap(const DashboardScreen(),
          profile: profile,
          settings: SettingsProvider(SettingsRepository())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('No data yet'), findsWidgets);
      expect(find.text('Log your first day'), findsOneWidget);
    });
  });
}
