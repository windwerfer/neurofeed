import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:muse_ml/src/connect_window.dart';
import 'package:muse_ml/src/reve/model_engine.dart';
import 'package:muse_ml/src/reve/model_selector.dart';
import 'package:muse_ml/src/reve/models.dart';
import 'package:muse_ml/src/settings.dart';

/// The gate bubble shown when the user tries to start a session whose
/// protocol uses the guardrail, without the selected guardrail model being
/// ready.
///
/// Shows a model dropdown (with sizes + availability), a short explanation of
/// the chosen model, and the import / Open Hugging Face / download buttons
/// (download is greyed out for gated models like REVE). Returns true as soon
/// as a model becomes ready, so the caller can continue straight into the
/// session.
Future<bool> showModelGateDialog(BuildContext context, WidgetRef ref) async {
  final ready = await showDialog<bool>(
    context: context,
    builder: (_) => const _ModelGateDialog(),
  );
  return ready ?? false;
}

class _ModelGateDialog extends ConsumerStatefulWidget {
  const _ModelGateDialog();

  @override
  ConsumerState<_ModelGateDialog> createState() => _ModelGateDialogState();
}

class _ModelGateDialogState extends ConsumerState<_ModelGateDialog> {
  bool _busy = false;
  String? _error;
  double? _progress;
  ProviderSubscription<ModelEngineState>? _readySub;
  int _closeRetries = 0;

  @override
  void initState() {
    super.initState();
    // Continue into the session as soon as the selected model is ready (the
    // initial probe finishing, or an import/download succeeding).
    _readySub = ref.listenManual(modelEngineNotifierProvider, (prev, next) {
      if (next is ModelEngineReady && mounted) {
        _maybeCloseWhenReady();
      }
    });
  }

  /// Close the dialog (popping `true`) only when *this* dialog is the current
  /// route. Readiness can land while the model dropdown's own route is on top
  /// of the navigator; popping then would hand `true` to the dropdown route and
  /// crash on the mismatched result type. Retries briefly because that menu may
  /// be mid-close when readiness arrives.
  void _maybeCloseWhenReady() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent) {
      Navigator.of(context).pop(true);
      return;
    }
    if (_closeRetries < 20) {
      _closeRetries++;
      Future.delayed(const Duration(milliseconds: 100), _maybeCloseWhenReady);
    }
  }

  @override
  void dispose() {
    _readySub?.close();
    super.dispose();
  }

  ModelKind get _selected => modelKindFromSettings(ref.read(settingsProvider));

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = await pickAndImportModel(ref, _selected);
    if (!mounted) return;
    setState(() => _busy = false);
    if (state is ModelEngineError) {
      setState(() => _error = state.message);
    }
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
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

  Future<void> _openHuggingFace() => launchUrl(
    Uri.parse(_selected.hfPageUrl),
    mode: LaunchMode.externalApplication,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installed = ref.watch(
      modelInstalledProvider(_selected),
    );
    if (installed.valueOrNull == true) {
      // Files are on disk but the model is still being probed/loaded — just
      // show a light "starting" state and let _maybeCloseWhenReady pop.
      return AlertDialog(
        title: const Text('Guardrail AI engine'),
        content: const Row(
          children: [
            Padding(
              padding: EdgeInsets.only(right: 12),
              child: BrailleSpinner(),
            ),
            Expanded(child: Text('Loading model…')),
          ],
        ),
      );
    }
    return AlertDialog(
      title: const Text('Guardrail AI engine'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The sleep guardrail runs an EEG foundation model that scores '
              'your brainwaves while you meditate. Pick a model, then '
              'download or import it.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
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
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  'Verifying and installing…',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _import,
                icon: const Icon(Icons.file_open),
                label: const Text('Import model file'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _openHuggingFace,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open Hugging Face'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || _selected.downloadUrl == null
                        ? null
                        : _download,
                    icon: const Icon(Icons.download),
                    label: const Text('Download'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
