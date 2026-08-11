import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                if (ref.watch(modelInstalledProvider(kind)).value ?? false)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Colors.green.shade600,
                    ),
                  ),
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
