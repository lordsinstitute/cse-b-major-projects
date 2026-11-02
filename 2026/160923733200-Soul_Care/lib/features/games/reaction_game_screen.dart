import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/app_widgets.dart';
import 'game_widgets.dart';
import 'games_provider.dart';
import 'memory_game_screen.dart' show statsText;

/// Pure reaction-time math over completed round times (ms).
int reactionAverage(List<int> ms) =>
    (ms.reduce((a, b) => a + b) / ms.length).round();
int reactionFastest(List<int> ms) => ms.reduce(min);

enum _Phase { idle, waiting, ready, foul }

/// 5-round reaction test. Early taps foul the round (retried, not scored).
class ReactionGameScreen extends StatefulWidget {
  const ReactionGameScreen({super.key});

  @override
  State<ReactionGameScreen> createState() => _ReactionGameScreenState();
}

class _ReactionGameScreenState extends State<ReactionGameScreen> {
  static const int rounds = 5;
  _Phase _phase = _Phase.idle;
  final List<int> _times = [];
  Timer? _timer;
  Stopwatch? _watch;
  final _random = Random();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startSession() {
    setState(() {
      _times.clear();
      _startRound();
    });
  }

  void _startRound() {
    _phase = _Phase.waiting;
    _timer?.cancel();
    _timer = Timer(
      Duration(milliseconds: 1200 + _random.nextInt(1800)),
      () {
        if (!mounted) return;
        setState(() {
          _phase = _Phase.ready;
          _watch = Stopwatch()..start();
        });
      },
    );
  }

  Future<void> _tap() async {
    switch (_phase) {
      case _Phase.idle:
        _startSession();
        setState(() {});
      case _Phase.waiting:
        // Foul — too soon. Retry the same round.
        _timer?.cancel();
        setState(() => _phase = _Phase.foul);
      case _Phase.foul:
        _startRound();
        setState(() {});
      case _Phase.ready:
        _watch?.stop();
        final ms = _watch!.elapsedMilliseconds;
        _times.add(ms);
        if (_times.length >= rounds) {
          _phase = _Phase.idle;
          final avg = reactionAverage(_times);
          await context.read<GamesProvider>().record('reaction', avg);
          if (!mounted) return;
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Session average: $avg ms ✓')));
        } else {
          _startRound();
          setState(() {});
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stats = context.watch<GamesProvider>().statsFor('reaction');
    final bg = switch (_phase) {
      _Phase.ready => scheme.primaryContainer,
      _Phase.foul => scheme.errorContainer,
      _ => scheme.surfaceContainerHighest,
    };
    final label = switch (_phase) {
      _Phase.idle => _times.isEmpty
          ? 'Tap to start — 5 rounds. Tap the moment it turns green.'
          : 'Tap to play again.',
      _Phase.waiting => 'Wait for green…',
      _Phase.ready => 'TAP!',
      _Phase.foul => 'Too soon! Tap to retry the round.',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Reaction Time')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StatsLine(statsText(
              plays: stats.playCount,
              best: stats.bestScore,
              recent: stats.recentScore,
              unit: ' ms avg')),
          const SizedBox(height: 4),
          Text(
              _times.isEmpty
                  ? 'Round 0/$rounds'
                  : 'Round ${_times.length}/$rounds · Avg: ${reactionAverage(_times)} ms · Fastest: ${reactionFastest(_times)} ms',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _tap,
            child: Container(
              height: 280,
              decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(16)),
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(label,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_times.isNotEmpty)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('This session',
                      style: theme.textTheme.titleSmall),
                  for (var i = 0; i < _times.length; i++)
                    Text('Round ${i + 1}: ${_times[i]} ms',
                        style: theme.textTheme.bodyMedium),
                ],
              ),
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
