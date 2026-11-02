/// Application-wide constants for SoulCare
class AppConstants {
  /// App metadata
  static const String appName = 'SoulCare';
  static const String appVersion = '1.0.0';
  static const String appVersionCode = '1';

  /// Database
  static const String databaseName = 'soulcare.db';
  static const int databaseVersion = 1;

  /// Default values
  static const int defaultWaterGlasses = 8;
  static const int defaultSleepHours = 8;
  static const int defaultScreenTimeHours = 2;

  /// Date formats
  static const String dateFormat = 'yyyy-MM-dd';
  static const String dateTimeFormat = 'yyyy-MM-dd HH:mm:ss';
  static const String displayDateFormat = 'MMM d, yyyy';
  static const String displayMonthFormat = 'MMMM yyyy';

  /// Storage keys
  static const String themeModeKey = 'theme_mode';
  static const String notificationsEnabledKey = 'notifications_enabled';
  static const String dailyReminderTimeKey = 'daily_reminder_time';
  static const String experimentRemindersEnabledKey = 'experiment_reminders_enabled';

  /// Limits
  static const int maxNotesLength = 2000;
  static const int maxTagsCount = 10;
  static const int maxExperimentDurationDays = 365;

  /// Animation durations
  static const Duration shortAnimation = Duration(milliseconds: 150);
  static const Duration mediumAnimation = Duration(milliseconds: 300);
  static const Duration longAnimation = Duration(milliseconds: 500);

  /// Spacing
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;

  /// Border radius
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double radiusFull = 999.0;

  /// Elevation
  static const double elevationNone = 0.0;
  static const double elevationLow = 1.0;
  static const double elevationMedium = 3.0;
  static const double elevationHigh = 6.0;

  /// Document vault (local-first).
  static const String documentsDirName = 'medical_documents';
  static const int maxDocumentSizeBytes = 25 * 1024 * 1024; // 25 MB
  static const List<String> allowedDocumentExtensions = ['pdf'];
}