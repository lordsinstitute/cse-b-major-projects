import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'game_widgets.dart';
import 'bubble_engine.dart';
import 'games_provider.dart';
import 'memory_game_screen.dart' show statsText;

/// Bubble Pop: 30 calm seconds — pop bubbles as they appear.
/// Misses only reset the combo, never punish.
class BubbleGameScreen extends StatefulWidget {
  const BubbleGameScreen({super.key});

  @override
  State<BubbleGameScreen> createState() => _BubbleGameScreenState();
}

class _BubbleGameScreenState extends State<BubbleGameScreen> {
  static const int sessionSeconds = 30;

  late BubblePop _game;
  Timer? _clock;
  Timer? _spawner;
  int _left = sessionSeconds;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _game = BubblePop();
    _start();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _spawner?.cancel();
    super.dispose();
  }

  void _start() {
    _clock?.cancel();
    _spawner?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _left--);
      if (_left <= 0) _finish();
    });
    _spawner =
        Timer.periodic(const Duration(milliseconds: 800), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_finished) return;
      setState(() => _game.spawn());
    });
  }

  void _pop(int index) {
    if (_finished) return;
    setState(() => _game.pop(index));
  }

  Future<void> _finish() async {
    if (_finished) return;
    _finished = true;
    _clock?.cancel();
    _spawner?.cancel();
    final score = bubbleScore(
      popped: _game.popped,
      maxCombo: _game.maxCombo,
      wrong: _game.wrong,
    );
    await context.read<GamesProvider>().record('bubbles', score);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${_game.popped} popped · best combo ${_game.maxCombo} — $score pts ✓')));
  }

  void _restart() {
    setState(() {
      _game = BubblePop();
      _left = sessionSeconds;
      _finished = false;
    });
    _start();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stats = context.watch<GamesProvider>().statsFor('bubbles');
    return Scaffold(
      appBar: AppBar(title: const Text('Bubble Pop')),
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
              _finished
                  ? 'Time! Nicely popped.'
                  : '$_left seconds left · ${_game.popped} popped',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8),
            itemCount: BubblePop.gridSize,
            itemBuilder: (c, i) {
              final lit = _game.active[i];
              return InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _finished ? null : () => _pop(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: lit
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                    border: Border.all(
                      color: lit
                          ? scheme.primary
                          : scheme.outlineVariant,
                      width: lit ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: lit
                      ? Icon(Icons.circle,
                          color: scheme.primary, size: 28)
                      : null,
                ),
              );
            },
          ),
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
