import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/providers/checkin_providers.dart';
import '../../app/theme/design_system.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/checkins.dart';

/// 20–30 second morning flow: sleep, rested, mood, energy, one optional
/// intention. Nothing is forced; everything has a default.
class MorningScreen extends StatefulWidget {
  const MorningScreen({super.key});

  @override
  State<MorningScreen> createState() => _MorningScreenState();
}

class _MorningScreenState extends State<MorningScreen> {
  double _sleep = 7;
  int _rested = 4;
  int _mood = 4;
  int _energy = 4;
  String? _intention;
  final _custom = TextEditingController();
  bool _seeded = false;
  bool _saving = false;
  bool _saved = false;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _seed(MorningCheckIn c) {
    _sleep = c.sleepHours > 0 ? c.sleepHours : 7;
    _rested = c.rested;
    _mood = c.mood;
    _energy = c.energy;
    _intention = c.intention != null && !intentionOptions.contains(c.intention)
        ? 'Custom'
        : c.intention;
    if (_intention == 'Custom') _custom.text = c.intention ?? '';
  }

  Future<void> _save() async {
    final prov = context.read<MorningProvider>();
    setState(() => _saving = true);
    final custom = _custom.text.trim();
    final ok = await prov.save(
      MorningCheckIn(
        date: prov.todayKey,
        sleepHours: _sleep,
        rested: _rested,
        mood: _mood,
        energy: _energy,
        intention: _intention == null
            ? null
            : _intention == 'Custom'
            ? (custom.isEmpty ? null : custom)
            : _intention,
        updatedAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = ok;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(prov.error ?? 'Could not save. Please try again.'),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MorningProvider>().loadToday();
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<MorningProvider>();
    if (prov.today != null && !_seeded) {
      _seed(prov.today!);
      _seeded = true;
      _saved = true;
    }
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Morning check-in')),
      body: prov.loading && prov.today == null
          ? const AppLoading(message: 'Loading…')
          : _saved && prov.today != null
          ? _Summary(
              checkIn: prov.today!,
              onToday: () => context.go('/today'),
              onEdit: () => setState(() => _saved = false),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                DS.xl,
                DS.l,
                DS.xl,
                DS.massive,
              ),
              children: [
                Text(
                  'Good morning',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'About 30 seconds — nothing is required.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: DS.textSecondary(theme.brightness),
                  ),
                ),
                const SizedBox(height: DS.l),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sleep: ${formatHours(_sleep)}',
                        style: theme.textTheme.titleSmall,
                      ),
                      Slider(
                        min: 0,
                        max: 12,
                        divisions: 24,
                        value: _sleep,
                        label: formatHours(_sleep),
                        onChanged: (v) => setState(() => _sleep = v),
                      ),
                      Text(
                        'How rested do you feel?',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      _ScaleRow(
                        value: _rested,
                        onPick: (v) => setState(() => _rested = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mood', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      _ScaleRow(
                        value: _mood,
                        onPick: (v) => setState(() => _mood = v),
                      ),
                      const SizedBox(height: 8),
                      Text('Energy', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      _ScaleRow(
                        value: _energy,
                        onPick: (v) => setState(() => _energy = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Today's intention (optional)",
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('None'),
                            selected: _intention == null,
                            onSelected: (_) =>
                                setState(() => _intention = null),
                          ),
                          for (final o in intentionOptions)
                            ChoiceChip(
                              label: Text(o),
                              selected: _intention == o,
                              onSelected: (_) => setState(() => _intention = o),
                            ),
                          ChoiceChip(
                            label: const Text('Custom'),
                            selected: _intention == 'Custom',
                            onSelected: (_) =>
                                setState(() => _intention = 'Custom'),
                          ),
                        ],
                      ),
                      if (_intention == 'Custom') ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _custom,
                          maxLength: 80,
                          decoration: const InputDecoration(
                            labelText: 'Your intention',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save check-in'),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _ScaleRow extends StatelessWidget {
  final int value;
  final ValueChanged<int> onPick;
  const _ScaleRow({required this.value, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduce = DS.reduceMotion(context);
    return Wrap(
      spacing: 8,
      children: [
        for (var i = 1; i <= 5; i++)
          AnimatedScale(
            scale: value == i ? 1.06 : 1.0,
            duration: reduce ? Duration.zero : const Duration(milliseconds: 160),
            curve: DS.curveEntrance,
            child: ChoiceChip(
              label: Text('$i', style: const TextStyle(fontSize: 16)),
              selected: value == i,
              onSelected: (_) => onPick(i),
            ),
          ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  final MorningCheckIn checkIn;
  final VoidCallback onToday;
  final VoidCallback onEdit;
  const _Summary({
    required this.checkIn,
    required this.onToday,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Good morning.', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              _summaryRow('Sleep', formatHours(checkIn.sleepHours)),
              _summaryRow('Energy', '${checkIn.energy}/5'),
              _summaryRow('Mood', '${checkIn.mood}/5'),
              const SizedBox(height: 8),
              Text("Today's focus:", style: theme.textTheme.titleSmall),
              Text(
                checkIn.intention ?? '— just be consistent',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onToday,
                child: const Text("Go to today's health screen"),
              ),
              TextButton(onPressed: onEdit, child: const Text('Edit check-in')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              Text(value, style: theme.textTheme.titleSmall),
            ],
          ),
        );
      },
    );
  }
}
