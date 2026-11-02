import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Optional 60-second breathing reset.
/// Calm, minimal, no medical claims — just a timed breathing aid.
Future<void> showBreathingReset(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _BreathingDialog(),
  );
}

class _BreathingDialog extends StatefulWidget {
  const _BreathingDialog();

  @override
  State<_BreathingDialog> createState() => _BreathingDialogState();
}

class _BreathingDialogState extends State<_BreathingDialog> {
  static const int totalSeconds = 60;
  int _remaining = totalSeconds;
  Timer? _timer;
  bool _running = false;
  bool _done = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 14s cycle: inhale 4, hold 4, exhale 6.
  String get _phase {
    if (_done) return 'Done';
    final elapsed = totalSeconds - _remaining;
    final t = elapsed % 14;
    if (t < 4) return 'Breathe in…';
    if (t < 8) return 'Hold…';
    return 'Breathe out…';
  }

  double get _scale {
    if (!_running && _remaining == totalSeconds) return 1.0;
    final elapsed = totalSeconds - _remaining;
    final t = elapsed % 14;
    if (t < 4) return 1.0 + (t / 4) * 0.35;
    if (t < 8) return 1.35;
    return 1.35 - ((t - 8) / 6) * 0.35;
  }

  void _toggle() {
    if (_done) {
      setState(() {
        _remaining = totalSeconds;
        _done = false;
        _running = true;
      });
      _startTimer();
      return;
    }
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
    } else {
      setState(() => _running = true);
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remaining <= 1) {
        t.cancel();
        setState(() {
          _remaining = 0;
          _running = false;
          _done = true;
        });
        HapticFeedback.mediumImpact();
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      title: const Text('60-second breathing reset'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: _done ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(seconds: 1),
              curve: Curves.easeInOut,
              width: 120 * _scale,
              height: 120 * _scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primaryContainer,
              ),
              alignment: Alignment.center,
              child: Text('$_remaining',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(color: scheme.onPrimaryContainer)),
            ),
          ),
          const SizedBox(height: 16),
          Text(_phase, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            _done
                ? 'Notice how you feel — you can log it in your check-in below.'
                : 'A short pause. No score, no streak, just breathing.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _timer?.cancel();
            Navigator.of(context).pop();
          },
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _toggle,
          child: Text(_done
              ? 'Restart'
              : _running
                  ? 'Pause'
                  : 'Start'),
        ),
      ],
    );
  }
}
