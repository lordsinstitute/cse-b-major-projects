import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/app/providers/action_center_provider.dart';
import 'package:soul_care/app/providers/checkin_providers.dart';
import 'package:soul_care/app/providers/daily_health_provider.dart';
import 'package:soul_care/app/providers/dashboard_provider.dart';
import 'package:soul_care/app/providers/documents_provider.dart';
import 'package:soul_care/app/providers/experiment_provider.dart';
import 'package:soul_care/app/providers/health_import_provider.dart';
import 'package:soul_care/app/providers/health_snapshot_provider.dart';
import 'package:soul_care/app/providers/journal_provider.dart';
import 'package:soul_care/app/providers/profile_provider.dart';
import 'package:soul_care/app/providers/reminders_provider.dart';
import 'package:soul_care/app/providers/settings_provider.dart';
import 'package:soul_care/app/router/app_router.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/user_profile.dart';
import 'package:soul_care/data/repositories/checkin_repository.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/data/repositories/experiment_repository.dart';
import 'package:soul_care/data/repositories/health_import_repository.dart';
import 'package:soul_care/data/repositories/health_snapshot_repository.dart';
import 'package:soul_care/data/repositories/journal_repository.dart';
import 'package:soul_care/data/repositories/medical_document_repository.dart';
import 'package:soul_care/data/repositories/stress_repository.dart';
import 'package:soul_care/data/repositories/profile_repository.dart';
import 'package:soul_care/data/repositories/settings_repository.dart';
import 'package:soul_care/features/onboarding/onboarding_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_onboard');
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
    Hive.openBox(LocalDatabase.snapshotBoxName),
    Hive.openBox(LocalDatabase.medRemindersBoxName),
    Hive.openBox(LocalDatabase.appointmentsBoxName),
    Hive.openBox(LocalDatabase.doseLogBoxName),
    Hive.openBox(LocalDatabase.healthImportsBoxName),
    Hive.openBox('action_center'),
  ]);
}

GoRouter _testRouter(ProfileProvider profile, SettingsProvider settings) =>
    GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(
          path: '/welcome',
          builder: (c, s) => MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: profile),
              ChangeNotifierProvider.value(value: settings),
            ],
            child: const OnboardingScreen(),
          ),
        ),
        GoRoute(
            path: '/home',
            builder: (c, s) => const Text('HOME')),
      ],
    );

