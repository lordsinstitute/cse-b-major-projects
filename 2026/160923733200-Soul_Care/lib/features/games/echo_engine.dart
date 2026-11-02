import 'dart:math';

/// Simon-style pattern recall: watch the tiles flash, then repeat the
/// pattern. The pattern grows by one tile each completed level. A wrong
/// tap ends the run — the score keeps completed levels only.
class EchoGame {
  static const int tileCount = 4;
  static const int startLength = 3;

  final Random _random;
  final List<int> sequence = [];
  final List<int> input = [];
  int levelsCompleted = 0;
  int mistakes = 0;
  bool over = false;

  EchoGame({Random? random}) : _random = random ?? Random() {
    _extend();
  }

  int get level => levelsCompleted + 1;
  int get longest => sequence.length;
  bool get awaitingInput => !over;

  void _extend() {
    while (sequence.length < startLength + levelsCompleted) {
      sequence.add(_random.nextInt(tileCount));
    }
    input.clear();
  }

  /// Taps a tile. Returns 'ok', 'level' (level completed), 'over', or
  /// 'ended' when the run already finished.
  String tap(int tile) {
    if (over) return 'ended';
    if (tile < 0 || tile >= tileCount) return 'ended';
    input.add(tile);
    final pos = input.length - 1;
    if (input[pos] != sequence[pos]) {
      mistakes++;
      over = true;
      return 'over';
    }
    if (input.length >= sequence.length) {
      levelsCompleted++;
      _extend();
      return 'level';
    }
    return 'ok';
  }

  void restart({Random? random}) {
    sequence.clear();
    input.clear();
    levelsCompleted = 0;
    mistakes = 0;
    over = false;
    _extend();
  }
}

/// Session score: completed levels matter most, mistakes cost a little.
int echoScore({required int levels, required int mistakes}) {
  return max(0, levels * 150 - mistakes * 20);
}
