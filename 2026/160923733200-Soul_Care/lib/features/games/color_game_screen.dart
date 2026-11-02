import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'game_widgets.dart';
import 'color_match_engine.dart';
import 'games_provider.dart';
import 'memory_game_screen.dart' show statsText;

/// Color Match: tap the INK color, not the word. 10 calm rounds.
class ColorGameScreen extends StatefulWidget {
  const ColorGameScreen({super.key});

  @override
  State<ColorGameScreen> createState() => _ColorGameScreenState();
}

class _ColorGameScreenState extends State<ColorGameScreen> {
  late StroopGame _game;
  final _stopwatch = Stopwatch();
  bool _finished = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _game = StroopGame();
  }

  void _answer(String name) {
    if (_finished) return;
    if (!_stopwatch.isRunning) _stopwatch.start();
    final ok = _game.answer(name);
    setState(() {
      _feedback = ok ? 'Correct ✓' : 'That was the word, not the ink.';
    });
    if (_game.complete) _finish();
  }

  Future<void> _finish() async {
    _stopwatch.stop();
    _finished = true;
    final score = stroopScore(
      correct: _game.correct,
      incorrect: _game.incorrect,
      seconds: _stopwatch.elapsed.inSeconds,
    );
    await context.read<GamesProvider>().record('color', score);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${_game.correct}/${StroopGame.totalRounds} correct — $score pts ✓')));
  }

  void _restart() {
    setState(() {
      _game = StroopGame();
      _stopwatch
        ..stop()
        ..reset();
      _finished = false;
      _feedback = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = context.watch<GamesProvider>().statsFor('color');
    final round = _game.current;
    return Scaffold(
      appBar: AppBar(title: const Text('Color Match')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StatsLine(statsText(
              plays: stats.playCount,
              best: stats.bestScore,
              recent: stats.recentScore,
              unit: ' pts')),
          const SizedBox(height: 4),
          Text('Round ${(_game.index + 1).clamp(1, StroopGame.totalRounds)} of ${StroopGame.totalRounds} · tap the INK color',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          if (!_finished)
            Center(
              child: Text(
                stroopChoices[round.word].name.toUpperCase(),
                style: theme.textTheme.displaySmall?.copyWith(
                  color: stroopChoices[round.ink].color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            Center(
              child: Text(
                'Session complete ✓',
                style: theme.textTheme.titleLarge,
              ),
            ),
          const SizedBox(height: 16),
          if (!_finished)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final c in stroopChoices)
                  FilledButton.tonal(
                    onPressed: () => _answer(c.name),
                    child: Text(c.name),
                  ),
              ],
            ),
          if (_feedback != null) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(_feedback!,
                  style: theme.textTheme.bodyMedium),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _restart,
            icon: const Icon(Icons.refresh),
            label: const Text('Restart'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
