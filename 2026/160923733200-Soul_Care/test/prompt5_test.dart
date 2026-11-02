import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/enums.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/data/repositories/stress_repository.dart';
import 'package:soul_care/features/simulator/projection_engine.dart';
import 'package:soul_care/features/simulator/simulator_controller.dart';
import 'package:soul_care/features/simulator/simulator_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_p5');
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

const _ideal = ScenarioInput(
    sleepHours: 8, exerciseMinWeek: 150, strain: 1, waterGlasses: 8);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await _initTestHive();
  });

  tearDown(() async {
    await LocalDatabase.clearAll();
  });

  group('WellnessProjectionEngine', () {
    test('deterministic: same inputs, same outputs', () {
      const input = ScenarioInput(
          sleepHours: 6.5,
          exerciseMinWeek: 90,
          strain: 3,
          waterGlasses: 5);
      final a = WellnessProjectionEngine.project(input);
      final b = WellnessProjectionEngine.project(input);
      expect(a.overall, b.overall);
      expect(a.physical, b.physical);
      expect(a.mental, b.mental);
      expect(a.energy, b.energy);
    });

    test('indices stay in range; ideal beats worst', () {
      const worst = ScenarioInput(
          sleepHours: 4, exerciseMinWeek: 0, strain: 5, waterGlasses: 0);
      final bad = WellnessProjectionEngine.project(worst);
      final good = WellnessProjectionEngine.project(_ideal);
      for (final v in [
        bad.physical,
        bad.mental,
        bad.energy,
        bad.overall,
        good.physical,
        good.mental,
        good.energy,
        good.overall
      ]) {
        expect(v, inInclusiveRange(0, 100));
      }
      expect(good.overall, greaterThan(bad.overall + 30));
    });

    test('contributors name changed variables only', () {
      const from = ScenarioInput(
          sleepHours: 6, exerciseMinWeek: 60, strain: 3, waterGlasses: 5);
      final to = from.copyWith(sleepHours: 7, exerciseMinWeek: 120);
      final c = WellnessProjectionEngine.changedInputs(from, to);
      expect(c.join(' '), contains('sleep'));
      expect(c.join(' '), contains('movement'));
      expect(c.join(' '), isNot(contains('water')));
      expect(WellnessProjectionEngine.changedInputs(from, from), isEmpty);
    });

    test('trajectory holds 10 illustrative points', () {
      final p = WellnessProjectionEngine.project(_ideal);
      final t = WellnessProjectionEngine.trajectory(p);
      expect(t.length, 10);
      expect(t.toSet(), {p.overall});
    });
  });

  group('baseline honesty', () {
    test('thin data yields incomplete baseline, never invented', () {
      final b = PatternBaseline.fromLogs(last7: const [], moodScores: const []);
      expect(b.isComplete, isFalse);
      expect(b.missing.length, 2);
      expect(b.missing.join(' '), contains('Today'));

      final oneDay = PatternBaseline.fromLogs(
          last7: [const DailyHealthEntry(date: '2026-09-28', sleepHours: 8)],
          moodScores: const [4]);
      expect(oneDay.isComplete, isFalse);
    });

    test('sufficient logs produce a real baseline', () {
      final b = PatternBaseline.fromLogs(
        last7: const [
          DailyHealthEntry(
              date: '2026-09-27', sleepHours: 7, exerciseMinutes: 30, waterGlasses: 6),
          DailyHealthEntry(
              date: '2026-09-28', sleepHours: 8, exerciseMinutes: 20, waterGlasses: 8),
        ],
        moodScores: const [4, 5],
      );
      expect(b.isComplete, isTrue);
      expect(b.sleepHours, closeTo(7.5, 0.01));
      expect(b.exerciseMinWeek, 50); // weekly sum, not average
      expect(b.waterGlasses, closeTo(7.0, 0.01));
      expect(b.strain, closeTo(1.5, 0.01)); // 6 − avg mood 4.5
    });
  });

  group('controller', () {
    Future<SimulatorController> seeded() async {
      final daily = DailyHealthRepository();
      final stress = StressRepository();
      final now = DateTime.now();
      await daily.save(DailyHealthEntry(
          date: _key(now.subtract(const Duration(days: 1))),
          sleepHours: 6.5,
          exerciseMinutes: 20,
          waterGlasses: 5,
          meditationMinutes: 5));
      await daily.save(DailyHealthEntry(
          date: _key(now),
          sleepHours: 7,
          exerciseMinutes: 30,
          waterGlasses: 6,
          meditationMinutes: 10));
      await stress.save(StressEntry(
          id: 's1',
          date: _key(now),
          mood: Mood.okay,
          createdAt: now));
      final c = SimulatorController();
      // Wait for async load.
      for (var i = 0; i < 50 && c.loading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return c;
    }

    test('presets move from current values with clamps', () async {
      final c = await seeded();
      expect(c.hasBaseline, isTrue);
      final before = c.scenario;
      c.applyPreset(SimulatorPreset.betterSleep);
      expect(c.scenario.sleepHours,
          closeTo((before.sleepHours + 1).clamp(4.0, 10.0), 0.001));
      c.applyPreset(SimulatorPreset.lowerStress);
      expect(c.scenario.strain, greaterThanOrEqualTo(1.0));
      expect(c.change,
          c.scenarioProjection.overall - c.currentProjection.overall);
    });

    test('reset restores current pattern; scenarios are temporary', () async {
      final c = await seeded();
      c.applyPreset(SimulatorPreset.balanced);
      c.saveScenario('Balanced sketch');
      expect(c.saved.length, 1);
      c.resetToCurrent();
      expect(
          WellnessProjectionEngine.changedInputs(
              c.currentInput, c.scenario),
          isEmpty);
      // Cap at 4 temporary sketches.
      for (var i = 0; i < 5; i++) {
        c.saveScenario('S$i');
      }
      expect(c.saved.length, 4);
      c.removeScenario(0);
      expect(c.saved.length, 3);
    });

    test('simulator never modifies health records', () async {
      final c = await seeded();
      final before =
          (await DailyHealthRepository().getRange(
                  DateTime.now().subtract(const Duration(days: 6)),
                  DateTime.now()))
              .value!
              .length;
      c.applyPreset(SimulatorPreset.betterSleep);
      c.saveScenario('x');
      c.resetToCurrent();
      c.removeScenario(0);
      final after =
          (await DailyHealthRepository().getRange(
                  DateTime.now().subtract(const Duration(days: 6)),
                  DateTime.now()))
              .value!
              .length;
      expect(after, before);
    });
  });

  group('widgets', () {
    Future<void> seed() async {
      final daily = DailyHealthRepository();
      final now = DateTime.now();
      await daily.save(DailyHealthEntry(
          date: _key(now.subtract(const Duration(days: 1))),
          sleepHours: 6.5,
          exerciseMinutes: 20,
          waterGlasses: 5,
          meditationMinutes: 5));
      await daily.save(DailyHealthEntry(
          date: _key(now),
          sleepHours: 7,
          exerciseMinutes: 30,
          waterGlasses: 6,
          meditationMinutes: 10));
      await StressRepository().save(StressEntry(
          id: 'w1',
          date: _key(now),
          mood: Mood.good,
          createdAt: now));
    }

    testWidgets('shows current vs scenario, presets, disclaimer',
        (tester) async {
      await seed();
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SimulatorScreen())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Current Pattern', skipOffstage: false),
          findsOneWidget);
      expect(find.text('Scenario', skipOffstage: false), findsWidgets);
      expect(find.text('Change', skipOffstage: false), findsOneWidget);
      expect(find.textContaining('Better Sleep', skipOffstage: false),
          findsOneWidget);
      expect(
          find.text('Reset to My Current Pattern', skipOffstage: false),
          findsOneWidget);
      expect(
          find.textContaining('not a medical prediction',
              skipOffstage: false),
          findsWidgets);

      // Preset moves the scenario.
      final preset =
          find.textContaining('More Movement', skipOffstage: false);
      await tester.ensureVisible(preset);
      await tester.pump();
      await tester.tap(preset);
      await tester.pump();
      expect(find.textContaining('movement', skipOffstage: false),
          findsWidgets);
    });

    testWidgets('thin data explains what is missing', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SimulatorScreen())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('More data needed'), findsOneWidget);
      expect(find.text('Log today'), findsOneWidget);
      expect(find.textContaining('not a medical prediction'), findsNothing);
    });
  });
}
