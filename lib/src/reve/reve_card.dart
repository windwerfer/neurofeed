import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:muse_ml/src/reve/model_engine.dart';
import 'package:muse_ml/src/reve/model_selector.dart';
import 'package:muse_ml/src/reve/models.dart';
import 'package:muse_ml/src/settings.dart';

/// AI-engine setup card: pick which foundation model powers the Pure Jhana
/// guardrail, and download/import/uninstall it. LUNA models are downloaded
/// directly from Hugging Face (un-gated); REVE is imported from a user-picked
/// `.safetensors` file (verified by SHA-256) after accepting the model's terms.
class AiEngineCard extends ConsumerStatefulWidget {
  const AiEngineCard({super.key});

  @override
  ConsumerState<AiEngineCard> createState() => _AiEngineCardState();
}

class _AiEngineCardState extends ConsumerState<AiEngineCard> {
  bool _busy = false;
  double? _progress;

  Future<void> _import() async {
    setState(() => _busy = true);
    final state = await pickAndImportModel(ref, _selected);
    if (!mounted) return;
    setState(() => _busy = false);
    if (state is ModelEngineError) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(state.message)));
    }
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _progress = 0;
    });
    await ref
        .read(modelEngineNotifierProvider.notifier)
        .download(
          _selected,
          onProgress: (received, total) {
            if (!mounted) return;
            setState(() => _progress = total > 0 ? received / total : null);
          },
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = null;
    });
  }

  Future<void> _recheck() async {
    setState(() => _busy = true);
    await ref.read(modelEngineNotifierProvider.notifier).recheck();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _openHuggingFace() => launchUrl(
    Uri.parse(_selected.hfPageUrl),
    mode: LaunchMode.externalApplication,
  );

  ModelKind get _selected => modelKindFromSettings(ref.read(settingsProvider));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(modelEngineNotifierProvider);

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Guardrail AI engine',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Runs the Pure Jhana sleep guardrail. Pick a foundation model — '
              'LUNA downloads straight from Hugging Face; REVE needs the '
              'license accepted and the file imported.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 24),
            const ModelSelectorDropdown(),
            const ModelInfoBlock(),
            if (_busy) ...[
              const SizedBox(height: 16),
              if (_progress != null) ...[
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text(
                  'Downloading… ${(_progress! * 100).round()}%',
                  style: theme.textTheme.bodySmall,
                ),
              ] else ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: CircularProgressIndicator(),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text('Working…', style: theme.textTheme.bodySmall),
                ),
              ],
            ],
            const Divider(height: 24),
            ..._buildBody(theme, state),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBody(ThemeData theme, ModelEngineState state) {
    final busy = _busy;
    switch (state) {
      case ModelEngineReady():
        return [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.description,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: busy ? null : _uninstall,
                child: const Text('Uninstall'),
              ),
            ],
          ),
        ];
      case ModelEngineLoading():
        return const [SizedBox.shrink()];
      case ModelEngineError(:final message):
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
            ],
          ),
          const SizedBox(height: 12),
          ..._actionButtons(theme, busy, importPrimary: true),
        ];
      case ModelEngineNotInstalled():
        final modelDir = ref.watch(modelFolderProvider);
        return [
          ..._actionButtons(theme, busy, importPrimary: true),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.folder_open, size: 14),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Model files live here (dropped files are picked up by '
                  '“Check for model”):\n${modelDir.value ?? 'resolving…'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ];
    }
  }

  List<Widget> _actionButtons(
    ThemeData theme,
    bool busy, {
    required bool importPrimary,
  }) {
    final downloadEnabled = !busy && _selected.downloadUrl != null;
    final row = Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy ? null : _openHuggingFace,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open Hugging Face'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: downloadEnabled ? _download : null,
            icon: const Icon(Icons.download),
            label: const Text('Download'),
          ),
        ),
      ],
    );
    return [
      if (importPrimary)
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: busy ? null : _import,
            icon: const Icon(Icons.file_open),
            label: const Text('Import model file'),
          ),
        )
      else ...[
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: busy ? null : _import,
            icon: const Icon(Icons.file_open),
            label: const Text('Import model file'),
          ),
        ),
        const SizedBox(height: 4),
      ],
      const SizedBox(height: 8),
      row,
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: busy ? null : _recheck,
          icon: const Icon(Icons.refresh),
          label: const Text('Check for model'),
        ),
      ),
    ];
  }

  Future<void> _uninstall() async {
    setState(() => _busy = true);
    await ref.read(modelEngineNotifierProvider.notifier).clear();
    if (mounted) setState(() => _busy = false);
  }
}
