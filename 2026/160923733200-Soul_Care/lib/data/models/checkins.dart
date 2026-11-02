/// Optional daily intentions (plus free-text custom).
const List<String> intentionOptions = [
  'Move more',
  'Stay hydrated',
  'Stay focused',
  'Reduce stress',
  'Sleep on time',
  'Be consistent',
];

/// One fast morning check-in per date (keyed by yyyy-MM-dd).
class MorningCheckIn {
  final String date;
  final double sleepHours;
  final int rested; // 1–5
  final int mood; // 1–5
  final int energy; // 1–5
  final String? intention; // preset or custom, optional
  final DateTime updatedAt;

  const MorningCheckIn({
    required this.date,
    this.sleepHours = 0,
    this.rested = 3,
    this.mood = 3,
    this.energy = 3,
    this.intention,
    required this.updatedAt,
  });

  MorningCheckIn copyWith({
    double? sleepHours,
    int? rested,
    int? mood,
    int? energy,
    String? Function()? intention,
    DateTime? updatedAt,
  }) {
    return MorningCheckIn(
      date: date,
      sleepHours: sleepHours ?? this.sleepHours,
      rested: rested ?? this.rested,
      mood: mood ?? this.mood,
      energy: energy ?? this.energy,
      intention: intention != null ? intention() : this.intention,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'sleepHours': sleepHours,
        'rested': rested,
        'mood': mood,
        'energy': energy,
        'intention': intention,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory MorningCheckIn.fromJson(Map<String, dynamic> json) {
    return MorningCheckIn(
      date: json['date'] as String,
      sleepHours: (json['sleepHours'] as num?)?.toDouble() ?? 0,
      rested: (json['rested'] as num?)?.toInt().clamp(1, 5) ?? 3,
      mood: (json['mood'] as num?)?.toInt().clamp(1, 5) ?? 3,
      energy: (json['energy'] as num?)?.toInt().clamp(1, 5) ?? 3,
      intention: (json['intention'] as String?)?.trim().isEmpty == true
          ? null
          : (json['intention'] as String?)?.trim(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// One evening reflection per date (keyed by yyyy-MM-dd), editable.
class EveningReflection {
  final String date;
  final int mood; // 1–5
  final int energy; // 1–5
  final int stress; // 1 calm – 5 high
  final String? wentWell;
  final String? improve;
  final DateTime updatedAt;

  const EveningReflection({
    required this.date,
    this.mood = 3,
    this.energy = 3,
    this.stress = 3,
    this.wentWell,
    this.improve,
    required this.updatedAt,
  });

  EveningReflection copyWith({
    int? mood,
    int? energy,
    int? stress,
    String? Function()? wentWell,
    String? Function()? improve,
    DateTime? updatedAt,
  }) {
    return EveningReflection(
      date: date,
      mood: mood ?? this.mood,
      energy: energy ?? this.energy,
      stress: stress ?? this.stress,
      wentWell: wentWell != null ? wentWell() : this.wentWell,
      improve: improve != null ? improve() : this.improve,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'mood': mood,
        'energy': energy,
        'stress': stress,
        'wentWell': wentWell,
        'improve': improve,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory EveningReflection.fromJson(Map<String, dynamic> json) {
    String? clean(String? key) => switch ((json[key] as String?)?.trim()) {
          '' || null => null,
          final t => t,
        };

    return EveningReflection(
      date: json['date'] as String,
      mood: (json['mood'] as num?)?.toInt().clamp(1, 5) ?? 3,
      energy: (json['energy'] as num?)?.toInt().clamp(1, 5) ?? 3,
      stress: (json['stress'] as num?)?.toInt().clamp(1, 5) ?? 3,
      wentWell: clean('wentWell'),
      improve: clean('improve'),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
