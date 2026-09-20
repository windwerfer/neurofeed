import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:neurofeed/src/monitor/cache/file_backed_source.dart';
import 'package:neurofeed/src/monitor/cache/recording_index.dart';
import 'package:neurofeed/src/monitor/recording/recording_metadata.dart';
import 'package:neurofeed/src/rust/api/muse.dart';
import 'package:neurofeed/src/session_v5/computed_frame.dart';
import 'package:neurofeed/src/spine/assemble.dart';
import 'package:neurofeed/src/spine/scratch_writer.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/spine/capture_client.dart' as spine;

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

  bool get usesRustCapture => _writer.usesRustCapture;

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
    await _writer.start(
      dir,
      prefix: prefix,
      sidecar: SidecarMode.snapshot,
      startedAtMs: captureStartedAtMs,
    );
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
      if (_writer.usesRustCapture) {
        _syncIndexFromRust();
      }
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

  Future<void> flushRaw() async {
    await _writer.flushRaw();
    if (_writer.usesRustCapture) {
      _syncIndexFromRust();
    }
  }

  /// Flush, write `recording_$id.neurofeed` with [placeholderWebP], delete
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
    final id = _writer.sessionId;
    final dir = _writer.tempDir;
    final rawPath = _writer.rawPath;
    if (id == null || dir == null || rawPath == null) {
      debugPrint('[monitor] assemble: no active recording');
      return null;
    }
    try {
      final File file;
      if (_writer.usesRustCapture) {
        file = await spine.assembleCaptureV5(metadataJson: metadataJson);
        _writer.detachAfterAssemble();
      } else {
        file = await writeScratchV5(
          dir: dir,
          id: id,
          prefix: 'recording',
          metadataJson: metadataJson,
          rawPath: rawPath,
          computedPath: _writer.computedPath,
        );
        await _writer.cleanupTempFiles();
      }
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
    if (_writer.usesRustCapture) {
      _syncIndexFromRust();
      return;
    }
    final started = captureStartedAtMs;
    final ts = _lastEegTsMs;
    if (started == null || ts == null) return;
    index.add(elapsedT: (ts - started) / 1000.0, fileLength: fileLength);
  }

  void _syncIndexFromRust() {
    spine.syncRecordingIndex(clear: index.clear, add: index.add);
  }
}
