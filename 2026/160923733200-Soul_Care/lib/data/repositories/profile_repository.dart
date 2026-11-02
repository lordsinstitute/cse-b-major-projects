import '../../core/errors/app_exceptions.dart';
import '../local/local_database.dart';
import '../models/user_profile.dart';

/// Profile persistence (own key in the settings box).
/// Migration is non-destructive: legacy/partial payloads are filled with
/// defaults, and a pre-existing reminder time in UserSettings is adopted
/// once (never overwritten back).
class ProfileRepository {
  static const _key = 'user_profile';

  static bool validTime(String? raw) {    if (raw == null) return true; // optional
    final parts = raw.split(':');
    if (parts.length != 2) return false;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    return h != null &&
        m != null &&
        h >= 0 &&
        h <= 23 &&
        m >= 0 &&
        m <= 59;
  }

  Future<Result<UserProfile>> load() async {
    try {
      final raw = LocalDatabase.settingsBox.get(_key);
      if (raw == null) {
        // First run: adopt legacy reminder time if the user set one.
        String? legacyReminder;
        try {
          final settings =
              LocalDatabase.settingsBox.get('user_settings');
          if (settings != null) {
            legacyReminder =
                (Map<String, dynamic>.from(settings as Map))[
                    'dailyReminderTime'] as String?;
          }
        } catch (_) {}
        final now = DateTime.now();
        return Success(UserProfile(
          reminderTime: legacyReminder,
          createdAt: now,
          updatedAt: now,
        ));
      }
      final profile = UserProfile.fromJson(
          Map<String, dynamic>.from(raw as Map));
      // Clamp out-of-range legacy numbers into valid ranges.
      return Success(UserProfile(
        displayName: profile.displayName,
        ageRange: profile.ageRange,
        exactAge: profile.exactAge,
        wakeTime: profile.wakeTime,
        sleepTime: profile.sleepTime,
        sleepGoal: profile.sleepGoal.clamp(4.0, 10.0),
        waterGoal: profile.waterGoal.clamp(1, 20),
        exerciseGoalWeek: profile.exerciseGoalWeek.clamp(10, 600),
        meditationGoal: profile.meditationGoal.clamp(0, 120),
        reminderTime: profile.reminderTime,
        primaryFocus: profile.primaryFocus,
        secondaryFocus: profile.secondaryFocus,
        createdAt: profile.createdAt,
        updatedAt: profile.updatedAt,
        profileVersion: UserProfile.currentVersion,
      ));
    } catch (e) {
      return Failure(PersistenceException('Could not load your profile.',
          originalError: e));
    }
  }

  Future<Result<UserProfile>> save(UserProfile profile) async {
    try {
      final name = profile.displayName?.trim() ?? '';
      if (name.length > 60) {
        return const Failure(
            ValidationException('Display name is too long.'));
      }
      if (profile.exactAge != null &&
          (profile.exactAge! < 1 || profile.exactAge! > 120)) {
        return const Failure(
            ValidationException('Age must be between 1 and 120.'));
      }
      if (!validTime(profile.wakeTime) ||
          !validTime(profile.sleepTime) ||
          !validTime(profile.reminderTime)) {
        return const Failure(
            ValidationException('Times must look like 07:30.'));
      }
      if (profile.waterGoal < 1 ||
          profile.waterGoal > 20 ||
          profile.sleepGoal < 4 ||
          profile.sleepGoal > 10 ||
          profile.exerciseGoalWeek < 10 ||
          profile.exerciseGoalWeek > 600 ||
          profile.meditationGoal < 0 ||
          profile.meditationGoal > 120) {
        return const Failure(
            ValidationException('One of the goals is out of range.'));
      }
      if (profile.secondaryFocus != null &&
          profile.secondaryFocus == profile.primaryFocus) {
        return const Failure(ValidationException(
            'Secondary focus must differ from the primary focus.'));
      }
      final cleaned = UserProfile(
        displayName: name.isEmpty ? null : name,
        ageRange: profile.ageRange,
        exactAge: profile.exactAge,
        wakeTime: profile.wakeTime,
        sleepTime: profile.sleepTime,
        sleepGoal: profile.sleepGoal,
        waterGoal: profile.waterGoal,
        exerciseGoalWeek: profile.exerciseGoalWeek,
        meditationGoal: profile.meditationGoal,
        reminderTime: profile.reminderTime,
        primaryFocus: profile.primaryFocus,
        secondaryFocus: profile.secondaryFocus,
        createdAt: profile.createdAt,
        updatedAt: DateTime.now(),
        profileVersion: UserProfile.currentVersion,
      );
      await LocalDatabase.settingsBox.put(_key, cleaned.toJson());
      return Success(cleaned);
    } catch (e) {
      return Failure(PersistenceException('Could not save your profile.',
          originalError: e));
    }
  }
}
