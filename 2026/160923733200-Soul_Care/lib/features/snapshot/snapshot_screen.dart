import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/providers/health_snapshot_provider.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/pin_gate.dart';
import '../../data/models/health_snapshot.dart';

/// /home/snapshot — manually maintained personal health record.
/// Informational only: never diagnosis, never treatment advice.
/// Sensitive: lock-gated when the app lock is on, never logged/uploaded.
class SnapshotScreen extends StatefulWidget {
  const SnapshotScreen({super.key});

  @override
  State<SnapshotScreen> createState() => _SnapshotScreenState();
}

class _SnapshotScreenState extends State<SnapshotScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HealthSnapshotProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<HealthSnapshotProvider>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Health Snapshot')),
      body: PinGate(
        title: 'Snapshot is locked',
        subtitle:
            'Enter your 4-digit PIN on this device to view sensitive health details.',
        child: prov.loading && prov.snapshot == null
            ? const AppLoading(message: 'Loading snapshot…')
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AppCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.privacy_tip_outlined,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Sensitive personal data. Stored only on this device — never sent, logged, or analyzed automatically.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(
                                    color: theme.colorScheme
                                        .onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _QuickView(onEdit: _editSheet),
                  const SizedBox(height: 12),
                  _MedicationList(onEdit: _editSheet),
                  const SizedBox(height: 12),
                  _AllergyList(onEdit: _editSheet),
                  const SizedBox(height: 12),
                  _DetailsCard(onEdit: _editSheet),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: _editSheet,
                          child: const Text('Edit snapshot'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _clearConfirm(context),
                          child: Text('Clear all',
                              style: TextStyle(
                                  color: theme.colorScheme.error)),
                        ),
                      ),
                    ],
                  ),
                  if (prov.error != null) ...[
                    const SizedBox(height: 8),
                    Text(prov.error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(
                                color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Future<void> _editSheet() async {
    final prov = context.read<HealthSnapshotProvider>();
    final current = prov.snapshot ?? HealthSnapshot.empty();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SnapshotEditor(initial: current),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved ✓')));
    }
  }

  Future<void> _clearConfirm(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear snapshot?'),
        content: const Text(
            'Every recorded detail will be permanently removed from this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    final ok =
        await context.read<HealthSnapshotProvider>().clear();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Snapshot cleared.'
            : (context.read<HealthSnapshotProvider>().error ??
                'Could not clear.'))));
  }
}

