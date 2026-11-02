import 'dart:math';

/// Curated health & wellness word list.
const wellnessWords = [
  'BREATHE',
  'SLEEP',
  'WATER',
  'CALM',
  'WALK',
  'YOGA',
  'MIND',
  'HEART',
  'REST',
  'FOCUS',
  'BALANCE',
  'ENERGY',
  'KINDNESS',
  'STRETCH',
  'NOURISH',
  'GRATITUDE',
  'PAUSE',
  'STRENGTH',
  'VITALITY',
  'MINDFUL',
];

/// Shuffles letters; retries until different from the original (anagrams of
/// a real word are always solvable — never unfair).
String scrambleWord(String word, Random random) {
  if (word.length <= 1) return word;
  for (var attempt = 0; attempt < 20; attempt++) {
    final letters = word.split('')..shuffle(random);
    final scrambled = letters.join();
    if (scrambled != word) return scrambled;
  }
  return word.split('').reversed.join() == word
      ? word
      : word.split('').reversed.join();
}

/// Session score: +100 per correct, −15 per wrong, plus a speed bonus.
int scrambleScore(
    {required int correct,
    required int incorrect,
    required int seconds}) {
  return max(
      0, correct * 100 - incorrect * 15 + max(0, 300 - seconds * 2));
}

/// Fixed 5-word session over a shuffled subset of the list.
class ScrambleGame {
  final List<String> words;
  int index = 0;
  int correct = 0;
  int incorrect = 0;
  late String current;
  final Random _random;

  ScrambleGame({Random? random, int wordCount = 5})
      : _random = random ?? Random(),
        words = [...wellnessWords]..shuffle(random ?? Random()) {
    words.length = min(wordCount, words.length);
    current = scrambleWord(words[0], _random);
  }

  bool get complete => index >= words.length;
  String? get answer => complete ? null : words[index];
  int get remaining => words.length - index;

  /// Returns true for a correct guess; advances on success only.
  bool guess(String text) {
    if (complete) return false;
    if (text.trim().toUpperCase() == words[index]) {
      correct++;
      index++;
      if (!complete) current = scrambleWord(words[index], _random);
      return true;
    }
    incorrect++;
    return false;
  }
}
