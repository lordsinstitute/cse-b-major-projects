/// Deterministic voice-log parser: plain transcript in, structured
/// candidate values out. Pure functions, no randomness, no network.
///
/// The parser only *proposes* values. The app validates them, the user
/// confirms them, and only confirmed sections are saved. Anything the
/// parser cannot understand is reported back as ignored — never guessed.
class VoiceExtraction {
  final double? sleepHours;
  final bool? feltRested;
  final int? energy; // 1..5
  final int? mood; // 1..5
  final int? stress; // 1 calm .. 5 high
  final int? exerciseMinutes;
  final String? exerciseType;
  final int? waterGlasses;
  final int? meditationMinutes;
  final double? screenTimeHours;

  /// Non-blocking notes: contradictions, clamps, ignored phrases.
  final List<String> warnings;

  /// True when at least one usable value was found.
  bool get hasAnything =>
      sleepHours != null ||
      energy != null ||
      mood != null ||
      stress != null ||
      exerciseMinutes != null ||
      waterGlasses != null ||
      meditationMinutes != null ||
      screenTimeHours != null;

  const VoiceExtraction({
    this.sleepHours,
    this.feltRested,
    this.energy,
    this.mood,
    this.stress,
    this.exerciseMinutes,
    this.exerciseType,
    this.waterGlasses,
    this.meditationMinutes,
    this.screenTimeHours,
    this.warnings = const [],
  });
}

const Map<String, String> _numberWords = {
  'zero': '0',
  'one': '1',
  'two': '2',
  'three': '3',
  'four': '4',
  'five': '5',
  'six': '6',
  'seven': '7',
  'eight': '8',
  'nine': '9',
  'ten': '10',
  'eleven': '11',
  'twelve': '12',
  'thirteen': '13',
  'fourteen': '14',
  'fifteen': '15',
  'sixteen': '16',
  'seventeen': '17',
  'eighteen': '18',
  'nineteen': '19',
  'twenty': '20',
  'thirty': '30',
  'forty': '40',
  'fifty': '50',
  'sixty': '60',
  'half': '0.5',
  'quarter': '0.25',
};

/// Lower-cases, converts number words, normalizes units.
String normalizeTranscript(String raw) {
  var t = ' ${raw.toLowerCase()} ';
  // Spoken fractions first ("half an hour" → "0.5 hours").
  t = t.replaceAll(RegExp(r'\bhalf an? hour\b'), ' 0.5 hours ');
  t = t.replaceAll(RegExp(r'\bhalf an? minute\b'), ' 0.5 minutes ');
  t = t.replaceAll(RegExp(r'\bquarter of an? hour\b'), ' 0.25 hours ');
  // "twenty five" style compounds are out of scope; single words suffice.
  _numberWords.forEach((word, digit) {
    t = t.replaceAll(RegExp('\\b$word\\b'), ' $digit ');
  });
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  // "an 0.5" / "a 0.5" from "half an hour" → keep the 0.5.
  t = t.replaceAll(RegExp(r'\ba(n)? 0\.5\b'), '0.5');
  return t;
}

/// Splits into clauses on sentence/pause boundaries. Decimal points in
/// numbers (e.g. "0.5 hours") are preserved — only sentence-ending periods
/// (followed by whitespace or the end) split.
List<String> splitClauses(String normalized) {
  return normalized
      .split(RegExp(r'[,;]+|\.(?=\s|$)|\band then\b|\band\b'))
      .map((s) => s.trim().replaceAll(RegExp(r'\.+$'), ''))
      .where((s) => s.isNotEmpty)
      .toList();
}

double? _firstDouble(RegExp re, String clause, [int group = 1]) {
  final m = re.firstMatch(clause);
  if (m == null) return null;
  return double.tryParse(m.group(group) ?? '');
}

int? _firstInt(RegExp re, String clause, [int group = 1]) {
  final v = _firstDouble(re, clause, group);
  return v?.round();
}

