import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/enums.dart';
import '../../data/models/journal.dart';
import '../../data/models/health_snapshot.dart';
import '../../data/models/models.dart';
import '../../data/repositories/daily_health_repository.dart';
import '../../data/repositories/experiment_repository.dart';
import '../../data/repositories/health_snapshot_repository.dart';
import '../../data/repositories/journal_repository.dart';
import '../../data/repositories/medical_document_repository.dart';
import '../../data/repositories/stress_repository.dart';
import 'report_engine.dart';

/// Reports state. Everything is computed locally from existing logs;
/// generation never uploads anything.
class ReportsController extends ChangeNotifier {
  final DailyHealthRepository _daily;
  final StressRepository _stress;
  final ExperimentRepository _experiments;
  final JournalRepository _journal;
  final MedicalDocumentRepository _documents;
  final HealthSnapshotRepository _snapshots;

  WeeklyReport? _current;
  WeeklyReport? _previous;
  MonthlyReport? _monthly;
  bool _loading = true;
  String? _error;

  ReportsController({
    DailyHealthRepository? daily,
    StressRepository? stress,
    ExperimentRepository? experiments,
    JournalRepository? journal,
    MedicalDocumentRepository? documents,
    HealthSnapshotRepository? snapshots,
  })  : _daily = daily ?? DailyHealthRepository(),
        _stress = stress ?? StressRepository(),
        _experiments = experiments ?? ExperimentRepository(),
        _journal = journal ?? JournalRepository(),
        _documents = documents ?? MedicalDocumentRepository(),
        _snapshots = snapshots ?? HealthSnapshotRepository() {
    load();
  }

  WeeklyReport? get current => _current;
  WeeklyReport? get previous => _previous;
  MonthlyReport? get monthly => _monthly;
  bool get loading => _loading;
  String? get error => _error;

  List<MetricDelta> get comparison => (_current == null ||
          _previous == null)
      ? const []
      : compareWeeks(_current!, _previous!);

  String get summary =>
      (_current == null || _previous == null)
          ? 'Log at least $minDaysForReport days in each of the last two weeks for a comparison.'
          : summarizeWeeks(_current!, _previous!);

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final wide = today.subtract(const Duration(days: 60));

      final entries = (await _daily.getRange(wide, now)).fold(
          onSuccess: (l) => l, onFailure: (_) => const <DailyHealthEntry>[]);
      final checks = (await _stress.getRange(wide, now)).fold(
          onSuccess: (l) => l, onFailure: (_) => const <StressEntry>[]);
      final byDate = <String, List<int>>{};
      for (final c in checks) {
        byDate.putIfAbsent(c.date, () => []).add(c.mood.score);
      }
      final calm = <String, double>{
        for (final k in byDate.keys)
          k: ((byDate[k]!.reduce((a, b) => a + b) /
                      byDate[k]!.length /
                      5 *
                      100)
                  .clamp(0, 100))
              .toDouble(),
      };

      List<DailyHealthEntry> inRange(DateTime from, DateTime to) {
        final out = <DailyHealthEntry>[];
        for (final e in entries) {
          final d = DateTime.tryParse(e.date);
          if (d == null) continue;
          final day = DateTime(d.year, d.month, d.day);
          if (!day.isBefore(from) && !day.isAfter(to)) out.add(e);
        }
        return out;
      }

      final curStart = today.subtract(const Duration(days: 6));
      final prevEnd = curStart.subtract(const Duration(days: 1));
      final prevStart = prevEnd.subtract(const Duration(days: 6));
      _current = buildWeekly(
        entries: inRange(curStart, today),
        calmByDate: calm,
        end: today,
        previous: inRange(prevStart, prevEnd),
      );
      final prevPrevEnd = prevStart.subtract(const Duration(days: 1));
      final prevPrevStart =
          prevPrevEnd.subtract(const Duration(days: 6));
      _previous = buildWeekly(
        entries: inRange(prevStart, prevEnd),
        calmByDate: calm,
        end: prevEnd,
        previous: inRange(prevPrevStart, prevPrevEnd),
      );

