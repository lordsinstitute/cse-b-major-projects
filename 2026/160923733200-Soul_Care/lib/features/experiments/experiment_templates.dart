import 'package:flutter/material.dart';

/// How much daily effort a template asks for.
enum EffortLevel { light, moderate }

extension EffortLevelX on EffortLevel {
  String get label => this == EffortLevel.light ? 'Light' : 'Moderate';
}

/// One startable 7-day behavioral experiment template.
class ExperimentTemplate {
  final String id;
  final String title;
  final String explanation;
  final List<String> instructions;
  final int durationDays;
  final String targetMetric;
  final String trackedFrom;
  final EffortLevel effort;
  final IconData icon;

  const ExperimentTemplate({
    required this.id,
    required this.title,
    required this.explanation,
    required this.instructions,
    required this.durationDays,
    required this.targetMetric,
    required this.trackedFrom,
    required this.effort,
    required this.icon,
  });
}

const List<ExperimentTemplate> experimentTemplates = [
  ExperimentTemplate(
    id: 'earlier-sleep',
    title: 'Earlier Sleep',
    explanation:
        'Wind down 30 minutes earlier each night and observe your tracked sleep pattern.',
    instructions: [
      'Set a wind-down alarm 30 minutes before bed.',
      'Dim screens during wind-down.',
      'Log your sleep each morning under Today.',
    ],
    durationDays: 7,
    targetMetric: 'sleepHours',
    trackedFrom: 'logged sleep hours',
    effort: EffortLevel.light,
    icon: Icons.bedtime_outlined,
  ),
  ExperimentTemplate(
    id: 'daily-walk',
    title: 'Daily Walk',
    explanation:
        'Take a 20-minute walk every day and observe your tracked movement pattern.',
    instructions: [
      'Walk at least 20 minutes daily.',
      'Any pace counts — consistency matters, not speed.',
      'Log movement under Today after each walk.',
    ],
    durationDays: 7,
    targetMetric: 'exerciseMinutes',
    trackedFrom: 'logged exercise minutes',
    effort: EffortLevel.light,
    icon: Icons.directions_walk,
  ),
  ExperimentTemplate(
    id: 'breathing-reset',
    title: 'Breathing Reset',
    explanation:
        'Do one 60-second breathing reset daily and observe your tracked calm pattern.',
    instructions: [
      'Open Today → Stress → Breathing reset once a day.',
      'Follow the full 60 seconds.',
      'Log a stress check-in right after.',
    ],
    durationDays: 7,
    targetMetric: 'meditationMinutes',
    trackedFrom: 'logged meditation minutes',
    effort: EffortLevel.light,
    icon: Icons.self_improvement_outlined,
  ),
  ExperimentTemplate(
    id: 'hydration',
    title: 'Hydration Consistency',
    explanation:
        'Drink 8 glasses of water daily and observe your tracked hydration pattern.',
    instructions: [
      'Keep water visible through the day.',
      'Spread glasses across morning, afternoon, evening.',
      'Log water glasses under Today each evening.',
    ],
    durationDays: 7,
    targetMetric: 'waterGlasses',
    trackedFrom: 'logged water glasses',
    effort: EffortLevel.light,
    icon: Icons.water_drop_outlined,
  ),
  ExperimentTemplate(
    id: 'screen',
    title: 'Reduced Late-Night Screen Time',
    explanation:
        'No screens in the last hour before bed and observe your tracked evening pattern.',
    instructions: [
      'Set a daily screen-off alarm 1 hour before bed.',
      'Charge your phone outside the bedroom if you can.',
      'Log screen time honestly under Today.',
    ],
    durationDays: 7,
    targetMetric: 'screenTimeHours',
    trackedFrom: 'logged screen-time hours',
    effort: EffortLevel.moderate,
    icon: Icons.phone_android_outlined,
  ),
];

ExperimentTemplate? templateById(String? id) {
  if (id == null) return null;
  for (final t in experimentTemplates) {
    if (t.id == id) return t;
  }
  return null;
}
