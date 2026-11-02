import '../../core/utils/utils.dart';
import '../../data/models/models.dart';
import '../../features/experiments/experiment_engine.dart';

/// Analytics Lab engine — pure, deterministic, local-only.
///
/// A research/exploration view over the user's own historical data. Results
/// are described as observed patterns only — never medical conclusions,
/// never causal claims. Every function is null-safe and finite-safe: no
/// output is ever NaN or infinite (uncomputable results are null, and the
/// UI reports them as unavailable).

/// Minimum paired observations before a correlation is calculated.
const int kMinCorrelationPairs = 5;

/// Minimum points before anomaly detection runs.
const int kMinAnomalyPoints = 7;

/// Modified z-score threshold for flagging an unusual day.
const double kAnomalyThreshold = 3.5;

double? _fin(double v) => v.isFinite ? v : null;

double _mean(List<double> v) =>
    v.reduce((a, b) => a + b) / v.length;

/// Metrics available in the Analytics Lab.
enum AnalyticsMetric {
  wellness,
  sleep,
  stress,
  energy,
  exercise,
  screen,
  water,
}

extension AnalyticsMetricX on AnalyticsMetric {
  String get label => switch (this) {
        AnalyticsMetric.wellness => 'Wellness',
        AnalyticsMetric.sleep => 'Sleep',
        AnalyticsMetric.stress => 'Stress',
        AnalyticsMetric.energy => 'Energy',
        AnalyticsMetric.exercise => 'Exercise',
        AnalyticsMetric.screen => 'Screen time',
        AnalyticsMetric.water => 'Water',
      };

  String get unit => switch (this) {
        AnalyticsMetric.wellness => '',
        AnalyticsMetric.sleep => 'h',
        AnalyticsMetric.stress => '/5',
        AnalyticsMetric.energy => '/5',
        AnalyticsMetric.exercise => ' min',
        AnalyticsMetric.screen => 'h',
        AnalyticsMetric.water => ' glasses',
      };
}

/// One observed value on a date.
class MetricPoint {
  final String dateKey;
  final double value;
  const MetricPoint(this.dateKey, this.value);
}

/// A named series of observed values (ascending by date).
class MetricSeries {
  final AnalyticsMetric metric;
  final List<MetricPoint> points;
  const MetricSeries(this.metric, this.points);
}

/// Moving average: null until [window] real observations accumulate.
/// Missing observations break the window (never interpolated).
List<double?> movingAverage(List<double?> values, int window) {
  assert(window >= 2);
  final out = List<double?>.filled(values.length, null);
  for (var i = 0; i < values.length; i++) {
    if (i + 1 < window) continue;
    final slice = values.sublist(i + 1 - window, i + 1);
    if (slice.any((v) => v == null)) continue;
    final avg = _mean(slice.whereType<double>().toList());
    out[i] = _fin(avg);
  }
  return out;
}

/// One time bucket (week or month) with its observed average.
class TrendBucket {
  final String label;
  final double? average;
  final int count;
  const TrendBucket(
      {required this.label, required this.average, required this.count});
}

/// Groups points into calendar weeks (Mon–Sun) with averages.
List<TrendBucket> weeklyTrend(List<MetricPoint> points) {
  final byWeek = <String, List<double>>{};
  for (final p in points) {
    final d = DateTime.tryParse(p.dateKey);
    if (d == null || !p.value.isFinite) continue;
    final monday = d.subtract(Duration(days: d.weekday - 1));
    final key =
        '${monday.year.toString().padLeft(4, '0')}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
    byWeek.putIfAbsent(key, () => []).add(p.value);
  }
  final keys = byWeek.keys.toList()..sort();
  return [
    for (final k in keys)
      TrendBucket(
        label: 'w/c $k',
        average: _fin(_mean(byWeek[k]!)),
        count: byWeek[k]!.length,
      ),
  ];
}

/// Groups points into calendar months with averages.
List<TrendBucket> monthlyTrend(List<MetricPoint> points) {
  final byMonth = <String, List<double>>{};
  for (final p in points) {
    final d = DateTime.tryParse(p.dateKey);
    if (d == null || !p.value.isFinite) continue;
    final key =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
    byMonth.putIfAbsent(key, () => []).add(p.value);
  }
  final keys = byMonth.keys.toList()..sort();
  return [
    for (final k in keys)
      TrendBucket(
        label: k,
        average: _fin(_mean(byMonth[k]!)),
        count: byMonth[k]!.length,
      ),
  ];
}

/// First-vs-last bucket change. Null when fewer than 2 buckets carry data.
double? bucketChange(List<TrendBucket> buckets) {
  final avgs = [
    for (final b in buckets)
      if (b.average != null) b.average!,
  ];
  if (avgs.length < 2) return null;
  return _fin(avgs.last - avgs.first);
}