      final monthStart = today.subtract(const Duration(days: 29));
      final allExps = (await _experiments.getAll()).fold(
          onSuccess: (l) => l,
          onFailure: (_) => const <Experiment>[]);
      final overlapping = <Experiment>[];
      for (final e in allExps) {
        final s = e.startDate;
        final en = e.endDate;
        if (s != null &&
            DateTime(s.year, s.month, s.day).isAfter(today)) {
          continue;
        }
        if (en != null &&
            DateTime(en.year, en.month, en.day).isBefore(monthStart)) {
          continue;
        }
        overlapping.add(e);
      }
      final journals = (await _journal.getAll()).fold(
          onSuccess: (l) => l,
          onFailure: (_) => const <JournalEntry>[]);
      final docs = (await _documents.getAll()).fold(
          onSuccess: (l) => l,
          onFailure: (_) => const <MedicalDocument>[]);
      bool inMonth(DateTime d) =>
          !d.isBefore(monthStart) && !d.isAfter(today);
      _monthly = buildMonthly(
        entries: inRange(monthStart, today),
        calmByDate: calm,
        experiments: overlapping,
        journalCount: journals
            .where((j) =>
                DateTime.tryParse(j.date) != null &&
                inMonth(DateTime.parse(j.date)))
            .length,
        documentsAdded:
            docs.where((d) => inMonth(d.importedAt)).length,
        end: today,
      );
    } catch (_) {
      _error = 'Could not build your report. Please try again.';
    }
    _loading = false;
    notifyListeners();
  }

  /// Human-readable JSON payload (documents as references, no binaries).
  /// The health snapshot is included ONLY when [includeSnapshot] is true
  /// (explicit user opt-in at share time), via [exportJsonAsync].
  Map<String, dynamic> exportJson(
      {HealthSnapshot? snapshotForExport}) {
    Map<String, dynamic>? week(WeeklyReport? w) => w == null
        ? null
        : {
            'weekStart':
                w.weekStart.toIso8601String().split('T').first,
            'daysLogged': w.daysLogged,
            'avgWellness': w.avgWellness,
            'wellnessChange': w.wellnessChange,
            'sleepAvg': w.sleepAvg,
            'sleepConsistency': w.sleepConsistency,
            'bestSleepDay': w.bestSleepDay,
            'lowSleepDay': w.lowSleepDay,
            'exerciseTotal': w.exerciseTotal,
            'activeDays': w.activeDays,
            'waterAvg': w.waterAvg,
            'waterGoalPct': w.waterGoalPct,
            'moodAvg': w.moodAvg,
            'bestMoodDay': w.bestMoodDay,
            'lowMoodDay': w.lowMoodDay,
            'meditationTotal': w.meditationTotal,
            'screenAvg': w.screenAvg,
          };
    final m = _monthly;
    return {
      'app': 'SoulCare',
      'type': 'wellness-report',
      'generatedAt': DateTime.now().toIso8601String(),
      'note':
          'Local-first report from logged data. Illustrative only — not a medical assessment.',
      'thisWeek': week(_current),
      'lastWeek': week(_previous),
      'comparison': [
        for (final d in comparison)
          {
            'metric': d.label,
            'thisWeek': d.current,
            'lastWeek': d.previous,
            'change': d.change,
          }
      ],
      'summary': (_current != null && _previous != null)
          ? summarizeWeeks(_current!, _previous!)
          : null,
      'month': m == null
          ? null
          : {
              'daysLogged': m.daysLogged,
              'avgWellness': m.avgWellness,
              'wellnessTrend': m.wellnessTrend,
              'sleepGoalPct': m.sleepGoalPct,
              'waterGoalPct': m.waterGoalPct,
              'experimentsCompleted': m.experimentsCompleted,
              'habitCheckIns': m.habitCheckIns,
              'journalCount': m.journalCount,
              'documentsAdded': m.documentsAdded,
            },
      'healthSnapshot': snapshotForExport == null
          ? 'excluded (include only with explicit opt-in)'
          : snapshotForExport.toJson(),
    };
  }

  Future<String?> shareJson({bool includeSnapshot = false}) async {
    try {
      HealthSnapshot? snap;
      if (includeSnapshot) {
        final res = await _snapshots.load();
        snap = res.fold(
            onSuccess: (s) => s.isEmpty ? null : s,
            onFailure: (_) => null);
      }
      final dir = await _tmpDir();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = await _writeFile(
          '$dir/soulcare-report-$stamp.json',
          const JsonEncoder.withIndent('  ')
              .convert(exportJson(snapshotForExport: snap)));
      await SharePlus.instance.share(ShareParams(
        text: 'My SoulCare weekly report',
        files: [XFile(file, mimeType: 'application/json')],
      ));
      return file;
    } catch (_) {
      return null;
    }
  }
}

// --- tiny IO helpers (kept local for testability) ---
Future<String> _tmpDir() async {
  final sys = Directory.systemTemp;
  final dir = Directory('${sys.path}/soulcare_reports');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}

Future<String> _writeFile(String path, String content) async {
  final f = File(path);
  await f.writeAsString(content, flush: true);
  return path;
}
