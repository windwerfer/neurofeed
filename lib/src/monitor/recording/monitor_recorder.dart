import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/monitor/cache/file_backed_source.dart';
import 'package:muse_ml/src/monitor/cache/recording_index.dart';
import 'package:muse_ml/src/monitor/recording/recording_metadata.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/session_v5/assemble.dart';
import 'package:muse_ml/src/session_v5/computed_frame.dart';
import 'package:muse_ml/src/session_v5/scratch_writer.dart';
import 'package:muse_ml/src/settings.dart';

/// Connect-time `tmp_$ts` / explicit `recording_$ts` writer. tmp never
/// assembles. 30 min silent rotate is owned by [MonitorController] via
/// [onRotate]. [flushRaw] indexes the same [RecordingIndex] for both prefixes.
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
  static const Duration kRecordingWarn = Duration(hours: 2);

  final SessionRecorder _writer;
  final Duration tmpCap;
  final Duration sidecarInterval;
  final RecordingIndex index = RecordingIndex();

  Timer? _rotateTimer;
  Timer? _sidecarTimer;
  Timer? _warnTimer;
  RecordingMetadata Function()? _metadata;
  VoidCallback? onRotate;
  int? captureStartedAtMs;
  int? _lastEegTsMs;
  String _prefix = 'tmp';

  bool get isOpen => _writer.isRecording;

  String? get captureId => _writer.sessionId;

  String? get currentFilePath => _writer.currentFilePath;

  Directory? get tempDir => _writer.tempDir;

  String get prefix => _prefix;

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
  }) {
    return _start(
      dir: dir,
      prefix: 'tmp',
      recordStreams: recordStreams,
      metadata: metadata,
      captureStartedAtMs: captureStartedAtMs,
      rotate: true,
    );
  }

  Future<void> startRecording({
    required Directory dir,
    required Set<RecordingStream> recordStreams,
    required RecordingMetadata Function() metadata,
    required int captureStartedAtMs,
  }) {
    return _start(
      dir: dir,
      prefix: 'recording',
      recordStreams: recordStreams,
      metadata: metadata,
      captureStartedAtMs: captureStartedAtMs,
      rotate: false,
    );
  }

  Future<void> _start({
    required Directory dir,
    required String prefix,
    required Set<RecordingStream> recordStreams,
    required RecordingMetadata Function() metadata,
    required int captureStartedAtMs,
    required bool rotate,
  }) async {
    index.clear();
    _lastEegTsMs = null;
    this.captureStartedAtMs = captureStartedAtMs;
    _metadata = metadata;
    _prefix = prefix;
    _writer.recordStreams = recordStreams;
    await _writer.start(dir, prefix: prefix, sidecar: SidecarMode.snapshot);
    debugPrint(
      '[monitor] $prefix start id=${_writer.sessionId} '
      'recordStreams=${recordStreams.map((s) => s.name).toList()}',
    );
    await writeSidecarNow();
    _rotateTimer?.cancel();
    _rotateTimer = null;
    _warnTimer?.cancel();
    _warnTimer = null;
    if (rotate) {
      _rotateTimer = Timer(tmpCap, () {
        debugPrint('[monitor] tmp rotate');
        onRotate?.call();
      });
    } else {
      _warnTimer = Timer(kRecordingWarn, () {
        debugPrint('[monitor] recording 2h warning');
      });
    }
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

  /// Flush, write `recording_$id.muse.feedback` with [placeholderWebP], delete
  /// temps on success. Returns null if there was nothing to assemble or encode
  /// failed (temps are kept).
  Future<File?> assemble({required Map<String, Object?> metadataJson}) async {
    await writeSidecarNow();
    _rotateTimer?.cancel();
    _rotateTimer = null;
    _warnTimer?.cancel();
    _warnTimer = null;
    _sidecarTimer?.cancel();
    _sidecarTimer = null;
    await _writer.flush();
    _writer.stopPeriodicFlush();
    final temps = await _writer.readTemps();
    final id = _writer.sessionId;
    final dir = _writer.tempDir;
    if (temps == null || id == null || dir == null) {
      debugPrint('[monitor] assemble: no active recording');
      return null;
    }
    try {
      final file = await writeScratchV5(
        dir: dir,
        id: id,
        prefix: 'recording',
        metadataJson: metadataJson,
        rawBody: temps.raw,
        computedJsonl: temps.computed,
      );
      await _writer.cleanupTempFiles();
      _metadata = null;
      index.clear();
      _lastEegTsMs = null;
      captureStartedAtMs = null;
      debugPrint('[monitor] assemble ${file.path} (${file.lengthSync()}B)');
      return file;
    } catch (e, st) {
      debugPrint('[monitor] assemble failed: $e\n$st');
      return null;
    }
  }

  Future<void> discard() async {
    _rotateTimer?.cancel();
    _rotateTimer = null;
    _warnTimer?.cancel();
    _warnTimer = null;
    _sidecarTimer?.cancel();
    _sidecarTimer = null;
    _metadata = null;
    index.clear();
    _lastEegTsMs = null;
    captureStartedAtMs = null;
    final id = _writer.sessionId;
    final prefix = _prefix;
    await _writer.stop();
    debugPrint('[monitor] $prefix discard id=$id');
  }

  void _indexFlushedFrame(int fileLength) {
    final started = captureStartedAtMs;
    final ts = _lastEegTsMs;
    if (started == null || ts == null) return;
    index.add(elapsedT: (ts - started) / 1000.0, fileLength: fileLength);
  }
}
