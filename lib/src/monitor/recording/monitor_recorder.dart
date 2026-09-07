import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/monitor/recording/recording_metadata.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/session_v5/computed_frame.dart';
import 'package:muse_ml/src/session_v5/scratch_writer.dart';
import 'package:muse_ml/src/settings.dart';

/// Connect-time `tmp_$ts` writer. Never assembles. 30 min silent rotate is
/// owned by [MonitorController] via [onRotate].
class MonitorRecorder {
  MonitorRecorder({
    SessionRecorder? writer,
    this.tmpCap = kTmpCap,
    this.sidecarInterval = kSidecarInterval,
  }) : _writer = writer ?? SessionRecorder();

  static const Duration kTmpCap = Duration(minutes: 30);
  static const Duration kSidecarInterval = Duration(seconds: 5);

  final SessionRecorder _writer;
  final Duration tmpCap;
  final Duration sidecarInterval;

  Timer? _rotateTimer;
  Timer? _sidecarTimer;
  RecordingMetadata Function()? _metadata;
  VoidCallback? onRotate;

  bool get isOpen => _writer.isRecording;

  String? get captureId => _writer.sessionId;

  Directory? get tempDir => _writer.tempDir;

  Set<RecordingStream> get recordStreams => _writer.recordStreams;

  Future<void> startTmp({
    required Directory dir,
    required Set<RecordingStream> recordStreams,
    required RecordingMetadata Function() metadata,
  }) async {
    _metadata = metadata;
    _writer.recordStreams = recordStreams;
    await _writer.start(dir, prefix: 'tmp', sidecar: SidecarMode.snapshot);
    debugPrint(
      '[monitor] tmp start id=${_writer.sessionId} '
      'recordStreams=${recordStreams.map((s) => s.name).toList()}',
    );
    await writeSidecarNow();
    _rotateTimer?.cancel();
    _rotateTimer = Timer(tmpCap, () {
      debugPrint('[monitor] tmp rotate');
      onRotate?.call();
    });
    _sidecarTimer?.cancel();
    _sidecarTimer = Timer.periodic(sidecarInterval, (_) {
      unawaited(writeSidecarNow());
    });
  }

  Future<void> writeSidecarNow() async {
    final build = _metadata;
    if (build == null) return;
    await _writer.writeSidecarSnapshot(build().toJson());
  }

  void writeEvent(MuseEventDto event) => _writer.writeEvent(event);

  void appendComputed(ComputedFrame frame) => _writer.appendComputed(frame);

  Future<void> discard() async {
    _rotateTimer?.cancel();
    _rotateTimer = null;
    _sidecarTimer?.cancel();
    _sidecarTimer = null;
    _metadata = null;
    final id = _writer.sessionId;
    await _writer.stop();
    debugPrint('[monitor] tmp discard id=$id');
  }
}
