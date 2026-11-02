import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/providers/health_import_provider.dart';

/// /settings/health — optional platform health-data integration.
/// Read-only, explicit, local. Everything keeps working when denied.
class HealthDataScreen extends StatefulWidget {
  const HealthDataScreen({super.key});

  @override
  State<HealthDataScreen> createState() => _HealthDataScreenState();
}

class _HealthDataScreenState extends State<HealthDataScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HealthImportProvider>().refresh();
    });
  }

  Future<void> _connect() async {
    final ok =
        await context.read<HealthImportProvider>().connect();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Health data connected ✓'
            : (context.read<HealthImportProvider>().error ??
                'Could not connect.'))));
  }

  Future<void> _disconnect() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Disconnect health data?'),
        content: const Text(
            'Platform permission is revoked and imported copies are removed from this device. Your manual logs are never touched.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Disconnect')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await context.read<HealthImportProvider>().disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final link = context.watch<HealthImportProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusText = switch (link.status) {
      HealthLinkStatus.connected =>
        'Connected${link.lastSync == null ? '' : ' · synced ${_fmtTime(link.lastSync!)}'} · ${link.totalPoints} records',
      HealthLinkStatus.denied => 'Permission not granted',
      HealthLinkStatus.unsupported =>
        'Health data integration is unavailable on this device.',
      HealthLinkStatus.unknown => 'Not connected',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health data'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/settings'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Icon(Icons.favorite_outline,
                  color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(statusText,
                    style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Optional read-only access to sleep, steps, exercise, and heart rate from your device health store. Manual logging always works.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              if (link.status != HealthLinkStatus.connected)
                FilledButton.tonal(
                  onPressed: link.busy ? null : _connect,
                  child: Text(link.busy
                      ? 'Working…'
                      : 'Connect Health Data'),
                )
              else ...[
                OutlinedButton(
                  onPressed: link.busy ? null : () => link.sync(),
                  child: const Text('Sync now'),
                ),
                TextButton(
                  onPressed: link.busy ? null : _disconnect,
                  child: Text('Disconnect',
                      style: TextStyle(color: scheme.error)),
                ),
              ],
            ],
          ),
          if (link.error != null) ...[
            const SizedBox(height: 4),
            Text(link.error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.error)),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static String _fmtTime(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
