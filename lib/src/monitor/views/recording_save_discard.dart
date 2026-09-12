import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/monitor/monitor_providers.dart';
import 'package:muse_ml/src/monitor/recording/crash_recovery.dart';

const kSaveRecordingTitle = 'Save recording?';
const kIncompleteRecordingTitle = 'Incomplete recording detected';

/// Save / Discard for an assembled `recording_$ts.muse.feedback`.
/// Same dialog on GraphShell Stop, session-view Stop, in-app disconnect,
/// and launch crash recovery (title [kIncompleteRecordingTitle]).
Future<void> showRecordingSaveDiscardDialog({
  required BuildContext context,
  required Future<void> Function() onSave,
  required Future<void> Function() onDiscard,
  String title = kSaveRecordingTitle,
}) async {
  final choice = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => RecordingSaveDiscardDialog(title: title),
  );
  if (choice == true) {
    await onSave();
  } else {
    await onDiscard();
  }
}

class RecordingSaveDiscardDialog extends StatelessWidget {
  const RecordingSaveDiscardDialog({
    super.key,
    this.title = kSaveRecordingTitle,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title),
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

/// After feedback's session_* crash dialog. Scans `recording_*` only.
Future<void> showRecordingCrashRecoveryDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final storage = await ref.read(sessionStorageProvider.future);
  final recovered = await scanRecoverableRecordings(scratchDirectory(storage));
  if (recovered.isEmpty) return;
  final store = await ref.read(recordingStoreProvider.future);
  for (final rec in recovered) {
    if (!context.mounted) return;
    await showRecordingSaveDiscardDialog(
      context: context,
      title: kIncompleteRecordingTitle,
      onSave: () => store.publish(rec.scratchV5),
      onDiscard: () => store.discard(rec.scratchV5),
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
