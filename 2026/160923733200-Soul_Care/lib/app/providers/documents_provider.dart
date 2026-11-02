import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/documents/document_processor.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';
import '../../data/repositories/medical_document_repository.dart';

/// Documents vault state: list, instant local search, category filters,
/// import, rename, metadata edits, delete. No login, no cloud.
class DocumentsProvider extends ChangeNotifier {
  final MedicalDocumentRepository _repo;
  final MedicalDocumentProcessor processor;

  List<MedicalDocument> _all = [];
  String _query = '';
  final Set<DocumentCategory> _filters = {};
  bool _loading = false;
  String? _error;
  String? _notice;

  DocumentsProvider(this._repo, {MedicalDocumentProcessor? processor})
      : processor = processor ?? UnavailableDocumentProcessor();

  List<MedicalDocument> get documents => _filtered();
  List<MedicalDocument> get all => List.unmodifiable(_all);
  String get query => _query;
  Set<DocumentCategory> get filters => Set.unmodifiable(_filters);
  bool get loading => _loading;
  String? get error => _error;

  /// One-shot user-facing notice (import summary, etc.).
  String? get notice => _notice;

  /// Test seam: preloads list state without touching storage.
  @visibleForTesting
  void setForTest(List<MedicalDocument> docs) {
    _all = [...docs];
    notifyListeners();
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    final res = await _repo.getAll();
    res.fold(
      onSuccess: (list) => _all = list,
      onFailure: (e) => _error = e.message,
    );
    _loading = false;
    notifyListeners();
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void toggleCategory(DocumentCategory c) {
    if (_filters.contains(c)) {
      _filters.remove(c);
    } else {
      _filters.add(c);
    }
    notifyListeners();
  }

  void clearFilters() {
    _filters.clear();
    _query = '';
    notifyListeners();
  }

  List<MedicalDocument> _filtered() {
    final q = _query.trim().toLowerCase();
    final out = _all.where((d) {
      if (_filters.isNotEmpty && !_filters.contains(d.category)) {
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
      return q.split(RegExp(r'\s+')).every((w) => hay.contains(w));
    }).toList();
    return out;
  }

  /// Opens the Android document picker (single or multiple PDFs) and
  /// imports into the vault. Returns true if at least one file imported.
  Future<bool> importFromPicker() async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        allowMultiple: true,
      );
    } catch (_) {
      _error = 'Could not open the file picker. Please try again.';
      notifyListeners();
      return false;
    }
    if (picked == null || picked.files.isEmpty) return false;

    final inputs = <({String sourcePath, String originalName})>[];
    final tempFiles = <File>[];
    for (final f in picked.files) {
      if (f.path != null && f.path!.isNotEmpty) {
        inputs.add((sourcePath: f.path!, originalName: f.name));
      } else if (f.bytes != null) {
        // Content-URI without a path: stage bytes to temp, then import
        // (the vault still gets its own permanent copy).
        final tmp =
            File(p.join(Directory.systemTemp.path, 'soulcare_${f.name}'));
        await tmp.writeAsBytes(f.bytes!, flush: true);
        tempFiles.add(tmp);
        inputs.add((sourcePath: tmp.path, originalName: f.name));
      }
    }
    if (inputs.isEmpty) {
      _error = 'Those files could not be read. Please try again.';
      notifyListeners();
      return false;
    }

    final res = await _repo.importPickedFiles(inputs);
    for (final t in tempFiles) {
      try {
        if (await t.exists()) await t.delete();
      } catch (_) {}
    }
    return res.fold(
      onSuccess: (summary) {
        _all = [...summary.imported, ..._all];
        final parts = <String>[];
        if (summary.imported.isNotEmpty) {
          parts.add(
              '${summary.imported.length} imported ✓ (${summary.imported.map((d) => d.fileName).join(', ')})');
        }
        for (final s in summary.skipped) {
          parts.add('${s.originalName}: ${s.skippedReason}');
        }
        _notice = parts.join('\n');
        _error = null;
        notifyListeners();
        return summary.imported.isNotEmpty;
      },
      onFailure: (e) {
        _error = e.message;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> updateMetadata(MedicalDocument doc) async {
    final res = await _repo.updateMetadata(doc);
    return res.fold(
      onSuccess: (updated) {
        _replace(updated);
        return true;
      },
      onFailure: (e) {
        _error = e.message;
        notifyListeners();
        return false;
      },
    );
  }

  Future<MedicalDocument?> rename(MedicalDocument doc, String name) async {
    final res = await _repo.rename(doc, name);
    return res.fold(
      onSuccess: (updated) {
        _replace(updated);
        return updated;
      },
      onFailure: (e) {
        _error = e.message;
        notifyListeners();
        return null;
      },
    );
  }

  Future<bool> remove(String id) async {
    final res = await _repo.delete(id);
    return res.fold(
      onSuccess: (_) {
        _all.removeWhere((d) => d.id == id);
        notifyListeners();
        return true;
      },
      onFailure: (e) {
        _error = e.message;
        notifyListeners();
        return false;
      },
    );
  }

  /// Attempts (unavailable-by-default) processing. Never fabricates output.
  Future<ProcessResult> process(MedicalDocument doc) =>
      processor.process(doc);

  void clearNotice() {
    _notice = null;
    notifyListeners();
  }

  void _replace(MedicalDocument updated) {
    final i = _all.indexWhere((d) => d.id == updated.id);
    if (i >= 0) {
      _all[i] = updated;
    } else {
      _all = [updated, ..._all];
    }
    _error = null;
    notifyListeners();
  }
}
