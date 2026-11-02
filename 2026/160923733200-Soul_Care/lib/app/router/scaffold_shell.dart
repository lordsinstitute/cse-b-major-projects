import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/design_system.dart';

/// Bottom-navigation shell. Android back button handled by go_router.
/// Visual: a floating, frosted capsule that keeps every destination,
/// label, and the exact branch behavior of the previous NavigationBar.
class ScaffoldShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const ScaffoldShell({super.key, required this.shell});

  static const _destinations = [
    (icon: Icons.home_outlined, active: Icons.home, label: 'Home'),
    (icon: Icons.today_outlined, active: Icons.today, label: 'Today'),
    (icon: Icons.timeline_outlined, active: Icons.timeline, label: 'Timeline'),
    (icon: Icons.science_outlined, active: Icons.science, label: 'Lab'),
    (
      icon: Icons.auto_graph_outlined,
      active: Icons.auto_graph,
      label: 'Future',
    ),
    (icon: Icons.games_outlined, active: Icons.games, label: 'Games'),
    (icon: Icons.settings_outlined, active: Icons.settings, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final barColor =
        (brightness == Brightness.dark
                ? const Color(0xF0101012)
                : const Color(0xF7FAFAFC))
            .withValues(alpha: 0.86);

    return Scaffold(
      // Contents stay above the floating bar (no scroll-under), while the
      // bar itself is a translucent frosted capsule with safe-area care.
      body: SafeArea(child: shell),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          DS.m,
          0,
          DS.m,
          MediaQuery.paddingOf(context).bottom + DS.s,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(DS.rXLarge - 4),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 56,
              decoration: BoxDecoration(color: barColor),
              child: Row(
                children: [
                  for (var i = 0; i < _destinations.length; i++)
                    Expanded(
                      child: _NavButton(
                        icon: _destinations[i].icon,
                        activeIcon: _destinations[i].active,
                        label: _destinations[i].label,
                        selected: shell.currentIndex == i,
                        accent: scheme.primary,
                        dim: DS.textSecondary(brightness),
                        onTap: () => shell.goBranch(
                          i,
                          initialLocation: i == shell.currentIndex,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final Color accent;
  final Color dim;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.dim,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: DS.durMedium,
          curve: DS.curveStandard,
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.13)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(DS.rMedium),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: DS.durFast,
                switchInCurve: DS.curveEntrance,
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: Tween<double>(begin: 0.85, end: 1).animate(anim),
                  child: child,
                ),
                child: Icon(
                  selected ? activeIcon : icon,
                  key: ValueKey(selected),
                  size: 21,
                  color: selected ? accent : dim,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.1,
                  letterSpacing: -0.1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? accent : dim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
