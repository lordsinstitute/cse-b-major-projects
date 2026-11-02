import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/providers/ai_chat_provider.dart';
import '../../core/ai/ai_config.dart';
import '../../core/ai/ai_models.dart';
import '../../core/widgets/app_widgets.dart';

/// Settings → SoulCare AI: mode, local server, cloud provider + keys,
/// privacy, and advanced generation parameters.
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _endpointCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  bool _urlInit = false;
  bool _cloudInit = false;
  bool _showAdvanced = false;
  String _maskedKey = 'Not set';

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _endpointCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(AiConfig next, {String? ok}) async {
    final prov = context.read<AiChatProvider>();
    final good = await prov.saveConfig(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(good
            ? (ok ?? 'Saved ✓')
            : 'Those settings are invalid.')));
  }

  Future<void> _refreshMask() async {
    final prov = context.read<AiChatProvider>();
    final masked =
        await prov.maskedCloudKey(prov.config.cloud.provider);
    if (mounted) setState(() => _maskedKey = masked);
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AiChatProvider>();
    final cfg = prov.config;
    final theme = Theme.of(context);
    if (!_urlInit) {
      _urlCtrl.text = cfg.local.serverUrl;
      _urlInit = true;
    }
    if (!_cloudInit ||
        _endpointCtrl.text != cfg.cloud.endpoint) {
      _endpointCtrl.text = cfg.cloud.endpoint;
      _modelCtrl.text = cfg.cloud.model;
      _cloudInit = true;
      Future.microtask(_refreshMask);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('SoulCare AI'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/settings'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _StatusPanel(),
          const SizedBox(height: 12),
          const _ModeSection(),
          const SizedBox(height: 16),
          const _LocalSection(),
          const SizedBox(height: 16),
          _CloudSection(
            endpointCtrl: _endpointCtrl,
            modelCtrl: _modelCtrl,
            keyCtrl: _keyCtrl,
            maskedKey: _maskedKey,
            onChanged: _refreshMask,
            onSave: _save,
          ),
          const SizedBox(height: 16),
          const _PrivacySection(),
          const SizedBox(height: 16),
          Text('Advanced',
              style: theme.textTheme.titleSmall),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Generation parameters'),
            subtitle: const Text(
                'Temperature, output length, timeouts, context size'),
            value: _showAdvanced,
            onChanged: (v) =>
                setState(() => _showAdvanced = v),
          ),
          if (_showAdvanced) _AdvancedSection(onSave: _save),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// AI Mode: Local AI vs Cloud AI. History is never touched by switching.
class _ModeSection extends StatelessWidget {
  const _ModeSection();

  Future<void> _pick(BuildContext context, AiMode next) async {
    final prov = context.read<AiChatProvider>();
    if (next == prov.mode) return;
    if (next == AiMode.cloud &&
        !prov.config.cloudConsentAcknowledged) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Cloud AI privacy notice'),
          content: const Text(
              'Messages sent to a cloud provider will leave your device and be processed according to that provider\u2019s policies.\n\nSoulCare will only send the information required for your request.\n\nYou can switch back to Local AI at any time.'),
          actions: [
            TextButton(
                onPressed: () =>
                    Navigator.of(d).pop(false),
                child: const Text('Not now')),
            FilledButton(
                onPressed: () =>
                    Navigator.of(d).pop(true),
                child: const Text('I understand')),
          ],
        ),
      );
      if (accepted != true || !context.mounted) return;
      await prov.acknowledgeCloudConsent();
    }
    await prov.setMode(next);
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AiChatProvider>();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AI Mode', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        RadioGroup<AiMode>(
          groupValue: prov.mode,
          onChanged: (v) {
            if (v != null) _pick(context, v);
          },
          child: const Column(
            children: [
              RadioListTile<AiMode>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('Local AI'),
                subtitle: Text(
                    'On-device LLM server (Gemma). No cloud involved.'),
                value: AiMode.local,
              ),
              RadioListTile<AiMode>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('Cloud AI'),
                subtitle: Text(
                    'Your configured provider, using your API key.'),
                value: AiMode.cloud,
              ),
            ],
          ),
        ),
        Text(
          'Switching providers never deletes history, health data, or settings — only the backend changes.',
          style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel();

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AiChatProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final st = prov.connection.state;
    final isLocal = prov.mode == AiMode.local;
    final dot = !prov.connection.isConnected
        ? scheme.outline
        : scheme.primary;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 12, color: dot),
              const SizedBox(width: 8),
              Expanded(
                child: Text('SoulCare AI',
                    style: theme.textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Mode: ${prov.mode.label}',
              style: theme.textTheme.bodyMedium),
          if (isLocal) ...[
            Text(
                'Server: ${prov.config.local.serverUrl.replaceFirst(RegExp(r'^https?://'), '')}',
                style: theme.textTheme.bodyMedium),
            Text(
                'Model: ${st?.activeModelId ?? prov.config.local.activeModelId ?? '—'}',
                style: theme.textTheme.bodyMedium),
            const Text('Inference: On Device',
                style: TextStyle()),
            const Text('Cloud: Not Used'),
          ] else ...[
            Text(
                'Provider: ${prov.config.cloud.provider.label}',
                style: theme.textTheme.bodyMedium),
            Text('Model: ${prov.config.cloud.model}',
                style: theme.textTheme.bodyMedium),
            const Text('Inference: Cloud (your provider)'),
          ],
          Text(
              'Status: ${prov.connection.checking ? 'Checking…' : (st == null ? 'Not checked yet' : (st.ok ? 'Ready' : 'Unavailable'))}'
              '${st?.latencyMs == null ? '' : ' · ${st!.latencyMs} ms'}',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant)),
          if (st?.error != null)
            Text(st!.error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.error)),
        ],
      ),
    );
  }
}

