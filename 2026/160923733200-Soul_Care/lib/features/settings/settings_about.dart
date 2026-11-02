import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/providers/settings_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/app_widgets.dart';

/// /settings/about — what SoulCare is, privacy note, credits, tour replay.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/settings'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
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
                Text(
                  'Privacy note: SoulCare is a wellness tracking and organization tool. Scores and scenarios are illustrative and based on your logged data — not medical diagnosis, disease prediction, or treatment recommendations.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Text('Acknowledgements',
                    style: theme.textTheme.titleSmall),
                Text(
                  'Built with Flutter · local storage with Hive · charts with fl_chart · PDF viewing with pdfrx · file picking with file_picker · notifications on-device only.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () async {
                    final prov =
                        context.read<SettingsProvider>();
                    await prov.update(prov.settings
                        .copyWith(onboardingDone: false));
                    if (!context.mounted) return;
                    context.push('/welcome');
                  },
                  child: const Text('Replay welcome tour'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
