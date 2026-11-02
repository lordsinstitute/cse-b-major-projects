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
import '../../data/repositories/stress_repository.dart';
import 'calendar_engine.dart';

/// Calendar state. Performance by design:
///
/// - Month data loads per-month on demand ([ensureMonth]) and is cached;
///   switching months never re-queries loaded months and never scans the
///   whole database.
/// - Heatmaps read Hive KEYS only (no record bodies) and are cached per
///   window (30/90/365).
/// - Experiments, journal and document metadata are small collections that
///   load once for counts/markers.
class CalendarProvider extends ChangeNotifier {
  final DailyHealthRepository _dailyRepo;
  final StressRepository _stressRepo;
  final MorningRepository _morningRepo;
  final EveningRepository _eveningRepo;
  final ExperimentRepository _expRepo;
  final JournalRepository _journalRepo;
  final MedicalDocumentRepository _docRepo;

  CalendarProvider({
    DailyHealthRepository? dailyRepo,
    StressRepository? stressRepo,
    MorningRepository? morningRepo,
    EveningRepository? eveningRepo,
    ExperimentRepository? experimentRepo,
    JournalRepository? journalRepo,
    MedicalDocumentRepository? docRepo,
  })  : _dailyRepo = dailyRepo ?? DailyHealthRepository(),
        _stressRepo = stressRepo ?? StressRepository(),
        _morningRepo = morningRepo ?? MorningRepository(),
        _eveningRepo = eveningRepo ?? EveningRepository(),
        _expRepo = experimentRepo ?? ExperimentRepository(),
        _journalRepo = journalRepo ?? const JournalRepository(),
        _docRepo = docRepo ?? MedicalDocumentRepository();

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  final Map<String, List<CalendarDay>> _months = {};
  final Map<String, MonthSummary> _summaries = {};
  final Map<int, Map<String, int>> _heat = {};
  List<Experiment> _experiments = const [];
  bool _metaLoaded = false;

  static String monthKey(int year, int month) =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  List<CalendarDay> month(int year, int month) =>
      _months[monthKey(year, month)] ?? const [];

  MonthSummary? summary(int year, int month) =>
      _summaries[monthKey(year, month)];

  List<Experiment> get experiments => _experiments;

  Map<String, int> heat(int windowDays) =>
      _heat[windowDays] ?? const {};

  Future<void> _ensureMeta() async {
    if (_metaLoaded) return;
    _metaLoaded = true;
    _experiments = (await _expRepo.getAll()).fold(
      onSuccess: (l) => l,
      onFailure: (_) => const <Experiment>[],
    );
    final journals = (await _journalRepo.getAll()).fold(
      onSuccess: (l) => l,
      onFailure: (_) => const <JournalEntry>[],
    );
    // Rebuild in one pass (clear-then-fill keeps restarts consistent).
    final counts = <String, int>{};
    for (final j in journals) {
      counts[j.date] = (counts[j.date] ?? 0) + 1;
    }
    _journalCounts = counts;
    final docs = (await _docRepo.getAll()).fold(
      onSuccess: (l) => l,
      onFailure: (_) => const <MedicalDocument>[],
    );
    final dcounts = <String, int>{};
    for (final d in docs) {
      final w = d.documentDate ?? d.importedAt;
      final k = formatDateForStorage(w);
      dcounts[k] = (dcounts[k] ?? 0) + 1;
    }
    _docCounts = dcounts;
    notifyListeners();
  }

  Map<String, int> _journalCounts = {};
  Map<String, int> _docCounts = {};

  /// Test seam: installs prebuilt month data (built by the pure engine, no
  /// storage I/O) so widget tests stay hermetic on machines where Hive
  /// file reads stall intermittently.
  @visibleForTesting
  void seedForTest({
    required int year,
    required int month,
    required List<CalendarDay> grid,
    Map<String, int>? heat90,
  }) {
    final mk = monthKey(year, month);
    _months[mk] = grid;
    _summaries[mk] = summarizeMonth(
      year: year,
      month: month,
      days: grid,
      experiments: _experiments,
    );
    _metaLoaded = true;
    if (heat90 != null) _heat[90] = heat90;
    notifyListeners();
  }

