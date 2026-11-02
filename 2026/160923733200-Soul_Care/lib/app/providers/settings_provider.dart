import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/app_lock/biometric_gateway.dart';
import '../../core/utils/utils.dart';
import '../../data/models/models.dart';
import '../../data/repositories/settings_repository.dart';

/// Known sensitive areas. Whole-app mode covers everything.
const List<String> lockableScreens = [
  'journal',
  'snapshot',
  'timeline',
  'reminders',
  'reports',
];

class SettingsProvider extends ChangeNotifier {
  final SettingsRepository _repo;
  final BiometricGateway _biometrics;
  UserSettings _settings = const UserSettings();
  bool _loaded = false;
  String? _error;

  SettingsProvider(this._repo, {BiometricGateway? biometrics})
      // SoulCare targets Android only: real biometrics there, an inert
      // gateway everywhere else (notably widget tests, where platform
      // channel FFI would otherwise block the isolate).
      : _biometrics = biometrics ??
            (defaultTargetPlatform == TargetPlatform.android
                ? LocalAuthGateway()
                : UnavailableBiometricGateway());

  UserSettings get settings => _settings;
  bool get loaded => _loaded;
  String? get error => _error;

  /// Session-only journal unlock (resets on restart).
  bool _journalUnlocked = false;
  bool get journalUnlocked => _journalUnlocked;

  /// Session-only whole-app unlock (resets on restart).
  bool _appUnlocked = false;
  bool get appUnlocked => _appUnlocked;

  /// Consecutive wrong PIN attempts this session (informational only;
  /// the user is never locked out).
  int _failedAttempts = 0;
  int get failedAttempts => _failedAttempts;

  /// Last time the app was active (foreground or successful auth).
  DateTime _lastActive = DateTime.now();
  DateTime get lastActiveAt => _lastActive;

  bool _biometricAvailableCache = false;
  bool get biometricAvailable => _biometricAvailableCache;

  ThemeMode get themeMode {
    switch (_settings.themeMode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> load() async {
    final res = await _repo.load();
    res.fold(
      onSuccess: (s) async {
        // Migration: pre-scope installs only knew on/off — an enabled
        // legacy lock becomes sections mode (same effective behavior).
        if (s.appLockEnabled && s.lockScope == 'off') {
          final migrated = s.copyWith(lockScope: 'sections');
          final saved = await _repo.save(migrated);
          _settings = saved.fold(
              onSuccess: (v) => v, onFailure: (_) => migrated);
        } else {
          _settings = s;
        }
        _loaded = true;
        _error = null;
      },
      onFailure: (e) {
        _error = 'Could not load settings. Using defaults.';
        _loaded = true;
      },
    );
    try {
      // Bounded: on some Windows machines the platform biometric query
      // can block; availability must never stall app (or test) startup.
      _biometricAvailableCache = await _biometrics
          .canCheck()
          .timeout(const Duration(seconds: 3),
              onTimeout: () => false);
    } catch (_) {
      _biometricAvailableCache = false;
    }
    notifyListeners();
  }

  Future<bool> update(UserSettings next) async {
    final res = await _repo.save(next);
    return res.fold(
      onSuccess: (s) {
        _settings = s;
        _error = null;
        if (!s.appLockEnabled) _journalUnlocked = false;
        notifyListeners();
        return true;
      },
      onFailure: (e) {
        _error = e.message;
        notifyListeners();
        return false;
      },
    );
  }

  /// Enables/disables the journal privacy lock. Enabling requires a
  /// 4-digit PIN; only its hash is stored, never the PIN.
  Future<bool> setAppLock({required bool enabled, String? pin}) async {
    if (enabled) {
      if (pin == null || !RegExp(r'^\d{4}$').hasMatch(pin)) {
        _error = 'Choose a 4-digit PIN.';
        notifyListeners();
        return false;
      }
      return update(_settings.copyWith(
        appLockEnabled: true,
        appLockHash: () => hashPin(pin),
      ));
    }
    _journalUnlocked = false;
    return update(_settings.copyWith(
      appLockEnabled: false,
      appLockHash: () => null,
    ));
  }

  /// Verifies the PIN for this session. Returns true when unlocked.
  /// Wrong attempts only increment a counter — never a lockout.
  bool unlockJournal(String pin) {
    final hash = _settings.appLockHash;
    if (!_settings.appLockEnabled || hash == null) {
      _journalUnlocked = true;
      _appUnlocked = true;
      notifyListeners();
      return true;
    }
    if (hashPin(pin) == hash) {
      _journalUnlocked = true;
      _appUnlocked = true;
      _failedAttempts = 0;
      _lastActive = DateTime.now();
      _error = null;
      notifyListeners();
      return true;
    }
    _failedAttempts++;
    _error = _failedAttempts == 1
        ? 'Wrong PIN. Try again — nothing is locked.'
        : 'Wrong PIN ($_failedAttempts tries). Keep trying — nothing is locked.';
    notifyListeners();
    return false;
  }

  void lockJournal() {
    _journalUnlocked = false;
    notifyListeners();
  }

  /// Biometric unlock (falls back to PIN in the UI when unavailable or
  /// declined). Returns true when this session is unlocked.
  Future<bool> authenticateBiometric() async {
    try {
      final ok = await _biometrics.authenticate(
          'Unlock SoulCare');
      if (ok) {
        _journalUnlocked = true;
        _appUnlocked = true;
        _failedAttempts = 0;
        _lastActive = DateTime.now();
        _error = null;
        notifyListeners();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Whether [screen] is currently protected (sections mode).
  bool protects(String screen) {
    if (!_settings.appLockEnabled) return false;
    if (_settings.lockScope == 'full') return true;
    if (_settings.lockScope != 'sections') return false;
    return _settings.protectedScreens.contains(screen);
  }

  /// Whether the whole-app gate must show right now.
  bool get appGateLocked =>
      _settings.appLockEnabled &&
      _settings.lockScope == 'full' &&
      !_appUnlocked;

  /// Called when the app leaves the foreground.
  void recordBackgrounded() {
    final s = _settings;
    if (!s.appLockEnabled) return;
    if (s.lockOnBackground || s.lockTimeoutMin <= 0) {
      _journalUnlocked = false;
      _appUnlocked = false;
      notifyListeners();
    }
  }

  /// Called when the app returns to the foreground. Applies the
  /// inactivity timeout on top of the background rule.
  void recordForegrounded({bool wasBackgrounded = true}) {
    final s = _settings;
    if (!s.appLockEnabled) return;
    final shouldLock = timeoutElapsed(
      lastActive: _lastActive,
      now: DateTime.now(),
      timeoutMin: s.lockTimeoutMin,
      lockOnBackground: s.lockOnBackground,
      wasBackgrounded: wasBackgrounded,
    );
    if (shouldLock) {
      _journalUnlocked = false;
      _appUnlocked = false;
    } else {
      _lastActive = DateTime.now();
    }
    notifyListeners();
  }

  /// Pure timeout check (testable): should a session that started at
  /// [lastActive] be locked at [now] under these settings?
  static bool timeoutElapsed({
    required DateTime lastActive,
    required DateTime now,
    required int timeoutMin,
    required bool lockOnBackground,
    required bool wasBackgrounded,
  }) {
    if (lockOnBackground && wasBackgrounded) return true;
    if (timeoutMin <= 0) return true;
    return now.difference(lastActive) > Duration(minutes: timeoutMin);
  }
}