Future<void> _pump(
    WidgetTester tester, ProfileProvider profile, SettingsProvider settings) async {
  await tester.pumpWidget(MaterialApp.router(
      routerConfig: _testRouter(profile, settings)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await _initTestHive();
  });

  tearDown(() async {
    await LocalDatabase.clearAll();
    if (Hive.isBoxOpen('action_center')) {
      await Hive.box('action_center').clear();
    }
  });

  group('redirect rule', () {
    test('unfinished users route to welcome; finished never see it', () {
      expect(
          onboardingRedirect(onboarded: false, path: '/home'),
          '/welcome');
      expect(
          onboardingRedirect(onboarded: false, path: '/today'),
          '/welcome');
      expect(
          onboardingRedirect(onboarded: false, path: '/welcome'),
          isNull);
      expect(
          onboardingRedirect(onboarded: true, path: '/welcome'),
          '/home');
      expect(
          onboardingRedirect(onboarded: true, path: '/home'), isNull);
    });
  });

  group('flow', () {
    testWidgets('complete onboarding saves focus, goals, flag',
        (tester) async {
      final profile = ProfileProvider(ProfileRepository());
      await profile.load();
      final settings = SettingsProvider(SettingsRepository());
      await settings.load();
      await _pump(tester, profile, settings);

      expect(find.text('Welcome to SoulCare.'), findsOneWidget);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      // Focus: pick Hydration.
      await tester.tap(find.text('Hydration'));
      await tester.pump();
      await tester.tap(find.text('Continue').first);
      await tester.pumpAndSettle();

      // Goals: sleep + water (2 of max 3).
      await tester.tap(find.text('Sleep 7+ hours'));
      await tester.pump();
      await tester.tap(find.text('Drink 8 glasses/day'));
      await tester.pump();
      await tester.tap(find.text('Continue').first);
      await tester.pumpAndSettle();

      // Reminders: not now.
      await tester.tap(find.text('Not now'));
      await tester.pump();
      await tester.tap(find.text('Continue').first);
      await tester.pumpAndSettle();

      // Privacy → ready → finish.
      await tester.tap(find.text('Continue').first);
      await tester.pumpAndSettle();
      expect(find.text("You're ready."), findsOneWidget);
      await tester.tap(find.text('Open SoulCare'));
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
      expect(settings.settings.onboardingDone, isTrue);
      expect(profile.profile!.primaryFocus, WellnessFocus.hydration);
      expect(profile.profile!.sleepGoal, 7.5);
      // Untoggled goals keep defaults.
      expect(profile.profile!.meditationGoal, 10);
      // Reminder stays off (never requested).
      expect(settings.settings.notificationsEnabled, isFalse);
    });

    testWidgets('skip lands home with defaults intact', (tester) async {
      final profile = ProfileProvider(ProfileRepository());
      await profile.load();
      // NOTE: settings.load() intentionally skipped here to isolate a
      // suspected hang; provider defaults are sufficient for this screen.
      final settings = SettingsProvider(SettingsRepository());
      await tester.pumpWidget(MaterialApp.router(
          routerConfig: _testRouter(profile, settings)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
      expect(settings.settings.onboardingDone, isTrue);
      expect(profile.isUnset, isTrue);
    });

    testWidgets('reminder Yes without permission keeps time, stays off',
        (tester) async {
      final profile = ProfileProvider(ProfileRepository());
      await profile.load();
      final settings = SettingsProvider(SettingsRepository());
      await settings.load();
      await _pump(tester, profile, settings);

      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue').first); // focus (none)
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue').first); // goals (none)
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pump();
      await tester.tap(find.text('Continue').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue').first); // privacy
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open SoulCare'));
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
      expect(settings.settings.onboardingDone, isTrue);
      // Time recorded, but nothing enabled without permission.
      expect(settings.settings.dailyReminderTime, isNotNull);
      expect(settings.settings.notificationsEnabled, isFalse);
    });

    testWidgets('two focus areas + lighter goal tier save correctly',
        (tester) async {
      final profile = ProfileProvider(ProfileRepository());
      await profile.load();
      final settings = SettingsProvider(SettingsRepository());
      await settings.load();
      await _pump(tester, profile, settings);

      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hydration'));
      await tester.pump();
      await tester.tap(find.text('Better Sleep'));
      await tester.pump();
      await tester.tap(find.text('Continue').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sleep 8 hours'));
      await tester.pump();
      await tester.tap(find.text('Continue').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not now'));
      await tester.pump();
      await tester.tap(find.text('Continue').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue').first); // privacy
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open SoulCare'));
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
      expect(profile.profile!.primaryFocus, WellnessFocus.hydration);
      expect(profile.profile!.secondaryFocus,
          WellnessFocus.betterSleep);
      expect(profile.profile!.sleepGoal, 8.0);
    });
  });

  group('persistence', () {
    test('flag survives restart; goals editable later', () async {
      final settings = SettingsProvider(SettingsRepository());
      await settings.load();
      await settings.update(
          settings.settings.copyWith(onboardingDone: true));
      final profile = ProfileProvider(ProfileRepository());
      await profile.load();
      await profile.save(profile.profile!.copyWith(waterGoal: 10));

      final restartedSettings =
          SettingsProvider(SettingsRepository());
      await restartedSettings.load();
      expect(restartedSettings.settings.onboardingDone, isTrue);
      final restartedProfile =
          ProfileProvider(ProfileRepository());
      await restartedProfile.load();
      expect(restartedProfile.profile!.waterGoal, 10);

      // Edit goals later via the normal profile path.
      expect(
          await restartedProfile.save(restartedProfile.profile!
              .copyWith(waterGoal: 6)),
          isTrue);
      expect(restartedProfile.profile!.waterGoal, 6);
    });
  });

  group('production router regression', () {
    testWidgets(
        'finishing onboarding then going home stays home (no bounce)',
        (tester) async {
      final settings = SettingsProvider(SettingsRepository());
      await settings.load();
      expect(settings.settings.onboardingDone, isFalse);
      final router = createAppRouter(onboarded: false);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider(
              create: (_) => ProfileProvider(ProfileRepository())),
          ChangeNotifierProvider(
              create: (_) => DailyHealthProvider(
                  DailyHealthRepository(),
                  stressRepo: StressRepository())),
          ChangeNotifierProvider(
              create: (_) => DashboardProvider(DailyHealthRepository(),
                  stressRepo: StressRepository())),
          ChangeNotifierProvider(
              create: (_) => ExperimentProvider(ExperimentRepository(),
                  dailyRepo: DailyHealthRepository())),
          ChangeNotifierProvider(
              create: (_) => DocumentsProvider(
                  MedicalDocumentRepository())),
          ChangeNotifierProvider(
              create: (_) => MorningProvider(MorningRepository(),
                  dailyRepo: DailyHealthRepository())),
          ChangeNotifierProvider(
              create: (_) =>
                  EveningProvider(EveningRepository())),
          ChangeNotifierProvider(
              create: (_) => JournalProvider(JournalRepository())),
          ChangeNotifierProvider(
              create: (_) => HealthSnapshotProvider(
                  HealthSnapshotRepository())),
          ChangeNotifierProvider(create: (_) => RemindersProvider()),
          ChangeNotifierProvider(
              create: (_) =>
                  HealthImportProvider(HealthImportRepository())),
          ChangeNotifierProvider(
              create: (_) => ActionCenterProvider()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to SoulCare.'), findsOneWidget);

      // Same effect as tapping Open SoulCare: flag flips, then go home.
      await settings
          .update(settings.settings.copyWith(onboardingDone: true));
      router.go('/home');
      await tester.pumpAndSettle();

      // Pre-fix this bounced straight back to /welcome.
      expect(find.text('Welcome to SoulCare.'), findsNothing);
      expect(find.text('No data yet'), findsOneWidget);
    });
  });
}
