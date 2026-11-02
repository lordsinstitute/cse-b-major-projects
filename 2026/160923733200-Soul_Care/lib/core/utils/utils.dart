// Utility functions for SoulCare
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../constants/app_constants.dart';
import '../extensions/extensions.dart';

/// Generates a unique ID
String generateId() => const Uuid().v4();

/// One-way FNV-1a hash for short local secrets (e.g. the journal PIN).
/// Only the hash is ever persisted — never the secret itself.
String hashPin(String secret) {
  const salt = 'soulcare-local-pin-v1';
  var hash = 0xcbf29ce484222325;
  final input = '$salt:$secret';
  for (var i = 0; i < input.length; i++) {
    hash ^= input.codeUnitAt(i);
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// Formats a date for display
String formatDate(DateTime date, {String? format}) {
  final formatter = DateFormat(format ?? AppConstants.displayDateFormat);
  return formatter.format(date);
}

/// Formats a date for storage (ISO8601 date only)
String formatDateForStorage(DateTime date) {
  return date.toIso8601String().split('T').first;
}

/// Parses a date from storage format
DateTime? parseDateFromStorage(String dateString) {
  return dateString.tryParseDateTime()?.dateOnly();
}

/// Formats a time for display
String formatTime(DateTime time, {bool use24Hour = false}) {
  final formatter = DateFormat(use24Hour ? 'HH:mm' : 'h:mm a');
  return formatter.format(time);
}

/// Formats a duration in minutes to a readable string
String formatDuration(int minutes) {
  if (minutes < 60) {
    return '${minutes}m';
  }
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  if (remainingMinutes == 0) {
    return '${hours}h';
  }
  return '${hours}h ${remainingMinutes}m';
}

/// Formats a duration in hours to a readable string
String formatHours(double hours) {
  if (hours < 1) {
    return '${(hours * 60).round()}m';
  }
  final wholeHours = hours.floor();
  final minutes = ((hours - wholeHours) * 60).round();
  if (minutes == 0) {
    return '${wholeHours}h';
  }
  return '${wholeHours}h ${minutes}m';
}

/// Calculates a wellness score from various metrics (0-100)
int calculateWellnessScore({
  required double sleepScore,
  required double exerciseScore,
  required double nutritionScore,
  required double mindfulnessScore,
  required double stressScore,
}) {
  // Weighted average: sleep 25%, exercise 20%, nutrition 20%, mindfulness 15%, stress 20%
  final score = (sleepScore * 0.25) +
      (exerciseScore * 0.20) +
      (nutritionScore * 0.20) +
      (mindfulnessScore * 0.15) +
      (stressScore * 0.20);
  return score.round().clamp(0, 100);
}

/// Calculates sleep score (0-100)
int calculateSleepScore(double hours, int quality, bool feltRested) {
  // Hours score: optimal 7-9 hours
  double hoursScore;
  if (hours >= 7 && hours <= 9) {
    hoursScore = 100;
  } else if (hours >= 6 && hours < 7) {
    hoursScore = 80;
  } else if (hours > 9 && hours <= 10) {
    hoursScore = 90;
  } else if (hours >= 5 && hours < 6) {
    hoursScore = 60;
  } else {
    hoursScore = 40;
  }

  // Quality score (1-5 scale)
  final qualityScore = (quality / 5) * 100;

  // Felt rested bonus
  final restedBonus = feltRested ? 10 : 0;

  final score = (hoursScore * 0.5) + (qualityScore * 0.4) + restedBonus;
  return score.round().clamp(0, 100);
}

/// Calculates exercise score (0-100)
int calculateExerciseScore(int minutes, String intensity) {
  // Minutes score: target 30+ minutes
  double minutesScore;
  if (minutes >= 60) {
    minutesScore = 100;
  } else if (minutes >= 45) {
    minutesScore = 90;
  } else if (minutes >= 30) {
    minutesScore = 80;
  } else if (minutes >= 15) {
    minutesScore = 60;
  } else if (minutes > 0) {
    minutesScore = 40;
  } else {
    minutesScore = 0;
  }

  // Intensity multiplier
  double intensityMultiplier;
  switch (intensity.toLowerCase()) {
    case 'high':
      intensityMultiplier = 1.2;
      break;
    case 'moderate':
      intensityMultiplier = 1.0;
      break;
    case 'low':
      intensityMultiplier = 0.8;
      break;
    default:
      intensityMultiplier = 1.0;
  }

  final score = (minutesScore * intensityMultiplier).round();
  return score.clamp(0, 100);
}

/// Calculates nutrition score (0-100)
int calculateNutritionScore(int mealQuality, int waterGlasses) {
  // Meal quality (1-5 scale)
  final mealScore = (mealQuality / 5) * 100;

  // Water score: target 8 glasses
  double waterScore;
  if (waterGlasses >= 8) {
    waterScore = 100;
  } else if (waterGlasses >= 6) {
    waterScore = 80;
  } else if (waterGlasses >= 4) {
    waterScore = 60;
  } else if (waterGlasses > 0) {
    waterScore = 40;
  } else {
    waterScore = 20;
  }

  final score = (mealScore * 0.6) + (waterScore * 0.4);
  return score.round().clamp(0, 100);
}

/// Calculates mindfulness score (0-100)
int calculateMindfulnessScore(int meditationMinutes, double screenTimeHours) {
  // Meditation score: target 20+ minutes
  double meditationScore;
  if (meditationMinutes >= 30) {
    meditationScore = 100;
  } else if (meditationMinutes >= 20) {
    meditationScore = 90;
  } else if (meditationMinutes >= 10) {
    meditationScore = 70;
  } else if (meditationMinutes > 0) {
    meditationScore = 50;
  } else {
    meditationScore = 30;
  }

  // Screen time penalty: target < 2 hours
  double screenTimeScore;
  if (screenTimeHours <= 1) {
    screenTimeScore = 100;
  } else if (screenTimeHours <= 2) {
    screenTimeScore = 80;
  } else if (screenTimeHours <= 4) {
    screenTimeScore = 60;
  } else if (screenTimeHours <= 6) {
    screenTimeScore = 40;
  } else {
    screenTimeScore = 20;
  }

  final score = (meditationScore * 0.7) + (screenTimeScore * 0.3);
  return score.round().clamp(0, 100);
}

/// Calculates stress score (0-100, higher is better/lower stress)
int calculateStressScore(int mood, List<String> triggers, double controllability) {
  // Mood score (1-5 scale, inverted for stress)
  final moodScore = ((6 - mood) / 5) * 100;

  // Triggers penalty
  double triggersScore;
  if (triggers.isEmpty) {
    triggersScore = 100;
  } else if (triggers.length <= 2) {
    triggersScore = 80;
  } else if (triggers.length <= 4) {
    triggersScore = 60;
  } else {
    triggersScore = 40;
  }

  // Controllability score (0-1 scale)
  final controlScore = controllability * 100;

  final score = (moodScore * 0.4) + (triggersScore * 0.3) + (controlScore * 0.3);
  return score.round().clamp(0, 100);
}

/// Validates an email address
bool isValidEmail(String email) {
  final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
  return regex.hasMatch(email);
}

/// Validates a date string in YYYY-MM-DD format
bool isValidDateString(String dateString) {
  final regex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  if (!regex.hasMatch(dateString)) return false;
  final date = dateString.tryParseDateTime();
  return date != null;
}

/// Gets a color for a score (green to red gradient)
int getScoreColor(int score) {
  if (score >= 80) return 0xFF2E7D32; // Green
  if (score >= 60) return 0xFF689F38; // Light green
  if (score >= 40) return 0xFFF9A825; // Yellow
  if (score >= 20) return 0xFFF57C00; // Orange
  return 0xFFC62828; // Red
}

/// Gets a label for a score
String getScoreLabel(int score) {
  if (score >= 80) return 'Excellent';
  if (score >= 60) return 'Good';
  if (score >= 40) return 'Fair';
  if (score >= 20) return 'Needs Attention';
  return 'Critical';
}

/// Debounces a function call
Function debounce(Function fn, Duration delay) {
  var timer = <dynamic>[];
  return () {
    if (timer.isNotEmpty) {
      (timer.first as dynamic).cancel();
    }
    timer = [Future.delayed(delay, () => fn())];
  };
}

/// Throttles a function call
Function throttle(Function fn, Duration delay) {
  var lastCall = DateTime.fromMillisecondsSinceEpoch(0);
  return () {
    final now = DateTime.now();
    if (now.difference(lastCall) >= delay) {
      lastCall = now;
      fn();
    }
  };
}