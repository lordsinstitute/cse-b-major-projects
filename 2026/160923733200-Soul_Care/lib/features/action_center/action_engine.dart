/// One suggested action: what, why, where it goes, and how to
/// dismiss it. Priorities are computed from real facts (explicit goals,
/// time sensitivity, incomplete actions) — urgency is never invented.
class TodayAction {
  final String id;
  final String title;
  final String explanation;
  final String destination;
  final int priority;
  final String dismissKey;

  const TodayAction({
    required this.id,
    required this.title,
    required this.explanation,
    required this.destination,
    required this.priority,
    required this.dismissKey,
  });
}

/// Everything the engine may consider. All fields are observed facts.
class ActionContext {
  final int completedSections;
  final int totalSections;
  final bool morningDone;
  final bool eveningDone;
  final bool eveningWindow;
  final List<GoalGap> goalGaps;
  final ExperimentDue? experimentDue;
  final List<AppointmentDue> appointmentsToday;

  const ActionContext({
    required this.completedSections,
    required this.totalSections,
    required this.morningDone,
    required this.eveningDone,
    required this.eveningWindow,
    required this.goalGaps,
    required this.experimentDue,
    required this.appointmentsToday,
  });
}

/// A personal target that is still open (current < target).
class GoalGap {
  final String label;
  final String detail;
  final String focusKey;
  final bool matchesFocus;

  const GoalGap({
    required this.label,
    required this.detail,
    required this.focusKey,
    required this.matchesFocus,
  });
}

class ExperimentDue {
  final String title;
  final int dayNumber;
  final int durationDays;

  const ExperimentDue({
    required this.title,
    required this.dayNumber,
    required this.durationDays,
  });
}

class AppointmentDue {
  final String title;
  final String timeLabel;

  const AppointmentDue({required this.title, required this.timeLabel});
}

/// Builds at most [maxActions] actions, highest priority first.
/// Deterministic: same context always yields the same list.
List<TodayAction> buildActions(ActionContext ctx,
    {int maxActions = 3}) {
  final out = <TodayAction>[];

  // Time-sensitive first: today's appointments, experiment due today.
  for (final a in ctx.appointmentsToday) {
    out.add(TodayAction(
      id: 'appt-${a.title}-${a.timeLabel}',
      title: 'Appointment today: ${a.title}',
      explanation: '${a.timeLabel} — see details and location.',
      destination: '/home/care',
      priority: 100,
      dismissKey: 'appt-${a.title}',
    ));
  }
  final exp = ctx.experimentDue;
  if (exp != null) {
    out.add(TodayAction(
      id: 'exp-today',
      title: 'Experiment check-in due',
      explanation:
          '${exp.title} · Day ${exp.dayNumber} of ${exp.durationDays}. Log DONE or MISSED.',
      destination: '/lab',
      priority: 90,
      dismissKey: 'exp-today',
    ));
  }

  // Incomplete daily actions (morning routine first, then sections).
  if (!ctx.morningDone) {
    out.add(const TodayAction(
      id: 'morning',
      title: 'Start your morning check-in',
      explanation: '30 seconds: sleep, mood, energy, one intention.',
      destination: '/home/morning',
      priority: 80,
      dismissKey: 'morning',
    ));
  }
  if (ctx.completedSections < ctx.totalSections) {
    final left = ctx.totalSections - ctx.completedSections;
    out.add(TodayAction(
      id: 'sections',
      title: left == 1
          ? 'One daily section left'
          : 'Complete your daily log',
      explanation:
          '${ctx.completedSections} of ${ctx.totalSections} sections logged. Closing the gap sharpens every trend.',
      destination: '/today',
      priority: 70,
      dismissKey: 'sections',
    ));
  }
  if (ctx.eveningWindow && !ctx.eveningDone) {
    out.add(const TodayAction(
      id: 'evening',
      title: 'Reflect on your day',
      explanation: 'One quiet minute: mood, energy, strain.',
      destination: '/home/evening',
      priority: 60,
      dismissKey: 'evening',
    ));
  }

  // Goal gaps: focus match first (explicit user goals win ties).
  final gaps = [...ctx.goalGaps]..sort((a, b) {
      final fa = a.matchesFocus ? 0 : 1;
      final fb = b.matchesFocus ? 0 : 1;
      return fa.compareTo(fb);
    });
  for (final g in gaps) {
    out.add(TodayAction(
      id: 'goal-${g.focusKey}',
      title: '${g.label} is open',
      explanation: g.detail,
      destination: '/today',
      priority: g.matchesFocus ? 55 : 50,
      dismissKey: 'goal-${g.focusKey}',
    ));
  }

  out.sort((a, b) => b.priority.compareTo(a.priority));
  return out.take(maxActions).toList();
}

/// Shown when nothing is actionable. Honest, never nagging.
const String caughtUpTitle = "You're all caught up.";
const String caughtUpBody =
    "Take a moment to review this week's progress.";
