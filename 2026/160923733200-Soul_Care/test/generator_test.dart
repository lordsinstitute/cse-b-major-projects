import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/app/providers/experiment_provider.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/enums.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/data/repositories/experiment_repository.dart';
import 'package:soul_care/features/experiments/experiment_engine.dart';
import 'package:soul_care/features/experiments/experiment_generator.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_gen');
  Hive.init(dir.path);
  await Future.wait([
    Hive.openBox(LocalDatabase.dailyBoxName),
    Hive.openBox(LocalDatabase.stressBoxName),
    Hive.openBox(LocalDatabase.morningBoxName),
    Hive.openBox(LocalDatabase.eveningBoxName),
    Hive.openBox(LocalDatabase.experimentsBoxName),
    Hive.openBox(LocalDatabase.settingsBoxName),
  ]);
}

String _key(int month, int day) =>
    '2026-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

DailyHealthEntry _day(String key,
    {double sleep = 7.5,
    int exercise = 30,
    int water = 8,
    int meditation = 15,
    double screen = 2}) {
  return DailyHealthEntry(
    date: key,
    sleepHours: sleep,
    sleepQuality: SleepQuality.good,
    feltRested: true,
    exerciseMinutes: exercise,
    exerciseIntensity: ExerciseIntensity.moderate,
    mealQuality: MealQuality.good,
    waterGlasses: water,
    meditationMinutes: meditation,
    screenTimeHours: screen,
  );
}

GeneratorInput _input(List<DailyHealthEntry> entries,
    {List<Experiment> previous = const []}) {
  return GeneratorInput(
    recent: entries,
    calmByDate: const {},
    morningByDate: const {},
    eveningByDate: const {},
    previous: previous,
    now: DateTime(2026, 9, 30),
  );
}

List<DailyHealthEntry> _week({
  List<double> sleeps = const [7.5, 7.5, 7.5, 7.5, 7.5, 7.5],
  int exercise = 30,
  int water = 8,
  int meditation = 15,
  double screen = 2,
}) {
  return [
    for (var i = 0; i < sleeps.length; i++)
      _day(_key(9, 20 + i),
          sleep: sleeps[i],
          exercise: exercise,
          water: water,
          meditation: meditation,
          screen: screen),
  ];
}

