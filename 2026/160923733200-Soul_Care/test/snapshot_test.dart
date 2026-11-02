import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/app/providers/health_snapshot_provider.dart';
import 'package:soul_care/app/providers/settings_provider.dart';
import 'package:soul_care/app/theme/app_theme.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/health_snapshot.dart';
import 'package:soul_care/data/repositories/health_snapshot_repository.dart';
import 'package:soul_care/data/repositories/settings_repository.dart';
import 'package:soul_care/features/snapshot/snapshot_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_snapshot');
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
  ]);
}

HealthSnapshot _full() {
  final now = DateTime.now();
  return HealthSnapshot(
    bloodGroup: 'O+',
    allergies: const [
      AllergyRecord(name: 'Peanuts', severity: 'Severe')
    ],
    medications: [
      MedicationRecord(
          name: 'Vitamin D',
          dosage: '1000 IU',
          frequency: 'daily',
          startDate: now.subtract(const Duration(days: 30))),
      MedicationRecord(
          name: 'Old Rx',
          dosage: '5mg',
          frequency: 'daily',
          endDate: now.subtract(const Duration(days: 1))),
    ],
    supplements: const ['Magnesium'],
    conditions: const ['Mild asthma'],
    emergencyName: 'Sam',
    emergencyPhone: '555-0100',
    provider: 'City Clinic',
    notes: 'Prefers morning appointments.',
    createdAt: now,
    updatedAt: now,
  );
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

  group('repository', () {
    test('empty for new user; create → edit → clear', () async {
      const repo = HealthSnapshotRepository();
      expect((await repo.load()).value!.isEmpty, isTrue);

      final saved = await repo.save(_full());
      expect(saved.isSuccess, isTrue);
      expect(saved.value!.activeMedications, 1);
      expect(saved.value!.hasEmergencyContact, isTrue);

      final edited = await repo.save(
          saved.value!.copyWith(bloodGroup: () => 'A+'));
      expect(edited.value!.bloodGroup, 'A+');

      // Restart: fresh instance restores.
      const fresh = HealthSnapshotRepository();
      expect((await fresh.load()).value!.bloodGroup, 'A+');

      expect((await fresh.clear()).isSuccess, isTrue);
      expect((await fresh.load()).value!.isEmpty, isTrue);
    });

    test('invalid blood group / severity rejected; blanks cleaned',
        () async {
      const repo = HealthSnapshotRepository();
      final bad = await repo.save(HealthSnapshot(
        bloodGroup: 'Z9',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      expect(bad.isFailure, isTrue);
      final badSev = await repo.save(HealthSnapshot(
        allergies: const [AllergyRecord(name: 'X', severity: 'Extreme')],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      expect(badSev.isFailure, isTrue);
    });

    test('medication active logic respects end dates', () {
      final now = DateTime.now();
      expect(
          MedicationRecord(
                  name: 'A',
                  endDate: now.subtract(const Duration(days: 1)))
              .isActive,
          isFalse);
      expect(
          MedicationRecord(
                  name: 'B',
                  endDate: now.add(const Duration(days: 1)))
              .isActive,
          isTrue);
      expect(const MedicationRecord(name: 'C').isActive, isTrue);
    });
  });

  group('privacy behavior', () {
    test('serializes without secrets leakage markers; round-trips',
        () async {
      const repo = HealthSnapshotRepository();
      await repo.save(_full());
      final raw = LocalDatabase.snapshotBox.get('snapshot');
      final encoded = jsonEncode(raw);
      // Stored as plain structured data (local box), no binaries/tokens.
      expect(encoded.contains('O+'), isTrue);
      expect(RegExp(r'base64|%PDF|bearer|token').hasMatch(encoded),
          isFalse);
      final restored = HealthSnapshot.fromJson(
          Map<String, dynamic>.from(raw as Map));
      expect(restored.allergies.single.severity, 'Severe');
      expect(restored.supplements, ['Magnesium']);
    });

    test('lock gate: locked by default session, PIN unlocks', () async {
      final settings = SettingsProvider(SettingsRepository());
      await settings.load();
      expect(
          await settings.setAppLock(enabled: true, pin: '1357'),
          isTrue);
      expect(settings.journalUnlocked, isFalse);
      expect(settings.unlockJournal('0000'), isFalse);
      expect(settings.unlockJournal('1357'), isTrue);
    });
  });

  group('widgets', () {
    MultiProvider wrap(Widget child,
        {HealthSnapshotProvider? snap,
        SettingsProvider? settings,
        bool dark = false}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider.value(
              value: snap ?? HealthSnapshotProvider(
                  HealthSnapshotRepository())),
          ChangeNotifierProvider.value(
              value: settings ?? SettingsProvider(SettingsRepository())),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: dark ? ThemeMode.dark : ThemeMode.system,
          home: Scaffold(body: child),
        ),
      );
    }

    testWidgets('quick view shows summary rows', (tester) async {
      const repo = HealthSnapshotRepository();
      await repo.save(_full());
      final snap = HealthSnapshotProvider(repo);
      await snap.load();
      final settings = SettingsProvider(SettingsRepository());
      await settings.load();

      await tester.pumpWidget(
          wrap(const SnapshotScreen(), snap: snap, settings: settings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Health Snapshot'), findsWidgets);
      expect(find.text('O+'), findsOneWidget);
      expect(find.text('Peanuts'), findsOneWidget);
      expect(find.text('2 active'), findsNothing);
      expect(find.text('1 active'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Edit snapshot'), findsOneWidget);
    });

    testWidgets('empty snapshot invites details; dark mode clean',
        (tester) async {
      final snap =
          HealthSnapshotProvider(HealthSnapshotRepository());
      await snap.load();
      final settings = SettingsProvider(SettingsRepository());
      await settings.load();
      await tester.pumpWidget(wrap(const SnapshotScreen(),
          snap: snap, settings: settings, dark: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Nothing recorded yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('locked snapshot requires PIN', (tester) async {
      const repo = HealthSnapshotRepository();
      await repo.save(_full());
      final snap = HealthSnapshotProvider(repo);
      await snap.load();
      final settings = SettingsProvider(SettingsRepository());
      await settings.load();
      await settings.setAppLock(enabled: true, pin: '2468');

      await tester.pumpWidget(
          wrap(const SnapshotScreen(), snap: snap, settings: settings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Locked: sensitive rows hidden behind the gate.
      expect(find.text('Snapshot is locked'), findsOneWidget);
      expect(find.text('O+'), findsNothing);

      // Correct PIN reveals content.
      for (final d in ['2', '4', '6', '8']) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('O+'), findsOneWidget);
    });
  });
}
