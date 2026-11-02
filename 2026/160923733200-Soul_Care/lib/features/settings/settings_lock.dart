import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/providers/settings_provider.dart';
import '../../data/models/models.dart';

/// /settings/lock — privacy lock scope, timing, sections, biometrics, PIN.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _busy = false;

  Future<void> _update(UserSettings next, {String? okMessage}) async {
    final prov = context.read<SettingsProvider>();
    final ok = await prov.update(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? (okMessage ?? 'Saved ✓')
            : (prov.error ?? 'Could not save settings.'))));
  }

  Future<void> _setScope(String scope) async {
    if (_busy) return;
    if (scope == 'off') {
      await _toggleLock(false);
      return;
    }
    final prov = context.read<SettingsProvider>();
    final s = prov.settings;
    if (!s.appLockEnabled || s.appLockHash == null) {
      await _toggleLock(true);
      if (!mounted) return;
      final after = context.read<SettingsProvider>().settings;
      if (!after.appLockEnabled) return;
      await _update(after.copyWith(lockScope: scope));
    } else {
      await _update(s.copyWith(lockScope: scope));
    }
  }

  Future<(String, String)?> _askPins(String title) async {
    final pin1 = TextEditingController();
    final pin2 = TextEditingController();
    final pins = await showDialog<(String, String)?>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pin1,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: '4-digit PIN'),
            ),
            TextField(
              controller: pin2,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Repeat PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(c)
                  .pop((pin1.text.trim(), pin2.text.trim())),
              child: const Text('Set PIN')),
        ],
      ),
    );
    pin1.dispose();
    pin2.dispose();
    if (pins == null || !mounted) return null;
    if (pins.$1 != pins.$2) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PINs do not match.')));
      return null;
    }
    return pins;
  }

  Future<void> _changePin() async {
    if (_busy) return;
    final pins = await _askPins('Change PIN');
    if (pins == null || !mounted) return;
    final prov = context.read<SettingsProvider>();
    setState(() => _busy = true);
    try {
      final ok = await prov.setAppLock(enabled: true, pin: pins.$1);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? 'PIN changed ✓'
              : (prov.error ?? 'Could not update.'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleLock(bool enabled) async {
    if (_busy) return;
    final prov = context.read<SettingsProvider>();
    if (!enabled) {
      setState(() => _busy = true);
      try {
        final ok = await prov.setAppLock(enabled: false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ok
                ? 'App lock removed.'
                : (prov.error ?? 'Could not update.'))));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    final pins = await _askPins('Set app PIN');
    if (pins == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final ok = await prov.setAppLock(enabled: true, pin: pins.$1);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? 'App lock enabled ✓'
              : (prov.error ?? 'Could not update.'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SettingsProvider>();
    final s = prov.settings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy lock'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/settings'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Protect', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'off', label: Text('Off')),
                ButtonSegment(
                    value: 'sections', label: Text('Sections')),
                ButtonSegment(
                    value: 'full', label: Text('Entire app')),
              ],
              selected: {
                s.appLockEnabled ? s.lockScope : 'off'
              },
              onSelectionChanged: _busy
                  ? null
                  : (sel) => _setScope(sel.first),
            ),
          ),
          if (s.appLockEnabled) ...[
            const SizedBox(height: 12),
            Text('Lock timing',
                style: theme.textTheme.titleSmall),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in const [
                  (0, 'Immediately'),
                  (1, 'After 1 min'),
                  (5, 'After 5 min'),
                ])
                  ChoiceChip(
                    label: Text(entry.$2),
                    selected:
                        s.lockTimeoutMin == entry.$1,
                    onSelected: _busy
                        ? null
                        : (_) => _update(s.copyWith(
                            lockTimeoutMin: entry.$1)),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Lock when app leaves foreground'),
              value: s.lockOnBackground,
              onChanged: _busy
                  ? null
                  : (v) => _update(
                      s.copyWith(lockOnBackground: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow screenshots'),
              subtitle: const Text(
                  'When off, screenshots and screen recorders are blocked.'),
              value: s.allowScreenshots,
              onChanged: _busy
                  ? null
                  : (v) => _update(s.copyWith(allowScreenshots: v)),
            ),
            if (s.lockScope == 'sections') ...[
              Text('Protected sections',
                  style: theme.textTheme.titleSmall),
              for (final screen in const [
                ('journal', 'Journal'),
                ('snapshot', 'Health snapshot'),
                ('timeline', 'Medical timeline'),
                ('reminders', 'Reminders & meds'),
                ('reports', 'Reports'),
              ])
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(screen.$2),
                  value:
                      s.protectedScreens.contains(screen.$1),
                  onChanged: _busy
                      ? null
                      : (v) {
                          final next = [
                            ...s.protectedScreens
                          ];
                          if (v == true) {
                            if (!next.contains(screen.$1)) {
                              next.add(screen.$1);
                            }
                          } else {
                            next.remove(screen.$1);
                          }
                          _update(s.copyWith(
                              protectedScreens: next));
                        },
                ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Biometric unlock'),
              subtitle: Text(prov.biometricAvailable
                  ? 'Fingerprint / face where supported, PIN fallback always available'
                  : 'No biometric sensor found — PIN only'),
              value:
                  s.biometricEnabled && prov.biometricAvailable,
              onChanged: (prov.biometricAvailable && !_busy)
                  ? (v) =>
                      _update(s.copyWith(biometricEnabled: v))
                  : null,
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _changePin,
                    child: const Text('Change PIN'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _busy ? null : () => _toggleLock(false),
                    child: Text('Remove lock',
                        style:
                            TextStyle(color: scheme.error)),
                  ),
                ),
              ],
            ),
            Text(
              'Only a hash of your PIN is stored — never the PIN itself. Locks reset when the app restarts; wrong attempts never lock you out.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant),
            ),
          ] else
            Text(
              'Optional: protect sensitive sections or the entire app with biometrics / PIN. No account needed.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
