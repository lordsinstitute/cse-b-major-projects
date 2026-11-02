import 'package:flutter/material.dart';

import '../../core/notifications/notification_service.dart';
import '../../core/reminders/reminder_schedule.dart';
import '../../core/utils/utils.dart';
import '../../data/models/reminders.dart';
import '../../data/repositories/reminders_repository.dart';

/// One row in the calendar-like upcoming view.
class UpcomingItem {
  final DateTime at;
  final String title;
  final String subtitle;
  final bool isAppointment;
  final String refId;

  const UpcomingItem({
    required this.at,
    required this.title,
    required this.subtitle,
    required this.isAppointment,
    required this.refId,
  });
}

/// One history row: logged taken/skipped, or neutral "no record".
class HistoryItem {
  final DoseOccurrence occurrence;
  final DoseAction? action;

  const HistoryItem({required this.occurrence, required this.action});

  String get statusLabel =>
      action == null ? 'No record' : action!.name;
}

/// Medication reminders + appointments + dose history, all local.
/// Scheduling calls are fire-and-forget safe (never throw into UI).
class RemindersProvider extends ChangeNotifier {
  final MedReminderRepository _meds;
  final AppointmentRepository _appts;
  final DoseLogRepository _logs;

  List<MedicationReminder> _reminders = [];
  List<Appointment> _appointments = [];
  List<DoseLog> _doseLogs = [];
  bool _loading = false;
  String? _error;

  RemindersProvider({
    MedReminderRepository? meds,
    AppointmentRepository? appointments,
    DoseLogRepository? logs,
  })  : _meds = meds ?? MedReminderRepository(),
        _appts = appointments ?? AppointmentRepository(),
        _logs = logs ?? DoseLogRepository();

