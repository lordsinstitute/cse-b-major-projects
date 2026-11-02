import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soul_care/app/providers/documents_provider.dart';
import 'package:soul_care/core/documents/document_processor.dart';
import 'package:soul_care/core/errors/app_exceptions.dart';
import 'package:soul_care/data/local/document_storage.dart';
import 'package:soul_care/data/local/local_database.dart';
import 'package:soul_care/data/models/enums.dart';
import 'package:soul_care/data/models/models.dart';
import 'package:soul_care/data/repositories/medical_document_repository.dart';
import 'package:soul_care/features/timeline/document_detail_screen.dart';
import 'package:soul_care/features/timeline/pdf_viewer_screen.dart';
import 'package:soul_care/features/timeline/timeline_screen.dart';

late Directory _vaultDir;
late Directory _pickerDir;

Future<void> _initTestHive() async {
  final dir = await Directory.systemTemp.createTemp('soulcare_p3');
  Hive.init(dir.path);
  await Future.wait([
    Hive.openBox(LocalDatabase.dailyBoxName),
    Hive.openBox(LocalDatabase.stressBoxName),
    Hive.openBox(LocalDatabase.experimentsBoxName),
    Hive.openBox(LocalDatabase.documentsBoxName),
    Hive.openBox(LocalDatabase.settingsBoxName),
  ]);
  _vaultDir = await Directory.systemTemp.createTemp('soulcare_vault');
  _pickerDir = await Directory.systemTemp.createTemp('soulcare_picker');
}

int _pdfCounter = 0;

/// Distinct minimal PDF bytes per call (valid header, unique body).
List<int> _pdfBytes(String tag) {
  _pdfCounter++;
  final body = '%PDF-1.4\n% $tag #$_pdfCounter\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n'
      '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n'
      '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\n'
      'trailer<</Root 1 0 R>>\n%%EOF\n';
  return body.codeUnits;
}

Future<String> _pickerPdf(String name, String tag) async {
  final f = File('${_pickerDir.path}/$name');
  await f.writeAsBytes(_pdfBytes(tag), flush: true);
  return f.path;
}

MedicalDocumentRepository _repo() => MedicalDocumentRepository(
    storage: DocumentStorage(testDir: _vaultDir));

