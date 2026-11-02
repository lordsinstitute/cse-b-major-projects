import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/providers/settings_provider.dart';

/// Generic privacy-lock gate: when [screen] is protected and this session
/// is locked, a PIN pad (plus biometrics when enabled) guards [child].
/// Set [fullApp] for the whole-application gate. Nothing behind it builds
/// unlocked. Failed attempts never lock the user out.
class PinGate extends StatefulWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final String screen;
  final bool fullApp;
  const PinGate(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.child,
      this.screen = 'journal',
      this.fullApp = false});

  @override
  State<PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<PinGate> {
  String _pin = '';
  bool _wrong = false;

  void _press(String d) {
    final settings = context.read<SettingsProvider>();
    final next = (_pin + d).length > 4 ? _pin : _pin + d;
    setState(() {
      _pin = next;
      _wrong = false;
    });
    if (next.length == 4) {
      final ok = settings.unlockJournal(next);
      setState(() {
        _wrong = !ok;
        if (!ok) _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final locked = widget.fullApp
        ? settings.appGateLocked
        : settings.protects(widget.screen) &&
            !settings.journalUnlocked;
    if (!locked) {
      return widget.child;
    }
    final theme = Theme.of(context);
    final showBiometrics = settings.settings.biometricEnabled &&
        settings.biometricAvailable;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline,
              size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(widget.title, style: theme.textTheme.titleLarge),
          Text(widget.subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center),
          if (showBiometrics) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () =>
                  settings.authenticateBiometric(),
              icon: const Icon(Icons.fingerprint),
              label: const Text('Use biometrics'),
            ),
            Text('or enter PIN',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 4; i++)
                Container(
                  width: 16,
                  height: 16,
                  margin:
                      const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
            ],
          ),
          if (_wrong) ...[
            const SizedBox(height: 8),
            Text(
                settings.failedAttempts <= 1
                    ? 'Wrong PIN. Try again — nothing is locked.'
                    : 'Wrong PIN (${settings.failedAttempts} tries). Keep trying — nothing is locked.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
                textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),
          for (final row in [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['', '0', '⌫'],
          ])
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final d in row)
                  SizedBox(
                    width: 72,
                    height: 64,
                    child: d.isEmpty
                        ? const SizedBox.shrink()
                        : TextButton(
                            onPressed: () => d == '⌫'
                                ? setState(() => _pin = _pin.isEmpty
                                    ? ''
                                    : _pin.substring(
                                        0, _pin.length - 1))
                                : _press(d),
                            child: Text(d,
                                style: theme
                                    .textTheme.headlineSmall),
                          ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
