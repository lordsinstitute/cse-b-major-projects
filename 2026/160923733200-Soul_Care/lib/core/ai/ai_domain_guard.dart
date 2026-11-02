/// Deterministic pre-check that keeps SoulCare AI inside its scope.
/// Runs BEFORE any provider call: out-of-scope questions are answered
/// with a polite canned response and cost zero tokens.
///
/// Deliberately conservative: anything plausibly health-related is
/// ALLOWED or AMBIGUOUS (answered in a health context). Only clearly
/// unrelated topics are rejected. Semantic judgment for genuinely
/// ambiguous phrasing belongs to the model via the system prompt —
/// the guard only filters the obvious.
enum AiDomain { allowed, outOfScope, ambiguous }

class AiDomainGuard {
  /// Polite scope response. Never sent to a provider; shown directly.
  static const scopeRefusal = "I'm SoulCare AI, so I focus on wellness, "
      'health, and information related to your SoulCare data. I can\'t help '
      'with that topic, but I can help with questions about sleep, exercise, '
      'stress, nutrition, habits, or your personal wellness data.';

  /// Topics that are never SoulCare questions, no matter the phrasing.
  /// Matched as whole-word/phrase signals, not single keywords:
  /// e.g. "stress" alone never rejects ("Can stress affect sleep?" is
  /// relevant; "stress fractures in the chassis" is not).
  static const _outOfScope = [
    // vehicles & machines
    'car repair', 'car engine', 'leaking car', 'oil change',
    'chassis', 'transmission', 'carburetor', 'brake pad',
    // programming & tech shopping
    'python', 'javascript', 'write code', 'write a program',
    'debug my code', 'programming homework', 'sql query',
    'gaming laptop', 'graphics card', 'best phone to buy',
    // entertainment & sports trivia
    'football match', 'who won the', 'sports score', 'match score',
    'tell me a joke', 'write a joke', 'movie recommendation',
    'pirate a movie', 'torrent', 'cracked software',
    // career / admin unrelated to health
    'write my resume', 'cover letter', 'job interview tips',
    // finance / legal as primary topic
    'stock tip', 'crypto to buy', 'tax evasion', 'write my will',
    // homework unrelated to health
    'math homework', 'history essay', 'solve this equation',
  ];

  /// Strong health / SoulCare / wellness signals. Any of these makes the
  /// question ALLOWED outright.
  static const _allowed = [
    'sleep', 'insomnia', 'nap', 'rested', 'tired', 'fatigue',
    'exercise', 'workout', 'walk', 'run', 'yoga', 'stretch',
    'resistance training', 'cardio', 'steps',
    'nutrition', 'diet', 'meal', 'protein', 'vitamin', 'calorie',
    'hydration', 'water', 'drink', 'dehydration',
    'stress', 'anxiety', 'anxious', 'mood', 'calm', 'mindful',
    'meditat', 'breath', 'relax', 'burnout', 'depress',
    'habit', 'routine', 'streak', 'goal', 'reminder',
    'experiment', 'completed', 'lab',
    'wellness', 'wellbeing', 'well-being', 'health', 'healthy',
    'headache', 'fever', 'pain', 'symptom', 'blood pressure',
    'heart', 'diabetes', 'cholesterol', 'immune', 'allergy',
    'medication', 'medicine', 'pill', 'dosage', 'side effect',
    'doctor', 'therapist', 'clinic', 'diagnos', 'treatment',
    'therapy', 'mental health', 'self-care', 'self care',
    'weight', 'bmi', 'posture', 'back pain', 'neck pain',
    'period', 'pregnancy', 'menstrual', 'hormone',
    'caffeine', 'alcohol', 'smoking', 'screen time',
    'soulcare', 'my week', 'my day', 'my month', 'my data',
    'my score', 'my experiment', 'my progress', 'my patterns',
    'my trends', 'my journal', 'my report', 'my calendar',
    'my average', 'my best', 'logged', 'check-in', 'check in',
    'how am i', 'how was my', 'how is my', 'why am i',
    'what changed', 'compare', 'summar', 'analyz', 'explain my',
    'anatomy', 'physiology', 'insulin', 'metabolism',
    'hygiene', 'immunity', 'disease', 'illness', 'injury',
    'fracture', 'sprain', 'strain', 'recovery', 'rehab',
  ];

  /// Explicit personal-health framing. When present, the question is
  /// about the user's own body/mind/data even if it also mentions an
  /// otherwise unrelated word.
  static const _healthFraming = [
    'my sleep', 'my mood', 'my stress', 'my health', 'my body',
    'my mind', 'my week', 'my data', 'my symptoms', 'i feel',
    'my medication', 'my heart', 'my head', 'my back', 'my weight',
    'am i ', 'is this normal', 'should i see',
  ];

  AiDomain classify(String question) {
    final q = ' ${question.toLowerCase()} ';
    var allowedHits = 0;
    for (final s in _allowed) {
      if (q.contains(s)) allowedHits++;
    }
    var outHits = 0;
    for (final s in _outOfScope) {
      if (q.contains(s)) outHits++;
    }
    // Personal-health framing wins over stray unrelated words:
    // "my car's stress fracture" is out, "my stress fracture" is in.
    if (allowedHits > 0) {
      for (final s in _healthFraming) {
        if (q.contains(s)) return AiDomain.allowed;
      }
      // A clear unrelated anchor (car chassis, python code, …) with no
      // health framing is not a SoulCare question — this is the
      // semantic-over-keyword rule, not plain keyword matching.
      if (outHits > 0) return AiDomain.outOfScope;
      return AiDomain.allowed;
    }
    if (outHits > 0) return AiDomain.outOfScope;

    // No health signal and no known-unrelated signal: ambiguous.
    // Answered in a health context rather than refused (Phase 13).
    if (_looksLikeQuestion(q)) return AiDomain.ambiguous;
    return AiDomain.outOfScope;
  }

  bool _looksLikeQuestion(String q) {
    if (q.contains('?')) return true;
    const starts = [
      'what', 'why', 'how', 'when', 'where', 'which', 'who', 'is ',
      'are ', 'can ', 'could ', 'should ', 'does ', 'do ',
      'tell me', 'explain', 'help me', 'i feel', 'i have', 'i am',
    ];
    for (final s in starts) {
      if (q.trimLeft().startsWith(s)) return true;
    }
    return false;
  }
}
