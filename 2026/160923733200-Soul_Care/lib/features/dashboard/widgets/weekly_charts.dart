import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../app/providers/dashboard_provider.dart';
import '../../../app/theme/design_system.dart';

/// Weekly charts for wellness, sleep, exercise, and calm (stress).
/// Missing days are left blank — points are only plotted for logged days,
/// with separate segments across gaps so no fake continuity is implied.
class WeeklyCharts extends StatelessWidget {
  final List<DayPoint> week;

  const WeeklyCharts({super.key, required this.week});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dim = DS.textTertiary(b);

    // Compute latest values for each metric
    final wellnessValues = [for (final d in week) d.wellness?.toDouble()];
    final sleepValues = [for (final d in week) d.sleepHours];
    final exerciseValues = [for (final d in week) d.exerciseMinutes?.toDouble()];
    final calmValues = [for (final d in week) d.calm];

    final wellnessLatest = wellnessValues.lastWhere((v) => v != null, orElse: () => null);
    final sleepLatest = sleepValues.lastWhere((v) => v != null, orElse: () => null);
    final exerciseLatest = exerciseValues.lastWhere((v) => v != null, orElse: () => null);
    final calmLatest = calmValues.lastWhere((v) => v != null, orElse: () => null);

    final wellnessLatestStr = wellnessLatest != null
        ? wellnessLatest % 1 == 0
            ? '${wellnessLatest.toInt()}'
            : wellnessLatest.toStringAsFixed(1)
        : '';
    final sleepLatestStr = sleepLatest != null
        ? sleepLatest % 1 == 0
            ? '${sleepLatest.toInt()}'
            : sleepLatest.toStringAsFixed(1)
        : '';
    final exerciseLatestStr = exerciseLatest != null
        ? exerciseLatest % 1 == 0
            ? '${exerciseLatest.toInt()}'
            : exerciseLatest.toStringAsFixed(1)
        : '';
    final calmLatestStr = calmLatest != null
        ? calmLatest % 1 == 0
            ? '${calmLatest.toInt()}'
            : calmLatest.toStringAsFixed(1)
        : '';

    return Column(
      children: [
        _MetricChart(
          title: 'Wellness score',
          unit: '',
          maxY: 100,
          color: scheme.primary,
          values: wellnessValues,
          dates: [for (final d in week) d.date],
          emptyHint: 'No data yet',
          latest: wellnessLatest,
          latestStr: wellnessLatestStr,
        ),
        const SizedBox(height: 12),
        _MetricChart(
          title: 'Sleep',
          unit: 'h',
          maxY: 12,
          color: DS.metric(b, MetricDomain.sleep),
          values: sleepValues,
          dates: [for (final d in week) d.date],
          emptyHint: 'No check-ins logged',
          latest: sleepLatest,
          latestStr: sleepLatestStr,
        ),
        const SizedBox(height: 12),
        _MetricChart(
          title: 'Exercise',
          unit: ' min',
          maxY: _niceMax(exerciseValues, 60),
          color: DS.metric(b, MetricDomain.activity),
          values: exerciseValues,
          dates: [for (final d in week) d.date],
          latest: exerciseLatest,
          latestStr: exerciseLatestStr,
        ),
        const SizedBox(height: 12),
        _MetricChart(
          title: 'Calm (from check-ins)',
          unit: '',
          maxY: 100,
          color: DS.metric(b, MetricDomain.mood),
          values: calmValues,
          dates: [for (final d in week) d.date],
          emptyHint: 'No check-ins logged',
          latest: calmLatest,
          latestStr: calmLatestStr,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Missing days are left blank — no filler data.',
            style: theme.textTheme.bodySmall?.copyWith(color: dim),
          ),
        ),
      ],
    );
  }

  static double _niceMax(List<double?> values, double fallback) {
    double max = 0;
    for (final v in values) {
      if (v != null && v > max) max = v;
    }
    if (max <= 0) return fallback;
    return (max * 1.2).ceilToDouble();
  }
}

class _MetricChart extends StatelessWidget {
  final String title;
  final String unit;
  final double maxY;
  final Color color;
  final List<double?> values;
  final List<DateTime> dates;
  final String emptyHint;
  final double? latest;
  final String latestStr;

  const _MetricChart({
    required this.title,
    required this.unit,
    required this.maxY,
    required this.color,
    required this.values,
    required this.dates,
    this.emptyHint = 'No data yet',
    this.latest,
    this.latestStr = '',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dim = DS.textTertiary(Theme.of(context).brightness);
    final segments = _segments(values);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant.withAlpha(128)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const Spacer(),
              if (latest != null)
                Text(
                  latestStr + unit,
                  style: theme.textTheme.labelLarge?.copyWith(color: color),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: segments.isEmpty
                ? Center(
                    child: Text(
                      emptyHint,
                      style: theme.textTheme.bodySmall?.copyWith(color: dim),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: 6,
                      minY: 0,
                      maxY: maxY,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      lineTouchData: const LineTouchData(enabled: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: const AxisTitles(
                            sideTitles: SideTitles(
                                showTitles: true, reservedSize: 30)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 1,
                            getTitlesWidget: (v, meta) {
                              final i = v.round();
                              if (i < 0 || i > 6) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _weekdayLetter(dates[i].weekday),
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: dim, fontSize: 10),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      lineBarsData: [
                        for (final seg in segments)
                          LineChartBarData(
                            spots: seg,
                            isCurved: true,
                            barWidth: 2.5,
                            color: color,
                            dotData: const FlDotData(show: true),
                            belowBarData: BarAreaData(
                              show: true,
                              color: color.withValues(alpha: 0.10),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Consecutive non-null runs → separate segments (gaps stay visible).
  /// Pure computation: O(n) with no side effects; safe to call every frame.
  static List<List<FlSpot>> _segments(List<double?> values) {
    final segs = <List<FlSpot>>[];
    var current = <FlSpot>[];
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        if (current.isNotEmpty) {
          segs.add(current);
          current = <FlSpot>[];
        }
      } else {
        current.add(FlSpot(i.toDouble(), v));
      }
    }
    if (current.isNotEmpty) segs.add(current);
    // Single isolated points still render (dot) via a 1-spot bar.
    return segs;
  }

  static String _weekdayLetter(int weekday) {
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return letters[weekday - 1];
  }
}