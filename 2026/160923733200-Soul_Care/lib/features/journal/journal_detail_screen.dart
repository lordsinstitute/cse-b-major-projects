import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/providers/ai_chat_provider.dart';
import '../../app/providers/journal_provider.dart';
import '../../core/ai/ai_models.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/enums.dart';
import '../../data/models/journal.dart';
import '../../data/repositories/daily_health_repository.dart';
import '../../data/repositories/stress_repository.dart';
import 'journal_screen.dart' show JournalGate;

/// Entry detail: full text, metadata, that-day health metrics shown
/// side-by-side (correlation only — never causal claims).
/// Actions: Open is implicit; Edit metadata; Delete (confirmed).
class JournalDetailScreen extends StatefulWidget {
  final String entryId;
  const JournalDetailScreen({super.key, required this.entryId});

  @override
  State<JournalDetailScreen> createState() => _JournalDetailScreenState();
}

class _JournalDetailScreenState extends State<JournalDetailScreen> {
  bool _editing = false;

  JournalEntry? _entry(BuildContext context) {
    final all = context.watch<JournalProvider>().all;
    for (final e in all) {
      if (e.id == widget.entryId) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Entry')),
      body: JournalGate(
        child: entry == null
            ? const AppEmptyState(
                icon: Icons.find_in_page_outlined,
                title: 'Entry not found',
                subtitle: 'It may have been deleted.',
              )
            : _editing
                ? _Editor(
                    entry: entry,
                    onDone: () =>
                        setState(() => _editing = false),
                  )
                : _DetailView(
                    entry: entry,
                    onEdit: () =>
                        setState(() => _editing = true),
                  ),
      ),
    );
  }
}

class _DetailView extends StatelessWidget {
  final JournalEntry entry;
  final VoidCallback onEdit;
  const _DetailView({required this.entry, required this.onEdit});

