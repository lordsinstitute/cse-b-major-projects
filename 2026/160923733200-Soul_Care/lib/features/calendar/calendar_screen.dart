import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/utils/utils.dart';
import '../../core/widgets/app_widgets.dart';
import 'calendar_engine.dart';
import 'calendar_provider.dart';

/// /calendar — Wellness Calendar.
///
/// A visual history of the wellness journey: monthly grid with subtle
/// visual wellness classifications (never health claims), day detail,
/// GitHub-style consistency heatmap, month summaries, metric focus
/// filters, and a direct Time Machine handoff. No-data days say "No data".
class CalendarScreen extends StatelessWidget {
  /// Optional provider for tests (installed pre-seeded, Hive-free).
  final CalendarProvider? provider;
  const CalendarScreen({super.key, this.provider});

  @override
  Widget build(BuildContext context) {
    final existing = provider;
    return ChangeNotifierProvider(
      create: (_) => existing ?? CalendarProvider(),
      child: const _CalendarBody(),
    );
  }
}

class _CalendarBody extends StatefulWidget {
  const _CalendarBody();

  @override
  State<_CalendarBody> createState() => _CalendarBodyState();
}

class _CalendarBodyState extends State<_CalendarBody> {
  late int _year;
  late int _month;
  String? _selectedKey;
  CalendarFocus _focus = CalendarFocus.all;
  int _heatWindow = 90;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CalendarProvider>().ensureMonth(_year, _month);
      context.read<CalendarProvider>().ensureHeat(_heatWindow);
    });
  }

  void _goMonth(int year, int month) {
    setState(() {
      _year = year;
      _month = month;
      _selectedKey = null;
    });
    context.read<CalendarProvider>().ensureMonth(year, month);
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<CalendarProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = prov.month(_year, _month);
    final summary = prov.summary(_year, _month);
    final selected = _selectedKey == null
        ? null
        : days.where((d) => d.key == _selectedKey).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wellness Calendar'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => prov.ensureMonth(_year, _month),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _MonthNav(
              year: _year,
              month: _month,
              onPrevMonth: () {
                final n = prevMonth(_year, _month);
                _goMonth(n.year, n.month);
              },
              onNextMonth: () {
                final n = nextMonth(_year, _month);
                _goMonth(n.year, n.month);
              },
              onPrevYear: () {
                final n = prevYear(_year, _month);
                _goMonth(n.year, n.month);
              },
              onNextYear: () {
                final n = nextYear(_year, _month);
                _goMonth(n.year, n.month);
              },
              onPick: _pickMonthYear,
              onToday: () {
                final now = DateTime.now();
                _goMonth(now.year, now.month);
              },
            ),
            const SizedBox(height: 12),
            if (prov.loading && days.isEmpty)
              const AppCard(
                  child: AppLoading(message: 'Loading month…'))
            else if (days.isEmpty)
              AppCard(
                child: Text(
                  'No data for this month yet. Days appear here once they hold logged data.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else ...[
              _MonthGrid(
                days: days,
                selectedKey: _selectedKey,
                onTap: (d) =>
                    setState(() => _selectedKey = d.key),
              ),
              const SizedBox(height: 8),
              _Legend(),
              const SizedBox(height: 12),
              _FocusBar(
                focus: _focus,
                onFocus: (f) => setState(() => _focus = f),
              ),
              const SizedBox(height: 12),
              if (selected != null) ...[
                _DayDetail(day: selected, focus: _focus),
                const SizedBox(height: 12),
              ],
              if (summary != null) ...[
                _MonthSummaryCard(summary: summary),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => context.push(
                      '/time-machine?month=${summary.year.toString().padLeft(4, '0')}-${summary.month.toString().padLeft(2, '0')}'),
                  icon: const Icon(Icons.history_outlined, size: 18),
                  label: const Text('Explore this month'),
                ),
                const SizedBox(height: 12),
              ],
              _HeatmapCard(
                windowDays: _heatWindow,
                levels: prov.heat(_heatWindow),
                onWindow: (w) {
                  setState(() => _heatWindow = w);
                  prov.ensureHeat(w);
                },
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

  Future<void> _pickMonthYear() async {
    final now = DateTime.now();
    var year = _year;
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Go to month'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () {
                      year--;
                      (c as Element).markNeedsBuild();
                    },
                  ),
                  Text('$year',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () {
                      if (year < now.year + 1) year++;
                      (c as Element).markNeedsBuild();
                    },
                  ),
                ],
              ),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                childAspectRatio: 2.2,
                children: [
                  for (var m = 1; m <= 12; m++)
                    TextButton(
                      onPressed: () =>
                          Navigator.of(c).pop(DateTime(year, m, 1)),
                      child: Text(_monthName(m).substring(0, 3)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) {
      _goMonth(picked.year, picked.month);
    }
  }
}

