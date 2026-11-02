import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/pin_gate.dart';
import 'report_engine.dart';
import 'reports_controller.dart';

/// /home/reports — weekly + monthly summaries computed locally from
/// existing logs. Illustrative only; honest about missing data.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ReportsController(),
      child: const _ReportsBody(),
    );
  }
}

class _ReportsBody extends StatefulWidget {
  const _ReportsBody();

  @override
  State<_ReportsBody> createState() => _ReportsBodyState();
}

class _ReportsBodyState extends State<_ReportsBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _exportJson() async {
    var includeSnapshot = false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Export report'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'A readable JSON file, shared via the Android share sheet. Nothing is uploaded.'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include health snapshot'),
                subtitle: const Text(
                    'Sensitive details — only if you explicitly choose so.'),
                value: includeSnapshot,
                onChanged: (v) =>
                    setD(() => includeSnapshot = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Share')),
          ],
        ),
      ),
    );
    if (proceed != true || !mounted) return;
    final path = await context
        .read<ReportsController>()
        .shareJson(includeSnapshot: includeSnapshot);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(path == null
            ? 'Could not share the report.'
            : 'Report shared ✓')));
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ReportsController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Open Wellness Calendar',
            onPressed: () => context.push('/calendar'),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Week'), Tab(text: 'Month')],
        ),
      ),
      body: PinGate(
        screen: 'reports',
        title: 'Reports are locked',
        subtitle: 'Unlock to view your wellness summaries.',
        child: ctrl.loading
            ? const AppLoading(message: 'Building your report…')
            : ctrl.error != null
                ? AppErrorState(
                    message: ctrl.error!, onRetry: ctrl.load)
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _WeekTab(onExport: _exportJson),
                      _MonthTab(onExport: _exportJson),
                    ],
                  ),
      ),
    );
  }
}

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _WeekTab extends StatelessWidget {
  final Future<void> Function() onExport;
  const _WeekTab({required this.onExport});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ReportsController>();
    final theme = Theme.of(context);
    final w = ctrl.current;
    if (w == null || !w.sufficient) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppEmptyState(
            icon: Icons.assessment_outlined,
            title: 'Not enough data yet',
            subtitle:
                'Log at least $minDaysForReport days under Today and your weekly report will appear here. Missing days are never filled in.',
            actionLabel: 'Log today',
            onAction: () => context.go('/today'),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Week of ${_fmtDate(w.weekStart)}',
            style: theme.textTheme.titleMedium),
        Text('Logged ${w.daysLogged} of 7 days',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        _SectionCard(title: 'Overview', rows: [
          _row('Average wellness score', '${w.avgWellness ?? '—'}'),
          _row('Score change vs last week',
              w.wellnessChange == null
                  ? 'need last week'
                  : '${w.wellnessChange! >= 0 ? '+' : ''}${w.wellnessChange}'),
          _row('Logging consistency',
              '${((w.daysLogged / 7) * 100).round()}%'),
        ]),
        _SectionCard(title: 'Sleep', rows: [
          _row('Average',
              w.sleepAvg == null ? '—' : '${w.sleepAvg!.toStringAsFixed(1)}h'),
          _row('Consistency (7–9h)',
              w.sleepConsistency == null
                  ? '—'
                  : '${(w.sleepConsistency! * 100).round()}%'),
          _row('Best day', w.bestSleepDay ?? '—'),
          _row('Lowest day', w.lowSleepDay ?? '—'),
        ]),
        _SectionCard(title: 'Movement', rows: [
          _row('Total minutes', '${w.exerciseTotal}'),
          _row('Active days (20+ min)', '${w.activeDays}'),
        ]),
        _SectionCard(title: 'Hydration', rows: [
          _row('Average',
              w.waterAvg == null ? '—' : w.waterAvg!.toStringAsFixed(1)),
          _row('Goal completion (8/day)',
              w.waterGoalPct == null
                  ? '—'
                  : '${(w.waterGoalPct! * 100).round()}%'),
        ]),
        _SectionCard(title: 'Stress', rows: [
          _row('Average mood',
              w.moodAvg == null ? '—' : w.moodAvg!.toStringAsFixed(1)),
          _row('Best day', w.bestMoodDay ?? '—'),
          _row('Lowest day', w.lowMoodDay ?? '—'),
        ]),
        _SectionCard(title: 'Mind', rows: [
          _row('Meditation total', '${w.meditationTotal} min'),
          _row('Screen time avg',
              w.screenAvg == null
                  ? '—'
                  : '${w.screenAvg!.toStringAsFixed(1)}h'),
        ]),
        _SectionCard(
            title: 'This week vs last week',
            rows: [
              for (final d in ctrl.comparison)
                _row(d.label, '${d.current} (was ${d.previous}) ${d.change}'),
              if (ctrl.comparison.isEmpty)
                _row('Comparison',
                    'Need $minDaysForReport+ logged days in each week.'),
            ]),
        AppCard(
          child: Text(ctrl.summary,
              style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: onExport,
          child: const Text('Export as JSON'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _MonthTab extends StatelessWidget {
  final Future<void> Function() onExport;
  const _MonthTab({required this.onExport});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ReportsController>();
    final theme = Theme.of(context);
    final m = ctrl.monthly;
    if (m == null || m.daysLogged < minDaysForReport) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppEmptyState(
            icon: Icons.calendar_month_outlined,
            title: 'Not enough data yet',
            subtitle:
                'Log at least $minDaysForReport days this month and your monthly trends will appear here.',
            actionLabel: 'Log today',
            onAction: () => context.go('/today'),
          ),
        ],
      );
    }
    String pct(double? v) =>
        v == null ? '—' : '${(v * 100).round()}%';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Last 30 days · ${m.daysLogged} logged',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        _SectionCard(title: 'Wellness trend', rows: [
          _row('Average score', '${m.avgWellness ?? '—'}'),
          _row('Trend (2nd half − 1st half)',
              m.wellnessTrend == null
                  ? 'need more days'
                  : '${m.wellnessTrend! >= 0 ? '+' : ''}${m.wellnessTrend!.round()}'),
        ]),
        _SectionCard(title: 'Goal consistency', rows: [
          _row('Sleep 7–9h days', pct(m.sleepGoalPct)),
          _row('Water 8+ days', pct(m.waterGoalPct)),
        ]),
        _SectionCard(title: 'Activity counts', rows: [
          _row('Experiments completed',
              '${m.experimentsCompleted}'),
          _row('Habit check-ins', '${m.habitCheckIns}'),
          _row('Journal entries', '${m.journalCount}'),
          _row('Documents added', '${m.documentsAdded}'),
        ]),
        AppCard(
          child: Text(
            'Counts and trends from your logs only. Illustrative — not a medical assessment.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: onExport,
          child: const Text('Export as JSON'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> rows;
  const _SectionCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            ...rows,
          ],
        ),
      ),
    );
  }
}

Widget _row(String label, String value) {
  return Builder(builder: (context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
              child: Text(label,
                  style: theme.textTheme.bodyMedium)),
          Text(value, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  });
}
