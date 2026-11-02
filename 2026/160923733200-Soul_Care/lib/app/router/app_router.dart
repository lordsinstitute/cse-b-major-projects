import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../theme/design_system.dart';

import '../../features/daily_health/daily_health_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/checkins/evening_screen.dart';
import '../../features/checkins/morning_screen.dart';
import '../../features/journal/journal_detail_screen.dart';
import '../../features/journal/journal_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/reminders/reminders_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/snapshot/snapshot_screen.dart';
import '../../features/experiments/experiments_screen.dart';
import '../../features/games/breathing_pacer_screen.dart';
import '../../features/games/bubble_game_screen.dart';
import '../../features/games/color_game_screen.dart';
import '../../features/games/echo_game_screen.dart';
import '../../features/games/games_screen.dart';
import '../../features/games/memory_game_screen.dart';
import '../../features/games/reaction_game_screen.dart';
import '../../features/games/scramble_game_screen.dart';
import '../../features/games/sequence_game_screen.dart';
import '../../features/ai/ai_screen.dart';
import '../../features/ai/ai_settings_screen.dart';
import '../../features/analytics/analytics_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/health_card/health_card_screen.dart';
import '../../features/milestones/milestones_screen.dart';
import '../../features/life_twin/life_twin_screen.dart';
import '../../features/time_machine/time_machine_screen.dart';
import '../../features/voice_log/voice_log_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/settings/settings_appearance.dart';
import '../../features/settings/settings_data.dart';
import '../../features/settings/settings_health.dart';
import '../../features/settings/settings_lock.dart';
import '../../features/settings/settings_notifications.dart';
import '../../features/settings/settings_privacy.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/simulator/simulator_screen.dart';
import '../../features/timeline/document_detail_screen.dart';
import '../../features/timeline/pdf_viewer_screen.dart';
import '../../features/timeline/timeline_screen.dart';
import 'scaffold_shell.dart';

final appRouter = createAppRouter();

/// Pure redirect rule (unit-tested): unfinished users belong on
/// /welcome; finished users never see it.
String? onboardingRedirect({required bool onboarded, required String path}) {
  if (!onboarded && path != '/welcome') return '/welcome';
  if (onboarded && path == '/welcome') return '/home';
  return null;
}

/// Shared page transition for pushed destinations: a quick fade with a
/// subtle horizontal drift — quiet and confident, like an iOS modal
/// push. Tab-level branches keep their instant switch.
CustomTransitionPage<void> _transitionPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Interval(0, 1, curve: DS.curveEntrance),
      );
      final fade = CurvedAnimation(
        parent: animation,
        curve: Interval(0, 0.6, curve: DS.curveEntrance),
      );
      return SlideTransition(
        position: Tween(
          begin: const Offset(0.06, 0),
          end: Offset.zero,
        ).animate(curve),
        child: FadeTransition(
          opacity: Tween<double>(begin: 0, end: 1).animate(fade),
          child: child,
        ),
      );
    },
  );
}

