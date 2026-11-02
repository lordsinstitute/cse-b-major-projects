import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/app/providers/action_center_provider.dart';
import 'package:soul_care/app/providers/checkin_providers.dart';
import 'package:soul_care/app/providers/daily_health_provider.dart';
import 'package:soul_care/app/providers/dashboard_provider.dart';
import 'package:soul_care/app/providers/experiment_provider.dart';
import 'package:soul_care/app/providers/profile_provider.dart';
import 'package:soul_care/app/theme/app_theme.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/repositories/checkin_repository.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/data/repositories/experiment_repository.dart';
import 'package:soul_care/data/repositories/profile_repository.dart';
import 'package:soul_care/features/action_center/action_engine.dart';
import 'package:soul_care/features/dashboard/dashboard_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_actions');
  Hive.init(dir.path);
  await Future.wait([
    Hive.openBox(LocalDatabase.dailyBoxName),
    Hive.openBox(LocalDatabase.stressBoxName),
    Hive.openBox(LocalDatabase.experimentsBoxName),
    Hive.openBox(LocalDatabase.documentsBoxName),
    Hive.openBox(LocalDatabase.settingsBoxName),
    Hive.openBox(LocalDatabase.gameStatsBoxName),
    Hive.openBox(LocalDatabase.morningBoxName),
    Hive.openBox(LocalDatabase.eveningBoxName),
    Hive.openBox(LocalDatabase.journalBoxName),
    Hive.openBox(LocalDatabase.snapshotBoxName),
    Hive.openBox(LocalDatabase.medRemindersBoxName),
    Hive.openBox(LocalDatabase.appointmentsBoxName),
    Hive.openBox(LocalDatabase.doseLogBoxName),
    Hive.openBox(LocalDatabase.healthImportsBoxName),
    Hive.openBox('action_center'),
  ]);
}

