import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/providers/ai_chat_provider.dart';
import '../../app/providers/documents_provider.dart';
import '../../core/ai/ai_models.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/pin_gate.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';

/// Document detail: metadata, tags, notes, processing state.
/// Actions: Open · Rename · Edit metadata · Delete.
class DocumentDetailScreen extends StatefulWidget {
  final String documentId;
  const DocumentDetailScreen({super.key, required this.documentId});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  bool _missing = false;
  bool _checked = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFile());
  }

  Future<void> _checkFile() async {
    MedicalDocument? doc;
    try {
      doc = context
          .read<DocumentsProvider>()
          .all
          .firstWhere((d) => d.id == widget.documentId);
    } catch (_) {
      doc = null;
    }
    if (doc == null) return;
    final missing = await doc.isFileMissing;
    if (!mounted) return;
    setState(() {
      _missing = missing;
      _checked = true;
    });
  }

  MedicalDocument? _doc() {
    final all = context.watch<DocumentsProvider>().all;
    for (final d in all) {
      if (d.id == widget.documentId) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(doc?.fileName ?? 'Document',
            overflow: TextOverflow.ellipsis),
      ),
      body: PinGate(
        screen: 'timeline',
        title: 'Documents are locked',
        subtitle: 'Unlock to view this document.',
        child: doc == null
          ? const AppEmptyState(
              icon: Icons.find_in_page_outlined,
              title: 'Document not found',
              subtitle: 'It may have been deleted.',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_checked && _missing)
                  AppCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_outlined,
                            color: scheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'The original file is missing from local storage. Your metadata is intact; re-import the PDF to view it again.',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_checked && _missing) const SizedBox(height: 12),
                // Header.
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.picture_as_pdf_outlined,
                              size: 32, color: scheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(doc.fileName,
                                    style:
                                        theme.textTheme.titleMedium),
                                Text(
                                  doc.documentDate != null
                                      ? 'Document date: ${_fmt(doc.documentDate!)}'
                                      : 'Document date not set',
                                  style: theme.textTheme.bodySmall,
                                ),
                                Text(
                                  'Added ${_fmt(doc.importedAt)}',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(
                                          color:
                                              scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Chip(label: Text(doc.category.label)),
                          for (final t in doc.tags) Chip(label: Text(t)),
                        ],
                      ),
                      if (doc.provider.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Provider: ${doc.provider}',
                            style: theme.textTheme.bodyMedium),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Processing state (honest — never claims fake AI work).
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Processing',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        'Status: ${doc.processingStatus.label}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (doc.summary != null &&
                          doc.summary!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(doc.summary!,
                            style: theme.textTheme.bodySmall),
                      ] else
                        Text(
                          'No summary. Summaries only appear after genuine processing.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant),
                        ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                setState(() => _busy = true);
                                final res = await context
                                    .read<DocumentsProvider>()
                                    .process(doc);
                                if (!context.mounted) return;
                                setState(() => _busy = false);
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: Text(res.message ??
                                      'State: ${res.state.name}'),
                                ));
                              },
                        child: Text(_busy ? 'Checking…' : 'Try processing'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Notes.
                const SectionHeader(title: 'Notes'),
                const SizedBox(height: 4),
                AppCard(
                  child: Text(
                    (doc.notes == null || doc.notes!.isEmpty)
                        ? 'No notes yet. Use Edit metadata to add some.'
                        : doc.notes!,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 16),
                // Actions.
                FilledButton.icon(
                  onPressed: (_checked && _missing)
                      ? null
                      : () => context.push(
                          '/timeline/doc/${doc.id}/view'),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _renameDialog(context, doc),
                        icon: const Icon(Icons.drive_file_rename_outline),
                        label: const Text('Rename'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _editSheet(context, doc),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit metadata'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _aiConfirm(context, doc),
                  icon: const Icon(Icons.psychology_outlined),
                  label: const Text('Ask AI'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _deleteConfirm(context, doc),
                  icon: Icon(Icons.delete_outline,
                      color: scheme.error),
                  label: Text('Delete',
                      style: TextStyle(color: scheme.error)),
                ),
                const SizedBox(height: 24),
              ],
            ),
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Explicit-consent AI handoff: document contents are NOT readable by
  /// the AI (no PDF text extraction exists), so only the reference the
  /// user confirmed — name, category, dates — is attached, once.
  Future<void> _aiConfirm(
      BuildContext context, MedicalDocument doc) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Use this document with SoulCare AI?'),
        content: const Text(
            'Only this document\u2019s name, category and dates will be shared with the on-device AI, for your next question only. File contents stay private — document text cannot be read yet.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Use document')),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    context.read<AiChatProvider>().attach(PendingAttachment(
          kind: 'document',
          label: doc.fileName,
          content:
              'Document reference (contents not readable): ${doc.fileName}, category ${doc.category.name}.',
        ));
    context.push('/ai');
  }

  Future<void> _renameDialog(
      BuildContext context, MedicalDocument doc) async {
    final controller = TextEditingController(text: doc.fileName);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Rename document'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'File name',
            hintText: 'e.g. blood-test-march.pdf',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(c).pop(controller.text.trim()),
              child: const Text('Rename')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !context.mounted) return;
    final updated =
        await context.read<DocumentsProvider>().rename(doc, name);
    if (!context.mounted) return;
    if (updated != null) {
      await _checkFile();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Renamed ✓')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.read<DocumentsProvider>().error ??
              'Could not rename.')));
    }
  }

  Future<void> _deleteConfirm(
      BuildContext context, MedicalDocument doc) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text(
            '"${doc.fileName}" and its stored file will be permanently removed from this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    final ok = await context.read<DocumentsProvider>().remove(doc.id);
    if (!context.mounted) return;
    if (ok) {
      context.pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Deleted.')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.read<DocumentsProvider>().error ??
              'Could not delete.')));
    }
  }

  Future<void> _editSheet(
      BuildContext context, MedicalDocument doc) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditMetadataSheet(doc: doc),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved ✓')));
    }
  }
}

