import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../local/local_database.dart';
import '../models/models.dart';

/// Settings repository. Hive is the source of truth; themeMode is mirrored
/// to SharedPreferences (genuinely small preference) for fast startup reads.
class SettingsRepository {
  static const _key = 'user_settings';

  Future<Result<UserSettings>> load() async {
    try {
      final raw = LocalDatabase.settingsBox.get(_key);
      if (raw == null) return const Success(UserSettings());
      return Success(
          UserSettings.fromJson(Map<String, dynamic>.from(raw as Map)));
    } catch (e) {
      return Failure(PersistenceException('Could not load settings.',
          originalError: e));
    }
  }

  Future<Result<UserSettings>> save(UserSettings settings) async {
    try {
      if (!['system', 'light', 'dark'].contains(settings.themeMode)) {
        return const Failure(
            ValidationException('Invalid theme mode.'));
      }
      await LocalDatabase.settingsBox.put(_key, settings.toJson());
      // Mirror tiny pref for fast startup.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.themeModeKey, settings.themeMode);
        await prefs.setBool('allow_screenshots', settings.allowScreenshots);
      } catch (_) {
        // Non-fatal: Hive remains source of truth.
      }
      return Success(settings);
    } catch (e) {
      return Failure(PersistenceException('Could not save settings.',
          originalError: e));
    }
  }
}
