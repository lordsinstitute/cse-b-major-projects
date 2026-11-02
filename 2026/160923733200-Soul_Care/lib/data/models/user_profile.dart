/// What the user wants to focus on. Used ONLY to personalize suggestion
/// ordering and dashboard goal order — never to alter scoring.
enum WellnessFocus {
  betterSleep,
  moreMovement,
  energy,
  stressManagement,
  hydration,
  mindfulness,
  consistency,
  healthyEating,
  screenBalance,
  general,
}

extension WellnessFocusX on WellnessFocus {
  String get label {
    switch (this) {
      case WellnessFocus.betterSleep:
        return 'Better Sleep';
      case WellnessFocus.moreMovement:
        return 'More Movement';
      case WellnessFocus.energy:
        return 'Energy';
      case WellnessFocus.stressManagement:
        return 'Stress Management';
      case WellnessFocus.hydration:
        return 'Hydration';
      case WellnessFocus.mindfulness:
        return 'Mindfulness';
      case WellnessFocus.consistency:
        return 'Consistency';
      case WellnessFocus.healthyEating:
        return 'Healthy Eating';
      case WellnessFocus.screenBalance:
        return 'Balanced Screen Time';
      case WellnessFocus.general:
        return 'General Wellness';
    }
  }

  static WellnessFocus fromName(String? name) {
    switch (name) {
      case 'betterSleep':
        return WellnessFocus.betterSleep;
      case 'moreMovement':
        return WellnessFocus.moreMovement;
      case 'energy':
        return WellnessFocus.energy;
      case 'stressManagement':
        return WellnessFocus.stressManagement;
      case 'hydration':
        return WellnessFocus.hydration;
      case 'mindfulness':
        return WellnessFocus.mindfulness;
      case 'consistency':
        return WellnessFocus.consistency;
      case 'healthyEating':
        return WellnessFocus.healthyEating;
      case 'screenBalance':
        return WellnessFocus.screenBalance;
      case 'general':
      default:
        return WellnessFocus.general;
    }
  }
}

const List<String> ageRangeOptions = [
  'Under 18',
  '18–29',
  '30–39',
  '40–49',
  '50–59',
  '60+',
  'Prefer not to say',
];

/// Local personal profile. Every personal field is optional; goals carry
/// sensible defaults. `createdAt`/`updatedAt` track schema life;
/// `profileVersion` drives future migrations.
class UserProfile {
  static const int currentVersion = 1;

  final String? displayName;
  final String? ageRange;
  final int? exactAge;
  final String? wakeTime; // HH:mm
  final String? sleepTime; // HH:mm
  final double sleepGoal; // hours/night
  final int waterGoal; // glasses/day
  final int exerciseGoalWeek; // minutes/week
  final int meditationGoal; // minutes/day
  final String? reminderTime; // HH:mm
  final WellnessFocus primaryFocus;
  final WellnessFocus? secondaryFocus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int profileVersion;

  const UserProfile({
    this.displayName,
    this.ageRange,
    this.exactAge,
    this.wakeTime,
    this.sleepTime,
    this.sleepGoal = 7.5,
    this.waterGoal = 8,
    this.exerciseGoalWeek = 150,
    this.meditationGoal = 10,
    this.reminderTime,
    this.primaryFocus = WellnessFocus.general,
    this.secondaryFocus,
    required this.createdAt,
    required this.updatedAt,
    this.profileVersion = currentVersion,
  });

  factory UserProfile.fresh() {
    final now = DateTime.now();
    return UserProfile(createdAt: now, updatedAt: now);
  }

  /// True when the user never touched personalization (all personal
  /// fields empty + default focus). The app stays fully functional.
  bool get isUnset =>
      (displayName == null || displayName!.trim().isEmpty) &&
      ageRange == null &&
      exactAge == null &&
      wakeTime == null &&
      sleepTime == null &&
      reminderTime == null &&
      primaryFocus == WellnessFocus.general &&
      secondaryFocus == null;

  UserProfile copyWith({
    String? Function()? displayName,
    String? Function()? ageRange,
    int? Function()? exactAge,
    String? Function()? wakeTime,
    String? Function()? sleepTime,
    double? sleepGoal,
    int? waterGoal,
    int? exerciseGoalWeek,
    int? meditationGoal,
    String? Function()? reminderTime,
    WellnessFocus? primaryFocus,
    WellnessFocus? Function()? secondaryFocus,
  }) {
    return UserProfile(
      displayName:
          displayName != null ? displayName() : this.displayName,
      ageRange: ageRange != null ? ageRange() : this.ageRange,
      exactAge: exactAge != null ? exactAge() : this.exactAge,
      wakeTime: wakeTime != null ? wakeTime() : this.wakeTime,
      sleepTime: sleepTime != null ? sleepTime() : this.sleepTime,
      sleepGoal: sleepGoal ?? this.sleepGoal,
      waterGoal: waterGoal ?? this.waterGoal,
      exerciseGoalWeek: exerciseGoalWeek ?? this.exerciseGoalWeek,
      meditationGoal: meditationGoal ?? this.meditationGoal,
      reminderTime:
          reminderTime != null ? reminderTime() : this.reminderTime,
      primaryFocus: primaryFocus ?? this.primaryFocus,
      secondaryFocus: secondaryFocus != null
          ? secondaryFocus()
          : this.secondaryFocus,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      profileVersion: profileVersion,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': profileVersion,
        'displayName': displayName,
        'ageRange': ageRange,
        'exactAge': exactAge,
        'wakeTime': wakeTime,
        'sleepTime': sleepTime,
        'sleepGoal': sleepGoal,
        'waterGoal': waterGoal,
        'exerciseGoalWeek': exerciseGoalWeek,
        'meditationGoal': meditationGoal,
        'reminderTime': reminderTime,
        'primaryFocus': primaryFocus.name,
        'secondaryFocus': secondaryFocus?.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// Non-destructive migration: unknown/old payloads get defaults,
  /// original timestamps preserved when parseable.
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    DateTime parse(String? key, DateTime fallback) {
      if (key == null) return fallback;
      return DateTime.tryParse(json[key] as String? ?? '') ?? fallback;
    }

    final now = DateTime.now();
    return UserProfile(
      displayName: (json['displayName'] as String?)?.trim().isEmpty == true
          ? null
          : (json['displayName'] as String?)?.trim(),
      ageRange: json['ageRange'] as String?,
      exactAge: (json['exactAge'] as num?)?.toInt(),
      wakeTime: json['wakeTime'] as String?,
      sleepTime: json['sleepTime'] as String?,
      sleepGoal: (json['sleepGoal'] as num?)?.toDouble() ?? 7.5,
      waterGoal: (json['waterGoal'] as num?)?.toInt() ?? 8,
      exerciseGoalWeek:
          (json['exerciseGoalWeek'] as num?)?.toInt() ?? 150,
      meditationGoal: (json['meditationGoal'] as num?)?.toInt() ?? 10,
      reminderTime: json['reminderTime'] as String?,
      primaryFocus:
          WellnessFocusX.fromName(json['primaryFocus'] as String?),
      secondaryFocus: json['secondaryFocus'] == null
          ? null
          : WellnessFocusX.fromName(json['secondaryFocus'] as String?),
      createdAt: parse('createdAt', now),
      updatedAt: parse('updatedAt', now),
      profileVersion:
          (json['version'] as num?)?.toInt() ?? currentVersion,
    );
  }
}
