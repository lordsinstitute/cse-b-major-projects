import 'package:hive_flutter/hive_flutter.dart';

/// Single local persistence solution: Hive boxes storing JSON maps.
/// Supports structured objects, updates, deletes, lists, restart persistence.
/// Settings (small prefs) additionally mirrored to SharedPreferences by the
/// settings repository — Hive remains the source of truth for structured data.
class LocalDatabase {
  static const String dailyBoxName = 'daily_health';
  static const String stressBoxName = 'stress_entries';
  static const String experimentsBoxName = 'experiments';
  static const String documentsBoxName = 'medical_documents';
  static const String settingsBoxName = 'settings';
  static const String gameStatsBoxName = 'game_stats';
  static const String morningBoxName = 'morning_checkins';
  static const String eveningBoxName = 'evening_reflections';
  static const String journalBoxName = 'journal_entries';
  static const String snapshotBoxName = 'health_snapshot';
  static const String medRemindersBoxName = 'med_reminders';
  static const String appointmentsBoxName = 'appointments';
  static const String doseLogBoxName = 'dose_log';
  static const String healthImportsBoxName = 'health_imports';
  static const String milestoneBoxName = 'milestone_state';
  static const String aiConversationsBoxName = 'ai_conversations';
  static const String aiMessagesBoxName = 'ai_messages';

  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  /// Initialize Hive. [path] overrides storage dir (used in tests).
  static Future<void> init({String? path}) async {
    if (_initialized) return;
    if (path != null) {
      Hive.init(path);
    } else {
      await Hive.initFlutter();
    }
    await Future.wait([
      Hive.openBox(dailyBoxName),
      Hive.openBox(stressBoxName),
      Hive.openBox(experimentsBoxName),
      Hive.openBox(documentsBoxName),
      Hive.openBox(settingsBoxName),
      Hive.openBox(gameStatsBoxName),
      Hive.openBox(morningBoxName),
      Hive.openBox(eveningBoxName),
      Hive.openBox(journalBoxName),
      Hive.openBox(snapshotBoxName),
      Hive.openBox(medRemindersBoxName),
      Hive.openBox(appointmentsBoxName),
      Hive.openBox(doseLogBoxName),
      Hive.openBox(healthImportsBoxName),
      Hive.openBox(milestoneBoxName),
      Hive.openBox(aiConversationsBoxName),
      Hive.openBox(aiMessagesBoxName),
    ]);
    _initialized = true;
  }

  static Box get dailyBox => Hive.box(dailyBoxName);
  static Box get stressBox => Hive.box(stressBoxName);
  static Box get experimentsBox => Hive.box(experimentsBoxName);
  static Box get documentsBox => Hive.box(documentsBoxName);
  static Box get settingsBox => Hive.box(settingsBoxName);
  static Box get gameStatsBox => Hive.box(gameStatsBoxName);
  static Box get morningBox => Hive.box(morningBoxName);
  static Box get eveningBox => Hive.box(eveningBoxName);
  static Box get journalBox => Hive.box(journalBoxName);
  static Box get snapshotBox => Hive.box(snapshotBoxName);
  static Box get medRemindersBox => Hive.box(medRemindersBoxName);
  static Box get appointmentsBox => Hive.box(appointmentsBoxName);
  static Box get doseLogBox => Hive.box(doseLogBoxName);
  static Box get healthImportsBox => Hive.box(healthImportsBoxName);
  static Box get milestoneBox => Hive.box(milestoneBoxName);
  static Box get aiConversationsBox =>
      Hive.box(aiConversationsBoxName);
  static Box get aiMessagesBox => Hive.box(aiMessagesBoxName);

  /// Test helper: wipe all boxes (only those currently open).
  static Future<void> clearAll() async {
    for (final name in [
      dailyBoxName,
      stressBoxName,
      experimentsBoxName,
      documentsBoxName,
      settingsBoxName,
      gameStatsBoxName,
      morningBoxName,
      eveningBoxName,
      journalBoxName,
      snapshotBoxName,
      medRemindersBoxName,
      appointmentsBoxName,
      doseLogBoxName,
      healthImportsBoxName,
      milestoneBoxName,
      aiConversationsBoxName,
      aiMessagesBoxName,
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).clear();
    }
  }
}
