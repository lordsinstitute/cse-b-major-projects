import 'dart:math';

/// Calm bubble popping: bubbles appear on a 4×4 board, pop them before
/// they fade. Timing lives in the screen (30-second session); this engine
/// only tracks board state, pops, misses and combos. Deterministic.
class BubblePop {
  static const int gridSize = 16;

  final Random _random;
  final List<bool> active;
  int popped = 0;
  int wrong = 0;
  int combo = 0;
  int maxCombo = 0;

  BubblePop({Random? random})
      : _random = random ?? Random(),
        active = List<bool>.filled(gridSize, false);

  int get lit => active.where((a) => a).length;

  /// Lights one random dark cell. No-op when the board is full.
  /// Returns the lit index, or -1 when nothing changed.
  int spawn() {
    final dark = <int>[];
    for (var i = 0; i < active.length; i++) {
      if (!active[i]) dark.add(i);
    }
    if (dark.isEmpty) return -1;
    final pick = dark[_random.nextInt(dark.length)];
    active[pick] = true;
    return pick;
  }

  /// Pops a cell. Returns true for a real pop (combo grows), false for a
  /// miss on an empty cell (combo resets).
  bool pop(int index) {
    if (index < 0 || index >= active.length) return false;
    if (!active[index]) {
      combo = 0;
      wrong++;
      return false;
    }
    active[index] = false;
    popped++;
    combo++;
    if (combo > maxCombo) maxCombo = combo;
    return true;
  }

  void restart() {
    for (var i = 0; i < active.length; i++) {
      active[i] = false;
    }
    popped = 0;
    wrong = 0;
    combo = 0;
    maxCombo = 0;
  }
}

/// Session score: pops plus a small combo bonus, misses cost a little.
int bubbleScore(
    {required int popped,
    required int maxCombo,
    required int wrong}) {
  return max(0, popped * 10 + maxCombo * 5 - wrong * 2);
}
