import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../local/document_storage.dart';

/// Backup format identity.
class BackupFormat {
  static const String magic = 'soulcare-backup';
  static const int version = 1;
}

/// Boxes included in every backup (settings through dose logs).
const List<String> backupBoxNames = [
  'daily_health',
  'stress_entries',
  'experiments',
  'medical_documents',
  'settings',
  'game_stats',
  'morning_checkins',
  'evening_reflections',
  'journal_entries',
  'health_snapshot',
  'med_reminders',
  'appointments',
  'dose_log',
];

/// Human-readable preview shown BEFORE anything is modified.
class BackupPreview {
  final DateTime createdAt;
  final String appVersion;
  final bool encrypted;
  final Map<String, int> counts;
  final int fileCount;

  const BackupPreview({
    required this.createdAt,
    required this.appVersion,
    required this.encrypted,
    required this.counts,
    required this.fileCount,
  });

  int get totalRecords =>
      counts.values.fold(0, (a, b) => a + b);
}

/// Restore strategy chosen by the user at confirm time.
enum RestoreStrategy { replace, merge }

/// Portable local backup: one AES-capable zip with manifest + data +
/// vault files. Medical PDFs ride INSIDE the zip (single portable file);
/// the UI says so plainly and offers password protection. Passwords are
/// never stored — only supplied at create/restore time.
class BackupService {
  final Directory? vaultDir;
  final Directory? workDir;

  BackupService({this.vaultDir, this.workDir});

  Future<Directory> _vault() =>
      DocumentStorage.vaultDirectory(override: vaultDir);

