/// Fixed blood-group options (plus unknown / prefer-not-to-say).
const List<String> bloodGroups = [
  'Unknown',
  'O+',
  'O-',
  'A+',
  'A-',
  'B+',
  'B-',
  'AB+',
  'AB-',
  'Prefer not to say',
];

const List<String> allergySeverities = ['Mild', 'Moderate', 'Severe'];

/// One allergy record: what, how bad, optional notes.
class AllergyRecord {
  final String name;
  final String severity;
  final String? notes;

  const AllergyRecord(
      {required this.name, this.severity = 'Mild', this.notes});

  Map<String, dynamic> toJson() => {
        'name': name,
        'severity': severity,
        'notes': notes,
      };

  factory AllergyRecord.fromJson(Map<String, dynamic> json) {
    final sev = json['severity'] as String?;
    return AllergyRecord(
      name: (json['name'] as String?)?.trim() ?? '',
      severity: allergySeverities.contains(sev) ? sev! : 'Mild',
      notes: (json['notes'] as String?)?.trim().isEmpty == true
          ? null
          : (json['notes'] as String?)?.trim(),
    );
  }
}

/// One medication record. Informational only — never advice.
class MedicationRecord {
  final String name;
  final String dosage;
  final String frequency;
  final String? notes;
  final DateTime? startDate;
  final DateTime? endDate;

  const MedicationRecord({
    required this.name,
    this.dosage = '',
    this.frequency = '',
    this.notes,
    this.startDate,
    this.endDate,
  });

  /// Active means no end date, or an end date in the future.
  bool get isActive {
    if (endDate == null) return true;
    final now = DateTime.now();
    final end = DateTime(endDate!.year, endDate!.month, endDate!.day);
    final today = DateTime(now.year, now.month, now.day);
    return !end.isBefore(today);
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'dosage': dosage,
        'frequency': frequency,
        'notes': notes,
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
      };

  factory MedicationRecord.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String key) {
      final v = json[key] as String?;
      return v == null ? null : DateTime.tryParse(v);
    }

    return MedicationRecord(
      name: (json['name'] as String?)?.trim() ?? '',
      dosage: (json['dosage'] as String?)?.trim() ?? '',
      frequency: (json['frequency'] as String?)?.trim() ?? '',
      notes: (json['notes'] as String?)?.trim().isEmpty == true
          ? null
          : (json['notes'] as String?)?.trim(),
      startDate: parse('startDate'),
      endDate: parse('endDate'),
    );
  }
}

/// Manually maintained personal health snapshot. Sensitive by nature:
/// local-only, never logged, never uploaded, lock-gated like the journal.
class HealthSnapshot {
  final String? bloodGroup;
  final List<AllergyRecord> allergies;
  final List<MedicationRecord> medications;
  final List<String> supplements;
  final List<String> conditions;
  final String? emergencyName;
  final String? emergencyPhone;
  final String? provider;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const HealthSnapshot({
    this.bloodGroup,
    this.allergies = const [],
    this.medications = const [],
    this.supplements = const [],
    this.conditions = const [],
    this.emergencyName,
    this.emergencyPhone,
    this.provider,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory HealthSnapshot.empty() {
    final now = DateTime.now();
    return HealthSnapshot(createdAt: now, updatedAt: now);
  }

  bool get isEmpty =>
      (bloodGroup == null ||
          bloodGroup == 'Unknown' ||
          bloodGroup == 'Prefer not to say') &&
      allergies.isEmpty &&
      medications.isEmpty &&
      supplements.isEmpty &&
      conditions.isEmpty &&
      (emergencyName == null || emergencyName!.isEmpty) &&
      (provider == null || provider!.isEmpty) &&
      (notes == null || notes!.isEmpty);

  int get activeMedications =>
      medications.where((m) => m.isActive).length;

  bool get hasEmergencyContact =>
      (emergencyName != null && emergencyName!.isNotEmpty) ||
      (emergencyPhone != null && emergencyPhone!.isNotEmpty);

  HealthSnapshot copyWith({
    String? Function()? bloodGroup,
    List<AllergyRecord>? allergies,
    List<MedicationRecord>? medications,
    List<String>? supplements,
    List<String>? conditions,
    String? Function()? emergencyName,
    String? Function()? emergencyPhone,
    String? Function()? provider,
    String? Function()? notes,
    DateTime? updatedAt,
  }) {
    return HealthSnapshot(
      bloodGroup:
          bloodGroup != null ? bloodGroup() : this.bloodGroup,
      allergies: allergies ?? this.allergies,
      medications: medications ?? this.medications,
      supplements: supplements ?? this.supplements,
      conditions: conditions ?? this.conditions,
      emergencyName: emergencyName != null
          ? emergencyName()
          : this.emergencyName,
      emergencyPhone: emergencyPhone != null
          ? emergencyPhone()
          : this.emergencyPhone,
      provider:
          provider != null ? provider() : this.provider,
      notes: notes != null ? notes() : this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'bloodGroup': bloodGroup,
        'allergies': [for (final a in allergies) a.toJson()],
        'medications': [for (final m in medications) m.toJson()],
        'supplements': supplements,
        'conditions': conditions,
        'emergencyName': emergencyName,
        'emergencyPhone': emergencyPhone,
        'provider': provider,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory HealthSnapshot.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) =>
        (json[key] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList() ??
        const [];
    String? clean(String key) {
      final v = json[key] as String?;
      return v == null || v.trim().isEmpty ? null : v.trim();
    }

    DateTime parse(String key, DateTime fallback) =>
        DateTime.tryParse(json[key] as String? ?? '') ?? fallback;
    final now = DateTime.now();
    return HealthSnapshot(
      bloodGroup: clean('bloodGroup'),
      allergies: (json['allergies'] as List?)
              ?.map((e) => AllergyRecord.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .where((a) => a.name.isNotEmpty)
              .toList() ??
          const [],
      medications: (json['medications'] as List?)
              ?.map((e) => MedicationRecord.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .where((m) => m.name.isNotEmpty)
              .toList() ??
          const [],
      supplements: strings('supplements'),
      conditions: strings('conditions'),
      emergencyName: clean('emergencyName'),
      emergencyPhone: clean('emergencyPhone'),
      provider: clean('provider'),
      notes: clean('notes'),
      createdAt: parse('createdAt', now),
      updatedAt: parse('updatedAt', now),
    );
  }
}
