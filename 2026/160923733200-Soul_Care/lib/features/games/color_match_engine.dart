import 'dart:math';

import 'package:flutter/material.dart';

/// Stroop-style focus game: a color word shown in a possibly different ink.
/// Always tap the INK color, not the word. Congruent rounds (word == ink)
/// keep it fair and calm.
class StroopChoice {
  final String name;
  final Color color;
  const StroopChoice(this.name, this.color);
}

const stroopChoices = [
  StroopChoice('Red', Colors.red),
  StroopChoice('Blue', Colors.blue),
  StroopChoice('Green', Colors.green),
  StroopChoice('Orange', Colors.orange),
];

class StroopRound {
  /// Index into [stroopChoices] of the displayed word.
  final int word;
  final int ink;
  const StroopRound(this.word, this.ink);

  bool get congruent => word == ink;
}

/// Session score: +100 per correct, −25 per wrong, plus a speed bonus.
int stroopScore(
    {required int correct,
    required int incorrect,
    required int seconds}) {
  return max(
      0, correct * 100 - incorrect * 25 + max(0, 300 - seconds * 2));
}

/// Fixed-length Stroop session (10 rounds, half congruent on average).
class StroopGame {
  static const int totalRounds = 10;

  final Random _random;
  int index = 0;
  int correct = 0;
  int incorrect = 0;
  late StroopRound current;

  StroopGame({Random? random}) : _random = random ?? Random() {
    current = _deal();
  }

  bool get complete => index >= totalRounds;
  int get remaining => totalRounds - index;

  StroopRound _deal() {
    final word = _random.nextInt(stroopChoices.length);
    // Congruent half the time so the task stays readable, not tricky.
    final ink = _random.nextBool()
        ? word
        : _random.nextInt(stroopChoices.length);
    return StroopRound(word, ink);
  }

  /// Answer with a color name. Returns true when it matched the ink.
  /// Advances the round either way.
  bool answer(String name) {
    if (complete) return false;
    final ok = name == stroopChoices[current.ink].name;
    if (ok) {
      correct++;
    } else {
      incorrect++;
    }
    index++;
    if (!complete) current = _deal();
    return ok;
  }
}
