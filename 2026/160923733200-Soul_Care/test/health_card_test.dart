import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/app/providers/health_snapshot_provider.dart';
import 'package:soul_care/app/providers/profile_provider.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/health_snapshot.dart';
import 'package:soul_care/data/models/user_profile.dart';
import 'package:soul_care/data/repositories/health_snapshot_repository.dart';
import 'package:soul_care/data/repositories/profile_repository.dart';
import 'package:soul_care/features/health_card/health_card_engine.dart';
import 'package:soul_care/features/health_card/health_card_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_hc');
  Hive.init(dir.path);
  await Future.wait([
    Hive.openBox(LocalDatabase.snapshotBoxName),
    Hive.openBox(LocalDatabase.settingsBoxName),
  ]);
}

HealthSnapshot _fullSnapshot() {
  final now = DateTime(2026, 9, 30);
  return HealthSnapshot(
    bloodGroup: 'O+',
    allergies: const [
      AllergyRecord(name: 'Peanuts', severity: 'Severe'),
    ],
    medications: [
      MedicationRecord(name: 'Loratadine', dosage: '10mg', frequency: 'daily'),
      MedicationRecord(
          name: 'Old Course',
          endDate: DateTime(2020, 1, 1)),
    ],
    emergencyName: 'Jan Doe',
    emergencyPhone: '555-0100',
    provider: 'Dr. Rao',
    notes: 'Carry antihistamine.',
    createdAt: now,
    updatedAt: now,
  );
}

const Set<HealthCardField> _all = {
  HealthCardField.name,
  HealthCardField.bloodGroup,
  HealthCardField.allergies,
  HealthCardField.emergencyContact,
  HealthCardField.medications,
  HealthCardField.provider,
  HealthCardField.notes,
};

