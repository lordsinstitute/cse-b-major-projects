import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/design_system.dart';
import '../../core/widgets/ui_kit.dart';

/// /settings — hub of grouped subsections, organized as an iOS-style
/// inset-grouped list. Each category opens its own screen (same routes);
/// everything stays local-first.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _core = (
    Icons.person_outline,
    'Profile & goals',
    'Optional context and targets — never required',
    '/settings/profile',
    'appearance',
  );

  static const List<(IconData, String, String, String)> _groups = [
    (
      Icons.palette_outlined,
      'Appearance',
      'Theme, colors, zoom and fonts',
      '/settings/appearance',
    ),
    (
      Icons.notifications_outlined,
      'Notifications',
      'Daily + experiment reminders',
      '/settings/notifications',
    ),
    (
      Icons.lock_outline,
      'Privacy lock',
      'Biometrics + PIN protection',
      '/settings/lock',
    ),
    (
      Icons.favorite_outline,
      'Health data',
      'Optional device integration',
      '/settings/health',
    ),
    (
      Icons.privacy_tip_outlined,
      'Privacy & About',
      'What stays local, plus about SoulCare',
      '/settings/privacy',
    ),
    (
      Icons.psychology_outlined,
      'SoulCare AI',
      'Local or cloud assistant, you choose',
      '/settings/ai',
    ),
    (
      Icons.folder_outlined,
      'Data & backup',
      'Export, backup, delete',
      '/settings/data',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        DS.xl,
        DS.huge - DS.xl,
        DS.xl,
        DS.massive,
      ),
      children: [
        const PageHeader(
          title: 'Settings',
          subtitle: 'Private and local-first — your data stays on this device',
        ),
        const SizedBox(height: DS.xxl),
        ListGroup(
          children: [
            ListRow(
              icon: _core.$1,
              title: _core.$2,
              subtitle: _core.$3,
              onTap: () => context.push(_core.$4),
            ),
          ],
        ),
        const SizedBox(height: DS.m),
        ListGroup(
          children: [
            for (final g in _groups)
              ListRow(
                icon: g.$1,
                title: g.$2,
                subtitle: g.$3,
                onTap: () => context.push(g.$4),
              ),
          ],
        ),
        const SizedBox(height: DS.xxxl),
        Text(
          'SoulCare · local-first by design',
          style: theme.textTheme.bodySmall?.copyWith(
            color: DS.textTertiary(theme.brightness),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
