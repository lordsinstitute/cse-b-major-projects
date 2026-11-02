import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/data/backup/backup_service.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/repositories/daily_health_repository.dart';

late Directory _vaultDir;
late Directory _workDir;

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_backup');
  Hive.init(dir.path);
  await Future.wait([
    for (final name in backupBoxNames) Hive.openBox(name),
  ]);
  _vaultDir = await Directory.systemTemp.createTemp('soulcare_bkvault');
  _workDir = await Directory.systemTemp.createTemp('soulcare_bkwork');
}

BackupService _service() =>
    BackupService(vaultDir: _vaultDir, workDir: _workDir);

Future<void> _seedDaily(String date, double sleep) =>
    DailyHealthRepository()
        .save(DailyHealthEntry(date: date, sleepHours: sleep));

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await _initTestHive();
  });

  tearDown(() async {
    await LocalDatabase.clearAll();
  });

  group('backup', () {
    test('creates versioned zip with manifest, data, counts', () async {
      await _seedDaily('2099-01-01', 7.5);
      final res = await _service().createBackup();
      expect(res.isSuccess, isTrue);
      final o = res.value!;
      expect(await File(o.path).exists(), isTrue);
      expect(o.encrypted, isFalse);
      expect(o.counts['daily_health'], 1);

      final preview =
          await _service().preview(o.path);
      expect(preview.isSuccess, isTrue);
      expect(preview.value!.counts['daily_health'], 1);
      expect(preview.value!.encrypted, isFalse);
    });

    test('password encrypts; wrong password fails friendly', () async {
      await _seedDaily('2099-01-01', 7.5);
      final res =
          await _service().createBackup(password: 's3cret!');
      expect(res.isSuccess, isTrue);
      expect(res.value!.encrypted, isTrue);

      final noPw = await _service().preview(res.value!.path);
      // Either a password-needed message or failure — never a crash.
      expect(noPw.isFailure, isTrue);

      final wrong = await _service()
          .preview(res.value!.path, password: 'nope');
      expect(wrong.isFailure, isTrue);

      final right = await _service()
          .preview(res.value!.path, password: 's3cret!');
      expect(right.isSuccess, isTrue);
      expect(right.value!.encrypted, isTrue);
    });
  });

  group('restore', () {
    test('replace restores records; merge never overwrites newer', () async {
      await _seedDaily('2099-01-01', 7.5);
      final backup =
          (await _service().createBackup()).value!;

      // Local newer data appears after the backup.
      await _seedDaily('2099-01-01', 5.0);
      await _seedDaily('2099-01-02', 8.0);

      // Merge: existing key kept (5.0, not 7.5), missing added... but
      // 2099-01-02 is not in the backup (created after), so stays 8.0.
      final merged = await _service().restore(backup.path,
          strategy: RestoreStrategy.merge);
      expect(merged.isSuccess, isTrue);
      final kept =
          await DailyHealthRepository().getByDate('2099-01-01');
      expect(kept.value!.sleepHours, 5.0);

      // Replace: backup wins wholesale.
      final replaced = await _service().restore(backup.path,
          strategy: RestoreStrategy.replace);
      expect(replaced.isSuccess, isTrue);
      final back =
          await DailyHealthRepository().getByDate('2099-01-01');
      expect(back.value!.sleepHours, 7.5);
      expect(
          (await DailyHealthRepository().getByDate('2099-01-02'))
              .value,
          isNull);
    });

    test('duplicate documents skipped on merge', () async {
      final vaultFile = File('${_vaultDir.path}/doc.pdf');
      await vaultFile.writeAsBytes([1, 2, 3], flush: true);
      final now = DateTime.now();
      final doc = MedicalDocument(
        id: 'd1',
        fileName: 'doc.pdf',
        localPath: vaultFile.path,
        importedAt: now,
        contentHash: 'abc123',
      );
      LocalDatabase.documentsBox.put('d1', doc.toJson());
      final backup =
          (await _service().createBackup()).value!;

      // Same content re-imported under another id, then merge.
      final dup = MedicalDocument(
        id: 'd2',
        fileName: 'copy.pdf',
        localPath: vaultFile.path,
        importedAt: now,
        contentHash: 'abc123',
      );
      LocalDatabase.documentsBox.put('d2', dup.toJson());
      final res = await _service().restore(backup.path,
          strategy: RestoreStrategy.merge);
      expect(res.isSuccess, isTrue);
      // d1 (existing) untouched; no duplicate rewrite.
      expect(
          MedicalDocument.fromJson(Map<String, dynamic>.from(
                  LocalDatabase.documentsBox.get('d1') as Map))
              .fileName,
          'doc.pdf');
    });

    test('corrupted file rejected without touching data', () async {
      await _seedDaily('2099-01-01', 7.5);
      final bad = File('${_workDir.path}/bad.zip');
      await bad.writeAsBytes([9, 9, 9, 9], flush: true);
      final res = await _service().restore(bad.path,
          strategy: RestoreStrategy.replace);
      expect(res.isFailure, isTrue);
      // Original data intact.
      expect(
          (await DailyHealthRepository().getByDate('2099-01-01'))
              .value!
              .sleepHours,
          7.5);
    });

    test('missing file and incompatible version rejected', () async {
      final missing = await _service().restore(
          '${_workDir.path}/nope.zip',
          strategy: RestoreStrategy.merge);
      expect(missing.isFailure, isTrue);

      // A structurally valid zip whose manifest demands a newer app.
      final fakeManifest = '{"format":"soulcare-backup",'
          '"formatVersion":999,"appVersion":"9.9",'
          '"createdAt":"2099-01-01T00:00:00.000",'
          '"encrypted":false,"counts":{}}';
      final fakeData = '{}';
      final archive = Archive()
        ..addFile(ArchiveFile('manifest.json',
            fakeManifest.length, fakeManifest.codeUnits))
        ..addFile(ArchiveFile(
            'data.json', fakeData.length, fakeData.codeUnits));
      final fake = File('${_workDir.path}/future.zip');
      await fake.writeAsBytes(
          ZipEncoder().encode(archive), flush: true);
      final res = await _service()
          .restore(fake.path, strategy: RestoreStrategy.merge);
      expect(res.isFailure, isTrue);
      expect(res.error!.message, contains('newer SoulCare'));
    });

    test('safety snapshot rolls back exactly', () async {
      await _seedDaily('2099-01-01', 7.5);
      final snap = await BackupSafetySnapshot.take();
      await _seedDaily('2099-01-01', 1.0);
      await _seedDaily('2099-01-02', 2.0);
      await snap.rollback();
      expect(
          (await DailyHealthRepository().getByDate('2099-01-01'))
              .value!
              .sleepHours,
          7.5);
      expect(
          (await DailyHealthRepository().getByDate('2099-01-02'))
              .value,
          isNull);
    });
  });
}
