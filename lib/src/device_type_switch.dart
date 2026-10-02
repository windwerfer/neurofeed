import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neurofeed/src/connection_provider.dart';
import 'package:neurofeed/src/feedback/feedback_state.dart';
import 'package:neurofeed/src/monitor/monitor_providers.dart';
import 'package:neurofeed/src/monitor/monitor_state.dart';

/// Why a device-type change must ask before dropping the link.
enum DeviceTypeSwitchBlock { none, recording, session, calibration }

/// [linked] is connected, connecting, or disconnecting.
/// A GraphShell recording stays open across the disconnect. A playing,
/// paused, or interrupted feedback session ends, because this disconnect
/// is user-initiated. Calibration keeps running without the headset.
DeviceTypeSwitchBlock deviceTypeSwitchBlock({
  required bool linked,
  required CaptureKind kind,
  required FeedbackPhase phase,
}) {
  if (!linked) return DeviceTypeSwitchBlock.none;
  switch (phase) {
    case FeedbackPhase.playing:
    case FeedbackPhase.paused:
    case FeedbackPhase.interrupted:
      return DeviceTypeSwitchBlock.session;
    case FeedbackPhase.calibrating:
      return DeviceTypeSwitchBlock.calibration;
    case FeedbackPhase.idle:
    case FeedbackPhase.ended:
      break;
  }
  if (kind == CaptureKind.recording) return DeviceTypeSwitchBlock.recording;
  return DeviceTypeSwitchBlock.none;
}

/// Live answer for the connect dropdown and the Debug-mode switch.
/// Does not create the feedback notifier just to open the menu.
final deviceTypeSwitchBlockProvider = Provider<DeviceTypeSwitchBlock>((ref) {
  final linked = ref.watch(
    appStateProvider.select(
      (s) => s.status.connected || s.connectingTo != null || s.disconnecting,
    ),
  );
  if (!linked) return DeviceTypeSwitchBlock.none;
  final kind = ref.exists(monitorControllerProvider)
      ? ref.watch(monitorControllerProvider.select((m) => m.kind))
      : CaptureKind.idle;
  final phase = ref.exists(feedbackStateProvider)
      ? ref.watch(feedbackStateProvider.select((s) => s.phase))
      : FeedbackPhase.idle;
  return deviceTypeSwitchBlock(linked: true, kind: kind, phase: phase);
});

String deviceTypeSwitchTitle(DeviceTypeSwitchBlock block) {
  return switch (block) {
    DeviceTypeSwitchBlock.recording => 'Recording in progress',
    DeviceTypeSwitchBlock.session ||
    DeviceTypeSwitchBlock.calibration => 'Session in progress',
    DeviceTypeSwitchBlock.none => '',
  };
}

String deviceTypeSwitchMessage({
  required DeviceTypeSwitchBlock block,
  required String deviceName,
  required String nextTypeLabel,
}) {
  final name = deviceName.trim().isEmpty ? 'this device' : deviceName.trim();
  final next = nextTypeLabel.trim();
  return switch (block) {
    DeviceTypeSwitchBlock.none => '',
    DeviceTypeSwitchBlock.recording =>
      'Disconnect $name? This recording stays open until you stop it. '
          'NeuroFeed will then look for a $next device.',
    DeviceTypeSwitchBlock.session =>
      'Disconnect $name? This ends the feedback session. '
          'NeuroFeed will then look for a $next device.',
    DeviceTypeSwitchBlock.calibration =>
      'Disconnect $name? Calibration is still running. '
          'NeuroFeed will then look for a $next device.',
  };
}

/// Disconnect / Cancel. A dismiss counts as Cancel.
Future<bool> confirmDeviceTypeChange(
  BuildContext context, {
  required DeviceTypeSwitchBlock block,
  required String deviceName,
  required String nextTypeLabel,
}) async {
  if (block == DeviceTypeSwitchBlock.none) return true;
  final answer = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(deviceTypeSwitchTitle(block)),
      content: Text(
        deviceTypeSwitchMessage(
          block: block,
          deviceName: deviceName,
          nextTypeLabel: nextTypeLabel,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Disconnect'),
        ),
      ],
    ),
  );
  return answer == true;
}
