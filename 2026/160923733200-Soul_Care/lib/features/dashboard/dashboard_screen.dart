import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/providers/action_center_provider.dart';
import '../../app/providers/checkin_providers.dart';
import '../../app/providers/daily_health_provider.dart';
import '../../app/providers/dashboard_provider.dart';
import '../../app/providers/experiment_provider.dart';
import '../../app/providers/milestones_provider.dart';
import '../../app/providers/profile_provider.dart';
import '../../app/providers/reminders_provider.dart';
import '../../app/theme/design_system.dart';
import '../../core/utils/utils.dart';
import '../../core/wellness/insights.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/ui_kit.dart';
import '../../features/experiments/experiment_engine.dart';
import '../../features/action_center/action_engine.dart';
import '../../features/profile/goal_progress.dart';
import 'widgets/score_detail_sheet.dart';
import 'widgets/weekly_charts.dart';

/// Home — an editorial "how am I doing today" page.
/// Hierarchy: greeting → score hero with animated ring → feature entries →
/// today's progress → goals → action center → insight → quick actions →
/// weekly overview → active experiment. All data comes from the same
/// providers as before; only the presentation changed.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Guarded reads: the dashboard must also work when a host (or an
      // isolated test harness) didn't register every provider. Each load
      // is independent — one missing dependency never wedges the screen.
      void safeLoad(dynamic Function() load) {
        try {
          load();
        } catch (_) {}
      }

      safeLoad(() => context.read<DailyHealthProvider>().loadToday());
      safeLoad(() => context.read<DashboardProvider>().load());
      safeLoad(() => context.read<ExperimentProvider>().load());
      safeLoad(() => context.read<MorningProvider>().loadToday());
      safeLoad(() => context.read<EveningProvider>().loadToday());
      safeLoad(() => context.read<ActionCenterProvider>().loadToday());
      safeLoad(() => context.read<MilestonesProvider>().load());
    });
  }

  @override
  Widget build(BuildContext context) {
    final daily = context.watch<DailyHealthProvider>();
    final dash = context.watch<DashboardProvider>();
    final experiments = context.watch<ExperimentProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final isBrandNew = !dash.loading && dash.daysLogged == 0 && !daily.loading;

    return RefreshIndicator(
      onRefresh: () async {
        final daily = context.read<DailyHealthProvider>();
        await daily.loadToday();
        if (!context.mounted) return;
        await context.read<DashboardProvider>().load();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          DS.xl,
          DS.huge - DS.xl - DS.xs,
          DS.xl,
          DS.massive,
        ),
        children: [
          // 1) Editorial greeting.
          _Greeting(),
          const SizedBox(height: DS.l),

          // 1b) Morning/evening routine prompts (quiet, non-naggy).
          const _RoutineCards(),

          if (isBrandNew) ...[
            _EmptyHero(onLog: () => context.go('/today')),
            const SizedBox(height: DS.xl),
          ] else ...[
            EntranceFader(
              index: 0,
              child: _ScoreHero(
                onTap: dash.todayScore == null
                    ? null
                    : () => ScoreDetailSheet.show(context, dash.todayScore!),
              ),
            ),
            const SizedBox(height: DS.l),
            EntranceFader(index: 1, child: const _TodayMetricsStrip()),
            const SizedBox(height: DS.xxl),
            EntranceFader(index: 2, child: _TodayProgress()),
            const SizedBox(height: DS.xl),
            EntranceFader(index: 2, child: const _GoalStrip()),
            EntranceFader(index: 3, child: const _ActionCenter()),
            // 4) Feature entries (2×2 editorial grid).
            if (!dash.loading) ...[
              const SectionHeader(title: 'Explore'),
              const SizedBox(height: DS.m),
              const _FeatureGrid(),
              const SizedBox(height: DS.xl),
            ],
            // 4b) Latest milestone + insight.
            EntranceFader(index: 2, child: _MilestoneSpot()),
            const SizedBox(height: DS.s),
            EntranceFader(index: 3, child: _TopInsight()),
            const SizedBox(height: DS.xl),
          ],

          if (!isBrandNew || dash.daysLogged > 0) ...[
            // 5) Weekly overview.
            const SectionHeader(title: 'Your week'),
            const SizedBox(height: DS.m),
            if (dash.loading)
              const AppCard(child: AppLoading(message: 'Loading your week…'))
            else if (dash.daysLogged == 0)
              AppCard(
                child: Text(
                  'No data yet. Your last-7-days charts for wellness, sleep, exercise, and calm will appear here.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: DS.m,
                  vertical: DS.l,
                ),
                child: WeeklyCharts(week: dash.week),
              ),
            const SizedBox(height: DS.xl),

            // 6) Active experiment (quiet footer).
            SectionHeader(
              title: 'Active experiment',
              actionLabel: 'Open Lab',
              onAction: () => context.go('/lab'),
            ),
            const SizedBox(height: DS.m),
            _ActiveExperimentCard(
              loading: experiments.loading,
              onOpenLab: () => context.go('/lab'),
            ),
            const SizedBox(height: DS.xl),
          ],

          // 7) Quick actions (kept compact; every destination preserved).
          const _QuickActions(),

          if (daily.error != null || dash.error != null) ...[
            const SizedBox(height: DS.l),
            Text(
              daily.error ?? dash.error ?? '',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
          const SizedBox(height: DS.xxxl),
        ],
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = context.watch<ProfileProvider>().profile;
    final name = profile?.displayName?.trim();
    final hasName = name != null && name.isNotEmpty;
    final greeting = greetingForHour(DateTime.now().hour);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasName ? '$greeting,' : '$greeting.',
          style: theme.textTheme.displayMedium?.copyWith(
            height: 1.05,
            letterSpacing: -1.0,
          ),
        ),
        if (hasName)
          Text(
            name,
            style: theme.textTheme.displayMedium?.copyWith(
              height: 1.05,
              letterSpacing: -1.0,
              color: theme.colorScheme.primary,
            ),
          ),
        const SizedBox(height: DS.s),
        Text(
          'Based on your logged data',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: DS.textSecondary(theme.brightness),
          ),
        ),
      ],
    );
  }
}

