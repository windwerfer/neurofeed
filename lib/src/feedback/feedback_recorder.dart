import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:neurofeed/src/session_format/computed_frame.dart';
import 'package:neurofeed/src/spine/assemble.dart';
import 'package:neurofeed/src/spine/scratch_writer.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';
import 'package:neurofeed/src/rust/api/muse.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/spine/capture_client.dart' as spine;

/// Wraps [SessionRecorder] with session-aware lifecycle.
///
/// Live writes always go to the fast scratch directory — SAF is only touched
/// on Save. At session end, [assembleScratch] writes a real `.neurofeed` (NFED6)
/// next to the temps, then deletes the temps on success.
class FeedbackRecorder {
  FeedbackRecorder({Future<SessionStorage>? storage})
    : _storage = storage ?? _defaultStorage();

  final Future<SessionStorage> _storage;
  final SessionRecorder _recorder = SessionRecorder();
  String? _scratchPath;
  String? _attachedId;

  static Future<SessionStorage> _defaultStorage() async {
    return FileSystemSessionStorage(await defaultSessionDir());
  }

  bool get isRecording => _recorder.isRecording;

  bool get usesRustCapture => _recorder.usesRustCapture;

  String? get currentFilePath => _scratchPath ?? _recorder.currentFilePath;

  String? get scratchPath => _scratchPath;

  String? get sessionId => _recorder.sessionId ?? _attachedId;

  /// Point at an already-assembled scratch `.neurofeed` (process restart / leftover).
  void attachAssembledScratch({required String id, required String path}) {
    _attachedId = id;
    _scratchPath = path;
  }

  /// Electrode indices that produced data in the current session recording.
  Set<int> get recordedChannels => _recorder.usesRustCapture
      ? spine.recordedChannelSet()
      : Set.unmodifiable(_recorder.channels);

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

  /// Pause/resume Rust raw capture for this session.
  void setRawPaused(bool paused) => _recorder.setRawPaused(paused);

  /// Write a metadata event (calibration step, guardrail event, etc.) as JSON line.
  void writeMetadata(Map<String, dynamic> meta) {
    _recorder.writeMetadata(meta);
  }

  /// Flush pending data to disk without assembling the container.
  Future<void> flushSession() => _recorder.flush();

  /// Flush temps, encode a `.neurofeed` (NFED6) into scratch, delete temps on success.
  /// Returns the scratch path, or null if there was nothing to assemble or
  /// encoding failed (temps are kept so crash recovery can retry).
  Future<String?> assembleScratch(Map<String, Object?> metadataJson) async {
    await _recorder.flush();
    _recorder.stopPeriodicFlush();
    final id = _recorder.sessionId;
    final dir = _recorder.tempDir;
    final rawPath = _recorder.rawPath;
    if (id == null || dir == null || rawPath == null) {
      debugPrint('[feedback] assembleScratch: no active recording');
      return null;
    }
    try {
      final File file;
      if (_recorder.usesRustCapture) {
        file = await spine.assembleCapture(metadataJson: metadataJson);
        _recorder.detachAfterAssemble();
      } else {
        file = await writeScratch(
          dir: dir,
          id: id,
          metadataJson: metadataJson,
          rawPath: rawPath,
          computedPath: _recorder.computedPath,
        );
        await _recorder.cleanupTempFiles();
      }
      _scratchPath = file.path;
      debugPrint(
        '[feedback] assembleScratch: ${file.path} (${file.lengthSync()}B)',
      );
      return file.path;
    } catch (e, st) {
      debugPrint('[feedback] assembleScratch failed: $e\n$st');
      return null;
    }
  }

  /// Delete the scratch `.neurofeed` (after a successful publish, or on discard).
  Future<void> deleteScratch() async {
    final path = _scratchPath;
    _scratchPath = null;
    _attachedId = null;
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (e) {
        debugPrint('[feedback] deleteScratch failed: $e');
      }
    }
  }

  /// Discard the session (delete temps and any scratch `.neurofeed`).
  Future<void> discardSession() async {
    await _recorder.stop();
    await deleteScratch();
  }

  /// Get collected computed frames for container assembly.
  List<ComputedFrame> get computedFrames => _recorder.computedFrames;

  /// Clear computed frames after container assembly.
  void clearComputedFrames() => _recorder.clearComputedFrames();
}
