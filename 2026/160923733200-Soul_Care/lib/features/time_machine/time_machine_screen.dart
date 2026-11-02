import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/utils/utils.dart';
import '../../core/widgets/app_widgets.dart';
import 'time_machine_engine.dart';
import 'time_machine_provider.dart';

/// /time-machine — SoulCare Time Machine.
///
/// Interactively explores personal wellness history from logged records.
/// Never fabricates history: dates without data are reported as
/// unavailable. Factual language only — no causal or medical claims.
class TimeMachineScreen extends StatelessWidget {
  /// Optional anchor (e.g. from the Calendar's "Explore this month"):
  /// the latest available day on or before the anchor month's end is
  /// selected instead of today.
  final DateTime? initialAnchor;
  const TimeMachineScreen({super.key, this.initialAnchor});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TimeMachineProvider()..loadIndex(),
      child: _TimeMachineBody(initialAnchor: initialAnchor),
    );
  }
}

class _TimeMachineBody extends StatefulWidget {
  final DateTime? initialAnchor;
  const _TimeMachineBody({this.initialAnchor});

  @override
  State<_TimeMachineBody> createState() => _TimeMachineBodyState();
}

class _TimeMachineBodyState extends State<_TimeMachineBody> {
  PeriodMode _mode = PeriodMode.day;
  DateTime? _selected;
  bool _compare = false;
  DateTime? _slotA;
  DateTime? _slotB;
  bool _replaying = false;
  int _replayIndex = 0;
  Timer? _replayTimer;
  final ScrollController _timelineScroll = ScrollController();

  static const double _cellWidth = 64;

  @override
  void dispose() {
    _replayTimer?.cancel();
    _timelineScroll.dispose();
    super.dispose();
  }

