// Game Mode scoring: one deterministic, centralized formula used for every player,
// so results are always comparable and "just wait between correct notes" can never win.
//
// Design goals (see product spec):
//   - Accuracy is the largest factor, but cannot win alone.
//   - Timing rewards playing close to the song's own rhythm (not raw speed).
//   - Fluency punishes long stalls between notes, proportionally (not all-or-nothing).
//   - Speed is a small tie-breaking component only.
(function (global) {
  // Timing tolerance windows, in milliseconds, off the note's expected onset time.
  const TIMING_WINDOWS = {
    perfect: 100,
    good: 250,
    acceptable: 500,
  };

  // Final score = 100 * (accuracy*W.accuracy + timing*W.timing + fluency*W.fluency + speed*W.speed)
  // Each of accuracy/timing/fluency/speed is a 0-100 value; weights sum to 1.
  const SCORE_WEIGHTS = {
    accuracy: 0.50,
    timing: 0.25,
    fluency: 0.20,
    speed: 0.05,
  };

  // Longest gap (ms) between two consecutive correct notes that's still considered
  // "reasonable" before fluency starts taking a proportional penalty.
  const MAX_REASONABLE_GAP_MS = 500;

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  // Smooth 0-100 timing quality: 100 at 0ms off, decaying to ~0 by `acceptable`ms off.
  // Bucketed thresholds are still respected as anchor points (perfect/good/acceptable).
  function timingQualityFromDiff(diffMs) {
    const absDiff = Math.abs(diffMs);
    if (absDiff <= TIMING_WINDOWS.perfect) return 100;
    if (absDiff <= TIMING_WINDOWS.good) {
      return 100 - ((absDiff - TIMING_WINDOWS.perfect) / (TIMING_WINDOWS.good - TIMING_WINDOWS.perfect)) * 20; // 100 -> 80
    }
    if (absDiff <= TIMING_WINDOWS.acceptable) {
      return 80 - ((absDiff - TIMING_WINDOWS.good) / (TIMING_WINDOWS.acceptable - TIMING_WINDOWS.good)) * 30; // 80 -> 50
    }
    // Beyond the acceptable window, quality keeps decaying but never fully hits zero
    // credit for a correct note - it's still the right note, just poorly timed.
    const overshoot = absDiff - TIMING_WINDOWS.acceptable;
    return clamp(50 - (overshoot / TIMING_WINDOWS.acceptable) * 30, 5, 50);
  }

  // Fluency for a single gap between two correct notes, vs. that gap's expected
  // duration from the song's own rhythm. Rushed AND stalled gaps are penalized;
  // only gaps well beyond `MAX_REASONABLE_GAP_MS` past the expected gap take the
  // full proportional "long pause" penalty (deliberate slow play).
  function fluencyForGap(actualGapMs, expectedGapMs) {
    const extra = actualGapMs - expectedGapMs;
    if (extra <= MAX_REASONABLE_GAP_MS) {
      // Within a reasonable window around the expected gap (including rushing a bit).
      const deviation = Math.abs(extra);
      return clamp(100 - (deviation / MAX_REASONABLE_GAP_MS) * 30, 60, 100);
    }
    // Proportional penalty for stalling well past the expected gap - never an
    // instant zero, so a single long pause doesn't wreck an otherwise good turn.
    const overage = extra - MAX_REASONABLE_GAP_MS;
    return clamp(60 - (overage / 1000) * 20, 5, 60);
  }

  // Aggregates a player's raw gameplay samples (see GameEngine) into the four
  // 0-100 components, then the single final 0-1000 score.
  function computeScore({ correctNotes, wrongAttempts, timingSamples, fluencySamples, completionSeconds, expectedTotalSeconds }) {
    const totalAttempts = correctNotes + wrongAttempts;
    const accuracy = totalAttempts > 0 ? (correctNotes / totalAttempts) * 100 : 0;

    const timing = timingSamples.length > 0
      ? timingSamples.reduce((sum, v) => sum + v, 0) / timingSamples.length
      : 100; // no timed notes yet (e.g. only the un-penalized first note) - neutral/full credit

    const fluency = fluencySamples.length > 0
      ? fluencySamples.reduce((sum, v) => sum + v, 0) / fluencySamples.length
      : 100;

    // Speed is intentionally small: only rewards finishing at or faster than the
    // song's own expected duration, capped so it can never dominate the score.
    const speedRatio = completionSeconds > 0 ? expectedTotalSeconds / completionSeconds : 1;
    const speed = clamp(speedRatio * 100, 0, 100);

    const score = Math.round(
      100 * (
        (accuracy / 100) * SCORE_WEIGHTS.accuracy +
        (timing / 100) * SCORE_WEIGHTS.timing +
        (fluency / 100) * SCORE_WEIGHTS.fluency +
        (speed / 100) * SCORE_WEIGHTS.speed
      ) * 10 // scale 0-100 composite up to a ~0-1000 point score
    );

    return {
      accuracy: Math.round(accuracy),
      timing: Math.round(timing),
      fluency: Math.round(fluency),
      speed: Math.round(speed),
      score,
    };
  }

  // Deterministic ranking used for both the live and final leaderboards.
  function comparePlayers(a, b) {
    if (b.score !== a.score) return b.score - a.score;
    if (b.accuracy !== a.accuracy) return b.accuracy - a.accuracy;
    if (b.timing !== a.timing) return b.timing - a.timing;
    if (b.fluency !== a.fluency) return b.fluency - a.fluency;
    return (a.completionTime || Infinity) - (b.completionTime || Infinity);
  }

  global.GameScoring = {
    TIMING_WINDOWS,
    SCORE_WEIGHTS,
    MAX_REASONABLE_GAP_MS,
    timingQualityFromDiff,
    fluencyForGap,
    computeScore,
    comparePlayers,
  };
})(window);
