import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:muse_ml/src/reve/model_engine.dart';
import 'package:muse_ml/src/reve/models.dart';
import 'package:muse_ml/src/settings.dart';

const XTypeGroup _safetensorsType = XTypeGroup(
  label: 'Model weights',
  extensions: ['safetensors'],
);

/// Let the user pick a `.safetensors` file and import it into the app for
/// [kind]. Returns the resulting engine state (Ready after a success).
Future<ModelEngineState> pickAndImportModel(
  WidgetRef ref,
  ModelKind kind,
) async {
  final file = await openFile(acceptedTypeGroups: [_safetensorsType]);
  if (file == null) {
    return ref.read(modelEngineNotifierProvider);
  }
  return ref
      .read(modelEngineNotifierProvider.notifier)
      .import(kind, file.openRead());
}

/// Green check shown next to a model's name when its files are on disk.
/// With [alwaysShow] it renders regardless (e.g. the always-available
/// band-math scorer).
class ModelInstalledCheck extends ConsumerWidget {
  const ModelInstalledCheck({super.key, this.kind, this.alwaysShow = false});

  final ModelKind? kind;
  final bool alwaysShow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed =
        kind != null &&
        (ref.watch(modelInstalledProvider(kind!)).value ?? false);
    if (!installed && !alwaysShow) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Icon(Icons.check_circle, size: 16, color: Colors.green.shade600),
    );
  }
}

/// Download / import / check actions for a model, with live progress. Shared
/// by the settings card and the guardrail dialog.
class ModelInstallBubble extends ConsumerStatefulWidget {
  const ModelInstallBubble({super.key, required this.kind});

  final ModelKind kind;

  @override
  ConsumerState<ModelInstallBubble> createState() =>
      _ModelInstallBubbleState();
}

class _ModelInstallBubbleState extends ConsumerState<ModelInstallBubble> {
  bool _busy = false;
  double? _progress;

  Future<void> _import() async {
    setState(() => _busy = true);
    final state = await pickAndImportModel(ref, widget.kind);
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
          widget.kind,
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
    Uri.parse(widget.kind.hfPageUrl),
    mode: LaunchMode.externalApplication,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy)
          Column(
            children: [
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
          )
        else ...[
          FilledButton.tonalIcon(
            onPressed: _import,
            icon: const Icon(Icons.file_open),
            label: const Text('Import model file'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openHuggingFace,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open Hugging Face'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.kind.downloadUrl == null ? null : _download,
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _recheck,
            icon: const Icon(Icons.refresh),
            label: const Text('Check for model'),
          ),
        ],
      ],
    );
  }
}

/// The model dropdown used in the settings card and the session gate bubble.
///
/// Shows every model with its size, a check when its files are already on
/// disk, and persists the selection to [Settings].
class ModelSelectorDropdown extends ConsumerWidget {
  const ModelSelectorDropdown({super.key, this.onChanged});

  final ValueChanged<ModelKind>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = modelKindFromSettings(ref.watch(settingsProvider));

    return DropdownButtonFormField<ModelKind>(
      initialValue: selected,
      isExpanded: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        for (final kind in ModelKind.values)
          DropdownMenuItem(
            value: kind,
            child: Row(
              children: [
                Expanded(child: Text(kind.folderLabel)),
                ModelInstalledCheck(kind: kind),
              ],
            ),
          ),
      ],
      onChanged: (kind) {
        if (kind == null) return;
        ref.read(modelEngineNotifierProvider.notifier).select(kind);
        onChanged?.call(kind);
      },
    );
  }
}

/// Short description + "how to get it" text for the currently selected model,
/// plus its install status.
class ModelInfoBlock extends ConsumerWidget {
  const ModelInfoBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected = modelKindFromSettings(ref.watch(settingsProvider));
    final engineState = ref.watch(modelEngineNotifierProvider);
    final installed = ref.watch(modelInstalledProvider(selected)).value;

    final statusText = switch (engineState) {
      ModelEngineReady(:final description) => description,
      ModelEngineLoading() => 'Loading…',
      _ when installed == true => 'Installed — will load on use.',
      _ => 'Not installed yet.',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(selected.shortDescription, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.info_outline, size: 14),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                selected.getGuide,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          statusText,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
