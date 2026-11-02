import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/providers/journal_provider.dart';
import '../../app/providers/settings_provider.dart';
import '../../core/utils/utils.dart';
import '../../app/theme/design_system.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/journal.dart';

/// Lock gate: when the journal privacy lock is on and this session is
/// locked, a PIN pad guards the child. Nothing behind it builds unlocked.
class JournalGate extends StatefulWidget {
  final Widget child;
  const JournalGate({super.key, required this.child});

  @override
  State<JournalGate> createState() => _JournalGateState();
}

class _JournalGateState extends State<JournalGate> {
  String _pin = '';
  bool _wrong = false;

  void _press(String d) {
    final settings = context.read<SettingsProvider>();
    final next = (_pin + d).length > 4 ? _pin : _pin + d;
    setState(() {
      _pin = next;
      _wrong = false;
    });
    if (next.length == 4) {
      final ok = settings.unlockJournal(next);
      setState(() {
        _wrong = !ok;
        if (!ok) _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    if (!settings.settings.appLockEnabled || settings.journalUnlocked) {
      return widget.child;
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Journal is locked', style: theme.textTheme.titleLarge),
          Text(
            'Enter your 4-digit PIN on this device.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 4; i++)
                Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
            ],
          ),
          if (_wrong) ...[
            const SizedBox(height: 8),
            Text(
              'Wrong PIN. Try again.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          for (final row in [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['', '0', '⌫'],
          ])
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final d in row)
                  SizedBox(
                    width: 72,
                    height: 64,
                    child: d.isEmpty
                        ? const SizedBox.shrink()
                        : TextButton(
                            onPressed: () => d == '⌫'
                                ? setState(
                                    () => _pin = _pin.isEmpty
                                        ? ''
                                        : _pin.substring(0, _pin.length - 1),
                                  )
                                : _press(d),
                            child: Text(
                              d,
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// /home/journal — chronological private timeline with local search,
/// tag chips, mood filter, and a fast "quick note" composer.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final _search = TextEditingController();
  final _quick = TextEditingController();
  bool _composing = false;
  bool _savingQuick = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<JournalProvider>().load();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _quick.dispose();
    super.dispose();
  }

  Future<void> _saveQuick() async {
    final text = _quick.text.trim();
    if (text.isEmpty) return;
    setState(() => _savingQuick = true);
    final now = DateTime.now();
    final saved = await context.read<JournalProvider>().save(
      JournalEntry(
        id: generateId(),
        date: JournalProvider.todayKey(),
        body: text,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (!mounted) return;
    setState(() {
      _savingQuick = false;
      if (saved != null) {
        _quick.clear();
        _composing = false;
        HapticFeedback.lightImpact();
      }
    });
    if (saved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<JournalProvider>().error ?? 'Could not save.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final journal = context.watch<JournalProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Journal')),
      body: JournalGate(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        hintText: 'Search title, body, tags…',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: journal.setQuery,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () => setState(() => _composing = !_composing),
                    child: const Text('Quick note'),
                  ),
                ],
              ),
              if (_composing) ...[
                const SizedBox(height: 8),
                AppCard(
                  child: Column(
                    children: [
                      TextField(
                        controller: _quick,
                        autofocus: true,
                        maxLines: 3,
                        maxLength: 1000,
                        decoration: const InputDecoration(
                          hintText: 'A short note — no metadata required…',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => setState(() {
                              _composing = false;
                              _quick.clear();
                            }),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: _savingQuick ? null : _saveQuick,
                            child: Text(_savingQuick ? 'Saving…' : 'Save note'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final t in journalTags)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(t),
                          selected: journal.tagFilters.contains(t),
                          onSelected: (_) => journal.toggleTag(t),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Text('Mood: '),
                    ChoiceChip(
                      label: const Text('Any'),
                      selected: journal.moodFilter == null,
                      onSelected: (_) => journal.setMoodFilter(null),
                      visualDensity: VisualDensity.compact,
                    ),
                    for (var m = 1; m <= 5; m++)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: ChoiceChip(
                          label: Text('$m'),
                          selected: journal.moodFilter == m,
                          onSelected: (_) => journal.setMoodFilter(
                            journal.moodFilter == m ? null : m,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: journal.loading
                    ? const AppLoading(message: 'Opening journal…')
                    : journal.entries.isEmpty
                    ? AppEmptyState(
                        icon: Icons.book_outlined,
                        title: journal.all.isEmpty
                            ? 'Empty journal'
                            : 'No matches',
                        subtitle: journal.all.isEmpty
                            ? 'Write a quick note to begin — it stays on this device.'
                            : 'Try a different search or clear the filters.',
                        actionLabel: journal.all.isEmpty
                            ? 'Write a quick note'
                            : null,
                        onAction: journal.all.isEmpty
                            ? () => setState(() => _composing = true)
                            : null,
                      )
                    : ListView.separated(
                        itemCount: journal.entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (c, i) =>
                            _EntryRow(entry: journal.entries[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final JournalEntry entry;
  const _EntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      onTap: () => context.push('/home/journal/${entry.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (entry.title == null || entry.title!.isEmpty)
                      ? _fmtDate(entry.date)
                      : entry.title!,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (entry.mood != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: DS
                        .metric(theme.brightness, MetricDomain.mood)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(DS.rPill),
                  ),
                  child: Text(
                    'Mood ${entry.mood}/5',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: DS.metric(theme.brightness, MetricDomain.mood),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            entry.body,
            style: theme.textTheme.bodyMedium,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (entry.tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final t in entry.tags)
                  Chip(label: Text(t), visualDensity: VisualDensity.compact),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${_fmtDate(entry.date)}${entry.isQuickNote ? ' · quick note' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDate(String key) {
    final d = DateTime.tryParse(key);
    if (d == null) return key;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
