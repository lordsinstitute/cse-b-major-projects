import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/reminders/reminder_schedule.dart';
import '../../data/models/reminders.dart';
import '../../data/repositories/reminders_repository.dart';

/// Android-only local notifications. No Firebase Cloud Messaging,
/// no network — everything is scheduled and delivered on-device.
class NotificationService {
  static const int dailyReminderId = 100;
  static const int experimentReminderId = 101;
  static const String channelId = 'soulcare_reminders';
  static const String channelName = 'Reminders';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;
  static Future<void> Function(String actionId, Map<String, String> data)?
      _externalHandler;

  /// Optional hook for dose responses (used by tests/UI layers).
  /// The built-in handler records dose logs locally by default.
  static void setResponseHandler(
      Future<void> Function(String actionId, Map<String, String> data)?
          handler) {
    _externalHandler = handler;
  }

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
        settings: const InitializationSettings(
      android: android,
    ), onDidReceiveNotificationResponse: _onResponse);
    _ready = true;
  }

  /// Returns true when notifications may be posted.
  static Future<bool> requestPermission() async {
    try {
      final android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return false;
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> scheduleDailyReminder(TimeOfDay time) async {
    await init();
    await _plugin.zonedSchedule(
      id: dailyReminderId,
      title: 'SoulCare daily check-in',
      body: 'A minute for yourself — log today’s wellness.',
      scheduledDate: _nextDaily(time),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> cancelDailyReminder() async {
    try {
      await _plugin.cancel(id: dailyReminderId);
    } catch (_) {}
  }

  static Future<void> scheduleExperimentReminder() async {
    await init();
    await _plugin.zonedSchedule(
      id: experimentReminderId,
      title: 'Lab check-in',
      body: 'How did today’s experiment go? Log DONE or MISSED.',
      scheduledDate: _nextDaily(const TimeOfDay(hour: 20, minute: 0)),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> cancelExperimentReminder() async {
    try {
      await _plugin.cancel(id: experimentReminderId);
    } catch (_) {}
  }

  /// Next occurrence of a wall-clock time strictly after [now].
  @visibleForTesting
  static tz.TZDateTime nextDailyOccurrence(
      DateTime now, TimeOfDay time) {
    var scheduled = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  static tz.TZDateTime _nextDaily(TimeOfDay time) =>
      nextDailyOccurrence(DateTime.now(), time);

  /// Parses 'HH:mm' (24h). Returns null when malformed.
  static TimeOfDay? parseReminderTime(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return TimeOfDay(hour: h, minute: m);
  }

  static String formatReminderTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // ---------- Medication & appointment scheduling (local only) ----------

  static const List<AndroidNotificationAction> _doseActions =
      [
    AndroidNotificationAction('taken', 'Taken'),
    AndroidNotificationAction('skipped', 'Skip'),
    AndroidNotificationAction('snooze', 'Snooze'),
  ];

  static String _dosePayload(DoseOccurrence o) => jsonEncode({
        'kind': 'dose',
        'reminderId': o.reminderId,
        'name': o.medicationName,
        'date': o.dateKey,
        'time': o.timeKey,
      });

  static NotificationDetails _doseDetails() =>
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          actions: _doseActions,
        ),
      );

  /// Schedules the next [maxDays] of occurrences. Deterministic ids mean
  /// re-scheduling replaces rather than duplicates alerts.
  static Future<void> scheduleMedication(MedicationReminder reminder,
      {int maxDays = 14}) async {
    try {
      await init();
      final now = DateTime.now();
      for (final o in medicationOccurrences(
          reminder: reminder, from: now, maxDays: maxDays)) {
        await _plugin.zonedSchedule(
          id: notificationIdFor(
              '${reminder.id}|${o.dateKey}|${o.timeKey}'),
          title: 'Medication reminder',
          body: o.medicationName,
          scheduledDate: tz.TZDateTime.from(o.at, tz.local),
          notificationDetails: _doseDetails(),
          androidScheduleMode:
              AndroidScheduleMode.inexactAllowWhileIdle,
          payload: _dosePayload(o),
        );
      }
    } catch (_) {}
  }

  /// Cancels scheduled occurrences across a ±window (unknown ids are
  /// simply ignored by the plugin).
  static Future<void> cancelMedication(MedicationReminder reminder) async {
    try {
      await init();
      final now = DateTime.now();
      for (var d = -7; d < 30; d++) {
        final day = DateTime(now.year, now.month, now.day)
            .add(Duration(days: d));
        if (reminder.days.isNotEmpty &&
            !reminder.days.contains(day.weekday)) {
          continue;
        }
        for (final t in reminder.times) {
          await _plugin.cancel(
              id: notificationIdFor(
                  '${reminder.id}|${_dayKey(day)}|$t'));
        }
      }
    } catch (_) {}
  }

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<void> scheduleAppointment(Appointment appt) async {
    try {
      await init();
      final at = appointmentAlertAt(appt, DateTime.now());
      if (at == null) return;
      await _plugin.zonedSchedule(
        id: notificationIdFor('appt|${appt.id}'),
        title: 'Upcoming appointment',
        body:
            '${appt.title}${appt.location.isNotEmpty ? ' · ${appt.location}' : ''}',
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode:
            AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {}
  }

  static Future<void> cancelAppointment(String id) async {
    try {
      await _plugin.cancel(id: notificationIdFor('appt|$id'));
    } catch (_) {}
  }

  /// Rebuilds all medication + appointment alerts. Called on app start
  /// (covers reboot, clock changes, permission toggles) and after edits.
  /// Purely local; expired moments are never scheduled.
  static Future<void> rescheduleAll() async {
    try {
      await init();
      final meds = await MedReminderRepository().getAll();
      final appts = await AppointmentRepository().getAll();
      final reminders = meds.fold(
          onSuccess: (l) => l, onFailure: (_) => const []);
      final appointments = appts.fold(
          onSuccess: (l) => l, onFailure: (_) => const []);
      for (final r in reminders) {
        if (r is MedicationReminder) {
          await scheduleMedication(r);
        }
      }
      final now = DateTime.now();
      for (final a in appointments) {
        if (a is Appointment &&
            a.enabled &&
            a.dateTime.isAfter(now)) {
          await scheduleAppointment(a);
        }
      }
    } catch (_) {}
  }

  static void _onResponse(NotificationResponse response) {
    () async {
      try {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        final data = Map<String, String>.from(
            jsonDecode(payload) as Map);
        if (data['kind'] != 'dose') return;
        final actionId = response.actionId ?? '';
        final external = _externalHandler;
        if (external != null) {
          await external(actionId, data);
          return;
        }
        final reminderId = data['reminderId'] ?? '';
        final date = data['date'] ?? '';
        final time = data['time'] ?? '';
        if (reminderId.isEmpty || date.isEmpty || time.isEmpty) {
          return;
        }
        if (actionId == 'snooze') {
          await init();
          final at =
              DateTime.now().add(const Duration(minutes: 10));
          await _plugin.zonedSchedule(
            id: notificationIdFor(
                '$reminderId|$date|$time|snooze'),
            title: 'Medication reminder',
            body: data['name'] ?? 'Snoozed reminder',
            scheduledDate: tz.TZDateTime.from(at, tz.local),
            notificationDetails: _doseDetails(),
            androidScheduleMode:
                AndroidScheduleMode.inexactAllowWhileIdle,
            payload: jsonEncode(data),
          );
          return;
        }
        if (actionId == 'taken' || actionId == 'skipped') {
          await DoseLogRepository().save(DoseLog(
            reminderId: reminderId,
            date: date,
            time: time,
            action: actionId == 'taken'
                ? DoseAction.taken
                : DoseAction.skipped,
            loggedAt: DateTime.now(),
          ));
        }
      } catch (_) {}
    }();
  }
}