/// Concise quick view (blood group, allergies, active meds, contact).
class _QuickView extends StatelessWidget {
  final VoidCallback onEdit;
  const _QuickView({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<HealthSnapshotProvider>();
    final snap = prov.snapshot;
    final theme = Theme.of(context);
    if (snap == null || snap.isEmpty) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Health Snapshot',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Nothing recorded yet — add what matters to you.',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            FilledButton.tonal(
                onPressed: onEdit,
                child: const Text('Add details')),
          ],
        ),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Health Snapshot',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _kv(context, 'Blood Group', snap.bloodGroup ?? '—'),
          _kv(
              context,
              'Allergies',
              snap.allergies.isEmpty
                  ? 'None recorded'
                  : snap.allergies.map((a) => a.name).join(', ')),
          _kv(context, 'Medications',
              '${snap.activeMedications} active'),
          _kv(context, 'Emergency Contact',
              snap.hasEmergencyContact ? 'Available' : '—'),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Flexible(
            child: Text(value,
                style: theme.textTheme.titleSmall,
                textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _MedicationList extends StatelessWidget {
  final VoidCallback onEdit;
  const _MedicationList({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final meds =
        context.watch<HealthSnapshotProvider>().snapshot?.medications ??
            const [];
    final theme = Theme.of(context);
    if (meds.isEmpty) return const SizedBox.shrink();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Medications',
                  style: theme.textTheme.titleSmall),
              TextButton(
                  onPressed: onEdit, child: const Text('Edit')),
            ],
          ),
          for (final m in meds)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${m.name}${m.dosage.isNotEmpty ? ' · ${m.dosage}' : ''}${m.frequency.isNotEmpty ? ' · ${m.frequency}' : ''}${m.isActive ? '' : ' (ended)'}',
                      style: theme.textTheme.bodyMedium),
                  if (m.notes != null && m.notes!.isNotEmpty)
                    Text(m.notes!,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme
                                .onSurfaceVariant)),
                ],
              ),
            ),
          Text(
            'Record only — never a recommendation or treatment advice.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _AllergyList extends StatelessWidget {
  final VoidCallback onEdit;
  const _AllergyList({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final items =
        context.watch<HealthSnapshotProvider>().snapshot?.allergies ??
            const [];
    final theme = Theme.of(context);
    if (items.isEmpty) return const SizedBox.shrink();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Allergies',
                  style: theme.textTheme.titleSmall),
              TextButton(
                  onPressed: onEdit, child: const Text('Edit')),
            ],
          ),
          for (final a in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('${a.name} · ${a.severity}',
                  style: theme.textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  final VoidCallback onEdit;
  const _DetailsCard({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final snap = context.watch<HealthSnapshotProvider>().snapshot;
    final theme = Theme.of(context);
    if (snap == null) return const SizedBox.shrink();
    final rows = <(String, String)>[
      if (snap.supplements.isNotEmpty)
        ('Supplements', snap.supplements.join(', ')),
      if (snap.conditions.isNotEmpty)
        ('Conditions', snap.conditions.join(', ')),
      if (snap.emergencyName != null ||
          snap.emergencyPhone != null)
        (
          'Emergency',
          [
            if (snap.emergencyName != null) snap.emergencyName!,
            if (snap.emergencyPhone != null) snap.emergencyPhone!,
          ].join(' · ')
        ),
      if (snap.provider != null && snap.provider!.isNotEmpty)
        ('Provider', snap.provider!),
      if (snap.notes != null && snap.notes!.isNotEmpty)
        ('Notes', snap.notes!),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Details',
                  style: theme.textTheme.titleSmall),
              TextButton(
                  onPressed: onEdit, child: const Text('Edit')),
            ],
          ),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.$1, style: theme.textTheme.labelMedium),
                  Text(r.$2, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SnapshotEditor extends StatefulWidget {
  final HealthSnapshot initial;
  const _SnapshotEditor({required this.initial});

  @override
  State<_SnapshotEditor> createState() => _SnapshotEditorState();
}

class _SnapshotEditorState extends State<_SnapshotEditor> {
  late final TextEditingController _supplements;
  late final TextEditingController _conditions;
  late final TextEditingController _emName;
  late final TextEditingController _emPhone;
  late final TextEditingController _provider;
  late final TextEditingController _notes;
  String? _blood;
  late List<AllergyRecord> _allergies;
  late List<MedicationRecord> _meds;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _supplements =
        TextEditingController(text: i.supplements.join(', '));
    _conditions =
        TextEditingController(text: i.conditions.join(', '));
    _emName = TextEditingController(text: i.emergencyName ?? '');
    _emPhone =
        TextEditingController(text: i.emergencyPhone ?? '');
    _provider = TextEditingController(text: i.provider ?? '');
    _notes = TextEditingController(text: i.notes ?? '');
    _blood = i.bloodGroup;
    _allergies = [...i.allergies];
    _meds = [...i.medications];
  }

  @override
  void dispose() {
    _supplements.dispose();
    _conditions.dispose();
    _emName.dispose();
    _emPhone.dispose();
    _provider.dispose();
    _notes.dispose();
    super.dispose();
  }

  static List<String> _split(String raw) => raw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> _save() async {
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final ok = await context.read<HealthSnapshotProvider>().save(
          widget.initial.copyWith(
            bloodGroup: () => _blood,
            allergies: _allergies,
            medications: _meds,
            supplements: _split(_supplements.text),
            conditions: _split(_conditions.text),
            emergencyName: () =>
                _emName.text.trim().isEmpty ? null : _emName.text.trim(),
            emergencyPhone: () => _emPhone.text.trim().isEmpty
                ? null
                : _emPhone.text.trim(),
            provider: () => _provider.text.trim().isEmpty
                ? null
                : _provider.text.trim(),
            notes: () => _notes.text.trim().isEmpty
                ? null
                : _notes.text.trim(),
          ),
        );
    if (!mounted) return;
    navigator.pop(ok);
  }

  Future<void> _addAllergy() async {
    final name = TextEditingController();
    String severity = 'Mild';
    final res = await showDialog<AllergyRecord>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Add allergy'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: name,
                  autofocus: true,
                  decoration:
                      const InputDecoration(labelText: 'Allergy')),
              DropdownButtonFormField<String>(
                initialValue: severity,
                decoration:
                    const InputDecoration(labelText: 'Severity'),
                items: [
                  for (final s in allergySeverities)
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (v) =>
                    setD(() => severity = v ?? severity),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(c).pop(),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(c).pop(AllergyRecord(
                    name: name.text.trim(), severity: severity)),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    name.dispose();
    if (res != null && res.name.isNotEmpty) {
      setState(() => _allergies.add(res));
    }
  }

  Future<void> _addMedication() async {
    final name = TextEditingController();
    final dosage = TextEditingController();
    final freq = TextEditingController();
    final res = await showDialog<MedicationRecord>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add medication'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Name (record only)')),
              TextField(
                  controller: dosage,
                  decoration: const InputDecoration(
                      labelText: 'Dosage (optional)')),
              TextField(
                  controller: freq,
                  decoration: const InputDecoration(
                      labelText: 'Frequency (optional)')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(c).pop(MedicationRecord(
                    name: name.text.trim(),
                    dosage: dosage.text.trim(),
                    frequency: freq.text.trim(),
                  )),
              child: const Text('Add')),
        ],
      ),
    );
    name.dispose();
    dosage.dispose();
    freq.dispose();
    if (res != null && res.name.isNotEmpty) {
      setState(() => _meds.add(res));
    }
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
            Text('Edit snapshot',
                style: theme.textTheme.titleLarge),
            Text('Everything optional. Record only — never advice.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _blood,
              decoration:
                  const InputDecoration(labelText: 'Blood group'),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('Not set')),
                for (final b in bloodGroups)
                  DropdownMenuItem(value: b, child: Text(b)),
              ],
              onChanged: (v) => setState(() => _blood = v),
            ),
            const SizedBox(height: 8),
            _ListEditor(
              title: 'Allergies',
              items: [
                for (var i = 0; i < _allergies.length; i++)
                  '${_allergies[i].name} · ${_allergies[i].severity}'
              ],
              onAdd: _addAllergy,
              onRemove: (i) =>
                  setState(() => _allergies.removeAt(i)),
            ),
            _ListEditor(
              title: 'Medications',
              items: [
                for (var i = 0; i < _meds.length; i++)
                  _meds[i].name
              ],
              onAdd: _addMedication,
              onRemove: (i) =>
                  setState(() => _meds.removeAt(i)),
            ),
            TextField(
              controller: _supplements,
              decoration: const InputDecoration(
                  labelText: 'Supplements (comma separated)'),
            ),
            TextField(
              controller: _conditions,
              decoration: const InputDecoration(
                  labelText: 'Conditions you record (comma separated)'),
            ),
            TextField(
              controller: _emName,
              decoration: const InputDecoration(
                  labelText: 'Emergency contact name'),
            ),
            TextField(
              controller: _emPhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Emergency contact phone'),
            ),
            TextField(
              controller: _provider,
              decoration: const InputDecoration(
                  labelText: 'Primary healthcare provider'),
            ),
            TextField(
              controller: _notes,
              maxLines: 3,
              maxLength: 2000,
              decoration: const InputDecoration(
                  labelText: 'Important notes'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save snapshot'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListEditor extends StatelessWidget {
  final String title;
  final List<String> items;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  const _ListEditor(
      {required this.title,
      required this.items,
      required this.onAdd,
      required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        if (items.isEmpty)
          Text('None recorded.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
        for (var i = 0; i < items.length; i++)
          Chip(
            label: Text(items[i]),
            deleteIcon: const Icon(Icons.close, size: 16),
            onDeleted: () => onRemove(i),
            visualDensity: VisualDensity.compact,
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}
