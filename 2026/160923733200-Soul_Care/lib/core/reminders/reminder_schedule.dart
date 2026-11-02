import '../../data/models/reminders.dart';

/// One scheduled occurrence (pure data — no platform calls).
class DoseOccurrence {
  final String reminderId;
  final String medicationName;
  final DateTime at;

  const DoseOccurrence({
    required this.reminderId,
    required this.medicationName,
    required this.at,
  });

  String get dateKey =>
      '${at.year.toString().padLeft(4, '0')}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
  String get timeKey =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}

/// Deterministic notification id from any string key. Stable across
/// restarts so re-scheduling replaces (never duplicates) alerts.
int notificationIdFor(String key) {
  var hash = 0xcbf29ce484222325;
  for (var i = 0; i < key.length; i++) {
    hash ^= key.codeUnitAt(i);
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return (hash & 0x7fffffff).toInt();
}

/// Pure occurrence computation. Testable without Android.
///
/// Rules: disabled reminders and empty time lists yield nothing; weekday
/// subsets filter days; start/end bound the window; past occurrences are
/// excluded ([from] is "now"); output capped at [maxDays] and sorted.
List<DoseOccurrence> medicationOccurrences({
  required MedicationReminder reminder,
  required DateTime from,
  int maxDays = 14,
}) {
  if (!reminder.enabled || reminder.times.isEmpty) return const [];
  final out = <DoseOccurrence>[];
  final day0 = DateTime(from.year, from.month, from.day);
  for (var d = 0; d < maxDays; d++) {
    final day = day0.add(Duration(days: d));
    if (reminder.days.isNotEmpty && !reminder.days.contains(day.weekday)) {
      continue;
    }
    if (reminder.startDate != null) {
      final s = reminder.startDate!;
      if (day.isBefore(DateTime(s.year, s.month, s.day))) continue;
    }
    if (reminder.endDate != null) {
      final e = reminder.endDate!;
      if (day.isAfter(DateTime(e.year, e.month, e.day))) continue;
    }
    for (final t in reminder.times) {
      final parts = t.split(':');
      final at = DateTime(
          day.year, day.month, day.day, int.parse(parts[0]), int.parse(parts[1]));
      if (!at.isAfter(from)) continue; // expired moments are skipped
      out.add(DoseOccurrence(
          reminderId: reminder.id,
          medicationName: reminder.medicationName,
          at: at));
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// Appointment alert moment, or null when disabled/past/no-reminder.
DateTime? appointmentAlertAt(Appointment appt, DateTime now) {
  if (!appt.enabled) return null;
  final at = appt.remindAt;
  if (at == null || !at.isAfter(now)) return null;
  return at;
}
