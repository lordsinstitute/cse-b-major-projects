import '../../data/models/health_snapshot.dart';

/// Shareable health-card fields. Only these — and only when the user checks
/// them — ever enter the QR code or the shared text. Journal entries,
/// detailed health history, medical documents and wellness analytics are not
/// representable here by construction (this builder never receives them).
enum HealthCardField {
  name,
  bloodGroup,
  allergies,
  emergencyContact,
  medications,
  provider,
  notes,
}

extension HealthCardFieldX on HealthCardField {
  String get label => switch (this) {
        HealthCardField.name => 'Name',
        HealthCardField.bloodGroup => 'Blood Group',
        HealthCardField.allergies => 'Allergies',
        HealthCardField.emergencyContact => 'Emergency Contact',
        HealthCardField.medications => 'Medications',
        HealthCardField.provider => 'Healthcare Provider',
        HealthCardField.notes => 'Important Notes',
      };
}

/// Privacy-safe defaults: identity + safety-critical fields on, everything
/// else off until the user explicitly opts in.
const Map<HealthCardField, bool> kDefaultShareSelection = {
  HealthCardField.name: true,
  HealthCardField.bloodGroup: true,
  HealthCardField.allergies: true,
  HealthCardField.emergencyContact: true,
  HealthCardField.medications: false,
  HealthCardField.provider: false,
  HealthCardField.notes: false,
};

bool _bloodEntered(String? group) =>
    group != null &&
    group.trim().isNotEmpty &&
    group != 'Unknown' &&
    group != 'Prefer not to say';

/// Builds the exact share payload: only selected AND actually-entered fields.
/// No hidden data is possible — the returned map contains nothing else.
Map<String, dynamic> buildSharePayload({
  required Set<HealthCardField> selected,
  required String? displayName,
  required HealthSnapshot? snapshot,
}) {
  final payload = <String, dynamic>{
    'type': 'soulcare-health-card',
    'v': 1,
  };
  final name = displayName?.trim();
  if (selected.contains(HealthCardField.name) &&
      name != null &&
      name.isNotEmpty) {
    payload['name'] = name;
  }
  final group = snapshot?.bloodGroup;
  if (selected.contains(HealthCardField.bloodGroup) &&
      _bloodEntered(group)) {
    payload['bloodGroup'] = group!.trim();
  }
  final allergies = (snapshot?.allergies ?? const [])
      .where((a) => a.name.trim().isNotEmpty)
      .toList();
  if (selected.contains(HealthCardField.allergies) &&
      allergies.isNotEmpty) {
    payload['allergies'] = [
      for (final a in allergies)
        {
          'name': a.name.trim(),
          'severity': a.severity,
        },
    ];
  }
  final eName = snapshot?.emergencyName?.trim();
  final ePhone = snapshot?.emergencyPhone?.trim();
  if (selected.contains(HealthCardField.emergencyContact) &&
      ((eName != null && eName.isNotEmpty) ||
          (ePhone != null && ePhone.isNotEmpty))) {
    payload['emergencyContact'] = {
      if (eName != null && eName.isNotEmpty) 'name': eName,
      if (ePhone != null && ePhone.isNotEmpty) 'phone': ePhone,
    };
  }
  final meds = (snapshot?.medications ?? const [])
      .where((m) => m.name.trim().isNotEmpty && m.isActive)
      .toList();
  if (selected.contains(HealthCardField.medications) &&
      meds.isNotEmpty) {
    payload['medications'] = [
      for (final m in meds)
        {
          'name': m.name.trim(),
          if (m.dosage.trim().isNotEmpty) 'dosage': m.dosage.trim(),
          if (m.frequency.trim().isNotEmpty)
            'frequency': m.frequency.trim(),
        },
    ];
  }
  final provider = snapshot?.provider?.trim();
  if (selected.contains(HealthCardField.provider) &&
      provider != null &&
      provider.isNotEmpty) {
    payload['provider'] = provider;
  }
  final notes = snapshot?.notes?.trim();
  if (selected.contains(HealthCardField.notes) &&
      notes != null &&
      notes.isNotEmpty) {
    payload['notes'] = notes;
  }
  return payload;
}

/// Printable / share-sheet text of the exact same payload (no hidden data:
/// it is rendered from [payload], not from the underlying records).
String formatShareText(Map<String, dynamic> payload) {
  final buf = StringBuffer('SoulCare Health Card');
  void line(String label, Object? value) {
    if (value == null) return;
    final s = value.toString().trim();
    if (s.isEmpty || s == '[]' || s == '{}') return;
    buf.writeln();
    buf.writeln('$label: $s');
  }

  line('Name', payload['name']);
  line('Blood group', payload['bloodGroup']);
  final allergies = payload['allergies'];
  if (allergies is List && allergies.isNotEmpty) {
    buf.writeln();
    buf.writeln('Allergies: ${allergies.map((a) {
      if (a is Map) {
        return '${a['name']} (${a['severity'] ?? '—'})';
      }
      return '$a';
    }).join(', ')}');
  }
  final contact = payload['emergencyContact'];
  if (contact is Map && contact.isNotEmpty) {
    final parts = [
      if (contact['name'] != null) '${contact['name']}',
      if (contact['phone'] != null) '${contact['phone']}',
    ];
    buf.writeln();
    buf.writeln('Emergency contact: ${parts.join(' · ')}');
  }
  final meds = payload['medications'];
  if (meds is List && meds.isNotEmpty) {
    buf.writeln();
    buf.writeln('Medications (record only — not advice): ${meds.map((m) {
      if (m is Map) {
        final bits = ['${m['name']}'];
        if (m['dosage'] != null) bits.add('${m['dosage']}');
        if (m['frequency'] != null) bits.add('${m['frequency']}');
        return bits.join(' ');
      }
      return '$m';
    }).join('; ')}');
  }
  line('Healthcare provider', payload['provider']);
  line('Notes', payload['notes']);
  return buf.toString().trim();
}

/// Initials avatar text (no photo is stored — privacy by design).
String initialsFor(String? displayName) {
  final parts = (displayName ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}
