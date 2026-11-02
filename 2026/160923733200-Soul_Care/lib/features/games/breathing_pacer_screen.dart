import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/app_widgets.dart';
import 'game_widgets.dart';
import 'games_provider.dart';
import 'memory_game_screen.dart' show statsText;

/// Calm guided breathing pacer: inhale 4s → hold 4s → exhale 6s,
/// for a chosen number of cycles, with pause and stop.
/// Completing the chosen cycles records one play (score = cycles).
class BreathingPacerScreen extends StatefulWidget {
  const BreathingPacerScreen({super.key});

  @override
  State<BreathingPacerScreen> createState() =>
      _BreathingPacerScreenState();
}

class _BreathingPacerScreenState extends State<BreathingPacerScreen> {
  static const _phases = ['Breathe in…', 'Hold…', 'Breathe out…'];
  static const _durations = [4, 4, 6];

  Timer? _timer;
  int _phaseIndex = 0;
  int _secondsLeft = _durations[0];
  int _targetCycles = 3;
  int _doneCycles = 0;
  bool _running = false;
  bool _complete = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    setState(() {
      _secondsLeft--;
      if (_secondsLeft <= 0) {
        _phaseIndex = (_phaseIndex + 1) % 3;
        if (_phaseIndex == 0) {
          _doneCycles++;
          if (_doneCycles >= _targetCycles) {
            _finish();
            return;
          }
        }
        _secondsLeft = _durations[_phaseIndex];
      }
    });
  }

  void _start() {
    _timer?.cancel();
    _timer =
        Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    setState(() {
      _running = true;
      _complete = false;
    });
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _running = false);
  }

  void _stop() {
    _timer?.cancel();
    setState(() {
      _running = false;
      _phaseIndex = 0;
      _secondsLeft = _durations[0];
      _doneCycles = 0;
      _complete = false;
    });
  }

  Future<void> _finish() async {
    _timer?.cancel();
    _running = false;
    _complete = true;
    await context
        .read<GamesProvider>()
        .record('breathing', _targetCycles);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$_targetCycles calm cycles complete ✓')));
  }

  double get _scale {
    // Gentle deterministic swell per phase second (display only).
    final elapsed = _durations[_phaseIndex] - _secondsLeft;
    switch (_phaseIndex) {
      case 0:
        return 1.0 + (elapsed / 4) * 0.3;
      case 1:
        return 1.3;
      default:
        return 1.3 - (elapsed / 6) * 0.3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stats = context.watch<GamesProvider>().statsFor('breathing');
    return Scaffold(
      appBar: AppBar(title: const Text('Breathing Pacer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StatsLine(statsText(
              plays: stats.playCount,
              best: stats.bestScore,
              recent: stats.recentScore,
              unit: ' cycles')),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(seconds: 1),
                  curve: Curves.easeInOut,
                  width: 140 * _scale,
                  height: 140 * _scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primaryContainer,
                  ),
                  alignment: Alignment.center,
                  child: Text('$_secondsLeft',
                      style: theme.textTheme.displaySmall?.copyWith(
                          color: scheme.onPrimaryContainer)),
                ),
                const SizedBox(height: 16),
                Text(_phases[_phaseIndex],
                    style: theme.textTheme.titleLarge),
                Text(
                    'Cycle ${_doneCycles + (_complete ? 0 : 1)} of $_targetCycles · Done: $_doneCycles',
                    style: theme.textTheme.bodyMedium),
                if (_complete)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Session complete — well done.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.primary)),
                  ),
                const SizedBox(height: 12),
                Text('Cycles', style: theme.textTheme.titleSmall),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      ChoiceChip(
                        label: Text('$i'),
                        selected: _targetCycles == i,
                        onSelected: _running
                            ? null
                            : (_) => setState(() {
                                  _targetCycles = i;
                                  _stop();
                                }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: _running ? _pause : _start,
                      child:
                          Text(_running ? 'Pause' : 'Start'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                        onPressed: _stop,
                        child: const Text('Stop')),
                  ],
                ),
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
