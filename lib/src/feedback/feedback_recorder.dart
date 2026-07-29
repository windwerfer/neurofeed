import 'dart:async';
import 'dart:io';
import 'package:muse_ml/src/charts/session_recorder.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

/// Wraps [SessionRecorder] with session-aware lifecycle.
///
/// The continuous recorder runs during the entire connection and captures raw
/// EEG/PPG/IMU. The [FeedbackRecorder] starts/stops in sync with feedback
/// sessions and records only the 1Hz derived metrics (bands, pulse, movement,
/// peak alpha) plus the raw EEG for the session duration.
class FeedbackRecorder {
  final SessionRecorder _recorder = SessionRecorder();
  final Directory _sessionDir;

  FeedbackRecorder({Directory? sessionDir})
    : _sessionDir = sessionDir ?? Directory.systemTemp;

  bool get isRecording => _recorder.isRecording;

  /// Begin a session recording. If one is already active, it is ended first.
  Future<void> startSession() async {
    await _recorder.stop();
    await _recorder.start(_sessionDir);
  }

  /// Write a Muse event to the session recording.
  void writeEvent(MuseEventDto event) {
    _recorder.writeEvent(event);
  }

  /// Mark the session as saved (rename temp file to final name).
  Future<void> saveSession() async {
    await _recorder.markSaved();
  }

  /// Discard the session (delete temp file).
  Future<void> discardSession() async {
    await _recorder.stop();
  }
}
