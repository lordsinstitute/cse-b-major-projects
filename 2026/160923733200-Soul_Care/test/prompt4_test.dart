import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/app/providers/experiment_provider.dart';
import 'package:soul_care/core/utils/utils.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/enums.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/data/repositories/experiment_repository.dart';
import 'package:soul_care/features/experiments/experiment_engine.dart';
import 'package:soul_care/features/experiments/experiment_templates.dart';
import 'package:soul_care/features/experiments/experiments_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_p4');
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

Experiment _exp({
  String? templateId,
  ExperimentStatus status = ExperimentStatus.active,
  DateTime? start,
  List<String> checkIns = const [],
  List<String> missed = const [],
}) {
  final now = DateTime.now();
  final s = start ??
      DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 3));
  return Experiment(
    id: generateId(),
    templateId: templateId,
    title: 'Test experiment',
    description: 'desc',
    targetMetric: 'sleepHours',
    durationDays: 7,
    startDate: s,
    endDate: s.add(const Duration(days: 6)),
    status: status,
    checkIns: checkIns,
    missedDays: missed,
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

  group('templates', () {
    test('five 7-day templates with complete content', () {
      expect(experimentTemplates.length, 5);
      final titles =
          experimentTemplates.map((t) => t.title).toSet();
      expect(
          titles,
          containsAll([
            'Earlier Sleep',
            'Daily Walk',
            'Breathing Reset',
            'Hydration Consistency',
            'Reduced Late-Night Screen Time',
          ]));
      for (final t in experimentTemplates) {
        expect(t.durationDays, 7);
        expect(t.explanation, isNotEmpty);
        expect(t.instructions, isNotEmpty);
        expect(t.targetMetric, isNotEmpty);
        expect(t.trackedFrom, isNotEmpty);
      }
    });
  });

  group('states', () {
    test('recommended/active/completed/abandoned exist with labels', () {
      expect(ExperimentStatusX.fromName('recommended'),
          ExperimentStatus.recommended);
      expect(ExperimentStatusX.fromName('active'), ExperimentStatus.active);
      expect(ExperimentStatusX.fromName('completed'),
          ExperimentStatus.completed);
      expect(ExperimentStatusX.fromName('abandoned'),
          ExperimentStatus.abandoned);
      // Legacy values still parse.
      expect(ExperimentStatusX.fromName('archived'),
          ExperimentStatus.archived);
      expect(ExperimentStatusX.fromName('paused'), ExperimentStatus.paused);
    });

    test('missedDays round-trips through JSON', () {
      final e = _exp(missed: ['2026-09-28']);
      final restored = Experiment.fromJson(e.toJson());
      expect(restored.missedDays, ['2026-09-28']);
      expect(restored.checkIns, isEmpty);
    });
  });

  group('engine math', () {
    test('day number, progress, streaks are deterministic', () {
      final now = DateTime.now();
      final today = _key(now);
      final y = _key(now.subtract(const Duration(days: 1)));
      final exp = _exp(checkIns: [y, today]);
      expect(dayNumber(exp, now), 4);
      expect(progressFraction(exp, now), closeTo(4 / 7, 0.001));
      expect(currentStreak(exp, now), 2);

      // MISSED breaks the streak.
      final broken = _exp(checkIns: [today], missed: [y]);
      expect(currentStreak(broken, now), 1);
      expect(bestStreak(_exp(checkIns: [y, today])), 2);
    });

    test('toggle DONE corrects accidental check-ins', () {
      final now = DateTime.now();
      var exp = _exp();
      exp = toggleDone(exp, now);
      expect(exp.checkIns, contains(_key(now)));
      exp = toggleDone(exp, now);
      expect(exp.checkIns, isNot(contains(_key(now))));
    });
  });

  group('provider: single active + persistence', () {
    ExperimentProvider provider() => ExperimentProvider(
        ExperimentRepository(),
        dailyRepo: DailyHealthRepository());

    test('only one experiment active at a time', () async {
      final p = provider();
      await p.load();
      expect(
          await p.startTemplate(experimentTemplates[0]), isTrue);
      expect(p.activeExperiment, isNotNull);
      expect(await p.startTemplate(experimentTemplates[1]), isFalse);
      expect(p.error, contains('Only one'));
      expect(
          p.items
              .where((e) => e.status == ExperimentStatus.active)
              .length,
          1);
    });

    test('check-in persists across provider recreation (restart)', () async {
      final p = provider();
      await p.load();
      await p.startTemplate(experimentTemplates[1]);
      final active = p.activeExperiment!;
      expect(await p.checkInDone(active), isTrue);

      // Simulate app restart.
      final restarted = provider();
      await restarted.load();
      final again = restarted.activeExperiment!;
      expect(again.checkIns, contains(_key(DateTime.now())));

      // Correction removes it and persists too.
      expect(await restarted.checkInDone(again), isTrue);
      final reloaded = provider();
      await reloaded.load();
      expect(reloaded.activeExperiment!.checkIns,
          isNot(contains(_key(DateTime.now()))));
    });

    test('MISSED records explicitly and can be undone', () async {
      final p = provider();
      await p.load();
      await p.startTemplate(experimentTemplates[2]);
      final active = p.activeExperiment!;
      expect(await p.checkInMissed(active), isTrue);
      expect(p.activeExperiment!.missedDays,
          contains(_key(DateTime.now())));
      expect(await p.checkInMissed(p.activeExperiment!), isTrue);
      expect(p.activeExperiment!.missedDays, isEmpty);
    });

    test('abandon moves to history, results viewable later', () async {
      final p = provider();
      await p.load();
      await p.startTemplate(experimentTemplates[0]);
      final id = p.activeExperiment!.id;
      expect(await p.abandon(id), isTrue);
      expect(p.activeExperiment, isNull);
      expect(p.history.map((e) => e.id), contains(id));
      // A new experiment can start after abandoning.
      expect(await p.startTemplate(experimentTemplates[1]), isTrue);
    });

    test('overdue active experiments auto-complete on load', () async {
      final repo = ExperimentRepository();
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 10));
      await repo.save(_exp(
          status: ExperimentStatus.active,
          start: start));
      final p = provider();
      await p.load();
      expect(p.activeExperiment, isNull);
      expect(p.history.length, 1);
      expect(p.history.single.status, ExperimentStatus.completed);
    });
  });

  group('baseline + results', () {
    test('factual before/during comparison, no causal claims', () async {
      final daily = DailyHealthRepository();
      final now = DateTime.now();
      // Baseline window (the 7 days before start): 6.4h avg.
      // Experiment starts today, so only today counts as "during".
      for (var i = 7; i >= 1; i--) {
        final d = now.subtract(Duration(days: i));
        await daily.save(
            DailyHealthEntry(date: _key(d), sleepHours: 6.4));
      }
      await daily.save(
          DailyHealthEntry(date: _key(now), sleepHours: 7.0));
      final p = ExperimentProvider(ExperimentRepository(),
          dailyRepo: DailyHealthRepository());
      await p.load();
      await p.startTemplate(experimentTemplates[0]);
      final active = p.activeExperiment!;

      final comparison = await p.baselineFor(active);
      expect(comparison, isNotNull);
      expect(comparison!.hasBaseline, isTrue);
      expect(comparison.baselineAvg, closeTo(6.4, 0.01));
      expect(comparison.currentAvg, closeTo(7.0, 0.01));
      expect(comparison.delta, closeTo(0.6, 0.01));

      final results = await p.resultsFor(active);
      expect(results, isNotNull);
      expect(results!.summary, contains('0.6'));
      expect(results.summary, contains('observed difference'));
      final lower = results.summary.toLowerCase();
      expect(lower, isNot(contains('prove')));
      expect(lower, isNot(contains('cause')));
      expect(lower, isNot(contains('diagnos')));
    });

    test('no baseline data yields honest gap, not zeros', () async {
      final p = ExperimentProvider(ExperimentRepository(),
          dailyRepo: DailyHealthRepository());
      await p.load();
      await p.startTemplate(experimentTemplates[0]);
      final results = await p.resultsFor(p.activeExperiment!);
      expect(results!.comparison.hasBaseline, isFalse);
      expect(results.summary, contains('no logged baseline'));
    });
  });

  group('recommendations', () {
    test('low sleep consistency recommends Earlier Sleep with reason',
        () async {
      final daily = DailyHealthRepository();
      final now = DateTime.now();
      final sleeps = [5.5, 8.5, 6.0, 5.0];
      for (var i = 0; i < sleeps.length; i++) {
        await daily.save(DailyHealthEntry(
          date: _key(now.subtract(Duration(days: i))),
          sleepHours: sleeps[i],
          exerciseMinutes: 30,
          waterGlasses: 8,
          meditationMinutes: 10,
        ));
      }
      final p = ExperimentProvider(ExperimentRepository(),
          dailyRepo: DailyHealthRepository());
      final recs = await p.recommendations();
      expect(recs, isNotEmpty);
      expect(recs.length, lessThanOrEqualTo(3));
      final ids = recs.map((r) => r.template.id);
      expect(ids, contains('earlier-sleep'));
      for (final r in recs) {
        expect(r.reason.trim(), isNotEmpty);
      }
    });

    test('no data yields no recommendations (never without reason)',
        () async {
      final p = ExperimentProvider(ExperimentRepository(),
          dailyRepo: DailyHealthRepository());
      expect(await p.recommendations(), isEmpty);
    });
  });

  group('widgets', () {
    ExperimentProvider provider() => ExperimentProvider(
        ExperimentRepository(),
        dailyRepo: DailyHealthRepository());

    testWidgets('lab shows templates, start flow, active hero',
        (tester) async {
      final p = provider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider.value(value: p)],
          child:
              const MaterialApp(home: Scaffold(body: ExperimentsScreen())),
        ),
      );
      // Bounded gate: wait until provider load finishes rendering
      // (fixed pumps race a slow store; pumpAndSettle risks spinner waits).
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find
            .text('All experiments', skipOffstage: false)
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }

      // All 5 templates listed (ListView builds all children eagerly;
      // skipOffstage:false sees them regardless of scroll position).
      debugPrint(
          'LABALL=${find.byType(Text, skipOffstage: false).evaluate().map((e) => (e.widget as Text).data).toList()}');
      for (final t in experimentTemplates) {
        expect(find.text(t.title, skipOffstage: false), findsOneWidget);
      }

      // Start flow for the first template (keyed button — robust
      // against recommendation duplicates and list position).
      final startKey = find.byKey(
          const ValueKey('template-start-earlier-sleep'),
          skipOffstage: false);
      expect(startKey, findsOneWidget);
      await tester.ensureVisible(startKey);
      await tester.pump();
      await tester.tap(startKey);
      await tester.pump();
      await tester.tap(startKey);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Confirmation sheet: what / duration / tracked / baseline.
      expect(find.text('What you will do'), findsOneWidget);
      expect(find.textContaining('Duration: 7 days'), findsOneWidget);
      expect(find.textContaining('Tracked:'), findsOneWidget);
      await tester.tap(find.text('Start 7-day experiment'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Active hero with big DONE / MISSED actions.
      expect(find.text('Day 1 of 7', skipOffstage: false), findsOneWidget);
      final doneBtn = find.text('DONE', skipOffstage: false);
      expect(doneBtn, findsOneWidget);
      expect(find.text('MISSED', skipOffstage: false), findsOneWidget);

      // DONE persists a check-in.
      await tester.ensureVisible(doneBtn);
      await tester.pump();
      await tester.tap(doneBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('logged'), findsOneWidget);
      expect(p.activeExperiment!.checkIns,
          contains(_key(DateTime.now())));
    });

    testWidgets('completed experiment shows results in history',
        (tester) async {
      final daily = DailyHealthRepository();
      final now = DateTime.now();
      // Minimal honest baseline: 2 pre-start days at 6.0h, today at 7.0h.
      for (var i = 2; i >= 1; i--) {
        await daily.save(DailyHealthEntry(
            date: _key(now.subtract(Duration(days: i))),
            sleepHours: 6.0));
      }
      await daily.save(
          DailyHealthEntry(date: _key(now), sleepHours: 7.0));
      final p = provider();
      await p.load();
      await p.startTemplate(experimentTemplates[0]);
      await p.checkInDone(p.activeExperiment!);
      await p.completeNow(p.activeExperiment!.id);

      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider.value(value: p)],
          child:
              const MaterialApp(home: Scaffold(body: ExperimentsScreen())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final historyTitle = find.text('History', skipOffstage: false);
      await tester.ensureVisible(historyTitle);
      await tester.pump();
      expect(historyTitle, findsOneWidget);
      final historyCard =
          find.text('Earlier Sleep', skipOffstage: false).last;
      await tester.ensureVisible(historyCard);
      await tester.pump();
      await tester.tap(historyCard);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Completion rate'), findsOneWidget);
      expect(find.textContaining('observed difference'), findsOneWidget);
    });
  });
}
