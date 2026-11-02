import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../../app/providers/documents_provider.dart';
import '../../core/widgets/app_widgets.dart';

/// In-app PDF viewer (stays inside SoulCare — no external app needed).
class PdfViewerScreen extends StatelessWidget {
  final String documentId;
  const PdfViewerScreen({super.key, required this.documentId});

  @override
  Widget build(BuildContext context) {
    final docs = context.watch<DocumentsProvider>();
    MedicalDocumentRef? found;
    for (final d in docs.all) {
      if (d.id == documentId) {
        found = MedicalDocumentRef(
            fileName: d.fileName, localPath: d.localPath);
        break;
      }
    }
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(found?.fileName ?? 'Document',
            overflow: TextOverflow.ellipsis),
      ),
      body: found == null
          ? const AppEmptyState(
              icon: Icons.find_in_page_outlined,
              title: 'Document not found',
              subtitle: 'It may have been deleted.',
            )
          : FutureBuilder<bool>(
              future: File(found.localPath).exists(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const AppLoading(message: 'Opening document…');
                }
                if (snap.data == false) {
                  return AppErrorState(
                    message:
                        'The stored file is missing from this device. Re-import the PDF to view it again. Your metadata is intact.',
                    onRetry: () =>
                        context.read<DocumentsProvider>().load(),
                  );
                }
                return PdfViewer.file(
                  found!.localPath,
                  params: PdfViewerParams(
                    errorBannerBuilder:
                        (context, error, stackTrace, documentRef) =>
                            Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'This file could not be opened as a PDF. It may be corrupted.',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class MedicalDocumentRef {
  final String fileName;
  final String localPath;
  const MedicalDocumentRef(
      {required this.fileName, required this.localPath});
}
