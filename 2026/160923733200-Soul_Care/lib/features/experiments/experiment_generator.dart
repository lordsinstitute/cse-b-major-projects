import '../../core/wellness/insights.dart';
import '../../data/models/checkins.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../data/models/user_profile.dart';
import 'experiment_engine.dart';

/// Minimum logged days (trailing 14) before any opportunity is identified.
const int kGeneratorMinDays = 5;

/// Success threshold shared by all generated experiments.
const int kGeneratorSuccessDays = 5;

/// One data-backed opportunity turned into a startable experiment.
///
/// All numbers (baseline, thresholds, durations) are computed
/// deterministically from logged data. An optional [ExperimentPhraser] may
/// reword the title/description only — it never sees or sets statistics.
class GeneratedExperiment {
  final String templateId; // maps to an existing template (measurement reuse)
  final String title;
  final String observation; // data-cited finding with real numbers
  final String hypothesis; // association-only; explicitly not claimed true
  final String action; // concrete daily behavior
  final int durationDays;
  final LabMetric metric;
  final String measureLabel; // e.g. 'Sleep duration + morning energy'
  final double? baselineAvg;
  final int baselineDays;
  final String baselineText;
  final String successCriteria;
  final String checkInRequirement;
  final double severity; // internal ranking signal (higher = stronger gap)

  const GeneratedExperiment({
    required this.templateId,
    required this.title,
    required this.observation,
    required this.hypothesis,
    required this.action,
    required this.durationDays,
    required this.metric,
    required this.measureLabel,
    required this.baselineAvg,
    required this.baselineDays,
    required this.baselineText,
    required this.successCriteria,
    required this.checkInRequirement,
    required this.severity,
  });
}

/// Output of one generator run.
class GeneratorOutput {
  final List<GeneratedExperiment> suggestions; // max 3, ranked
  final int loggedDays;
  final String? insufficientReason;

  const GeneratorOutput({
    required this.suggestions,
    required this.loggedDays,
    this.insufficientReason,
  });

  bool get hasSuggestions => suggestions.isNotEmpty;
}

/// Optional phrasing layer. The local SoulCare AI is currently unavailable
/// (no model exists in this app), so [DeterministicPhraser] is always used
/// in practice: wording passes through untouched. Any future implementation
/// MUST only reword the given strings — measurements, baselines, thresholds
/// and calculations always come from this deterministic engine, and an AI
/// model must never invent user statistics.
abstract class ExperimentPhraser {
  ({String title, String description}) phrase({
    required String draftTitle,
    required String draftDescription,
  });
}

/// Default (and currently only) phraser: returns drafts unchanged.
class DeterministicPhraser implements ExperimentPhraser {
  const DeterministicPhraser();

  @override
  ({String title, String description}) phrase({
    required String draftTitle,
    required String draftDescription,
  }) =>
      (title: draftTitle, description: draftDescription);
}

/// Full input bundle for one generator run. Plain data only.
class GeneratorInput {
  final List<DailyHealthEntry> recent; // trailing logged entries, any order
  final Map<String, double> calmByDate;
  final Map<String, MorningCheckIn> morningByDate;
  final Map<String, EveningReflection> eveningByDate;
  final UserProfile? profile;
  final List<Experiment> previous;
  final DateTime now;

  const GeneratorInput({
    required this.recent,
    required this.calmByDate,
    required this.morningByDate,
    required this.eveningByDate,
    required this.previous,
    required this.now,
    this.profile,
  });
}

