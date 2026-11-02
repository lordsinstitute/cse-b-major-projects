import '../../core/errors/app_exceptions.dart';
import '../local/local_database.dart';
import '../models/health_import.dart';

/// Imported health data: local copies keyed by stable platform ids.
/// Manual logs live in other boxes and are never touched here.
class HealthImportRepository {
  static const _connectedKey = '__connected';
  static const _syncedAtKey = '__syncedAt';

  Future<Result<List<ImportedPoint>>> getAll() async {
    try {
      final out = <ImportedPoint>[];
      for (final key in LocalDatabase.healthImportsBox.keys) {
        if (key == _connectedKey || key == _syncedAtKey) continue;
        final raw = LocalDatabase.healthImportsBox.get(key);
        if (raw == null) continue;
        try {
          out.add(ImportedPoint.fromJson(
              Map<String, dynamic>.from(raw as Map)));
        } catch (_) {
          // Skip unreadable rows, never crash the list.
        }
      }
      out.sort((a, b) => b.measuredTo.compareTo(a.measuredTo));
      return Success(out);
    } catch (e) {
      return Failure(PersistenceException(
          'Could not load imported data.',
          originalError: e));
    }
  }

  /// Stores points, skipping ids already present (stable-id dedupe:
  /// repeated syncs never duplicate). Returns the count of NEW records.
  Future<Result<int>> saveAll(List<ImportedPoint> points) async {
    try {
      var added = 0;
      for (final p in points) {
        if (!LocalDatabase.healthImportsBox.containsKey(p.id)) {
          await LocalDatabase.healthImportsBox.put(
              p.id, p.toJson());
          added++;
        }
      }
      return Success(added);
    } catch (e) {
      return Failure(PersistenceException(
          'Could not store imported data.',
          originalError: e));
    }
  }

  Future<Result<Map<String, ImportedDay>>> daysByDate() async {
    final res = await getAll();
    return res.fold(
      onSuccess: (points) {
        final sleep = <String, double>{};
        final steps = <String, double>{};
        final exercise = <String, double>{};
        final hrSum = <String, double>{};
        final hrCount = <String, int>{};
        final sources = <String, Set<String>>{};
        void src(String k, String s) =>
            sources.putIfAbsent(k, () => {}).add(s);
        for (final p in points) {
          switch (p.metric) {
            case ImportMetric.sleepHours:
              sleep[p.dateKey] = (sleep[p.dateKey] ?? 0) + p.value;
              src(p.dateKey, p.sourceName);
            case ImportMetric.steps:
              steps[p.dateKey] = (steps[p.dateKey] ?? 0) + p.value;
              src(p.dateKey, p.sourceName);
            case ImportMetric.exerciseMin:
              exercise[p.dateKey] =
                  (exercise[p.dateKey] ?? 0) + p.value;
              src(p.dateKey, p.sourceName);
            case ImportMetric.heartRate:
              hrSum[p.dateKey] = (hrSum[p.dateKey] ?? 0) + p.value;
              hrCount[p.dateKey] = (hrCount[p.dateKey] ?? 0) + 1;
              src(p.dateKey, p.sourceName);
          }
        }
        final keys = {
          ...sleep.keys,
          ...steps.keys,
          ...exercise.keys,
          ...hrSum.keys
        };
        return Success({
          for (final k in keys)
            k: ImportedDay(
              sleepHours: sleep[k] ?? 0,
              steps: (steps[k] ?? 0).round(),
              exerciseMin: (exercise[k] ?? 0).round(),
              heartRateAvg: hrCount[k] == null
                  ? null
                  : hrSum[k]! / hrCount[k]!,
              sources: sources[k] ?? const {},
            ),
        });
      },
      onFailure: (e) => Failure(e),
    );
  }

  Future<bool> isConnected() async {
    try {
      return LocalDatabase.healthImportsBox.get(_connectedKey) == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setConnected(bool value) async {
    try {
      await LocalDatabase.healthImportsBox.put(_connectedKey, value);
      if (value) {
        await LocalDatabase.healthImportsBox.put(
            _syncedAtKey, DateTime.now().toIso8601String());
      }
    } catch (_) {}
  }

  Future<DateTime?> lastSyncedAt() async {
    try {
      final raw =
          LocalDatabase.healthImportsBox.get(_syncedAtKey);
      return raw == null
          ? null
          : DateTime.tryParse(raw as String);
    } catch (_) {
      return null;
    }
  }

  /// Removes imported copies only. Manual logs are never touched.
  Future<Result<void>> clearImported() async {
    try {
      final keys = LocalDatabase.healthImportsBox.keys
          .where((k) => k != _connectedKey && k != _syncedAtKey)
          .toList();
      for (final k in keys) {
        await LocalDatabase.healthImportsBox.delete(k);
      }
      await LocalDatabase.healthImportsBox.put(_connectedKey, false);
      return const Success(null);
    } catch (e) {
      return Failure(PersistenceException(
          'Could not remove imported data.',
          originalError: e));
    }
  }
}