/// Polished empty state for brand-new users.
class _EmptyHero extends StatelessWidget {
  final VoidCallback onLog;
  const _EmptyHero({required this.onLog});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EntranceFader(
      child: AppCard(
        padding: const EdgeInsets.all(DS.xxl),
        child: Column(
          children: [
            const SoulCareMark(size: 60, radius: 18),
            const SizedBox(height: DS.l),
            Text('No data yet', style: theme.textTheme.headlineSmall),
            const SizedBox(height: DS.s),
            Text(
              'Start with a 30-second check-in. Your wellness score, trends, and insights will grow from your logs.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: DS.textSecondary(theme.brightness),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DS.xl),
            FilledButton(
              onPressed: onLog,
              child: const Text('Log your first day'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hero: today's wellness score with an animated ring.
class _ScoreHero extends StatelessWidget {
  final VoidCallback? onTap;
  const _ScoreHero({this.onTap});

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DailyHealthProvider>();
    final week = context.watch<DashboardProvider>();
    final theme = Theme.of(context);
    final score = week.todayScore;
    final total = score?.totalScore ?? dash.todayWellnessScore;
    final color = Color(getScoreColor(total));

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(DS.xxl),
      child: week.loading || dash.loading
          ? const AppLoading(message: 'Scoring your day…')
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Today's wellness score",
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: DS.textSecondary(theme.brightness),
                        ),
                      ),
                      AnimatedNumber(
                        value: total,
                        style: theme.textTheme.displayLarge?.copyWith(
                          height: 1.1,
                          color: color,
                        ),
                      ),
                      Text(
                        getScoreLabel(total),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: DS.xs),
                      if (score?.change case final int delta when delta != 0)
                        Text(
                          delta > 0
                              ? '▲ $delta vs previous logged day'
                              : '▼ ${-delta} vs previous logged day',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: DS.textSecondary(theme.brightness),
                          ),
                        ),
                      Text(
                        'Tap for details · illustrative only, not a medical assessment.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: DS.textTertiary(theme.brightness),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: DS.l),
                ProgressRing(
                  value: total / 100,
                  size: 92,
                  stroke: 8.5,
                  color: color,
                  child: Icon(Icons.spa_outlined, size: 30, color: color),
                ),
              ],
            ),
    );
  }
}

/// Horizontal strip of today's headline metrics — Apple Health style
/// "Today" row. Uses real logged values only; missing values show "—".
class _TodayMetricsStrip extends StatelessWidget {
  const _TodayMetricsStrip();

  @override
  Widget build(BuildContext context) {
    final daily = context.watch<DailyHealthProvider>();
    final dash = context.watch<DashboardProvider>();
    final theme = Theme.of(context);
    final b = theme.brightness;
    final entry = daily.today;
    if (entry == null && daily.loading) {
      return const SizedBox.shrink();
    }
    final items = <(IconData, String, String, Color)>[
      (
        Icons.bedtime_outlined,
        'Sleep',
        entry != null ? '${entry.sleepHours.toStringAsFixed(1)}h' : '—',
        DS.metric(b, MetricDomain.sleep),
      ),
      (
        Icons.directions_run_outlined,
        'Movement',
        entry != null ? '${entry.exerciseMinutes}m' : '—',
        DS.metric(b, MetricDomain.activity),
      ),
      (
        Icons.water_drop_outlined,
        'Water',
        entry != null ? '${entry.waterGlasses}' : '—',
        DS.metric(b, MetricDomain.hydration),
      ),
      (
        Icons.spa_outlined,
        'Calm',
        (dash.week.isNotEmpty && dash.week.last.calm != null)
            ? '${dash.week.last.calm!.round()}'
            : '—',
        DS.metric(b, MetricDomain.mood),
      ),
    ];
    return SizedBox(
      height: 94,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: DS.m),
        itemBuilder: (context, i) {
          final it = items[i];
          return Container(
            width: 118,
            padding: const EdgeInsets.all(DS.l),
            decoration: BoxDecoration(
              color: DS.backgroundSecondary(b),
              borderRadius: BorderRadius.circular(DS.rLarge),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(it.$1, size: 20, color: it.$4),
                const Spacer(),
                Text(
                  it.$3,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    height: 1,
                    color: it.$4,
                  ),
                ),
                const SizedBox(height: DS.xs / 2),
                Text(
                  it.$2,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: DS.textSecondary(b),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Today's section progress, restyled as a clean metric strip.
class _TodayProgress extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final daily = context.watch<DailyHealthProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = daily.completedSections;
    final total = DailyHealthProvider.totalSections;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Daily progress', style: theme.textTheme.titleSmall),
              const Spacer(),
              AnimatedNumber(
                value: done,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: scheme.primary,
                ),
              ),
              Text(
                ' / $total',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: DS.textTertiary(theme.brightness),
                ),
              ),
            ],
          ),
          const SizedBox(height: DS.m),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: done / total),
            duration: DS.durSlow + const Duration(milliseconds: 300),
            curve: DS.curveEntrance,
            builder: (context, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 7,
                color: scheme.primary,
                backgroundColor: scheme.outline.withValues(alpha: 0.12),
              ),
            ),
          ),
          const SizedBox(height: DS.m),
          Wrap(
            spacing: DS.s,
            runSpacing: DS.s,
            children: [
              MetricChip(label: 'Sleep', done: daily.sleepDone),
              MetricChip(label: 'Movement', done: daily.movementDone),
              MetricChip(label: 'Nutrition', done: daily.nutritionDone),
              MetricChip(label: 'Mind', done: daily.mindDone),
              MetricChip(label: 'Stress', done: daily.stressDone),
            ],
          ),
        ],
      ),
    );
  }
}

