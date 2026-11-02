import 'dart:io';

import '../../core/errors/app_exceptions.dart';
import '../local/document_storage.dart';
import '../local/local_database.dart';
import '../models/enums.dart';
import '../models/models.dart';

/// Outcome of importing one picked file.
class ImportOutcome {
  final String originalName;
  final MedicalDocument? document;
  final String? skippedReason;

  const ImportOutcome.imported(this.document)
      : originalName = '',
        skippedReason = null;

  const ImportOutcome.skipped(this.originalName, this.skippedReason)
      : document = null;

  bool get isImported => document != null;
}

/// Summary of a multi-file import.
class ImportSummary {
  final List<MedicalDocument> imported;
  final List<ImportOutcome> skipped;

  const ImportSummary({required this.imported, required this.skipped});
}

/// Document vault repository. Metadata lives in Hive; file bytes live in
/// the app-controlled vault directory. UI must go through here.
class MedicalDocumentRepository {
  final DocumentStorage _storage;

  MedicalDocumentRepository({DocumentStorage? storage})
      : _storage = storage ?? DocumentStorage();

  Future<Result<List<MedicalDocument>>> getAll() async {
    try {
      final out = <MedicalDocument>[];
      for (final key in LocalDatabase.documentsBox.keys) {
        final raw = LocalDatabase.documentsBox.get(key);
        if (raw == null) continue;
        out.add(
            MedicalDocument.fromJson(Map<String, dynamic>.from(raw as Map)));
      }
      out.sort((a, b) => _sortDate(b).compareTo(_sortDate(a)));
      return Success(out);
    } catch (e) {
      return Failure(PersistenceException('Could not load documents.',
          originalError: e));
    }
  }

  Future<Result<MedicalDocument?>> getById(String id) async {
    try {
      final raw = LocalDatabase.documentsBox.get(id);
      if (raw == null) return const Success(null);
      return Success(
          MedicalDocument.fromJson(Map<String, dynamic>.from(raw as Map)));
    } catch (e) {
      return Failure(PersistenceException('Could not load the document.',
          originalError: e));
    }
  }

  /// Imports picked files (single or multiple). Each file is validated
  /// (type/size/readable) and copied into the vault. Duplicates (identical
  /// content) are skipped with a friendly reason — never imported twice.
  Future<Result<ImportSummary>> importPickedFiles(
      List<({String sourcePath, String originalName})> picked) async {
    try {
      final existing = await _allDocs();
      final byHash = {for (final d in existing) d.contentHash: d};
      final imported = <MedicalDocument>[];
      final skipped = <ImportOutcome>[];

      for (final p in picked) {
        StoredFile stored;
        try {
          stored = await _storage.storePickedFile(
              File(p.sourcePath), p.originalName);
        } on ValidationException catch (e) {
          skipped.add(ImportOutcome.skipped(p.originalName, e.message));
          continue;
        } catch (e) {
          skipped.add(ImportOutcome.skipped(
              p.originalName, 'That file could not be imported.'));
          continue;
        }

        final dup = byHash[stored.contentHash];
        if (dup != null && stored.contentHash.isNotEmpty) {
          await _storage.deleteVaultFile(stored.localPath);
          skipped.add(ImportOutcome.skipped(p.originalName,
              'Already in your vault as "${dup.fileName}". Skipped.'));
          continue;
        }

        final now = DateTime.now();
        final doc = MedicalDocument(
          id: _newId(),
          fileName: stored.fileName,
          localPath: stored.localPath,
          importedAt: now,
          category: DocumentCategory.other,
          contentHash: stored.contentHash,
        );
        await LocalDatabase.documentsBox.put(doc.id, doc.toJson());
        byHash[doc.contentHash] = doc;
        imported.add(doc);
      }
      return Success(ImportSummary(imported: imported, skipped: skipped));
    } catch (e) {
      return Failure(PersistenceException(
          'Could not import documents. Nothing was lost — please try again.',
          originalError: e));
    }
  }

