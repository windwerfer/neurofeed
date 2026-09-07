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
    this.captureId,
  });

  final CaptureKind kind;
  final List<String> electrodeNames;
  final int channelCount;
  final int? captureStartedAtMs;
  final String? captureId;

  Duration get captureElapsed {
    final start = captureStartedAtMs;
    if (start == null) return Duration.zero;
    final ms = DateTime.now().millisecondsSinceEpoch - start;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  double get captureElapsedSeconds => captureElapsed.inMilliseconds / 1000.0;

  factory MonitorState.idle({DeviceKind? deviceKind}) {
    final names = electrodeNamesForKind(deviceKind);
    return MonitorState(
      kind: CaptureKind.idle,
      electrodeNames: names,
      channelCount: names.length,
    );
  }

  MonitorState copyWith({
    CaptureKind? kind,
    List<String>? electrodeNames,
    int? channelCount,
    Object? captureStartedAtMs = _sentinel,
    Object? captureId = _sentinel,
  }) => MonitorState(
    kind: kind ?? this.kind,
    electrodeNames: electrodeNames ?? this.electrodeNames,
    channelCount: channelCount ?? this.channelCount,
    captureStartedAtMs: identical(captureStartedAtMs, _sentinel)
        ? this.captureStartedAtMs
        : captureStartedAtMs as int?,
    captureId: identical(captureId, _sentinel)
        ? this.captureId
        : captureId as String?,
  );

  static const Object _sentinel = Object();
}
