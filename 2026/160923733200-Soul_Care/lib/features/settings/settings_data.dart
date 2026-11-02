import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers/daily_health_provider.dart';
import '../../app/providers/dashboard_provider.dart';
import '../../app/providers/documents_provider.dart';
import '../../app/providers/experiment_provider.dart';
import '../../data/backup/backup_service.dart';
import '../../data/export/data_deletion.dart';
import '../../data/export/data_export.dart';

/// /settings/data — export, backup/restore, deletion. Every destructive
/// action confirms first; providers refresh after wipes.
class DataScreen extends StatefulWidget {
  const DataScreen({super.key});

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await DataExportService().exportAndShare();
      if (!mounted) return;
      res.fold(
        onSuccess: (o) {
          final c = o.counts;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Exported ${c['days']} days, ${c['checkIns']} check-ins, '
                  '${c['experiments']} experiments, ${c['documents']} document refs.')));
        },
        onFailure: (e) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sentinel distinguishing "no password" from "user cancelled".
  static const _cancelled = '\u0000cancelled\u0000';

  /// Asks for an optional backup password. Returns the password, null for
  /// "no password", or [_cancelled] when the user backs out.
  Future<String?> _askBackupPassword({required bool create}) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(create ? 'Protect backup?' : 'Backup password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(create
                ? 'Optional password encrypts the whole backup file. It is never stored — lose it and the backup cannot be opened.'
                : 'Enter the password used when this backup was created. Leave empty for unprotected backups.'),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Password (optional)',
                  hintText: 'Minimum 4 characters'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(_cancelled),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(c).pop(ctrl.text.trim()),
              child: const Text('Continue')),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result == _cancelled) return _cancelled;
    if (result.length < 4) return null;
    return result;
  }

  Future<void> _createBackup() async {
    if (_busy) return;
    final password = await _askBackupPassword(create: true);
    if (password == _cancelled) return;
    if (!mounted) return;
    if (password != null &&
        password.isNotEmpty &&
        password.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Password needs at least 4 characters — or leave it empty for no password.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await BackupService().createBackup(password: password);
      if (!mounted) return;
      await res.fold(
        onSuccess: (o) async {
          final c = o.counts.values.fold(0, (a, b) => a + b);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Backup ready: $c records + ${o.fileCount} files${o.encrypted ? ' (encrypted)' : ''}. Choose where to keep it.')));
          await SharePlus.instance.share(ShareParams(
            text: 'My SoulCare backup — keep it somewhere safe.',
            files: [XFile(o.path, mimeType: 'application/zip')],
          ));
        },
        onFailure: (e) async {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    if (_busy) return;
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        allowMultiple: false,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open the file picker.')));
      return;
    }
    if (picked == null || picked.files.isEmpty) return; // cancelled
    final path = picked.files.single.path;
    if (path == null || path.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('That file could not be read.')));
      return;
    }
    setState(() => _busy = true);
    try {
      // Preview first without a password; retry with one if needed.
      var preview = await BackupService().preview(path);
      String? password;
      if (preview.isFailure &&
          preview.error!.message.contains('password')) {
        if (!mounted) return;
        final entered = await _askBackupPassword(create: false);
        if (entered == _cancelled) return;
        if (!mounted) return;
        if (entered != null && entered.isNotEmpty) {
          password = entered;
          preview =
              await BackupService().preview(path, password: password);
        }
      }
      if (!mounted) return;
      final okPreview = preview.fold(
          onSuccess: (v) => v, onFailure: (_) => null);
      if (okPreview == null) {
        final err = preview.fold(
            onSuccess: (_) => '', onFailure: (e) => e.message);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
        return;
      }
      // Confirmation summary + strategy choice.
      final strategy = await showDialog<RestoreStrategy>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Restore this backup?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Backup created: ${_fmtDateTime(okPreview.createdAt)}'
                    '${okPreview.encrypted ? ' (encrypted ✓)' : ''}'),
                const SizedBox(height: 8),
                const Text('Contains:'),
                for (final k in okPreview.counts.keys)
                  if ((okPreview.counts[k] ?? 0) > 0)
                    Text(
                        '· ${_labelBox(k)}: ${okPreview.counts[k]}'),
                Text('· Vault files: ${okPreview.fileCount}'),
                const SizedBox(height: 8),
                const Text(
                    'Merge adds only new records (your newer data is never overwritten). Replace wipes current data first — a safety copy is kept either way.'),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(c).pop(),
                child: const Text('Cancel')),
            FilledButton.tonal(
                onPressed: () =>
                    Navigator.of(c).pop(RestoreStrategy.merge),
                child: const Text('Merge')),
            FilledButton(
                onPressed: () =>
                    Navigator.of(c).pop(RestoreStrategy.replace),
                child: const Text('Replace')),
          ],
        ),
      );
      if (strategy == null || !mounted) return;
      final res = await BackupService().restore(path,
          strategy: strategy,
          password:
              password == null || password.isEmpty ? null : password);
      if (!mounted) return;
      res.fold(
        onSuccess: (o) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Restored ${o.added} records (${o.strategy.name}). Previous data was safety-kept. Restart the app to see everything fresh.')));
          _refreshProviders();
        },
        onFailure: (e) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _fmtDateTime(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _labelBox(String box) {
    switch (box) {
      case 'daily_health':
        return 'health entries';
      case 'stress_entries':
        return 'stress check-ins';
      case 'experiments':
        return 'experiments';
      case 'medical_documents':
        return 'documents';
      case 'morning_checkins':
        return 'morning check-ins';
      case 'evening_reflections':
        return 'evening reflections';
      case 'journal_entries':
        return 'journal entries';
      case 'health_snapshot':
        return 'health snapshot';
      case 'med_reminders':
        return 'medication reminders';
      case 'appointments':
        return 'appointments';
      case 'dose_log':
        return 'dose records';
      case 'game_stats':
        return 'game stats';
      case 'settings':
        return 'settings';
      default:
        return box;
    }
  }

  Future<bool> _confirm(String title, String body,
      {String confirmLabel = 'Delete'}) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: Text(confirmLabel)),
        ],
      ),
    );
    return yes == true;
  }

  void _refreshProviders() {
    if (!mounted) return;
    context.read<DailyHealthProvider>().loadToday();
    context.read<DashboardProvider>().load();
    context.read<ExperimentProvider>().load();
    context.read<DocumentsProvider>().load();
  }

  Future<void> _delete(
      String title,
      String body,
      Future<bool> Function() action,
      String doneMessage) async {
    if (!await _confirm(title, body)) return;
    if (!mounted) return;
    final ok = await action();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? doneMessage : 'Could not delete.')));
    // Refresh in-memory providers so the UI reflects the wipe.
    if (ok) _refreshProviders();
  }

  Future<void> _deleteEverything() async {
    final first = await _confirm('Delete ALL local data?',
        'This permanently removes daily health, experiments, documents and their stored files, games stats, and settings from this device. This cannot be undone.');
    if (!first || !mounted) return;
    final second = await _confirm('Really delete everything?',
        'Last chance — every local record will be wiped.',
        confirmLabel: 'Delete everything');
    if (!second || !mounted) return;
    final res = await DataDeletionService().deleteEverything();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.isSuccess
            ? 'All local data deleted.'
            : 'Could not delete all data.')));
    if (res.isSuccess) _refreshProviders();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data & backup'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/settings'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Export', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Readable JSON (days, check-ins, experiments, document references, settings). PDFs referenced, never embedded.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _busy ? null : _export,
            child: Text(_busy ? 'Working…' : 'Export as JSON'),
          ),
          const SizedBox(height: 16),
          Text('Backup & restore',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'One portable file (records + documents). Optional password (never stored). Restore previews first.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _busy ? null : _createBackup,
                  child:
                      Text(_busy ? 'Working…' : 'Create Backup'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _restoreBackup,
                  child: const Text('Restore'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Delete data',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          _DeleteTile(
            title: 'Delete daily health data',
            subtitle: 'Entries + stress check-ins',
            onTap: () => _delete(
              'Delete daily health data?',
              'All logged days and stress check-ins will be permanently removed from this device.',
              () async => (await DataDeletionService()
                      .deleteDailyHealth())
                  .isSuccess,
              'Daily health data deleted.',
            ),
          ),
          _DeleteTile(
            title: 'Delete experiments',
            subtitle: 'Active, history, everything',
            onTap: () => _delete(
              'Delete experiments?',
              'All experiments and check-ins will be permanently removed.',
              () async => (await DataDeletionService()
                      .deleteExperiments())
                  .isSuccess,
              'Experiments deleted.',
            ),
          ),
          _DeleteTile(
            title: 'Delete medical documents',
            subtitle: 'Metadata + stored files',
            onTap: () => _delete(
              'Delete medical documents?',
              'All document records and their stored PDF files will be permanently removed from this device.',
              () async => (await DataDeletionService()
                      .deleteDocuments())
                  .isSuccess,
              'Medical documents deleted.',
            ),
          ),
          _DeleteTile(
            title: 'Delete all local data',
            subtitle: 'Everything, including settings',
            destructive: true,
            onTap: _deleteEverything,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _DeleteTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool destructive;
  final VoidCallback onTap;
  const _DeleteTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title,
          style: destructive
              ? TextStyle(
                  color: scheme.error, fontWeight: FontWeight.w600)
              : null),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