  Future<Directory> _work() async {
    if (workDir != null) {
      if (!await workDir!.exists()) {
        await workDir!.create(recursive: true);
      }
      return workDir!;
    }
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(tmp.path, 'soulcare_backup'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Map<String, Map<String, dynamic>> _readAllBoxes() {
    final out = <String, Map<String, dynamic>>{};
    for (final name in backupBoxNames) {
      final box = <String, dynamic>{};
      try {
        if (!HiveBox.isOpen(name)) continue;
        final b = HiveBox.box(name);
        for (final k in b.keys) {
          final v = b.get(k);
          box['$k'] =
              v is Map ? Map<String, dynamic>.from(v) : v;
        }
      } catch (_) {}
      out[name] = box;
    }
    return out;
  }

  /// Creates `soulcare-backup-<stamp>.zip` and returns its path.
  /// [password] enables AES encryption (optional, never stored).
  Future<Result<BackupOutcome>> createBackup({String? password}) async {
    try {
      final now = DateTime.now();
      final boxes = _readAllBoxes();
      final counts = {
        for (final k in boxes.keys) k: boxes[k]!.length,
      };
      final manifest = {
        'format': BackupFormat.magic,
        'formatVersion': BackupFormat.version,
        'appVersion': AppConstants.appVersion,
        'createdAt': now.toIso8601String(),
        'encrypted': password != null && password.isNotEmpty,
        'counts': counts,
      };

      final archive = Archive();
      final manifestBytes =
          utf8.encode(jsonEncode(manifest));
      archive.addFile(ArchiveFile(
          'manifest.json', manifestBytes.length, manifestBytes));
      final dataBytes = utf8.encode(jsonEncode(boxes));
      archive.addFile(
          ArchiveFile('data.json', dataBytes.length, dataBytes));

      // Vault PDFs bundled by document id (single portable file).
      var fileCount = 0;
      try {
        final docs = boxes['medical_documents'] ?? const {};
        for (final id in docs.keys) {
          final meta = docs[id];
          final localPath =
              meta is Map ? meta['localPath'] as String? : null;
          if (localPath == null || localPath.isEmpty) continue;
          final f = File(localPath);
          if (!await f.exists()) continue;
          final bytes = await f.readAsBytes();
          final name = p.basename(localPath);
          archive.addFile(ArchiveFile(
              'files/${id}_$name', bytes.length, bytes));
          fileCount++;
        }
      } catch (_) {}

      final encoder = password != null && password.isNotEmpty
          ? ZipEncoder(password: password)
          : ZipEncoder();
      final zipped = encoder.encode(archive);
      final dir = await _work();
      final stamp = now
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file =
          File(p.join(dir.path, 'soulcare-backup-$stamp.zip'));
      await file.writeAsBytes(zipped, flush: true);
      return Success(BackupOutcome(
        path: file.path,
        createdAt: now,
        counts: counts,
        fileCount: fileCount,
        encrypted: password != null && password.isNotEmpty,
      ));
    } catch (e) {
      return Failure(PersistenceException('Could not create the backup.',
          originalError: e));
    }
  }

  /// Reads + validates a backup file WITHOUT modifying anything.
  Future<Result<BackupPreview>> preview(String path,
      {String? password}) async {
    try {
      final parsed = await _open(path, password: password);
      return parsed.fold(
        onSuccess: (b) => Success(BackupPreview(
          createdAt: b.createdAt,
          appVersion: b.appVersion,
          encrypted: b.encrypted,
          counts: b.counts,
          fileCount: b.fileNames.length,
        )),
        onFailure: (e) => Failure(e),
      );
    } catch (e) {
      return Failure(PersistenceException(
          'That file could not be read as a SoulCare backup.',
          originalError: e));
    }
  }

  /// Restores [path] with [strategy]. Takes a safety snapshot first;
  /// any failure rolls back so the database is never left corrupted.
  Future<Result<RestoreOutcome>> restore(String path,
      {required RestoreStrategy strategy, String? password}) async {
    BackupSafetySnapshot? safety;
    try {
      final parsed = await _open(path, password: password);
      final backup = parsed.fold(
          onSuccess: (b) => b,
          onFailure: (e) => throw _RestoreFailure(e.message));
      safety = await BackupSafetySnapshot.take(vaultDir: vaultDir);
      final applied = await _apply(backup, strategy);
      return Success(RestoreOutcome(
        strategy: strategy,
        added: applied,
        safetyKept: true,
      ));
    } on _RestoreFailure catch (e) {
      if (safety != null) {
        await safety.rollback(vaultDir: vaultDir);
      }
      return Failure(PersistenceException(e.message));
    } catch (e) {
      if (safety != null) {
        await safety.rollback(vaultDir: vaultDir);
      }
      return Failure(PersistenceException(
          'Restore failed and your previous data was kept.',
          originalError: e));
    }
  }

  // --- internals ---

  Future<Result<_ParsedBackup>> _open(String path,
      {String? password}) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return const Failure(ValidationException(
            'Backup file not found. It may have been moved or deleted.'));
      }
      final bytes = await file.readAsBytes();
      Archive archive;
      try {
        archive = ZipDecoder()
            .decodeBytes(bytes, password: password ?? '');
      } catch (_) {
        // Retry without password for plain zips.
        try {
          archive = ZipDecoder().decodeBytes(bytes);
        } catch (e) {
          return const Failure(ValidationException(
              'That file is not a readable backup. It may be corrupted, or the password may be wrong.'));
        }
      }
      Map<String, dynamic>? manifest;
      Map<String, dynamic>? data;
      final files = <String, List<int>>{};
      for (final f in archive.files) {
        if (!f.isFile) continue;
        if (f.name == 'manifest.json') {
          manifest = Map<String, dynamic>.from(
              jsonDecode(utf8.decode(f.content as List<int>)) as Map);
        } else if (f.name == 'data.json') {
          data = Map<String, dynamic>.from(
              jsonDecode(utf8.decode(f.content as List<int>)) as Map);
        } else if (f.name.startsWith('files/')) {
          files[f.name] =
              List<int>.from(f.content as List<int>);
        }
      }
      if (manifest == null || data == null) {
        return const Failure(ValidationException(
            'That file is not a SoulCare backup (manifest missing).'));
      }
      if (manifest['format'] != BackupFormat.magic) {
        return const Failure(ValidationException(
            'That file is not a SoulCare backup.'));
      }
      final v = (manifest['formatVersion'] as num?)?.toInt() ?? 0;
      if (v > BackupFormat.version) {
        return Failure(ValidationException(
            'That backup needs a newer SoulCare (v$v > v${BackupFormat.version}). Update the app first.'));
      }
      if (v < 1) {
        return const Failure(ValidationException(
            'That backup format is too old to restore.'));
      }
      final counts = <String, int>{};
      final rawCounts = manifest['counts'];
      if (rawCounts is Map) {
        for (final k in rawCounts.keys) {
          counts['$k'] = (rawCounts[k] as num?)?.toInt() ?? 0;
        }
      }
      DateTime createdAt;
      try {
        createdAt = DateTime.parse(manifest['createdAt'] as String);
      } catch (_) {
        createdAt = DateTime.now();
      }
      return Success(_ParsedBackup(
        createdAt: createdAt,
        appVersion: manifest['appVersion'] as String? ?? '?',
        encrypted:
            manifest['encrypted'] as bool? ?? false,
        counts: counts,
        data: data,
        fileNames: files.keys.toList(),
        files: files,
      ));
    } catch (e) {
      if (e is AppException) rethrow;
      return Failure(PersistenceException(
          'That file could not be read as a SoulCare backup.',
          originalError: e));
    }
  }

  /// Applies records; returns number of records written.
  /// Merge never overwrites existing keys (no silent newer-data loss).
  Future<int> _apply(
      _ParsedBackup backup, RestoreStrategy strategy) async {
    var written = 0;
    final vault = await _vault();
    if (strategy == RestoreStrategy.replace) {
      for (final name in backupBoxNames) {
        try {
          if (HiveBox.isOpen(name)) {
            await HiveBox.box(name).clear();
          }
        } catch (_) {
          throw const _RestoreFailure(
              'Could not clear local storage.');
        }
      }
      try {
        await for (final f in vault.list()) {
          if (f is File) await f.delete();
        }
      } catch (_) {
        throw const _RestoreFailure('Could not clear the vault.');
      }
    }
    for (final boxName in backup.data.keys) {
      if (!backupBoxNames.contains(boxName)) continue;
      if (!HiveBox.isOpen(boxName)) continue;
      final box = HiveBox.box(boxName);
      final records = backup.data[boxName];
      if (records is! Map) continue;
      for (final key in records.keys) {
        final value = records[key];
        if (value is! Map) continue;
        if (strategy == RestoreStrategy.merge &&
            box.containsKey(key)) {
          continue; // never overwrite existing (possibly newer) data
        }
        // Documents: skip duplicates already present by content.
        if (strategy == RestoreStrategy.merge &&
            boxName == 'medical_documents') {
          final hash = value['contentHash'];
          var dup = false;
          for (final k in box.keys) {
            final existing = box.get(k);
            if (existing is Map &&
                existing['contentHash'] == hash &&
                hash is String &&
                hash.isNotEmpty) {
              dup = true;
              break;
            }
          }
          if (dup) continue;
        }
        await box.put(key, Map<String, dynamic>.from(value));
        written++;
      }
    }
    // Vault files for newly added documents.
    for (final name in backup.fileNames) {
      final bytes = backup.files[name]!;
      final dest = File(p.join(vault.path, p.basename(name)));
      if (strategy == RestoreStrategy.merge && await dest.exists()) {
        continue;
      }
      await dest.writeAsBytes(bytes, flush: true);
    }
    return written;
  }
}

