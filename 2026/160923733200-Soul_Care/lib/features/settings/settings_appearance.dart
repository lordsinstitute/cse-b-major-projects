import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/providers/settings_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../data/models/models.dart';

/// /settings/appearance — theme, palette, zoom, fonts.
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  Future<void> _update(UserSettings next, {String? okMessage}) async {
    final prov = context.read<SettingsProvider>();
    final ok = await prov.update(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? (okMessage ?? 'Saved ✓')
            : (prov.error ?? 'Could not save settings.'))));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().settings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appearance'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/settings'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Theme', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'system', label: Text('System')),
                ButtonSegment(
                    value: 'light', label: Text('Light')),
                ButtonSegment(value: 'dark', label: Text('Dark')),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (sel) =>
                  _update(s.copyWith(themeMode: sel.first)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Color palette',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final p in AppTheme.palettes)
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () =>
                      _update(s.copyWith(colorSeed: p.$2)),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(p.$2),
                      border: Border.all(
                        color: s.colorSeed == p.$2
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: s.colorSeed == p.$2 ? 3 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: s.colorSeed == p.$2
                        ? Icon(Icons.check,
                            color: scheme.onPrimary)
                        : null,
                  ),
                ),
            ],
          ),
          Text(
              'Palette: ${AppTheme.palettes.firstWhere((p) => p.$2 == s.colorSeed, orElse: () => AppTheme.palettes.first).$1}',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Text('Interface zoom (${(s.uiZoom * 100).round()}%)',
              style: theme.textTheme.titleSmall),
          Slider(
            min: 0.5,
            max: 2.0,
            divisions: 15,
            value: s.uiZoom.clamp(0.5, 2.0),
            label: '${(s.uiZoom * 100).round()}%',
            onChanged: (v) =>
                _update(s.copyWith(uiZoom: v)),
          ),
          Text('100% is default · range 50%–200%',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Text('Font style',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in AppTheme.fontChoices)
                ChoiceChip(
                  label: Text(AppTheme.fontLabel(f)),
                  selected: s.fontFamily == f,
                  onSelected: (_) =>
                      _update(s.copyWith(fontFamily: () => f)),
                ),
            ],
          ),
          Text(
              'Named fonts download once when online, then work offline from then on.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Text('Font size (${(s.fontScale * 100).round()}%)',
              style: theme.textTheme.titleSmall),
          Slider(
            min: 0.8,
            max: 1.4,
            divisions: 6,
            value: s.fontScale.clamp(0.8, 1.4),
            label: '${(s.fontScale * 100).round()}%',
            onChanged: (v) =>
                _update(s.copyWith(fontScale: v)),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _update(s.copyWith(
              uiZoom: 1.0,
              fontFamily: () => null,
              fontScale: 1.0,
            )),
            child: const Text('Reset look'),
          ),
          Text('Resets zoom, font style and size to defaults.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
