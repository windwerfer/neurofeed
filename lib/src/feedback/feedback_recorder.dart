import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/charts/session_recorder.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

/// Wraps [SessionRecorder] with session-aware lifecycle.
///
/// The continuous recorder runs during the entire connection and captures raw
/// EEG/PPG/IMU. The [FeedbackRecorder] starts/stops in sync with feedback
/// sessions and records only the 1Hz derived metrics (bands, pulse, movement,
/// peak alpha) plus the raw EEG for the session duration. Live writes always
/// go to the fast scratch directory — SAF is only touched on Save.
class FeedbackRecorder {
  FeedbackRecorder({SessionStorage? storage})
    : _scratch = _scratchDir(storage);

  final Future<Directory> _scratch;
  final SessionRecorder _recorder = SessionRecorder();

  static Future<Directory> _scratchDir(SessionStorage? storage) async {
    if (storage != null) return scratchDirectory(storage);
    return Directory('${Directory.systemTemp.path}/muse_scratch');
  }

  bool get isRecording => _recorder.isRecording;

  String? get currentFilePath => _recorder.currentFilePath;

  /// Begin a session recording in the scratch directory. If one is already
  /// active, it is ended first.
  Future<void> startSession() async {
    await _recorder.stop();
    final dir = await _scratch;
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

  /// Flush pending data to disk without finalizing the temp file.
  Future<void> flushSession() => _recorder.flush();

  /// Mark the session as saved (rename temp file to final name). Returns the
  /// finalized scratch file on disk.
  Future<File?> saveSession() => _recorder.markSaved();

  /// Discard the session (delete temp file).
  Future<void> discardSession() async {
    await _recorder.stop();
  }
}