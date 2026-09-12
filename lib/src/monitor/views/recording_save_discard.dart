import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/monitor/monitor_providers.dart';

/// Save / Discard for an assembled `recording_$ts.muse.feedback`.
/// Same dialog on GraphShell Stop, session-view Stop, and in-app disconnect.
Future<void> showRecordingSaveDiscardDialog({
  required BuildContext context,
  required Future<void> Function() onSave,
  required Future<void> Function() onDiscard,
}) async {
  final choice = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const RecordingSaveDiscardDialog(),
  );
  if (choice == true) {
    await onSave();
  } else {
    await onDiscard();
  }
}

class RecordingSaveDiscardDialog extends StatelessWidget {
  const RecordingSaveDiscardDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Save recording?'),
        content: const Text('Save this recording to History, or discard it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Shows [RecordingSaveDiscardDialog] when a pending scratch v5 appears.
/// Host once on [AppShell] so GraphShell Stop and in-app disconnect share it.
class RecordingSaveHost extends ConsumerStatefulWidget {
  const RecordingSaveHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RecordingSaveHost> createState() => _RecordingSaveHostState();
}

class _RecordingSaveHostState extends ConsumerState<RecordingSaveHost> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      monitorControllerProvider.select((s) => s.pendingScratchPath),
      (prev, next) {
        if (next == null || _open) return;
        _open = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) {
            _open = false;
            return;
          }
          final notifier = ref.read(monitorControllerProvider.notifier);
          await showRecordingSaveDiscardDialog(
            context: context,
            onSave: notifier.savePendingRecording,
            onDiscard: notifier.discardPendingRecording,
          );
          if (mounted) _open = false;
        });
      },
    );
    return widget.child;
  }
}
