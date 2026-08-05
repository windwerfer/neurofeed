import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/charts/session_recorder.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

/// Wraps [SessionRecorder] with session-aware lifecycle.
///
/// The continuous recorder runs during the entire connection and captures raw
/// EEG/PPG/IMU. The [FeedbackRecorder] starts/stops in sync with feedback
/// sessions and records only the 1Hz derived metrics (bands, pulse, movement,
/// peak alpha) plus the raw EEG for the session duration.
class FeedbackRecorder {
  final SessionRecorder _recorder = SessionRecorder();
  final Future<Directory> _sessionDir;

  FeedbackRecorder({Future<Directory>? sessionDir})
    : _sessionDir = sessionDir ?? defaultSessionDir();

  bool get isRecording => _recorder.isRecording;

  String? get currentFilePath => _recorder.currentFilePath;

  /// Begin a session recording. If one is already active, it is ended first.
  Future<void> startSession() async {
    await _recorder.stop();
    final dir = await _sessionDir;
    debugPrint('[feedback] startSession: dir=${dir.path}');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      debugPrint('[feedback] startSession: created dir');
    }
    await _recorder.start(dir);
  }

  /// Write a Muse event to the session recording.
  void writeEvent(MuseEventDto event) {
    _recorder.writeEvent(event);
  }

  /// Flush pending data to disk without finalizing the temp file.
  Future<void> flushSession() => _recorder.flush();

  /// Mark the session as saved (rename temp file to final name).
  Future<File?> saveSession() => _recorder.markSaved();

  /// Discard the session (delete temp file).
  Future<void> discardSession() async {
    await _recorder.stop();
  }
}
