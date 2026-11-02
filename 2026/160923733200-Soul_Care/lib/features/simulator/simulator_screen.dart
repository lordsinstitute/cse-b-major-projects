import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/app_widgets.dart';
import 'projection_engine.dart';
import 'simulator_controller.dart';

/// /future — illustrative wellness scenario sketches.
/// Explores "what if my pattern looked like this?" using a deterministic,
/// transparent formula. Never a medical prediction; never touches records.
class SimulatorScreen extends StatelessWidget {
  const SimulatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SimulatorController(),
      child: const _SimulatorBody(),
    );
  }
}

class _SimulatorBody extends StatelessWidget {
  const _SimulatorBody();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SimulatorController>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Future', style: theme.textTheme.headlineSmall),
        Text('Illustrative scenarios from your logged pattern',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        if (ctrl.loading)
          const AppCard(child: AppLoading(message: 'Reading your pattern…'))
        else if (!ctrl.hasBaseline)
          AppCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.insights_outlined,
                    size: 48, color: scheme.primary),
                const SizedBox(height: 12),
                Text('More data needed',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  'The simulator starts from your real logged pattern, and there isn\'t enough yet — nothing is guessed or filled in.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                for (final m in ctrl.baseline?.missing ?? const <String>[])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('• $m',
                        style: theme.textTheme.bodySmall),
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
          _BaselineCard(),
          const SizedBox(height: 12),
          _CurrentVsScenario(),
          const SizedBox(height: 12),
          _Controls(),
          const SizedBox(height: 12),
          _Presets(),
          const SizedBox(height: 12),
          _Trajectory(),
          const SizedBox(height: 12),
          _Comparison(),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

class _BaselineCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SimulatorController>();
    final theme = Theme.of(context);
    final b = ctrl.baseline!;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My current pattern',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '${b.sleepHours.toStringAsFixed(1)}h sleep · '
            '${b.exerciseMinWeek.round()} min/week movement · '
            'strain ${b.strain.toStringAsFixed(1)}/5 · '
            '${b.waterGlasses.toStringAsFixed(1)} glasses water',
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            'From ${b.daysLogged} logged days + ${b.checkIns} check-ins.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CurrentVsScenario extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SimulatorController>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = ctrl.currentProjection.overall;
    final scenario = ctrl.scenarioProjection.overall;
    final change = ctrl.change;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _BigNumber(
                    label: 'Current Pattern', value: current),
              ),
              Expanded(
                child: _BigNumber(label: 'Scenario', value: scenario),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Change',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant)),
                    Text(
                      '${change >= 0 ? '+' : ''}$change',
                      style: theme.textTheme.displaySmall?.copyWith(
                          color: change > 0
                              ? scheme.primary
                              : change < 0
                                  ? scheme.error
                                  : scheme.onSurface),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ctrl.contributors.isEmpty
                ? 'Scenario matches your current pattern — move a slider or try a preset.'
                : 'Driven by: ${ctrl.contributors.join(' · ')} (simulated).',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
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

class _Controls extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SimulatorController>();
    final theme = Theme.of(context);
    final s = ctrl.scenario;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Scenario controls',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text('Sleep: ${s.sleepHours.toStringAsFixed(1)}h',
              style: theme.textTheme.titleSmall),
          Slider(
            min: 4,
            max: 10,
            divisions: 12,
            value: s.sleepHours,
            label: '${s.sleepHours.toStringAsFixed(1)}h',
            onChanged: (v) =>
                ctrl.updateScenario(s.copyWith(sleepHours: v)),
          ),
          Text('Exercise: ${s.exerciseMinWeek.round()} min/week',
              style: theme.textTheme.titleSmall),
          Slider(
            min: 0,
            max: 180,
            divisions: 18,
            value: s.exerciseMinWeek,
            label: '${s.exerciseMinWeek.round()}',
            onChanged: (v) =>
                ctrl.updateScenario(s.copyWith(exerciseMinWeek: v)),
          ),
          Text(
              'Stress (strain): ${s.strain.toStringAsFixed(0)} — 1 calm … 5 high strain',
              style: theme.textTheme.titleSmall),
          Slider(
            min: 1,
            max: 5,
            divisions: 4,
            value: s.strain,
            label: s.strain.toStringAsFixed(0),
            onChanged: (v) =>
                ctrl.updateScenario(s.copyWith(strain: v)),
          ),
          Text('Hydration: ${s.waterGlasses.toStringAsFixed(0)} glasses/day',
              style: theme.textTheme.titleSmall),
          Slider(
            min: 0,
            max: 12,
            divisions: 12,
            value: s.waterGlasses,
            label: s.waterGlasses.toStringAsFixed(0),
            onChanged: (v) =>
                ctrl.updateScenario(s.copyWith(waterGlasses: v)),
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: ctrl.resetToCurrent,
            icon: const Icon(Icons.refresh),
            label: const Text('Reset to My Current Pattern'),
          ),
        ],
      ),
    );
  }
}