ActionContext _ctx({
  int done = 0,
  int total = 5,
  bool morning = false,
  bool evening = false,
  bool eveningWindow = false,
  List<GoalGap> gaps = const [],
  ExperimentDue? exp,
  List<AppointmentDue> appts = const [],
}) =>
    ActionContext(
      completedSections: done,
      totalSections: total,
      morningDone: morning,
      eveningDone: evening,
      eveningWindow: eveningWindow,
      goalGaps: gaps,
      experimentDue: exp,
      appointmentsToday: appts,
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await _initTestHive();
  });

  tearDown(() async {
    await LocalDatabase.clearAll();
    if (Hive.isBoxOpen('action_center')) {
      await Hive.box('action_center').clear();
    }
  });

  group('engine', () {
    test('new user gets gentle starters, max 3, deterministic', () {
      final a = buildActions(_ctx());
      final b = buildActions(_ctx());
      expect(a.length, lessThanOrEqualTo(3));
      expect(a.map((e) => e.id), b.map((e) => e.id));
      expect(a.first.priority,
          greaterThanOrEqualTo(a.last.priority));
      for (final action in a) {
        expect(action.title, isNotEmpty);
        expect(action.explanation, isNotEmpty);
        expect(action.destination.startsWith('/'), isTrue);
        expect(action.dismissKey, isNotEmpty);
      }
    });

    test('incomplete day surfaces sections + routine', () {
      final actions = buildActions(_ctx(done: 2));
      expect(actions.map((a) => a.id),
          containsAll(['morning', 'sections']));
      expect(actions.length, lessThanOrEqualTo(3));
    });

    test('active experiment due outranks routine', () {
      final actions = buildActions(_ctx(
        exp: const ExperimentDue(
            title: 'Walk', dayNumber: 4, durationDays: 7),
      ));
      expect(actions.first.id, 'exp-today');
      expect(actions.first.destination, '/lab');
    });

    test('appointment today is top priority with its time', () {
      final actions = buildActions(_ctx(
        exp: const ExperimentDue(
            title: 'Walk', dayNumber: 4, durationDays: 7),
        appts: const [
          AppointmentDue(title: 'Dentist', timeLabel: '10:30')
        ],
      ));
      expect(actions.first.id.startsWith('appt-'), isTrue);
      expect(actions.first.explanation, contains('10:30'));
    });

    test('focus-matching goal wins ties, never invents urgency', () {
      final actions = buildActions(_ctx(done: 5, morning: true, gaps: const [
        GoalGap(
            label: 'Water',
            detail: '5 of 8 — 3 to go',
            focusKey: 'water',
            matchesFocus: true),
        GoalGap(
            label: 'Sleep',
            detail: '6.0 of 7.5 — 1.5 to go',
            focusKey: 'sleep',
            matchesFocus: false),
      ]));
      expect(actions.first.id, 'goal-water');
      for (final a in actions) {
        expect(a.explanation.toLowerCase(), isNot(contains('urgent')));
        expect(a.explanation.toLowerCase(), isNot(contains('must')));
      }
    });

    test('fully completed day yields no actions (caught-up UI)', () {
      expect(buildActions(_ctx(done: 5, morning: true)), isEmpty);
      expect(caughtUpTitle, isNotEmpty);
      expect(caughtUpBody, isNotEmpty);
    });

    test('no data still answers without crashing', () {
      final actions = buildActions(_ctx(total: 5));
      expect(actions, isNotEmpty);
      expect(actions.length, lessThanOrEqualTo(3));
    });
  });

  group('dismissals', () {
    test('dismiss persists today, returns tomorrow, never escalates',
        () async {
      final p = ActionCenterProvider();
      await p.loadToday();
      await p.dismiss('morning');
      expect(p.dismissed, contains('morning'));

      final restarted = ActionCenterProvider();
      await restarted.loadToday();
      expect(restarted.dismissed, contains('morning'));

      // A dismissed item filtered out does not come back stronger:
      final actions = buildActions(_ctx())
          .where((a) => !restarted.dismissed.contains(a.dismissKey))
          .toList();
      expect(actions.map((a) => a.id), isNot(contains('morning')));
      expect(actions.length, lessThanOrEqualTo(3));
    });
  });

  group('widgets', () {
    MultiProvider wrap(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider(
                create: (_) =>
                    DailyHealthProvider(DailyHealthRepository())),
            ChangeNotifierProvider(
                create: (_) =>
                    DashboardProvider(DailyHealthRepository())),
            ChangeNotifierProvider(
                create: (_) =>
                    ExperimentProvider(ExperimentRepository())),
            ChangeNotifierProvider(
                create: (_) => ProfileProvider(ProfileRepository())),
            ChangeNotifierProvider(
                create: (_) => ActionCenterProvider()),
            ChangeNotifierProvider(
                create: (_) => MorningProvider(MorningRepository())),
            ChangeNotifierProvider(
                create: (_) => EveningProvider(EveningRepository())),
          ],
          child: MaterialApp(home: Scaffold(body: child)),
        );

    testWidgets('incomplete day shows actions with dismiss', (tester) async {
      final now = DateTime.now();
      await DailyHealthRepository().save(DailyHealthEntry(
          date:
              '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
          sleepHours: 7));
      await tester.pumpWidget(wrap(const DashboardScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Today', skipOffstage: false), findsWidgets);
      expect(find.text('Start your morning check-in', skipOffstage: false),
          findsOneWidget);
      // Dismiss removes it for today.
      await tester.ensureVisible(find.byIcon(Icons.close).first);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();
      expect(find.text('Start your morning check-in', skipOffstage: false),
          findsNothing);
    });

    testWidgets('dark mode renders', (tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(
              create: (_) =>
                  DailyHealthProvider(DailyHealthRepository())),
          ChangeNotifierProvider(
              create: (_) =>
                  DashboardProvider(DailyHealthRepository())),
          ChangeNotifierProvider(
              create: (_) =>
                  ExperimentProvider(ExperimentRepository())),
          ChangeNotifierProvider(
              create: (_) => ProfileProvider(ProfileRepository())),
          ChangeNotifierProvider(
              create: (_) => ActionCenterProvider()),
          ChangeNotifierProvider(
              create: (_) => MorningProvider(MorningRepository())),
          ChangeNotifierProvider(
              create: (_) => EveningProvider(EveningRepository())),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: const Scaffold(body: DashboardScreen()),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  });
}