/// Fixed date for document fixtures.
final _fixedDate = DateTime(2026, 9, 18);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await _initTestHive();
  });

  tearDown(() async {
    await LocalDatabase.clearAll();
  });

  group('document model', () {
    test('round-trips with provider + tags + new categories', () {
      final doc = MedicalDocument(
        id: 'd1',
        fileName: 'blood-test.pdf',
        localPath: '/vault/x.pdf',
        importedAt: DateTime(2026, 9, 20),
        documentDate: DateTime(2026, 9, 18),
        category: DocumentCategory.labResult,
        tags: const ['annual', 'thyroid'],
        provider: 'City Lab',
        notes: 'Fasting sample',
        processingStatus: DocumentProcessingStatus.idle,
      );
      final restored = MedicalDocument.fromJson(doc.toJson());
      expect(restored.provider, 'City Lab');
      expect(restored.tags, ['annual', 'thyroid']);
      expect(restored.category, DocumentCategory.labResult);
      expect(restored.documentDate, DateTime(2026, 9, 18));
    });

    test('legacy values migrate (labReport/note/pending/processed)', () {
      final old = MedicalDocument.fromJson({
        'id': 'old',
        'fileName': 'x.pdf',
        'localPath': '/tmp/x.pdf',
        'importedAt': '2026-01-01T00:00:00.000',
        'category': 'labReport',
        'processingStatus': 'pending',
      });
      expect(old.category, DocumentCategory.labResult);
      expect(old.processingStatus, DocumentProcessingStatus.idle);

      final old2 = MedicalDocument.fromJson({
        'id': 'old2',
        'fileName': 'y.pdf',
        'localPath': '/tmp/y.pdf',
        'importedAt': '2026-01-01T00:00:00.000',
        'category': 'note',
        'processingStatus': 'processed',
      });
      expect(old2.category, DocumentCategory.other);
      expect(old2.processingStatus, DocumentProcessingStatus.completed);
    });
  });

  group('import', () {
    test('single PDF copied to vault, survives source deletion', () async {
      final src = await _pickerPdf('report.pdf', 'single');
      final res = await _repo().importPickedFiles(
          [(sourcePath: src, originalName: 'report.pdf')]);
      expect(res.isSuccess, isTrue);
      final doc = res.value!.imported.single;
      expect(doc.fileName, 'report.pdf');
      expect(await File(doc.localPath).exists(), isTrue);
      expect(doc.localPath, isNot(startsWith(_pickerDir.path)));

      // Original source can vanish — vault copy remains.
      await File(src).delete();
      expect(await File(doc.localPath).exists(), isTrue);
      expect(await doc.isFileMissing, isFalse);
    });

    test('multiple PDFs import together', () async {
      final a = await _pickerPdf('a.pdf', 'multi-a');
      final b = await _pickerPdf('b.pdf', 'multi-b');
      final c = await _pickerPdf('c.pdf', 'multi-c');
      final res = await _repo().importPickedFiles([
        (sourcePath: a, originalName: 'a.pdf'),
        (sourcePath: b, originalName: 'b.pdf'),
        (sourcePath: c, originalName: 'c.pdf'),
      ]);
      expect(res.value!.imported.length, 3);
      expect(res.value!.skipped, isEmpty);
    });

    test('invalid files skipped: wrong type, unreadable, empty', () async {
      final txt = File('${_pickerDir.path}/notes.txt');
      await txt.writeAsString('hello');
      final empty = File('${_pickerDir.path}/empty.pdf');
      await empty.writeAsBytes([]);
      final res = await _repo().importPickedFiles([
        (sourcePath: txt.path, originalName: 'notes.txt'),
        (sourcePath: '${_pickerDir.path}/gone.pdf', originalName: 'gone.pdf'),
        (sourcePath: empty.path, originalName: 'empty.pdf'),
      ]);
      expect(res.value!.imported, isEmpty);
      expect(res.value!.skipped.length, 3);
      for (final s in res.value!.skipped) {
        expect(s.skippedReason, isNotNull);
      }
    });

    test('oversize file rejected', () async {
      final big = File('${_pickerDir.path}/big.pdf');
      // 25 MB limit + 1 byte (sparse streaming write).
      final sink = big.openWrite();
      sink.add(List.filled(1024 * 1024, 0));
      for (var i = 0; i < 25; i++) {
        sink.add(List.filled(1024 * 1024, i % 251));
      }
      sink.add([1]);
      await sink.close();
      final res = await _repo().importPickedFiles(
          [(sourcePath: big.path, originalName: 'big.pdf')]);
      expect(res.value!.imported, isEmpty);
      expect(res.value!.skipped.single.skippedReason, contains('25'));
      await big.delete();
    });

    test('duplicate content imported only once', () async {
      final repo = _repo();
      final src1 = await _pickerPdf('dup.pdf', 'same-bytes');
      final first = await repo.importPickedFiles(
          [(sourcePath: src1, originalName: 'dup.pdf')]);
      expect(first.value!.imported.length, 1);

      // Different name, identical bytes → duplicate.
      final src2 = '${_pickerDir.path}/dup-renamed.pdf';
      await File(src1).copy(src2);
      final second = await repo.importPickedFiles(
          [(sourcePath: src2, originalName: 'dup-renamed.pdf')]);
      expect(second.value!.imported, isEmpty);
      expect(second.value!.skipped.single.skippedReason, contains('Already'));

      final all = await repo.getAll();
      expect(all.value!.length, 1);
    });
  });

  group('repository CRUD', () {
    test('restart: new repository instance still lists documents', () async {
      final src = await _pickerPdf('persist.pdf', 'persist');
      await _repo().importPickedFiles(
          [(sourcePath: src, originalName: 'persist.pdf')]);

      // Simulate app restart — fresh repo over the same boxes.
      final fresh = MedicalDocumentRepository(
          storage: DocumentStorage(testDir: _vaultDir));
      final all = await fresh.getAll();
      expect(all.isSuccess, isTrue);
      expect(all.value!.length, 1);
      expect(all.value!.single.fileName, 'persist.pdf');
    });

    test('search by filename, category, tag, provider, notes', () async {
      final repo = _repo();
      final src = await _pickerPdf('thyroid.pdf', 'search');
      final imported =
          (await repo.importPickedFiles([(sourcePath: src, originalName: 'thyroid.pdf')]))
              .value!
              .imported
              .single;
      await repo.updateMetadata(imported.copyWith(
        category: DocumentCategory.labResult,
        provider: 'City Lab',
        tags: const ['annual'],
        notes: 'fasting sample',
        documentDate: DateTime(2026, 9, 18),
      ));

      Future<int> hits(String q) async =>
          (await repo.search(query: q)).value!.length;
      expect(await hits('thyroid'), 1);
      expect(await hits('lab result'), 1);
      expect(await hits('annual'), 1);
      expect(await hits('city'), 1);
      expect(await hits('fasting'), 1);
      expect(await hits('no-such-thing'), 0);
    });

    test('category filter narrows results', () async {
      final repo = _repo();
      final a = await _pickerPdf('lab.pdf', 'filter-lab');
      final b = await _pickerPdf('rx.pdf', 'filter-rx');
      final da = (await repo.importPickedFiles(
              [(sourcePath: a, originalName: 'lab.pdf')]))
          .value!
          .imported
          .single;
      final db = (await repo.importPickedFiles(
              [(sourcePath: b, originalName: 'rx.pdf')]))
          .value!
          .imported
          .single;
      await repo.updateMetadata(
          da.copyWith(category: DocumentCategory.labResult));
      await repo.updateMetadata(
          db.copyWith(category: DocumentCategory.prescription));

      final onlyRx = await repo.search(
          categories: {DocumentCategory.prescription});
      expect(onlyRx.value!.length, 1);
      expect(onlyRx.value!.single.fileName, 'rx.pdf');
    });

    test('rename updates metadata + vault file', () async {
      final repo = _repo();
      final src = await _pickerPdf('old-name.pdf', 'rename');
      final doc = (await repo.importPickedFiles(
              [(sourcePath: src, originalName: 'old-name.pdf')]))
          .value!
          .imported
          .single;
      final oldPath = doc.localPath;

      final renamed = await repo.rename(doc, 'blood-test-march');
      expect(renamed.isSuccess, isTrue);
      expect(renamed.value!.fileName, 'blood-test-march.pdf');
      expect(await File(renamed.value!.localPath).exists(), isTrue);
      expect(await File(oldPath).exists(), isFalse);
    });

    test('rename rejects empty names', () async {
      final repo = _repo();
      final src = await _pickerPdf('keep.pdf', 'rename-empty');
      final doc = (await repo.importPickedFiles(
              [(sourcePath: src, originalName: 'keep.pdf')]))
          .value!
          .imported
          .single;
      final res = await repo.rename(doc, '   ');
      expect(res.isFailure, isTrue);
    });

    test('tagging cleans duplicates, blanks, caps count', () async {
      final repo = _repo();
      final src = await _pickerPdf('tags.pdf', 'tags');
      final doc = (await repo.importPickedFiles(
              [(sourcePath: src, originalName: 'tags.pdf')]))
          .value!
          .imported
          .single;
      final updated = await repo.updateMetadata(doc.copyWith(tags: const [
        ' Annual ',
        'annual',
        '  ',
        'thyroid',
      ]));
      expect(updated.isSuccess, isTrue);
      expect(updated.value!.tags, ['Annual', 'thyroid']);
    });

    test('delete removes metadata + vault file', () async {
      final repo = _repo();
      final src = await _pickerPdf('todelete.pdf', 'delete');
      final doc = (await repo.importPickedFiles(
              [(sourcePath: src, originalName: 'todelete.pdf')]))
          .value!
          .imported
          .single;
      final path = doc.localPath;
      expect(await repo.delete(doc.id),
          predicate<Result<void>>((r) => r.isSuccess));
      expect((await repo.getById(doc.id)).value, isNull);
      expect(await File(path).exists(), isFalse);
    });

    test('missing vault file is detectable', () async {
      final repo = _repo();
      final src = await _pickerPdf('lost.pdf', 'lost');
      final doc = (await repo.importPickedFiles(
              [(sourcePath: src, originalName: 'lost.pdf')]))
          .value!
          .imported
          .single;
      await File(doc.localPath).delete();
      expect(await doc.isFileMissing, isTrue);
      // Metadata survives the missing file.
      expect((await repo.getById(doc.id)).value, isNotNull);
    });
  });

  group('processor', () {
    test('default processor is unavailable and never fabricates', () async {
      const processor = UnavailableDocumentProcessor();
      expect(processor.isAvailable, isFalse);
      final doc = MedicalDocument(
        id: 'x',
        fileName: 'x.pdf',
        localPath: '/vault/x.pdf',
        importedAt: DateTime(2026, 9, 29),
      );
      expect(processor.stateFor(doc), ProcessorState.idle);
      final res = await processor.process(doc);
      expect(res.state, ProcessorState.unavailable);
      expect(res.summary, isNull);
      expect(res.message, isNotNull);
    });
  });

  group('widgets', () {
    DocumentsProvider provider() {
      final p = DocumentsProvider(_repo());
      return p;
    }

    testWidgets('timeline empty state invites first import',
        (tester) async {
      final p = provider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider.value(value: p)],
          child: const MaterialApp(
              home: Scaffold(body: TimelineScreen())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('No documents yet'), findsOneWidget);
      expect(find.text('Import PDF'), findsWidgets);
      expect(find.textContaining('Stored only on this device'), findsNothing);
    });

    testWidgets('timeline lists imported doc with dates + privacy note',
        (tester) async {
      final repo = _repo();
      final src = await _pickerPdf('widget.pdf', 'widget');
      final doc = (await repo.importPickedFiles(
              [(sourcePath: src, originalName: 'widget.pdf')]))
          .value!
          .imported
          .single;
      await repo.updateMetadata(doc.copyWith(
        category: DocumentCategory.prescription,
        documentDate: DateTime(2026, 9, 18),
      ));

      final p = provider();
      await p.load();
      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider.value(value: p)],
          child: const MaterialApp(
              home: Scaffold(body: TimelineScreen())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('widget.pdf', skipOffstage: false), findsOneWidget);
      expect(find.text('2026', skipOffstage: false), findsOneWidget);
      expect(find.text('September', skipOffstage: false), findsOneWidget);
      expect(find.textContaining('Document date:', skipOffstage: false),
          findsOneWidget);
      expect(
          find.textContaining('Stored only on this device',
              skipOffstage: false),
          findsOneWidget);
    });

    testWidgets('detail screen shows actions', (tester) async {
      // Hive-free: provider state is preseeded, so no storage I/O can
      // wedge this test (Hive box writes stall intermittently on some
      // Windows machines). The absent vault path also exercises the
      // missing-file banner.
      final doc = MedicalDocument(
        id: 'detail-doc',
        fileName: 'detail.pdf',
        localPath: '/vault-not-present/detail.pdf',
        importedAt: _fixedDate,
        category: DocumentCategory.prescription,
        tags: ['annual'],
        provider: 'City Lab',
        notes: 'Take with food',
      );

      final p = provider();
      p.setForTest([doc]);
      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider.value(value: p)],
          child: MaterialApp(
              home: DocumentDetailScreen(documentId: doc.id)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      // Detail ListView builds all children eagerly; skipOffstage:false
      // sees them regardless of scroll position (no scrolling needed).
      expect(find.text('detail.pdf', skipOffstage: false), findsWidgets);
      expect(find.text('Open', skipOffstage: false), findsOneWidget);
      for (final label in [
        'Rename',
        'Edit metadata',
        'Delete',
        'Notes',
      ]) {
        expect(find.text(label, skipOffstage: false), findsWidgets);
      }
      expect(
          find.textContaining('missing from local storage',
              skipOffstage: false),
          findsOneWidget);
    });

    testWidgets('viewer shows friendly error for missing file',
        (tester) async {
      final doc = MedicalDocument(
        id: 'missing-doc',
        fileName: 'gone.pdf',
        localPath: '/vault-not-present/gone.pdf',
        importedAt: _fixedDate,
      );

      final p = provider();
      p.setForTest([doc]);
      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider.value(value: p)],
          child: MaterialApp(home: PdfViewerScreen(documentId: doc.id)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
          find.textContaining('missing from this device',
              skipOffstage: false),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