  /// Explicit-consent AI handoff: asks first, attaches this entry only,
  /// for the next message only.
  Future<void> _analyzeWithAi(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Analyze this journal entry?'),
        content: const Text(
            'Only this entry will be shared with the on-device AI, for your next question only. Nothing else is sent.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Analyze')),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    var body = entry.body.trim();
    if (body.length > 2000) body = '${body.substring(0, 2000)}…';
    context.read<AiChatProvider>().attach(PendingAttachment(
          kind: 'journal',
          label: entry.title?.isNotEmpty == true
              ? entry.title!
              : 'journal entry ${entry.date}',
          content: body,
        ));
    context.push('/ai');
  }

  Future<void> _delete(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text(
            'This journal entry will be permanently removed from this device.'),
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
    final ok =
        await context.read<JournalProvider>().remove(entry.id);
    if (!context.mounted) return;
    if (ok) {
      context.pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Deleted.')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.read<JournalProvider>().error ??
              'Could not delete.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.title != null &&
                  entry.title!.isNotEmpty) ...[
                Text(entry.title!,
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
              ],
              Text(entry.body,
                  style: theme.textTheme.bodyLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (entry.mood != null)
                    Chip(label: Text('Mood ${entry.mood}/5')),
                  if (entry.energy != null)
                    Chip(label: Text('Energy ${entry.energy}/5')),
                  if (entry.stress != null)
                    Chip(label: Text('Stress ${entry.stress}/5')),
                  for (final t in entry.tags) Chip(label: Text(t)),
                ],
              ),
              const SizedBox(height: 4),
              Text(entry.date,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ThatDayMetrics(date: entry.date),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _analyzeWithAi(context),
                icon: const Icon(Icons.psychology_outlined),
                label: const Text('Ask AI'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _delete(context),
                icon:
                    Icon(Icons.delete_outline, color: scheme.error),
                label: Text('Delete',
                    style: TextStyle(color: scheme.error)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Health metrics logged on the entry's date, shown for reflection.
/// Correlation display only — no causal language anywhere.
class _ThatDayMetrics extends StatelessWidget {
  final String date;
  const _ThatDayMetrics({required this.date});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return FutureBuilder<_DayMetrics>(
      future: _load(date),
      builder: (context, snap) {
        final m = snap.data;
        if (m == null || !m.hasAny) {
          return AppCard(
            child: Text(
              'No health metrics logged that day.',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant),
            ),
          );
        }
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('That day', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              if (m.sleep != null)
                Text('Sleep: ${formatHours(m.sleep!)}',
                    style: theme.textTheme.bodyMedium),
              if (m.exercise != null)
                Text('Exercise: ${m.exercise} min',
                    style: theme.textTheme.bodyMedium),
              if (m.water != null)
                Text('Water: ${m.water}/8',
                    style: theme.textTheme.bodyMedium),
              if (m.stress != null)
                Text('Stress: ${m.stress}/5',
                    style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(
                'Shown alongside your note for reflection — not as cause and effect.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<_DayMetrics> _load(String date) async {
    final daily = await DailyHealthRepository().getByDate(date);
    final entry = daily.fold(
        onSuccess: (e) => e, onFailure: (_) => null);
    double? calm;
    try {
      final checks = await StressRepository().getByDate(date);
      final moods = checks.fold(
          onSuccess: (l) => l.map((c) => c.mood.score).toList(),
          onFailure: (_) => const <int>[]);
      if (moods.isNotEmpty) {
        // Lower calm value presented as higher strain for display.
        final avg =
            moods.reduce((a, b) => a + b) / moods.length;
        calm = (6 - avg).clamp(1.0, 5.0);
      }
    } catch (_) {}
    return _DayMetrics(
      sleep: entry != null && entry.sleepHours > 0
          ? entry.sleepHours
          : null,
      exercise: entry != null && entry.exerciseMinutes > 0
          ? entry.exerciseMinutes
          : null,
      water:
          entry != null && entry.waterGlasses > 0 ? entry.waterGlasses : null,
      stress: calm?.round(),
    );
  }
}

class _DayMetrics {
  final double? sleep;
  final int? exercise;
  final int? water;
  final int? stress;
  const _DayMetrics({this.sleep, this.exercise, this.water, this.stress});

  bool get hasAny =>
      sleep != null ||
      exercise != null ||
      water != null ||
      stress != null;
}

class _Editor extends StatefulWidget {
  final JournalEntry entry;
  final VoidCallback onDone;
  const _Editor({required this.entry, required this.onDone});

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  int? _mood;
  int? _energy;
  int? _stress;
  late Set<String> _tags;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.entry.title ?? '');
    _body = TextEditingController(text: widget.entry.body);
    _mood = widget.entry.mood;
    _energy = widget.entry.energy;
    _stress = widget.entry.stress;
    _tags = widget.entry.tags.toSet();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_body.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Write something first.')));
      return;
    }
    setState(() => _saving = true);
    final saved = await context.read<JournalProvider>().save(widget.entry
        .copyWith(
          title: () => _title.text.trim().isEmpty
              ? null
              : _title.text.trim(),
          body: _body.text.trim(),
          mood: () => _mood,
          energy: () => _energy,
          stress: () => _stress,
          tags: _tags.toList(),
        ));
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved != null) {
      widget.onDone();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved ✓')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.read<JournalProvider>().error ??
              'Could not save.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _title,
          maxLength: 120,
          decoration:
              const InputDecoration(labelText: 'Title (optional)'),
        ),
        TextField(
          controller: _body,
          maxLines: 8,
          maxLength: 10000,
          decoration: const InputDecoration(labelText: 'Body'),
        ),
        const SizedBox(height: 8),
        _OptionalScale(
            label: 'Mood',
            value: _mood,
            onPick: (v) => setState(
                () => _mood = _mood == v ? null : v)),
        _OptionalScale(
            label: 'Energy',
            value: _energy,
            onPick: (v) => setState(
                () => _energy = _energy == v ? null : v)),
        _OptionalScale(
            label: 'Stress (1 calm … 5 high)',
            value: _stress,
            onPick: (v) => setState(
                () => _stress = _stress == v ? null : v)),
        const SizedBox(height: 8),
        Text('Tags', style: theme.textTheme.titleSmall),
        Wrap(
          spacing: 8,
          children: [
            for (final t in journalTags)
              FilterChip(
                label: Text(t),
                selected: _tags.contains(t),
                onSelected: (sel) => setState(() {
                  if (sel) {
                    _tags.add(t);
                  } else {
                    _tags.remove(t);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.onDone,
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _OptionalScale extends StatelessWidget {
  final String label;
  final int? value;
  final ValueChanged<int> onPick;
  const _OptionalScale(
      {required this.label, required this.value, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleSmall),
        Wrap(
          spacing: 8,
          children: [
            for (var i = 1; i <= 5; i++)
              ChoiceChip(
                label: Text('$i'),
                selected: value == i,
                onSelected: (_) => onPick(i),
              ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
