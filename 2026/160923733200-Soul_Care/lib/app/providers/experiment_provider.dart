import 'package:flutter/material.dart';

import '../../core/utils/utils.dart';
import '../../data/models/checkins.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/checkin_repository.dart';
import '../../data/repositories/daily_health_repository.dart';
import '../../data/repositories/experiment_repository.dart';
import '../../data/repositories/stress_repository.dart';
import '../../features/experiments/experiment_engine.dart';
import '../../features/experiments/experiment_generator.dart';
import '../../features/experiments/experiment_templates.dart';

/// Lab state: templates, active experiment, history, baselines, results.
/// Check-ins persist immediately via the repository (survive app restarts).
/// Only one experiment is active at a time.
class ExperimentProvider extends ChangeNotifier {
  final ExperimentRepository _repo;
  final DailyHealthRepository? _dailyRepo;
  final StressRepository _stressRepo;
  final MorningRepository _morningRepo;
  final EveningRepository _eveningRepo;

  List<Experiment> _items = [];
  bool _loading = false;
  String? _error;

  ExperimentProvider(this._repo,
      {DailyHealthRepository? dailyRepo,
      StressRepository? stressRepo,
      MorningRepository? morningRepo,
      EveningRepository? eveningRepo})
      : _dailyRepo = dailyRepo,
        _stressRepo = stressRepo ?? StressRepository(),
        _morningRepo = morningRepo ?? MorningRepository(),
        _eveningRepo = eveningRepo ?? EveningRepository();

  List<Experiment> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  String? get error => _error;

  Experiment? get activeExperiment {
    for (final e in _items) {
      if (e.status == ExperimentStatus.active) return e;
    }
    return null;
  }

