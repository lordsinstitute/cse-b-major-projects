import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import 'analytics_engine.dart';
import 'analytics_provider.dart';

/// /analytics — Analytics Lab.
///
/// A research/exploration view over the user's own historical data.
/// Everything is labeled as observed patterns — never medical conclusions,
/// never causal claims. Unavailable results are stated plainly.
class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AnalyticsProvider()..load(),
      child: const _AnalyticsBody(),
    );
  }
}

class _AnalyticsBody extends StatefulWidget {
  const _AnalyticsBody();

  @override
  State<_AnalyticsBody> createState() => _AnalyticsBodyState();
}

class _AnalyticsBodyState extends State<_AnalyticsBody> {
  AnalyticsMetric _metric = AnalyticsMetric.sleep;
  String? _expId;

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AnalyticsProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics Lab'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        actions: [
          if (prov.loaded)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Export analytics report',
              onPressed: () async {
                final path = await prov.shareReport();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(path == null
                      ? 'Could not export right now.'
                      : 'Analytics report exported ✓'),
                ));
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => prov.load(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Understand your patterns',
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text(
              'Exploratory views of your last ${AnalyticsProvider.windowDays} logged days. Observed patterns only — not medical conclusions, and correlation never means cause.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (prov.loading && !prov.loaded)
              const AppCard(
                  child: AppLoading(message: 'Crunching your logs…'))
            else if (!prov.loaded)
              AppCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.query_stats_outlined,
                        size: 48, color: scheme.primary),
                    const SizedBox(height: 12),
                    Text('Not enough history yet',
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      'Log a few days under Today and this lab fills with trends, observed correlations and unusual-day flags — all from real data.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.go('/today'),
                      child: const Text('Log today'),
                    ),
                  ],
                ),
              )
            else ...[
              _CompletenessCard(items: prov.completenessList()),
              const SizedBox(height: 12),
              _TrendCard(
                series: prov.series,
                metric: _metric,
                onMetric: (m) => setState(() => _metric = m),
              ),
              const SizedBox(height: 12),
              _MatrixCard(matrix: prov.matrix),
              const SizedBox(height: 12),
              _AnomalyCard(anomalies: prov.anomalies),
              const SizedBox(height: 12),
              _ExperimentCard(
                experiments: prov.experiments,
                selectedId: _expId,
                onPick: (id) => setState(() => _expId = id),
                analysis: _expId == null
                    ? null
                    : prov.analysisFor(prov.experiments.firstWhere(
                        (e) => e.id == _expId,
                        orElse: () => prov.experiments.first)),
              ),
              const SizedBox(height: 12),
              const _EducationCard(),
              const SizedBox(height: 24),
            ],
            if (prov.error != null) ...[
              const SizedBox(height: 8),
              Text(prov.error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Data completeness first — the guard against misleading analytics.
class _CompletenessCard extends StatelessWidget {
  final List<Completeness> items;
  const _CompletenessCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Data completeness',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text('Logged days in the last ${AnalyticsProvider.completenessDays} days.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          for (final c in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                      width: 92,
                      child: Text(c.metric.label,
                          style: theme.textTheme.bodyMedium)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: c.fraction,
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 84,
                    child: Text(c.label,
                        style: theme.textTheme.bodySmall,
                        textAlign: TextAlign.end),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Trend analysis: moving average chart + weekly/monthly + change detection.
class _TrendCard extends StatelessWidget {
  final Map<AnalyticsMetric, MetricSeries> series;
  final AnalyticsMetric metric;
  final ValueChanged<AnalyticsMetric> onMetric;
  const _TrendCard(
      {required this.series, required this.metric, required this.onMetric});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = series[metric] ?? MetricSeries(metric, const []);
    final ma = movingAverage(
        [for (final p in s.points) p.value], 7);
    final weeks = weeklyTrend(s.points);
    final months = monthlyTrend(s.points);
    final change =
        detectChange([for (final p in s.points) p.value]);
    final spots = <FlSpot>[
      for (var i = 0; i < s.points.length; i++)
        FlSpot(i.toDouble(), s.points[i].value),
    ];
    final maSpots = <FlSpot>[
      for (var i = 0; i < ma.length; i++)
        if (ma[i] != null) FlSpot(i.toDouble(), ma[i]!),
    ];

    String changeText() {
      if (change.delta == null) {
        return 'Not enough logged points to judge change yet (needs 6+).';
      }
      final dir = change.delta! > 0 ? 'higher' : 'lower';
      return 'Second half averaged ${change.secondAvg!.toStringAsFixed(1)}${metric.unit} vs ${change.firstAvg!.toStringAsFixed(1)}${metric.unit} in the first half '
          '(${change.points} points) — ${change.significant ? 'a notable shift in your logs' : 'a small shift, possibly just day-to-day variation'}. $dir does not mean better or worse on its own.';
    }

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Trend analysis', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in AnalyticsMetric.values)
                ChoiceChip(
                  selected: m == metric,
                  label: Text(m.label),
                  onSelected: (_) => onMetric(m),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (s.points.length < 2)
            Text('No logged ${metric.label.toLowerCase()} data in this window yet.',
                style: theme.textTheme.bodyMedium)
          else ...[
            SizedBox(
              height: 150,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  lineTouchData:
                      const LineTouchData(enabled: false),
                  titlesData: const FlTitlesData(
                    topTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: false,
                      barWidth: 1.5,
                      color: scheme.outline,
                      dotData: const FlDotData(show: false),
                    ),
                    if (maSpots.length >= 2)
                      LineChartBarData(
                        spots: maSpots,
                        isCurved: true,
                        barWidth: 2.5,
                        color: scheme.primary,
                        dotData: const FlDotData(show: false),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('Daily values (thin) with 7-day moving average (bold).',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            _StatRow(
                label: 'Weekly buckets',
                value: weeks.isEmpty
                    ? '—'
                    : weeks
                        .map((w) =>
                            '${w.label.substring(5)}: ${w.average?.toStringAsFixed(1) ?? '–'} (${w.count})')
                        .take(4)
                        .join(' · ')),
            _StatRow(
                label: 'Monthly trend',
                value: months.length < 2
                    ? 'needs 2+ months'
                    : '${months.first.average?.toStringAsFixed(1) ?? '–'} → ${months.last.average?.toStringAsFixed(1) ?? '–'}${metric.unit}'),
            _StatRow(
                label: 'Week change',
                value: bucketChange(weeks) == null
                    ? 'needs 2+ weeks'
                    : '${bucketChange(weeks)! >= 0 ? '+' : ''}${bucketChange(weeks)!.toStringAsFixed(1)}${metric.unit}'),
            const SizedBox(height: 4),
            Text(changeText(), style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 130,
              child: Text(label,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant))),
          Expanded(
              child:
                  Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// Interactive correlation matrix (neutral visualization).
class _MatrixCard extends StatelessWidget {
  final List<CorrelationCell> matrix;
  const _MatrixCard({required this.matrix});

  CorrelationCell? _cell(AnalyticsMetric a, AnalyticsMetric b) {
    for (final c in matrix) {
      if ((c.row == a && c.col == b) ||
          (c.row == b && c.col == a)) {
        return c;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metrics = AnalyticsMetric.values;
    final computed = matrix.where((c) => c.computed).length;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Observed correlations',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            '$computed of ${matrix.length} pairs have enough paired data. Tap any cell for details.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Table(
            children: [
              TableRow(
                children: [
                  const SizedBox.shrink(),
                  for (final m in metrics)
                    Center(
                      child: Text(m.label[0],
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant)),
                    ),
                ],
              ),
              for (final row in metrics)
                TableRow(
                  children: [
                    Text(row.label,
                        style: theme.textTheme.labelSmall),
                    for (final col in metrics)
                      _cellWidget(context, row, col),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final m in metrics)
                Text('${m.label[0]} = ${m.label}',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cellWidget(
      BuildContext context, AnalyticsMetric row, AnalyticsMetric col) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (row == col) {
      return Container(
        margin: const EdgeInsets.all(2),
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        ),
        child: Text('—',
            style: TextStyle(color: scheme.outline)),
      );
    }
    final cell = _cell(row, col);
    final r = cell?.r;
    final strength = r == null ? 0.0 : r.abs().clamp(0.0, 1.0);
    final bg = r == null
        ? Colors.transparent
        : (r >= 0 ? scheme.primary : scheme.secondary)
            .withValues(alpha: 0.12 + strength * 0.5);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: cell == null
          ? null
          : () => showModalBottomSheet(
                context: context,
                showDragHandle: true,
                builder: (_) => _CellSheet(cell: cell),
              ),
      child: Container(
        margin: const EdgeInsets.all(2),
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: bg,
          border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Text(
          r == null ? '·' : r.toStringAsFixed(2),
          style: theme.textTheme.labelMedium,
        ),
      ),
    );
  }
}

/// Cell detail: metrics, sample count, coefficient, range, explanation.
class _CellSheet extends StatelessWidget {
  final CorrelationCell cell;
  const _CellSheet({required this.cell});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${cell.row.label} vs ${cell.col.label}',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(cell.label,
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: scheme.primary)),
            const SizedBox(height: 12),
            _StatRow(
                label: 'Coefficient (r)',
                value: cell.r == null
                    ? 'unavailable'
                    : cell.r!.toStringAsFixed(2)),
            _StatRow(
                label: 'Paired days',
                value: '${cell.pairs} (needs $kMinCorrelationPairs+)'),
            _StatRow(
                label: 'Date range',
                value: cell.pairs == 0
                    ? '—'
                    : '${cell.startKey} → ${cell.endKey}'),
            const SizedBox(height: 8),
            AppCard(
              child: Text(cell.explanation,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Unusual days from the anomaly detector.
class _AnomalyCard extends StatelessWidget {
  final List<Anomaly> anomalies;
  const _AnomalyCard({required this.anomalies});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Unusual days', style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text('Days far from your own typical values — worth a look, never a diagnosis.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          if (anomalies.isEmpty)
            Text('No unusual days detected in this window. The detector needs $kMinAnomalyPoints+ logged points per metric.',
                style: theme.textTheme.bodyMedium)
          else
            for (final a in anomalies.take(10))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_outlined,
                        size: 16, color: scheme.secondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(a.description,
                          style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// Baseline-vs-experiment analysis for a chosen experiment.
class _ExperimentCard extends StatelessWidget {
  final List<Experiment> experiments;
  final String? selectedId;
  final ValueChanged<String?> onPick;
  final ExperimentAnalysis? analysis;
  const _ExperimentCard({
    required this.experiments,
    required this.selectedId,
    required this.onPick,
    required this.analysis,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Experiment analysis',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (experiments.isEmpty)
            Text('No experiments yet — start one in the Lab to analyze it here.',
                style: theme.textTheme.bodyMedium)
          else ...[
            DropdownButton<String>(
              value: selectedId,
              hint: const Text('Choose an experiment'),
              isExpanded: true,
              items: [
                for (final e in experiments)
                  DropdownMenuItem(
                      value: e.id, child: Text(e.title)),
              ],
              onChanged: onPick,
            ),
            if (analysis != null) ...[
              const SizedBox(height: 8),
              _StatRow(
                  label: 'Baseline mean',
                  value:
                      '${analysis!.baselineMean?.toStringAsFixed(1) ?? 'unavailable'}${analysis!.unit} (${analysis!.baselineN} days)'),
              _StatRow(
                  label: 'Experiment mean',
                  value:
                      '${analysis!.experimentMean?.toStringAsFixed(1) ?? 'unavailable'}${analysis!.unit} (${analysis!.experimentN} days)'),
              _StatRow(
                  label: 'Experiment median',
                  value:
                      '${analysis!.experimentMedian?.toStringAsFixed(1) ?? 'unavailable'}${analysis!.unit}'),
              _StatRow(
                  label: 'Difference',
                  value: analysis!.difference == null
                      ? 'unavailable'
                      : '${analysis!.difference! >= 0 ? '+' : ''}${analysis!.difference!.toStringAsFixed(1)}${analysis!.unit}'),
              _StatRow(
                  label: 'Completion',
                  value:
                      '${(analysis!.completionRate * 100).round()}%'),
              const SizedBox(height: 4),
              Text(analysis!.summary,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant)),
            ],
          ],
        ],
      ),
    );
  }
}

/// Educational mode: plain-language statistics primers.
class _EducationCard extends StatelessWidget {
  const _EducationCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Learn the ideas', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final entry in analyticsEducation.entries)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(entry.key,
                  style: theme.textTheme.bodyMedium),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(entry.value,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
                const SizedBox(height: 8),
              ],
            ),
        ],
      ),
    );
  }
}
