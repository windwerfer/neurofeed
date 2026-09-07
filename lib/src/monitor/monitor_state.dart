import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/rust/api/device_config.dart';

enum CaptureKind { idle, tmp, recording, feedback }

const List<String> kMuseElectrodeNames = ['TP9', 'AF7', 'AF8', 'TP10'];
const List<String> kCrownElectrodeNames = [
  'CP3',
  'C3',
  'F5',
  'PO3',
  'PO4',
  'F6',
  'C4',
  'CP4',
];

List<String> electrodeNamesForKind(DeviceKind? kind) =>
    kind == DeviceKind.neurosity ? kCrownElectrodeNames : kMuseElectrodeNames;

@immutable
class MonitorState {
  const MonitorState({
    required this.kind,
    required this.electrodeNames,
    required this.channelCount,
    this.captureStartedAtMs,
    this.captureElapsed = Duration.zero,
    this.captureId,
  });

  final CaptureKind kind;
  final List<String> electrodeNames;
  final int channelCount;
  final int? captureStartedAtMs;
  final Duration captureElapsed;
  final String? captureId;

  factory MonitorState.idle({DeviceKind? deviceKind}) {
    final names = electrodeNamesForKind(deviceKind);
    return MonitorState(
      kind: CaptureKind.idle,
      electrodeNames: names,
      channelCount: names.length,
    );
  }
}
