import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/app/providers/daily_health_provider.dart';
import 'package:soul_care/app/providers/health_import_provider.dart';
import 'package:soul_care/app/providers/settings_provider.dart';
import 'package:soul_care/core/health/health_gateway.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/health_import.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';
import 'package:soul_care/data/repositories/health_import_repository.dart';
import 'package:soul_care/data/repositories/settings_repository.dart';
import 'package:soul_care/features/daily_health/daily_health_screen.dart';
import 'package:soul_care/features/settings/settings_screen.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_hc');
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
  ]);
}

ImportedPoint _pt(String id, ImportMetric metric, String date, double value,
    {String source = 'TestWatch'}) {
  final day = DateTime.parse(date);
  return ImportedPoint(
    id: id,
    metric: metric,
    dateKey: date,
    value: value,
    unit: '',
    sourceName: source,
    sourceId: 'test-source',
    measuredFrom: day,
    measuredTo: day.add(const Duration(hours: 1)),
    importedAt: DateTime.now(),
  );
}

/// Configurable fake platform store.
class FakeGateway implements HealthGateway {
  bool available;
  bool granted;
  List<ImportedPoint> points;
  bool revoked = false;

  FakeGateway(
      {this.available = true,
      this.granted = false,
      this.points = const []});

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> hasAccess() async => available && granted && !revoked;

  @override
  Future<bool> requestAccess() async {
    if (!available) return false;
    return granted;
  }

  @override
  Future<void> revokeAccess() async {
    revoked = true;
  }

  @override
  Future<List<ImportedPoint>> fetch(
      {required DateTime from, required DateTime to}) async {
    if (!await hasAccess()) throw StateError('no access');
    return points;
  }
}

HealthImportProvider _provider(FakeGateway gateway) =>
    HealthImportProvider(HealthImportRepository(), gateway: gateway);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await _initTestHive();
  });

  tearDown(() async {
    await LocalDatabase.clearAll();
  });

  group('permissions', () {
    test('denied permission leaves app functional, nothing stored',
        () async {
      final p = _provider(FakeGateway(granted: false));
      await p.refresh();
      expect(await p.connect(), isFalse);
      expect(p.status, HealthLinkStatus.denied);
      expect(p.totalPoints, 0);
      // Manual side unaffected.
      expect((await HealthImportRepository().getAll()).value, isEmpty);
    });

    test('unavailable integration reports honestly', () async {
      final p = _provider(FakeGateway(available: false));
      expect(await p.connect(), isFalse);
      expect(p.status, HealthLinkStatus.unsupported);
      expect(p.error, contains('unavailable on this device'));
    });
  });

  group('import', () {
    List<ImportedPoint> sample(String date) => [
          _pt('sleep|$date', ImportMetric.sleepHours, date, 7.5),
          _pt('steps|$date', ImportMetric.steps, date, 8432),
          _pt('hr|$date', ImportMetric.heartRate, date, 68),
          _pt('hr2|$date', ImportMetric.heartRate, date, 72),
        ];

    test('available data aggregates with source transparency', () async {
      final gateway = FakeGateway(
          granted: true, points: sample('2099-06-01'));
      final p = _provider(gateway);
      expect(await p.connect(), isTrue);
      expect(p.status, HealthLinkStatus.connected);
      final day = p.dayFor('2099-06-01')!;
      expect(day.sleepHours, 7.5);
      expect(day.steps, 8432);
      expect(day.heartRateAvg, 70);
      expect(day.sources, {'TestWatch'});
      expect(day.hasAny, isTrue);
    });

    test('no data syncs zero records, stays connected', () async {
      final p = _provider(FakeGateway(granted: true, points: const []));
      expect(await p.connect(), isTrue);
      expect(p.totalPoints, 0);
      expect(p.dayFor('2099-06-01'), isNull);
    });

    test('repeated sync never duplicates (stable ids)', () async {
      final gateway =
          FakeGateway(granted: true, points: sample('2099-06-01'));
      final p = _provider(gateway);
      await p.connect();
      final first = p.totalPoints;
      expect(first, 4);
      expect(await p.sync(), isTrue);
      expect(p.totalPoints, first);
      // New record for a new day adds exactly one.
      gateway.points = [
        ...sample('2099-06-01'),
        _pt('steps|2099-06-02', ImportMetric.steps, '2099-06-02', 1000),
      ];
      expect(await p.sync(), isTrue);
      expect(p.totalPoints, first + 1);
    });

    test('revoked access clears imports, keeps manual logs', () async {
      final gateway =
          FakeGateway(granted: true, points: sample('2099-06-01'));
      final p = _provider(gateway);
      await p.connect();
      expect(p.totalPoints, 4);
      await p.disconnect();
      expect(p.totalPoints, 0);
      expect(p.dayFor('2099-06-01'), isNull);
      expect(gateway.revoked, isTrue);
      expect(p.status, HealthLinkStatus.unknown);
    });

    test('restart restores connection flag + data', () async {
      final gateway =
          FakeGateway(granted: true, points: sample('2099-06-01'));
      final p = _provider(gateway);
      await p.connect();
      final restarted = _provider(gateway);
      await restarted.refresh();
      expect(restarted.status, HealthLinkStatus.connected);
      expect(restarted.totalPoints, 4);
    });
  });

  group('widgets', () {
    MultiProvider wrap(Widget child, HealthImportProvider link) =>
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: link),
            ChangeNotifierProvider(
                create: (_) =>
                    SettingsProvider(SettingsRepository())),
            ChangeNotifierProvider(
                create: (_) =>
                    DailyHealthProvider(DailyHealthRepository())),
          ],
          child: MaterialApp(home: Scaffold(body: child)),
        );

    testWidgets('unavailable device shows fallback, manual flow intact',
        (tester) async {
      final link = _provider(FakeGateway(available: false));
      await tester.pumpWidget(wrap(const SettingsScreen(), link));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final section =
          find.text('Health data', skipOffstage: false);
      await tester.ensureVisible(section);
      await tester.pump();
      final connect = find.text('Connect Health Data',
          skipOffstage: false);
      await tester.ensureVisible(connect);
      await tester.pump();
      await tester.tap(connect);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
          find.text(
              'Health data integration is unavailable on this device.',
              skipOffstage: false),
          findsWidgets);
    });

    testWidgets('today shows imported badge next to manual sections',
        (tester) async {
      final now = DateTime.now();
      final key =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final link = _provider(FakeGateway(granted: true, points: [
        _pt('sleep|$key', ImportMetric.sleepHours, key, 7.25),
        _pt('steps|$key', ImportMetric.steps, key, 9100),
      ]));
      await link.connect();
      await tester.pumpWidget(wrap(const DailyHealthScreen(), link));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final deviceHeader =
          find.text('From your device', skipOffstage: false);
      await tester.ensureVisible(deviceHeader);
      await tester.pump();
      expect(find.text('Imported', skipOffstage: false), findsOneWidget);
      expect(find.textContaining('9100', skipOffstage: false),
          findsOneWidget);
      // Manual sections still present alongside.
      expect(
          find.text('Save Sleep', skipOffstage: false), findsWidgets);
    });
  });
}