  List<MedicationReminder> get reminders =>
      List.unmodifiable(_reminders);
  List<Appointment> get appointments =>
      List.unmodifiable(_appointments);
  bool get loading => _loading;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    final r = await _meds.getAll();
    final a = await _appts.getAll();
    final l = await _logs.getAll();
    r.fold(onSuccess: (v) => _reminders = v,
        onFailure: (e) => _error = e.message);
    a.fold(onSuccess: (v) => _appointments = v, onFailure: (_) {});
    l.fold(onSuccess: (v) => _doseLogs = v, onFailure: (_) {});
    _loading = false;
    notifyListeners();
  }

  Future<bool> saveReminder(MedicationReminder r) async {
    final res = await _meds.save(r);
    return res.fold(
      onSuccess: (saved) {
        final i = _reminders.indexWhere((e) => e.id == saved.id);
        if (i >= 0) {
          _reminders[i] = saved;
        } else {
          _reminders = [..._reminders, saved];
        }
        _error = null;
        notifyListeners();
        NotificationService.cancelMedication(saved);
        if (saved.enabled) {
          NotificationService.scheduleMedication(saved);
        }
        return true;
      },
      onFailure: (e) {
        _error = e.message;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> removeReminder(String id) async {
    final existing = _reminders.where((e) => e.id == id).toList();
    final res = await _meds.delete(id);
    return res.fold(
      onSuccess: (_) {
        _reminders.removeWhere((e) => e.id == id);
        notifyListeners();
        if (existing.isNotEmpty) {
          NotificationService.cancelMedication(existing.first);
        }
        return true;
      },
      onFailure: (e) {
        _error = e.message;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> saveAppointment(Appointment a) async {
    final res = await _appts.save(a);
    return res.fold(
      onSuccess: (saved) {
        final i = _appointments.indexWhere((e) => e.id == saved.id);
        if (i >= 0) {
          _appointments[i] = saved;
        } else {
          _appointments = [..._appointments, saved];
        }
        _error = null;
        notifyListeners();
        NotificationService.cancelAppointment(saved.id);
        if (saved.enabled) {
          NotificationService.scheduleAppointment(saved);
        }
        return true;
      },
      onFailure: (e) {
        _error = e.message;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> removeAppointment(String id) async {
    final res = await _appts.delete(id);
    return res.fold(
      onSuccess: (_) {
        _appointments.removeWhere((e) => e.id == id);
        notifyListeners();
        NotificationService.cancelAppointment(id);
        return true;
      },
      onFailure: (e) {
        _error = e.message;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> logDose(
      String reminderId, String date, String time, DoseAction action) async {
    final res = await _logs.save(DoseLog(
      reminderId: reminderId,
      date: date,
      time: time,
      action: action,
      loggedAt: DateTime.now(),
    ));
    return res.fold(
      onSuccess: (log) {
        _doseLogs.removeWhere((e) => e.key == log.key);
        _doseLogs = [..._doseLogs, log];
        notifyListeners();
        return true;
      },
      onFailure: (e) {
        _error = e.message;
        notifyListeners();
        return false;
      },
    );
  }

  /// Next 14 days merged + sorted (meds + future appointments).
  List<UpcomingItem> upcoming({int maxDays = 14}) {
    final now = DateTime.now();
    final out = <UpcomingItem>[];
    for (final r in _reminders) {
      for (final o in medicationOccurrences(
          reminder: r, from: now, maxDays: maxDays)) {
        out.add(UpcomingItem(
          at: o.at,
          title: o.medicationName,
          subtitle:
              '${o.timeKey} · ${r.frequency}${r.enabled ? '' : ' · paused'}',
          isAppointment: false,
          refId: r.id,
        ));
      }
    }
    for (final a in _appointments) {
      if (!a.enabled || !a.dateTime.isAfter(now)) continue;
      if (a.dateTime.difference(now).inDays > maxDays) continue;
      out.add(UpcomingItem(
        at: a.dateTime,
        title: a.title,
        subtitle:
            '${a.location.isEmpty ? 'Appointment' : a.location}${a.provider.isNotEmpty ? ' · ${a.provider}' : ''}',
        isAppointment: true,
        refId: a.id,
      ));
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  /// Last 7 days of scheduled doses joined with logs.
  /// Missing logs read "No record" — neutral wording, never a judgment.
  List<HistoryItem> recentHistory() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    final byKey = {for (final l in _doseLogs) l.key: l.action};
    final out = <HistoryItem>[];
    for (final r in _reminders) {
      DateTime cursor = start;
      while (!cursor.isAfter(now)) {
        if (r.days.isEmpty || r.days.contains(cursor.weekday)) {
          if (_inWindow(r, cursor)) {
            for (final t in r.times) {
              final at = _at(cursor, t);
              if (at == null || !at.isBefore(now)) continue;
              final key =
                  '${r.id}|${_dayKey(cursor)}|$t';
              out.add(HistoryItem(
                occurrence: DoseOccurrence(
                    reminderId: r.id,
                    medicationName: r.medicationName,
                    at: at),
                action: byKey[key],
              ));
            }
          }
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    out.sort((a, b) => b.occurrence.at.compareTo(a.occurrence.at));
    return out;
  }

  bool _inWindow(MedicationReminder r, DateTime day) {
    if (r.startDate != null) {
      final s = r.startDate!;
      if (day.isBefore(DateTime(s.year, s.month, s.day))) {
        return false;
      }
    }
    if (r.endDate != null) {
      final e = r.endDate!;
      if (day.isAfter(DateTime(e.year, e.month, e.day))) return false;
    }
    return true;
  }

  DateTime? _at(DateTime day, String time) {
    final parts = time.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return DateTime(day.year, day.month, day.day, h, m);
  }

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static MedicationReminder blankReminder() {
    final now = DateTime.now();
    return MedicationReminder(
      id: generateId(),
      medicationName: '',
      times: const ['08:00'],
      createdAt: now,
      updatedAt: now,
    );
  }

  static Appointment blankAppointment() {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    return Appointment(
      id: generateId(),
      title: '',
      date: day,
      createdAt: now,
      updatedAt: now,
    );
  }
}
