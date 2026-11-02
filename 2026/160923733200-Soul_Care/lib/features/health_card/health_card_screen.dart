import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers/health_snapshot_provider.dart';
import '../../app/providers/profile_provider.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/health_snapshot.dart';
import 'health_card_engine.dart';

/// /health-card — Quick Health Card.
///
/// A personal information card (never a diagnosis system). Shows only
/// fields the user actually entered. Sharing is explicit: the user checks
/// exactly which fields go into the QR code and shared text, warned that
/// recipients can see everything selected. Fully offline.
class HealthCardScreen extends StatefulWidget {
  const HealthCardScreen({super.key});

  @override
  State<HealthCardScreen> createState() => _HealthCardScreenState();
}

class _HealthCardScreenState extends State<HealthCardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HealthSnapshotProvider>().load();
      context.read<ProfileProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapProv = context.watch<HealthSnapshotProvider>();
    final profile = context.watch<ProfileProvider>().profile;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snapshot = snapProv.snapshot;
    final name = profile?.displayName?.trim();

    final hasAnything = (name != null && name.isNotEmpty) ||
        (snapshot != null && !snapshot.isEmpty);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Card'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (snapProv.loading)
            const AppCard(child: AppLoading(message: 'Reading your card…'))
          else if (!hasAnything)
            AppCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.contact_emergency_outlined,
                      size: 48, color: scheme.primary),
                  const SizedBox(height: 12),
                  Text('No card details yet',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    'Add your name, blood group, allergies, medications and emergency contact — only what you enter ever appears here.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        context.push('/home/snapshot'),
                    child: const Text('Add health details'),
                  ),
                ],
              ),
            )
          else ...[
            _Card(
              name: name,
              snapshot: snapshot ?? HealthSnapshot.empty(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => _ShareSheet(
                    displayName: name,
                    snapshot: snapshot,
                  ),
                ),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share Health Card'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        context.push('/home/snapshot'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit details'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        context.push('/settings/profile'),
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: const Text('Edit name'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Stored only on this device. Sharing happens only through the Share button with fields you check.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// The polished digital card: strong hierarchy, clear labels, restrained
/// icons, print/share-friendly light-on-dark-safe layout.
class _Card extends StatelessWidget {
  final String? name;
  final HealthSnapshot snapshot;
  const _Card({required this.name, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meds = snapshot.medications
        .where((m) => m.name.trim().isNotEmpty && m.isActive)
        .toList();
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    initialsFor(name),
                    style: theme.textTheme.headlineSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (name == null || name!.isEmpty)
                            ? 'My Health Card'
                            : name!,
                        style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold),
                      ),
                      Text('Personal Health Card',
                          style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.primary)),
                      Text('Information only — not a diagnosis',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),
            if (snapshot.bloodGroup != null &&
                snapshot.bloodGroup!.trim().isNotEmpty &&
                snapshot.bloodGroup != 'Unknown' &&
                snapshot.bloodGroup != 'Prefer not to say')
              _Row(
                icon: Icons.bloodtype_outlined,
                label: 'Blood group',
                value: snapshot.bloodGroup!.trim(),
              ),
            if (snapshot.allergies
                .any((a) => a.name.trim().isNotEmpty))
              _Row(
                icon: Icons.warning_amber_outlined,
                label: 'Allergies',
                value: snapshot.allergies
                    .where((a) => a.name.trim().isNotEmpty)
                    .map((a) =>
                        '${a.name.trim()} (${a.severity})')
                    .join(', '),
              ),
            if (meds.isNotEmpty)
              _Row(
                icon: Icons.medication_outlined,
                label: 'Medications (${meds.length} active)',
                value: meds
                    .map((m) => [
                          m.name.trim(),
                          if (m.dosage.trim().isNotEmpty)
                            m.dosage.trim(),
                          if (m.frequency.trim().isNotEmpty)
                            m.frequency.trim(),
                        ].join(' '))
                    .join('; '),
              ),
            if (snapshot.hasEmergencyContact)
              _Row(
                icon: Icons.contact_phone_outlined,
                label: 'Emergency contact',
                value: [
                  if (snapshot.emergencyName != null &&
                      snapshot.emergencyName!.trim().isNotEmpty)
                    snapshot.emergencyName!.trim(),
                  if (snapshot.emergencyPhone != null &&
                      snapshot.emergencyPhone!.trim().isNotEmpty)
                    snapshot.emergencyPhone!.trim(),
                ].join(' · '),
              ),
            if (snapshot.provider != null &&
                snapshot.provider!.trim().isNotEmpty)
              _Row(
                icon: Icons.local_hospital_outlined,
                label: 'Healthcare provider',
                value: snapshot.provider!.trim(),
              ),
            if (snapshot.notes != null &&
                snapshot.notes!.trim().isNotEmpty)
              _Row(
                icon: Icons.note_outlined,
                label: 'Important notes',
                value: snapshot.notes!.trim(),
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Row(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.8)),
                const SizedBox(height: 2),
                Text(value,
                    style: theme.textTheme.titleSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Share mode: field checkboxes → live QR + text preview → explicit share.
class _ShareSheet extends StatefulWidget {
  final String? displayName;
  final HealthSnapshot? snapshot;
  const _ShareSheet({required this.displayName, required this.snapshot});

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late final Map<HealthCardField, bool> _selected = Map.of(
      kDefaultShareSelection);

  Map<String, dynamic> get _payload => buildSharePayload(
        selected: {
          for (final e in _selected.entries)
            if (e.value) e.key,
        },
        displayName: widget.displayName,
        snapshot: widget.snapshot,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final payload = _payload;
    final qrData = jsonEncode(payload);
    final shareable =
        payload.keys.where((k) => k != 'type' && k != 'v').length;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Share Health Card',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Shareable Information — check only what you want to share.',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            for (final f in HealthCardField.values)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(f.label),
                value: _selected[f] ?? false,
                onChanged: (v) =>
                    setState(() => _selected[f] = v ?? false),
              ),
            const SizedBox(height: 8),
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.privacy_tip_outlined,
                      color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Anyone who receives this card can see the information you selected. The QR code contains exactly what is previewed below — nothing hidden.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (shareable == 0)
              Text(
                  'Nothing selected (or nothing entered for the checked fields) — check a field with entered data to generate the code.',
                  style: theme.textTheme.bodyMedium)
            else ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: scheme.outlineVariant),
                  ),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 200,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(formatShareText(payload),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () =>
                      SharePlus.instance.share(ShareParams(
                        text: formatShareText(payload),
                        subject: 'My SoulCare Health Card',
                      )),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share this card'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