/// Parses a transcript into candidate values. Deterministic.
VoiceExtraction parseVoiceLog(String transcript) {
  final normalized = normalizeTranscript(transcript);
  final clauses = splitClauses(normalized);
  final warnings = <String>[];

  final sleepVals = <double>[];
  var restedTrue = false;
  var restedFalse = false;
  final energyVals = <int>[];
  final moodVals = <int>[];
  final stressVals = <int>[];
  final exerciseVals = <int>[];
  String? exerciseType;
  final waterVals = <int>[];
  final meditationVals = <int>[];
  final screenVals = <double>[];

  final num = r'(\d+(?:\.\d+)?)';

  for (final c in clauses) {
    var used = false;

    // --- Sleep ---
    if (RegExp(r'\bsleep\b|\bslept\b|\bsleeping\b').hasMatch(c)) {
      final h = _firstDouble(
          RegExp('$num\\s*(hours?|hrs?|\\bh\\b)'), c);
      if (h != null) {
        sleepVals.add(h);
        used = true;
      }
      if (RegExp(
              r'tired|exhausted|groggy|restless|badly|poorly|not (well|enough)')
          .hasMatch(c)) {
        restedFalse = true;
        used = true;
      }
      if (RegExp(r'well rested|great|deeply|soundly|refreshed')
          .hasMatch(c)) {
        restedTrue = true;
        used = true;
      }
    }

    // --- Energy ---
    if (RegExp(r'\benergy\b|\benergetic\b|\btired\b|\bexhausted\b|\bsluggish\b|\bactive\b|\bawake\b')
        .hasMatch(c)) {
      if (RegExp(r'very|so|really|super').hasMatch(c) &&
          RegExp(r'tired|exhausted|drained|sluggish').hasMatch(c)) {
        energyVals.add(1);
        used = true;
      } else if (RegExp(r'little|bit|slightly|kind of|a tad')
              .hasMatch(c) &&
          RegExp(r'tired|sleepy').hasMatch(c)) {
        energyVals.add(3);
        used = true;
      } else if (RegExp(r'tired|exhausted|drained|sluggish|low')
          .hasMatch(c)) {
        energyVals.add(2);
        used = true;
      } else if (RegExp(
              r'great|fantastic|energetic|full of energy|wide awake')
          .hasMatch(c)) {
        energyVals.add(5);
        used = true;
      } else if (RegExp(r'okay|ok|fine|alright|decent').hasMatch(c)) {
        energyVals.add(3);
        used = true;
      }
    }

    // --- Mood ---
    if (RegExp(
            r'\bmood\b|\bhappy\b|\bsad\b|\bdown\b|\bgreat\b|\banxious\b|\bfeeling\b|\bfeel\b|\bfelt\b')
        .hasMatch(c)) {
      if (RegExp(r'very (sad|down|low)|terrible|awful|depressed')
          .hasMatch(c)) {
        moodVals.add(1);
        used = true;
      } else if (RegExp(r'sad|down|blue|meh|low').hasMatch(c) &&
          !RegExp(r'sleep|bed').hasMatch(c)) {
        moodVals.add(2);
        used = true;
      } else if (RegExp(r'amazing|fantastic|wonderful|thrilled|overjoyed')
          .hasMatch(c)) {
        moodVals.add(5);
        used = true;
      } else if (RegExp(r'happy|good|great|positive|content|cheerful')
          .hasMatch(c)) {
        moodVals.add(4);
        used = true;
      } else if (RegExp(r'okay|ok|fine|alright|neutral').hasMatch(c)) {
        moodVals.add(3);
        used = true;
      }
    }

    // --- Stress ---
    if (RegExp(r'\bstress\b|\bstressed\b|\bstressful\b|\banxious\b|\boverwhelm')
        .hasMatch(c)) {
      if (RegExp(r'very|so|really|super|extremely|incredibly')
          .hasMatch(c)) {
        stressVals.add(5);
        used = true;
      } else if (RegExp(r'little|bit|slightly|kind of|somewhat|moderately')
          .hasMatch(c)) {
        stressVals.add(3);
        used = true;
      } else if (RegExp(r'not|no|zero|unstressed|calm|relaxed|chill')
          .hasMatch(c)) {
        stressVals.add(1);
        used = true;
      } else {
        stressVals.add(4);
        used = true;
      }
    }
    if (RegExp(r'\bcalm\b|\brelaxed\b|\bpeaceful\b|\bchill\b')
            .hasMatch(c) &&
        !RegExp(r'stress').hasMatch(c)) {
      stressVals.add(2);
      used = true;
    }

    // --- Exercise ---
    if (RegExp(
            r'\bwalk\b|\bwalked\b|\brun\b|\bran\b|\bjog\b|\bexercise\b|\bworkout\b|\byoga\b|\bswim\b|\bcycl|\bgym\b|\bhike\b|\bstretch')
        .hasMatch(c)) {
      final mins = _firstInt(
          RegExp('$num\\s*(minutes?|mins?|\\bmin\\b|hours?|hrs?|\\bh\\b)'),
          c);
      if (mins != null) {
        var m = mins;
        if (RegExp('$num\\s*(hours?|hrs?|\\bh\\b)').hasMatch(c)) {
          m = (mins * 60);
        }
        exerciseVals.add(m);
        used = true;
      } else if (RegExp(r'walk').hasMatch(c)) {
        // "went for a walk" with no duration: noted, not measurable.
        used = true;
      }
      final type = RegExp(
              r'\b(walk|run|jog|yoga|swim|gym|hike|cycle|stretch|workout)\w*')
          .firstMatch(c);
      if (type != null) {
        exerciseType = type.group(1)![0].toUpperCase() +
            type.group(1)!.substring(1);
      }
    }

    // --- Hydration ---
    if (RegExp(r'\bwater\b|\bdrank\b|\bdrink\b|\bglass|\bhydrat')
        .hasMatch(c)) {
      final g = _firstInt(RegExp('$num\\s*(glasses?|cups?|litres?|liters?|\\bl\\b)'), c);
      if (g != null) {
        var glasses = g;
        if (RegExp('$num\\s*(litres?|liters?)').hasMatch(c)) {
          glasses = g * 4;
        }
        waterVals.add(glasses);
        used = true;
      }
    }

    // --- Meditation ---
    if (RegExp(r'\bmeditat|\bmindful|\bbreath|\byoga\b').hasMatch(c) &&
        RegExp('$num\\s*(minutes?|mins?|\\bmin\\b|seconds?|secs?|\\bsec\\b)')
            .hasMatch(c)) {
      var mins = _firstInt(
          RegExp('$num\\s*(minutes?|mins?|\\bmin\\b|seconds?|secs?|\\bsec\\b)'),
          c)!;
      if (RegExp('$num\\s*(seconds?|secs?|\\bsec\\b)').hasMatch(c)) {
        mins = (mins / 60).round().clamp(1, 600);
      }
      meditationVals.add(mins);
      used = true;
    }

    // --- Screen time ---
    if (RegExp(r'\bscreen\b|\bphone\b|\btv\b|\bscrolling\b|\bnetflix\b')
        .hasMatch(c)) {
      final h = _firstDouble(
          RegExp('$num\\s*(hours?|hrs?|\\bh\\b|minutes?|mins?)'), c);
      if (h != null) {
        var hours = h;
        if (RegExp('$num\\s*(minutes?|mins?)').hasMatch(c)) {
          hours = h / 60;
        }
        screenVals.add(hours);
        used = true;
      }
    }

    if (!used) {
      warnings.add('Could not use: "$c".');
    }
  }

  // Contradictions: same metric heard twice with different values.
  T pickFirst<T>(List<T> vals, String label, String Function(T) fmt) {
    if (vals.length > 1 &&
        vals.toSet().length > 1) {
      warnings.add(
          'I heard two different $label values (${vals.map(fmt).join(' vs ')}) — I kept the first; adjust it below if needed.');
    }
    return vals.first;
  }

  double? sleep;
  if (sleepVals.isNotEmpty) {
    final s = pickFirst(sleepVals, 'sleep', (v) => '${v}h');
    if (s < 0 || s > 24) {
      warnings.add('Sleep of ${s}h is outside 0–24h, so it was dropped.');
    } else {
      sleep = s;
    }
  }
  int? clampScale(int? v, String label) {
    if (v == null) return null;
    if (v < 1 || v > 5) {
      warnings.add('$label was outside 1–5, so it was dropped.');
      return null;
    }
    return v;
  }

  int? water;
  if (waterVals.isNotEmpty) {
    final w = pickFirst(waterVals, 'water', (v) => '$v glasses');
    if (w < 0 || w > 30) {
      warnings.add('Water of $w glasses looks off, so it was dropped.');
    } else {
      water = w;
    }
  }
  int? exercise;
  if (exerciseVals.isNotEmpty) {
    final m = pickFirst(exerciseVals, 'exercise', (v) => '$v min');
    if (m < 0 || m > 600) {
      warnings.add('Exercise of $m min looks off, so it was dropped.');
    } else {
      exercise = m;
    }
  }
  int? meditation;
  if (meditationVals.isNotEmpty) {
    final m = pickFirst(meditationVals, 'meditation', (v) => '$v min');
    if (m < 0 || m > 600) {
      warnings.add('Meditation of $m min looks off.');
    } else {
      meditation = m;
    }
  }
  double? screen;
  if (screenVals.isNotEmpty) {
    final h = pickFirst(screenVals, 'screen time', (v) => '${v}h');
    if (h < 0 || h > 24) {
      warnings.add('Screen time of ${h}h looks off, so it was dropped.');
    } else {
      screen = h;
    }
  }

  return VoiceExtraction(
    sleepHours: sleep,
    feltRested: restedTrue && !restedFalse
        ? true
        : (!restedTrue && restedFalse ? false : null),
    energy: energyVals.isEmpty
        ? null
        : clampScale(pickFirst(energyVals, 'energy', (v) => '$v/5'), 'Energy'),
    mood: moodVals.isEmpty
        ? null
        : clampScale(pickFirst(moodVals, 'mood', (v) => '$v/5'), 'Mood'),
    stress: stressVals.isEmpty
        ? null
        : clampScale(pickFirst(stressVals, 'stress', (v) => '$v/5'), 'Stress'),
    exerciseMinutes: exercise,
    exerciseType:
        exercise != null && exercise > 0 ? exerciseType : null,
    waterGlasses: water,
    meditationMinutes: meditation,
    screenTimeHours: screen,
    warnings: warnings,
  );
}