String _monthName(int m) => switch (m) {
      1 => 'January',
      2 => 'February',
      3 => 'March',
      4 => 'April',
      5 => 'May',
      6 => 'June',
      7 => 'July',
      8 => 'August',
      9 => 'September',
      10 => 'October',
      11 => 'November',
      12 => 'December',
      _ => '',
    };

class _MonthNav extends StatelessWidget {
  final int year;
  final int month;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onPrevYear;
  final VoidCallback onNextYear;
  final VoidCallback onPick;
  final VoidCallback onToday;
  const _MonthNav({
    required this.year,
    required this.month,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onPrevYear,
    required this.onNextYear,
    required this.onPick,
    required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Row(
        children: [
          IconButton(
              icon: const Icon(Icons.skip_previous_outlined),
              tooltip: 'Previous year',
              onPressed: onPrevYear),
          IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous month',
              onPressed: onPrevMonth),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onPick,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    Text('${_monthName(month)} $year}',
                        style: theme.textTheme.titleMedium),
                    Text('Tap to jump',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme
                                .onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next month',
              onPressed: onNextMonth),
          IconButton(
              icon: const Icon(Icons.skip_next_outlined),
              tooltip: 'Next year',
              onPressed: onNextYear),
        ],
      ),
    );
  }
}

/// Day-state dot color + icon (never color alone).
(Color, IconData) _stateStyle(BuildContext context, DayState state) {
  final scheme = Theme.of(context).colorScheme;
  return switch (state) {
    DayState.excellent => (scheme.primary, Icons.star_outlined),
    DayState.good => (scheme.tertiary, Icons.check_circle_outline),
    DayState.mixed => (scheme.secondary, Icons.contrast_outlined),
    DayState.difficult => (scheme.error, Icons.waves_outlined),
    DayState.insufficient => (scheme.outlineVariant, Icons.circle_outlined),
  };
}

