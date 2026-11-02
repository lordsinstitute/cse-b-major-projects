import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/utils/utils.dart';
import '../../core/widgets/app_widgets.dart';
import 'life_twin_engine.dart';
import 'life_twin_provider.dart';

/// /life-twin — SoulCare Life Twin.
///
/// An interactive visualization of the user's *tracked* wellness state.
/// Illustrative only — NOT a medical digital twin, never a clinical model.
/// All calculations happen locally on-device from logged records.
class LifeTwinScreen extends StatelessWidget {
  const LifeTwinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LifeTwinProvider()..load(rangeDays: 30),
      child: const _LifeTwinBody(),
    );
  }
}

class _LifeTwinBody extends StatefulWidget {
  const _LifeTwinBody();

  @override
  State<_LifeTwinBody> createState() => _LifeTwinBodyState();
}

class _LifeTwinBodyState extends State<_LifeTwinBody> {
  LifeTwinDimension _selected = LifeTwinDimension.sleep;
  bool _scenarioOn = false;
  double _extraSleep = 0;
  double _extraExercise = 0;
  double _calmer = 0;
  double _extraWater = 0;

  void _resetScenario() {
    setState(() {
      _extraSleep = 0;
      _extraExercise = 0;
      _calmer = 0;
      _extraWater = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<LifeTwinProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = prov.state;

    final scenario = (state != null && state.hasData && _scenarioOn)
        ? projectScenario(
            base: state,
            extraSleepHours: _extraSleep,
            extraExerciseMin: _extraExercise,
            calmerStress: _calmer,
            extraWaterGlasses: _extraWater,
          )
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SoulCare Life Twin'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/home'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => prov.load(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Your tracked wellness, visualized',
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text(
              'An interactive picture of your logged sleep, energy, stress, movement, hydration, mindfulness and consistency. Illustrative only — not a medical model, not a diagnosis.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (prov.loading && state == null)
              const AppCard(
                  child: AppLoading(message: 'Building your twin…'))
            else if (state == null || !state.hasData)
              _ZeroState(onRetry: () => prov.load())
            else ...[
              _StateCard(state: state),
              const SizedBox(height: 12),
              _RangeSelector(
                current: prov.rangeDays,
                onPick: (d) => prov.load(rangeDays: d),
              ),
              const SizedBox(height: 12),
              _TwinVisual(
                state: state,
                selected: _selected,
                scenario: scenario,
                onSelect: (dim) => setState(() => _selected = dim),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _DetailPanel(
                  key: ValueKey(
                      '${prov.rangeDays}-${_selected.name}-${state.daysContributing}'),
                  state: state,
                  selected: _selected,
                ),
              ),
              const SizedBox(height: 12),
              _RelationshipGraph(
                  state: state, selected: _selected),
              const SizedBox(height: 12),
              _ScenarioCard(
                enabled: _scenarioOn,
                onToggle: (v) => setState(() => _scenarioOn = v),
                extraSleep: _extraSleep,
                extraExercise: _extraExercise,
                calmer: _calmer,
                extraWater: _extraWater,
                onSleep: (v) => setState(() => _extraSleep = v),
                onExercise: (v) =>
                    setState(() => _extraExercise = v),
                onCalmer: (v) => setState(() => _calmer = v),
                onWater: (v) => setState(() => _extraWater = v),
                onReset: _resetScenario,
                state: state,
                scenario: scenario,
              ),
              const SizedBox(height: 12),
              Text(
                'All visualization calculations happen on this device. No health data leaves your phone for this feature.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
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

class _ZeroState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ZeroState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.hub_outlined,
              size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Your twin is waiting for data',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            'Log a few days under Today — sleep, movement, water, mind and stress check-ins all feed the twin. Nothing is guessed or filled in.',
            style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.go('/today'),
            child: const Text('Log today'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
              onPressed: onRetry, child: const Text('Refresh')),
        ],
      ),
    );
  }
}

/// Central personal state: overall index, recent change, confidence, days.
class _StateCard extends StatelessWidget {
  final LifeTwinState state;
  const _StateCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final overall = state.overallIndex?.round();
    final change = state.recentChange;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SoulCare Wellness State',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${overall ?? '–'}',
                  style: theme.textTheme.displaySmall),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  overall == null ? '' : getScoreLabel(overall),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(Icons.trending_flat,
                    size: 16, color: scheme.primary),
                label: Text(change == null
                    ? 'Change: keep logging'
                    : 'Recent change: ${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}'),
              ),
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(Icons.verified_outlined,
                    size: 16, color: scheme.primary),
                label: Text(
                    'Confidence: ${state.confidence}'),
              ),
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(Icons.calendar_month_outlined,
                    size: 16, color: scheme.primary),
                label: Text(
                    '${state.daysContributing} of ${state.daysInWindow} days'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(state.confidenceReason,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  final int current;
  final ValueChanged<int> onPick;
  const _RangeSelector({required this.current, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Time period',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              segments: [
                for (final d in LifeTwinRanges.options)
                  ButtonSegment(value: d, label: Text(LifeTwinRanges.label(d))),
              ],
              selected: {current},
              onSelectionChanged: (s) => onPick(s.first),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Patterns are only described within your logged data — no longer-term claims are made.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Central radar visualization + tappable dimension nodes.
class _TwinVisual extends StatelessWidget {
  final LifeTwinState state;
  final LifeTwinDimension selected;
  final LifeTwinScenarioResult? scenario;
  final ValueChanged<LifeTwinDimension> onSelect;
  const _TwinVisual({
    required this.state,
    required this.selected,
    required this.scenario,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dims = LifeTwinDimension.values;
    final values = [
      for (final d in dims) (state.dimensions[d]?.average ?? 0) / 100,
    ];
    final scenValues = scenario == null
        ? null
        : [
            for (final d in dims)
              ((scenario!.hypotheticalAverages[d] ?? 0)) / 100,
          ];
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Life Twin', style: theme.textTheme.titleSmall),
              const Spacer(),
              if (scenario != null)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Scenario'),
                  backgroundColor:
                      scheme.secondaryContainer,
                )
              else
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('My Data'),
                  backgroundColor: scheme.primaryContainer,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a dimension to explore its trend, supporting data and observed relationships.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Center(
            child: TweenAnimationBuilder<double>(
              // Re-key on data so range/metric/scenario changes replay
              // the transition smoothly instead of snapping.
              key: ValueKey(
                  '${values.map((v) => v.toStringAsFixed(3)).join(',')}|${scenValues?.map((v) => v.toStringAsFixed(3)).join(',')}|${dims.indexOf(selected)}'),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 350),
              builder: (context, t, _) => CustomPaint(
                size: const Size(260, 260),
                painter: _RadarPainter(
                  values: values,
                  scenarioValues: scenValues,
                  progress: t,
                  selected: dims.indexOf(selected),
                  primary: scheme.primary,
                  secondary: scheme.secondary,
                  grid: scheme.outlineVariant,
                  labels: [for (final d in dims) d.label],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in dims)
                ChoiceChip(
                  selected: d == selected,
                  label: Text(
                      '${d.label} · ${state.dimensions[d]?.average?.round() ?? '–'}'),
                  onSelected: (_) => onSelect(d),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<double> values; // 0..1 target
  final List<double>? scenarioValues;
  final double progress; // 0..1 intro animation
  final int selected;
  final Color primary;
  final Color secondary;
  final Color grid;
  final List<String> labels;

  _RadarPainter({
    required this.values,
    required this.scenarioValues,
    required this.progress,
    required this.selected,
    required this.primary,
    required this.secondary,
    required this.grid,
    required this.labels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 28;
    Offset at(int i, double r) {
      final angle = -math.pi / 2 + i * 2 * math.pi / n;
      return Offset(center.dx + r * math.cos(angle),
          center.dy + r * math.sin(angle));
    }

    final gridPaint = Paint()
      ..color = grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final f in [0.25, 0.5, 0.75, 1.0]) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final p = at(i, radius * f);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
      for (var i = 0; i < n; i++) {
        canvas.drawLine(center, at(i, radius), gridPaint);
      }
    }

    void drawPoly(List<double> vs, Color color, bool fill) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final p = at(i, radius * (vs[i] * progress).clamp(0.0, 1.0));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      if (fill) {
        canvas.drawPath(
            path, Paint()..color = color.withValues(alpha: 0.18));
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeJoin = StrokeJoin.round);
      for (var i = 0; i < n; i++) {
        final p = at(i, radius * (vs[i] * progress).clamp(0.0, 1.0));
        canvas.drawCircle(
            p,
            i == selected ? 6 : 4,
            Paint()
              ..color = i == selected ? color : color.withValues(alpha: 0.7));
      }
    }

    drawPoly(values, primary, true);
    final scen = scenarioValues;
    if (scen != null) {
      // Dashed-style overlay: draw as a second stroked polygon.
      drawPoly(scen, secondary, false);
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < n; i++) {
      final p = at(i, radius + 14);
      tp.text = TextSpan(
        text: labels[i],
        style: TextStyle(
          fontSize: i == selected ? 13 : 11,
          fontWeight: i == selected ? FontWeight.bold : FontWeight.normal,
          color: i == selected
              ? primary.withValues(alpha: 1)
              : const Color(0xFF757575),
        ),
      );
      tp.layout();
      canvas.save();
      canvas.translate(
          (p.dx - tp.width / 2).clamp(0, size.width - tp.width),
          (p.dy - tp.height / 2).clamp(0, size.height - tp.height));
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.values != values ||
      old.scenarioValues != scenarioValues ||
      old.progress != progress ||
      old.selected != selected ||
      old.primary != primary;
}

/// Detail panel: average, trend, best/lowest day, previous-period change,
/// related observations. Association-only language throughout.
class _DetailPanel extends StatelessWidget {
  final LifeTwinState state;
  final LifeTwinDimension selected;
  const _DetailPanel(
      {super.key, required this.state, required this.selected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = state.dimensions[selected]!;
    final related = state.relationships
        .where((r) => r.from == selected || r.to == selected)
        .take(3)
        .toList();
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${selected.label} — details',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(selected.whatItShows,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          if (!s.hasData)
            Text('Not enough logged ${selected.label.toLowerCase()} data in this period. Keep logging to discover this pattern.',
                style: theme.textTheme.bodyMedium)
          else ...[
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _Stat(
                    label: 'Average',
                    value: s.average!.toStringAsFixed(0)),
                _Stat(
                    label: 'Trend',
                    value: s.trend == null
                        ? 'keep logging'
                        : '${s.trend! >= 0 ? '+' : ''}${s.trend!.toStringAsFixed(1)}'),
                _Stat(
                    label: 'Best day',
                    value:
                        '${s.best!.toStringAsFixed(0)} · ${s.bestDay}'),
                _Stat(
                    label: 'Lowest day',
                    value:
                        '${s.worst!.toStringAsFixed(0)} · ${s.worstDay}'),
                _Stat(
                    label: 'Vs previous period',
                    value: s.changeVsPrevious == null
                        ? 'keep logging'
                        : '${s.changeVsPrevious! >= 0 ? '+' : ''}${s.changeVsPrevious!.toStringAsFixed(1)}'),
                _Stat(
                    label: 'Days',
                    value: '${s.count} logged'),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
                height: 120,
                child: _TrendSpark(
                    values: _selectedValues(s.series, selected))),
            const SizedBox(height: 8),
            const SectionHeader(title: 'Related observations'),
            const SizedBox(height: 4),
            if (related.isEmpty)
              Text('Keep logging to discover this pattern.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant))
            else
              for (final r in related)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${r.from.label} ↔ ${r.to.label}: ${r.label.toLowerCase()} across ${r.overlap} days (association only — one does not prove the other causes the other).',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

/// Extracts the selected dimension's values in chronological order.
List<double> _selectedValues(
    List<LifeTwinDay> series, LifeTwinDimension selected) {
  final out = <double>[];
  for (final d in series) {
    final v = d.values[selected];
    if (v != null) out.add(v);
  }
  return out;
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          Text(value, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _TrendSpark extends StatelessWidget {
  final List<double> values;
  const _TrendSpark({required this.values});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (values.length < 2) {
      return const Center(child: Text('Log more days to see a trend.'));
    }
    final spots = <FlSpot>[
      for (var i = 0; i < values.length; i++)
        FlSpot(i.toDouble(), values[i].clamp(0, 100)),
    ];
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (spots.length - 1).toDouble(),
        minY: 0,
        maxY: 100,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        titlesData: const FlTitlesData(
          topTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles:
              AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 2.5,
            color: scheme.primary,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
                show: true,
                color: scheme.primary.withValues(alpha: 0.12)),
          ),
        ],
      ),
    );
  }
}

/// Relationship tree for the selected dimension (association-only).
class _RelationshipGraph extends StatelessWidget {
  final LifeTwinState state;
  final LifeTwinDimension selected;
  const _RelationshipGraph({required this.state, required this.selected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rels = state.relationships
        .where((r) => r.from == selected || r.to == selected)
        .toList();
    final expectedPeers = _expectedPeers(selected);
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How ${selected.label} relates in your data',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text('Observed patterns only — never causes.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          // Tree root.
          Row(
            children: [
              Icon(Icons.hub_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Text(selected.label,
                  style: theme.textTheme.titleMedium),
            ],
          ),
          for (final peer in expectedPeers) ...[
            Row(
              children: [
                const SizedBox(width: 12),
                Text('│',
                    style: TextStyle(color: scheme.outline)),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('├── ',
                    style: TextStyle(color: scheme.outline)),
                Expanded(
                  child: _peerRow(context, peer, rels),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Relationships appear after at least $kLifeTwinMinOverlap overlapping logged days.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  List<LifeTwinDimension> _expectedPeers(LifeTwinDimension dim) {
    if (dim == LifeTwinDimension.sleep) {
      return const [
        LifeTwinDimension.stress,
        LifeTwinDimension.energy,
        LifeTwinDimension.consistency,
      ];
    }
    return LifeTwinDimension.values
        .where((d) => d != dim)
        .take(3)
        .toList();
  }

  Widget _peerRow(BuildContext context, LifeTwinDimension peer,
      List<ObservedRelationship> rels) {
    final theme = Theme.of(context);
    ObservedRelationship? match;
    for (final r in rels) {
      if (r.from == peer || r.to == peer) {
        match = r;
        break;
      }
    }
    if (match == null) {
      return Text(
        '${peer.label} → Keep logging to discover this pattern.',
        style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant),
      );
    }
    final m = match;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'observed relationship → ${peer.label}',
          style: theme.textTheme.bodyMedium,
        ),
        Text(
          '${m.label} · ${m.overlap} days together',
          style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Scenario mode: hypothetical adjustments, never touching real data.
class _ScenarioCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final double extraSleep;
  final double extraExercise;
  final double calmer;
  final double extraWater;
  final ValueChanged<double> onSleep;
  final ValueChanged<double> onExercise;
  final ValueChanged<double> onCalmer;
  final ValueChanged<double> onWater;
  final VoidCallback onReset;
  final LifeTwinState state;
  final LifeTwinScenarioResult? scenario;

  const _ScenarioCard({
    required this.enabled,
    required this.onToggle,
    required this.extraSleep,
    required this.extraExercise,
    required this.calmer,
    required this.extraWater,
    required this.onSleep,
    required this.onExercise,
    required this.onCalmer,
    required this.onWater,
    required this.onReset,
    required this.state,
    required this.scenario,
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
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Try a Scenario',
                        style: theme.textTheme.titleSmall),
                    Text(
                      'Hypothetical only — your real data is never modified.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(value: enabled, onChanged: onToggle),
            ],
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: enabled ? null : 0,
            child: enabled
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                              label: const Text('My Data'),
                              backgroundColor:
                                  scheme.primaryContainer),
                          if (scenario != null)
                            Chip(
                                label: const Text('Scenario'),
                                backgroundColor:
                                    scheme.secondaryContainer),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _Slider(
                          label:
                              'More sleep: +${extraSleep.toStringAsFixed(1)}h',
                          value: extraSleep,
                          max: 2,
                          divisions: 4,
                          onChanged: onSleep),
                      _Slider(
                          label:
                              'More exercise: +${extraExercise.toStringAsFixed(0)} min',
                          value: extraExercise,
                          max: 90,
                          divisions: 6,
                          onChanged: onExercise),
                      _Slider(
                          label:
                              'Lower stress: +${calmer.toStringAsFixed(0)} calm',
                          value: calmer,
                          max: 30,
                          divisions: 6,
                          onChanged: onCalmer),
                      _Slider(
                          label:
                              'Better hydration: +${extraWater.toStringAsFixed(1)} glasses',
                          value: extraWater,
                          max: 4,
                          divisions: 4,
                          onChanged: onWater),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonal(
                              onPressed: () {
                                onSleep(1);
                                onExercise(0);
                                onCalmer(0);
                                onWater(0);
                              },
                              child: const Text('Better Sleep')),
                          FilledButton.tonal(
                              onPressed: () {
                                onSleep(0);
                                onExercise(60);
                                onCalmer(0);
                                onWater(0);
                              },
                              child: const Text('More Movement')),
                          FilledButton.tonal(
                              onPressed: () {
                                onSleep(0);
                                onExercise(0);
                                onCalmer(10);
                                onWater(0);
                              },
                              child: const Text('Lower Stress')),
                          FilledButton.tonal(
                              onPressed: () {
                                onSleep(0);
                                onExercise(0);
                                onCalmer(0);
                                onWater(2);
                              },
                              child: const Text('Better Hydration')),
                          OutlinedButton.icon(
                            onPressed: onReset,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Reset'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (scenario != null) ...[
                        Row(
                          children: [
                            Expanded(
                                child: _BigNumber(
                                    label: 'My Data',
                                    value: state.overallIndex!
                                        .round())),
                            Expanded(
                                child: _BigNumber(
                                    label: 'Scenario',
                                    value: scenario!
                                        .hypotheticalOverall
                                        .round())),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text('Change',
                                      style: theme
                                          .textTheme.labelMedium
                                          ?.copyWith(
                                              color: scheme
                                                  .onSurfaceVariant)),
                                  Text(
                                    '${scenario!.deltaVsActual >= 0 ? '+' : ''}${scenario!.deltaVsActual.toStringAsFixed(1)}',
                                    style: theme
                                        .textTheme.headlineSmall
                                        ?.copyWith(
                                            color: scenario!
                                                        .deltaVsActual >
                                                    0
                                                ? scheme.primary
                                                : scheme.onSurface),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          scenario!.contributors.isEmpty
                              ? 'Move a slider or pick a preset to preview a hypothetical shift.'
                              : 'Driven by: ${scenario!.contributors.join(' · ')} (hypothetical).',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        for (final d
                            in LifeTwinDimension.values)
                          if (state.dimensions[d]?.average !=
                              null)
                            Padding(
                              padding: const EdgeInsets.only(
                                  bottom: 6),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${d.label}: ${state.dimensions[d]!.average!.toStringAsFixed(0)} → ${scenario!.hypotheticalAverages[d]!.toStringAsFixed(0)}',
                                      style: theme
                                          .textTheme.bodySmall),
                                  const SizedBox(height: 2),
                                  ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(
                                            999),
                                    child:
                                        LinearProgressIndicator(
                                      value: (scenario!
                                                  .hypotheticalAverages[
                                              d]! /
                                          100),
                                      minHeight: 6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        Text(
                          'Hypothetical preview from fixed illustrative adjustments — not a prediction of what will happen.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(
                                  color:
                                      scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  const _Slider({
    required this.label,
    required this.value,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        Slider(
          min: 0,
          max: max,
          divisions: divisions,
          value: value,
          label: label,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _BigNumber extends StatelessWidget {
  final String label;
  final int value;
  const _BigNumber({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant)),
        Text('$value', style: theme.textTheme.displaySmall),
      ],
    );
  }
}
