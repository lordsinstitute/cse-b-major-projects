import 'package:flutter/material.dart';

import '../../../core/wellness/wellness_score.dart';
import '../../../core/widgets/app_widgets.dart';

/// Score transparency: total, components, change, and contributing data.
/// Only references actual logged values — no invented explanations.
class ScoreDetailSheet extends StatelessWidget {
  final WellnessScore score;

  const ScoreDetailSheet({super.key, required this.score});

  static Future<void> show(BuildContext context, WellnessScore score) {
    return showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: ScoreDetailSheet(score: score),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, int)>[
      ('Sleep', score.sleepScore),
      ('Movement', score.movementScore),
      ('Hydration', score.hydrationScore),
      ('Mind', score.mindScore),
      ('Stress', score.stressScore),
      ('Consistency', score.consistencyScore),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Wellness Score', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${score.totalScore}',
                    style: theme.textTheme.displaySmall),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    score.change == null
                        ? 'based on your logged data'
                        : score.change! > 0
                            ? '▲ ${score.change} vs previous logged day'
                            : score.change! < 0
                                ? '▼ ${-score.change!} vs previous logged day'
                                : 'unchanged vs previous logged day',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final r in rows) ...[
              _ComponentRow(
                label: r.$1,
                value: r.$2,
                detail: score.contributions[r.$1],
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
            AppCard(
              child: Text(score.explanation,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
            if (score.previousScore != null) ...[
              const SizedBox(height: 8),
              Text('Previous logged day: ${score.previousScore}',
                  style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComponentRow extends StatelessWidget {
  final String label;
  final int value;
  final String? detail;

  const _ComponentRow(
      {required this.label, required this.value, this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            Text('$value', style: theme.textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: value / 100,
            minHeight: 8,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(detail!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ],
    );
  }
}
