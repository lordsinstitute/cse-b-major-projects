import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/providers/profile_provider.dart';
import '../../app/providers/settings_provider.dart';
import '../../app/theme/design_system.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/user_profile.dart';

/// First-run setup. No login, fully skippable, never reshown unless the
/// user replays it from Settings. Writes profile targets + reminder
/// preference + the onboarding completion flag.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;
  bool _finishing = false;

  final List<WellnessFocus> _foci = [];
  bool _goalSleep = false;
  bool _goalSleep8 = false;
  bool _goalMove = false;
  bool _goalMove90 = false;
  bool _goalWater = false;
  bool _goalWater6 = false;
  bool _goalMind = false;
  bool _goalMind5 = false;
  bool? _wantsReminder;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 20, minute: 0);

  static const int _last = 5;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  int get _goalCount => [
    _goalSleep,
    _goalSleep8,
    _goalMove,
    _goalMove90,
    _goalWater,
    _goalWater6,
    _goalMind,
    _goalMind5,
  ].where((g) => g).length;

  void _toggleFocus(WellnessFocus f) {
    setState(() {
      if (_foci.contains(f)) {
        _foci.remove(f);
      } else if (_foci.length >= 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick up to 2 focus areas.')),
        );
      } else {
        _foci.add(f);
      }
    });
  }

  void _next() {
    if (_index >= _last) return;
    setState(() => _index++);
    _pages.animateToPage(
      _index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _back() {
    if (_index <= 0) return;
    setState(() => _index--);
    _pages.animateToPage(
      _index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _skip() async {
    final settings = context.read<SettingsProvider>();
    await settings.update(settings.settings.copyWith(onboardingDone: true));
    if (!mounted) return;
    context.go('/home');
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    // Captured before any await (State stays alive via _finishing guard).
    final profileProv = context.read<ProfileProvider>();
    final settingsProv = context.read<SettingsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    var reminderNote = false;
    try {
      // Profile: focus + chosen preset targets (untouched stays default).
      // Within one area the higher chosen tier wins.
      try {
        await profileProv.load();
        final base = profileProv.profile ?? UserProfile.fresh();
        await profileProv.save(
          base.copyWith(
            primaryFocus: _foci.isEmpty ? null : _foci.first,
            secondaryFocus: () => _foci.length > 1 ? _foci[1] : null,
            sleepGoal: _goalSleep8
                ? 8.0
                : _goalSleep
                ? 7.5
                : base.sleepGoal,
            exerciseGoalWeek: _goalMove
                ? 150
                : _goalMove90
                ? 90
                : base.exerciseGoalWeek,
            waterGoal: _goalWater
                ? 8
                : _goalWater6
                ? 6
                : base.waterGoal,
            meditationGoal: _goalMind
                ? 10
                : _goalMind5
                ? 5
                : base.meditationGoal,
          ),
        );
      } catch (_) {}

      // Reminders: only requested when the user said yes. A denied or
      // missing permission leaves reminders off but never blocks finish.
      var enabled = false;
      if (_wantsReminder == true) {
        try {
          await NotificationService.init();
          final granted = await NotificationService.requestPermission();
          if (granted) {
            await NotificationService.scheduleDailyReminder(_reminderTime);
            enabled = true;
          } else {
            reminderNote = true;
          }
        } catch (_) {
          reminderNote = true;
        }
      }
      try {
        final current = settingsProv.settings;
        await settingsProv.update(
          current.copyWith(
            notificationsEnabled: enabled,
            dailyReminderTime: NotificationService.formatReminderTime(
              _reminderTime,
            ),
            onboardingDone: true,
          ),
        );
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
    if (!mounted) return;
    if (reminderNote) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Reminder permission was not granted — time saved, reminders off.',
          ),
        ),
      );
    }
    router.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome'),
        actions: [TextButton(onPressed: _skip, child: const Text('Skip'))],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pages,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _index = i),
              children: [
                _WelcomePage(onNext: _next),
                _FocusPage(foci: _foci, onToggle: _toggleFocus, onNext: _next),
                _GoalsPage(
                  sleep: _goalSleep,
                  sleep8: _goalSleep8,
                  move: _goalMove,
                  move90: _goalMove90,
                  water: _goalWater,
                  water6: _goalWater6,
                  mind: _goalMind,
                  mind5: _goalMind5,
                  onToggle: (which, v) => setState(() {
                    if (v &&
                        _goalCount >= 3 &&
                        ![
                          _goalSleep,
                          _goalSleep8,
                          _goalMove,
                          _goalMove90,
                          _goalWater,
                          _goalWater6,
                          _goalMind,
                          _goalMind5,
                        ][_whichIndex(which)]) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Pick up to 3 to start — add more later.',
                          ),
                        ),
                      );
                      return;
                    }
                    switch (which) {
                      case _GoalKind.sleep:
                        _goalSleep = v;
                      case _GoalKind.sleep8:
                        _goalSleep8 = v;
                      case _GoalKind.move:
                        _goalMove = v;
                      case _GoalKind.move90:
                        _goalMove90 = v;
                      case _GoalKind.water:
                        _goalWater = v;
                      case _GoalKind.water6:
                        _goalWater6 = v;
                      case _GoalKind.mind:
                        _goalMind = v;
                      case _GoalKind.mind5:
                        _goalMind5 = v;
                    }
                  }),
                  onNext: _next,
                ),
                _RemindersPage(
                  choice: _wantsReminder,
                  time: _reminderTime,
                  onChoice: (v) => setState(() => _wantsReminder = v),
                  onTime: (t) => setState(() => _reminderTime = t),
                  onNext: _next,
                ),
                _PrivacyPage(onNext: _next),
                _ReadyPage(finishing: _finishing, onFinish: _finish),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (_index > 0)
                  TextButton(onPressed: _back, child: const Text('Back')),
                const Spacer(),
                Text(
                  '${_index + 1} of ${_last + 1}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static int _whichIndex(_GoalKind k) {
    switch (k) {
      case _GoalKind.sleep:
        return 0;
      case _GoalKind.sleep8:
        return 1;
      case _GoalKind.move:
        return 2;
      case _GoalKind.move90:
        return 3;
      case _GoalKind.water:
        return 4;
      case _GoalKind.water6:
        return 5;
      case _GoalKind.mind:
        return 6;
      case _GoalKind.mind5:
        return 7;
    }
  }
}

