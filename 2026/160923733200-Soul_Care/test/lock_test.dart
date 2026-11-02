import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/app/providers/settings_provider.dart';
import 'package:soul_care/core/app_lock/biometric_gateway.dart';
import 'package:soul_care/core/widgets/pin_gate.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/repositories/settings_repository.dart';

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_lock');
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
  ]);
}

class _FakeBiometrics implements BiometricGateway {
  final bool available;
  final bool success;
  _FakeBiometrics({required this.available, this.success = true});

  @override
  Future<bool> canCheck() async => available;

  @override
  Future<bool> authenticate(String reason) async =>
      available && success;
}

Future<SettingsProvider> _lockedProvider(
    {BiometricGateway? gateway}) async {
  final p = SettingsProvider(SettingsRepository(),
      biometrics: gateway ?? UnavailableBiometricGateway());
  await p.load();
  expect(await p.setAppLock(enabled: true, pin: '2468'), isTrue);
  await p.update(p.settings.copyWith(lockScope: 'sections'));
  return p;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await _initTestHive();
  });

  tearDown(() async {
    await LocalDatabase.clearAll();
  });

  group('biometrics', () {
    test('available sensor unlocks the session', () async {
      final p = SettingsProvider(SettingsRepository(),
          biometrics:
              _FakeBiometrics(available: true, success: true));
      await p.load();
      expect(p.biometricAvailable, isTrue);
      expect(await p.setAppLock(enabled: true, pin: '2468'), isTrue);
      expect(await p.authenticateBiometric(), isTrue);
      expect(p.appUnlocked, isTrue);
      expect(p.journalUnlocked, isTrue);
    });

    test('unavailable sensor reports false; auth fails closed', () async {
      final p = SettingsProvider(SettingsRepository(),
          biometrics: UnavailableBiometricGateway());
      await p.load();
      expect(p.biometricAvailable, isFalse);
      expect(await p.authenticateBiometric(), isFalse);
      expect(p.appUnlocked, isFalse);
    });

    test('declined biometric keeps session locked (PIN still works)',
        () async {
      final p = SettingsProvider(SettingsRepository(),
          biometrics:
              _FakeBiometrics(available: true, success: false));
      await p.load();
      expect(await p.setAppLock(enabled: true, pin: '2468'), isTrue);
      expect(await p.authenticateBiometric(), isFalse);
      expect(p.appUnlocked, isFalse);
      expect(p.unlockJournal('2468'), isTrue);
    });
  });

  group('background and timeouts', () {
    test('immediate + on-background lock on backgrounding', () async {
      final p = await _lockedProvider();
      await p.update(p.settings.copyWith(
        lockTimeoutMin: 0,
        lockOnBackground: false,
      ));
      p.unlockJournal('2468');
      expect(p.journalUnlocked, isTrue);
      p.recordBackgrounded();
      expect(p.journalUnlocked, isFalse);
      expect(p.appUnlocked, isFalse);
    });

    test('foreground applies timeout math, not vibes', () async {
      final p = await _lockedProvider();
      await p.update(p.settings.copyWith(
        lockTimeoutMin: 5,
        lockOnBackground: false,
      ));
      p.unlockJournal('2468');
      // Returned quickly: stays unlocked.
      p.recordForegrounded(wasBackgrounded: false);
      expect(p.journalUnlocked, isTrue);

      expect(
          SettingsProvider.timeoutElapsed(
            lastActive: DateTime(2026, 9, 29, 10, 0),
            now: DateTime(2026, 9, 29, 10, 4),
            timeoutMin: 5,
            lockOnBackground: false,
            wasBackgrounded: true,
          ),
          isFalse);
      expect(
          SettingsProvider.timeoutElapsed(
            lastActive: DateTime(2026, 9, 29, 10, 0),
            now: DateTime(2026, 9, 29, 10, 6),
            timeoutMin: 5,
            lockOnBackground: false,
            wasBackgrounded: true,
          ),
          isTrue);
      expect(
          SettingsProvider.timeoutElapsed(
            lastActive: DateTime(2026, 9, 29, 10, 0),
            now: DateTime(2026, 9, 29, 10, 0, 30),
            timeoutMin: 5,
            lockOnBackground: true,
            wasBackgrounded: true,
          ),
          isTrue);
    });
  });

  group('scopes and restart', () {
    test('sections protect only chosen screens; full covers all',
        () async {
      final p = await _lockedProvider();
      expect(p.protects('journal'), isTrue);
      expect(p.protects('reports'), isTrue);
      await p.update(p.settings
          .copyWith(protectedScreens: ['journal']));
      expect(p.protects('journal'), isTrue);
      expect(p.protects('reports'), isFalse);

      await p.update(p.settings.copyWith(lockScope: 'full'));
      expect(p.protects('reports'), isTrue);
      expect(p.appUnlocked, isFalse);
      expect(p.appGateLocked, isTrue);
    });

    test('restart keeps settings, drops the session', () async {
      final p = await _lockedProvider();
      await p.update(p.settings.copyWith(
        lockScope: 'full',
        lockTimeoutMin: 5,
        biometricEnabled: true,
      ));
      p.unlockJournal('2468');
      expect(p.appUnlocked, isTrue);

      final restarted = SettingsProvider(SettingsRepository(),
          biometrics: UnavailableBiometricGateway());
      await restarted.load();
      expect(restarted.settings.lockScope, 'full');
      expect(restarted.settings.appLockEnabled, isTrue);
      expect(restarted.appUnlocked, isFalse);
      expect(restarted.journalUnlocked, isFalse);
      expect(restarted.appGateLocked, isTrue);
    });

    test('wrong PINs never lock out, counter is informational', () async {
      final p = await _lockedProvider();
      for (var i = 0; i < 7; i++) {
        expect(p.unlockJournal('0000'), isFalse);
      }
      expect(p.failedAttempts, 7);
      expect(p.unlockJournal('2468'), isTrue);
      expect(p.failedAttempts, 0);
    });
  });

  group('widgets', () {
    testWidgets('disabled lock renders child directly', (tester) async {
      final p = SettingsProvider(SettingsRepository(),
          biometrics: UnavailableBiometricGateway());
      await p.load();
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider.value(value: p)],
        child: const MaterialApp(
            home: Scaffold(
                body: PinGate(
                    title: 'T',
                    subtitle: 'S',
                    screen: 'journal',
                    child: Text('secret content')))),
      ));
      await tester.pump();
      expect(find.text('secret content'), findsOneWidget);
      expect(find.text('T'), findsNothing);
    });

    testWidgets('protected screen shows gate, PIN reveals', (tester) async {
      final p = await _lockedProvider();
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider.value(value: p)],
        child: const MaterialApp(
            home: Scaffold(
                body: PinGate(
                    title: 'Locked title',
                    subtitle: 'Locked sub',
                    screen: 'journal',
                    child: Text('secret content')))),
      ));
      await tester.pump();
      expect(find.text('Locked title'), findsOneWidget);
      expect(find.text('secret content'), findsNothing);

      for (final d in ['2', '4', '6', '8']) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('secret content'), findsOneWidget);
    });

    testWidgets('biometric button appears when enabled + available',
        (tester) async {
      final p = SettingsProvider(SettingsRepository(),
          biometrics: _FakeBiometrics(available: true));
      await p.load();
      await p.setAppLock(enabled: true, pin: '2468');
      await p.update(p.settings.copyWith(
          lockScope: 'sections', biometricEnabled: true));
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider.value(value: p)],
        child: const MaterialApp(
            home: Scaffold(
                body: PinGate(
                    title: 'T',
                    subtitle: 'S',
                    screen: 'journal',
                    child: Text('secret content')))),
      ));
      await tester.pump();
      expect(find.text('Use biometrics'), findsOneWidget);
      await tester.tap(find.text('Use biometrics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('secret content'), findsOneWidget);
    });
  });
}