  /// Loads one month (cached; repeat calls are free).
  Future<void> ensureMonth(int year, int month) async {
    await _ensureMeta();
    final mk = monthKey(year, month);
    if (_months.containsKey(mk)) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final first = DateTime(year, month, 1);
      final last = DateTime(year, month + 1, 0);

      final dailyByDate = <String, DailyHealthEntry>{};
      (await _dailyRepo.getRange(first, last)).fold(
        onSuccess: (list) {
          for (final e in list) {
            dailyByDate[e.date] = e;
          }
        },
        onFailure: (_) {},
      );

      final moods = <String, List<int>>{};
      (await _stressRepo.getRange(first, last)).fold(
        onSuccess: (list) {
          for (final s in list) {
            moods.putIfAbsent(s.date, () => []).add(s.mood.score);
          }
        },
        onFailure: (_) {},
      );
      final calmByDate = <String, double>{
        for (final k in moods.keys)
          k: (moods[k]!.reduce((a, b) => a + b) / moods[k]!.length) /
              5 *
              100,
      };

      final morningByDate = <String, MorningCheckIn>{};
      final eveningByDate = <String, EveningReflection>{};
      final moodSources = <String, List<int>>{};
      var d = first;
      while (!d.isAfter(last)) {
        final key = formatDateForStorage(d);
        final m = await _morningRepo.getByDate(key);
        m.fold(
          onSuccess: (v) {
            if (v != null) {
              morningByDate[key] = v;
              moodSources.putIfAbsent(key, () => []).add(v.mood);
            }
          },
          onFailure: (_) {},
        );
        final e = await _eveningRepo.getByDate(key);
        e.fold(
          onSuccess: (v) {
            if (v != null) {
              eveningByDate[key] = v;
              moodSources.putIfAbsent(key, () => []).add(v.mood);
            }
          },
          onFailure: (_) {},
        );
        if (moods[key] != null) {
          moodSources.putIfAbsent(key, () => []).addAll(moods[key]!);
        }
        d = d.add(const Duration(days: 1));
      }

      final grid = buildMonthGrid(
        year: year,
        month: month,
        dailyByDate: dailyByDate,
        calmByDate: calmByDate,
        moodSourcesByDate: moodSources,
        morningByDate: morningByDate,
        eveningByDate: eveningByDate,
        experiments: _experiments,
        journalCountByDate: _journalCounts,
        documentCountByDate: _docCounts,
      );
      _months[mk] = grid;
      _summaries[mk] = summarizeMonth(
        year: year,
        month: month,
        days: grid,
        experiments: _experiments,
      );
    } catch (_) {
      _error = 'Could not load this month. Please try again.';
    }
    _loading = false;
    notifyListeners();
  }

  /// GitHub-style consistency levels for trailing [windowDays] (cached).
  /// Key-based only: daily keys count double, morning/evening single.
  Future<Map<String, int>> ensureHeat(int windowDays) async {
    if (_heat.containsKey(windowDays)) return _heat[windowDays]!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    Set<String> keys(String box) {
      try {
        if (box == LocalDatabase.dailyBoxName) {
          return LocalDatabase.dailyBox.keys
              .map((e) => e.toString())
              .toSet();
        }
        if (box == LocalDatabase.morningBoxName) {
          return LocalDatabase.morningBox.keys
              .map((e) => e.toString())
              .toSet();
        }
        if (box == LocalDatabase.eveningBoxName) {
          return LocalDatabase.eveningBox.keys
              .map((e) => e.toString())
              .toSet();
        }
        return {};
      } catch (_) {
        return {};
      }
    }

    final daily = keys(LocalDatabase.dailyBoxName);
    final morning = keys(LocalDatabase.morningBoxName);
    final evening = keys(LocalDatabase.eveningBoxName);
    final out = <String, int>{};
    for (var i = 0; i < windowDays; i++) {
      final k = formatDateForStorage(
          today.subtract(Duration(days: i)));
      out[k] = consistencyLevel(
        hasEntry: daily.contains(k),
        hasMorning: morning.contains(k),
        hasEvening: evening.contains(k),
        hasStress: false,
      );
    }
    _heat[windowDays] = out;
    notifyListeners();
    return out;
  }
}
