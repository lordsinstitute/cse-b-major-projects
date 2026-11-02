/// Metrics SoulCare actually imports (a small subset of what the
/// platform offers — nothing more is ever requested).
enum ImportMetric { sleepHours, steps, exerciseMin, heartRate }

extension ImportMetricX on ImportMetric {
  String get label {
    switch (this) {
      case ImportMetric.sleepHours:
        return 'Sleep';
      case ImportMetric.steps:
        return 'Steps';
      case ImportMetric.exerciseMin:
        return 'Exercise';
      case ImportMetric.heartRate:
        return 'Heart rate';
    }
  }

  static ImportMetric? fromName(String? name) {
    switch (name) {
      case 'sleepHours':
        return ImportMetric.sleepHours;
      case 'steps':
        return ImportMetric.steps;
      case 'exerciseMin':
        return ImportMetric.exerciseMin;
      case 'heartRate':
        return ImportMetric.heartRate;
      default:
        return null;
    }
  }
}

/// One imported measurement. Carries its provenance: source app, original
/// timestamps, and metric type. Stored locally, never uploaded.
class ImportedPoint {
  /// Stable platform identifier (uuid + source) — the dedupe key.
  final String id;
  final ImportMetric metric;
  final String dateKey; // yyyy-MM-dd (attribution day, see gateway)
  final double value;
  final String unit;
  final String sourceName;
  final String sourceId;
  final DateTime measuredFrom;
  final DateTime measuredTo;
  final DateTime importedAt;

  const ImportedPoint({
    required this.id,
    required this.metric,
    required this.dateKey,
    required this.value,
    required this.unit,
    required this.sourceName,
    required this.sourceId,
    required this.measuredFrom,
    required this.measuredTo,
    required this.importedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'metric': metric.name,
        'dateKey': dateKey,
        'value': value,
        'unit': unit,
        'sourceName': sourceName,
        'sourceId': sourceId,
        'measuredFrom': measuredFrom.toIso8601String(),
        'measuredTo': measuredTo.toIso8601String(),
        'importedAt': importedAt.toIso8601String(),
      };

  factory ImportedPoint.fromJson(Map<String, dynamic> json) {
    final metric =
        ImportMetricX.fromName(json['metric'] as String?);
    if (metric == null) {
      throw const FormatException('unknown metric');
    }
    return ImportedPoint(
      id: json['id'] as String,
      metric: metric,
      dateKey: json['dateKey'] as String,
      value: (json['value'] as num).toDouble(),
      unit: json['unit'] as String? ?? '',
      sourceName: json['sourceName'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      measuredFrom:
          DateTime.parse(json['measuredFrom'] as String),
      measuredTo: DateTime.parse(json['measuredTo'] as String),
      importedAt: DateTime.tryParse(
              json['importedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Per-day totals derived from imported points (display only).
class ImportedDay {
  final double sleepHours;
  final int steps;
  final int exerciseMin;
  final double? heartRateAvg;
  final Set<String> sources;

  const ImportedDay({
    this.sleepHours = 0,
    this.steps = 0,
    this.exerciseMin = 0,
    this.heartRateAvg,
    this.sources = const {},
  });

  bool get hasAny =>
      sleepHours > 0 ||
      steps > 0 ||
      exerciseMin > 0 ||
      heartRateAvg != null;
}