  /// Completed + abandoned archive, newest first.
  List<Experiment> get history => _items
      .where((e) =>
          e.status == ExperimentStatus.completed ||
          e.status == ExperimentStatus.abandoned)
      .toList();

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    final res = await _repo.getAll();
    res.fold(
      onSuccess: (list) => _items = list,
      onFailure: (e) => _error = e.message,
    );
    _loading = false;
    notifyListeners();
    await _autoCompleteOverdue();
  }

  /// Completes active experiments whose end date has passed.
  Future<void> _autoCompleteOverdue() async {
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _items.length; i++) {
      final e = _items[i];
      if (e.status == ExperimentStatus.active &&
          e.endDate != null &&
          now.isAfter(DateTime(
              e.endDate!.year, e.endDate!.month, e.endDate!.day, 23, 59))) {
        final updated = e.copyWith(status: ExperimentStatus.completed);
        final res = await _repo.save(updated);
        res.fold(
          onSuccess: (s) {
            _items[i] = s;
            changed = true;
          },
          onFailure: (_) {},
        );
      }
    }
    if (changed) notifyListeners();
  }

  /// Starts a template experiment after user confirmation.
  /// Returns false with an error when another experiment is active.
  Future<bool> startTemplate(ExperimentTemplate template) async {
    if (activeExperiment != null) {
      _error =
          'Finish or abandon "${activeExperiment!.title}" before starting a new experiment. Only one runs at a time.';
      notifyListeners();
      return false;
    }
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final exp = Experiment(
      id: generateId(),
      templateId: template.id,
      title: template.title,
      description: template.explanation,
      targetMetric: template.targetMetric,
      durationDays: template.durationDays,
      startDate: start,
      endDate: start.add(Duration(days: template.durationDays - 1)),
      status: ExperimentStatus.active,
      createdAt: now,
      updatedAt: now,
    );
    final res = await _repo.save(exp);
    return res.fold(
      onSuccess: (s) {
        _items = [s, ..._items];
        _error = null;
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

  /// DONE for today (toggles off if already done → corrects accidents).
  /// Persists immediately.
  Future<bool> checkInDone(Experiment exp) async {
    final updated = toggleDone(exp, DateTime.now());
    return _persistCheckIn(updated);
  }

  /// Explicit MISSED for today (toggles off if already missed).
  Future<bool> checkInMissed(Experiment exp) async {
    final updated = toggleMissed(exp, DateTime.now());
    return _persistCheckIn(updated);
  }

  Future<bool> _persistCheckIn(Experiment updated) async {
    final res = await _repo.save(updated);
    return res.fold(
      onSuccess: (s) {
        final i = _items.indexWhere((e) => e.id == s.id);
        if (i >= 0) _items[i] = s;
        _error = null;
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

  Future<bool> abandon(String id) async {
    final i = _items.indexWhere((e) => e.id == id);
    if (i < 0) return false;
    final updated = _items[i].copyWith(status: ExperimentStatus.abandoned);
    final res = await _repo.save(updated);
    return res.fold(
      onSuccess: (s) {
        _items[i] = s;
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

  Future<bool> completeNow(String id) async {
    final i = _items.indexWhere((e) => e.id == id);
    if (i < 0) return false;
    final updated = _items[i].copyWith(status: ExperimentStatus.completed);
    final res = await _repo.save(updated);
    return res.fold(
      onSuccess: (s) {
        _items[i] = s;
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

  Future<bool> save(Experiment exp) async {
    final res = await _repo.save(exp);
    return res.fold(
      onSuccess: (_) {
        load();
        return true;
      },
      onFailure: (e) {
        _error = e.message;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> remove(String id) async {
    final res = await _repo.delete(id);
    return res.fold(
      onSuccess: (_) {
        _items.removeWhere((e) => e.id == id);
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

  // --- Data-backed computations ---

  Future<List<DailyHealthEntry>> _entriesFor(Experiment exp) async {
    final repo = _dailyRepo;
    if (repo == null || exp.startDate == null) return const [];
    final start = DateTime(exp.startDate!.year, exp.startDate!.month,
        exp.startDate!.day);
    final res = await repo.getRange(
        start.subtract(const Duration(days: 7)), DateTime.now());
    return res.fold(onSuccess: (l) => l, onFailure: (_) => const []);
  }

  Future<BaselineComparison?> baselineFor(Experiment exp) async {
    if (_dailyRepo == null) return null;
    final entries = await _entriesFor(exp);
    return compareBaseline(exp: exp, entries: entries, now: DateTime.now());
  }

  Future<ExperimentResults?> resultsFor(Experiment exp) async {
    final entries = await _entriesFor(exp);
    return buildResults(exp: exp, entries: entries, now: DateTime.now());
  }

  /// Starts a generator-approved experiment. The user must explicitly
  /// approve (the Lab shows a full approval sheet first) — this method is
  /// only called from that approval action and never automatically.
  /// Measurement reuses the existing system via [GeneratedExperiment.templateId];
  /// no second experiment database is created.
  Future<bool> startGenerated(GeneratedExperiment gen) async {
    if (activeExperiment != null) {
      _error =
          'Finish or abandon "${activeExperiment!.title}" before starting a new experiment. Only one runs at a time.';
      notifyListeners();
      return false;
    }
    final template = templateById(gen.templateId);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final exp = Experiment(
      id: generateId(),
      templateId: gen.templateId,
      title: gen.title,
      description:
          '${gen.observation} ${gen.hypothesis} Action: ${gen.action} Success: ${gen.successCriteria}',
      targetMetric: template?.targetMetric ?? gen.metric.name,
      durationDays: gen.durationDays,
      startDate: start,
      endDate: start.add(Duration(days: gen.durationDays - 1)),
      status: ExperimentStatus.active,
      createdAt: now,
      updatedAt: now,
    );
    final res = await _repo.save(exp);
    return res.fold(
      onSuccess: (s) {
        _items = [s, ..._items];
        _error = null;
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

  /// Builds a personal generator run from goals, health history, check-in
  /// habits, wellness trends, pattern-engine observations and previous
  /// experiments. Pure generation — nothing is started as a side effect.
  Future<GeneratorOutput> generatePersonalized({
    UserProfile? profile,
    ExperimentPhraser phraser = const DeterministicPhraser(),
  }) async {
    final repo = _dailyRepo;
    if (repo == null) {
      return const GeneratorOutput(
          suggestions: [], loggedDays: 0, insufficientReason: 'Health history is unavailable right now.');
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = today.subtract(const Duration(days: 13));
    final entries = (await repo.getRange(from, now)).fold(
      onSuccess: (l) => l,
      onFailure: (_) => const <DailyHealthEntry>[],
    );

    final calmByDate = <String, double>{};
    final stressRes = await _stressRepo.getRange(from, now);
    stressRes.fold(
      onSuccess: (checks) {
        final moods = <String, List<int>>{};
        for (final c in checks) {
          moods.putIfAbsent(c.date, () => []).add(c.mood.score);
        }
        for (final k in moods.keys) {
          calmByDate[k] =
              (moods[k]!.reduce((a, b) => a + b) / moods[k]!.length) /
                  5 *
                  100;
        }
      },
      onFailure: (_) {},
    );

    final morningByDate = <String, MorningCheckIn>{};
    final eveningByDate = <String, EveningReflection>{};
    for (var i = 0; i < 14; i++) {
      final d = today.subtract(Duration(days: i));
      final key =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      // Check-ins load for every day in the window: habits live there even
      // on days without Today logs.
      final m = await _morningRepo.getByDate(key);
      m.fold(
        onSuccess: (v) {
          if (v != null) morningByDate[key] = v;
        },
        onFailure: (_) {},
      );
      final e = await _eveningRepo.getByDate(key);
      e.fold(
        onSuccess: (v) {
          if (v != null) eveningByDate[key] = v;
        },
        onFailure: (_) {},
      );
    }

    // Pattern-engine observations over the trailing week (read by the UI
    // from the output's data summary; generation itself is deterministic).
    observationsForGenerator(
      last7: entries
          .where((e) =>
              !DateTime.parse(e.date)
                  .isBefore(today.subtract(const Duration(days: 6))))
          .toList(),
      calmByDate: calmByDate,
    );

    return generateExperiments(
      GeneratorInput(
        recent: entries,
        calmByDate: calmByDate,
        morningByDate: morningByDate,
        eveningByDate: eveningByDate,
        previous: _items,
        now: now,
        profile: profile,
      ),
      phraser: phraser,
    );
  }

  Future<List<ExperimentRecommendation>> recommendations() async {
    final repo = _dailyRepo;
    if (repo == null) return const [];
    final now = DateTime.now();
    final res = await repo.getRange(
        now.subtract(const Duration(days: 6)), now);
    return res.fold(
      onSuccess: (list) => recommend(last7: list),
      onFailure: (_) => const [],
    );
  }
}
