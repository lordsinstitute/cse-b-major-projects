import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'game_widgets.dart';
import 'echo_engine.dart';
import 'games_provider.dart';
import 'memory_game_screen.dart' show statsText;

/// Pattern Echo: watch the tiles flash, then repeat the pattern.
/// The pattern grows each level; a wrong tap ends the run.
class EchoGameScreen extends StatefulWidget {
  const EchoGameScreen({super.key});

  @override
  State<EchoGameScreen> createState() => _EchoGameScreenState();
}

class _EchoGameScreenState extends State<EchoGameScreen> {
  late EchoGame _game;
  bool _showing = true;
  int _flash = -1;
  Timer? _showTimer;
  bool _finished = false;

  static const _tileColors = [
    Colors.teal,
    Colors.blue,
    Colors.amber,
    Colors.pink,
  ];

  @override
  void initState() {
    super.initState();
    _game = EchoGame();
    _playSequence();
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    super.dispose();
  }

  void _playSequence() {
    _showTimer?.cancel();
    setState(() {
      _showing = true;
      _flash = -1;
    });
    final seq = [..._game.sequence];
    var i = 0;
    _showTimer =
        Timer.periodic(const Duration(milliseconds: 600), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (i >= seq.length) {
        t.cancel();
        if (mounted) {
          setState(() {
            _showing = false;
            _flash = -1;
          });
        }
        return;
      }
      setState(() => _flash = seq[i]);
      i++;
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted && _showing) setState(() => _flash = -1);
      });
    });
  }

  void _tap(int tile) {
    if (_finished || _showing || _game.over) return;
    final result = _game.tap(tile);
    if (result == 'over') {
      _finish();
    } else if (result == 'level') {
      _playSequence();
    } else {
      setState(() {});
    }
  }

  Future<void> _finish() async {
    _finished = true;
    _showTimer?.cancel();
    final score = echoScore(
        levels: _game.levelsCompleted, mistakes: _game.mistakes);
    await context.read<GamesProvider>().record('echo', score);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Reached level ${_game.level} — $score pts ✓')));
  }

  void _restart() {
    _showTimer?.cancel();
    setState(() {
      _game = EchoGame();
      _finished = false;
    });
    _playSequence();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = context.watch<GamesProvider>().statsFor('echo');
    return Scaffold(
      appBar: AppBar(title: const Text('Pattern Echo')),
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
              _game.over
                  ? 'Run over — nice focus.'
                  : _showing
                      ? 'Watch… (level ${_game.level})'
                      : 'Your turn — repeat it (level ${_game.level})',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8),
            itemCount: EchoGame.tileCount,
            itemBuilder: (c, i) {
              final lit = _flash == i;
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _tap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: lit
                        ? _tileColors[i]
                        : theme.colorScheme
                            .surfaceContainerHighest,
                    border: Border.all(
                      color: lit
                          ? _tileColors[i]
                          : theme.colorScheme.outlineVariant,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: lit
                      ? const Icon(Icons.circle,
                          color: Colors.white, size: 32)
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