  void _afterIndex(TimeMachineProvider prov) {
    if (_selected != null || prov.availableDays.isEmpty) return;
    final anchor = widget.initialAnchor;
    DateTime pick;
    if (anchor != null) {
      final end = DateTime(anchor.year, anchor.month + 1, 0);
      final within =
          prov.availableDays.where((d) => !d.isAfter(end)).toList();
      pick = within.isNotEmpty
          ? within.last
          : prov.availableDays.last;
    } else {
      final today = DateTime.now();
      final now = DateTime(today.year, today.month, today.day);
      final past =
          prov.availableDays.where((d) => !d.isAfter(now)).toList();
      pick = past.isNotEmpty ? past.last : prov.availableDays.last;
    }
    setState(() => _selected = pick);
    prov.ensureMonth(pick.year, pick.month);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(pick, prov));
  }

  void _scrollTo(DateTime day, TimeMachineProvider prov) {
    final i = prov.availableDays.indexWhere((d) =>
        d.year == day.year && d.month == day.month && d.day == day.day);
    if (i < 0 || !_timelineScroll.hasClients) return;
    _timelineScroll.animateTo(
      (i * _cellWidth).clamp(
          0.0,
          (_timelineScroll.position.maxScrollExtent)),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _select(DateTime day, TimeMachineProvider prov) async {
    _stopReplay();
    if (_compare) {
      setState(() {
        if (_slotA == null) {
          _slotA = day;
        } else if (_slotB == null && !_isSameDay(_slotA!, day)) {
          _slotB = day;
        } else {
          _slotA = day;
          _slotB = null;
        }
      });
    } else {
      setState(() => _selected = day);
    }
    await prov.ensureMonth(day.year, day.month);
    if (mounted && !_compare) _scrollTo(day, prov);
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<DayReplay> _currentPeriod(TimeMachineProvider prov) {
    final anchor = _selected;
    if (anchor == null) return const [];
    return prov.periodReplays(anchor, _mode);
  }

  Future<void> _startReplay(TimeMachineProvider prov) async {
    final period = _currentPeriod(prov);
    if (period.isEmpty) return;
    final months = {
      for (final d in period) '${d.date.year}-${d.date.month}',
    };
    for (final m in months) {
      final parts = m.split('-');
      await prov.ensureMonth(int.parse(parts[0]), int.parse(parts[1]));
    }
    if (!mounted) return;
    setState(() {
      _replaying = true;
      _replayIndex = 0;
    });
    _replayTimer?.cancel();
    _replayTimer = Timer.periodic(const Duration(milliseconds: 800), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final days = _currentPeriod(prov);
      if (_replayIndex >= days.length - 1) {
        _stopReplay();
        return;
      }
      setState(() => _replayIndex++);
    });
  }

  void _stopReplay() {
    _replayTimer?.cancel();
    _replayTimer = null;
    if (_replaying && mounted) setState(() => _replaying = false);
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<TimeMachineProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (prov.indexed && _selected == null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _afterIndex(prov));
    }

    final days = prov.availableDays;
    final sel = _selected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Machine'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        actions: [
          if (days.isNotEmpty)
            TextButton(
              onPressed: () {
                final today = DateTime.now();
                final now = DateTime(today.year, today.month, today.day);
                final past =
                    days.where((d) => !d.isAfter(now)).toList();
                if (past.isNotEmpty) _select(past.last, prov);
              },
              child: const Text('Today'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => prov.loadIndex(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Your wellness history',
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text(
              'Replay logged days, watch experiments unfold, and compare periods. Only real logged history is shown — gaps stay gaps.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (prov.loading && !prov.indexed)
              const AppCard(
                  child: AppLoading(message: 'Reading your history…'))
            else if (prov.indexed && days.isEmpty)
              AppCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.history_outlined,
                        size: 48, color: scheme.primary),
                    const SizedBox(height: 12),
                    Text('No history yet',
                        style: theme.textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      'Your Time Machine builds itself as you log. Start with today — past days appear once they hold logged data.',
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
              _ModeBar(
                mode: _mode,
                compare: _compare,
                onMode: (m) {
                  _stopReplay();
                  setState(() => _mode = m);
                },
                onCompare: (v) {
                  _stopReplay();
                  setState(() {
                    _compare = v;
                    _slotA = null;
                    _slotB = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              _Timeline(
                days: days,
                eventsByDate: prov.eventsByDate,
                selected: _compare ? null : sel,
                slotA: _slotA,
                slotB: _slotB,
                compare: _compare,
                controller: _timelineScroll,
                onTap: (d) => _select(d, prov),
              ),
              const SizedBox(height: 12),
              if (_compare)
                _ComparePanel(
                  slotA: _slotA,
                  slotB: _slotB,
                  mode: _mode,
                  provider: prov,
                  onClear: () => setState(() {
                    _slotA = null;
                    _slotB = null;
                  }),
                )
              else if (sel != null) ...[
                _ReplayPanel(
                  period: _currentPeriod(prov),
                  eventsByDate: prov.eventsByDate,
                  mode: _mode,
                  replaying: _replaying,
                  replayIndex: _replayIndex,
                  onReplay: () => _startReplay(prov),
                  onStop: _stopReplay,
                ),
                const SizedBox(height: 12),
              ],
            ],
            if (prov.error != null) ...[
              const SizedBox(height: 8),
              Text(prov.error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.error)),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _ModeBar extends StatelessWidget {
  final PeriodMode mode;
  final bool compare;
  final ValueChanged<PeriodMode> onMode;
  final ValueChanged<bool> onCompare;
  const _ModeBar({
    required this.mode,
    required this.compare,
    required this.onMode,
    required this.onCompare,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Period', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<PeriodMode>(
              segments: const [
                ButtonSegment(value: PeriodMode.day, label: Text('Day')),
                ButtonSegment(value: PeriodMode.week, label: Text('Week')),
                ButtonSegment(value: PeriodMode.month, label: Text('Month')),
              ],
              selected: {mode},
              onSelectionChanged: (s) => onMode(s.first),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch(value: compare, onChanged: onCompare),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  compare
                      ? 'Compare on — tap two dates to fill slots A and B.'
                      : 'Compare two dates or periods.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

IconData _iconFor(TimeEventType t) => switch (t) {
      TimeEventType.healthLog => Icons.check_circle_outline,
      TimeEventType.experimentStarted => Icons.science_outlined,
      TimeEventType.experimentCompleted => Icons.emoji_events_outlined,
      TimeEventType.habitActivity => Icons.task_alt_outlined,
      TimeEventType.habitMilestone => Icons.military_tech_outlined,
      TimeEventType.journalEntry => Icons.book_outlined,
      TimeEventType.documentAdded => Icons.folder_outlined,
      TimeEventType.goalReached => Icons.flag_outlined,
    };

Color _colorFor(BuildContext context, TimeEventType t) {
  final s = Theme.of(context).colorScheme;
  return switch (t) {
    TimeEventType.experimentCompleted => s.primary,
    TimeEventType.habitMilestone => s.primary,
    TimeEventType.goalReached => s.primary,
    TimeEventType.experimentStarted => s.secondary,
    TimeEventType.documentAdded => s.secondary,
    TimeEventType.journalEntry => s.tertiary,
    TimeEventType.habitActivity => s.tertiary,
    TimeEventType.healthLog => s.outline,
  };
}

/// Horizontally scrollable, lazily-built timeline of available dates.
class _Timeline extends StatelessWidget {
  final List<DateTime> days;
  final Map<String, List<TimeEvent>> eventsByDate;
  final DateTime? selected;
  final DateTime? slotA;
  final DateTime? slotB;
  final bool compare;
  final ScrollController controller;
  final ValueChanged<DateTime> onTap;
  const _Timeline({
    required this.days,
    required this.eventsByDate,
    required this.selected,
    required this.slotA,
    required this.slotB,
    required this.compare,
    required this.controller,
    required this.onTap,
  });

  static bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('${days.length} days with history',
                style: theme.textTheme.titleSmall),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 92,
            child: ListView.builder(
              controller: controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: days.length,
              itemBuilder: (c, i) {
                final d = days[i];
                final key = formatDateForStorage(d);
                final evs = eventsByDate[key] ?? const [];
                final isSel =
                    selected != null && _same(selected!, d);
                final isA = slotA != null && _same(slotA!, d);
                final isB = slotB != null && _same(slotB!, d);
                final highlight = compare ? (isA || isB) : isSel;
                final markerTypes =
                    evs.map((e) => e.type).toSet().take(4).toList();
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onTap(d),
                    child: Container(
                      width: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: highlight
                            ? scheme.primaryContainer
                            : Colors.transparent,
                        border: Border.all(
                          color: highlight
                              ? scheme.primary
                              : scheme.outlineVariant
                                  .withValues(alpha: 0.5),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            compare && (isA || isB)
                                ? (isA ? 'A' : 'B')
                                : _weekday(d.weekday),
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant),
                          ),
                          Text('${d.day}',
                              style: theme.textTheme.titleMedium),
                          Text('${d.month}/${d.year % 100}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              for (final t in markerTypes)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 1),
                                  child: Icon(_iconFor(t),
                                      size: 10,
                                      color: _colorFor(context, t)),
                                ),
                              if (evs.isEmpty)
                                Icon(Icons.circle,
                                    size: 6,
                                    color: scheme.outlineVariant),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final t in TimeEventType.values)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_iconFor(t),
                          size: 12,
                          color: _colorFor(context, t)),
                      const SizedBox(width: 4),
                      Text(t.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _weekday(int w) => switch (w) {
        1 => 'Mon',
        2 => 'Tue',
        3 => 'Wed',
        4 => 'Thu',
        5 => 'Fri',
        6 => 'Sat',
        _ => 'Sun',
      };
}

/// Date replay: dashboard state for the period + replay controls.
class _ReplayPanel extends StatelessWidget {
  final List<DayReplay> period;
  final Map<String, List<TimeEvent>> eventsByDate;
  final PeriodMode mode;
  final bool replaying;
  final int replayIndex;
  final VoidCallback onReplay;
  final VoidCallback onStop;
  const _ReplayPanel({
    required this.period,
    required this.eventsByDate,
    required this.mode,
    required this.replaying,
    required this.replayIndex,
    required this.onReplay,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (period.isEmpty) {
      return const AppCard(
          child: Text('Select a date to replay it.'));
    }
    final shown = replaying
        ? period[replayIndex.clamp(0, period.length - 1)]
        : period.lastWhere((d) => true, orElse: () => period.first);
    // In week/month mode the replay target is the anchor (last) day;
    // the replay animation walks the whole period day by day.
    final summary = summarizePeriod(period);
    final important = importantChangeKeys(
        ordered: period, eventsByDate: eventsByDate);
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  mode == PeriodMode.day
                      ? 'Date replay — ${shown.dateKey}'
                      : '${_modeLabel(mode)} ending ${period.last.dateKey}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (mode != PeriodMode.day)
                FilledButton.tonal(
                  onPressed: replaying ? onStop : onReplay,
                  child: Text(
                      replaying ? 'Stop' : 'Replay this period'),
                ),
            ],
          ),
          if (replaying) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: period.length <= 1
                    ? 1
                    : replayIndex / (period.length - 1),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Replaying ${shown.dateKey} — day ${replayIndex + 1} of ${period.length}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _DayCard(
              key: ValueKey(
                  '${shown.dateKey}-$replaying-$replayIndex'),
              day: shown,
              events: eventsByDate[shown.dateKey] ?? const [],
            ),
          ),
          if (mode != PeriodMode.day) ...[
            const SizedBox(height: 12),
            const SectionHeader(title: 'Period overview'),
            const SizedBox(height: 4),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _Stat(
                    label: 'Logged days',
                    value:
                        '${summary.loggedDays} of ${period.length}'),
                _Stat(
                    label: 'Avg wellness',
                    value: summary.avgWellness == null
                        ? 'unavailable'
                        : summary.avgWellness!
                            .toStringAsFixed(0)),
                _Stat(
                    label: 'Avg sleep',
                    value: summary.avgSleep == null
                        ? 'unavailable'
                        : formatHours(summary.avgSleep!)),
                _Stat(
                    label: 'Movement total',
                    value: '${summary.totalExercise} min'),
                _Stat(
                    label: 'Change',
                    value: summary.change == null
                        ? 'keep logging'
                        : '${summary.change! >= 0 ? '+' : ''}${summary.change!.toStringAsFixed(0)}'),
              ],
            ),
            if (important.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Important changes',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final k in important)
                Text('• $k — notable shift or milestone in your logs.',
                    style: theme.textTheme.bodySmall),
            ],
          ],
        ],
      ),
    );
  }

  String _modeLabel(PeriodMode m) => switch (m) {
        PeriodMode.day => 'Day',
        PeriodMode.week => 'Week',
        PeriodMode.month => 'Month',
      };
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

/// Animated dashboard state for one date.
class _DayCard extends StatelessWidget {
  final DayReplay day;
  final List<TimeEvent> events;
  const _DayCard({super.key, required this.day, required this.events});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (!day.hasData) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(day.dateKey, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(day.unavailableReason ?? 'No data for this date.',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(day.dateKey,
                  style: theme.textTheme.titleMedium),
              const Spacer(),
              if (day.wellness != null)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('Score ${day.wellness}'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _Stat(
                  label: 'Sleep',
                  value: day.sleepHours == null
                      ? 'unavailable'
                      : formatHours(day.sleepHours!)),
              _Stat(
                  label: 'Calm',
                  value: day.calm == null
                      ? 'unavailable'
                      : day.calm!.toStringAsFixed(0)),
              _Stat(
                  label: 'Mood (1–5)',
                  value: day.mood == null
                      ? 'unavailable'
                      : day.mood!.toStringAsFixed(1)),
              _Stat(
                  label: 'Energy (1–5)',
                  value: day.energy == null
                      ? 'unavailable'
                      : day.energy!.toStringAsFixed(1)),
              _Stat(
                  label: 'Exercise',
                  value: day.exerciseMinutes == null
                      ? 'unavailable'
                      : '${day.exerciseMinutes} min'),
              _Stat(
                  label: 'Water',
                  value: day.waterGlasses == null
                      ? 'unavailable'
                      : '${day.waterGlasses} glasses'),
            ],
          ),
          if (day.activeExperiment != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.science_outlined,
                    size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Active experiment: ${day.activeExperiment}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
          if (day.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final n in day.notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• $n',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant)),
              ),
          ],
          if (events.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final e in events)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_iconFor(e.type),
                        size: 14,
                        color: _colorFor(context, e.type)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text('${e.type.label}: ${e.title}',
                              style: theme.textTheme.bodySmall),
                          Text(e.detail,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(
                                      color: scheme
                                          .onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Side-by-side comparison of two dates or two periods.
class _ComparePanel extends StatelessWidget {
  final DateTime? slotA;
  final DateTime? slotB;
  final PeriodMode mode;
  final TimeMachineProvider provider;
  final VoidCallback onClear;
  const _ComparePanel({
    required this.slotA,
    required this.slotB,
    required this.mode,
    required this.provider,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (slotA == null || slotB == null) {
      return AppCard(
        child: Text(
          slotA == null
              ? 'Tap a date on the timeline for slot A.'
              : 'Slot A: ${formatDateForStorage(slotA!)}. Now tap a second date for slot B.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    final List<ComparisonRow> rows;
    final String titleA;
    final String titleB;
    if (mode == PeriodMode.day) {
      final a = provider.dayReplay(slotA!);
      final b = provider.dayReplay(slotB!);
      rows = compareDays(a, b);
      titleA = formatDateForStorage(slotA!);
      titleB = formatDateForStorage(slotB!);
    } else {
      final a = summarizePeriod(provider.periodReplays(slotA!, mode));
      final b = summarizePeriod(provider.periodReplays(slotB!, mode));
      rows = comparePeriods(a, b);
      titleA =
          '${mode == PeriodMode.week ? 'Week' : 'Month'} ending ${formatDateForStorage(slotA!)}';
      titleB =
          '${mode == PeriodMode.week ? 'Week' : 'Month'} ending ${formatDateForStorage(slotB!)}';
    }
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Compare',
                    style: theme.textTheme.titleSmall),
              ),
              TextButton(
                  onPressed: onClear,
                  child: const Text('Clear')),
            ],
          ),
          const SizedBox(height: 4),
          Text('A: $titleA\nB: $titleB',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('')),
                DataColumn(label: Text('A')),
                DataColumn(label: Text('B')),
                DataColumn(label: Text('Change')),
              ],
              rows: [
                for (final r in rows)
                  DataRow(cells: [
                    DataCell(Text(r.metric)),
                    DataCell(Text(r.sideA)),
                    DataCell(Text(r.sideB)),
                    DataCell(Text(r.delta)),
                  ]),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Differences reflect logged data on each side — many factors can differ between periods.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
