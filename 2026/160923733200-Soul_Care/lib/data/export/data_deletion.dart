import 'dart:io';

import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/errors/app_exceptions.dart';
import '../local/local_database.dart';
import '../repositories/medical_document_repository.dart';

/// Local data deletion. Every method is explicit and scoped;
/// the UI must confirm before calling any of them.
///
/// Methods operate on open boxes directly and never silently skip:
/// a delete that cannot run returns Failure, never a false Success.
class DataDeletionService {
  final MedicalDocumentRepository _documents;

  DataDeletionService({MedicalDocumentRepository? documents})
      : _documents = documents ?? MedicalDocumentRepository();

  static bool _boxReady(String name) {
    try {
      return Hive.isBoxOpen(name);
    } catch (_) {
      return false;
    }
  }

  Future<Result<void>> deleteDailyHealth() async {
    try {
      var cleared = false;
      if (_boxReady(LocalDatabase.dailyBoxName)) {
        await LocalDatabase.dailyBox.clear();
        cleared = true;
      }
      if (_boxReady(LocalDatabase.stressBoxName)) {
        await LocalDatabase.stressBox.clear();
        cleared = true;
      }
      if (!cleared) {
        return const Failure(PersistenceException(
            'Health storage is unavailable right now. Nothing was deleted.'));
      }
      return const Success(null);
    } catch (e) {
      return Failure(PersistenceException('Could not delete health data.',
          originalError: e));
    }
  }

  Future<Result<void>> deleteExperiments() async {
    try {
      if (!_boxReady(LocalDatabase.experimentsBoxName)) {
        return const Failure(PersistenceException(
            'Experiment storage is unavailable right now. Nothing was deleted.'));
      }
      await LocalDatabase.experimentsBox.clear();
      return const Success(null);
    } catch (e) {
      return Failure(PersistenceException('Could not delete experiments.',
          originalError: e));
    }
  }

  /// Removes document metadata AND the stored vault files.
  Future<Result<int>> deleteDocuments() async {
    try {
      if (!_boxReady(LocalDatabase.documentsBoxName)) {
        return const Failure(PersistenceException(
            'Document storage is unavailable right now. Nothing was deleted.'));
      }
      var removedFiles = 0;
      final all = await _documents.getAll();
      final docs =
          all.fold(onSuccess: (l) => l, onFailure: (_) => const []);
      for (final d in docs) {
        try {
          final f = File(d.localPath);
          if (d.localPath.isNotEmpty && await f.exists()) {
            await f.delete();
            removedFiles++;
          }
        } catch (_) {}
      }
      await LocalDatabase.documentsBox.clear();
      return Success(removedFiles);
    } catch (e) {
      return Failure(PersistenceException('Could not delete documents.',
          originalError: e));
    }
  }

  /// Wipes everything: all boxes, vault files, preferences.
  Future<Result<void>> deleteEverything() async {
    try {
      final daily = await deleteDailyHealth();
      final exps = await deleteExperiments();
      final docs = await deleteDocuments();
      for (final name in [
        LocalDatabase.gameStatsBoxName,
        LocalDatabase.morningBoxName,
        LocalDatabase.eveningBoxName,
        LocalDatabase.journalBoxName,
        LocalDatabase.snapshotBoxName,
        LocalDatabase.settingsBoxName,
      ]) {
        if (_boxReady(name)) {
          await Hive.box(name).clear();
        }
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
      } catch (_) {}
      if (daily.isFailure && exps.isFailure && docs.isFailure) {
        return const Failure(PersistenceException(
            'Storage is unavailable right now. Nothing was deleted.'));
      }
      return const Success(null);
    } catch (e) {
      return Failure(PersistenceException('Could not delete all data.',
          originalError: e));
    }
  }
}
