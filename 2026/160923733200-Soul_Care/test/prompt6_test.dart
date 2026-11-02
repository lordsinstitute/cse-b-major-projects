import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/game_stats.dart';
import 'package:soul_care/data/repositories/game_stats_repository.dart';
import 'package:soul_care/features/games/breathing_pacer_screen.dart';
import 'package:soul_care/features/games/bubble_engine.dart';
import 'package:soul_care/features/games/bubble_game_screen.dart';
import 'package:soul_care/features/games/color_game_screen.dart';
import 'package:soul_care/features/games/color_match_engine.dart';
import 'package:soul_care/features/games/echo_engine.dart';
import 'package:soul_care/features/games/echo_game_screen.dart';
import 'package:soul_care/features/games/games_provider.dart';
import 'package:soul_care/features/games/games_screen.dart';
import 'package:soul_care/features/games/memory_game_screen.dart';
import 'package:soul_care/features/games/reaction_game_screen.dart';
import 'package:soul_care/features/games/scramble_engine.dart';
import 'package:soul_care/features/games/scramble_game_screen.dart';
import 'package:soul_care/features/games/sequence_game_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_p6');
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

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await _initTestHive();
  });

  tearDown(() async {
    await LocalDatabase.clearAll();
  });

  group('memory', () {
    test('deck has 6 pairs, all matchable, restart reshuffles', () {
      final board = MemoryBoard.newGame(random: Random(42));
      expect(board.cards.length, 12);
      final counts = <int, int>{};
      for (final c in board.cards) {
        counts[c.pairId] = (counts[c.pairId] ?? 0) + 1;
      }
      expect(counts.length, 6);
      expect(counts.values.toSet(), {2});
    });

    test('flip/match/miss/complete flow with attempts', () {
      final board = MemoryBoard.newGame(random: Random(7));
      // Find a matching pair and a non-matching card.
      final byPair = <int, List<int>>{};
      for (var i = 0; i < board.cards.length; i++) {
        byPair
            .putIfAbsent(board.cards[i].pairId, () => [])
            .add(i);
      }
      final pair = byPair.values.first;
      final other = byPair.values
          .firstWhere((l) => l.first != pair.first)
          .first;

      expect(board.flip(pair[0]), 'first');
      expect(board.flip(other), 'miss');
      expect(board.attempts, 1);
      board.hideMiss(pair[0], other);
      expect(board.cards[pair[0]].faceUp, isFalse);

      expect(board.flip(pair[0]), 'first');
      expect(board.flip(pair[1]), 'match');
      expect(board.matchedPairs, 1);

      // Flipping a matched card is ignored.
      expect(board.flip(pair[0]), 'ignored');
    });

    test('score rewards efficiency deterministically', () {
      expect(
          memoryScore(attempts: 6, pairs: 6, seconds: 0), 1000);
      expect(
          memoryScore(attempts: 6, pairs: 6, seconds: 0),
          memoryScore(attempts: 6, pairs: 6, seconds: 0));
      expect(memoryScore(attempts: 12, pairs: 6, seconds: 60),
          lessThan(1000));
      expect(
          memoryScore(attempts: 500, pairs: 6, seconds: 9999), 0);
    });
  });

  group('reaction', () {
    test('average/fastest math over 5 rounds', () {
      const times = [210, 180, 250, 190, 230];
      expect(reactionAverage(times), 212);
      expect(reactionFastest(times), 180);
    });
  });

  group('sequence', () {
    test('levels always solvable, mistakes tracked, auto-advance', () {
      final game = SequenceGame(random: Random(3));
      expect(game.count, 3);
      // Board always holds exactly 1..n.
      expect(game.board.toSet(), {1, 2, 3});

      // Wrong tap first.
      expect(game.tap(2), isFalse);
      expect(game.mistakes, 1);

      // Correct order clears level 1 and advances.
      expect(game.tap(1), isTrue);
      expect(game.tap(2), isTrue);
      expect(game.tap(3), isTrue);
      expect(game.levelsDone, 1);
      expect(game.level, 2);
      expect(game.board.toSet(), {1, 2, 3, 4});
    });

    test('score math + restart', () {
      expect(sequenceScore(levelsDone: 3, mistakes: 0), 300);
      expect(sequenceScore(levelsDone: 3, mistakes: 2), 280);
      expect(sequenceScore(levelsDone: 0, mistakes: 99), 0);
      final game = SequenceGame(random: Random(1));
      game.tap(2);
      game.restart();
      expect(game.mistakes, 0);
      expect(game.level, 1);
    });
  });

  group('scramble', () {
    test('curated list is clean; scrambles are fair anagrams', () {
      expect(wellnessWords.length, greaterThanOrEqualTo(10));
      for (final w in wellnessWords) {
        expect(w, matches(RegExp(r'^[A-Z]+$')));
      }
      final r = Random(11);
      for (final w in wellnessWords) {
        final s = scrambleWord(w, r);
        expect(s.split('').toList()..sort(),
            (w.split('').toList()..sort()));
        if (w.length > 1 &&
            w.split('').toSet().length > 1) {
          expect(s, isNot(w));
        }
      }
    });

    test('guess flow tracks correct/incorrect + completion', () {
      final game = ScrambleGame(random: Random(5), wordCount: 2);
      final first = game.answer!;
      expect(game.guess('nope'), isFalse);
      expect(game.incorrect, 1);
      expect(game.complete, isFalse);
      expect(game.guess(first.toLowerCase()), isTrue);
      expect(game.correct, 1);
      expect(game.guess(game.answer!), isTrue);
      expect(game.complete, isTrue);
    });

    test('score math rewards accuracy + speed', () {
      expect(scrambleScore(correct: 5, incorrect: 0, seconds: 30),
          greaterThan(scrambleScore(correct: 4, incorrect: 3, seconds: 30)));
      expect(scrambleScore(correct: 0, incorrect: 9, seconds: 9999), 0);
    });
  });

  group('stats repository', () {
    test('round-trips; play count increments; best by direction', () async {
      const repo = GameStatsRepository();
      var res = await repo.recordPlay('memory', 800, higherBetter: true);
      expect(res.value!.playCount, 1);
      expect(res.value!.bestScore, 800);
      expect(res.value!.recentScore, 800);

      // Worse score: count + recent update, best kept.
      res = await repo.recordPlay('memory', 700, higherBetter: true);
      expect(res.value!.playCount, 2);
      expect(res.value!.bestScore, 800);
      expect(res.value!.recentScore, 700);

      // Lower-better game: improvement lowers best.
      await repo.recordPlay('reaction', 300, higherBetter: false);
      final improved =
          await repo.recordPlay('reaction', 250, higherBetter: false);
      expect(improved.value!.bestScore, 250);
      final worse =
          await repo.recordPlay('reaction', 400, higherBetter: false);
      expect(worse.value!.bestScore, 250);

      // Restart persistence: fresh instance sees the same rows.
      const fresh = GameStatsRepository();
      final mem = await fresh.getStats('memory');
      expect(mem.value!.playCount, 2);
      expect(mem.value!.bestScore, 800);
    });

    test('unknown game starts empty', () async {
      const repo = GameStatsRepository();
      final s = await repo.getStats('never-played');
      expect(s.value!.playCount, 0);
      expect(s.value!.bestScore, isNull);
    });

    test('GameStats JSON round-trip', () {
      const s = GameStats(gameId: 'x', playCount: 3, bestScore: 100);
      final r = GameStats.fromJson(s.toJson());
      expect(r.playCount, 3);
      expect(r.bestScore, 100);
    });
  });

  group('widgets', () {
    testWidgets('hub lists all eight games', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: GamesScreen())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      for (final title in [
        'Memory Match',
        'Reaction Time',
        'Number Sequence',
        'Breathing Pacer',
        'Word Scramble',
        'Color Match',
        'Pattern Echo',
        'Bubble Pop',
      ]) {
        await tester.scrollUntilVisible(find.text(title), 500,
            scrollable: find.byType(Scrollable).first);
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Not played yet.'), findsWidgets);
    });

    testWidgets('memory flips, restarts', (tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => GamesProvider())
        ],
        child: const MaterialApp(home: MemoryGameScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.question_mark), findsWidgets);
      await tester.tap(find.byIcon(Icons.question_mark).first);
      await tester.pump();
      expect(find.byIcon(Icons.question_mark),
          findsNWidgets(MemoryBoard.icons.length * 2 - 1));
      await tester.scrollUntilVisible(find.text('Restart'), 500,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Restart'));
      await tester.pump();
      expect(find.byIcon(Icons.question_mark),
          findsNWidgets(MemoryBoard.icons.length * 2));
    });

    testWidgets('sequence completes level 1 by tapping 1-2-3',
        (tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => GamesProvider())
        ],
        child: const MaterialApp(home: SequenceGameScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      for (final n in ['1', '2', '3']) {
        await tester.tap(find.text(n));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.textContaining('Level 2'), findsOneWidget);
    });

    testWidgets('scramble rejects wrong answer, restarts', (tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => GamesProvider())
        ],
        child: const MaterialApp(home: ScrambleGameScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
          find.byType(TextField), 'definitely wrong');
      await tester.tap(find.text('Check'));
      await tester.pump();
      expect(find.text('Not quite — try again.'), findsOneWidget);
      await tester.tap(find.text('Restart'));
      await tester.pump();
      expect(find.textContaining('Word 1 of 5'), findsOneWidget);
    });

    testWidgets('breathing pacer starts, pauses, changes cycles',
        (tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => GamesProvider())
        ],
        child: const MaterialApp(home: BreathingPacerScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Breathe in…'), findsOneWidget);
      await tester.tap(find.text('5'));
      await tester.pump();
      await tester.tap(find.text('Start'));
      await tester.pump();
      expect(find.text('Pause'), findsOneWidget);
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('reaction shows idle prompt', (tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => GamesProvider())
        ],
        child: const MaterialApp(home: ReactionGameScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Tap to start'), findsOneWidget);
      expect(find.text('Round 0/5'), findsOneWidget);
    });

    testWidgets('game scope provides stats to sub-screens', (tester) async {
      // Regression: sub-routes do not inherit the hub provider, so each
      // screen ships its own scope — production used to crash here.
      await tester.pumpWidget(const MaterialApp(
          home: GameScope(child: ColorGameScreen())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Color Match'), findsWidgets);
      expect(find.text('Round 1 of 10'), findsOneWidget);
    });
  });

  group('color match', () {
    test('ten answers complete the session; score floors at zero', () {
      final g = StroopGame(random: Random(11));
      for (var i = 0; i < StroopGame.totalRounds; i++) {
        g.answer('Red');
      }
      expect(g.complete, isTrue);
      expect(g.correct + g.incorrect, StroopGame.totalRounds);
      expect(
          stroopScore(correct: 0, incorrect: 10, seconds: 999), 0);
      expect(stroopScore(correct: 10, incorrect: 0, seconds: 0),
          greaterThan(1000));
    });

    test('seeded sessions are deterministic', () {
      List<String> play(int seed) {
        final g = StroopGame(random: Random(seed));
        final out = <String>[];
        for (var i = 0; i < StroopGame.totalRounds; i++) {
          out.add('${g.current.word}:${g.current.ink}');
          g.answer(stroopChoices[g.current.ink].name);
        }
        return out;
      }

      expect(play(7), play(7));
      expect(play(7), isNot(play(8)));
    });

    testWidgets('color answers advance rounds', (tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => GamesProvider())
        ],
        child: const MaterialApp(home: ColorGameScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Round 1 of 10'), findsOneWidget);
      await tester.tap(find.text('Red').first);
      await tester.pump();
      expect(find.text('Round 2 of 10'), findsOneWidget);
    });
  });

  group('pattern echo', () {
    test('correct taps advance levels; wrong tap ends the run', () {
      final g = EchoGame(random: Random(21));
      expect(g.sequence.length, EchoGame.startLength);
      // Play level 1 perfectly by reading the dealt pattern.
      for (final tile in [...g.sequence]) {
        final last = tile == g.sequence.last;
        expect(g.tap(tile), last ? 'level' : 'ok');
      }
      expect(g.levelsCompleted, 1);
      expect(g.level, 2);
      expect(g.over, isFalse);
      // A guaranteed-wrong tap ends the run.
      final wrong = (g.sequence[g.input.length] + 1) % EchoGame.tileCount;
      expect(g.tap(wrong), 'over');
      expect(g.over, isTrue);
      expect(g.tap(0), 'ended');
    });

    test('restart resets the run; score rewards levels', () {
      final g = EchoGame(random: Random(3));
      g.tap((g.sequence[0] + 1) % EchoGame.tileCount);
      expect(g.over, isTrue);
      g.restart();
      expect(g.over, isFalse);
      expect(g.levelsCompleted, 0);
      expect(g.sequence.length, EchoGame.startLength);
      expect(echoScore(levels: 3, mistakes: 1), 430);
      expect(echoScore(levels: 0, mistakes: 9), 0);
    });

    testWidgets('echo shows watch phase then your turn', (tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => GamesProvider())
        ],
        child: const MaterialApp(home: EchoGameScreen()),
      ));
      await tester.pump();
      expect(find.textContaining('Watch'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('Your turn'), findsOneWidget);
    });
  });

  group('bubble pop', () {
    test('spawn fills; pops combo; misses reset combo', () {
      final g = BubblePop(random: Random(5));
      for (var i = 0; i < BubblePop.gridSize; i++) {
        expect(g.spawn(), isNot(-1));
      }
      expect(g.lit, BubblePop.gridSize);
      expect(g.spawn(), -1); // full board: no-op
      expect(g.pop(0), isTrue);
      expect(g.pop(0), isFalse); // already dark: miss
      expect(g.popped, 1);
      expect(g.wrong, 1);
      expect(g.maxCombo, 1);
      g.restart();
      expect(g.popped, 0);
      expect(g.lit, 0);
    });

    test('score math floors at zero', () {
      expect(
          bubbleScore(popped: 20, maxCombo: 6, wrong: 2), 226);
      expect(bubbleScore(popped: 0, maxCombo: 0, wrong: 9), 0);
    });

    testWidgets('bubbles render session and restart', (tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => GamesProvider())
        ],
        child: const MaterialApp(home: BubbleGameScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('seconds left'), findsOneWidget);
      await tester.tap(find.text('Restart'));
      await tester.pump();
      expect(find.textContaining('30 seconds left'), findsOneWidget);
    });
  });
}