/// The dashboard's 2×2 feature grid — Life Twin, Time Machine, Analytics,
/// SoulCare AI — same routes as the previous list rows.
class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 430 ? 2 : 1;
        const gap = DS.m;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: w,
              child: EntryTile(
                icon: Icons.hub_outlined,
                title: 'Life Twin',
                subtitle: 'See how your days connect',
                tint: scheme.primary,
                onTap: () => context.push('/life-twin'),
              ),
            ),
            SizedBox(
              width: w,
              child: EntryTile(
                icon: Icons.history_edu_outlined,
                title: 'Time Machine',
                subtitle: 'Replay your logged history',
                tint: DS.metric(
                  Theme.of(context).brightness,
                  MetricDomain.sleep,
                ),
                onTap: () => context.push('/time-machine'),
              ),
            ),
            SizedBox(
              width: w,
              child: EntryTile(
                icon: Icons.analytics_outlined,
                title: 'Analytics Lab',
                subtitle: 'Trends and correlations',
                tint: DS.metric(
                  Theme.of(context).brightness,
                  MetricDomain.activity,
                ),
                onTap: () => context.push('/analytics'),
              ),
            ),
            SizedBox(
              width: w,
              child: EntryTile(
                icon: Icons.psychology_outlined,
                title: 'SoulCare AI',
                subtitle: 'Ask about your week',
                tint: DS.metric(
                  Theme.of(context).brightness,
                  MetricDomain.mood,
                ),
                onTap: () => context.push('/ai'),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Quiet milestone presence: the single most recent unlock (or the next
/// one quietly progressing), plus a View-all entry. Never a wall of badges.
class _MilestoneSpot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final miles = context.watch<MilestonesProvider>();
    final recent = miles.mostRecent;
    final next = miles.next;
    if (recent == null && next == null) {
      return const SizedBox.shrink();
    }
    final title = recent?.def.title ?? next!.def.title;
    final subtitle = recent != null
        ? 'Unlocked ${recent.achievedDate == null ? 'recently' : formatDate(recent.achievedDate!)} · tap to view all milestones'
        : 'Next: ${next!.progress} / ${next.def.target} days · tap to view all milestones';
    return EntryTile(
      icon: recent != null ? Icons.verified_outlined : Icons.flag_outlined,
      title: title,
      subtitle: subtitle,
      tint: recent != null ? scheme.primary : null,
      onTap: () => context.push('/milestones'),
    );
  }
}

class _TopInsight extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();
    final theme = Theme.of(context);
    final insight = dash.topInsight;
    if (dash.loading) {
      return const AppCard(child: AppLoading(message: 'Reading patterns…'));
    }
    if (insight == null) {
      return const SizedBox.shrink();
    }
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DS
                  .metric(theme.brightness, MetricDomain.nutrition)
                  .withValues(alpha: 0.13),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.lightbulb_outline,
              size: 19,
              color: DS.metric(theme.brightness, MetricDomain.nutrition),
            ),
          ),
          const SizedBox(width: DS.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Insight',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: DS.textTertiary(theme.brightness),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(insight.title, style: theme.textTheme.titleSmall),
                const SizedBox(height: DS.xs / 2),
                Text(
                  insight.body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: DS.textSecondary(theme.brightness),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveExperimentCard extends StatelessWidget {
  final bool loading;
  final VoidCallback onOpenLab;
  const _ActiveExperimentCard({required this.loading, required this.onOpenLab});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<ExperimentProvider>();
    if (loading) return const AppCard(child: AppLoading());
    if (provider.items.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.all(DS.l),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'No experiments yet. Try a tiny 7-day self-experiment.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            TextButton(onPressed: onOpenLab, child: const Text('Open Lab')),
          ],
        ),
      );
    }
    final active = provider.items.firstWhere(
      (e) => e.status.name == 'active',
      orElse: () => provider.items.first,
    );
    return EntryTile(
      icon: Icons.science_outlined,
      title: active.title,
      subtitle:
          '${active.status.name} · ${active.durationDays} days · ${active.checkIns.length} check-ins',
      onTap: onOpenLab,
    );
  }
}