  /// Instant local search across filename, category, tags, provider, notes.
  /// [categories] optionally narrows to those categories.
  Future<Result<List<MedicalDocument>>> search({
    String query = '',
    Set<DocumentCategory> categories = const {},
  }) async {
    try {
      final all = await _allDocs();
      final q = query.trim().toLowerCase();
      final out = all.where((d) {
        if (categories.isNotEmpty && !categories.contains(d.category)) {
          return false;
        }
        if (q.isEmpty) return true;
        final hay = [
          d.fileName,
          d.category.label,
          d.provider,
          d.notes ?? '',
          ...d.tags,
        ].join(' ').toLowerCase();
        return q.split(RegExp(r'\s+')).every((word) => hay.contains(word));
      }).toList();
      out.sort((a, b) => _sortDate(b).compareTo(_sortDate(a)));
      return Success(out);
    } catch (e) {
      return Failure(PersistenceException('Search failed. Please try again.',
          originalError: e));
    }
  }

  Future<Result<MedicalDocument>> updateMetadata(MedicalDocument doc) async {
    try {
      if (doc.fileName.trim().isEmpty) {
        return const Failure(
            ValidationException('A file name is required.'));
      }
      final cleaned = doc.copyWith(
        tags: _cleanTags(doc.tags),
        provider: doc.provider.trim(),
      );
      await LocalDatabase.documentsBox.put(cleaned.id, cleaned.toJson());
      return Success(cleaned);
    } catch (e) {
      return Failure(PersistenceException('Could not save changes.',
          originalError: e));
    }
  }

  /// Renames both the metadata and the vault file (extension preserved).
  Future<Result<MedicalDocument>> rename(
      MedicalDocument doc, String newFileName) async {
    try {
      final name = newFileName.trim();
      if (name.isEmpty) {
        return const Failure(ValidationException('A file name is required.'));
      }
      String newPath = doc.localPath;
      try {
        newPath = await _storage.renameVaultFile(doc.localPath, name);
      } on ValidationException catch (e) {
        return Failure(e);
      }
      var finalName = name;
      if (!finalName.toLowerCase().endsWith('.pdf')) {
        finalName = '$finalName.pdf';
      }
      final updated =
          doc.copyWith(fileName: finalName, localPath: newPath);
      await LocalDatabase.documentsBox.put(updated.id, updated.toJson());
      return Success(updated);
    } catch (e) {
      return Failure(PersistenceException('Could not rename the document.',
          originalError: e));
    }
  }

  /// Deletes metadata and the vault file (best effort on the file).
  Future<Result<void>> delete(String id) async {
    try {
      final raw = LocalDatabase.documentsBox.get(id);
      if (raw != null) {
        final doc =
            MedicalDocument.fromJson(Map<String, dynamic>.from(raw as Map));
        await _storage.deleteVaultFile(doc.localPath);
      }
      await LocalDatabase.documentsBox.delete(id);
      return const Success(null);
    } catch (e) {
      return Failure(PersistenceException('Could not delete the document.',
          originalError: e));
    }
  }

  // --- helpers ---

  Future<List<MedicalDocument>> _allDocs() async {
    final res = await getAll();
    return res.fold(onSuccess: (v) => v, onFailure: (_) => []);
  }

  static DateTime _sortDate(MedicalDocument d) =>
      d.documentDate ?? d.importedAt;

  static List<String> _cleanTags(List<String> tags) {
    final seen = <String>{};
    final out = <String>[];
    for (final t in tags) {
      final c = t.trim();
      if (c.isEmpty || c.length > 40) continue;
      final key = c.toLowerCase();
      if (seen.add(key)) {
        out.add(c);
        if (out.length >= 10) break;
      }
    }
    return out;
  }

  static int _idCounter = 0;
  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';
}