void main() {
  group('payload — selection discipline', () {
    test('no data yields envelope only', () {
      final p = buildSharePayload(
        selected: _all,
        displayName: null,
        snapshot: null,
      );
      expect(p.keys.toSet(), {'type', 'v'});
    });

    test('partial data shows only entered fields', () {
      final now = DateTime(2026, 9, 30);
      final p = buildSharePayload(
        selected: _all,
        displayName: 'Ada',
        snapshot: HealthSnapshot(
          allergies: const [AllergyRecord(name: 'Dust')],
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(p.keys.toSet(),
          {'type', 'v', 'name', 'allergies'});
    });

    test('complete data encodes everything selected', () {
      final p = buildSharePayload(
        selected: _all,
        displayName: 'Ada Lovelace',
        snapshot: _fullSnapshot(),
      );
      expect(p['name'], 'Ada Lovelace');
      expect(p['bloodGroup'], 'O+');
      expect((p['allergies'] as List).length, 1);
      expect(p['emergencyContact'], {'name': 'Jan Doe', 'phone': '555-0100'});
      // Only active medications; ended courses are excluded.
      expect((p['medications'] as List).length, 1);
      expect(p['provider'], 'Dr. Rao');
      expect(p['notes'], 'Carry antihistamine.');
    });

    test('unchecked fields stay out, even when entered', () {
      final p = buildSharePayload(
        selected: const {
          HealthCardField.name,
          HealthCardField.bloodGroup,
          HealthCardField.allergies,
          HealthCardField.emergencyContact,
        },
        displayName: 'Ada Lovelace',
        snapshot: _fullSnapshot(),
      );
      expect(p.containsKey('medications'), isFalse);
      expect(p.containsKey('provider'), isFalse);
      expect(p.containsKey('notes'), isFalse);
    });

    test('Unknown blood group is treated as not entered', () {
      final now = DateTime(2026, 9, 30);
      final p = buildSharePayload(
        selected: _all,
        displayName: 'Ada',
        snapshot: HealthSnapshot(
            bloodGroup: 'Unknown', createdAt: now, updatedAt: now),
      );
      expect(p.containsKey('bloodGroup'), isFalse);
    });

    test('payload can never leak non-card data', () {
      const forbidden = [
        'journal',
        'entries',
        'history',
        'documents',
        'analytics',
        'wellness',
        'score',
        'password',
        'hash',
        'contentHash',
        'localPath',
      ];
      final p = buildSharePayload(
        selected: _all,
        displayName: 'Ada Lovelace',
        snapshot: _fullSnapshot(),
      );
      final encoded = jsonEncode(p).toLowerCase();
      for (final f in forbidden) {
        expect(encoded.contains(f), isFalse,
            reason: 'leaked key: $f');
      }
      // And the shared text renders the same payload (nothing hidden).
      final text = formatShareText(p);
      expect(text, contains('Ada Lovelace'));
      expect(text, contains('O+'));
    });

    test('initials avatar needs no photo', () {
      expect(initialsFor('Ada Lovelace'), 'AL');
      expect(initialsFor('Ada'), 'A');
      expect(initialsFor(null), '?');
      expect(initialsFor('  '), '?');
    });
  });

  group('screen', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await _initTestHive();
    });

    tearDown(() async {
      await LocalDatabase.clearAll();
    });

    Future<void> pumpCard(WidgetTester tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(
              create: (_) =>
                  HealthSnapshotProvider(HealthSnapshotRepository())),
          ChangeNotifierProvider(
              create: (_) => ProfileProvider(ProfileRepository())),
        ],
        child: const MaterialApp(home: HealthCardScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('no data explains itself', (tester) async {
      await pumpCard(tester);
      expect(find.text('No card details yet'), findsOneWidget);
    });

    testWidgets('complete data shows entered fields only', (tester) async {
      final now = DateTime(2026, 9, 30);
      await HealthSnapshotRepository().save(_fullSnapshot());
      await ProfileRepository().save(UserProfile(
          displayName: 'Ada Lovelace', createdAt: now, updatedAt: now));
      await pumpCard(tester);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('O+'), findsOneWidget);
      expect(find.textContaining('Peanuts'), findsOneWidget);
      expect(find.textContaining('Loratadine'), findsOneWidget);
      expect(find.text('Old Course'), findsNothing); // inactive
      expect(find.text('Share Health Card'), findsOneWidget);
    });

    testWidgets('share sheet previews QR with selected fields only',
        (tester) async {
      final now = DateTime(2026, 9, 30);
      await HealthSnapshotRepository().save(_fullSnapshot());
      await ProfileRepository().save(UserProfile(
          displayName: 'Ada Lovelace', createdAt: now, updatedAt: now));
      await pumpCard(tester);
      await tester.tap(find.text('Share Health Card'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(QrImageView), findsOneWidget);
      expect(
          find.text(
              'Anyone who receives this card can see the information you selected. The QR code contains exactly what is previewed below — nothing hidden.'),
          findsOneWidget);
      // The QR encodes the same payload as the text preview: medications
      // unchecked by default, name included.
      expect(find.textContaining('Ada Lovelace'), findsWidgets);
      expect(find.textContaining('Loratadine'), findsNothing);
      // Opt in and both the preview text and the code update.
      await tester.tap(find.text('Medications'));
      await tester.pump();
      expect(find.textContaining('Loratadine'), findsWidgets);
    });

    testWidgets('restart restores the card from storage', (tester) async {
      final now = DateTime(2026, 9, 30);
      await HealthSnapshotRepository().save(_fullSnapshot());
      await ProfileRepository().save(UserProfile(
          displayName: 'Ada Lovelace', createdAt: now, updatedAt: now));
      // Fresh provider instances over the same boxes (like an app restart).
      await pumpCard(tester);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('O+'), findsOneWidget);
    });

    testWidgets('screen renders in dark mode', (tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(
              create: (_) =>
                  HealthSnapshotProvider(HealthSnapshotRepository())),
          ChangeNotifierProvider(
              create: (_) => ProfileProvider(ProfileRepository())),
        ],
        child: MaterialApp(
          themeMode: ThemeMode.dark,
          darkTheme: ThemeData.dark(useMaterial3: true),
          theme: ThemeData.light(useMaterial3: true),
          home: const HealthCardScreen(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(HealthCardScreen), findsOneWidget);
    });
  });
}
