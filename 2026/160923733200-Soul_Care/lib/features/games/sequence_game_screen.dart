import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'game_widgets.dart';
import 'games_provider.dart';
import 'memory_game_screen.dart' show statsText;

/// Score: 100 per cleared level minus 10 per mistake (floor 0).
int sequenceScore({required int levelsDone, required int mistakes}) =>
    max(0, levelsDone * 100 - mistakes * 10);

/// Always-solvable levels: tap 1..n in order. Level n shows n+2 numbers,
/// so difficulty grows gently and no unfair sequence can appear.
class SequenceGame {
  int level = 1;
  late List<int> board;
  int next = 1;
  int mistakes = 0;
  int levelsDone = 0;
  final Random _random;

  SequenceGame({Random? random}) : _random = random ?? Random() {
    _deal();
  }

  int get count => level + 2;

  void _deal() {
    next = 1;
    board = List<int>.generate(count, (i) => i + 1)..shuffle(_random);
  }

  /// Returns true when the tap was the expected next number.
  bool tap(int value) {
    if (value == next) {
      next++;
      if (next > count) {
        levelsDone++;
        level++;
        _deal();
      }
      return true;
    }
    mistakes++;
    return false;
  }

  void restart() {
    level = 1;
    mistakes = 0;
    levelsDone = 0;
    _deal();
  }
}

class SequenceGameScreen extends StatefulWidget {
  const SequenceGameScreen({super.key});

  @override
  State<SequenceGameScreen> createState() => _SequenceGameScreenState();
}

class _SequenceGameScreenState extends State<SequenceGameScreen> {
  late SequenceGame _game;
  int? _flash;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _game = SequenceGame();
  }

  Future<void> _tap(int value) async {
    if (_finished) return;
    final ok = _game.tap(value);
    setState(() => _flash = value);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    setState(() => _flash = null);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Not the next number — try again.')));
    }
  }

  Future<void> _finish() async {
    _finished = true;
    final score = sequenceScore(
        levelsDone: _game.levelsDone, mistakes: _game.mistakes);
    await context.read<GamesProvider>().record('sequence', score);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session over — $score pts ✓')));
    setState(() {});
  }

  void _restart() {
    setState(() {
      _game.restart();
      _finished = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = context.watch<GamesProvider>().statsFor('sequence');
    return Scaffold(
      appBar: AppBar(title: const Text('Number Sequence')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StatsLine(statsText(
              plays: stats.playCount,
              best: stats.bestScore,
              recent: stats.recentScore,
              unit: ' pts')),
          const SizedBox(height: 4),
          Text(
              'Level ${_game.level} · Tap 1–${_game.count} in order · Mistakes: ${_game.mistakes}',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in _game.board)
                SizedBox(
                  width: 72,
                  height: 72,
                  child: FilledButton.tonal(
                    onPressed: _flash == n ? null : () => _tap(n),
                    child: Text('$n',
                        style: theme.textTheme.titleLarge),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _restart,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Restart'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _finished ? null : _finish,
                  child: const Text('Finish session'),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Back to games'),
          ),
        ],
      ),
    );
  }
}
