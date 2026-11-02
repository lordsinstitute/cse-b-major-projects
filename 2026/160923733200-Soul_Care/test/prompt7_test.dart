import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:soul_care/app/providers/daily_health_provider.dart';
import 'package:soul_care/app/providers/dashboard_provider.dart';
import 'package:soul_care/app/providers/documents_provider.dart';
import 'package:soul_care/app/providers/experiment_provider.dart';
import 'package:soul_care/app/providers/health_import_provider.dart';
import 'package:soul_care/app/providers/settings_provider.dart';
import 'package:soul_care/core/constants/app_constants.dart';
import 'package:soul_care/core/notifications/notification_service.dart';
import 'package:soul_care/data/export/data_deletion.dart';
import 'package:soul_care/data/export/data_export.dart';
import 'package:soul_care/data/local/document_storage.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/enums.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/data/repositories/experiment_repository.dart';
import 'package:soul_care/data/repositories/health_import_repository.dart';
import 'package:soul_care/data/repositories/medical_document_repository.dart';
import 'package:soul_care/data/repositories/settings_repository.dart';
import 'package:soul_care/data/repositories/stress_repository.dart';
import 'package:soul_care/features/settings/settings_appearance.dart';
import 'package:soul_care/features/settings/settings_data.dart';
import 'package:soul_care/features/settings/settings_privacy.dart';
import 'package:soul_care/features/settings/settings_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_p7');
  Hive.init(dir.path);
  await Future.wait([
    Hive.openBox(LocalDatabase.dailyBoxName),
    Hive.openBox(LocalDatabase.stressBoxName),
    Hive.openBox(LocalDatabase.experimentsBoxName),
    Hive.openBox(LocalDatabase.documentsBoxName),
    Hive.openBox(LocalDatabase.settingsBoxName),
    Hive.openBox(LocalDatabase.gameStatsBoxName),
    Hive.openBox(LocalDatabase.healthImportsBoxName),
  ]);
}

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<void> _seedAll() async {
  final now = DateTime.now();
  await DailyHealthRepository().save(
      DailyHealthEntry(date: _key(now), sleepHours: 7));
  await StressRepository().save(StressEntry(
      id: 's1', date: _key(now), mood: Mood.okay, createdAt: now));
  await ExperimentRepository().save(Experiment(
    id: 'e1',
    title: 'Test',
    description: 'd',
    targetMetric: 'm',
    durationDays: 7,
    createdAt: now,
    updatedAt: now,
  ));
  final vault = await Directory.systemTemp.createTemp('soulcare_p7vault');
  final src = File('${vault.path}/seed.pdf');
  await src.writeAsBytes('%PDF-1.4\n%EOF\n'.codeUnits, flush: true);
  final repo = MedicalDocumentRepository(
      storage: DocumentStorage(testDir: vault));
  await repo.importPickedFiles(
      [(sourcePath: src.path, originalName: 'seed.pdf')]);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await _initTestHive();
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('UTC'));
  });

  tearDown(() async {
    await LocalDatabase.clearAll();
  });

  group('appearance', () {
    test('theme choice persists across loads', () async {
      final repo = SettingsRepository();
      final p = SettingsProvider(repo);
      await p.load();
      expect(p.themeMode, ThemeMode.system);
      expect(await p.update(const UserSettings(themeMode: 'dark')),
          isTrue);
      expect(p.themeMode, ThemeMode.dark);

      final reloaded = SettingsProvider(SettingsRepository());
      await reloaded.load();
      expect(reloaded.themeMode, ThemeMode.dark);

      expect(await reloaded.update(const UserSettings(themeMode: 'light')),
          isTrue);
      expect(reloaded.themeMode, ThemeMode.light);
    });

    test('palette, zoom, font style and size persist (clamped)', () async {
      final repo = SettingsRepository();
      final p = SettingsProvider(repo);
      await p.load();
      expect(
          await p.update(const UserSettings(
            colorSeed: 0xFF6D5BA4,
            uiZoom: 1.5,
            fontFamily: 'Nunito',
            fontScale: 1.2,
          )),
          isTrue);
      expect(p.settings.colorSeed, 0xFF6D5BA4);
      expect(p.settings.uiZoom, 1.5);
      expect(p.settings.fontFamily, 'Nunito');
      expect(p.settings.fontScale, 1.2);

      final reloaded = SettingsProvider(SettingsRepository());
      await reloaded.load();
      expect(reloaded.settings.colorSeed, 0xFF6D5BA4);
      expect(reloaded.settings.fontFamily, 'Nunito');

      // Out-of-range values clamp on read (never break layout).
      expect(
          await reloaded.update(const UserSettings(
              uiZoom: 9.0, fontScale: 0.1)),
          isTrue);
      final reread = SettingsProvider(SettingsRepository());
      await reread.load();
      expect(reread.settings.uiZoom, 2.0);
      expect(reread.settings.fontScale, 0.8);
    });

    test('reminder time parse/format round-trips; rejects garbage', () {
      expect(NotificationService.parseReminderTime('20:30'),
          const TimeOfDay(hour: 20, minute: 30));
      expect(NotificationService.formatReminderTime(
          const TimeOfDay(hour: 8, minute: 5)), '08:05');
      expect(NotificationService.parseReminderTime(null), isNull);
      expect(NotificationService.parseReminderTime('late'), isNull);
      expect(NotificationService.parseReminderTime('25:00'), isNull);
      expect(NotificationService.parseReminderTime('12:60'), isNull);
    });

    test('next daily occurrence is strictly in the future', () {
      // Build "now" in the same zone the scheduler uses (tz.local).
      final morning = tz.TZDateTime(tz.local, 2026, 9, 29, 8, 0);
      final laterToday = NotificationService.nextDailyOccurrence(
          morning, const TimeOfDay(hour: 20, minute: 0));
      expect(laterToday.day, 29);
      expect(laterToday.hour, 20);

      final evening = tz.TZDateTime(tz.local, 2026, 9, 29, 21, 0);
      final tomorrow = NotificationService.nextDailyOccurrence(
          evening, const TimeOfDay(hour: 20, minute: 0));
      expect(tomorrow.day, 30);

      final exact = NotificationService.nextDailyOccurrence(
          tz.TZDateTime(tz.local, 2026, 9, 29, 20, 0),
          const TimeOfDay(hour: 20, minute: 0));
      expect(exact.day, 30); // not now — tomorrow
    });
  });

  group('export', () {
    test('JSON export includes records, references docs, embeds no PDFs',
        () async {
      await _seedAll();
      final res = await DataExportService().buildExportMap();
      expect(res.isSuccess, isTrue);
      final map = res.value!;
      expect(map['app'], 'SoulCare');
      expect((map['dailyHealth'] as List).length, 1);
      expect((map['stressCheckIns'] as List).length, 1);
      expect((map['experiments'] as List).length, 1);
      final docs = map['medicalDocuments'] as List;
      expect(docs.length, 1);
      final doc = Map<String, dynamic>.from(docs.single as Map);
      expect(doc['fileName'], 'seed.pdf');
      expect(doc.containsKey('localPath'), isFalse);
      expect(doc.containsKey('contentHash'), isFalse);
      // Whole map must be plain JSON — and contain no binary blobs.
      final encoded = jsonEncode(map);
      expect(encoded.contains('seed.pdf'), isTrue);
      expect(RegExp(r'base64|bytes|%PDF').hasMatch(encoded), isFalse);
    });

    test('empty vault exports empty lists, still succeeds', () async {
      final res = await DataExportService().buildExportMap();
      expect(res.isSuccess, isTrue);
      expect((res.value!['dailyHealth'] as List), isEmpty);
    });
  });

  group('deletion', () {
    test('scoped deletes keep other categories intact', () async {
      await _seedAll();
      expect(
          (await DataDeletionService().deleteDailyHealth()).isSuccess,
          isTrue);
      expect(LocalDatabase.dailyBox.isEmpty, isTrue);
      expect(LocalDatabase.stressBox.isEmpty, isTrue);
      expect(LocalDatabase.experimentsBox.isNotEmpty, isTrue);
      expect(LocalDatabase.documentsBox.isNotEmpty, isTrue);

      expect(
          (await DataDeletionService().deleteExperiments()).isSuccess,
          isTrue);
      expect(LocalDatabase.experimentsBox.isEmpty, isTrue);
      expect(LocalDatabase.documentsBox.isNotEmpty, isTrue);
    });

    test('document deletion removes vault files too', () async {
      await _seedAll();
      final before = await MedicalDocumentRepository().getAll();
      final path = before.value!.single.localPath;
      expect(await File(path).exists(), isTrue);
      final res = await DataDeletionService().deleteDocuments();
      expect(res.isSuccess, isTrue);
      expect(res.value, 1);
      expect(await File(path).exists(), isFalse);
      expect(LocalDatabase.documentsBox.isEmpty, isTrue);
    });

    test('delete-everything wipes all boxes', () async {
      await _seedAll();
      expect(
          (await DataDeletionService().deleteEverything()).isSuccess,
          isTrue);
      for (final name in [
        LocalDatabase.dailyBoxName,
        LocalDatabase.stressBoxName,
        LocalDatabase.experimentsBoxName,
        LocalDatabase.documentsBoxName,
        LocalDatabase.gameStatsBoxName,
        LocalDatabase.settingsBoxName,
      ]) {
        expect(Hive.box(name).isEmpty, isTrue);
      }
    });
  });

  group('widgets', () {
    MultiProvider app(Widget child, SettingsProvider settings) =>
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
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
                    DocumentsProvider(MedicalDocumentRepository())),
            ChangeNotifierProvider(
                create: (_) =>
                    HealthImportProvider(HealthImportRepository())),
          ],
          child: MaterialApp(home: Scaffold(body: child)),
        );

    // Hub + sub-screens under a real (test) router, mirroring production.
    Widget routerApp(SettingsProvider settings) {
      final router = GoRouter(
        initialLocation: '/settings',
        routes: [
          GoRoute(
            path: '/settings',
            builder: (c, s) => const Scaffold(body: SettingsScreen()),
            routes: [
              GoRoute(
                  path: 'appearance',
                  builder: (c, s) => const AppearanceScreen()),
              GoRoute(
                  path: 'privacy',
                  builder: (c, s) => const PrivacyScreen()),
              GoRoute(
                  path: 'data',
                  builder: (c, s) => const DataScreen()),
            ],
          ),
        ],
      );
      return MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
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
                  DocumentsProvider(MedicalDocumentRepository())),
          ChangeNotifierProvider(
              create: (_) =>
                  HealthImportProvider(HealthImportRepository())),
        ],
        child: MaterialApp.router(routerConfig: router),
      );
    }

    testWidgets('settings hub lists grouped subsections', (tester) async {
      final settings = SettingsProvider(SettingsRepository());
      await settings.load();
      await tester.pumpWidget(routerApp(settings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      for (final title in [
        'Appearance',
        'Notifications',
        'Privacy lock',
        'Health data',
        'Privacy & About',
        'Data & backup',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
    });

    testWidgets('privacy subsection explains local-only handling',
        (tester) async {
      final settings = SettingsProvider(SettingsRepository());
      await settings.load();
      await tester.pumpWidget(routerApp(settings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Privacy Center'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          find.textContaining('Nothing, automatically',
              skipOffstage: false),
          findsOneWidget);
    });

    testWidgets('data subsection offers export + deletion', (tester) async {
      final settings = SettingsProvider(SettingsRepository());
      await settings.load();
      await tester.pumpWidget(routerApp(settings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Data & backup'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Export as JSON', skipOffstage: false),
          findsOneWidget);
      expect(find.text('Delete all local data', skipOffstage: false),
          findsOneWidget);
    });

    testWidgets('privacy screen combines about content', (tester) async {
      final settings = SettingsProvider(SettingsRepository());
      await settings.load();
      await tester.pumpWidget(routerApp(settings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Privacy & About'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          find.textContaining('SoulCare ${AppConstants.appVersion}',
              skipOffstage: false),
          findsOneWidget);
      expect(find.text('Permissions used, and why', skipOffstage: false),
          findsOneWidget);
    });

    testWidgets('appearance subsection: theme, palette, zoom, fonts',
        (tester) async {
      final settings = SettingsProvider(SettingsRepository());
      await settings.load();
      await tester.pumpWidget(routerApp(settings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Appearance'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(settings.themeMode, ThemeMode.system);
      await tester.tap(find.text('Dark'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(settings.themeMode, ThemeMode.dark);

      expect(find.text('Color palette'), findsOneWidget);
      expect(find.textContaining('Interface zoom'), findsOneWidget);
      await tester.tap(find.text('System default'));
      await tester.pump();
      expect(settings.settings.fontFamily, isNull);
    });
  });
}