class _LocalSection extends StatefulWidget {
  const _LocalSection();

  @override
  State<_LocalSection> createState() => _LocalSectionState();
}

class _LocalSectionState extends State<_LocalSection> {
  final _urlCtrl = TextEditingController();
  bool _init = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AiChatProvider>();
    final cfg = prov.config.local;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (!_init) {
      _urlCtrl.text = cfg.serverUrl;
      _init = true;
    } else if (_urlCtrl.text != cfg.serverUrl &&
        !_urlCtrl.text.endsWith('…')) {
      // Keep user edits; resync only after external saves.
    }
    final placement = classifyServerUrl(cfg.serverUrl);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Local AI', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        const Text(
            'Your AI requests are processed through the local AI server running on this device. No cloud AI provider is used for these requests.'),
        const SizedBox(height: 8),
        TextField(
          controller: _urlCtrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Local AI Server URL',
            hintText: 'http://127.0.0.1:11434/v1',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) async {
            final err = validateServerUrl(v);
            if (err != null) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(err)));
              }
              return;
            }
            final p = context.read<AiChatProvider>();
            await p.saveConfig(p.config.copyWith(
                local: p.config.local
                    .copyWith(serverUrl: v.trim())));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Saved ✓')));
            }
          },
        ),
        const SizedBox(height: 4),
        Text(
          placement == ServerPlacement.onDevice
              ? 'Same-device server (loopback).'
              : placement == ServerPlacement.lan
                  ? 'LAN server — traffic stays on your network.'
                  : 'Remote server — this is not on-device AI.',
          style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.tonal(
              onPressed: prov.connection.checking
                  ? null
                  : () => prov.checkConnection(force: true),
              child: Text(prov.connection.checking
                  ? 'Testing…'
                  : 'Test connection'),
            ),
            const SizedBox(width: 8),
            if (prov.connection.state?.latencyMs != null)
              Text(
                  'Latency: ${prov.connection.state!.latencyMs} ms',
                  style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 8),
        Text('Model', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        const _ModelPicker(),
      ],
    );
  }
}