/// Compact "My goals" strip: current/target/%/trend/remaining per goal,
/// ordered by primary focus first, capped at 3. Hidden when there is no
/// logged week to measure against. Score algorithm untouched.
class _GoalStrip extends StatelessWidget {
  const _GoalStrip();

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();
    final profile = context.watch<ProfileProvider>().profile;
    final days = dash.week.where((d) => d.hasData && d.entry != null).toList();
    if (days.length < 2) return const SizedBox.shrink();

    final goals = computeGoalItems(
      entries: [for (final d in days) d.entry!],
      sleepTarget: profile?.sleepGoal ?? 7.5,
      exerciseTarget: (profile?.exerciseGoalWeek ?? 150).toDouble(),
      waterTarget: (profile?.waterGoal ?? 8).toDouble(),
      meditationTarget: (profile?.meditationGoal ?? 10).toDouble(),
    );

    final focusKey = goalKeyForFocusName(
      profile?.primaryFocus.name ?? 'general',
    );
    final shown = orderGoalsForFocus(goals, focusKey).take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'My goals'),
        const SizedBox(height: DS.m),
        for (final g in shown) ...[
          GoalProgressCard(progress: g.$2, compact: true),
          const SizedBox(height: DS.s),
        ],
        const SizedBox(height: DS.xs),
      ],
    );
  }
}

