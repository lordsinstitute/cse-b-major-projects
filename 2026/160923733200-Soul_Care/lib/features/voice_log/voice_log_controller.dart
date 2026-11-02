import 'package:flutter/material.dart';

import '../../app/providers/daily_health_provider.dart';
import '../../data/models/enums.dart';
import 'voice_gateway.dart';
import 'voice_parse_engine.dart';

/// One confirmable row in the "I found" card.
class VoiceSection {
  final String key;
  final String label;
  final String display;
  bool include;

  VoiceSection({
    required this.key,
    required this.label,
    required this.display,
    this.include = true,
  });
}

/// Voice-log flow state (provided locally inside the voice screen).
/// Nothing is saved until the user explicitly taps Save — and then only
/// the checked sections are written through the normal daily-health merge
/// path (previously saved sections are preserved).
class VoiceLogController extends ChangeNotifier {
  final VoiceInputGateway _gateway;
  final VoiceExtractor _extractor;

  VoiceLogController({
    VoiceInputGateway? gateway,
    VoiceExtractor? extractor,
  })  : _gateway = gateway ?? const UnavailableVoiceGateway(),
        _extractor = extractor ?? const DeterministicVoiceExtractor();

  String _transcript = '';
  String get transcript => _transcript;

  VoiceExtraction? _extraction;
  VoiceExtraction? get extraction => _extraction;

  bool _editing = false;
  bool get editing => _editing;

  bool _listening = false;
  bool get listening => _listening;

  bool _parsing = false;
  bool get parsing => _parsing;

  bool _saving = false;
  bool get saving => _saving;

  MicAvailability? _mic;
  MicAvailability? get mic => _mic;

  String? _notice;
  String? get notice => _notice;

  bool _saved = false;
  bool get saved => _saved;

  // Editable overrides (null = use parsed value).
  final Map<String, num> _overrides = {};
  final Map<String, bool> _include = {};

  void setTranscript(String v) {
    _transcript = v;
    _saved = false;
    notifyListeners();
  }

  Future<void> checkMic() async {
    try {
      _mic = await _gateway.check();
    } catch (_) {
      _mic = MicAvailability.unavailable;
    }
    notifyListeners();
  }

  /// One microphone capture → transcript → parse. Graceful on every
  /// failure path (denied/unavailable/empty all explain instead of crash).
  Future<void> listenAndParse() async {
    _notice = null;
    _listening = true;
    notifyListeners();
    try {
      final availability = await _gateway.check();
      _mic = availability;
      if (availability == MicAvailability.denied) {
        _notice =
            'Microphone access was denied. You can still type your update below — voice logging keeps working without the mic.';
        return;
      }
      if (availability != MicAvailability.available) {
        _notice =
            'Speech recognition is unavailable on this device right now. You can still type your update below.';
        return;
      }
      final heard = await _gateway.listenOnce();
      if (heard == null || heard.trim().isEmpty) {
        _notice =
            'I did not catch that — try again, or type your update below.';
        return;
      }
      _transcript = heard;
      await parse();
    } finally {
      _listening = false;
      notifyListeners();
    }
  }

  Future<void> parse() async {
    if (_transcript.trim().isEmpty) {
      _notice = 'Say or type your update first.';
      notifyListeners();
      return;
    }
    _parsing = true;
    _notice = null;
    notifyListeners();
    try {
      _extraction = await _extractor.extract(_transcript);
      _overrides.clear();
      _include.clear();
      _editing = false;
      _saved = false;
      if (!_extraction!.hasAnything) {
        _notice =
            'I could not pick out any trackable details — try mentioning sleep hours, movement, water, or how you feel. Nothing was saved.';
      }
    } finally {
      _parsing = false;
      notifyListeners();
    }
  }

  void toggleEditing() {
    _editing = !_editing;
    notifyListeners();
  }

  void clear() {
    _transcript = '';
    _extraction = null;
    _overrides.clear();
    _include.clear();
    _editing = false;
    _notice = null;
    _saved = false;
    notifyListeners();
  }

  // --- Section values (parsed or edited) ---

  double? get sleepHours =>
      _num('sleep')?.toDouble() ?? _extraction?.sleepHours;
  int? get energy => _num('energy')?.toInt() ?? _extraction?.energy;
  int? get mood => _num('mood')?.toInt() ?? _extraction?.mood;
  int? get stress => _num('stress')?.toInt() ?? _extraction?.stress;
  int? get exerciseMinutes =>
      _num('exercise')?.toInt() ?? _extraction?.exerciseMinutes;
  int? get waterGlasses =>
      _num('water')?.toInt() ?? _extraction?.waterGlasses;
  int? get meditationMinutes =>
      _num('meditation')?.toInt() ?? _extraction?.meditationMinutes;
  double? get screenHours =>
      _num('screen')?.toDouble() ?? _extraction?.screenTimeHours;

  num? _num(String key) => _overrides[key];