enum _GoalKind { sleep, sleep8, move, move90, water, water6, mind, mind5 }

class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;
  const _WelcomePage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(DS.xxxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: DS.xxxl),
          const SoulCareMark(size: 88, radius: 24),
          const SizedBox(height: DS.xxl),
          Text(
            'Welcome to SoulCare.',
            style: theme.textTheme.headlineSmall?.copyWith(height: 1.15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DS.m),
          Text(
            'Track your daily wellness, discover your personal patterns, and build routines that work for you.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: DS.textSecondary(theme.brightness),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DS.massive),
          SizedBox(
            width: 200,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: onNext,
              child: const Text('Get started'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusPage extends StatelessWidget {
  final List<WellnessFocus> foci;
  final ValueChanged<WellnessFocus> onToggle;
  final VoidCallback onNext;
  const _FocusPage({
    required this.foci,
    required this.onToggle,
    required this.onNext,
  });

  static const _choices = [
    WellnessFocus.betterSleep,
    WellnessFocus.energy,
    WellnessFocus.moreMovement,
    WellnessFocus.stressManagement,
    WellnessFocus.hydration,
    WellnessFocus.mindfulness,
    WellnessFocus.consistency,
    WellnessFocus.healthyEating,
    WellnessFocus.screenBalance,
    WellnessFocus.general,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'What would you like to focus on?',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Pick up to 2 — shapes suggestions only.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in _choices)
              FilterChip(
                label: Text(f.label),
                selected: foci.contains(f),
                onSelected: (_) => onToggle(f),
              ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: onNext, child: const Text('Continue')),
      ],
    );
  }
}

class _GoalsPage extends StatelessWidget {
  final bool sleep;
  final bool sleep8;
  final bool move;
  final bool move90;
  final bool water;
  final bool water6;
  final bool mind;
  final bool mind5;
  final void Function(_GoalKind, bool) onToggle;
  final VoidCallback onNext;
  const _GoalsPage({
    required this.sleep,
    required this.sleep8,
    required this.move,
    required this.move90,
    required this.water,
    required this.water6,
    required this.mind,
    required this.mind5,
    required this.onToggle,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [
      (_GoalKind.sleep, 'Sleep 7+ hours', sleep),
      (_GoalKind.sleep8, 'Sleep 8 hours', sleep8),
      (_GoalKind.move, 'Move 150 min/week', move),
      (_GoalKind.move90, 'Move 90 min/week', move90),
      (_GoalKind.water, 'Drink 8 glasses/day', water),
      (_GoalKind.water6, 'Drink 6 glasses/day', water6),
      (_GoalKind.mind, 'Meditate 10 minutes/day', mind),
      (_GoalKind.mind5, 'Meditate 5 minutes/day', mind5),
    ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Pick up to 3 starter goals',
          style: theme.textTheme.headlineSmall,
        ),
        Text(
          'Optional — higher tiers win within an area; everything stays editable later.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        for (final r in rows)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(r.$2),
            value: r.$3,
            onChanged: (v) => onToggle(r.$1, v ?? false),
          ),
        const SizedBox(height: 12),
        FilledButton(onPressed: onNext, child: const Text('Continue')),
      ],
    );
  }
}

class _RemindersPage extends StatelessWidget {
  final bool? choice;
  final TimeOfDay time;
  final ValueChanged<bool> onChoice;
  final ValueChanged<TimeOfDay> onTime;
  final VoidCallback onNext;
  const _RemindersPage({
    required this.choice,
    required this.time,
    required this.onChoice,
    required this.onTime,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Would you like a daily reminder?',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.tonal(
                onPressed: choice == true ? null : () => onChoice(true),
                child: const Text('Yes'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: choice == false ? null : () => onChoice(false),
                child: const Text('Not now'),
              ),
            ],
          ),
          if (choice == true) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Reminder time', style: theme.textTheme.bodyMedium),
                  TextButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: time,
                      );
                      if (picked != null) onTime(picked);
                    },
                    child: Text(time.format(context)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: choice == null ? null : onNext,
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}

class _PrivacyPage extends StatelessWidget {
  final VoidCallback onNext;
  const _PrivacyPage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            'Your data stays yours.',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Your SoulCare data is stored locally on this device unless you explicitly choose a feature that sends data elsewhere — like sharing an export. No account, no cloud required.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: onNext, child: const Text('Continue')),
        ],
      ),
    );
  }
}

class _ReadyPage extends StatelessWidget {
  final bool finishing;
  final VoidCallback onFinish;
  const _ReadyPage({required this.finishing, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text("You're ready.", style: theme.textTheme.headlineSmall),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: finishing ? null : onFinish,
            child: Text(finishing ? 'Saving…' : 'Open SoulCare'),
          ),
        ],
      ),
    );
  }
}
