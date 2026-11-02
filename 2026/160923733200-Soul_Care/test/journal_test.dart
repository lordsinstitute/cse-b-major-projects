import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/app/providers/daily_health_provider.dart';
import 'package:soul_care/app/providers/journal_provider.dart';
import 'package:soul_care/app/providers/settings_provider.dart';
import 'package:soul_care/app/theme/app_theme.dart';
import 'package:soul_care/core/utils/utils.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/journal.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/data/repositories/journal_repository.dart';
import 'package:soul_care/data/repositories/settings_repository.dart';
import 'package:soul_care/features/journal/journal_detail_screen.dart';
import 'package:soul_care/features/journal/journal_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_journal');
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
  ]);
}

JournalEntry _entry(String id, String body,
    {String date = '2099-05-01',
    String? title,
    int? mood,
    int? energy,
    List<String> tags = const []}) {
  final now = DateTime.now();
  return JournalEntry(
    id: id,
    date: date,
    title: title,
    body: body,
    mood: mood,
    energy: energy,
    tags: tags,
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
    test('creating full + quick entries; empty body rejected', () async {
      const repo = JournalRepository();
      final full = await repo.save(_entry('j1', 'A long reflection.',
          title: 'Evening', mood: 4, energy: null, tags: const ['Personal']));
      expect(full.isSuccess, isTrue);
      expect(full.value!.isQuickNote, isFalse);

      final quick = await repo.save(_entry('j2', 'Tired today.'));
      expect(quick.isSuccess, isTrue);
      expect(quick.value!.isQuickNote, isTrue);

      final empty = await repo.save(_entry('j3', '   '));
      expect(empty.isFailure, isTrue);
    });

    test('editing keeps id, updates body + timestamp', () async {
      const repo = JournalRepository();
      await repo.save(_entry('j1', 'First draft.'));
      final before =
          (await repo.getById('j1')).value!;
      final edited = await repo.save(before.copyWith(
        body: 'Revised thought.',
        tags: ['Work'],
      ));
      expect(edited.isSuccess, isTrue);
      final loaded = (await repo.getById('j1')).value!;
      expect(loaded.body, 'Revised thought.');
      expect(loaded.tags, ['Work']);
    });

    test('deleting removes the entry', () async {
      const repo = JournalRepository();
      await repo.save(_entry('j1', 'Gone soon.'));
      expect((await repo.delete('j1')).isSuccess, isTrue);
      expect((await repo.getById('j1')).value, isNull);
    });

    test('local search across title, body, tags + filters', () async {
      const repo = JournalRepository();
      await repo.save(_entry('j1', 'Slept badly.',
          title: 'Rough night', mood: 2, tags: const ['Sleep']));
      await repo.save(_entry('j2', 'Great run at lunch.',
          tags: const ['Exercise'], mood: 5));

      Future<int> hits(String q,
          {Set<String> tags = const {}, int? mood}) async =>
          (await repo.search(query: q, tags: tags, mood: mood))
              .value!
              .length;
      expect(await hits('rough'), 1);
      expect(await hits('run'), 1);
      expect(await hits('sleep'), 1);
      expect(await hits('', tags: {'Exercise'}), 1);
      expect(await hits('', mood: 5), 1);
      expect(await hits('nope'), 0);
    });

    test('unknown tags dropped; out-of-range moods clamped', () async {
      const repo = JournalRepository();
      final saved = await repo.save(JournalEntry(
        id: 'j1',
        date: '2099-05-01',
        body: 'x',
        mood: 9,
        tags: const ['Sleep', 'Hacker!'],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      expect(saved.value!.mood, 5);
      expect(saved.value!.tags, ['Sleep']);
    });

    test('restart restores entries', () async {
      const repo = JournalRepository();
      await repo.save(_entry('j1', 'Persist me.'));
      const fresh = JournalRepository();
      expect((await fresh.getById('j1')).value?.body, 'Persist me.');
    });
  });

  group('app lock', () {
    test('PIN enable/verify is hash-based; wrong PIN rejected', () async {
      final p = SettingsProvider(SettingsRepository());
      await p.load();
      expect(p.settings.appLockHash, isNull);
      expect(
          await p.setAppLock(enabled: true, pin: '12'), isFalse);
      expect(await p.setAppLock(enabled: true, pin: '2468'), isTrue);
      expect(p.settings.appLockEnabled, isTrue);
      expect(p.settings.appLockHash, isNotNull);
      expect(p.settings.appLockHash, isNot('2468'));
      expect(p.settings.appLockHash, hashPin('2468'));

      expect(p.unlockJournal('0000'), isFalse);
      expect(p.journalUnlocked, isFalse);
      expect(p.unlockJournal('2468'), isTrue);
      expect(p.journalUnlocked, isTrue);

      expect(await p.setAppLock(enabled: false), isTrue);
      expect(p.journalUnlocked, isFalse);
    });
  });

  group('widgets', () {
    MultiProvider wrap(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider(
                create: (_) => JournalProvider(JournalRepository())),
            ChangeNotifierProvider(
                create: (_) => SettingsProvider(SettingsRepository())),
            ChangeNotifierProvider(
                create: (_) =>
                    DailyHealthProvider(DailyHealthRepository())),
          ],
          child: MaterialApp(home: Scaffold(body: child)),
        );

    testWidgets('empty journal invites a quick note', (tester) async {
      await tester.pumpWidget(wrap(const JournalScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Empty journal'), findsOneWidget);
      expect(find.text('Quick note'), findsOneWidget);
    });

    testWidgets('quick note saves and lists', (tester) async {
      await tester.pumpWidget(wrap(const JournalScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Quick note'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, 'Tired today.');
      await tester.tap(find.text('Save note'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Tired today.'), findsOneWidget);
    });

    testWidgets('detail shows entry + that-day metrics, dark mode',
        (tester) async {
      final now = DateTime.now();
      final todayKey =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      const repo = JournalRepository();
      await repo.save(_entry('j1', 'Felt unusually tired today.',
          date: todayKey, mood: 2, tags: const ['Sleep']));
      await DailyHealthRepository().save(DailyHealthEntry(
          date: todayKey, sleepHours: 5.6));

      final journal = JournalProvider(JournalRepository());
      await journal.load();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: journal),
          ChangeNotifierProvider(
              create: (_) => SettingsProvider(SettingsRepository())),
          ChangeNotifierProvider(
              create: (_) =>
                  DailyHealthProvider(DailyHealthRepository())),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: const Scaffold(
              body: JournalDetailScreen(entryId: 'j1')),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Felt unusually tired today.'), findsOneWidget);
      expect(find.text('That day'), findsOneWidget);
      expect(find.textContaining('not as cause and effect'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