/// A detected shift between the first and second half of a series.
/// Null fields mean "no detectable change" — never a fabricated zero.
class ChangeResult {
  final double? firstAvg;
  final double? secondAvg;
  final double? delta;
  final bool significant;
  final int points;

  const ChangeResult({
    required this.firstAvg,
    required this.secondAvg,
    required this.delta,
    required this.significant,
    required this.points,
  });
}

/// Splits finite values into halves; significant when |delta] reaches half
/// a standard deviation. Needs ≥3 points per half.
ChangeResult detectChange(List<double> values) {
  final finite = [for (final v in values) if (v.isFinite) v];
  if (finite.length < 6) {
    return const ChangeResult(
        firstAvg: null,
        secondAvg: null,
        delta: null,
        significant: false,
        points: 0);
  }
  final half = finite.length ~/ 2;
  final first = finite.take(half).toList();
  final second = finite.skip(half).toList();
  final fa = _mean(first);
  final sa = _mean(second);
  final overall = _mean(finite);
  final variance =
      _mean([for (final v in finite) (v - overall) * (v - overall)]);
  final sd = variance <= 0 ? 0.0 : _sqrt(variance);
  final delta = _fin(sa - fa);
  return ChangeResult(
    firstAvg: _fin(fa),
    secondAvg: _fin(sa),
    delta: delta,
    significant: delta != null && sd > 0 && delta.abs() >= 0.5 * sd,
    points: finite.length,
  );
}

double _sqrt(double v) =>
    v <= 0 ? 0.0 : _newtonSqrt(v);

double _newtonSqrt(double v) {
  var x = v > 1 ? v / 2 : 1.0;
  for (var i = 0; i < 20; i++) {
    x = (x + v / x) / 2;
  }
  return x.isFinite ? x : 0.0;
}

/// Pearson correlation over paired observations. Null when there are fewer
/// than [kMinCorrelationPairs] pairs, zero variance, or non-finite input —
/// the UI reports these as unavailable, never as zero.
double? pearson(List<double> xs, List<double> ys) {
  if (xs.length != ys.length || xs.length < kMinCorrelationPairs) {
    return null;
  }
  final x = <double>[];
  final y = <double>[];
  for (var i = 0; i < xs.length; i++) {
    if (xs[i].isFinite && ys[i].isFinite) {
      x.add(xs[i]);
      y.add(ys[i]);
    }
  }
  if (x.length < kMinCorrelationPairs) return null;
  final n = x.length;
  final mx = _mean(x);
  final my = _mean(y);
  var num = 0.0;
  var dx = 0.0;
  var dy = 0.0;
  for (var i = 0; i < n; i++) {
    final a = x[i] - mx;
    final b = y[i] - my;
    num += a * b;
    dx += a * a;
    dy += b * b;
  }
  if (dx <= 0 || dy <= 0) return null;
  return _fin(num / _newtonSqrt(dx * dy));
}

/// One computed matrix cell (an observed correlation, never a cause).
class CorrelationCell {
  final AnalyticsMetric row;
  final AnalyticsMetric col;
  final double? r;
  final int pairs;
  final String startKey;
  final String endKey;

  const CorrelationCell({
    required this.row,
    required this.col,
    required this.r,
    required this.pairs,
    required this.startKey,
    required this.endKey,
  });

  bool get computed => r != null;

  /// Association-only label for the UI.
  String get label {
    final v = r;
    if (v == null) return 'Not enough paired data';
    if (v >= 0.5) return 'Observed correlation — moves together';
    if (v <= -0.5) return 'Observed correlation — moves oppositely';
    if (v >= 0.3) return 'Observed correlation — weak together';
    if (v <= -0.3) return 'Observed correlation — weak opposite';
    return 'Observed correlation — negligible';
  }

  String get explanation {
    if (r == null) {
      return 'Fewer than $kMinCorrelationPairs days had both ${row.label.toLowerCase()} and ${col.label.toLowerCase()} logged ($pairs found). Log both on the same days to enable this cell.';
    }
    return 'Across $pairs days ($startKey → $endKey), ${row.label.toLowerCase()} and ${col.label.toLowerCase()} showed r = ${r!.toStringAsFixed(2)}. '
        'This is an observed correlation in your logged data — it does not show that one causes the other.';
  }
}