GoRouter createAppRouter({bool onboarded = true}) => GoRouter(
  initialLocation: onboarded ? '/home' : '/welcome',
  // Reads the LIVE setting on every navigation: the router is created once
  // with the boot-time flag, but finishing onboarding flips the persisted
  // flag afterwards. A captured value would bounce every post-onboarding
  // trip to /home back to /welcome (dead "Open SoulCare" button).
  redirect: (context, state) {
    bool live;
    try {
      live = context.read<SettingsProvider>().settings.onboardingDone;
    } catch (_) {
      live = onboarded;
    }
    return onboardingRedirect(onboarded: live, path: state.uri.path);
  },
  routes: [
    GoRoute(
      path: '/welcome',
      pageBuilder: (c, s) => _transitionPage(s, const OnboardingScreen()),
    ),
    GoRoute(
      path: '/life-twin',
      pageBuilder: (c, s) => _transitionPage(s, const LifeTwinScreen()),
    ),
    GoRoute(
      path: '/time-machine',
      pageBuilder: (c, s) {
        final m = s.uri.queryParameters['month'];
        DateTime? anchor;
        if (m != null) {
          final parsed = DateTime.tryParse('$m-01');
          if (parsed != null) anchor = parsed;
        }
        return _transitionPage(s, TimeMachineScreen(initialAnchor: anchor));
      },
    ),
    GoRoute(
      path: '/analytics',
      pageBuilder: (c, s) => _transitionPage(s, const AnalyticsScreen()),
    ),
    GoRoute(
      path: '/health-card',
      pageBuilder: (c, s) => _transitionPage(s, const HealthCardScreen()),
    ),
    GoRoute(
      path: '/calendar',
      pageBuilder: (c, s) => _transitionPage(s, const CalendarScreen()),
    ),
    GoRoute(
      path: '/ai',
      pageBuilder: (c, s) => _transitionPage(s, const AiScreen()),
    ),
    GoRoute(
      path: '/milestones',
      pageBuilder: (c, s) => _transitionPage(s, const MilestonesScreen()),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => ScaffoldShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (c, s) => const DashboardScreen(),
              routes: [
                GoRoute(
                  path: 'morning',
                  pageBuilder: (c, s) =>
                      _transitionPage(s, const MorningScreen()),
                ),
                GoRoute(
                  path: 'evening',
                  pageBuilder: (c, s) =>
                      _transitionPage(s, const EveningScreen()),
                ),
                GoRoute(
                  path: 'journal',
                  pageBuilder: (c, s) =>
                      _transitionPage(s, const JournalScreen()),
                  routes: [
                    GoRoute(
                      path: ':id',
                      pageBuilder: (c, s) => _transitionPage(
                        s,
                        JournalDetailScreen(
                          entryId: s.pathParameters['id'] ?? '',
                        ),
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'reports',
                  pageBuilder: (c, s) =>
                      _transitionPage(s, const ReportsScreen()),
                ),
                GoRoute(
                  path: 'snapshot',
                  pageBuilder: (c, s) =>
                      _transitionPage(s, const SnapshotScreen()),
                ),
                GoRoute(
                  path: 'care',
                  pageBuilder: (c, s) =>
                      _transitionPage(s, const RemindersScreen()),
                ),
                GoRoute(
                  path: 'voice',
                  pageBuilder: (c, s) =>
                      _transitionPage(s, VoiceLogScreen.withMic()),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/today',
              builder: (c, s) => const DailyHealthScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/timeline',
              builder: (c, s) => const TimelineScreen(),
              routes: [
                GoRoute(
                  path: 'doc/:id',
                  pageBuilder: (c, s) => _transitionPage(
                    s,
                    DocumentDetailScreen(
                      documentId: s.pathParameters['id'] ?? '',
                    ),
                  ),
                  routes: [
                    GoRoute(
                      path: 'view',
                      pageBuilder: (c, s) => _transitionPage(
                        s,
                        PdfViewerScreen(
                          documentId: s.pathParameters['id'] ?? '',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/lab', builder: (c, s) => const ExperimentsScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/future',
              builder: (c, s) => const SimulatorScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/games',
              builder: (c, s) => const GamesScreen(),
              routes: [
                GoRoute(
                  path: 'memory',
                  pageBuilder: (c, s) => _transitionPage(
                    s,
                    const GameScope(child: MemoryGameScreen()),
                  ),
                ),
                GoRoute(
                  path: 'reaction',
                  pageBuilder: (c, s) => _transitionPage(
                    s,
                    const GameScope(child: ReactionGameScreen()),
                  ),
                ),
                GoRoute(
                  path: 'sequence',
                  pageBuilder: (c, s) => _transitionPage(
                    s,
                    const GameScope(child: SequenceGameScreen()),
                  ),
                ),
                GoRoute(
                  path: 'breathing',
                  pageBuilder: (c, s) => _transitionPage(
                    s,
                    const GameScope(child: BreathingPacerScreen()),
                  ),
                ),
                GoRoute(
                  path: 'scramble',
                  pageBuilder: (c, s) => _transitionPage(
                    s,
                    const GameScope(child: ScrambleGameScreen()),
                  ),
                ),
                GoRoute(
                  path: 'color',
                  pageBuilder: (c, s) => _transitionPage(
                    s,
                    const GameScope(child: ColorGameScreen()),
                  ),
                ),
                GoRoute(
                  path: 'echo',
                  pageBuilder: (c, s) => _transitionPage(
                    s,
                    const GameScope(child: EchoGameScreen()),
                  ),
                ),
                GoRoute(
                  path: 'bubbles',
                  pageBuilder: (c, s) => _transitionPage(
                    s,
                    const GameScope(child: BubbleGameScreen()),
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (c, s) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'profile',
                  pageBuilder: (c, s) =>
                      _transitionPage(s, const ProfileScreen()),
                ),
                GoRoute(
                  path: 'appearance',
                  pageBuilder: (c, s) =>
                      _transitionPage(s, const AppearanceScreen()),
                ),
                GoRoute(
                  path: 'notifications',
                  pageBuilder: (c, s) =>
                      _transitionPage(s, const NotificationsScreen()),
                ),
                GoRoute(
                  path: 'lock',
                  pageBuilder: (c, s) => _transitionPage(s, const LockScreen()),
                ),
                GoRoute(
                  path: 'health',
                  pageBuilder: (c, s) =>
                      _transitionPage(s, const HealthDataScreen()),
                ),
                GoRoute(
                  path: 'privacy',
                  pageBuilder: (c, s) =>
                      _transitionPage(s, const PrivacyScreen()),
                ),
                GoRoute(
                  path: 'data',
                  pageBuilder: (c, s) => _transitionPage(s, const DataScreen()),
                ),
                GoRoute(
                  path: 'ai',
                  pageBuilder: (c, s) =>
                      _transitionPage(s, const AiSettingsScreen()),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
