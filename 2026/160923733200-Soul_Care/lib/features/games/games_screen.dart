import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/design_system.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/ui_kit.dart';
import 'games_provider.dart';
import 'memory_game_screen.dart' show statsText;

/// /games hub: eight isolated games + persisted stats per game.
class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => GamesProvider(),
      child: const _GamesHub(),
    );
  }
}

class _GameEntry {
  final String id;
  final String title;
  final String blurb;
  final IconData icon;
  final String route;

  const _GameEntry({
    required this.id,
    required this.title,
    required this.blurb,
    required this.icon,
    required this.route,
  });
}

const _games = [
  _GameEntry(
    id: 'memory',
    title: 'Memory Match',
    blurb: 'Flip pairs of calm cards.',
    icon: Icons.grid_view,
    route: '/games/memory',
  ),
  _GameEntry(
    id: 'reaction',
    title: 'Reaction Time',
    blurb: 'Five rounds — tap on green.',
    icon: Icons.bolt_outlined,
    route: '/games/reaction',
  ),
  _GameEntry(
    id: 'sequence',
    title: 'Number Sequence',
    blurb: 'Tap numbers in order, growing levels.',
    icon: Icons.format_list_numbered,
    route: '/games/sequence',
  ),
  _GameEntry(
    id: 'breathing',
    title: 'Breathing Pacer',
    blurb: 'Guided inhale · hold · exhale.',
    icon: Icons.self_improvement_outlined,
    route: '/games/breathing',
  ),
  _GameEntry(
    id: 'scramble',
    title: 'Word Scramble',
    blurb: 'Unscramble wellness words.',
    icon: Icons.spellcheck_outlined,
    route: '/games/scramble',
  ),
  _GameEntry(
    id: 'color',
    title: 'Color Match',
    blurb: 'Tap the ink color, not the word.',
    icon: Icons.palette_outlined,
    route: '/games/color',
  ),
  _GameEntry(
    id: 'echo',
    title: 'Pattern Echo',
    blurb: 'Watch, then repeat the pattern.',
    icon: Icons.grid_on_outlined,
    route: '/games/echo',
  ),
  _GameEntry(
    id: 'bubbles',
    title: 'Bubble Pop',
    blurb: '30 calm seconds of popping.',
    icon: Icons.bubble_chart_outlined,
    route: '/games/bubbles',
  ),
];

/// Scope wrapper: every game screen (hub children included) gets its own
/// GamesProvider backed by the same Hive stats. Sub-routes do NOT inherit
/// the hub's provider, so each screen brings its own — previously they
/// crashed on open with no provider in scope.
class GameScope extends StatelessWidget {
  final Widget child;
  const GameScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(create: (_) => GamesProvider(), child: child);
  }
}

class _GamesHub extends StatelessWidget {
  const _GamesHub();

  @override
  Widget build(BuildContext context) {
    final games = context.watch<GamesProvider>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        DS.xl,
        DS.huge - DS.xl,
        DS.xl,
        DS.massive,
      ),
      children: [
        const PageHeader(
          title: 'Games & mind breaks',
          subtitle: 'Short, calm, and stored only on this device',
        ),
        const SizedBox(height: DS.xl),
        if (games.loading)
          const AppCard(child: AppLoading())
        else
          for (final g in _games) ...[
            _GameCard(
              entry: g,
              statsLine: statsText(
                plays: games.statsFor(g.id).playCount,
                best: games.statsFor(g.id).bestScore,
                recent: games.statsFor(g.id).recentScore,
                unit: _unit(g.id),
              ),
              onTap: () => context.push(g.route),
            ),
            const SizedBox(height: DS.s),
          ],
        const SizedBox(height: DS.xl),
      ],
    );
  }

  static String _unit(String id) =>
      gameMetas.firstWhere((m) => m.id == id).scoreUnit;
}

class _GameCard extends StatelessWidget {
  final _GameEntry entry;
  final String statsLine;
  final VoidCallback onTap;

  const _GameCard({
    required this.entry,
    required this.statsLine,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(entry.icon, size: 32, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, style: theme.textTheme.titleSmall),
                Text(
                  entry.blurb,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  statsLine,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