/// Builds the full pairwise matrix over same-date observations.
List<CorrelationCell> correlationMatrix(Map<AnalyticsMetric, MetricSeries> all) {
  final metrics = AnalyticsMetric.values;
  final byDate = <AnalyticsMetric, Map<String, double>>{
    for (final m in metrics)
      m: {for (final p in all[m]?.points ?? const <MetricPoint>[]) p.dateKey: p.value},
  };
  final out = <CorrelationCell>[];
  for (var i = 0; i < metrics.length; i++) {
    for (var j = i + 1; j < metrics.length; j++) {
      final a = metrics[i];
      final b = metrics[j];
      final common = byDate[a]!.keys.toSet().intersection(byDate[b]!.keys.toSet()).toList()
        ..sort();
      final xs = [for (final k in common) byDate[a]![k]!];
      final ys = [for (final k in common) byDate[b]![k]!];
      out.add(CorrelationCell(
        row: a,
        col: b,
        r: pearson(xs, ys),
        pairs: common.length,
        startKey: common.isEmpty ? '' : common.first,
        endKey: common.isEmpty ? '' : common.last,
      ));
    }
  }
  return out;
}

/// One unusual day flagged by the detector.
class Anomaly {
  final String dateKey;
  final AnalyticsMetric metric;
  final double value;
  final double typical; // median of the series
  final double deviation; // |modified z-score|

  const Anomaly({
    required this.dateKey,
    required this.metric,
    required this.value,
    required this.typical,
    required this.deviation,
  });

  String get description =>
      '${metric.label} was ${value.toStringAsFixed(1)}${metric.unit} on $dateKey vs a typical ${typical.toStringAsFixed(1)}${metric.unit} — an unusual day in your logs, not a diagnosis.';
}

/// Modified z-score anomaly detection (median + MAD, robust to outliers).
/// Returns [] when there are too few points or zero spread — never NaN.
List<Anomaly> detectAnomalies(MetricSeries series) {
  final pts = [
    for (final p in series.points)
      if (p.value.isFinite) p,
  ];
  if (pts.length < kMinAnomalyPoints) return const [];
  final sorted = [...pts.map((p) => p.value)]..sort();
  final median = sorted.length.isOdd
      ? sorted[sorted.length ~/ 2]
      : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;
  final deviations = [
    for (final v in sorted) (v - median).abs(),
  ]..sort();
  final mad = deviations.length.isOdd
      ? deviations[deviations.length ~/ 2]
      : (deviations[deviations.length ~/ 2 - 1] +
              deviations[deviations.length ~/ 2]) /
          2;
  if (mad <= 0 || !mad.isFinite) return const []; // zero variance: nothing unusual
  final out = <Anomaly>[];
  for (final p in pts) {
    final z = (0.6745 * (p.value - median) / mad);
    if (!z.isFinite) continue;
    if (z.abs() >= kAnomalyThreshold) {
      out.add(Anomaly(
        dateKey: p.dateKey,
        metric: series.metric,
        value: p.value,
        typical: median,
        deviation: z.abs(),
      ));
    }
  }
  out.sort((a, b) => b.deviation.compareTo(a.deviation));
  return out;
}

/// Baseline-vs-experiment analysis with mean, median, difference,
/// completion rate and sample counts. Reuses the Lab's baseline windows.
class ExperimentAnalysis {
  final String experimentTitle;
  final String metricLabel;
  final String unit;
  final double? baselineMean;
  final int baselineN;
  final double? experimentMean;
  final double? experimentMedian;
  final int experimentN;
  final double? difference;
  final double completionRate;
  final String summary;

  const ExperimentAnalysis({
    required this.experimentTitle,
    required this.metricLabel,
    required this.unit,
    required this.baselineMean,
    required this.baselineN,
    required this.experimentMean,
    required this.experimentMedian,
    required this.experimentN,
    required this.difference,
    required this.completionRate,
    required this.summary,
  });
}

double? _median(List<double> v) {
  final finite = [for (final x in v) if (x.isFinite) x]..sort();
  if (finite.isEmpty) return null;
  if (finite.length.isOdd) return _fin(finite[finite.length ~/ 2]);
  return _fin((finite[finite.length ~/ 2 - 1] + finite[finite.length ~/ 2]) / 2);
}

