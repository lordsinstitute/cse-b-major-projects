import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/app/providers/reminders_provider.dart';
import 'package:soul_care/core/reminders/reminder_schedule.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/reminders.dart';
import 'package:soul_care/features/reminders/reminders_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_remind');
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
  ]);
}

MedicationReminder _med(String id, String name,
    {List<String> times = const ['08:00'],
    List<int> days = const [],
    bool enabled = true,
    DateTime? start,
    DateTime? end}) {
  final now = DateTime.now();
  return MedicationReminder(
    id: id,
    medicationName: name,
    times: times,
    days: days,
    startDate: start,
    endDate: end,
    enabled: enabled,
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

  group('schedule math', () {
    test('daily: one occurrence per future time, skips past', () {
      final from = DateTime(2026, 9, 29, 7, 0);
      final occ = medicationOccurrences(
          reminder: _med('m1', 'Aspirin', times: const ['06:00', '08:00']),
          from: from,
          maxDays: 2);
      // 06:00 today expired; 08:00 today + both tomorrow.
      expect(occ.length, 3);
      expect(occ.first.at, DateTime(2026, 9, 29, 8, 0));
      expect(occ.map((o) => o.medicationName).toSet(), {'Aspirin'});
    });

    test('selected weekdays filter days', () {
      // 2026-09-29 is a Tuesday.
      final from = DateTime(2026, 9, 29, 0, 1);
      final occ = medicationOccurrences(
          reminder: _med('m1', 'X', times: const ['09:00'], days: const [1]),
          from: from,
          maxDays: 8);
      expect(occ.length, 1);
      expect(occ.single.at.weekday, DateTime.monday);
    });

    test('disabled / empty / windowed reminders yield nothing', () {
      final from = DateTime(2026, 9, 29, 7, 0);
      expect(
          medicationOccurrences(
              reminder: _med('m1', 'X', enabled: false),
              from: from),
          isEmpty);
      expect(
          medicationOccurrences(
              reminder: _med('m1', 'X', times: const []), from: from),
          isEmpty);
      expect(
          medicationOccurrences(
              reminder: _med('m1', 'X',
                  start: DateTime(2026, 10, 5), times: const ['08:00']),
              from: from,
              maxDays: 3),
          isEmpty);
      expect(
          medicationOccurrences(
              reminder: _med('m1', 'X',
                  end: DateTime(2026, 9, 20), times: const ['08:00']),
              from: from,
              maxDays: 3),
          isEmpty);
    });

    test('notification ids are stable across calls', () {
      expect(notificationIdFor('m1|2026-09-29|08:00'),
          notificationIdFor('m1|2026-09-29|08:00'));
      expect(notificationIdFor('a'),
          isNot(notificationIdFor('b')));
    });

    test('appointment alert respects enable/past/lead-time', () {
      final now = DateTime(2026, 9, 29, 10, 0);
      Appointment appt(
              {bool enabled = true, int lead = 60, DateTime? date}) =>
          Appointment(
            id: 'a1',
            title: 'Checkup',
            date: date ?? DateTime(2026, 9, 30),
            time: '09:00',
            enabled: enabled,
            remindBeforeMin: lead,
            createdAt: now,
            updatedAt: now,
          );
      expect(appointmentAlertAt(appt(), now),
          DateTime(2026, 9, 30, 8, 0));
      expect(appointmentAlertAt(appt(enabled: false), now), isNull);
      expect(appointmentAlertAt(appt(lead: 0), now), isNull);
      expect(
          appointmentAlertAt(
              appt(date: DateTime(2026, 9, 28)), now),
          isNull); // past
    });

    test('frequency labels cover daily/twice/weekdays', () {
      expect(frequencyLabel(['08:00'], []), 'Daily');
      expect(frequencyLabel(['08:00', '20:00'], []), 'Twice daily');
      expect(frequencyLabel(['08:00'], [1, 3, 5]), 'Selected weekdays');
    });
  });

  group('provider: CRUD + restart', () {
    test('create, edit, disable, delete persist across restart', () async {
      final p = RemindersProvider();
      await p.load();
      expect(await p.saveReminder(_med('m1', 'Vitamin D')), isTrue);
      expect(p.reminders.length, 1);

      // Edit times.
      expect(
          await p.saveReminder(
              p.reminders.single.copyWith(times: ['08:00', '20:00'])),
          isTrue);
      expect(p.reminders.single.times.length, 2);

      // Restart restores.
      final restarted = RemindersProvider();
      await restarted.load();
      expect(restarted.reminders.single.medicationName, 'Vitamin D');
      expect(restarted.reminders.single.times.length, 2);

      // Disable persists.
      await restarted.saveReminder(
          restarted.reminders.single.copyWith(enabled: false));
      final reloaded = RemindersProvider();
      await reloaded.load();
      expect(reloaded.reminders.single.enabled, isFalse);

      // Delete removes.
      expect(await reloaded.removeReminder('m1'), isTrue);
      final empty = RemindersProvider();
      await empty.load();
      expect(empty.reminders, isEmpty);
    });

    test('validation rejects nameless reminders', () async {
      final p = RemindersProvider();
      await p.load();
      expect(await p.saveReminder(_med('m1', '   ')), isFalse);
      expect(p.error, isNotNull);
    });

    test('appointments CRUD + upcoming merge + history labels', () async {
      final p = RemindersProvider();
      await p.load();
      final now = DateTime.now();
      final appt = Appointment(
        id: 'a1',
        title: 'Dental checkup',
        date: DateTime(now.year, now.month, now.day)
            .add(const Duration(days: 2)),
        time: '10:30',
        location: 'City Clinic',
        createdAt: now,
        updatedAt: now,
      );
      expect(await p.saveAppointment(appt), isTrue);
      await p.saveReminder(_med('m1', 'Omega', times: const ['23:59']));

      final upcoming = p.upcoming();
      expect(upcoming.any((u) => u.isAppointment), isTrue);
      expect(upcoming.any((u) => !u.isAppointment), isTrue);
      for (var i = 1; i < upcoming.length; i++) {
        expect(upcoming[i].at.isAfter(upcoming[i - 1].at) ||
            upcoming[i].at.isAtSameMomentAs(upcoming[i - 1].at), isTrue);
      }

      // Log taken + skipped; unlogged reads neutral "No record".
      final key = _dayKey(now);
      expect(
          await p.logDose('m1', key, '08:00', DoseAction.taken), isTrue);
      expect(
          await p.logDose('m1', key, '20:00', DoseAction.skipped),
          isTrue);
      final history = p.recentHistory();
      final taken = history.where(
          (h) => h.occurrence.timeKey == '08:00' && h.occurrence.dateKey == key);
      if (taken.isNotEmpty) {
        expect(taken.single.action, DoseAction.taken);
        expect(taken.single.statusLabel, 'taken');
      }
      // Neutral wording exists somewhere when unlogged doses remain.
      expect(
          history.any((h) => h.statusLabel == 'No record') ||
              history.every((h) => h.action != null),
          isTrue);
    });
  });

  group('widgets', () {
    testWidgets('schedule screen lists tabs + empty states', (tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => RemindersProvider())
        ],
        child: const MaterialApp(home: RemindersScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Medications'), findsOneWidget);
      expect(find.text('Appointments'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
    });

    testWidgets('dark mode renders', (tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => RemindersProvider())
        ],
        child: MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: ThemeMode.dark,
          home: const RemindersScreen(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  });
}

String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
