import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soul_care/data/models/enums.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/features/calendar/calendar_engine.dart';
import 'package:soul_care/features/calendar/calendar_provider.dart';
import 'package:soul_care/features/calendar/calendar_screen.dart';

/// Hermetic widget tests: pre-seeded provider, zero Hive I/O (Hive file
/// access stalls intermittently on the Windows dev machine — see progress
/// notes. Provider loading against real storage is covered in
/// `calendar_test.dart`, which owns the Hive setup for this area).
DailyHealthEntry _day(String key) {
  return DailyHealthEntry(
    date: key,
    sleepHours: 7.5,
    sleepQuality: SleepQuality.good,
    feltRested: true,
    exerciseMinutes: 30,
    exerciseIntensity: ExerciseIntensity.moderate,
    mealQuality: MealQuality.good,
    waterGlasses: 8,
    meditationMinutes: 10,
    screenTimeHours: 2,
  );
}

List<CalendarDay> _emptyGrid(DateTime now) => buildMonthGrid(
      year: now.year,
      month: now.month,
      dailyByDate: {},
      calmByDate: {},
      moodSourcesByDate: {},
      morningByDate: {},
      eveningByDate: {},
      experiments: [],
      journalCountByDate: {},
      documentCountByDate: {},
    );

void main() {
  // Tall surface: the calendar ListView builds lazily, so below-the-fold
  // content (legend, detail) only exists once visible. A tall viewport
  // keeps every assertion scroll-free and deterministic.
  Future<void> pumpTall(
      WidgetTester tester, Widget home) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pump();
  }

  testWidgets('empty month shows No-data days, honestly', (tester) async {
    final now = DateTime.now();
    final prov = CalendarProvider()
      ..seedForTest(
          year: now.year, month: now.month, grid: _emptyGrid(now));
    await pumpTall(tester, CalendarScreen(provider: prov));
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.text('No data'), findsWidgets);
    expect(find.text('Excellent'), findsWidgets);
    // Tapping a day reports honestly instead of scoring it.
    await tester.tap(find.text('${now.day}').first);
    await tester.pump();
    expect(find.textContaining('No data was logged on this day'),
        findsOneWidget);
  });

  testWidgets('seeded day shows detail with focus filter', (tester) async {
    final now = DateTime.now();
    final key =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-15';
    final grid = buildMonthGrid(
      year: now.year,
      month: now.month,
      dailyByDate: {key: _day(key)},
      calmByDate: {},
      moodSourcesByDate: {
        key: [4]
      },
      morningByDate: {},
      eveningByDate: {},
      experiments: [],
      journalCountByDate: {key: 1},
      documentCountByDate: {},
    );
    final prov = CalendarProvider()
      ..seedForTest(year: now.year, month: now.month, grid: grid);
    await pumpTall(tester, CalendarScreen(provider: prov));
    await tester.tap(find.text('15').first);
    await tester.pump();
    expect(find.textContaining('Wellness score'), findsOneWidget);
    expect(find.textContaining('1 journal entry'), findsOneWidget);
    // Stress focus highlights stress rows without crashing.
    await tester.tap(find.text('Stress'));
    await tester.pump();
    expect(find.textContaining('Wellness score'), findsOneWidget);
  });

  testWidgets('screen renders in dark mode', (tester) async {
    final now = DateTime.now();
    final prov = CalendarProvider()
      ..seedForTest(
          year: now.year, month: now.month, grid: _emptyGrid(now));
    await tester.pumpWidget(MaterialApp(
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark(useMaterial3: true),
      theme: ThemeData.light(useMaterial3: true),
      home: CalendarScreen(provider: prov),
    ));
    await tester.pump();
    expect(find.byType(CalendarScreen), findsOneWidget);
  });
}