ExperimentAnalysis analyzeExperiment({
  required Experiment exp,
  required List<DailyHealthEntry> entries,
  required DateTime now,
}) {
  final comparison =
      compareBaseline(exp: exp, entries: entries, now: now);
  final info = comparison.metric;
  final day = DateTime(now.year, now.month, now.day);
  final start = exp.startDate == null
      ? day
      : DateTime(exp.startDate!.year, exp.startDate!.month, exp.startDate!.day);
  final byDate = {for (final e in entries) e.date: e};
  final expVals = <double>[];
  for (var d = start;
      !d.isAfter(day);
      d = d.add(const Duration(days: 1))) {
    final e = byDate[formatDateForStorage(d)];
    if (e == null) continue;
    final v = metricValue(e, info.metric);
    if ((v > 0 || info.metric == LabMetric.screenTimeHours) && v.isFinite) {
      expVals.add(v);
    }
  }
  final median = _median(expVals);
  final mean = expVals.isEmpty ? null : _fin(_mean(expVals));
  final diff = mean == null || comparison.baselineAvg == null
      ? null
      : _fin(mean - comparison.baselineAvg!);
  final rate = exp.durationDays <= 0
      ? 0.0
      : (exp.checkIns.length / exp.durationDays).clamp(0.0, 1.0);
  final buf = StringBuffer()
    ..write(
        'Baseline ${info.label}: ${comparison.baselineAvg?.toStringAsFixed(1) ?? 'unavailable'}${info.unit} (${comparison.baselineDays} days). ')
    ..write(
        'Experiment: mean ${mean?.toStringAsFixed(1) ?? 'unavailable'}${info.unit}, median ${median?.toStringAsFixed(1) ?? 'unavailable'}${info.unit} (${expVals.length} logged days), completion ${(rate * 100).round()}%. ');
  if (diff != null) {
    buf.write(
        'Difference: ${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}${info.unit} — an observed difference, not proof of an effect.');
  } else {
    buf.write('No before/during comparison is available yet.');
  }
  return ExperimentAnalysis(
    experimentTitle: exp.title,
    metricLabel: info.label,
    unit: info.unit,
    baselineMean: comparison.baselineAvg,
    baselineN: comparison.baselineDays,
    experimentMean: mean,
    experimentMedian: median,
    experimentN: expVals.length,
    difference: diff,
    completionRate: rate.isFinite ? rate : 0.0,
    summary: buf.toString(),
  );
}

/// Data completeness for one series over a window.
class Completeness {
  final AnalyticsMetric metric;
  final int logged;
  final int total;
  const Completeness(
      {required this.metric, required this.logged, required this.total});

  String get label => '$logged / $total days';
  double get fraction => total <= 0 ? 0 : (logged / total).clamp(0.0, 1.0);
}

/// Counts distinct logged dates within [start]..[end] (inclusive).
Completeness completeness({
  required MetricSeries series,
  required DateTime start,
  required DateTime end,
}) {
  final days = end.difference(start).inDays + 1;
  final inWindow = series.points.where((p) {
    final d = DateTime.tryParse(p.dateKey);
    if (d == null) return false;
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(DateTime(start.year, start.month, start.day)) &&
        !day.isAfter(DateTime(end.year, end.month, end.day));
  }).map((p) => p.dateKey).toSet();
  return Completeness(
      metric: series.metric, logged: inWindow.length, total: days > 0 ? days : 0);
}

/// Educational explanations (college-demo friendly, plain language).
const Map<String, String> analyticsEducation = {
  'What does correlation mean?':
      'Correlation (r, from −1 to +1) describes how two logged measures move together. Near +1: high days for one tend to be high days for the other. Near −1: they move oppositely. Near 0: no visible pattern. It is always an observed correlation — it never shows that one causes the other.',
  'What does sample size mean?':
      'Sample size is how many paired days sit behind a number. Five paired days is the minimum shown here; more days make patterns steadier. A strong-looking value from very few days can easily be coincidence — that is why small cells stay unavailable.',
  'What does an anomaly mean?':
      'An anomaly is a day unusually far from your own typical value (median), flagged by a robust statistical rule. It marks "worth a look" days in your logs — not errors, and never diagnoses.',
};

/// JSON-safe analytics report for export (numbers only, no bodies).
Map<String, dynamic> analyticsReportJson({
  required DateTime generatedAt,
  required int windowDays,
  required List<Completeness> completenessList,
  required List<CorrelationCell> matrix,
  required List<Anomaly> anomalies,
  required List<ExperimentAnalysis> experiments,
}) {
  return {
    'type': 'soulcare-analytics-report',
    'generatedAt': generatedAt.toIso8601String(),
    'windowDays': windowDays,
    'disclaimer':
        'Exploratory summaries of logged data only — not medical conclusions. Correlations never imply causation.',
    'completeness': [
      for (final c in completenessList)
        {
          'metric': c.metric.label,
          'logged': c.logged,
          'total': c.total,
        },
    ],
    'correlations': [
      for (final cell in matrix.where((c) => c.computed))
        {
          'pair': '${cell.row.label} vs ${cell.col.label}',
          'r': double.parse(cell.r!.toStringAsFixed(3)),
          'pairs': cell.pairs,
          'range': '${cell.startKey} to ${cell.endKey}',
        },
    ],
    'anomalies': [
      for (final a in anomalies)
        {
          'date': a.dateKey,
          'metric': a.metric.label,
          'value': a.value,
          'typical': a.typical,
        },
    ],
    'experiments': [
      for (final e in experiments)
        {
          'title': e.experimentTitle,
          'metric': e.metricLabel,
          'baselineMean': e.baselineMean,
          'baselineN': e.baselineN,
          'experimentMean': e.experimentMean,
          'experimentMedian': e.experimentMedian,
          'experimentN': e.experimentN,
          'difference': e.difference,
          'completionRate': e.completionRate,
        },
    ],
  };
}
