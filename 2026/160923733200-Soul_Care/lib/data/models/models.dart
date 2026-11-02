import 'dart:io';

import 'enums.dart';

/// One row per calendar day. date is stored as yyyy-MM-dd, dateOnly semantics.
class DailyHealthEntry {
  final String date; // yyyy-MM-dd
  final double sleepHours;
  final SleepQuality sleepQuality;
  final bool feltRested;
  final String? exerciseType;
  final int exerciseMinutes;
  final ExerciseIntensity exerciseIntensity;
  final MealQuality mealQuality;
  final int waterGlasses;
  final int meditationMinutes;
  final double screenTimeHours;

  const DailyHealthEntry({
    required this.date,
    this.sleepHours = 0,
    this.sleepQuality = SleepQuality.okay,
    this.feltRested = false,
    this.exerciseType,
    this.exerciseMinutes = 0,
    this.exerciseIntensity = ExerciseIntensity.none,
    this.mealQuality = MealQuality.okay,
    this.waterGlasses = 0,
    this.meditationMinutes = 0,
    this.screenTimeHours = 0,
  });

  DailyHealthEntry copyWith({
    String? date,
    double? sleepHours,
    SleepQuality? sleepQuality,
    bool? feltRested,
    String? exerciseType,
    int? exerciseMinutes,
    ExerciseIntensity? exerciseIntensity,
    MealQuality? mealQuality,
    int? waterGlasses,
    int? meditationMinutes,
    double? screenTimeHours,
  }) {
    return DailyHealthEntry(
      date: date ?? this.date,
      sleepHours: sleepHours ?? this.sleepHours,
      sleepQuality: sleepQuality ?? this.sleepQuality,
      feltRested: feltRested ?? this.feltRested,
      exerciseType: exerciseType ?? this.exerciseType,
      exerciseMinutes: exerciseMinutes ?? this.exerciseMinutes,
      exerciseIntensity: exerciseIntensity ?? this.exerciseIntensity,
      mealQuality: mealQuality ?? this.mealQuality,
      waterGlasses: waterGlasses ?? this.waterGlasses,
      meditationMinutes: meditationMinutes ?? this.meditationMinutes,
      screenTimeHours: screenTimeHours ?? this.screenTimeHours,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'sleepHours': sleepHours,
        'sleepQuality': sleepQuality.score,
        'feltRested': feltRested,
        'exerciseType': exerciseType,
        'exerciseMinutes': exerciseMinutes,
        'exerciseIntensity': exerciseIntensity.name,
        'mealQuality': mealQuality.score,
        'waterGlasses': waterGlasses,
        'meditationMinutes': meditationMinutes,
        'screenTimeHours': screenTimeHours,
      };

  factory DailyHealthEntry.fromJson(Map<String, dynamic> json) {
    return DailyHealthEntry(
      date: json['date'] as String,
      sleepHours: (json['sleepHours'] as num?)?.toDouble() ?? 0,
      sleepQuality:
          SleepQualityX.fromScore((json['sleepQuality'] as num?)?.toInt() ?? 3),
      feltRested: json['feltRested'] as bool? ?? false,
      exerciseType: json['exerciseType'] as String?,
      exerciseMinutes: (json['exerciseMinutes'] as num?)?.toInt() ?? 0,
      exerciseIntensity: ExerciseIntensityX.fromName(
          json['exerciseIntensity'] as String?),
      mealQuality:
          MealQualityX.fromScore((json['mealQuality'] as num?)?.toInt() ?? 3),
      waterGlasses: (json['waterGlasses'] as num?)?.toInt() ?? 0,
      meditationMinutes: (json['meditationMinutes'] as num?)?.toInt() ?? 0,
      screenTimeHours:
          (json['screenTimeHours'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Stress / mood check-in. Multiple per day allowed (id = uuid).
class StressEntry {
  final String id;
  final String date; // yyyy-MM-dd
  final Mood mood;
  final List<String> triggers;
  final double controllability; // 0..1
  final String? notes;
  final DateTime createdAt;

  const StressEntry({
    required this.id,
    required this.date,
    required this.mood,
    this.triggers = const [],
    this.controllability = 0.5,
    this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'mood': mood.score,
        'triggers': triggers,
        'controllability': controllability,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory StressEntry.fromJson(Map<String, dynamic> json) {
    return StressEntry(
      id: json['id'] as String,
      date: json['date'] as String,
      mood: MoodX.fromScore((json['mood'] as num?)?.toInt() ?? 3),
      triggers:
          (json['triggers'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      controllability:
          (json['controllability'] as num?)?.toDouble() ?? 0.5,
      notes: json['notes'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Self-experiment (e.g. "no caffeine after 2pm for 14 days").
class Experiment {
  final String id;
  final String? templateId;
  final String title;
  final String description;
  final String targetMetric;
  final int durationDays;
  final DateTime? startDate;
  final DateTime? endDate;
  final ExperimentStatus status;
  final List<String> checkIns; // yyyy-MM-dd strings (DONE days)
  final List<String> missedDays; // yyyy-MM-dd strings (explicit MISSED)
  final DateTime createdAt;
  final DateTime updatedAt;

  const Experiment({
    required this.id,
    this.templateId,
    required this.title,
    required this.description,
    required this.targetMetric,
    required this.durationDays,
    this.startDate,
    this.endDate,
    this.status = ExperimentStatus.draft,
    this.checkIns = const [],
    this.missedDays = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  Experiment copyWith({
    String? title,
    String? description,
    String? targetMetric,
    int? durationDays,
    DateTime? startDate,
    DateTime? endDate,
    ExperimentStatus? status,
    List<String>? checkIns,
    List<String>? missedDays,
    DateTime? updatedAt,
  }) {
    return Experiment(
      id: id,
      templateId: templateId,
      title: title ?? this.title,
      description: description ?? this.description,
      targetMetric: targetMetric ?? this.targetMetric,
      durationDays: durationDays ?? this.durationDays,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      checkIns: checkIns ?? this.checkIns,
      missedDays: missedDays ?? this.missedDays,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'templateId': templateId,
        'title': title,
        'description': description,
        'targetMetric': targetMetric,
        'durationDays': durationDays,
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'status': status.name,
        'checkIns': checkIns,
        'missedDays': missedDays,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Experiment.fromJson(Map<String, dynamic> json) {
    return Experiment(
      id: json['id'] as String,
      templateId: json['templateId'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      targetMetric: json['targetMetric'] as String? ?? '',
      durationDays: (json['durationDays'] as num?)?.toInt() ?? 7,
      startDate: json['startDate'] == null
          ? null
          : DateTime.tryParse(json['startDate'] as String),
      endDate: json['endDate'] == null
          ? null
          : DateTime.tryParse(json['endDate'] as String),
      status: ExperimentStatusX.fromName(json['status'] as String?),
      checkIns:
          (json['checkIns'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      missedDays:
          (json['missedDays'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Local health document metadata (file itself lives in app documents dir).
/// Metadata is stored separately from file contents.
class MedicalDocument {
  final String id;
  final String fileName;
  final String localPath;
  final DateTime importedAt;
  final DateTime? documentDate;
  final DocumentCategory category;
  final List<String> tags;
  final String provider;
  final String? summary;
  final DocumentProcessingStatus processingStatus;
  final String? notes;

  /// Internal content hash for duplicate detection. Never logged.
  final String contentHash;

  const MedicalDocument({
    required this.id,
    required this.fileName,
    required this.localPath,
    required this.importedAt,
    this.documentDate,
    this.category = DocumentCategory.other,
    this.tags = const [],
    this.provider = '',
    this.summary,
    this.processingStatus = DocumentProcessingStatus.idle,
    this.notes,
    this.contentHash = '',
  });

  MedicalDocument copyWith({
    String? fileName,
    String? localPath,
    DateTime? documentDate,
    DocumentCategory? category,
    List<String>? tags,
    String? provider,
    String? summary,
    DocumentProcessingStatus? processingStatus,
    String? notes,
    String? contentHash,
  }) {
    return MedicalDocument(
      id: id,
      fileName: fileName ?? this.fileName,
      localPath: localPath ?? this.localPath,
      importedAt: importedAt,
      documentDate: documentDate ?? this.documentDate,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      provider: provider ?? this.provider,
      summary: summary ?? this.summary,
      processingStatus: processingStatus ?? this.processingStatus,
      notes: notes ?? this.notes,
      contentHash: contentHash ?? this.contentHash,
    );
  }

  /// True when the copied file no longer exists on disk.
  Future<bool> get isFileMissing async {
    if (localPath.isEmpty) return true;
    try {
      return !(await File(localPath).exists());
    } catch (_) {
      return true;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'localPath': localPath,
        'importedAt': importedAt.toIso8601String(),
        'documentDate': documentDate?.toIso8601String(),
        'category': category.name,
        'tags': tags,
        'provider': provider,
        'summary': summary,
        'processingStatus': processingStatus.name,
        'notes': notes,
        'contentHash': contentHash,
      };

  factory MedicalDocument.fromJson(Map<String, dynamic> json) {
    return MedicalDocument(
      id: json['id'] as String,
      fileName: json['fileName'] as String? ?? '',
      localPath: json['localPath'] as String? ?? '',
      importedAt:
          DateTime.tryParse(json['importedAt'] as String? ?? '') ??
              DateTime.now(),
      documentDate: json['documentDate'] == null
          ? null
          : DateTime.tryParse(json['documentDate'] as String),
      category:
          DocumentCategoryX.fromName(json['category'] as String?),
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      provider: json['provider'] as String? ?? '',
      summary: json['summary'] as String?,
      processingStatus: DocumentProcessingStatusX.fromName(
          json['processingStatus'] as String?),
      notes: json['notes'] as String?,
      contentHash: json['contentHash'] as String? ?? '',
    );
  }
}

/// Small user preferences.
class UserSettings {
  final String themeMode; // system | light | dark
  final int colorSeed; // ARGB seed for the Material 3 color scheme
  final double uiZoom; // 0.5..2.0 global scale, 1.0 = 100%
  final String? fontFamily; // null = system; otherwise a bundled Google Font
  final double fontScale; // 0.8..1.4 text-size multiplier, 1.0 = default
  final bool notificationsEnabled;
  final String? dailyReminderTime; // HH:mm
  final bool experimentRemindersEnabled;
  final bool appLockEnabled; // journal privacy lock
  final String? appLockHash; // hashed PIN, never the PIN itself
  final String lockScope; // off | sections | full
  final int lockTimeoutMin; // 0 immediate, 1, or 5
  final bool lockOnBackground;
  final List<String> protectedScreens;
  final bool biometricEnabled;
  final bool onboardingDone;
  final bool allowScreenshots; // false = block screenshots (FLAG_SECURE)

  const UserSettings({
    this.themeMode = 'system',
    this.colorSeed = 0xFF3E7C6B,
    this.uiZoom = 1.0,
    this.fontFamily,
    this.fontScale = 1.0,
    this.notificationsEnabled = false,
    this.dailyReminderTime,
    this.experimentRemindersEnabled = true,
    this.appLockEnabled = false,
    this.appLockHash,
    this.lockScope = 'off',
    this.lockTimeoutMin = 1,
    this.lockOnBackground = true,
    this.protectedScreens = const [
      'journal',
      'snapshot',
      'timeline',
      'reminders',
      'reports',
    ],
    this.biometricEnabled = false,
    this.onboardingDone = false,
    this.allowScreenshots = false,
  });

  UserSettings copyWith({
    String? themeMode,
    int? colorSeed,
    double? uiZoom,
    String? Function()? fontFamily,
    double? fontScale,
    bool? notificationsEnabled,
    String? dailyReminderTime,
    bool? experimentRemindersEnabled,
    bool? appLockEnabled,
    String? Function()? appLockHash,
    String? lockScope,
    int? lockTimeoutMin,
    bool? lockOnBackground,
    List<String>? protectedScreens,
    bool? biometricEnabled,
    bool? onboardingDone,
    bool? allowScreenshots,
  }) {
    return UserSettings(
      themeMode: themeMode ?? this.themeMode,
      colorSeed: colorSeed ?? this.colorSeed,
      uiZoom: uiZoom ?? this.uiZoom,
      fontFamily:
          fontFamily != null ? fontFamily() : this.fontFamily,
      fontScale: fontScale ?? this.fontScale,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      dailyReminderTime: dailyReminderTime ?? this.dailyReminderTime,
      experimentRemindersEnabled:
          experimentRemindersEnabled ?? this.experimentRemindersEnabled,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      appLockHash:
          appLockHash != null ? appLockHash() : this.appLockHash,
      lockScope: lockScope ?? this.lockScope,
      lockTimeoutMin: lockTimeoutMin ?? this.lockTimeoutMin,
      lockOnBackground: lockOnBackground ?? this.lockOnBackground,
      protectedScreens: protectedScreens ?? this.protectedScreens,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      onboardingDone: onboardingDone ?? this.onboardingDone,
      allowScreenshots: allowScreenshots ?? this.allowScreenshots,
    );
  }

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode,
        'colorSeed': colorSeed,
        'uiZoom': uiZoom,
        'fontFamily': fontFamily,
        'fontScale': fontScale,
        'notificationsEnabled': notificationsEnabled,
        'dailyReminderTime': dailyReminderTime,
        'experimentRemindersEnabled': experimentRemindersEnabled,
        'appLockEnabled': appLockEnabled,
        'appLockHash': appLockHash,
        'lockScope': lockScope,
        'lockTimeoutMin': lockTimeoutMin,
        'lockOnBackground': lockOnBackground,
        'protectedScreens': protectedScreens,
        'biometricEnabled': biometricEnabled,
        'onboardingDone': onboardingDone,
        'allowScreenshots': allowScreenshots,
      };

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      themeMode: json['themeMode'] as String? ?? 'system',
      colorSeed:
          (json['colorSeed'] as num?)?.toInt() ?? 0xFF3E7C6B,
      uiZoom: ((json['uiZoom'] as num?)?.toDouble() ?? 1.0)
          .clamp(0.5, 2.0),
      fontFamily: json['fontFamily'] as String?,
      fontScale: ((json['fontScale'] as num?)?.toDouble() ?? 1.0)
          .clamp(0.8, 1.4),
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? false,
      dailyReminderTime: json['dailyReminderTime'] as String?,
      experimentRemindersEnabled:
          json['experimentRemindersEnabled'] as bool? ?? true,
      appLockEnabled: json['appLockEnabled'] as bool? ?? false,
      appLockHash: json['appLockHash'] as String?,
      lockScope: json['lockScope'] as String? ?? 'off',
      lockTimeoutMin: (json['lockTimeoutMin'] as num?)?.toInt() ?? 1,
      lockOnBackground: json['lockOnBackground'] as bool? ?? true,
      protectedScreens: (json['protectedScreens'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [
            'journal',
            'snapshot',
            'timeline',
            'reminders',
            'reports',
          ],
      biometricEnabled: json['biometricEnabled'] as bool? ?? false,
      onboardingDone: json['onboardingDone'] as bool? ?? false,
      allowScreenshots: json['allowScreenshots'] as bool? ?? false,
    );
  }
}