/// Generates up to 3 personal experiment suggestions from actual user data.
///
/// Returns an insufficient-data output when fewer than [kGeneratorMinDays]
/// days are logged — opportunities are only identified when supported by
/// sufficient data. Never throws; never invents statistics.
GeneratorOutput generateExperiments(
  GeneratorInput input, {
  ExperimentPhraser phraser = const DeterministicPhraser(),
}) {
  final entries = [...input.recent]
    ..sort((a, b) => a.date.compareTo(b.date));
  if (entries.length < kGeneratorMinDays) {
    return GeneratorOutput(
      suggestions: const [],
      loggedDays: entries.length,
      insufficientReason:
          'Only ${entries.length} logged days found — log at least $kGeneratorMinDays days under Today so suggestions can be based on your real pattern.',
    );
  }

  // Previous-experiment guard: skip templates with a currently active
  // experiment, or one completed in the last 30 days.
  bool recentlyDone(String templateId) {
    for (final e in input.previous) {
      if (e.templateId != templateId) continue;
      if (e.status == ExperimentStatus.active) return true;
      if (e.status == ExperimentStatus.completed) {
        final end = e.endDate ?? e.updatedAt;
        if (input.now.difference(end).inDays < 30) return true;
      }
    }
    return false;
  }

  final candidates = <GeneratedExperiment?>[
    _sleepOpportunity(entries, input, recentlyDone),
    _activityOpportunity(entries, input, recentlyDone),
    _hydrationOpportunity(entries, input, recentlyDone),
    _screenOpportunity(entries, input, recentlyDone),
    _mindfulnessOpportunity(entries, input, recentlyDone),
  ].whereType<GeneratedExperiment>().toList();

  candidates.sort((a, b) => b.severity.compareTo(a.severity));
  final top = candidates.take(3).toList();

  // Phrasing pass: wording only, numbers already fixed above.
  return GeneratorOutput(
    loggedDays: entries.length,
    suggestions: [
      for (final g in top)
        () {
          final phrased = phraser.phrase(
            draftTitle: g.title,
            draftDescription: g.action,
          );
          return GeneratedExperiment(
            templateId: g.templateId,
            title: phrased.title,
            observation: g.observation,
            hypothesis: g.hypothesis,
            action: phrased.description,
            durationDays: g.durationDays,
            metric: g.metric,
            measureLabel: g.measureLabel,
            baselineAvg: g.baselineAvg,
            baselineDays: g.baselineDays,
            baselineText: g.baselineText,
            successCriteria: g.successCriteria,
            checkInRequirement: g.checkInRequirement,
            severity: g.severity,
          );
        }(),
    ],
  );
}

// --- Opportunity detectors (one per finding) ---

String _hypothesisDisclaimer =
    'Hypothesis only — not claimed to be true. The experiment tests whether the pattern shows up in your logs.';

GeneratedExperiment? _sleepOpportunity(
  List<DailyHealthEntry> entries,
  GeneratorInput input,
  bool Function(String) recentlyDone,
) {
  if (recentlyDone('earlier-sleep')) return null;
  final sleeps = [
    for (final e in entries)
      if (e.sleepHours > 0) e.sleepHours,
  ];
  if (sleeps.length < kGeneratorMinDays) return null;
  final avg = sleeps.reduce((a, b) => a + b) / sleeps.length;
  final range = sleeps.reduce((a, b) => a > b ? a : b) -
      sleeps.reduce((a, b) => a < b ? a : b);
  if (range < 2.0 && avg >= 7.0) return null; // no finding: consistent + enough

  final energies = <int>[];
  for (final e in entries) {
    final m = input.morningByDate[e.date];
    if (m != null) energies.add(m.energy);
    final v = input.eveningByDate[e.date];
    if (v != null) energies.add(v.energy);
  }
  final energyNote = energies.isEmpty
      ? 'Log morning check-ins to track energy alongside sleep.'
      : 'Your logged energy averaged ${(energies.reduce((a, b) => a + b) / energies.length).toStringAsFixed(1)}/5 across these days.';
  return GeneratedExperiment(
    templateId: 'earlier-sleep',
    title: '7-Day Consistent Sleep Window',
    observation:
        'Your sleep duration varied by ${range.toStringAsFixed(1)} hours across your last ${sleeps.length} logged days (average ${avg.toStringAsFixed(1)}h).',
    hypothesis:
        'A more consistent sleep window may coincide with steadier morning energy. $energyNote $_hypothesisDisclaimer',
    action:
        'Pick a fixed sleep window (e.g. 11pm–7am) and keep lights-out within 30 minutes of it every night for 7 days. Log sleep each morning under Today.',
    durationDays: 7,
    metric: LabMetric.sleepHours,
    measureLabel: 'Sleep duration + morning energy',
    baselineAvg: avg,
    baselineDays: sleeps.length,
    baselineText:
        'Baseline sleep: ${avg.toStringAsFixed(1)}h average over ${sleeps.length} logged days.',
    successCriteria:
        'Complete $kGeneratorSuccessDays+ of 7 daily check-ins. Success is participation — any measured difference is reported as an observed difference only.',
    checkInRequirement:
        'Tap DONE (or MISSED) in the Lab once per day — 30 seconds.',
    severity: range + (avg < 7.0 ? 1.5 : 0),
  );
}

