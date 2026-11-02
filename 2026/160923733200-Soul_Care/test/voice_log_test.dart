import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/app/providers/daily_health_provider.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/enums.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/data/repositories/stress_repository.dart';
import 'package:soul_care/features/voice_log/voice_gateway.dart';
import 'package:soul_care/features/voice_log/voice_log_controller.dart';
import 'package:soul_care/features/voice_log/voice_log_screen.dart';
import 'package:soul_care/features/voice_log/voice_parse_engine.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_voice');
  Hive.init(dir.path);
  await Future.wait([
    Hive.openBox(LocalDatabase.dailyBoxName),
    Hive.openBox(LocalDatabase.stressBoxName),
  ]);
}

const String kExample =
    "I slept around seven hours, felt a little tired, walked for thirty minutes, drank six glasses of water and I'm feeling stressed today.";

void main() {
  group('parser — natural language', () {
    test('spec example extracts sleep/energy/exercise/water/stress', () {
      final e = parseVoiceLog(kExample);
      expect(e.sleepHours, 7);
      expect(e.energy, 3);
      expect(e.exerciseMinutes, 30);
      expect(e.exerciseType, 'Walk');
      expect(e.waterGlasses, 6);
      expect(e.stress, 4);
      expect(e.hasAnything, isTrue);
    });

    test('deterministic across runs', () {
      final a = parseVoiceLog(kExample);
      final b = parseVoiceLog(kExample);
      expect(b.sleepHours, a.sleepHours);
      expect(b.exerciseMinutes, a.exerciseMinutes);
      expect(b.warnings, a.warnings);
    });

    test('number words, halves and litres convert', () {
      expect(parseVoiceLog('I drank two litres of water').waterGlasses, 8);
      expect(
          parseVoiceLog('I watched tv for half an hour').screenTimeHours,
          0.5);
      expect(parseVoiceLog('I meditated for ten minutes').meditationMinutes,
          10);
      expect(parseVoiceLog('I felt fantastic today').mood, 5);
      expect(
          parseVoiceLog('I am very stressed about work').stress, 5);
    });
  });

  group('parser — incomplete information', () {
    test('vague statements yield nothing usable, gracefully', () {
      final e = parseVoiceLog('drank some water and went for a walk');
      expect(e.waterGlasses, isNull);
      expect(e.exerciseMinutes, isNull);
      expect(e.hasAnything, isFalse);
      expect(e.warnings.any((w) => w.startsWith('Could not use')), isTrue);
    });

    test('partial capture keeps what was heard', () {
      final e = parseVoiceLog('slept five hours, feeling okay otherwise');
      expect(e.sleepHours, 5);
      expect(e.waterGlasses, isNull);
      expect(e.hasAnything, isTrue);
    });
  });

  group('parser — contradictory values', () {
    test('two sleep values keep the first and warn', () {
      final e = parseVoiceLog(
          'I slept seven hours, I mean I slept six hours');
      expect(e.sleepHours, 7);
      expect(
          e.warnings.any((w) => w.contains('two different sleep values')),
          isTrue);
    });
  });

  group('parser — unsupported phrases', () {
    test('unrelated speech is reported as ignored, never guessed', () {
      final e = parseVoiceLog('my cat is cute and the sky is blue');
      expect(e.hasAnything, isFalse);
      expect(e.warnings.length, 2);
      expect(e.sleepHours, isNull);
      expect(e.mood, isNull);
    });

    test('out-of-range values are dropped with a warning', () {
      final e = parseVoiceLog('I slept thirty hours');
      expect(e.sleepHours, isNull);
      expect(e.warnings.any((w) => w.contains('outside 0–24h')), isTrue);
    });
  });

  group('extractor — AI unavailable', () {
    test('deterministic extractor matches the parser exactly', () async {
      const extractor = DeterministicVoiceExtractor();
      final e = await extractor.extract(kExample);
      final p = parseVoiceLog(kExample);
      expect(e.sleepHours, p.sleepHours);
      expect(e.exerciseMinutes, p.exerciseMinutes);
      expect(e.waterGlasses, p.waterGlasses);
      expect(e.stress, p.stress);
      expect(e.energy, p.energy);
    });
  });

  group('controller — microphone denied', () {
    test('denied mic explains and preserves typed fallback', () async {
      final ctrl = VoiceLogController(
        gateway: const FakeVoiceGateway('slept eight hours',
            availability: MicAvailability.denied),
      );
      await ctrl.listenAndParse();
      expect(ctrl.mic, MicAvailability.denied);
      expect(ctrl.transcript, isEmpty);
      expect(ctrl.notice, contains('denied'));

      ctrl.setTranscript('I slept eight hours');
      await ctrl.parse();
      expect(ctrl.extraction?.sleepHours, 8);
    });

    test('unavailable recognizer fails gracefully', () async {
      final ctrl = VoiceLogController(
        gateway: const UnavailableVoiceGateway(),
      );
      await ctrl.listenAndParse();
      expect(ctrl.notice, contains('unavailable'));
    });
  });

  group('controller — confirmation and save', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await _initTestHive();
    });

    tearDown(() async {
      await LocalDatabase.clearAll();
    });

    test('only checked sections save; nothing auto-overwrites', () async {
      final daily = DailyHealthProvider(DailyHealthRepository(),
          stressRepo: StressRepository());
      await daily.loadToday();

      final ctrl = VoiceLogController(
        gateway: const FakeVoiceGateway(kExample),
      );
      await ctrl.listenAndParse();
      expect(ctrl.transcript, kExample);
      final rows = ctrl.sections();
      expect(rows.map((s) => s.key),
          containsAll(['sleep', 'energy', 'exercise', 'water', 'stress']));

      // User unchecks water before saving.
      ctrl.setIncluded('water', false);
      final n = await ctrl.save(daily);
      // sleep + exercise + stress-check = 3 (energy/mood have no save path
      // of their own; mood merges into the stress check-in).
      expect(n, 3);

      await daily.loadToday();
      expect(daily.today?.sleepHours, 7);
      expect(daily.today?.exerciseMinutes, 30);
      expect(daily.today?.waterGlasses, 0); // unchecked → untouched
      expect(daily.todayStress.length, 1);
      expect(daily.todayStress.first.mood.score, 2); // 6 - stress 4
    });

    test('editing adjusts values before save', () async {
      final daily = DailyHealthProvider(DailyHealthRepository(),
          stressRepo: StressRepository());
      await daily.loadToday();
      final ctrl = VoiceLogController(
        gateway: const FakeVoiceGateway('I slept six hours'),
      );
      await ctrl.listenAndParse();
      ctrl.adjust('sleep', 1.5, max: 24);
      expect(ctrl.sleepHours, 7.5);
      await ctrl.save(daily);
      await daily.loadToday();
      expect(daily.today?.sleepHours, 7.5);
    });
  });

  group('screen widgets', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('mic capture flows to an I-found confirmation',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => DailyHealthProvider(DailyHealthRepository()),
          child: const VoiceLogScreen(
            gateway: FakeVoiceGateway(kExample),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('Tap the mic and speak, or type instead.'),
          findsOneWidget);

      await tester.tap(find.byIcon(Icons.mic_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('I found:'), findsOneWidget);
      expect(find.text('7h'), findsOneWidget);
      expect(find.text('30 min · Walk'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('screen renders in dark mode', (tester) async {
      await tester.pumpWidget(MaterialApp(
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark(useMaterial3: true),
        theme: ThemeData.light(useMaterial3: true),
        home: ChangeNotifierProvider(
          create: (_) => DailyHealthProvider(DailyHealthRepository()),
          child: const VoiceLogScreen(),
        ),
      ));
      await tester.pump();
      expect(find.byType(VoiceLogScreen), findsOneWidget);
      expect(find.text('Mic unavailable — typing works the same.'),
          findsOneWidget);
    });
  });
}
