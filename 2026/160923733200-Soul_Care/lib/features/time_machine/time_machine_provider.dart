import 'package:flutter/material.dart';

import '../../core/utils/utils.dart';
import '../../data/local/local_database.dart';
import '../../data/models/checkins.dart';
import '../../data/models/enums.dart';
import '../../data/models/journal.dart';
import '../../data/models/models.dart';
import '../../data/repositories/checkin_repository.dart';
import '../../data/repositories/daily_health_repository.dart';
import '../../data/repositories/experiment_repository.dart';
import '../../data/repositories/journal_repository.dart';
import '../../data/repositories/medical_document_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/stress_repository.dart';
import 'time_machine_engine.dart';

/// Day / week / month replay granularity.
enum PeriodMode { day, week, month }

/// Time Machine state. Lazy by design:
///
/// - The timeline index is built from Hive KEYS only (no record bodies).
/// - Experiments, journals and document metadata are small collections and
///   load once (journal bodies stay inside their entries and are only read
///   when their date is opened).
/// - Daily/mood/check-in values load per calendar month on demand
///   ([ensureMonth]) and are cached; months the user never opens are never
///   read. Goal-reached markers are (re)computed from cached months and
///   merged in as months load.
class TimeMachineProvider extends ChangeNotifier {
  final DailyHealthRepository _dailyRepo;
  final StressRepository _stressRepo;
  final MorningRepository _morningRepo;
  final EveningRepository _eveningRepo;
  final ExperimentRepository _expRepo;
  final JournalRepository _journalRepo;
  final MedicalDocumentRepository _docRepo;
  final ProfileRepository _profileRepo;

  TimeMachineProvider({
    DailyHealthRepository? dailyRepo,
    StressRepository? stressRepo,
    MorningRepository? morningRepo,
    EveningRepository? eveningRepo,
    ExperimentRepository? experimentRepo,
    JournalRepository? journalRepo,
    MedicalDocumentRepository? docRepo,
    ProfileRepository? profileRepo,
  })  : _dailyRepo = dailyRepo ?? DailyHealthRepository(),
        _stressRepo = stressRepo ?? StressRepository(),
        _morningRepo = morningRepo ?? MorningRepository(),
        _eveningRepo = eveningRepo ?? EveningRepository(),
        _expRepo = experimentRepo ?? ExperimentRepository(),
        _journalRepo = journalRepo ?? const JournalRepository(),
        _docRepo = docRepo ?? MedicalDocumentRepository(),
        _profileRepo = profileRepo ?? ProfileRepository();

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  bool _indexed = false;
  bool get indexed => _indexed;

  /// All dates with any logged data or event, ascending.
  List<DateTime> _availableDays = const [];
  List<DateTime> get availableDays => _availableDays;

  List<TimeEvent> _events = const [];
  List<TimeEvent> get events => _events;

  Map<String, List<TimeEvent>> _eventsByDate = const {};
  Map<String, List<TimeEvent>> get eventsByDate => _eventsByDate;

  // Month-granular value caches (key: 'yyyy-MM').
  final Map<String, DailyHealthEntry> _daily = {};
  final Map<String, List<int>> _moods = {};
  final Map<String, MorningCheckIn> _morning = {};
  final Map<String, EveningReflection> _evening = {};
  final Map<String, List<JournalEntry>> _journalsByDate = {};
  List<Experiment> _experiments = const [];
  List<MedicalDocument> _documents = const [];
  final Set<String> _loadedMonths = {};

  double _sleepTarget = 7.5;
  double _exerciseTarget = 150;
  double _waterTarget = 8;
  double _meditationTarget = 10;

  static String _monthKey(int year, int month) =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  /// Builds the timeline index from storage keys + small collections.
  Future<void> loadIndex() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final prof = await _profileRepo.load();
      prof.fold(
        onSuccess: (p) {
          _sleepTarget = p.sleepGoal;
          _exerciseTarget = p.exerciseGoalWeek.toDouble();
          _waterTarget = p.waterGoal.toDouble();
          _meditationTarget = p.meditationGoal.toDouble();
        },
        onFailure: (_) {},
      );

      final exps = await _expRepo.getAll();
      _experiments = exps.fold(
        onSuccess: (v) => v,
        onFailure: (_) => <Experiment>[],
      );
      final journals = (await _journalRepo.getAll()).fold(
        onSuccess: (v) => v,
        onFailure: (_) => <JournalEntry>[],
      );
      final docs = (await _docRepo.getAll()).fold(
        onSuccess: (v) => v,
        onFailure: (_) => <MedicalDocument>[],
      );
      _documents = docs;

      _journalsByDate.clear();
      for (final j in journals) {
        _journalsByDate.putIfAbsent(j.date, () => []).add(j);
      }

      // Keys only — no record bodies are read here.
      final dailyKeys = _boxKeys(LocalDatabase.dailyBoxName);
      final morningKeys = _boxKeys(LocalDatabase.morningBoxName);
      final eveningKeys = _boxKeys(LocalDatabase.eveningBoxName);

