import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/monitor/cache/file_backed_source.dart';
import 'package:muse_ml/src/monitor/cache/recording_index.dart';
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
  }) : _writer = writer ?? SessionRecorder() {
    _writer.onRawFlushed = _indexFlushedFrame;
  }

  static const Duration kTmpCap = Duration(minutes: 30);
  static const Duration kSidecarInterval = Duration(seconds: 5);

  final SessionRecorder _writer;
  final Duration tmpCap;
  final Duration sidecarInterval;
  final RecordingIndex index = RecordingIndex();

  Timer? _rotateTimer;
  Timer? _sidecarTimer;
  RecordingMetadata Function()? _metadata;
  VoidCallback? onRotate;
  int? captureStartedAtMs;
  int? _lastEegTsMs;

  bool get isOpen => _writer.isRecording;

  String? get captureId => _writer.sessionId;

  String? get currentFilePath => _writer.currentFilePath;

  Directory? get tempDir => _writer.tempDir;

  Set<RecordingStream> get recordStreams => _writer.recordStreams;

  FileBackedSource? get source {
    if (!isOpen) return null;
    final path = currentFilePath;
    if (path == null) return null;
    return FileBackedSource(
      file: File(path),
      index: index,
      captureStartedAtMs: captureStartedAtMs,
    );
  }

  Future<void> startTmp({
    required Directory dir,
    required Set<RecordingStream> recordStreams,
    required RecordingMetadata Function() metadata,
    required int captureStartedAtMs,
  }) async {
    index.clear();
    _lastEegTsMs = null;
    this.captureStartedAtMs = captureStartedAtMs;
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

  void writeEvent(MuseEventDto event) {
    switch (event) {
      case MuseEventDto_Eeg():
        if (_writer.recordStreams.contains(RecordingStream.eeg)) {
          _lastEegTsMs = event.field0.timestamp.round();
        }
      default:
        break;
    }
    _writer.writeEvent(event);
  }

  void appendComputed(ComputedFrame frame) => _writer.appendComputed(frame);

  void flushRaw() => _writer.flushRaw();

  Future<void> discard() async {
    _rotateTimer?.cancel();
    _rotateTimer = null;
    _sidecarTimer?.cancel();
    _sidecarTimer = null;
    _metadata = null;
    index.clear();
    _lastEegTsMs = null;
    captureStartedAtMs = null;
    final id = _writer.sessionId;
    await _writer.stop();
    debugPrint('[monitor] tmp discard id=$id');
  }

  void _indexFlushedFrame(int fileLength) {
    final started = captureStartedAtMs;
    final ts = _lastEegTsMs;
    if (started == null || ts == null) return;
    index.add(elapsedT: (ts - started) / 1000.0, fileLength: fileLength);
  }
}