class _Presets extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SimulatorController>();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Presets'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in SimulatorPreset.values)
              FilledButton.tonal(
                onPressed: () => ctrl.applyPreset(p),
                child: Text('${p.label} (${p.hint})'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Presets start from your current values.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _Trajectory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SimulatorController>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final points =
        WellnessProjectionEngine.trajectory(ctrl.scenarioProjection);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('10-year trajectory (illustrative)',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 9,
                minY: 0,
                maxY: 100,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData:
                    const LineTouchData(enabled: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(
                      sideTitles:
                          SideTitles(showTitles: true, reservedSize: 30)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 4,
                      getTitlesWidget: (v, meta) {
                        final year = v.round() + 1;
                        if (year != 1 && year != 5 && year != 10) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Y$year',
                              style: theme.textTheme.bodySmall),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < points.length; i++)
                        FlSpot(i.toDouble(), points[i].toDouble()),
                    ],
                    isCurved: false,
                    barWidth: 2.5,
                    color: scheme.primary,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: scheme.primary.withAlpha(26),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Illustrative scenario based on your selected inputs — not a medical prediction. '
            'It assumes the pattern is sustained and claims no scientific predictive accuracy.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Comparison extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SimulatorController>();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Saved scenarios',
          actionLabel: 'Save current',
          onAction: () => _saveDialog(context),
        ),
        const SizedBox(height: 8),
        if (ctrl.saved.isEmpty)
          AppCard(
            child: Text(
              'Save up to 4 sketches (e.g. Better Sleep, More Exercise) to compare side by side. They are temporary and never alter your records.',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  const DataColumn(label: Text('')),
                  const DataColumn(label: Text('Current')),
                  for (final s in ctrl.saved)
                    DataColumn(label: Text(s.name)),
                ],
                rows: [
                  _row('Sleep', (i) => '${i.sleepHours.toStringAsFixed(1)}h',
                      ctrl),
                  _row('Movement', (i) => '${i.exerciseMinWeek.round()}/wk',
                      ctrl),
                  _row('Strain', (i) => i.strain.toStringAsFixed(1), ctrl),
                  _row('Water', (i) => '${i.waterGlasses.toStringAsFixed(0)}/d',
                      ctrl),
                  _row('Overall', (i) => '${WellnessProjectionEngine.project(i).overall}',
                      ctrl),
                ],
              ),
            ),
          ),
        if (ctrl.saved.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < ctrl.saved.length; i++)
                Chip(
                  label: Text('Remove ${ctrl.saved[i].name}'),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => ctrl.removeScenario(i),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }

  DataRow _row(String label, String Function(ScenarioInput) f,
      SimulatorController ctrl) {
    return DataRow(cells: [
      DataCell(Text(label)),
      DataCell(Text(f(ctrl.currentInput))),
      for (final s in ctrl.saved) DataCell(Text(f(s.input))),
    ]);
  }

  Future<void> _saveDialog(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Save scenario sketch'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'e.g. Better Sleep',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(c).pop(controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !context.mounted) return;
    context.read<SimulatorController>().saveScenario(name);
  }
}