class _ModelPicker extends StatefulWidget {
  const _ModelPicker();

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  List<AiModel>? _models;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final prov = context.read<AiChatProvider>();
    try {
      final models = await prov.listModels();
      if (!mounted) return;
      setState(() => _models = models);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AiChatProvider>();
    final theme = Theme.of(context);
    if (_busy) {
      return const AppCard(
          child: AppLoading(message: 'Listing models…'));
    }
    if (_models == null) {
      return AppCard(
        child: Row(
          children: [
            const Expanded(
                child: Text(
                    'Model list unavailable — test the connection first.')),
            TextButton(
                onPressed: _load,
                child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_models!.isEmpty) {
      return const AppCard(
          child: Text(
              'No models reported by the server. Load a model in the local AI server first.'));
    }
    final activeId = prov.connection.state?.activeModelId ??
        prov.config.local.activeModelId;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadioGroup<String>(
            groupValue: activeId,
            onChanged: (v) async {
              if (v == null) return;
              final p = context.read<AiChatProvider>();
              final ok = await p.saveConfig(p.config.copyWith(
                  local: p.config.local.copyWith(
                      activeModelId: () => v)));
              if (ok) await p.checkConnection(force: true);
            },
            child: Column(
              children: [
                for (final m in _models!)
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(m.displayName),
                    subtitle: Text(m.id,
                        style: theme.textTheme.bodySmall),
                    value: m.id,
                  ),
              ],
            ),
          ),
          Text(
            'Model IDs come from the server — never typed in. Single-model servers select automatically.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CloudSection extends StatefulWidget {
  final TextEditingController endpointCtrl;
  final TextEditingController modelCtrl;
  final TextEditingController keyCtrl;
  final String maskedKey;
  final VoidCallback onChanged;
  final Future<void> Function(AiConfig next) onSave;
  const _CloudSection({
    required this.endpointCtrl,
    required this.modelCtrl,
    required this.keyCtrl,
    required this.maskedKey,
    required this.onChanged,
    required this.onSave,
  });

  @override
  State<_CloudSection> createState() => _CloudSectionState();
}

class _CloudSectionState extends State<_CloudSection> {
  bool _savingKey = false;
  bool _hasKey = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_check);
  }

  Future<void> _check() async {
    final prov = context.read<AiChatProvider>();
    final has = await prov.hasCloudKey();
    if (mounted) setState(() => _hasKey = has);
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AiChatProvider>();
    final cfg = prov.config.cloud;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cloud AI', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        DropdownButtonFormField<CloudProviderKind>(
          initialValue: cfg.provider,
          decoration: const InputDecoration(
            labelText: 'Provider',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final k in CloudProviderKind.values)
              DropdownMenuItem(
                  value: k, child: Text(k.label)),
          ],
          onChanged: (v) async {
            if (v == null) return;
            final p = context.read<AiChatProvider>();
            final current = p.config.cloud;
            // Switching provider kinds resets endpoint/model to that
            // provider's defaults; the key is per-provider in secure
            // storage, so nothing leaks across providers.
            await widget.onSave(p.config.copyWith(
                cloud: current.copyWith(
              provider: v,
              endpoint:
                  CloudAiSettings.defaultEndpointFor(v),
              model: CloudAiSettings.defaultModelFor(v),
            )));
            widget.endpointCtrl.text =
                CloudAiSettings.defaultEndpointFor(v);
            widget.modelCtrl.text =
                CloudAiSettings.defaultModelFor(v);
            widget.keyCtrl.clear();
            await _check();
            widget.onChanged();
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.endpointCtrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Endpoint',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) async {
            final p = context.read<AiChatProvider>();
            await widget.onSave(p.config.copyWith(
                cloud: p.config.cloud
                    .copyWith(endpoint: v.trim())));
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.modelCtrl,
          decoration: const InputDecoration(
            labelText: 'Model',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) async {
            final p = context.read<AiChatProvider>();
            await widget.onSave(p.config.copyWith(
                cloud:
                    p.config.cloud.copyWith(model: v.trim())));
          },
        ),
        const SizedBox(height: 8),
        Text('API Key: ${widget.maskedKey}',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        TextField(
          controller: widget.keyCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New API key (replaces saved key)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: _savingKey
                  ? null
                  : () async {
                      setState(() => _savingKey = true);
                      try {
                        final p =
                            context.read<AiChatProvider>();
                        final ok = await p.saveCloudKey(
                            widget.keyCtrl.text);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(
                                content: Text(ok
                                    ? 'API key saved securely ✓'
                                    : 'Enter an API key first.')));
                        if (ok) {
                          widget.keyCtrl.clear();
                          await _check();
                          widget.onChanged();
                        }
                      } finally {
                        if (mounted) {
                          setState(
                              () => _savingKey = false);
                        }
                      }
                    },
              child: Text(_savingKey
                  ? 'Saving…'
                  : (_hasKey ? 'Replace key' : 'Save key')),
            ),
            if (_hasKey)
              TextButton(
                onPressed: () async {
                  final p =
                      context.read<AiChatProvider>();
                  await p.deleteCloudKey();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(
                          content:
                              Text('API key removed.')));
                  await _check();
                  widget.onChanged();
                },
                child: const Text('Remove key'),
              ),
            FilledButton.tonal(
              onPressed: prov.connection.checking
                  ? null
                  : () => prov.checkConnection(force: true),
              child: Text(prov.connection.checking
                  ? 'Testing…'
                  : 'Test connection'),
            ),
          ],
        ),
        if (prov.connection.state?.error != null &&
            prov.mode == AiMode.cloud) ...[
          const SizedBox(height: 4),
          Text(prov.connection.state!.error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.error)),
        ],
        const SizedBox(height: 4),
        Text(
          'Keys are stored in platform secure storage — never in the database, chat history, logs, or exports. Only the last 4 characters are ever shown.',
          style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final prov = context.watch<AiChatProvider>();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Privacy', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          const Text(
              'Local AI: requests stay on this device / your network. No cloud provider is used.\n\nCloud AI: messages leave your device under your provider\u2019s policies. SoulCare sends only what your request needs — never your whole database.'),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                  prov.config.cloudConsentAcknowledged
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 18,
                  color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  prov.config.cloudConsentAcknowledged
                      ? 'Cloud AI privacy notice accepted.'
                      : 'Cloud AI privacy notice not yet accepted.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdvancedSection extends StatelessWidget {
  final Future<void> Function(AiConfig next) onSave;
  const _AdvancedSection({required this.onSave});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AiChatProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLocal = prov.mode == AiMode.local;
    final temp = isLocal
        ? prov.config.local.temperature
        : prov.config.cloud.temperature;
    final maxTok = isLocal
        ? prov.config.local.maxTokens
        : prov.config.cloud.maxTokens;
    Future<void> apply(double? t, int? m) async {
      final p = context.read<AiChatProvider>();
      if (isLocal) {
        await onSave(p.config.copyWith(
            local: p.config.local.copyWith(
                temperature: t, maxTokens: m)));
      } else {
        await onSave(p.config.copyWith(
            cloud: p.config.cloud.copyWith(
                temperature: t, maxTokens: m)));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            'Applies to: ${isLocal ? 'Local AI' : 'Cloud AI'}',
            style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant)),
        Text('Temperature: ${temp.toStringAsFixed(2)}',
            style: theme.textTheme.bodyMedium),
        Slider(
          min: 0,
          max: 2,
          divisions: 20,
          value: temp.clamp(0.0, 2.0),
          label: temp.toStringAsFixed(2),
          onChanged: (v) => apply(v, null),
        ),
        Text('Maximum output tokens: $maxTok',
            style: theme.textTheme.bodyMedium),
        Slider(
          min: 32,
          max: 2048,
          divisions: 16,
          value: maxTok.clamp(32, 2048).toDouble(),
          label: '$maxTok',
          onChanged: (v) => apply(null, v.round()),
        ),
        Text(
            'Context turns kept: ${prov.config.local.contextTurns}',
            style: theme.textTheme.bodyMedium),
        Slider(
          min: 1,
          max: 20,
          divisions: 19,
          value: prov.config.local.contextTurns
              .clamp(1, 20)
              .toDouble(),
          label: '${prov.config.local.contextTurns}',
          onChanged: (v) async {
            final p = context.read<AiChatProvider>();
            await onSave(p.config.copyWith(
                local: p.config.local
                    .copyWith(contextTurns: v.round())));
          },
        ),
        if (kDebugMode) const _DiagnosticsCard(),
      ],
    );
  }
}

/// Developer diagnostics (debug builds only). Counts and timings only —
/// never prompt contents, keys, or private data.
class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard();

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AiChatProvider>();
    final theme = Theme.of(context);
    final conn = prov.connection;
    final st = conn.state;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Diagnostics (debug)',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text('Mode: ${prov.mode.name}'),
          if (prov.mode == AiMode.local)
            Text(
                'Server URL: ${prov.config.local.serverUrl}'),
          if (prov.mode == AiMode.cloud)
            Text(
                'Endpoint: ${prov.config.cloud.endpoint}\nProvider: ${prov.config.cloud.provider.label} · Model: ${prov.config.cloud.model}'),
          Text(
              'Status: ${st == null ? 'unknown' : (st.ok ? 'ready' : 'unavailable')} · latency ${st?.latencyMs ?? '—'} ms'),
          Text('Models seen: ${st?.modelCount ?? 0}'),
          Text(
              'Streaming: ${prov.generating ? 'active' : 'idle'}'),
          Text(
              'Requests this session: ${conn.requestCount}'),
          Text('Last error: ${conn.lastError ?? 'none'}'),
        ],
      ),
    );
  }
}
