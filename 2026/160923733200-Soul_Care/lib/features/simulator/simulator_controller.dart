import 'package:flutter/material.dart';

import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../data/repositories/daily_health_repository.dart';
import '../../data/repositories/stress_repository.dart';
import 'projection_engine.dart';

/// A named scenario sketch. Temporary by design (session state only).
class SavedScenario {
  final String name;
  final ScenarioInput input;
  final Projection projection;

  const SavedScenario({
    required this.name,
    required this.input,
    required this.projection,
  });
}

/// Preset adjustments applied on top of current values.
enum SimulatorPreset {
  betterSleep,
  moreMovement,
  lowerStress,
  betterHydration,
  balanced,
}

extension SimulatorPresetX on SimulatorPreset {
  String get label {
    switch (this) {
      case SimulatorPreset.betterSleep:
        return 'Better Sleep';
      case SimulatorPreset.moreMovement:
        return 'More Movement';
      case SimulatorPreset.lowerStress:
        return 'Lower Stress';
      case SimulatorPreset.betterHydration:
        return 'Better Hydration';
      case SimulatorPreset.balanced:
        return 'Balanced Routine';
    }
  }

  String get hint {
    switch (this) {
      case SimulatorPreset.betterSleep:
        return '+1h sleep';
      case SimulatorPreset.moreMovement:
        return '+60 min/week';
      case SimulatorPreset.lowerStress:
        return '−1 strain';
      case SimulatorPreset.betterHydration:
        return '+2 glasses';
      case SimulatorPreset.balanced:
        return 'all toward ideal';
    }
  }

  ScenarioInput apply(ScenarioInput current) {
    switch (this) {
      case SimulatorPreset.betterSleep:
        return current.copyWith(
            sleepHours: (current.sleepHours + 1).clamp(4.0, 10.0));
      case SimulatorPreset.moreMovement:
        return current.copyWith(
            exerciseMinWeek:
                (current.exerciseMinWeek + 60).clamp(0.0, 180.0));
      case SimulatorPreset.lowerStress:
        return current.copyWith(
            strain: (current.strain - 1).clamp(1.0, 5.0));
      case SimulatorPreset.betterHydration:
        return current.copyWith(
            waterGlasses:
                (current.waterGlasses + 2).clamp(0.0, 12.0));
      case SimulatorPreset.balanced:
        return ScenarioInput(
          sleepHours: current.sleepHours < 8 ? 8 : current.sleepHours,
          exerciseMinWeek:
              current.exerciseMinWeek < 150 ? 150 : current.exerciseMinWeek,
          strain: current.strain > 2 ? 2 : current.strain,
          waterGlasses:
              current.waterGlasses < 8 ? 8 : current.waterGlasses,
        );
    }
  }
}

/// Simulator state. READ-ONLY toward health records: it loads logged data
/// for the baseline and never writes entries, check-ins, or experiments.
class SimulatorController extends ChangeNotifier {
  final DailyHealthRepository _dailyRepo;
  final StressRepository _stressRepo;

  PatternBaseline? _baseline;
  bool _loading = true;
  ScenarioInput? _scenario;
  final List<SavedScenario> _saved = [];

  SimulatorController({
    DailyHealthRepository? dailyRepo,
    StressRepository? stressRepo,
  })  : _dailyRepo = dailyRepo ?? DailyHealthRepository(),
        // Never leave this null: a missing stress repo silently starves
        // the baseline of moods, locking the screen on "More data needed"
        // no matter how much is logged (found via a restore that changed
        // nothing on /future).
        _stressRepo = stressRepo ?? StressRepository() {
    load();
  }

  PatternBaseline? get baseline => _baseline;
  bool get loading => _loading;
  bool get hasBaseline => _baseline?.isComplete ?? false;

  ScenarioInput get currentInput =>
      _baseline?.toInput() ??
      const ScenarioInput(
          sleepHours: 7, exerciseMinWeek: 0, strain: 3, waterGlasses: 0);

  ScenarioInput get scenario => _scenario ?? currentInput;

  Projection get currentProjection =>
      WellnessProjectionEngine.project(currentInput);
  Projection get scenarioProjection =>
      WellnessProjectionEngine.project(scenario);

  int get change => scenarioProjection.overall - currentProjection.overall;

  List<String> get contributors =>
      WellnessProjectionEngine.changedInputs(currentInput, scenario);

  List<SavedScenario> get saved => List.unmodifiable(_saved);

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    final now = DateTime.now();
    final entries = await _dailyRepo
        .getRange(now.subtract(const Duration(days: 6)), now)
        .then((r) => r.fold(
            onSuccess: (l) => l,
            onFailure: (_) => const <DailyHealthEntry>[]));
    var moods = <int>[];
    final res = await _stressRepo.getRange(
        now.subtract(const Duration(days: 6)), now);
    res.fold(
      onSuccess: (list) =>
          moods = [for (final c in list) c.mood.score],
      onFailure: (_) {},
    );
    _baseline =
        PatternBaseline.fromLogs(last7: entries, moodScores: moods);
    _loading = false;
    notifyListeners();
  }

  void updateScenario(ScenarioInput next) {
    _scenario = next;
    notifyListeners();
  }

  void applyPreset(SimulatorPreset preset) {
    _scenario = preset.apply(scenario);
    notifyListeners();
  }

  /// Back to the user's own logged pattern. Never touches records.
  void resetToCurrent() {
    _scenario = null;
    notifyListeners();
  }

  /// Keeps up to 4 temporary sketches for side-by-side comparison.
  void saveScenario(String name) {
    final label = name.trim().isEmpty ? 'Scenario ${_saved.length + 1}' : name.trim();
    _saved.add(SavedScenario(
        name: label, input: scenario, projection: scenarioProjection));
    while (_saved.length > 4) {
      _saved.removeAt(0);
    }
    notifyListeners();
  }

  void removeScenario(int index) {
    if (index >= 0 && index < _saved.length) {
      _saved.removeAt(index);
      notifyListeners();
    }
  }
}
