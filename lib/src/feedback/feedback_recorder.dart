import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/charts/session_recorder.dart';
import 'package:muse_ml/src/feedback/computed_frame.dart';
import 'package:muse_ml/src/feedback/session_assembler.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/settings.dart';

/// Wraps [SessionRecorder] with session-aware lifecycle.
///
/// Live writes always go to the fast scratch directory — SAF is only touched
/// on Save. At session end, [assembleScratchV5] writes a real v5 container
/// next to the temps, then deletes the temps on success.
class FeedbackRecorder {
  FeedbackRecorder({Future<SessionStorage>? storage})
      : _storage = storage ?? _defaultStorage();

  final Future<SessionStorage> _storage;
  final SessionRecorder _recorder = SessionRecorder();
  String? _scratchV5Path;

  static Future<SessionStorage> _defaultStorage() async {
    return FileSystemSessionStorage(await defaultSessionDir());
  }

  bool get isRecording => _recorder.isRecording;

  String? get currentFilePath => _scratchV5Path ?? _recorder.currentFilePath;

  String? get scratchV5Path => _scratchV5Path;

  String? get sessionId => _recorder.sessionId;

  /// Electrode indices that produced data in the current session recording.
  Set<int> get recordedChannels => Set.unmodifiable(_recorder.channels);

  /// Streams this recorder is set to persist.
  Set<RecordingStream> get streams => Set.unmodifiable(_recorder.recordStreams);

  /// Streams to persist into the session file. Applied before [startSession]
  /// so the recorder only writes the user-selected data types.
  void setRecordStreams(Set<RecordingStream> streams) {
    _recorder.recordStreams = streams;
  }

  /// Begin a session recording in the scratch directory. If one is already
  /// active, it is ended first.
  Future<void> startSession() async {
    await discardSession();
    final storage = await _storage;
    await storage.ensureDir();
    final dir = scratchDirectory(storage);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      debugPrint('[feedback] startSession: created scratch $dir');
    }
    debugPrint('[feedback] startSession: scratch=${dir.path}');
    await _recorder.start(dir);
  }

  /// Write a Muse event to the session recording.
  void writeEvent(MuseEventDto event) {
    _recorder.writeEvent(event);
  }

  /// Add a computed frame (1 Hz) to the session recording.
  void appendComputed(ComputedFrame frame) {
    _recorder.appendComputed(frame);
  }

  /// Write a metadata event (calibration step, guardrail event, etc.) as JSON line.
  void writeMetadata(Map<String, dynamic> meta) {
    _recorder.writeMetadata(meta);
  }

  /// Flush pending data to disk without assembling the container.
  Future<void> flushSession() => _recorder.flush();

  /// Flush temps, encode a v5 container into scratch, delete temps on success.
  /// Returns the scratch path, or null if there was nothing to assemble or
  /// encoding failed (temps are kept so crash recovery can retry).
  Future<String?> assembleScratchV5(Map<String, Object?> metadataJson) async {
    await _recorder.flush();
    _recorder.stopPeriodicFlush();
    final temps = await _recorder.readTemps();
    final id = _recorder.sessionId;
    final dir = _recorder.tempDir;
    if (temps == null || id == null || dir == null) {
      debugPrint('[feedback] assembleScratchV5: no active recording');
      return null;
    }
    try {
      final file = await writeScratchV5(
        dir: dir,
        id: id,
        metadataJson: metadataJson,
        rawBody: temps.raw,
        computedJsonl: temps.computed,
      );
      await _recorder.cleanupTempFiles();
      _scratchV5Path = file.path;
      debugPrint(
        '[feedback] assembleScratchV5: ${file.path} (${file.lengthSync()}B)',
      );
      return file.path;
    } catch (e, st) {
      debugPrint('[feedback] assembleScratchV5 failed: $e\n$st');
      return null;
    }
  }

  /// Delete the scratch v5 (after a successful publish, or on discard).
  Future<void> deleteScratchV5() async {
    final path = _scratchV5Path;
    _scratchV5Path = null;
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (e) {
        debugPrint('[feedback] deleteScratchV5 failed: $e');
      }
    }
  }

  /// Discard the session (delete temps and any scratch v5).
  Future<void> discardSession() async {
    await _recorder.stop();
    await deleteScratchV5();
  }

  /// Get collected computed frames for v5 format assembly.
  List<ComputedFrame> get computedFrames => _recorder.computedFrames;

  /// Clear computed frames after v5 assembly.
  void clearComputedFrames() => _recorder.clearComputedFrames();
}
