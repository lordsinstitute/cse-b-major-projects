import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/app_widgets.dart';
import 'game_widgets.dart';
import 'games_provider.dart';
import 'memory_game_screen.dart' show statsText;
import 'scramble_engine.dart';

class ScrambleGameScreen extends StatefulWidget {
  const ScrambleGameScreen({super.key});

  @override
  State<ScrambleGameScreen> createState() => _ScrambleGameScreenState();
}

class _ScrambleGameScreenState extends State<ScrambleGameScreen> {
  late ScrambleGame _game;
  final _controller = TextEditingController();
  final _stopwatch = Stopwatch();
  bool _started = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _game = ScrambleGame();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_started) {
      setState(() => _started = true);
      _stopwatch.start();
    }
    final ok = _game.guess(_controller.text);
    _controller.clear();
    setState(() {
      _feedback = ok ? 'Correct ✓' : 'Not quite — try again.';
    });
    if (_game.complete) _finish();
  }

  Future<void> _finish() async {
    _stopwatch.stop();
    final score = scrambleScore(
      correct: _game.correct,
      incorrect: _game.incorrect,
      seconds: _stopwatch.elapsed.inSeconds,
    );
    await context.read<GamesProvider>().record('scramble', score);
    if (!mounted) return;
    setState(() {});
  }

  void _restart() {
    setState(() {
      _game = ScrambleGame();
      _controller.clear();
      _stopwatch
        ..stop()
        ..reset();
      _started = false;
      _feedback = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = context.watch<GamesProvider>().statsFor('scramble');
    return Scaffold(
      appBar: AppBar(title: const Text('Word Scramble')),
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
              _game.complete
                  ? 'Complete: ${_game.correct} correct, ${_game.incorrect} wrong in ${_stopwatch.elapsed.inSeconds}s'
                  : 'Word ${_game.index + 1} of ${_game.words.length} · Correct: ${_game.correct} · Wrong: ${_game.incorrect}',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          if (!_game.complete) ...[
            AppCard(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  _game.current.split('').join(' '),
                  style: theme.textTheme.headlineMedium?.copyWith(
                      letterSpacing: 2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  labelText: 'Your answer',
                  hintText: 'Type the unscrambled word'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            if (_feedback != null)
              Text(_feedback!, style: theme.textTheme.bodyMedium),
            FilledButton(
              onPressed: _submit,
              child: const Text('Check'),
            ),
          ] else
            AppCard(
              child: Text(
                'Nice — a calm mind moment. Play again any time.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _restart,
            icon: const Icon(Icons.refresh),
            label: const Text('Restart'),
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
