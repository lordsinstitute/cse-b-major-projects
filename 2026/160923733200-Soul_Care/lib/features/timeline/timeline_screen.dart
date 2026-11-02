import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/providers/documents_provider.dart';
import '../../app/theme/design_system.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/pin_gate.dart';
import '../../data/models/enums.dart';
import '../../data/models/models.dart';

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// /timeline — local medical-document organizer.
/// Year → month → document grouping, instant search, category filters.
/// No login, no cloud. Files stay on this device.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  final _searchController = TextEditingController();
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DocumentsProvider>().load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    final ok = await context.read<DocumentsProvider>().importFromPicker();
    if (!mounted) return;
    setState(() => _importing = false);
    final notice = context.read<DocumentsProvider>().notice;
    final error = context.read<DocumentsProvider>().error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          notice ?? error ?? (ok ? 'Imported ✓' : 'Nothing imported.'),
        ),
      ),
    );
    context.read<DocumentsProvider>().clearNotice();
  }

  @override
  Widget build(BuildContext context) {
    final docs = context.watch<DocumentsProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final groups = _group(docs.documents);

    return PinGate(
      screen: 'timeline',
      title: 'Documents are locked',
      subtitle: 'Unlock to view your medical timeline.',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DS.xl,
          DS.huge - DS.xl,
          DS.xl,
          DS.massive,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Documents',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'Your medical timeline, stored on this device',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _importing ? null : _import,
                  icon: _importing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.upload_file, size: 18),
                  label: Text(_importing ? 'Importing…' : 'Import PDFs'),
                ),
              ],
            ),
            Text(
              'Select one or many PDFs — each is validated and reported individually.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // Search.
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search name, category, tag, provider, notes…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: docs.query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          docs.setQuery('');
                        },
                      )
                    : null,
              ),
              onChanged: docs.setQuery,
            ),
            const SizedBox(height: 8),
            // Category filters.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final c in DocumentCategory.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(c.label),
                        selected: docs.filters.contains(c),
                        onSelected: (_) => docs.toggleCategory(c),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: docs.loading
                  ? const AppLoading(message: 'Loading your vault…')
                  : docs.error != null && docs.all.isEmpty
                  ? AppErrorState(message: docs.error!, onRetry: docs.load)
                  : docs.all.isEmpty
                  ? AppEmptyState(
                      icon: Icons.folder_open_outlined,
                      title: 'No documents yet',
                      subtitle:
                          'Import your first PDFs to start your local medical timeline.',
                      actionLabel: 'Import PDFs',
                      onAction: _import,
                    )
                  : docs.documents.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.search_off_outlined,
                      title: 'No matches',
                      subtitle: 'Try a different search or clear the filters.',
                    )
                  : ListView(
                      children: [
                        for (final year in groups.keys) ...[
                          Text(year, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 4),
                          for (final month in groups[year]!.keys) ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 8,
                                top: 8,
                                bottom: 4,
                              ),
                              child: Text(
                                _monthNames[month - 1],
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                            for (final doc in groups[year]![month]!)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 16,
                                  bottom: 8,
                                ),
                                child: _DocumentRow(doc: doc),
                              ),
                          ],
                          const SizedBox(height: 8),
                        ],
                        // Privacy footer.
                        AppCard(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.lock_outline,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Stored only on this device. Nothing is uploaded unless you explicitly use a cloud feature.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Year → month → docs, newest first. Sort key: document date, else import.
  static Map<String, Map<int, List<MedicalDocument>>> _group(
    List<MedicalDocument> docs,
  ) {
    final sorted = [...docs]
      ..sort((a, b) {
        final da = a.documentDate ?? a.importedAt;
        final db = b.documentDate ?? b.importedAt;
        return db.compareTo(da);
      });
    final out = <String, Map<int, List<MedicalDocument>>>{};
    for (final d in sorted) {
      final dt = d.documentDate ?? d.importedAt;
      final year = '${dt.year}';
      final months = out.putIfAbsent(year, () => {});
      months.putIfAbsent(dt.month, () => []).add(d);
    }
    return out;
  }
}

class _DocumentRow extends StatelessWidget {
  final MedicalDocument doc;
  const _DocumentRow({required this.doc});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final docDate = doc.documentDate;
    return AppCard(
      onTap: () => context.push('/timeline/doc/${doc.id}'),
      child: FutureBuilder<bool>(
        future: doc.isFileMissing,
        builder: (context, snap) {
          final missing = snap.data ?? false;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.picture_as_pdf_outlined,
                    color: missing ? scheme.error : scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      doc.fileName,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (missing)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'File missing',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  Chip(
                    label: Text(doc.category.label),
                    visualDensity: VisualDensity.compact,
                  ),
                  for (final t in doc.tags.take(3))
                    Chip(label: Text(t), visualDensity: VisualDensity.compact),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                docDate != null
                    ? 'Document date: ${_fmtDate(docDate)} · Added ${_fmtDate(doc.importedAt)}'
                    : 'Added ${_fmtDate(doc.importedAt)} (document date not set)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (doc.provider.isNotEmpty)
                Text(
                  'Provider: ${doc.provider}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
