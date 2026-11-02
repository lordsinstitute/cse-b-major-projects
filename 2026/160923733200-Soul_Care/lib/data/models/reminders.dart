/// Frequency label derived from times + days (no separate enum to
/// validate — the stored lists are the source of truth).
String frequencyLabel(List<String> times, List<int> days) {
  if (days.isNotEmpty && days.length < 7) return 'Selected weekdays';
  if (times.length >= 2) return 'Twice daily';
  return 'Daily';
}

/// One medication reminder: name, daily times, optional weekday subset,
/// optional active window, enabled flag. Entirely user-controlled.
class MedicationReminder {
  final String id;
  final String medicationName;
  final List<String> times; // HH:mm, 24h
  final List<int> days; // 1 Mon … 7 Sun; empty = every day
  final DateTime? startDate;
  final DateTime? endDate;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MedicationReminder({
    required this.id,
    required this.medicationName,
    this.times = const [],
    this.days = const [],
    this.startDate,
    this.endDate,
    this.enabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  String get frequency => frequencyLabel(times, days);

  MedicationReminder copyWith({
    String? medicationName,
    List<String>? times,
    List<int>? days,
    DateTime? Function()? startDate,
    DateTime? Function()? endDate,
    bool? enabled,
    DateTime? updatedAt,
  }) {
    return MedicationReminder(
      id: id,
      medicationName: medicationName ?? this.medicationName,
      times: times ?? this.times,
      days: days ?? this.days,
      startDate:
          startDate != null ? startDate() : this.startDate,
      endDate: endDate != null ? endDate() : this.endDate,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'medicationName': medicationName,
        'times': times,
        'days': days,
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'enabled': enabled,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory MedicationReminder.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String key) {
      final v = json[key] as String?;
      return v == null ? null : DateTime.tryParse(v);
    }

    return MedicationReminder(
      id: json['id'] as String,
      medicationName: (json['medicationName'] as String?)?.trim() ?? '',
      times: (json['times'] as List?)
              ?.map((e) => e.toString())
              .where(_validTime)
              .toList() ??
          const [],
      days: (json['days'] as List?)
              ?.map((e) => (e as num).toInt())
              .where((d) => d >= 1 && d <= 7)
              .toSet()
              .toList() ??
          const [],
      startDate: parse('startDate'),
      endDate: parse('endDate'),
      enabled: json['enabled'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static bool _validTime(String raw) {
    final parts = raw.split(':');
    if (parts.length != 2) return false;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    return h != null && m != null && h >= 0 && h <= 23 && m >= 0 && m <= 59;
  }
}

/// One healthcare appointment with an optional advance reminder.
class Appointment {
  final String id;
  final String title;
  final DateTime date; // day
  final String time; // HH:mm
  final String location;
  final String provider;
  final String notes;
  final int remindBeforeMin; // 0 = none
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Appointment({
    required this.id,
    required this.title,
    required this.date,
    this.time = '09:00',
    this.location = '',
    this.provider = '',
    this.notes = '',
    this.remindBeforeMin = 60,
    this.enabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  DateTime get dateTime {
    final parts = time.split(':');
    final h = int.tryParse(parts[0]) ?? 9;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(date.year, date.month, date.day, h, m);
  }

  DateTime? get remindAt => remindBeforeMin <= 0
      ? null
      : dateTime.subtract(Duration(minutes: remindBeforeMin));

  Appointment copyWith({
    String? title,
    DateTime? date,
    String? time,
    String? location,
    String? provider,
    String? notes,
    int? remindBeforeMin,
    bool? enabled,
    DateTime? updatedAt,
  }) {
    return Appointment(
      id: id,
      title: title ?? this.title,
      date: date ?? this.date,
      time: time ?? this.time,
      location: location ?? this.location,
      provider: provider ?? this.provider,
      notes: notes ?? this.notes,
      remindBeforeMin: remindBeforeMin ?? this.remindBeforeMin,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date': date.toIso8601String(),
        'time': time,
        'location': location,
        'provider': provider,
        'notes': notes,
        'remindBeforeMin': remindBeforeMin,
        'enabled': enabled,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Appointment.fromJson(Map<String, dynamic> json) {
    return Appointment(
      id: json['id'] as String,
      title: (json['title'] as String?)?.trim() ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ??
          DateTime.now(),
      time: (json['time'] as String?) ?? '09:00',
      location: (json['location'] as String?)?.trim() ?? '',
      provider: (json['provider'] as String?)?.trim() ?? '',
      notes: (json['notes'] as String?)?.trim() ?? '',
      remindBeforeMin:
          (json['remindBeforeMin'] as num?)?.toInt() ?? 60,
      enabled: json['enabled'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Dose actions. "missed" is never stored as a judgment — the history view
/// derives "no record" for scheduled doses without a log, worded neutrally.
enum DoseAction { taken, skipped }

/// One logged dose response (from notification action or in-app).
class DoseLog {
  final String reminderId;
  final String date; // yyyy-MM-dd
  final String time; // HH:mm
  final DoseAction action;
  final DateTime loggedAt;

  const DoseLog({
    required this.reminderId,
    required this.date,
    required this.time,
    required this.action,
    required this.loggedAt,
  });

  String get key => '$reminderId|$date|$time';

  Map<String, dynamic> toJson() => {
        'reminderId': reminderId,
        'date': date,
        'time': time,
        'action': action.name,
        'loggedAt': loggedAt.toIso8601String(),
      };

  factory DoseLog.fromJson(Map<String, dynamic> json) {
    return DoseLog(
      reminderId: json['reminderId'] as String,
      date: json['date'] as String,
      time: json['time'] as String,
      action: (json['action'] as String?) == 'skipped'
          ? DoseAction.skipped
          : DoseAction.taken,
      loggedAt: DateTime.tryParse(json['loggedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