/// Quiet routine prompts. Morning shows until done; evening shows from
/// 5pm until done. Completed states collapse to one line. Never nagging.
class _RoutineCards extends StatelessWidget {
  const _RoutineCards();

  static bool get _eveningWindow {
    final h = DateTime.now().hour;
    return h >= 17;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final morning = context.watch<MorningProvider>();
    final evening = context.watch<EveningProvider>();
    final showMorning = !morning.done;
    final showEvening = _eveningWindow && !evening.done;
    if (!showMorning && !showEvening) return const SizedBox.shrink();
    return Column(
      children: [
        if (showMorning)
          Padding(
            padding: const EdgeInsets.only(bottom: DS.s),
            child: EntryTile(
              icon: Icons.wb_sunny_outlined,
              title: 'Start your morning check-in',
              subtitle: '30 seconds: sleep, mood, energy, intention',
              tint: DS.metric(theme.brightness, MetricDomain.nutrition),
              onTap: () => context.go('/home/morning'),
            ),
          ),
        if (showEvening)
          Padding(
            padding: const EdgeInsets.only(bottom: DS.s),
            child: EntryTile(
              icon: Icons.nights_stay_outlined,
              title: 'Reflect on your day',
              subtitle: 'Mood, energy, strain, one quiet minute',
              tint: DS.metric(theme.brightness, MetricDomain.sleep),
              onTap: () => context.go('/home/evening'),
            ),
          ),
        const SizedBox(height: DS.s),
      ],
    );
  }
}

/// "What should I pay attention to today?" — at most 3 honest,
/// dismissible actions built from observed facts. Never medical advice,
/// never invented urgency. Dismissals last the day; ignored items are
/// never escalated.
class _ActionCenter extends StatelessWidget {
  const _ActionCenter();