GeneratedExperiment? _activityOpportunity(
  List<DailyHealthEntry> entries,
  GeneratorInput input,
  bool Function(String) recentlyDone,
) {
  if (recentlyDone('daily-walk')) return null;
  final active =
      entries.where((e) => e.exerciseMinutes >= 20).length;
  if (active > 2) return null;
  final total = entries.map((e) => e.exerciseMinutes).fold(0, (a, b) => a + b);
  final target = (input.profile?.exerciseGoalWeek ?? 150).toDouble();
  return GeneratedExperiment(
    templateId: 'daily-walk',
    title: '7-Day Movement Boost',
    observation:
        'You logged 20+ minutes of movement on $active of your last ${entries.length} logged days ($total min total vs a ${target.toStringAsFixed(0)} min/week target).',
    hypothesis:
        'Adding a short daily walk may coincide with higher logged energy on active days. $_hypothesisDisclaimer',
    action:
        'Walk at least 20 minutes every day for 7 days — any pace counts. Log movement under Today after each walk.',
    durationDays: 7,
    metric: LabMetric.exerciseMinutes,
    measureLabel: 'Exercise minutes + energy',
    baselineAvg: total / entries.length,
    baselineDays: entries.length,
    baselineText:
        'Baseline movement: ${(total / entries.length).toStringAsFixed(0)} min/day average over ${entries.length} logged days.',
    successCriteria:
        'Complete $kGeneratorSuccessDays+ of 7 daily check-ins. Success is participation — any measured difference is reported as an observed difference only.',
    checkInRequirement:
        'Tap DONE (or MISSED) in the Lab once per day — 30 seconds.',
    severity: (3 - active).toDouble() + (total < target ? 1.0 : 0),
  );
}

GeneratedExperiment? _hydrationOpportunity(
  List<DailyHealthEntry> entries,
  GeneratorInput input,
  bool Function(String) recentlyDone,
) {
  if (recentlyDone('hydration')) return null;
  final waters = [
    for (final e in entries) e.waterGlasses.toDouble(),
  ];
  final avg = waters.reduce((a, b) => a + b) / waters.length;
  final range = waters.reduce((a, b) => a > b ? a : b) -
      waters.reduce((a, b) => a < b ? a : b);
  if (avg >= 6 && range < 4) return null;
  return GeneratedExperiment(
    templateId: 'hydration',
    title: '7-Day Steady Hydration',
    observation:
        'Your logged water averaged ${avg.toStringAsFixed(1)} glasses per day with a ${range.toStringAsFixed(0)}-glass spread across ${entries.length} logged days.',
    hypothesis:
        'Drinking water steadily through the day may coincide with steadier logged energy. $_hypothesisDisclaimer',
    action:
        'Drink 8 glasses of water daily for 7 days, spread across morning, afternoon and evening. Log water each evening under Today.',
    durationDays: 7,
    metric: LabMetric.waterGlasses,
    measureLabel: 'Water glasses + energy',
    baselineAvg: avg,
    baselineDays: entries.length,
    baselineText:
        'Baseline water: ${avg.toStringAsFixed(1)} glasses/day average over ${entries.length} logged days.',
    successCriteria:
        'Complete $kGeneratorSuccessDays+ of 7 daily check-ins. Success is participation — any measured difference is reported as an observed difference only.',
    checkInRequirement:
        'Tap DONE (or MISSED) in the Lab once per day — 30 seconds.',
    severity: (6 - avg).clamp(0, 6) + range / 4,
  );
}