/// Bottom-sheet editor: category, provider, document date, tags, notes.
class _EditMetadataSheet extends StatefulWidget {
  final MedicalDocument doc;
  const _EditMetadataSheet({required this.doc});

  @override
  State<_EditMetadataSheet> createState() => _EditMetadataSheetState();
}

class _EditMetadataSheetState extends State<_EditMetadataSheet> {
  late DocumentCategory _category;
  late final TextEditingController _provider;
  late final TextEditingController _tags;
  late final TextEditingController _notes;
  DateTime? _docDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _category = widget.doc.category;
    _provider = TextEditingController(text: widget.doc.provider);
    _tags = TextEditingController(text: widget.doc.tags.join(', '));
    _notes = TextEditingController(text: widget.doc.notes ?? '');
    _docDate = widget.doc.documentDate;
  }

  @override
  void dispose() {
    _provider.dispose();
    _tags.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, 28 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Edit metadata', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            DropdownButtonFormField<DocumentCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in DocumentCategory.values)
                  DropdownMenuItem(value: c, child: Text(c.label)),
              ],
              onChanged: (v) =>
                  setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _provider,
              decoration: const InputDecoration(
                labelText: 'Provider (hospital, clinic, doctor)',
                hintText: 'e.g. City Lab',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _docDate == null
                        ? 'Document date: not set'
                        : 'Document date: ${_docDate!.year}-${_docDate!.month.toString().padLeft(2, '0')}-${_docDate!.day.toString().padLeft(2, '0')}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _docDate ?? DateTime.now(),
                      firstDate: DateTime(1990),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => _docDate = picked);
                    }
                  },
                  child: const Text('Pick date'),
                ),
                if (_docDate != null)
                  TextButton(
                    onPressed: () => setState(() => _docDate = null),
                    child: const Text('Clear'),
                  ),
              ],
            ),
            TextField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: 'Tags (comma separated)',
                hintText: 'e.g. annual, thyroid, urgent',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              maxLines: 3,
              maxLength: 2000,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      final tags = _tags.text
                          .split(',')
                          .map((t) => t.trim())
                          .where((t) => t.isNotEmpty)
                          .toList();
                      final ok = await context
                          .read<DocumentsProvider>()
                          .updateMetadata(widget.doc.copyWith(
                            category: _category,
                            provider: _provider.text,
                            documentDate: _docDate,
                            tags: tags,
                            notes: _notes.text.trim().isEmpty
                                ? null
                                : _notes.text.trim(),
                          ));
                      if (!context.mounted) return;
                      Navigator.of(context).pop(ok);
                    },
              child: Text(_saving ? 'Saving…' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