      final daySet = <DateTime>{};
      for (final k in {...dailyKeys, ...morningKeys, ...eveningKeys}) {
        final d = DateTime.tryParse(k);
        if (d != null) daySet.add(DateTime(d.year, d.month, d.day));
      }
      for (final e in _experiments) {
        if (e.startDate != null) {
          final s = e.startDate!;
          daySet.add(DateTime(s.year, s.month, s.day));
        }
        for (final c in [...e.checkIns, ...e.missedDays]) {
          final d = DateTime.tryParse(c);
          if (d != null) daySet.add(DateTime(d.year, d.month, d.day));
        }
      }
      for (final j in journals) {
        final d = DateTime.tryParse(j.date);
        if (d != null) daySet.add(DateTime(d.year, d.month, d.day));
      }
      for (final d in docs) {
        final w = d.documentDate ?? d.importedAt;
        daySet.add(DateTime(w.year, w.month, w.day));
      }

      final sorted = daySet.toList()..sort();
      _availableDays = sorted;

      // Base events need no daily values (streaks from keys; the goal pass
      // runs against the value cache, empty at first — markers merge in as
      // months load).
      _rebuildEvents(dailyKeys);
      _indexed = true;
    } catch (_) {
      _error = 'Could not read your history index. Please try again.';
    }
    _loading = false;
    notifyListeners();
  }

  Set<String> _boxKeys(String name) {
    try {
      if (name == LocalDatabase.dailyBoxName) {
        return LocalDatabase.dailyBox.keys.map((e) => e.toString()).toSet();
      }
      if (name == LocalDatabase.morningBoxName) {
        return LocalDatabase.morningBox.keys.map((e) => e.toString()).toSet();
      }
      if (name == LocalDatabase.eveningBoxName) {
        return LocalDatabase.eveningBox.keys.map((e) => e.toString()).toSet();
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  void _rebuildEvents(Set<String> dailyKeys) {
    final base = collectEvents(
      dailyKeys: dailyKeys.isEmpty
          ? _daily.keys.toSet()
          : {...dailyKeys, ..._daily.keys},
      dailyByDate: _daily,
      experiments: _experiments,
      journals: [
        for (final list in _journalsByDate.values) ...list,
      ],
      documents: _documents,
      sleepTarget: _sleepTarget,
      exerciseTarget: _exerciseTarget,
      waterTarget: _waterTarget,
      meditationTarget: _meditationTarget,
    );
    _events = base;
    final map = <String, List<TimeEvent>>{};
    for (final e in base) {
      map.putIfAbsent(e.dateKey, () => []).add(e);
    }
    _eventsByDate = map;
  }

  /// Loads one calendar month of values (cached; repeat calls are free).
  Future<void> ensureMonth(int year, int month) async {
    final mk = _monthKey(year, month);
    if (_loadedMonths.contains(mk)) return;
    _loadedMonths.add(mk); // mark early: failures still leave index usable
    try {
      final first = DateTime(year, month, 1);
      final last = DateTime(year, month + 1, 0);
      final dailyRes = await _dailyRepo.getRange(first, last);
      dailyRes.fold(
        onSuccess: (list) {
          for (final e in list) {
            _daily[e.date] = e;
          }
        },
        onFailure: (_) {},
      );
      final stressRes = await _stressRepo.getRange(first, last);
      stressRes.fold(
        onSuccess: (list) {
          for (final s in list) {
            _moods.putIfAbsent(s.date, () => []).add(s.mood.score);
          }
        },
        onFailure: (_) {},
      );
      var d = first;
      while (!d.isAfter(last)) {
        final key = formatDateForStorage(d);
        final m = await _morningRepo.getByDate(key);
        m.fold(
          onSuccess: (v) {
            if (v != null) _morning[key] = v;
          },
          onFailure: (_) {},
        );
        final e = await _eveningRepo.getByDate(key);
        e.fold(
          onSuccess: (v) {
            if (v != null) _evening[key] = v;
          },
          onFailure: (_) {},
        );
        d = d.add(const Duration(days: 1));
      }
      // Merge newly-discoverable goal markers from cached values.
      _rebuildEvents({});
      notifyListeners();
    } catch (_) {
      // Month values stay missing; day views report honestly.
    }
  }

  /// Day replay from cache (ensure the month is loaded first).
  DayReplay dayReplay(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return buildDayReplay(
      date: day,
      dailyByDate: _daily,
      stressMoodsByDate: _moods,
      morningByDate: _morning,
      eveningByDate: _evening,
      experiments: _experiments,
      journalsByDate: _journalsByDate,
    );
  }

  /// Period replays: day (1), week (7 ending anchor), month (calendar).
  List<DayReplay> periodReplays(DateTime anchor, PeriodMode mode) {
    final a = DateTime(anchor.year, anchor.month, anchor.day);
    final List<DateTime> dates;
    switch (mode) {
      case PeriodMode.day:
        dates = [a];
        break;
      case PeriodMode.week:
        dates = [
          for (var i = 6; i >= 0; i--) a.subtract(Duration(days: i)),
        ];
        break;
      case PeriodMode.month:
        final first = DateTime(a.year, a.month, 1);
        final count = DateTime(a.year, a.month + 1, 0).day;
        dates = [
          for (var i = 0; i < count; i++)
            first.add(Duration(days: i)),
        ];
        break;
    }
    return [for (final d in dates) dayReplay(d)];
  }
}