class _MonthGrid extends StatelessWidget {
  final List<CalendarDay> days;
  final String? selectedKey;
  final ValueChanged<CalendarDay> onTap;
  const _MonthGrid(
      {required this.days,
      required this.selectedKey,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const headers = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              for (final h in headers)
                Expanded(
                  child: Center(
                    child: Text(h,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(
                                color: scheme.onSurfaceVariant)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7),
            itemCount: days.length,
            itemBuilder: (c, i) {
              final d = days[i];
              final (color, icon) = _stateStyle(context, d.state);
              final selected = d.key == selectedKey;
              final markers = [
                if (d.journalCount > 0) Icons.book_outlined,
                if (d.documentCount > 0) Icons.folder_outlined,
                if (d.habits.any((h) => h.endsWith('✓')))
                  Icons.task_alt_outlined,
              ].take(2).toList();
              final cell = InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onTap(d),
                child: Opacity(
                  opacity: d.inMonth ? 1 : 0.35,
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: selected
                          ? scheme.primaryContainer
                          : (d.hasData
                              ? color.withValues(alpha: 0.12)
                              : Colors.transparent),
                      border: Border.all(
                        color: selected
                            ? scheme.primary
                            : scheme.outlineVariant
                                .withValues(alpha: 0.4),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                        vertical: 3, horizontal: 2),
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Text('${d.date.day}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(
                                    fontWeight: selected
                                        ? FontWeight.bold
                                        : null)),
                        Icon(icon, size: 12, color: color),
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            for (final m in markers)
                              Icon(m,
                                  size: 8,
                                  color:
                                      scheme.onSurfaceVariant),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
              return Tooltip(
                message: '${d.key}: ${d.state.label}',
                child: Semantics(
                  button: true,
                  selected: selected,
                  label:
                      '${d.key}, ${d.state.description}',
                  child: cell,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final s in DayState.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_stateStyle(context, s).$2,
                  size: 12,
                  color: _stateStyle(context, s).$1),
              const SizedBox(width: 4),
              Text(s.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
      ],
    );
  }
}

class _FocusBar extends StatelessWidget {
  final CalendarFocus focus;
  final ValueChanged<CalendarFocus> onFocus;
  const _FocusBar({required this.focus, required this.onFocus});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<CalendarFocus>(
        segments: const [
          ButtonSegment(
              value: CalendarFocus.all, label: Text('All')),
          ButtonSegment(
              value: CalendarFocus.sleep, label: Text('Sleep')),
          ButtonSegment(
              value: CalendarFocus.stress, label: Text('Stress')),
        ],
        selected: {focus},
        onSelectionChanged: (s) => onFocus(s.first),
      ),
    );
  }
}

/// Day detail with focus highlighting (dim non-focused rows smoothly).
class _DayDetail extends StatelessWidget {
  final CalendarDay day;
  final CalendarFocus focus;
  const _DayDetail({required this.day, required this.focus});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (color, icon) = _stateStyle(context, day.state);
    bool highlight(String section) {
      if (focus == CalendarFocus.all) return true;
      if (focus == CalendarFocus.sleep) {
        return section == 'sleep';
      }
      return section == 'stress' || section == 'mood';
    }

    Widget row(String label, String value, String section,
        {bool emphasize = false}) {
      final on = highlight(section);
      return AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: on ? 1 : 0.35,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              Text(value,
                  style: (emphasize
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.titleSmall)
                      ?.copyWith(
                          color: on
                              ? null
                              : scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${day.key} — ${day.state.label}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(day.state.description,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          if (!day.hasData)
            Text('No data was logged on this day — and that is fine. It is not shown as a bad day.',
                style: theme.textTheme.bodyMedium)
          else ...[
            if (day.wellness != null)
              row('Wellness score', '${day.wellness}',
                  'score',
                  emphasize: true),
            row(
                'Sleep',
                day.sleepHours == null
                    ? 'No data'
                    : formatHours(day.sleepHours!),
                'sleep'),
            row(
                'Exercise',
                day.exerciseMinutes == null
                    ? 'No data'
                    : '${day.exerciseMinutes} min',
                'exercise'),
            row(
                'Hydration',
                day.waterGlasses == null
                    ? 'No data'
                    : '${day.waterGlasses} glasses',
                'hydration'),
            row(
                'Stress (calm)',
                day.calm == null
                    ? 'No data'
                    : day.calm!.toStringAsFixed(0),
                'stress'),
            row(
                'Mood (1–5)',
                day.mood == null
                    ? 'No data'
                    : day.mood!.toStringAsFixed(1),
                'mood'),
            if (day.habits.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Habits',
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant)),
              for (final h in day.habits)
                Text('• $h',
                    style: theme.textTheme.bodySmall),
            ],
            if (day.experimentStatus.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Experiment status',
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant)),
              for (final t in day.experimentStatus)
                Text('• Active: $t',
                    style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                if (day.journalCount > 0)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.book_outlined,
                        size: 14),
                    label: Text(
                        '${day.journalCount} journal ${day.journalCount == 1 ? 'entry' : 'entries'}'),
                  ),
                if (day.documentCount > 0)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.folder_outlined,
                        size: 14),
                    label: Text(
                        '${day.documentCount} document${day.documentCount == 1 ? '' : 's'}'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MonthSummaryCard extends StatelessWidget {
  final MonthSummary summary;
  const _MonthSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String v(String? s) => s ?? 'needs more logged days';
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '${_monthName(summary.month)} ${summary.year} — summary',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _row(context, 'Days logged',
              '${summary.daysLogged} of ${summary.daysInMonth}'),
          _row(context, 'Average wellness',
              summary.avgWellness == null
                  ? 'needs logged days'
                  : summary.avgWellness!.toStringAsFixed(0)),
          _row(context, 'Highest wellness day',
              summary.bestDay == null
                  ? 'needs logged days'
                  : '${summary.bestDay} (${summary.bestScore})'),
          _row(context, 'Most consistent metric',
              v(summary.mostConsistentMetric)),
          _row(context, 'Biggest improvement',
              v(summary.biggestImprovement)),
          _row(
              context,
              'Experiments',
              summary.activeExperiments.isEmpty &&
                      summary.completedExperiments.isEmpty
                  ? 'none this month'
                  : '${summary.activeExperiments.length} active · ${summary.completedExperiments.length} completed'),
          if (summary.activeExperiments.isNotEmpty)
            Text('Active: ${summary.activeExperiments.join(', ')}',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant)),
          if (summary.completedExperiments.isNotEmpty)
            Text(
                'Completed: ${summary.completedExperiments.join(', ')}',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant)),
          _row(context, 'Journal entries', '${summary.journalCount}'),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Flexible(
            child: Text(value,
                style: theme.textTheme.titleSmall,
                textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

/// GitHub-style consistency heatmap with hand-tuned light/dark ramps
/// (designed per mode, never inverted).
class _HeatmapCard extends StatelessWidget {
  final int windowDays;
  final Map<String, int> levels;
  final ValueChanged<int> onWindow;
  const _HeatmapCard(
      {required this.windowDays,
      required this.levels,
      required this.onWindow});

  Color _levelColor(
      BuildContext context, int level) {
    final scheme = Theme.of(context).colorScheme;
    final dark =
        Theme.of(context).brightness == Brightness.dark;
    if (level <= 0) {
      return dark
          ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
          : scheme.surfaceContainerHighest;
    }
    // Calm teal-green ramp, tuned separately per brightness.
    if (dark) {
      return switch (level) {
        1 => const Color(0xFF1B3A32),
        2 => const Color(0xFF2A5A4C),
        3 => const Color(0xFF3E7C6B),
        _ => const Color(0xFF7BC4A8),
      };
    }
    return switch (level) {
      1 => const Color(0xFFD9EDE5),
      2 => const Color(0xFFA9D6C2),
      3 => const Color(0xFF3E7C6B),
      _ => const Color(0xFF1F5C4D),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final today =
        DateTime(now.year, now.month, now.day);
    final dates = [
      for (var i = windowDays - 1; i >= 0; i--)
        today.subtract(Duration(days: i)),
    ];
    // Monday-first week columns.
    final lead = dates.first.weekday - 1;
    final cells = <DateTime?>[
      for (var i = 0; i < lead; i++) null,
      ...dates,
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final cols = cells.length ~/ 7;
    final logged =
        levels.values.where((l) => l > 0).length;

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
                    Text('Logging consistency',
                        style: theme.textTheme.titleSmall),
                    Text('$logged of $windowDays days with logs',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(
                                color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              SegmentedButton<int>(
                style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: 30, label: Text('30d')),
                  ButtonSegment(value: 90, label: Text('90d')),
                  ButtonSegment(value: 365, label: Text('1y')),
                ],
                selected: {windowDays},
                onSelectionChanged: (s) => onWindow(s.first),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < cols; c++)
                  Column(
                    children: [
                      for (var r = 0; r < 7; r++)
                        Builder(builder: (context) {
                          final d = cells[c * 7 + r];
                          if (d == null) {
                            return const SizedBox(
                                width: 13, height: 13);
                          }
                          final key = formatDateForStorage(d);
                          final level = levels[key] ?? 0;
                          return Tooltip(
                            message:
                                '$key: ${level == 0 ? 'no logs' : 'level $level logging'}',
                            child: Container(
                              width: 11,
                              height: 11,
                              margin:
                                  const EdgeInsets.all(1),
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(3),
                                color: _levelColor(
                                    context, level),
                                border: Border.all(
                                    color: scheme.outlineVariant
                                        .withValues(
                                            alpha: 0.4),
                                    width: 0.5),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Less',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant)),
              const SizedBox(width: 4),
              for (var l = 0; l <= 4; l++)
                Container(
                  width: 11,
                  height: 11,
                  margin: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: _levelColor(context, l),
                  ),
                ),
              const SizedBox(width: 4),
              Text('More',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant)),
              const Spacer(),
              Text('Square = day · shade + tooltip = level',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}
