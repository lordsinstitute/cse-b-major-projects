import 'package:health/health.dart';

import '../../data/models/health_import.dart';

/// Test seam for the platform health store. Production talks to Health
/// Connect; tests inject fakes (denied, empty, populated, unavailable).
abstract class HealthGateway {
  Future<bool> isAvailable();
  Future<bool> hasAccess();
  Future<bool> requestAccess();
  Future<void> revokeAccess();
  Future<List<ImportedPoint>> fetch(
      {required DateTime from, required DateTime to});
}

/// Read-only Health Connect access. Only the four metrics SoulCare uses
/// are ever requested; syncs stay within the platform's 30-day window.
class HealthConnectGateway implements HealthGateway {
  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.WORKOUT,
    HealthDataType.HEART_RATE,
  ];

  final Health _health = Health();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _health.isHealthConnectAvailable();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> hasAccess() async {
    try {
      return await _health.hasPermissions(
            _types,
            permissions: List.filled(
                _types.length, HealthDataAccess.READ),
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestAccess() async {
    try {
      return await _health.requestAuthorization(
        _types,
        permissions:
            List.filled(_types.length, HealthDataAccess.READ),
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> revokeAccess() async {
    try {
      await _health.revokePermissions();
    } catch (_) {}
  }

  @override
  Future<List<ImportedPoint>> fetch(
      {required DateTime from, required DateTime to}) async {
    final points = await _health.getHealthDataFromTypes(
      types: _types,
      startTime: from,
      endTime: to,
    );
    final now = DateTime.now();
    final out = <ImportedPoint>[];
    for (final p in points) {
      final mapped = _map(p, now);
      if (mapped != null) out.add(mapped);
    }
    return out;
  }

  /// Maps one platform record, preserving source + timestamps.
  /// Unparseable records are skipped (never fabricated).
  static ImportedPoint? _map(HealthDataPoint p, DateTime now) {
    try {
      final base =
          '${p.uuid}|${p.sourceId}|${p.dateFrom.toIso8601String()}';
      switch (p.type) {
        case HealthDataType.SLEEP_ASLEEP:
          final min = _num(p);
          if (min == null || min <= 0) return null;
          // Attribute overnight sleep to the wake day.
          final day = p.dateTo;
          return ImportedPoint(
            id: 'sleep|$base',
            metric: ImportMetric.sleepHours,
            dateKey: _key(day),
            value: min / 60,
            unit: 'h',
            sourceName: p.sourceName,
            sourceId: p.sourceId,
            measuredFrom: p.dateFrom,
            measuredTo: p.dateTo,
            importedAt: now,
          );
        case HealthDataType.STEPS:
          final steps = _num(p);
          if (steps == null || steps <= 0) return null;
          return ImportedPoint(
            id: 'steps|$base',
            metric: ImportMetric.steps,
            dateKey: _key(p.dateFrom),
            value: steps,
            unit: '',
            sourceName: p.sourceName,
            sourceId: p.sourceId,
            measuredFrom: p.dateFrom,
            measuredTo: p.dateTo,
            importedAt: now,
          );
        case HealthDataType.WORKOUT:
          final mins = p.dateTo
              .difference(p.dateFrom)
              .inMinutes
              .toDouble();
          if (mins <= 0) return null;
          return ImportedPoint(
            id: 'workout|$base',
            metric: ImportMetric.exerciseMin,
            dateKey: _key(p.dateFrom),
            value: mins,
            unit: ' min',
            sourceName: p.sourceName,
            sourceId: p.sourceId,
            measuredFrom: p.dateFrom,
            measuredTo: p.dateTo,
            importedAt: now,
          );
        case HealthDataType.HEART_RATE:
          final bpm = _num(p);
          if (bpm == null || bpm <= 0) return null;
          return ImportedPoint(
            id: 'hr|$base',
            metric: ImportMetric.heartRate,
            dateKey: _key(p.dateFrom),
            value: bpm,
            unit: ' bpm',
            sourceName: p.sourceName,
            sourceId: p.sourceId,
            measuredFrom: p.dateFrom,
            measuredTo: p.dateTo,
            importedAt: now,
          );
        default:
          return null; // never requested; ignore defensively
      }
    } catch (_) {
      return null;
    }
  }

  static double? _num(HealthDataPoint p) {
    final v = p.value;
    if (v is NumericHealthValue) return v.numericValue.toDouble();
    return null;
  }

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Always-unavailable gateway (unsupported devices; default in tests
/// where platform channels have no implementation).
class UnavailableHealthGateway implements HealthGateway {
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<bool> hasAccess() async => false;
  @override
  Future<bool> requestAccess() async => false;
  @override
  Future<void> revokeAccess() async {}
  @override
  Future<List<ImportedPoint>> fetch(
          {required DateTime from, required DateTime to}) async =>
      const [];
}