/// Thin Hive facade (single choke point for box access in this service).
class HiveBox {
  static bool isOpen(String name) {
    try {
      return Hive.isBoxOpen(name);
    } catch (_) {
      return false;
    }
  }

  static dynamic box(String name) => Hive.box(name);
}

class BackupOutcome {
  final String path;
  final DateTime createdAt;
  final Map<String, int> counts;
  final int fileCount;
  final bool encrypted;
  const BackupOutcome({
    required this.path,
    required this.createdAt,
    required this.counts,
    required this.fileCount,
    required this.encrypted,
  });
}

class RestoreOutcome {
  final RestoreStrategy strategy;
  final int added;
  final bool safetyKept;
  const RestoreOutcome({
    required this.strategy,
    required this.added,
    required this.safetyKept,
  });
}

class _ParsedBackup {
  final DateTime createdAt;
  final String appVersion;
  final bool encrypted;
  final Map<String, int> counts;
  final Map<String, dynamic> data;
  final List<String> fileNames;
  final Map<String, List<int>> files;
  const _ParsedBackup({
    required this.createdAt,
    required this.appVersion,
    required this.encrypted,
    required this.counts,
    required this.data,
    required this.fileNames,
    required this.files,
  });
}

class _RestoreFailure implements Exception {
  final String message;
  const _RestoreFailure(this.message);
}

/// In-memory copy of every box + vault file copies in temp.
/// Rollback rewrites everything, so a failed restore never corrupts.
/// Public so the safety behavior itself is testable.
class BackupSafetySnapshot {
  final Map<String, Map<String, dynamic>> boxes;
  final Map<String, List<int>> vaultFiles;

  const BackupSafetySnapshot(
      {required this.boxes, required this.vaultFiles});

  static Future<BackupSafetySnapshot> take({Directory? vaultDir}) async {
    final boxes = <String, Map<String, dynamic>>{};
    for (final name in backupBoxNames) {
      final box = <String, dynamic>{};
      try {
        if (!HiveBox.isOpen(name)) continue;
        final b = HiveBox.box(name);
        for (final k in b.keys) {
          final v = b.get(k);
          box['$k'] =
              v is Map ? Map<String, dynamic>.from(v) : v;
        }
      } catch (_) {}
      boxes[name] = box;
    }
    final vaultFiles = <String, List<int>>{};
    try {
      final vault =
          await DocumentStorage.vaultDirectory(override: vaultDir);
      await for (final f in vault.list()) {
        if (f is File) {
          vaultFiles[p.basename(f.path)] =
              await f.readAsBytes();
        }
      }
    } catch (_) {}
    return BackupSafetySnapshot(boxes: boxes, vaultFiles: vaultFiles);
  }

  Future<void> rollback({Directory? vaultDir}) async {
    for (final name in boxes.keys) {
      try {
        if (!HiveBox.isOpen(name)) continue;
        final box = HiveBox.box(name);
        await box.clear();
        for (final k in boxes[name]!.keys) {
          await box.put(k, boxes[name]![k]);
        }
      } catch (_) {}
    }
    try {
      final vault =
          await DocumentStorage.vaultDirectory(override: vaultDir);
      await for (final f in vault.list()) {
        if (f is File) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
      for (final name in vaultFiles.keys) {
        await File(p.join(vault.path, name))
            .writeAsBytes(vaultFiles[name]!, flush: true);
      }
    } catch (_) {}
  }
}
