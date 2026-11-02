import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/providers/settings_provider.dart';
import '../../core/notifications/notification_service.dart';
import '../../data/models/models.dart';

/// /settings/notifications — daily + experiment reminders, on-device only.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
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

  Future<void> _toggleDaily(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final settings = context.read<SettingsProvider>().settings;
      if (enabled) {
        await NotificationService.init();
        final granted =
            await NotificationService.requestPermission();
        if (!mounted) return;
        if (!granted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Notification permission is needed for reminders. Your setting was left off.')));
          return;
        }
        final time = NotificationService.parseReminderTime(
                settings.dailyReminderTime) ??
            const TimeOfDay(hour: 20, minute: 0);
        await NotificationService.scheduleDailyReminder(time);
        if (!mounted) return;
        await _update(settings.copyWith(
          notificationsEnabled: true,
          dailyReminderTime:
              NotificationService.formatReminderTime(time),
        ));
      } else {
        await NotificationService.cancelDailyReminder();
        if (!mounted) return;
        await _update(
            settings.copyWith(notificationsEnabled: false));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickTime() async {
    final settings = context.read<SettingsProvider>().settings;
    final current = NotificationService.parseReminderTime(
            settings.dailyReminderTime) ??
        const TimeOfDay(hour: 20, minute: 0);
    final picked = await showTimePicker(
        context: context, initialTime: current);
    if (picked == null || !mounted) return;
    await NotificationService.scheduleDailyReminder(picked);
    if (!mounted) return;
    await _update(
      settings.copyWith(
        notificationsEnabled: true,
        dailyReminderTime:
            NotificationService.formatReminderTime(picked),
      ),
      okMessage: 'Daily reminder set ✓',
    );
  }

  Future<void> _toggleExperiments(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final settings = context.read<SettingsProvider>().settings;
      if (enabled) {
        await NotificationService.init();
        final granted =
            await NotificationService.requestPermission();
        if (!mounted) return;
        if (!granted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Notification permission is needed for reminders. Your setting was left off.')));
          return;
        }
        await NotificationService.scheduleExperimentReminder();
        if (!mounted) return;
        await _update(
            settings.copyWith(experimentRemindersEnabled: true));
      } else {
        await NotificationService.cancelExperimentReminder();
        if (!mounted) return;
        await _update(
            settings.copyWith(experimentRemindersEnabled: false));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().settings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reminderTime = NotificationService.parseReminderTime(
            s.dailyReminderTime) ??
        const TimeOfDay(hour: 20, minute: 0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/settings'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable daily reminder'),
            subtitle: Text(
                'Local notification at ${reminderTime.format(context)}',
                style: theme.textTheme.bodySmall),
            value: s.notificationsEnabled,
            onChanged: _busy ? null : _toggleDaily,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reminder time'),
            trailing: Text(reminderTime.format(context),
                style: theme.textTheme.titleSmall),
            onTap: _busy ? null : _pickTime,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Experiment reminders'),
            subtitle: const Text('Evening Lab check-in nudge'),
            value: s.experimentRemindersEnabled,
            onChanged: _busy ? null : _toggleExperiments,
          ),
          Text(
            'Reminders are scheduled on this device only — no accounts, no Firebase Cloud Messaging.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