void main() {
  group('generator — insufficient data', () {
    test('empty history yields guidance, never a suggestion', () {
      final out = generateExperiments(_input([]));
      expect(out.suggestions, isEmpty);
      expect(out.loggedDays, 0);
      expect(out.insufficientReason, contains('at least 5 days'));
    });

    test('thin history (3 days) is refused honestly', () {
      final out = generateExperiments(_input(_week(
          sleeps: const [5.0, 9.0, 5.0])));
      expect(out.suggestions, isEmpty);
      expect(out.loggedDays, 3);
      expect(out.insufficientReason, isNotNull);
    });
  });

  group('generator — adequate data', () {
    test('ragged sleep generates the sleep-window experiment', () {
      final out = generateExperiments(_input(_week(
          sleeps: const [5.0, 8.0, 6.0, 9.0, 5.5, 7.5])));
      expect(out.hasSuggestions, isTrue);
      final sleep = out.suggestions.firstWhere(
          (g) => g.templateId == 'earlier-sleep');
      expect(sleep.title, '7-Day Consistent Sleep Window');
      expect(sleep.observation, contains('varied by 4.0 hours'));
      expect(sleep.baselineDays, 6);
      expect(sleep.baselineAvg, closeTo(6.83, 0.01));
      expect(sleep.durationDays, 7);
      expect(sleep.measureLabel, contains('Sleep duration'));
      expect(sleep.successCriteria, contains('5+ of 7'));
      expect(sleep.checkInRequirement, isNotEmpty);
      expect(sleep.hypothesis, contains('Hypothesis only'));
    });

    test('low activity generates the movement experiment', () {
      final out = generateExperiments(
          _input(_week(exercise: 0)));
      final move = out.suggestions
          .firstWhere((g) => g.templateId == 'daily-walk');
      expect(move.observation, contains('0 of your last 6'));
    });

    test('low water generates the hydration experiment', () {
      final out =
          generateExperiments(_input(_week(water: 3)));
      expect(
          out.suggestions.any((g) => g.templateId == 'hydration'),
          isTrue);
    });

    test('heavy screens generate the wind-down experiment', () {
      final out =
          generateExperiments(_input(_week(screen: 5.5)));
      final screenExp = out.suggestions
          .firstWhere((g) => g.templateId == 'screen');
      expect(screenExp.observation, contains('5.5h'));
    });

    test('no mindfulness generates the breathing experiment', () {
      final out = generateExperiments(
          _input(_week(meditation: 0)));
      expect(
          out.suggestions
              .any((g) => g.templateId == 'breathing-reset'),
          isTrue);
    });

    test('stacked gaps return at most 3 ranked suggestions', () {
      final out = generateExperiments(_input(_week(
        sleeps: const [5.0, 9.0, 5.0, 9.0, 5.0, 9.0],
        exercise: 0,
        water: 2,
        meditation: 0,
        screen: 6,
      )));
      expect(out.suggestions.length, lessThanOrEqualTo(3));
      expect(out.suggestions.length, greaterThan(1));
    });
  });

  group('generator — conflicting/healthy signals', () {
    test('healthy pattern yields no suggestions', () {
      final out = generateExperiments(_input(_week()));
      expect(out.suggestions, isEmpty);
      expect(out.insufficientReason, isNull);
    });

    test('good sleep plus low activity suggests only movement', () {
      final out = generateExperiments(
          _input(_week(exercise: 0)));
      expect(
          out.suggestions.any((g) => g.templateId == 'earlier-sleep'),
          isFalse);
      expect(
          out.suggestions.any((g) => g.templateId == 'daily-walk'),
          isTrue);
    });

    test('active experiments and recent completions are skipped', () {
      final now = DateTime(2026, 9, 30);
      final active = Experiment(
        id: 'a',
        templateId: 'daily-walk',
        title: 'Daily Walk',
        description: 'd',
        targetMetric: 'exerciseMinutes',
        durationDays: 7,
        startDate: DateTime(2026, 9, 28),
        status: ExperimentStatus.active,
        createdAt: now,
        updatedAt: now,
      );
      final recent = Experiment(
        id: 'b',
        templateId: 'earlier-sleep',
        title: 'Earlier Sleep',
        description: 'd',
        targetMetric: 'sleepHours',
        durationDays: 7,
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 17),
        status: ExperimentStatus.completed,
        createdAt: now,
        updatedAt: now,
      );
      final out = generateExperiments(
          _input(
              _week(
                  sleeps: const [5.0, 9.0, 5.0, 9.0, 5.0, 9.0],
                  exercise: 0),
              previous: [active, recent]));
      expect(
          out.suggestions.any((g) => g.templateId == 'daily-walk'),
          isFalse);
      expect(
          out.suggestions.any((g) => g.templateId == 'earlier-sleep'),
          isFalse);
    });
  });

  group('generator — honesty guards', () {
    test('every hypothesis disclaims truth; nothing claims cause', () {
      final out = generateExperiments(_input(_week(
        sleeps: const [5.0, 9.0, 5.0, 9.0, 5.0, 9.0],
        exercise: 0,
        water: 2,
        meditation: 0,
        screen: 6,
      )));
      expect(out.suggestions, isNotEmpty);
      for (final g in out.suggestions) {
        expect(g.hypothesis, contains('Hypothesis only'));
        for (final text in [
          g.title,
          g.observation,
          g.hypothesis,
          g.action,
          g.successCriteria
        ]) {
          expect(text.toLowerCase(), isNot(contains('cause')));
          expect(text.toLowerCase(), isNot(contains('prove')));
        }
      }
    });

    test('deterministic across runs', () {
      final entries = _week(
          sleeps: const [5.0, 9.0, 5.0, 9.0, 5.0, 9.0], exercise: 0);
      final a = generateExperiments(_input(entries));
      final b = generateExperiments(_input(entries));
      expect(
          b.suggestions.map((g) => '${g.title}|${g.baselineAvg}'),
          a.suggestions.map((g) => '${g.title}|${g.baselineAvg}'));
    });

    test('phraser rewords but never alters numbers', () {
      final rewriting = _RewritingPhraser();
      final entries = _week(
          sleeps: const [5.0, 9.0, 5.0, 9.0, 5.0, 9.0]);
      final plain = generateExperiments(_input(entries));
      final phrased =
          generateExperiments(_input(entries), phraser: rewriting);
      expect(phrased.suggestions.first.title, contains('[AI]'));
      expect(phrased.suggestions.first.baselineAvg,
          plain.suggestions.first.baselineAvg);
      expect(phrased.suggestions.first.observation,
          plain.suggestions.first.observation);
    });
  });

  group('provider — approval and measurement reuse', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await _initTestHive();
    });

    tearDown(() async {
      await LocalDatabase.clearAll();
    });

    test('generation never auto-starts; approval starts exactly one',
        () async {
      final dailyRepo = DailyHealthRepository();
      for (var i = 0; i < 6; i++) {
        await dailyRepo.save(_day(_key(9, 20 + i),
            sleep: [5.0, 9.0, 5.0, 9.0, 5.0, 9.0][i], exercise: 0));
      }
      final prov = ExperimentProvider(ExperimentRepository(),
          dailyRepo: dailyRepo);
      await prov.load();
      final out = await prov.generatePersonalized();
      expect(out.hasSuggestions, isTrue);
      // Nothing started as a side effect.
      expect(prov.activeExperiment, isNull);
      expect(prov.items, isEmpty);

      // Explicit approval starts it on the existing system.
      final ok = await prov.startGenerated(out.suggestions.first);
      expect(ok, isTrue);
      expect(prov.activeExperiment, isNotNull);
      expect(prov.activeExperiment!.templateId,
          out.suggestions.first.templateId);

      // Single-active rule still enforced.
      final second = await prov.startGenerated(out.suggestions.first);
      expect(second, isFalse);
    });

    test('completed generated experiment reports factual results',
        () async {
      final dailyRepo = DailyHealthRepository();
      final now = DateTime.now();
      final today =
          DateTime(now.year, now.month, now.day);
      String k(int ago) {
        final d = today.subtract(Duration(days: ago));
        return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }

      // Baseline week: ragged sleep.
      for (var i = 13; i >= 7; i--) {
        await dailyRepo.save(
            _day(k(i), sleep: i.isEven ? 5.0 : 8.0));
      }
      final prov = ExperimentProvider(ExperimentRepository(),
          dailyRepo: dailyRepo);
      await prov.load();
      final out = await prov.generatePersonalized();
      final sleep =
          out.suggestions.firstWhere((g) => g.templateId == 'earlier-sleep');
      expect(await prov.startGenerated(sleep), isTrue);

      // Experiment week: steady 7.5h + DONE check-ins.
      for (var i = 6; i >= 0; i--) {
        await dailyRepo.save(_day(k(i), sleep: 7.5));
      }
      final active = prov.activeExperiment!;
      var updated = active;
      for (var i = 6; i >= 2; i--) {
        updated = toggleDone(
            updated, today.subtract(Duration(days: i)));
      }
      await prov.save(updated);
      // save() refreshes fire-and-forget: reload before completing so the
      // completion is applied to the check-in-bearing copy.
      await prov.load();
      final saved = prov.items.firstWhere((e) => e.id == updated.id);
      expect(saved.checkIns.length, 5);
      await prov.completeNow(saved.id);

      final done = prov.items
          .firstWhere((e) => e.status == ExperimentStatus.completed);
      final results = await prov.resultsFor(done);
      expect(results, isNotNull);
      expect(results!.doneDays, 5);
      expect(results.comparison.hasBaseline, isTrue);
      expect(results.comparison.hasCurrent, isTrue);
      expect(results.summary, contains('observed difference'));
      expect(results.summary.toLowerCase(),
          isNot(contains('prove')));
    });
  });
}

class _RewritingPhraser implements ExperimentPhraser {
  @override
  ({String title, String description}) phrase(
          {required String draftTitle,
          required String draftDescription}) =>
      (
        title: '[AI] $draftTitle',
        description: draftDescription,
      );
}