  @override
  Widget build(BuildContext context) {
    final daily = context.watch<DailyHealthProvider>();
    final dash = context.watch<DashboardProvider>();
    final morning = context.watch<MorningProvider>();
    final evening = context.watch<EveningProvider>();
    final experiments = context.watch<ExperimentProvider>();
    final profile = context.watch<ProfileProvider>().profile;
    final actions = context.watch<ActionCenterProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    RemindersProvider? reminders;
    try {
      reminders = context.watch<RemindersProvider>();
    } catch (_) {
      reminders = null;
    }

    final days = dash.week.where((d) => d.hasData && d.entry != null).toList();
    final goals = computeGoalItems(
      entries: [for (final d in days) d.entry!],
      sleepTarget: profile?.sleepGoal ?? 7.5,
      exerciseTarget: (profile?.exerciseGoalWeek ?? 150).toDouble(),
      waterTarget: (profile?.waterGoal ?? 8).toDouble(),
      meditationTarget: (profile?.meditationGoal ?? 10).toDouble(),
    );
    final focusKey = goalKeyForFocusName(
      profile?.primaryFocus.name ?? 'general',
    );
    final gaps = [
      for (final g in goals)
        if (g.$2.remaining > 0)
          GoalGap(
            label: g.$2.label.replaceAll(' Goal', ''),
            detail:
                '${formatGoalValue(g.$2.current, g.$2.unit)} of ${formatGoalValue(g.$2.target, g.$2.unit)} — ${formatGoalValue(g.$2.remaining, g.$2.unit)} to go',
            focusKey: g.$1,
            matchesFocus: g.$1 == focusKey,
          ),
    ];

    ExperimentDue? due;
    final active = experiments.activeExperiment;
    if (active != null && active.startDate != null) {
      final now = DateTime.now();
      final key =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      if (!active.checkIns.contains(key) && !active.missedDays.contains(key)) {
        due = ExperimentDue(
          title: active.title,
          dayNumber: dayNumber(active, now),
          durationDays: active.durationDays,
        );
      }
    }

    final appts = <AppointmentDue>[];
    final upcoming = reminders?.upcoming(maxDays: 1) ?? const [];
    for (final u in upcoming) {
      if (!u.isAppointment) continue;
      appts.add(
        AppointmentDue(
          title: u.title,
          timeLabel:
              '${u.at.hour.toString().padLeft(2, '0')}:${u.at.minute.toString().padLeft(2, '0')}',
        ),
      );
    }

    final hour = DateTime.now().hour;
    final items = buildActions(
      ActionContext(
        completedSections: daily.completedSections,
        totalSections: DailyHealthProvider.totalSections,
        morningDone: morning.done,
        eveningDone: evening.done,
        eveningWindow: hour >= 17,
        goalGaps: gaps,
        experimentDue: due,
        appointmentsToday: appts,
      ),
    ).where((a) => !actions.dismissed.contains(a.dismissKey)).toList();

    if (items.isEmpty) {
      if (dash.loading || daily.loading) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Today'),
          const SizedBox(height: DS.m),
          AppCard(
            padding: const EdgeInsets.all(DS.l),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, color: scheme.primary),
                const SizedBox(width: DS.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(caughtUpTitle, style: theme.textTheme.titleSmall),
                      Text(
                        caughtUpBody,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: DS.textSecondary(theme.brightness),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: DS.xl),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Today'),
        const SizedBox(height: DS.m),
        for (final a in items)
          Padding(
            padding: const EdgeInsets.only(bottom: DS.s),
            child: EntryTile(
              icon: Icons.arrow_circle_right_outlined,
              title: a.title,
              subtitle: a.explanation,
              onTap: () => context.go(a.destination),
              trailing: _DismissButton(
                onDismiss: () => actions.dismiss(a.dismissKey),
              ),
            ),
          ),
        const SizedBox(height: DS.xl),
      ],
    );
  }
}

class _DismissButton extends StatelessWidget {
  final VoidCallback onDismiss;
  const _DismissButton({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.close, size: 18),
      tooltip: 'Dismiss for today',
      splashRadius: 18,
      onPressed: onDismiss,
    );
  }
}

/// Editor's picks — every previous quick action preserved, restyled as a
/// calm grid of links instead of a pile of buttons.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final items = <(IconData, String, String)>[
      (Icons.edit_note_outlined, 'Log today', '/today'),
      (Icons.mic_outlined, 'Quick Voice Log', '/home/voice'),
      (Icons.psychology_outlined, 'SoulCare AI', '/ai'),
      (Icons.book_outlined, 'Journal', '/home/journal'),
      (Icons.calendar_month_outlined, 'Calendar', '/calendar'),
      (Icons.health_and_safety_outlined, 'Health Card', '/health-card'),
      (Icons.assessment_outlined, 'Reports', '/home/reports'),
      (Icons.medical_information_outlined, 'Snapshot', '/home/snapshot'),
      (Icons.alarm_outlined, 'Reminders', '/home/care'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Quick actions', style: theme.textTheme.titleMedium),
            const Spacer(),
            TextButton(
              onPressed: () => context.go('/timeline'),
              child: Text(
                'Timeline',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: DS.m),
        SizedBox(
          height: 78,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: DS.s),
            itemBuilder: (context, i) {
              final item = items[i];
              return PressableScale(
                onTap: item.$3.startsWith('/today')
                    ? () => context.go(item.$3)
                    : () => context.push(item.$3),
                borderRadius: DS.rMedium,
                child: Container(
                  width: 92,
                  padding: const EdgeInsets.symmetric(
                      horizontal: DS.s, vertical: DS.m),
                  decoration: BoxDecoration(
                    color: DS.backgroundSecondary(
                        Theme.of(context).brightness),
                    borderRadius: BorderRadius.circular(DS.rMedium),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item.$1, size: 20, color: scheme.primary),
                      const SizedBox(height: DS.xs),
                      Text(
                        item.$2,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: DS.textSecondary(theme.brightness),
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}


