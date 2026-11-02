import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/errors/app_exceptions.dart';
import '../../data/local/local_database.dart';
import '../../data/models/models.dart';
import '../../data/repositories/daily_health_repository.dart';
import '../../data/repositories/experiment_repository.dart';
import '../../data/repositories/medical_document_repository.dart';
import '../../data/repositories/stress_repository.dart';

/// Structured JSON export of personal wellness records.
///
/// Medical PDFs are NEVER embedded (no binary blobs in JSON). Documents
/// appear as metadata references (id + file name + category + dates) so
/// the export stays readable and small.
class DataExportService {
  final DailyHealthRepository _daily;
  final StressRepository _stress;
  final ExperimentRepository _experiments;
  final MedicalDocumentRepository _documents;

  DataExportService({
    DailyHealthRepository? daily,
    StressRepository? stress,
    ExperimentRepository? experiments,
    MedicalDocumentRepository? documents,
  })  : _daily = daily ?? DailyHealthRepository(),
        _stress = stress ?? StressRepository(),
        _experiments = experiments ?? ExperimentRepository(),
        _documents = documents ?? MedicalDocumentRepository();

  /// Builds the export map (pure data, no I/O beyond reads).
  Future<Result<Map<String, dynamic>>> buildExportMap() async {
    try {
      final now = DateTime.now();
      final wide = now.subtract(const Duration(days: 365 * 5));
      final dailyRes = await _daily.getRange(wide, now);
      final stressRes = await _stress.getRange(wide, now);
      final expRes = await _experiments.getAll();
      final docsRes = await _documents.getAll();
      final settingsRes = await SettingsExport.read();

      var entries = const <DailyHealthEntry>[];
      var checks = const <StressEntry>[];
      var exps = const <Experiment>[];
      var docs = const <MedicalDocument>[];
      dailyRes.fold(onSuccess: (l) => entries = l, onFailure: (_) {});
      stressRes.fold(onSuccess: (l) => checks = l, onFailure: (_) {});
      expRes.fold(onSuccess: (l) => exps = l, onFailure: (_) {});
      docsRes.fold(onSuccess: (l) => docs = l, onFailure: (_) {});
      if (dailyRes.isFailure &&
          stressRes.isFailure &&
          expRes.isFailure &&
          docsRes.isFailure) {
        return const Failure(PersistenceException(
            'Could not read your data for export.'));
      }

      return Success({
        'app': 'SoulCare',
        'exportedAt': now.toIso8601String(),
        'format': 'soulcare-export/1',
        'note':
            'Local-first export. Medical document files are referenced, not embedded.',
        'dailyHealth': [for (final e in entries) e.toJson()],
        'stressCheckIns': [for (final c in checks) c.toJson()],
        'experiments': [for (final e in exps) e.toJson()],
        'medicalDocuments': [
          for (final d in docs)
            {
              'id': d.id,
              'fileName': d.fileName,
              'category': d.category.name,
              'documentDate': d.documentDate?.toIso8601String(),
              'importedAt': d.importedAt.toIso8601String(),
              'tags': d.tags,
              'provider': d.provider,
            }
        ],
        'settings': settingsRes,
      });
    } catch (e) {
      return Failure(PersistenceException('Could not build the export.',
          originalError: e));
    }
  }

  /// Writes the JSON file and opens the Android share sheet.
  /// Returns the file path for display.
  Future<Result<ExportOutcome>> exportAndShare() async {
    final mapRes = await buildExportMap();
    if (mapRes.isFailure) return Failure(mapRes.error!);
    try {
      final dir = await getTemporaryDirectory();
      final stamp =
          DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final file =
          File(p.join(dir.path, 'soulcare-export-$stamp.json'));
      final counts = _counts(mapRes.value!);
      await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(mapRes.value!),
          flush: true);
      await SharePlus.instance.share(ShareParams(
        text: 'My SoulCare wellness export',
        files: [XFile(file.path, mimeType: 'application/json')],
      ));
      return Success(ExportOutcome(path: file.path, counts: counts));
    } catch (e) {
      return Failure(PersistenceException(
          'Could not share the export. Your data is unchanged.',
          originalError: e));
    }
  }

  static Map<String, int> _counts(Map<String, dynamic> map) => {
        'days': (map['dailyHealth'] as List).length,
        'checkIns': (map['stressCheckIns'] as List).length,
        'experiments': (map['experiments'] as List).length,
        'documents': (map['medicalDocuments'] as List).length,
      };
}

class ExportOutcome {
  final String path;
  final Map<String, int> counts;
  const ExportOutcome({required this.path, required this.counts});
}

/// Settings portion of the export (small prefs only).
class SettingsExport {
  static Future<Map<String, dynamic>> read() async {
    try {
      final raw = LocalDatabase.settingsBox.get('user_settings');
      if (raw == null) return const {};
      return Map<String, dynamic>.from(raw as Map);
    } catch (_) {
      return const {};
    }
  }
}
