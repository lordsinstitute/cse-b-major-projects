import '../../data/models/models.dart';

/// A single deterministic insight derived from logged data.
/// Language is careful: patterns and trends only, never causal claims,
/// never diagnoses.
class Insight {
  final String title;
  final String body;

  const Insight({required this.title, required this.body});
}

/// Deterministic insight engine — pure functions, no randomness.
class InsightEngine {
  /// Builds up to 3 insights from the last-7-days entries.
  ///
  /// [calmByDate]: calm indicator (0..100, higher = calmer) per yyyy-MM-dd
  /// date derived from logged stress check-ins. Absent dates = no check-in.
  static List<Insight> build({
    required List<DailyHealthEntry> last7,
    required Map<String, double> calmByDate,
  }) {
    if (last7.isEmpty) return const [];
    final sorted = [...last7]..sort((a, b) => a.date.compareTo(b.date));
    final out = <Insight>[];

    // 1) Sleep trend: second half vs first half (needs >= 3 logged days).
    if (sorted.length >= 3) {
      final half = sorted.length ~/ 2;
      final first = sorted.take(half).toList();
      final second = sorted.skip(half).toList();
      final firstAvg = _avg(first.map((e) => e.sleepHours));
      final secondAvg = _avg(second.map((e) => e.sleepHours));
      if (secondAvg - firstAvg >= 0.25) {
        out.add(Insight(
          title: 'Sleep is trending up',
          body:
              'Your average logged sleep rose from ${firstAvg.toStringAsFixed(1)}h to ${secondAvg.toStringAsFixed(1)}h across your recent entries. Tracked pattern — keep logging to confirm the trend.',
        ));
      } else if (firstAvg - secondAvg >= 0.25) {
        out.add(Insight(
          title: 'Sleep dipped lately',
          body:
              'Your average logged sleep went from ${firstAvg.toStringAsFixed(1)}h to ${secondAvg.toStringAsFixed(1)}h across your recent entries. A tracked pattern, not a diagnosis.',
        ));
      }
    }

    // 2) Exercise consistency.
    final exerciseDays =
        sorted.where((e) => e.exerciseMinutes > 0).length;
    if (sorted.length >= 2) {
      out.add(Insight(
        title: 'Movement consistency',
        body:
            'You logged exercise on $exerciseDays of your last ${sorted.length} logged days. Based on your logged data.',
      ));
    }

    // 3) Sleep × calm co-occurrence (careful: association only).
    final lowSleepCalm = <double>[];
    final restedCalm = <double>[];
    for (final e in sorted) {
      final calm = calmByDate[e.date];
      if (calm == null) continue;
      if (e.sleepHours > 0 && e.sleepHours < 6) {
        lowSleepCalm.add(calm);
      } else if (e.sleepHours >= 7) {
        restedCalm.add(calm);
      }
    }
    if (lowSleepCalm.isNotEmpty && restedCalm.isNotEmpty) {
      final lowAvg = _avg(lowSleepCalm);
      final restedAvg = _avg(restedCalm);
      if (restedAvg - lowAvg >= 10) {
        out.add(Insight(
          title: 'Lower calm on short-sleep days',
          body:
              'Your tracked calm averaged ${lowAvg.round()} on days with under 6h sleep vs ${restedAvg.round()} on days with 7h+. This is an observed pattern in your logs — it does not prove one causes the other.',
        ));
      }
    }

    // 4) Logging consistency nudge.
    if (sorted.length < 3) {
      out.add(const Insight(
        title: 'Keep logging',
        body:
            'Log a few more days to reveal your personal trend. Insights appear once there is enough logged data.',
      ));
    }

    return out.take(3).toList();
  }

  static double _avg(Iterable<num> values) {
    final list = values.toList();
    if (list.isEmpty) return 0;
    return list.fold<double>(0, (a, b) => a + b.toDouble()) / list.length;
  }
}

/// Greeting helper (deterministic per hour).
String greetingForHour(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}
