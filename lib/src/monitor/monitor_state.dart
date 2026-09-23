import 'package:flutter/foundation.dart';
import 'package:neurofeed/src/monitor/device_montage.dart';
import 'package:neurofeed/src/rust/api/device_config.dart';

export 'device_montage.dart';

enum CaptureKind { idle, tmp, recording, feedback }

@immutable
class MonitorState {
  const MonitorState({
    required this.kind,
    required this.electrodeNames,
    required this.channelCount,
    this.captureStartedAtMs,
    this.captureId,
    this.pendingScratchPath,
    this.graphEpoch = 0,
    this.graphResumeFollow = false,
    this.graphResetAnchors = false,
  });

  final CaptureKind kind;
  final List<String> electrodeNames;
  final int channelCount;
  final int? captureStartedAtMs;
  final String? captureId;

  /// Assembled `recording_$ts.neurofeed` waiting for Save / Discard.
  final String? pendingScratchPath;

  final int graphEpoch;
  final bool graphResumeFollow;
  final bool graphResetAnchors;

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
    Object? pendingScratchPath = _sentinel,
    int? graphEpoch,
    bool? graphResumeFollow,
    bool? graphResetAnchors,
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
    pendingScratchPath: identical(pendingScratchPath, _sentinel)
        ? this.pendingScratchPath
        : pendingScratchPath as String?,
    graphEpoch: graphEpoch ?? this.graphEpoch,
    graphResumeFollow: graphResumeFollow ?? this.graphResumeFollow,
    graphResetAnchors: graphResetAnchors ?? this.graphResetAnchors,
  );

  static const Object _sentinel = Object();
}


/// Live plot chrome while connected, or while an explicit recording is held
/// open across a BLE drop (dashed gaps / Follow keep running).
bool monitorGraphsLive({
  required CaptureKind kind,
  required bool connected,
}) =>
    connected || kind == CaptureKind.recording;
