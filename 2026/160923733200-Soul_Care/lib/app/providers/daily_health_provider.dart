import 'package:flutter/material.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/home_widget/widget_refresh.dart';
import '../../core/utils/utils.dart';
import '../../core/wellness/insights.dart';
import '../../core/wellness/wellness_score.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../data/repositories/daily_health_repository.dart';
import '../../data/repositories/stress_repository.dart';

/// Daily-health state: today's entry, yesterday's entry (suggestions),
/// today's stress check-ins, and per-section partial saving.
///
/// Section completion is derived from persisted data (survives restarts):
/// sleep = sleepHours > 0, movement = exerciseMinutes > 0,
/// nutrition = waterGlasses > 0, mind = meditationMinutes > 0,
/// stress = ≥ 1 check-in logged today.
class DailyHealthProvider extends ChangeNotifier {
  final DailyHealthRepository _repo;
  final StressRepository? _stressRepo;

  DailyHealthEntry? _today;
  DailyHealthEntry? _yesterday;
  List<StressEntry> _todayStress = [];
  bool _loading = false;
  String? _error;
  String? _lastSavedSection;

  DailyHealthProvider(this._repo, {StressRepository? stressRepo})
      : _stressRepo = stressRepo;

  DailyHealthEntry? get today => _today;
  DailyHealthEntry? get yesterday => _yesterday;
  List<StressEntry> get todayStress => List.unmodifiable(_todayStress);
  bool get loading => _loading;
  String? get error => _error;

  /// Name of the section saved most recently (for subtle confirmation).
  String? get lastSavedSection => _lastSavedSection;

  String get todayKey => formatDateForStorage(DateTime.now());
  String get yesterdayKey => formatDateForStorage(
      DateTime.now().subtract(const Duration(days: 1)));

  // --- Section completion (data-driven) ---
  bool get sleepDone => (_today?.sleepHours ?? 0) > 0;
  bool get movementDone => (_today?.exerciseMinutes ?? 0) > 0;
  bool get nutritionDone => (_today?.waterGlasses ?? 0) > 0;
  bool get mindDone => (_today?.meditationMinutes ?? 0) > 0;
  bool get stressDone => _todayStress.isNotEmpty;

  int get completedSections => [
        sleepDone,
        movementDone,
        nutritionDone,
        mindDone,
        stressDone,
      ].where((d) => d).length;

  static const int totalSections = 5;

  Future<void> loadToday() async {
    _loading = true;
    _error = null;
    notifyListeners();
    final res = await _repo.getByDate(todayKey);
    res.fold(
      onSuccess: (e) => _today = e ?? DailyHealthEntry(date: todayKey),
      onFailure: (err) => _error = err.message,
    );
    await _loadYesterday();
    await _loadTodayStress();
    _loading = false;
    notifyListeners();
  }

  Future<void> _loadYesterday() async {
    final res = await _repo.getByDate(yesterdayKey);
    res.fold(onSuccess: (e) => _yesterday = e, onFailure: (_) {});
  }

  Future<void> _loadTodayStress() async {
    final repo = _stressRepo;
    if (repo == null) return;
    final res = await repo.getByDate(todayKey);
    res.fold(onSuccess: (list) => _todayStress = list, onFailure: (_) {});
  }

  /// Merges [update] into today's persisted entry and saves.
  /// Previously saved sections are preserved (merge, never overwrite blindly).
  Future<bool> _saveSection(
      String section, DailyHealthEntry Function(DailyHealthEntry) update) async {
    final base = _today ?? DailyHealthEntry(date: todayKey);
    final merged = update(base);
    final res = await _repo.save(merged);
    return res.fold(
      onSuccess: (e) {
        _today = e;
        _error = null;
        _lastSavedSection = section;
        notifyListeners();
        // Push fresh numbers to the home-screen widget (best effort;
        // failures are swallowed inside the refresh service).
        WidgetRefresh.refresh(
          score: todayWellnessScore,
          done: completedSections,
          total: totalSections,
          dateKey: todayKey,
          greeting: greetingForHour(DateTime.now().hour),
        );
        return true;
      },
      onFailure: (err) {
        _error = err is ValidationException
            ? err.message
            : 'Could not save. Your previously saved sections are intact — please try again.';
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> saveSleep({
    required double hours,
    required SleepQuality quality,
    required bool feltRested,
  }) =>
      _saveSection('Sleep',
          (e) => e.copyWith(sleepHours: hours, sleepQuality: quality, feltRested: feltRested));

  Future<bool> saveMovement({
    required String type,
    required int minutes,
    required ExerciseIntensity intensity,
  }) =>
      _saveSection(
          'Movement',
          (e) => e.copyWith(
              exerciseType: type,
              exerciseMinutes: minutes,
              exerciseIntensity: intensity));

  Future<bool> saveNutrition({
    required MealQuality mealQuality,
    required int waterGlasses,
  }) =>
      _saveSection(
          'Nutrition',
          (e) =>
              e.copyWith(mealQuality: mealQuality, waterGlasses: waterGlasses));

  Future<bool> saveMind({
    required int meditationMinutes,
    required double screenTimeHours,
  }) =>
      _saveSection(
          'Mind',
          (e) => e.copyWith(
              meditationMinutes: meditationMinutes,
              screenTimeHours: screenTimeHours));

  /// Full-entry save (kept for compatibility).
  Future<bool> save(DailyHealthEntry entry) =>
      _saveSection('Day', (e) => entry.copyWith(date: e.date));

  Future<bool> saveStressCheck({
    required Mood mood,
    required List<String> triggers,
    required double controllability,
    String? notes,
  }) async {
    final repo = _stressRepo;
    if (repo == null) {
      _error = 'Stress storage is unavailable right now.';
      notifyListeners();
      return false;
    }
    final now = DateTime.now();
    final entry = StressEntry(
      id: generateId(),
      date: todayKey,
      mood: mood,
      triggers: triggers,
      controllability: controllability.clamp(0.0, 1.0),
      notes: (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
      createdAt: now,
    );
    final res = await repo.save(entry);
    return res.fold(
      onSuccess: (e) {
        _todayStress = [e, ..._todayStress];
        _error = null;
        _lastSavedSection = 'Stress';
        notifyListeners();
        return true;
      },
      onFailure: (err) {
        _error = err is ValidationException
            ? err.message
            : 'Could not save your check-in. Please try again.';
        notifyListeners();
        return false;
      },
    );
  }

  /// Illustrative wellness score based only on logged data.
  WellnessScore get todayScore {
    final daysLogged = 1; // single-day view; dashboard supplies week context
    final calm = _todayStress.isEmpty
        ? null
        : calmFromMoods(_todayStress.map((e) => e.mood.score).toList());
    return WellnessScoreCalculator.calculate(
      entry: _today ?? DailyHealthEntry(date: todayKey),
      previousEntry: _yesterday,
      daysLoggedLast7: _today == null ? 0 : daysLogged,
      calmScore: calm,
    );
  }

  int get todayWellnessScore => todayScore.totalScore;

  void clearSavedFlag() {
    _lastSavedSection = null;
    notifyListeners();
  }
}
