import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/providers/daily_health_provider.dart';
import '../../core/widgets/app_widgets.dart';
import 'stt_gateway.dart';
import 'voice_gateway.dart';
import 'voice_log_controller.dart';

/// /home/voice — Quick Voice Log.
///
/// Speak (or type) a natural update → deterministic extraction → explicit
/// confirmation → save. Nothing is overwritten automatically: only checked
/// sections are written, and only after the user taps Save.
class VoiceLogScreen extends StatelessWidget {
  final VoiceInputGateway gateway;
  const VoiceLogScreen({super.key, VoiceInputGateway? gateway})
      : gateway = gateway ?? const UnavailableVoiceGateway();

  /// Voice screen with the real on-device recognizer.
  factory VoiceLogScreen.withMic({Key? key}) =>
      VoiceLogScreen(key: key, gateway: SpeechToTextGateway());

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => VoiceLogController(gateway: gateway)..checkMic(),
      child: const _VoiceBody(),
    );
  }
}

class _VoiceBody extends StatefulWidget {
  const _VoiceBody();

  @override
  State<_VoiceBody> createState() => _VoiceBodyState();
}

class _VoiceBodyState extends State<_VoiceBody> {
  final _textCtrl = TextEditingController();

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<VoiceLogController>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Voice Log'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Speak your update',
              style: theme.textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(
            'Say what you did today in your own words — sleep, movement, water, mood. Nothing saves until you confirm it.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          // 1) Voice input.
          AppCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _MicButton(
                  listening: ctrl.listening,
                  onTap: ctrl.listening
                      ? null
                      : () => _listen(context),
                ),
                const SizedBox(height: 8),
                Text(
                  ctrl.listening
                      ? 'Listening… speak now.'
                      : _micHint(ctrl),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _textCtrl,
                  maxLines: 4,
                  minLines: 2,
                  onChanged: (v) {
                    ctrl.setTranscript(v);
                  },
                  decoration: const InputDecoration(
                    labelText: 'What happened today? (or type instead)',
                    hintText:
                        'e.g. I slept around seven hours, walked for thirty minutes, drank six glasses of water…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: ctrl.parsing || ctrl.listening
                        ? null
                        : () {
                            FocusScope.of(context).unfocus();
                            ctrl.setTranscript(_textCtrl.text);
                            ctrl.parse();
                          },
                    icon: ctrl.parsing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2))
                        : const Icon(Icons.text_snippet_outlined),
                    label: const Text('Understand this'),
                  ),
                ),
              ],
            ),
          ),
          if (ctrl.notice != null) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Text(ctrl.notice!,
                  style: theme.textTheme.bodyMedium),
            ),
          ],
          // 2) Confirmation.
          if (ctrl.extraction != null &&
              ctrl.extraction!.hasAnything) ...[
            const SizedBox(height: 12),
            _ConfirmationCard(
              textCtrl: _textCtrl,
              onSaved: () {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Voice log saved ✓')),
                );
                context.pop();
              },
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Recordings are never uploaded. Temporary audio is discarded after recognition.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _micHint(VoiceLogController ctrl) {
    return switch (ctrl.mic) {
      MicAvailability.denied =>
        'Microphone denied — typing works the same.',
      MicAvailability.unavailable =>
        'Mic unavailable — typing works the same.',
      _ => 'Tap the mic and speak, or type instead.',
    };
  }

  Future<void> _listen(BuildContext context) async {
    final ctrl = context.read<VoiceLogController>();
    await ctrl.listenAndParse();
    if (mounted && ctrl.transcript.isNotEmpty) {
      _textCtrl.text = ctrl.transcript;
    }
  }
}

class _MicButton extends StatelessWidget {
  final bool listening;
  final VoidCallback? onTap;
  const _MicButton({required this.listening, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              listening ? scheme.errorContainer : scheme.primaryContainer,
        ),
        alignment: Alignment.center,
        child: Icon(
          listening ? Icons.stop : Icons.mic_outlined,
          size: 40,
          color: listening
              ? scheme.onErrorContainer
              : scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// "I found" confirmation: Save / Edit / Cancel, explicit and honest.
class _ConfirmationCard extends StatelessWidget {
  final TextEditingController textCtrl;
  final VoidCallback onSaved;
  const _ConfirmationCard(
      {required this.textCtrl, required this.onSaved});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<VoiceLogController>();
    final daily = context.watch<DailyHealthProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sections = ctrl.sections();
    final warnings = ctrl.extraction?.warnings ?? const [];

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('I found:',
                    style: theme.textTheme.titleMedium),
              ),
              TextButton(
                onPressed: ctrl.toggleEditing,
                child: Text(ctrl.editing ? 'Done' : 'Edit'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final s in sections)
            _SectionRow(section: s, editing: ctrl.editing),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• $w',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant)),
              ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: ctrl.saving
                      ? null
                      : () async {
                          final n = await ctrl.save(daily);
                          if (!context.mounted) return;
                          if (n > 0) {
                            onSaved();
                          } else {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                                    content: Text(ctrl.notice ??
                                        'Nothing was saved.')));
                          }
                        },
                  child: Text(
                      ctrl.saving ? 'Saving…' : 'Save'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    ctrl.clear();
                    textCtrl.clear();
                  },
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Only checked sections are saved — your other logged data is left untouched.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  final VoiceSection section;
  final bool editing;
  const _SectionRow(
      {required this.section, required this.editing});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<VoiceLogController>();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: section.include,
            onChanged: (v) =>
                ctrl.setIncluded(section.key, v ?? true),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(section.label,
                    style: theme.textTheme.bodyMedium),
                Text(section.display,
                    style: theme.textTheme.titleSmall),
              ],
            ),
          ),
          if (editing)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove, size: 18),
                  onPressed: () => ctrl.adjust(
                      section.key, -_step(section.key),
                      min: _min(section.key)),
                  tooltip: 'Less',
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => ctrl.adjust(
                      section.key, _step(section.key),
                      max: _max(section.key)),
                  tooltip: 'More',
                ),
              ],
            ),
        ],
      ),
    );
  }

  static double _step(String key) => switch (key) {
        'sleep' => 0.5,
        'screen' => 0.5,
        'exercise' => 5,
        'water' => 1,
        'meditation' => 5,
        _ => 1,
      };

  static double _min(String key) => switch (key) {
        'energy' => 1,
        'mood' => 1,
        'stress' => 1,
        _ => 0,
      };

  static double _max(String key) => switch (key) {
        'sleep' => 24,
        'energy' => 5,
        'mood' => 5,
        'stress' => 5,
        'exercise' => 600,
        'water' => 30,
        'meditation' => 600,
        'screen' => 24,
        _ => 100,
      };
}
