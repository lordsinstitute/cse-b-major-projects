import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'game_widgets.dart';
import 'games_provider.dart';

/// Deterministic memory-match score: perfect play (one attempt per pair)
/// scores 1000; each extra attempt and each 2 seconds cost points.
int memoryScore(
    {required int attempts, required int pairs, required int seconds}) {
  final extra = max(0, attempts - pairs);
  return max(0, 1000 - extra * 50 - (seconds ~/ 2) * 5);
}

class MemoryCardState {
  final int pairId;
  final IconData icon;
  bool faceUp = false;
  bool matched = false;

  MemoryCardState({required this.pairId, required this.icon});
}

/// Framework-free board logic: flip, match, attempts, restart.
class MemoryBoard {
  static const icons = [
    Icons.spa,
    Icons.water_drop,
    Icons.bedtime,
    Icons.directions_walk,
    Icons.self_improvement,
    Icons.favorite,
  ];

  final List<MemoryCardState> cards;
  int attempts = 0;
  int matchedPairs = 0;
  int? _firstIndex;
  bool lock = false;

  MemoryBoard._(this.cards);

  factory MemoryBoard.newGame({Random? random}) {
    final r = random ?? Random();
    final cards = <MemoryCardState>[];
    for (var i = 0; i < icons.length; i++) {
      cards.add(MemoryCardState(pairId: i, icon: icons[i]));
      cards.add(MemoryCardState(pairId: i, icon: icons[i]));
    }
    cards.shuffle(r);
    return MemoryBoard._(cards);
  }

  int get pairs => icons.length;
  bool get complete => matchedPairs >= pairs;
  int? get firstIndex => _firstIndex;

  /// Returns 'first', 'match', 'miss', or 'ignored'.
  String flip(int index) {
    if (lock) return 'ignored';
    final card = cards[index];
    if (card.faceUp || card.matched) return 'ignored';
    card.faceUp = true;
    if (_firstIndex == null) {
      _firstIndex = index;
      return 'first';
    }
    attempts++;
    final first = cards[_firstIndex!];
    _firstIndex = null;
    if (first.pairId == card.pairId) {
      first.matched = true;
      card.matched = true;
      matchedPairs++;
      return 'match';
    }
    lock = true;
    return 'miss';
  }

  /// Hides the two face-up unmatched cards after a miss preview.
  void hideMiss(int a, int b) {
    cards[a].faceUp = false;
    cards[b].faceUp = false;
    lock = false;
  }
}

class MemoryGameScreen extends StatefulWidget {
  const MemoryGameScreen({super.key});

  @override
  State<MemoryGameScreen> createState() => _MemoryGameScreenState();
}

class _MemoryGameScreenState extends State<MemoryGameScreen> {
  late MemoryBoard _board;
  final _stopwatch = Stopwatch();
  bool _finished = false;
  int? _pendingA;
  int? _pendingB;

  @override
  void initState() {
    super.initState();
    _board = MemoryBoard.newGame();
  }

  void _onTap(int index) {
    if (_finished) return;
    if (!_stopwatch.isRunning) _stopwatch.start();
    final result = _board.flip(index);
    if (result == 'ignored') return;
    if (result == 'miss') {
      // Find the two face-up unmatched cards for the preview hide.
      final open = <int>[];
      for (var i = 0; i < _board.cards.length; i++) {
        final c = _board.cards[i];
        if (c.faceUp && !c.matched) open.add(i);
      }
      _pendingA = open[0];
      _pendingB = open[1];
      setState(() {});
      Timer(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        setState(() => _board.hideMiss(_pendingA!, _pendingB!));
      });
      return;
    }
    if (_board.complete) _finish();
    setState(() {});
  }

  Future<void> _finish() async {
    _stopwatch.stop();
    _finished = true;
    final score = memoryScore(
      attempts: _board.attempts,
      pairs: _board.pairs,
      seconds: _stopwatch.elapsed.inSeconds,
    );
    await context.read<GamesProvider>().record('memory', score);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Complete in ${_board.attempts} attempts — $score pts ✓')));
  }

  void _restart() {
    setState(() {
      _board = MemoryBoard.newGame();
      _stopwatch
        ..stop()
        ..reset();
      _finished = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = context.watch<GamesProvider>().statsFor('memory');
    return Scaffold(
      appBar: AppBar(title: const Text('Memory Match')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StatsLine(statsText(
              plays: stats.playCount,
              best: stats.bestScore,
              recent: stats.recentScore,
              unit: ' pts')),
          const SizedBox(height: 4),
          Text('Attempts: ${_board.attempts} · Pairs: ${_board.matchedPairs}/${_board.pairs}',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8),
            itemCount: _board.cards.length,
            itemBuilder: (c, i) {
              final card = _board.cards[i];
              final shown = card.faceUp || card.matched;
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _onTap(i),
                child: Container(
                  decoration: BoxDecoration(
                    color: shown
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: shown
                      ? Icon(card.icon,
                          size: 32,
                          color: card.matched
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onPrimaryContainer)
                      : Icon(Icons.question_mark,
                          color: theme.colorScheme.onSurfaceVariant),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _restart,
            icon: const Icon(Icons.refresh),
            label: const Text('Restart'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Back to games'),
          ),
        ],
      ),
    );
  }
}

String statsText(
    {required int plays,
    required int? best,
    required int? recent,
    required String unit}) {
  if (plays == 0) return 'Not played yet.';
  return 'Plays: $plays · Best: ${best ?? '—'}$unit · Recent: ${recent ?? '—'}$unit';
}
