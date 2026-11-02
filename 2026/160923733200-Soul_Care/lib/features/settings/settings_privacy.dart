import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/providers/settings_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/app_widgets.dart';

/// /settings/privacy — Privacy & About combined: detailed plain-language
/// privacy documentation plus app identity, credits and tour replay.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy & About'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/settings'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader(title: 'Privacy'),
          const SizedBox(height: 8),
          const PrivacyCard(
            icon: Icons.phone_android,
            title: 'What is stored locally',
            body:
                'Everything lives in private on-device storage (Hive boxes plus a document vault folder no other app can read): daily health entries, sleep/movement/water/mind logs, stress check-ins, morning/evening check-ins, experiments and their DONE/MISSED marks, journal entries, your health snapshot, medication reminders, appointments and dose logs, imported health points, game stats, your profile and goals, and every setting. Files rest in the app sandbox as plain data files — protected by Android sandboxing plus your optional app lock, not by additional encryption (backups can add an AES password).',
          ),
          const SizedBox(height: 8),
          const PrivacyCard(
            icon: Icons.lock_outline,
            title: 'What is protected, and how',
            body:
                'The optional privacy lock covers sensitive sections (journal, snapshot, timeline, reminders, reports) or the entire app. Unlock uses on-device biometrics with an always-available 4-digit PIN fallback. Only a salted hash of the PIN is stored — never the PIN itself, so it cannot be recovered or read back. Locks are session-scoped and reset on restart; wrong attempts only show a counter and never lock you out. App-switcher previews are blanked at the OS level.',
          ),
          const SizedBox(height: 8),
          const PrivacyCard(
            icon: Icons.cloud_off_outlined,
            title: 'What leaves the device',
            body:
                'Nothing, automatically. There is no account, no analytics, no crash reporting and no background sync. Data leaves only through actions you take yourself: sharing a JSON export, sharing an analytics report or health card, or handing a backup file to a storage app you pick. Voice recordings are never uploaded — speech is recognized on-device and temporary audio is discarded. Named display fonts (if you pick one) download once from Google Fonts when online, then work offline; the system font choice never touches the network.',
          ),
          const SizedBox(height: 8),
          const PrivacyCard(
            icon: Icons.key_outlined,
            title: 'Permissions used, and why',
            body:
                'Notifications: local reminders only (no cloud messaging). Biometric: on-device unlock only. Health Connect: read-only steps, sleep, workouts and heart rate, only after you tap Connect. Activity recognition: step counting for Health Connect. Microphone: on-device speech recognition for Quick Voice Log, only while you hold the mic flow. Files and photos: only through the pickers and share sheets you open yourself. Every permission is requested at the moment of use, and refusing one only disables that feature — the rest of the app keeps working.',
          ),
          const SizedBox(height: 8),
          const PrivacyCard(
            icon: Icons.picture_as_pdf_outlined,
            title: 'Medical documents & shared cards',
            body:
                'Imported PDFs are copied into the private vault and never uploaded; their contents are never logged. JSON exports reference documents instead of embedding them, and include your health snapshot only when you tick the box. Health-card QR codes encode exactly the fields you check — the preview is the payload, with nothing hidden. Analytics exports contain aggregates and statistics, never journal bodies or document contents.',
          ),
          const SizedBox(height: 8),
          const PrivacyCard(
            icon: Icons.backup_outlined,
            title: 'Backups: portable and password-optional',
            body:
                'A backup is one portable .zip holding every record plus vault files, created only when you tap Create Backup. An optional password encrypts the whole file with AES; the password is never stored anywhere, so a lost password means an unopenable backup. Restoring previews contents first, then Merges (never overwrites your newer data) or Replaces after an automatic safety snapshot with rollback.',
          ),
          const SizedBox(height: 8),
          const PrivacyCard(
            icon: Icons.delete_outline,
            title: 'Deletion is yours and total',
            body:
                'Delete daily data, experiments, or documents individually — or wipe everything including settings. Every destructive action confirms first and removes stored files too. Because there is no cloud copy, deleting everything on-device plus uninstalling leaves nothing behind anywhere.',
          ),
          const SizedBox(height: 8),
          const PrivacyCard(
            icon: Icons.medical_information_outlined,
            title: 'What SoulCare is not',
            body:
                'SoulCare is a tracking and organization tool, not a medical device. Wellness scores, trends, correlations, scenarios, milestones and experiment results are illustrative summaries of your logged data — never diagnosis, disease prediction, clinical assessment or treatment advice. Nothing here tells you what to do about a health condition; for that, talk to a qualified professional.',
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'About'),
          const SizedBox(height: 8),
          const _AboutCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SoulCare ${AppConstants.appVersion}',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'A private, local-first personal wellness and health organization app: track habits, understand personal patterns, run small self-experiments, organize health documents, and explore illustrative scenarios.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text('Acknowledgements',
              style: theme.textTheme.titleSmall),
          Text(
            'Built with Flutter · local storage with Hive · charts with fl_chart · PDF viewing with pdfrx · file picking with file_picker · speech recognition on-device · notifications on-device only.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              final prov = context.read<SettingsProvider>();
              await prov.update(
                  prov.settings.copyWith(onboardingDone: false));
              if (!context.mounted) return;
              context.push('/welcome');
            },
            child: const Text('Replay welcome tour'),
          ),
        ],
      ),
    );
  }
}

/// Shared privacy explainer card.
class PrivacyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const PrivacyCard(
      {super.key,
      required this.icon,
      required this.title,
      required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                Text(body, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
