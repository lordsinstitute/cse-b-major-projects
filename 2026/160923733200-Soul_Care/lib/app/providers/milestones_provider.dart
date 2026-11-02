import 'package:flutter/material.dart';

import '../../data/models/checkins.dart';
import '../../data/models/journal.dart';
import '../../data/models/models.dart';
import '../../data/repositories/checkin_repository.dart';
import '../../data/repositories/daily_health_repository.dart';
import '../../data/repositories/experiment_repository.dart';
import '../../data/repositories/journal_repository.dart';
import '../../data/repositories/milestone_repository.dart';
import '../../data/repositories/stress_repository.dart';
import '../../features/milestones/milestone_engine.dart';

/// Milestones state: derived from real data on every load (never manually
/// awarded), with celebrated-ids persisted so each unlock is celebrated
/// exactly once — including across restarts.
class MilestonesProvider extends ChangeNotifier {
  final DailyHealthRepository _dailyRepo;
  final StressRepository _stressRepo;
  final ExperimentRepository _expRepo;
  final JournalRepository _journalRepo;
  final EveningRepository _eveningRepo;
  final MilestoneRepository _milestoneRepo;

  MilestonesProvider({
    DailyHealthRepository? dailyRepo,
    StressRepository? stressRepo,
    ExperimentRepository? experimentRepo,
    JournalRepository? journalRepo,
    EveningRepository? eveningRepo,
    MilestoneRepository? milestoneRepo,
  })  : _dailyRepo = dailyRepo ?? DailyHealthRepository(),
        _stressRepo = stressRepo ?? StressRepository(),
        _expRepo = experimentRepo ?? ExperimentRepository(),
        _journalRepo = journalRepo ?? const JournalRepository(),
        _eveningRepo = eveningRepo ?? EveningRepository(),
        _milestoneRepo = milestoneRepo ?? MilestoneRepository();

  List<MilestoneStatus> _all = const [];
  List<MilestoneStatus> get all => _all;

  List<MilestoneStatus> get unlocked =>
      [for (final m in _all) if (m.unlocked) m];
  List<MilestoneStatus> get locked =>
      [for (final m in _all) if (!m.unlocked) m];

  MilestoneStatus? get mostRecent => mostRecentMilestone(_all);
  MilestoneStatus? get next => nextMilestone(_all);

  List<MilestoneStatus> get uncelebrated =>
      [for (final m in _all) if (m.unlocked && !m.celebrated) m];

  bool _loading = false;
  bool get loading => _loading;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      final now = DateTime.now();
      final entries = (await _dailyRepo.getRange(
        DateTime(2020, 1, 1),
        now,
      ))
          .fold(
        onSuccess: (l) => l,
        onFailure: (_) => const <DailyHealthEntry>[],
      );
      final stressDates = (await _stressRepo.getRange(
        DateTime(2020, 1, 1),
        now,
      ))
          .fold(
        onSuccess: (list) => list.map((e) => e.date).toSet(),
        onFailure: (_) => <String>{},
      );
      final experiments = (await _expRepo.getAll()).fold(
        onSuccess: (l) => l,
        onFailure: (_) => const <Experiment>[],
      );
      final journals = (await _journalRepo.getAll()).fold(
        onSuccess: (l) => l,
        onFailure: (_) => const <JournalEntry>[],
      );
      final evenings = (await _eveningRepo.getAll()).fold(
        onSuccess: (l) => l,
        onFailure: (_) => const <EveningReflection>[],
      );
      final celebrated = (await _milestoneRepo.getCelebrated()).fold(
        onSuccess: (s) => s,
        onFailure: (_) => <String>{},
      );

      final evaluated = evaluateMilestones(MilestoneInput(
        entriesByDate: {for (final e in entries) e.date: e},
        stressDates: stressDates,
        experiments: experiments,
        journals: journals,
        evenings: evenings,
        now: now,
      ));
      _all = [
        for (final m in evaluated)
          celebrated.contains(m.def.id) ? m.markCelebrated() : m,
      ];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> celebrate(String id) async {
    final current = (await _milestoneRepo.getCelebrated()).fold(
      onSuccess: (s) => Set<String>.from(s),
      onFailure: (_) => <String>{},
    );
    current.add(id);
    await _milestoneRepo.saveCelebrated(current);
    _all = [
      for (final m in _all)
        m.def.id == id ? m.markCelebrated() : m,
    ];
    notifyListeners();
  }
}