  bool included(String key) => _include[key] ?? true;

  void setIncluded(String key, bool v) {
    _include[key] = v;
    notifyListeners();
  }

  void adjust(String key, num delta, {num? min, num? max}) {
    final current = _currentFor(key);
    if (current == null) return;
    var next = current + delta;
    if (min != null && next < min) next = min;
    if (max != null && next > max) next = max;
    // Keep halves for hour-based sections, integers otherwise.
    _overrides[key] = (key == 'sleep' || key == 'screen')
        ? (next.toDouble() * 2).round() / 2
        : next.round();
    notifyListeners();
  }

  num? _currentFor(String key) => switch (key) {
        'sleep' => sleepHours,
        'energy' => energy,
        'mood' => mood,
        'stress' => stress,
        'exercise' => exerciseMinutes,
        'water' => waterGlasses,
        'meditation' => meditationMinutes,
        'screen' => screenHours,
        _ => null,
      };

  List<VoiceSection> sections() {
    final e = _extraction;
    if (e == null) return const [];
    final out = <VoiceSection>[];
    void add(String key, String label, String? display) {
      if (display == null) return;
      out.add(VoiceSection(
        key: key,
        label: label,
        display: display,
        include: included(key),
      ));
    }

    add('sleep', 'Sleep',
        sleepHours == null ? null : '${_fmtH(sleepHours!)}${e.feltRested == true ? ' · rested' : ''}');
    add('energy', 'Energy',
        energy == null ? null : '$energy/5');
    add('mood', 'Mood', mood == null ? null : '$mood/5');
    add('stress', 'Stress',
        stress == null ? null : '$stress/5');
    add('exercise', 'Exercise',
        exerciseMinutes == null
            ? null
            : '$exerciseMinutes min${e.exerciseType != null ? ' · ${e.exerciseType}' : ''}');
    add('water', 'Water',
        waterGlasses == null ? null : '$waterGlasses glasses');
    add('meditation', 'Meditation',
        meditationMinutes == null ? null : '$meditationMinutes min');
    add('screen', 'Screen time',
        screenHours == null ? null : _fmtH(screenHours!));
    return out;
  }

  static String _fmtH(double h) {
    if (h % 1 == 0) return '${h.toInt()}h';
    return '${h.toStringAsFixed(1)}h';
  }

  /// Saves checked sections through the normal merge path.
  /// Returns the number of sections saved.
  Future<int> save(DailyHealthProvider daily) async {
    final e = _extraction;
    if (e == null) return 0;
    _saving = true;
    _notice = null;
    notifyListeners();
    var count = 0;
    try {
      final today = daily.today;
      if (included('sleep') && sleepHours != null) {
        final ok = await daily.saveSleep(
          hours: sleepHours!.clamp(0, 24).toDouble(),
          quality: today?.sleepQuality ?? SleepQuality.okay,
          feltRested: e.feltRested ?? today?.feltRested ?? false,
        );
        if (ok) count++;
      }
      if (included('exercise') && exerciseMinutes != null) {
        final type = e.exerciseType ?? today?.exerciseType ?? 'Walk';
        final ok = await daily.saveMovement(
          type: type,
          minutes: exerciseMinutes!.clamp(0, 600),
          intensity: _intensityFor(type),
        );
        if (ok) count++;
      }
      if (included('water') && waterGlasses != null) {
        final ok = await daily.saveNutrition(
          mealQuality: today?.mealQuality ?? MealQuality.okay,
          waterGlasses: waterGlasses!.clamp(0, 30),
        );
        if (ok) count++;
      }
      if ((included('meditation') && meditationMinutes != null) ||
          (included('screen') && screenHours != null)) {
        final ok = await daily.saveMind(
          meditationMinutes: included('meditation') && meditationMinutes != null
              ? meditationMinutes!.clamp(0, 600)
              : (today?.meditationMinutes ?? 0),
          screenTimeHours: included('screen') && screenHours != null
              ? screenHours!.clamp(0, 24).toDouble()
              : (today?.screenTimeHours ?? 0),
        );
        if (ok) count++;
      }
      final moodVal = included('mood') && mood != null
          ? mood
          : (included('stress') && stress != null ? 6 - stress! : null);
      if (moodVal != null) {
        final ok = await daily.saveStressCheck(
          mood: MoodX.fromScore(moodVal.clamp(1, 5)),
          triggers: const [],
          controllability: 0.5,
        );
        if (ok) count++;
      }
      _saved = count > 0;
      if (!_saved) {
        _notice = 'Nothing was saved — uncheck nothing and try again.';
      }
      return count;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  static ExerciseIntensity _intensityFor(String type) {
    switch (type.toLowerCase()) {
      case 'run':
      case 'gym':
      case 'swim':
        return ExerciseIntensity.high;
      case 'walk':
      case 'stretch':
      case 'yoga':
        return ExerciseIntensity.low;
      default:
        return ExerciseIntensity.moderate;
    }
  }
}
