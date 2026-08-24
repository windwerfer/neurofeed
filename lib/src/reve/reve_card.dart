import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muse_ml/src/feedback/feedback_state.dart';
import 'package:muse_ml/src/feedback/guardrail_mode.dart';
import 'package:muse_ml/src/reve/model_engine.dart';
import 'package:muse_ml/src/reve/model_selector.dart';
import 'package:muse_ml/src/settings.dart';

/// AI-engine setup card: pick which foundation model powers the sleep
/// guardrail, and download/import/uninstall it. LUNA models are downloaded
/// directly from Hugging Face (un-gated); REVE is imported from a user-picked
/// `.safetensors` file (verified by SHA-256) after accepting the model's terms.
class AiEngineCard extends ConsumerStatefulWidget {
  const AiEngineCard({super.key});

  @override
  ConsumerState<AiEngineCard> createState() => _AiEngineCardState();
}

class _AiEngineCardState extends ConsumerState<AiEngineCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final fb = ref.watch(feedbackStateProvider);
    final mode = settings.guardrailModeForProtocol[fb.protocol]!;
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
              'Runs the AI sleep guardrail. Pick a foundation model — '
              'LUNA downloads straight from Hugging Face; REVE needs the '
              'license accepted and the file imported.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 24),
            ModelSelectorDropdown(),
            const Divider(height: 24),
            ..._buildBody(theme, state, mode),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBody(ThemeData theme, ModelEngineState state, GuardrailMode mode) {
    if (mode.isBandMath) {
      return [
        Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Band math mode — no model needed',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ];
    }

    if (mode.modelKind == null) {
      return [
        Text(
          'Unknown guardrail mode',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ];
    }

    final modelKind = mode.modelKind!;
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
                onPressed: _uninstall,
                child: const Text('Uninstall'),
              ),
            ],
          ),
        ];
      case ModelEngineLoading():
        return [
          const SizedBox(height: 8),
          ModelInstallBubble(kind: modelKind),
        ];
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
          ModelInstallBubble(kind: modelKind),
        ];
      case ModelEngineNotInstalled():
        final modelDir = ref.watch(modelFolderProvider);
        return [
          ModelInstallBubble(kind: modelKind),
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
                  '"Check for model"):\n${modelDir.value ?? 'resolving…'}',
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

  Future<void> _uninstall() async {
    await ref.read(modelEngineNotifierProvider.notifier).clear();
  }
}