GeneratedExperiment? _screenOpportunity(
  List<DailyHealthEntry> entries,
  GeneratorInput input,
  bool Function(String) recentlyDone,
) {
  if (recentlyDone('screen')) return null;
  final avg =
      entries.map((e) => e.screenTimeHours).reduce((a, b) => a + b) /
          entries.length;
  if (avg < 4) return null;
  return GeneratedExperiment(
    templateId: 'screen',
    title: '7-Day Evening Screen Wind-Down',
    observation:
        'Your logged screen time averaged ${avg.toStringAsFixed(1)}h per day across ${entries.length} logged days.',
    hypothesis:
        'No screens in the last hour before bed may coincide with steadier logged sleep. $_hypothesisDisclaimer',
    action:
        'Keep the last hour before bed screen-free for 7 days (set a screen-off alarm). Log screen time honestly under Today.',
    durationDays: 7,
    metric: LabMetric.screenTimeHours,
    measureLabel: 'Screen time + sleep duration',
    baselineAvg: avg,
    baselineDays: entries.length,
    baselineText:
        'Baseline screen time: ${avg.toStringAsFixed(1)}h/day average over ${entries.length} logged days.',
    successCriteria:
        'Complete $kGeneratorSuccessDays+ of 7 daily check-ins. Success is participation — any measured difference is reported as an observed difference only.',
    checkInRequirement:
        'Tap DONE (or MISSED) in the Lab once per day — 30 seconds.',
    severity: avg - 4,
  );
}

GeneratedExperiment? _mindfulnessOpportunity(
  List<DailyHealthEntry> entries,
  GeneratorInput input,
  bool Function(String) recentlyDone,
) {
  if (recentlyDone('breathing-reset')) return null;
  final medDays = entries.where((e) => e.meditationMinutes > 0).length;
  if (medDays > 1) return null;
  return GeneratedExperiment(
    templateId: 'breathing-reset',
    title: '7-Day Mindful Minute',
    observation:
        'You logged meditation on $medDays of your last ${entries.length} logged days.',
    hypothesis:
        'One daily breathing reset may coincide with calmer logged check-ins. $_hypothesisDisclaimer',
    action:
        'Do one 60-second breathing reset daily for 7 days (Today → Stress → Breathing reset) and log a stress check-in right after.',
    durationDays: 7,
    metric: LabMetric.meditationMinutes,
    measureLabel: 'Meditation minutes + calm',
    baselineAvg:
        entries.map((e) => e.meditationMinutes).fold(0, (a, b) => a + b) /
            entries.length,
    baselineDays: entries.length,
    baselineText:
        'Baseline meditation: ${(entries.map((e) => e.meditationMinutes).fold(0, (a, b) => a + b) / entries.length).toStringAsFixed(1)} min/day average over ${entries.length} logged days.',
    successCriteria:
        'Complete $kGeneratorSuccessDays+ of 7 daily check-ins. Success is participation — any measured difference is reported as an observed difference only.',
    checkInRequirement:
        'Tap DONE (or MISSED) in the Lab once per day — 30 seconds.',
    severity: (2 - medDays).toDouble(),
  );
}

/// Builds the pattern-engine observations for the generator input.
/// Thin wrapper so the Lab UI needs only one call site.
List<Insight> observationsForGenerator({
  required List<DailyHealthEntry> last7,
  required Map<String, double> calmByDate,
}) =>
    InsightEngine.build(last7: last7, calmByDate: calmByDate);
