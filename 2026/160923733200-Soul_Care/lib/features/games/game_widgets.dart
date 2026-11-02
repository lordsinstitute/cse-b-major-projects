import 'package:flutter/material.dart';

/// Small muted stats line used by every game screen.
class StatsLine extends StatelessWidget {
  final String text;
  const StatsLine(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant));
  }
}
