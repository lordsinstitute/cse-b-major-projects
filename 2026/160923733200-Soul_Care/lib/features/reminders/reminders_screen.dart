import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/providers/reminders_provider.dart';
import '../../core/utils/utils.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/pin_gate.dart';
import '../../data/models/reminders.dart';

/// /home/care — medication reminders, appointments, upcoming view,
/// neutral history. Everything local, user-controlled.
class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _Tabs();
  }
}

class _Tabs extends StatefulWidget {
  const _Tabs();

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RemindersProvider>().load();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders & appointments'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Medications'),
            Tab(text: 'Appointments'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: PinGate(
        screen: 'reminders',
        title: 'Reminders are locked',
        subtitle: 'Unlock to view medication and appointment details.',
        child: TabBarView(
          controller: _tabs,
          children: const [
            _UpcomingTab(),
            _MedicationsTab(),
            _AppointmentsTab(),
            _HistoryTab(),
          ],
        ),
      ),
    );
  }
}

String _fmtDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _fmtTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _UpcomingTab extends StatelessWidget {
  const _UpcomingTab();

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RemindersProvider>();
    final theme = Theme.of(context);
    if (prov.loading) {
      return const AppLoading(message: 'Loading schedule…');
    }
    final items = prov.upcoming();
    if (items.isEmpty) {
      return const AppEmptyState(
        icon: Icons.event_available_outlined,
        title: 'Nothing scheduled',
        subtitle:
            'Add a medication reminder or appointment to see it here.',
      );
    }
    String? lastDay;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (c, i) {
        final it = items[i];
        final day = _fmtDay(it.at);
        final header = day != lastDay;
        lastDay = day;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header) ...[
              if (i > 0) const SizedBox(height: 12),
              Text(day, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
            ],
            AppCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                      it.isAppointment
                          ? Icons.event_outlined
                          : Icons.medication_outlined,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(it.title,
                            style: theme.textTheme.titleSmall),
                        Text('${_fmtTime(it.at)} · ${it.subtitle}',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _MedicationsTab extends StatelessWidget {
  const _MedicationsTab();

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RemindersProvider>();
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editReminder(context, null),
        child: const Icon(Icons.add),
      ),
      body: prov.loading
          ? const AppLoading()
          : prov.reminders.isEmpty
              ? const AppEmptyState(
                  icon: Icons.medication_outlined,
                  title: 'No medication reminders',
                  subtitle:
                      'Set times that suit you — daily, twice daily, or chosen weekdays.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: prov.reminders.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: 8),
                  itemBuilder: (c, i) {
                    final r = prov.reminders[i];
                    return AppCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(r.medicationName,
                                    style: theme
                                        .textTheme.titleSmall),
                                Text(
                                  '${r.times.join(', ')} · ${r.frequency}${r.enabled ? '' : ' · paused'}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: r.enabled,
                            onChanged: (v) => prov.saveReminder(
                                r.copyWith(enabled: v)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () =>
                                _editReminder(context, r),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                color: theme.colorScheme.error),
                            onPressed: () =>
                                _deleteReminder(context, r),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _editReminder(
      BuildContext context, MedicationReminder? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReminderEditor(existing: existing),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved ✓')));
    }
  }

  Future<void> _deleteReminder(
      BuildContext context, MedicationReminder r) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete reminder?'),
        content: Text(
            '"${r.medicationName}" and its scheduled alerts will be removed. Logged history stays.'),
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
    await context.read<RemindersProvider>().removeReminder(r.id);
  }
}

class _AppointmentsTab extends StatelessWidget {
  const _AppointmentsTab();

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RemindersProvider>();
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editAppointment(context, null),
        child: const Icon(Icons.add),
      ),
      body: prov.loading
          ? const AppLoading()
          : prov.appointments.isEmpty
              ? const AppEmptyState(
                  icon: Icons.event_outlined,
                  title: 'No appointments',
                  subtitle:
                      'Add checkups or visits with optional advance reminders.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: prov.appointments.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: 8),
                  itemBuilder: (c, i) {
                    final a = prov.appointments[i];
                    final past = !a.dateTime
                        .isAfter(DateTime.now());
                    return AppCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(a.title,
                                    style: theme
                                        .textTheme.titleSmall),
                                Text(
                                  '${_fmtDay(a.dateTime)} ${_fmtTime(a.dateTime)}'
                                  '${a.location.isNotEmpty ? ' · ${a.location}' : ''}'
                                  '${a.provider.isNotEmpty ? ' · ${a.provider}' : ''}'
                                  '${past ? ' · past' : ''}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: a.enabled,
                            onChanged: (v) => prov.saveAppointment(
                                a.copyWith(enabled: v)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () =>
                                _editAppointment(context, a),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                color: theme.colorScheme.error),
                            onPressed: () =>
                                _deleteAppointment(context, a),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _editAppointment(
      BuildContext context, Appointment? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AppointmentEditor(existing: existing),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved ✓')));
    }
  }

  Future<void> _deleteAppointment(
      BuildContext context, Appointment a) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete appointment?'),
        content: Text('"${a.title}" will be removed.'),
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
    await context.read<RemindersProvider>().removeAppointment(a.id);
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RemindersProvider>();
    final theme = Theme.of(context);
    final items = prov.recentHistory();
    if (prov.loading) return const AppLoading();
    if (items.isEmpty) {
      return const AppEmptyState(
        icon: Icons.history_outlined,
        title: 'No dose history yet',
        subtitle:
            'Taken, skipped, or unrecorded doses from the last 7 days appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (c, i) {
        final h = items[i];
        final o = h.occurrence;
        final logged = h.action != null;
        return AppCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                  h.action == DoseAction.taken
                      ? Icons.check_circle_outline
                      : h.action == DoseAction.skipped
                          ? Icons.remove_circle_outline
                          : Icons.radio_button_unchecked,
                  color: logged
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.medicationName,
                        style: theme.textTheme.titleSmall),
                    Text('${o.dateKey} ${o.timeKey} · ${h.statusLabel}',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (!logged)
                TextButton(
                  onPressed: () => context
                      .read<RemindersProvider>()
                      .logDose(o.reminderId, o.dateKey,
                          o.timeKey, DoseAction.taken),
                  child: const Text('Taken'),
                ),
              if (!logged)
                TextButton(
                  onPressed: () => context
                      .read<RemindersProvider>()
                      .logDose(o.reminderId, o.dateKey,
                          o.timeKey, DoseAction.skipped),
                  child: const Text('Skip'),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ReminderEditor extends StatefulWidget {
  final MedicationReminder? existing;
  const _ReminderEditor({required this.existing});

  @override
  State<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<_ReminderEditor> {
  late final TextEditingController _name;
  late List<String> _times;
  late Set<int> _days;
  DateTime? _start;
  DateTime? _end;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.medicationName ?? '');
    _times = [...(e?.times ?? ['08:00'])];
    _days = {...(e?.days ?? {})};
    _start = e?.startDate;
    _end = e?.endDate;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickTime(int index) async {
    final parts = _times[index].split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (picked == null) return;
    setState(() => _times[index] =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          (isStart ? _start : _end) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  String _fmtD(DateTime? d) => d == null
      ? 'not set'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Medication name is required.')));
      return;
    }
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final now = DateTime.now();
    final base = widget.existing ??
        MedicationReminder(
            id: generateId(), medicationName: '', createdAt: now, updatedAt: now);
    final ok = await context.read<RemindersProvider>().saveReminder(
          base.copyWith(
            medicationName: _name.text.trim(),
            times: _times,
            days: _days.toList()..sort(),
            startDate: () => _start,
            endDate: () => _end,
          ),
        );
    if (!mounted) return;
    navigator.pop(ok);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, 28 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                widget.existing == null
                    ? 'New medication reminder'
                    : 'Edit reminder',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              maxLength: 80,
              decoration: const InputDecoration(
                  labelText: 'Medication name'),
            ),
            Text('Times', style: theme.textTheme.titleSmall),
            for (var i = 0; i < _times.length; i++)
              Row(
                children: [
                  Expanded(
                      child: Text(_times[i],
                          style: theme.textTheme.titleMedium)),
                  TextButton(
                      onPressed: () => _pickTime(i),
                      child: const Text('Change')),
                  if (_times.length > 1)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () =>
                          setState(() => _times.removeAt(i)),
                    ),
                ],
              ),
            TextButton.icon(
              onPressed: _times.length >= 4
                  ? null
                  : () => setState(() => _times.add('20:00')),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add time'),
            ),
            Text('Days (none = every day)',
                style: theme.textTheme.titleSmall),
            Wrap(
              spacing: 4,
              children: [
                for (var d = 1; d <= 7; d++)
                  ChoiceChip(
                    label: Text(dayLabels[d - 1]),
                    selected: _days.contains(d),
                    onSelected: (sel) => setState(() {
                      if (sel) {
                        _days.add(d);
                      } else {
                        _days.remove(d);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: Text('From: ${_fmtD(_start)}',
                        style: theme.textTheme.bodyMedium)),
                TextButton(
                    onPressed: () => _pickDate(true),
                    child: const Text('Set')),
                if (_start != null)
                  TextButton(
                      onPressed: () =>
                          setState(() => _start = null),
                      child: const Text('Clear')),
              ],
            ),
            Row(
              children: [
                Expanded(
                    child: Text('Until: ${_fmtD(_end)}',
                        style: theme.textTheme.bodyMedium)),
                TextButton(
                    onPressed: () => _pickDate(false),
                    child: const Text('Set')),
                if (_end != null)
                  TextButton(
                      onPressed: () =>
                          setState(() => _end = null),
                      child: const Text('Clear')),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save reminder'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentEditor extends StatefulWidget {
  final Appointment? existing;
  const _AppointmentEditor({required this.existing});

  @override
  State<_AppointmentEditor> createState() => _AppointmentEditorState();
}

class _AppointmentEditorState extends State<_AppointmentEditor> {
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _provider;
  late final TextEditingController _notes;
  late DateTime _date;
  late TimeOfDay _time;
  late int _remind;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _provider = TextEditingController(text: e?.provider ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    final now = DateTime.now();
    _date = e?.date ??
        DateTime(now.year, now.month, now.day)
            .add(const Duration(days: 1));
    final parts = (e?.time ?? '09:00').split(':');
    _time = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 9,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0);
    _remind = e?.remindBeforeMin ?? 60;
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _provider.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Title is required.')));
      return;
    }
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final now = DateTime.now();
    final base = widget.existing ??
        Appointment(
            id: generateId(),
            title: '',
            date: _date,
            createdAt: now,
            updatedAt: now);
    final ok = await context.read<RemindersProvider>().saveAppointment(
          base.copyWith(
            title: _title.text.trim(),
            date: _date,
            time:
                '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
            location: _location.text.trim(),
            provider: _provider.text.trim(),
            notes: _notes.text.trim(),
            remindBeforeMin: _remind,
          ),
        );
    if (!mounted) return;
    navigator.pop(ok);
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
            Text(
                widget.existing == null
                    ? 'New appointment'
                    : 'Edit appointment',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              autofocus: widget.existing == null,
              maxLength: 120,
              decoration:
                  const InputDecoration(labelText: 'Title'),
            ),
            Row(
              children: [
                Expanded(
                    child: Text(
                        'Date: ${_fmtDay(_date)}',
                        style: theme.textTheme.bodyMedium)),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now()
                          .add(const Duration(days: 365 * 2)),
                    );
                    if (picked != null) {
                      setState(() => _date = picked);
                    }
                  },
                  child: const Text('Pick'),
                ),
                Expanded(
                    child: Text(
                        'Time: ${_time.format(context)}',
                        style: theme.textTheme.bodyMedium)),
                TextButton(
                  onPressed: () async {
                    final picked = await showTimePicker(
                        context: context, initialTime: _time);
                    if (picked != null) {
                      setState(() => _time = picked);
                    }
                  },
                  child: const Text('Pick'),
                ),
              ],
            ),
            TextField(
              controller: _location,
              decoration:
                  const InputDecoration(labelText: 'Location'),
            ),
            TextField(
              controller: _provider,
              decoration:
                  const InputDecoration(labelText: 'Provider'),
            ),
            DropdownButtonFormField<int>(
              initialValue: _remind,
              decoration: const InputDecoration(
                  labelText: 'Remind me before'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('No reminder')),
                DropdownMenuItem(value: 15, child: Text('15 minutes')),
                DropdownMenuItem(value: 30, child: Text('30 minutes')),
                DropdownMenuItem(value: 60, child: Text('1 hour')),
                DropdownMenuItem(value: 120, child: Text('2 hours')),
                DropdownMenuItem(value: 1440, child: Text('1 day')),
              ],
              onChanged: (v) =>
                  setState(() => _remind = v ?? 60),
            ),
            TextField(
              controller: _notes,
              maxLines: 2,
              maxLength: 1000,
              decoration:
                  const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save appointment'),
            ),
          ],
        ),
      ),
    );
  }
}
