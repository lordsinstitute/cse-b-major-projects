import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/providers/profile_provider.dart';
import '../../app/providers/settings_provider.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/user_profile.dart';

/// /settings/profile — everything optional, editable any time.
/// Skipping setup leaves a fully functional app (never a blocking wizard).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  bool _seeded = false;
  bool _saving = false;

  String? _ageRange;
  String? _wake;
  String? _sleep;
  String? _reminder;
  int _water = 8;
  int _exercise = 150;
  int _meditation = 10;
  double _sleepGoal = 7.5;
  WellnessFocus _primary = WellnessFocus.general;
  WellnessFocus? _secondary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProfileProvider>().load();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    super.dispose();
  }

  void _seed(UserProfile p) {
    _name.text = p.displayName ?? '';
    _age.text = p.exactAge?.toString() ?? '';
    _ageRange = p.ageRange;
    _wake = p.wakeTime;
    _sleep = p.sleepTime;
    _reminder = p.reminderTime;
    _water = p.waterGoal;
    _exercise = p.exerciseGoalWeek;
    _meditation = p.meditationGoal;
    _sleepGoal = p.sleepGoal;
    _primary = p.primaryFocus;
    _secondary = p.secondaryFocus;
  }

  Future<void> _pickTime(String kind) async {
    final initial = _parse(kind == 'wake'
        ? _wake
        : kind == 'sleep'
            ? _sleep
            : _reminder);
    final picked = await showTimePicker(
        context: context,
        initialTime: initial ?? const TimeOfDay(hour: 7, minute: 0));
    if (picked == null) return;
    setState(() {
      final v =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      if (kind == 'wake') {
        _wake = v;
      } else if (kind == 'sleep') {
        _sleep = v;
      } else {
        _reminder = v;
      }
    });
  }

  static TimeOfDay? _parse(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  Future<void> _save() async {
    final prov = context.read<ProfileProvider>();
    final base = prov.profile;
    setState(() => _saving = true);
    final parsedAge = int.tryParse(_age.text.trim());
    final next = (base ?? UserProfile.fresh()).copyWith(
      displayName: () =>
          _name.text.trim().isEmpty ? null : _name.text.trim(),
      ageRange: () => _ageRange,
      exactAge: () => parsedAge,
      wakeTime: () => _wake,
      sleepTime: () => _sleep,
      reminderTime: () => _reminder,
      sleepGoal: _sleepGoal,
      waterGoal: _water,
      exerciseGoalWeek: _exercise,
      meditationGoal: _meditation,
      primaryFocus: _primary,
      secondaryFocus: () => _secondary,
    );
    final ok = await prov.save(next);
    // Keep the single scheduler source in sync (settings owns reminders).
    if (ok && _reminder != null && mounted) {
      final settings = context.read<SettingsProvider>();
      await settings.update(settings.settings
          .copyWith(dailyReminderTime: _reminder));
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Profile saved ✓'
            : (prov.error ?? 'Could not save.'))));
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ProfileProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (prov.profile != null && !_seeded) {
      _seed(prov.profile!);
      _seeded = true;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile & goals')),
      body: prov.loading && prov.profile == null
          ? const AppLoading(message: 'Loading profile…')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Optional personal context — used only to personalize suggestions and goal order on this device.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('About you (all optional)',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _name,
                        maxLength: 60,
                        decoration: const InputDecoration(
                            labelText: 'Display name'),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _ageRange,
                        decoration: const InputDecoration(
                            labelText: 'Age range (optional)'),
                        items: [
                          const DropdownMenuItem<String>(
                              value: null, child: Text('Not set')),
                          for (final r in ageRangeOptions)
                            DropdownMenuItem(
                                value: r, child: Text(r)),
                        ],
                        onChanged: (v) =>
                            setState(() => _ageRange = v),
                      ),
                      TextField(
                        controller: _age,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Exact age (optional)',
                            hintText: 'Leave blank if you prefer'),
                      ),
                      const SizedBox(height: 8),
                      _TimeRow(
                          label: 'Wake time',
                          value: _wake,
                          onPick: () => _pickTime('wake'),
                          onClear: () =>
                              setState(() => _wake = null)),
                      _TimeRow(
                          label: 'Sleep time',
                          value: _sleep,
                          onPick: () => _pickTime('sleep'),
                          onClear: () =>
                              setState(() => _sleep = null)),
                      _TimeRow(
                          label: 'Preferred reminder time',
                          value: _reminder,
                          onPick: () => _pickTime('reminder'),
                          onClear: () =>
                              setState(() => _reminder = null)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Primary wellness focus',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final f in WellnessFocus.values)
                            ChoiceChip(
                              label: Text(f.label),
                              selected: _primary == f,
                              onSelected: (_) =>
                                  setState(() => _primary = f),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Secondary focus (optional)',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('None'),
                            selected: _secondary == null,
                            onSelected: (_) =>
                                setState(() => _secondary = null),
                          ),
                          for (final f in WellnessFocus.values)
                            if (f != _primary)
                              ChoiceChip(
                                label: Text(f.label),
                                selected: _secondary == f,
                                onSelected: (_) =>
                                    setState(() => _secondary = f),
                              ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Personal targets (editable any time)',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      _GoalSlider(
                        label: 'Sleep',
                        display:
                            '${(_sleepGoal).toStringAsFixed(1)}h / night',
                        value: _sleepGoal,
                        min: 4,
                        max: 10,
                        divisions: 12,
                        onChanged: (v) => setState(
                            () => _sleepGoal = v),
                      ),
                      _GoalSlider(
                        label: 'Exercise',
                        display: '$_exercise min / week',
                        value: _exercise.toDouble(),
                        min: 10,
                        max: 600,
                        divisions: 59,
                        onChanged: (v) => setState(
                            () => _exercise = v.round()),
                      ),
                      _GoalSlider(
                        label: 'Water',
                        display: '$_water glasses / day',
                        value: _water.toDouble(),
                        min: 1,
                        max: 20,
                        divisions: 19,
                        onChanged: (v) =>
                            setState(() => _water = v.round()),
                      ),
                      _GoalSlider(
                        label: 'Meditation',
                        display: '$_meditation min / day',
                        value: _meditation.toDouble(),
                        min: 0,
                        max: 120,
                        divisions: 24,
                        onChanged: (v) => setState(
                            () => _meditation = v.round()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save profile'),
                ),
                if (prov.error != null) ...[
                  const SizedBox(height: 8),
                  Text(prov.error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.error)),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onPick;
  final VoidCallback onClear;
  const _TimeRow(
      {required this.label,
      required this.value,
      required this.onPick,
      required this.onClear});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
            child: Text(
                value == null ? '$label: not set' : '$label: $value',
                style: theme.textTheme.bodyMedium)),
        TextButton(onPressed: onPick, child: const Text('Set')),
        if (value != null)
          TextButton(onPressed: onClear, child: const Text('Clear')),
      ],
    );
  }
}

class _GoalSlider extends StatelessWidget {
  final String label;
  final String display;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  const _GoalSlider({
    required this.label,
    required this.display,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $display',
            style: theme.textTheme.titleSmall),
        Slider(
          min: min,
          max: max,
          divisions: divisions,
          value: value.clamp(min, max),
          label: display,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
