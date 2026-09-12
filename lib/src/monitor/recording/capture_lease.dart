import 'package:muse_ml/src/monitor/monitor_state.dart';

/// Exclusive capture owner. At most one scratch writer is open.
class CaptureLease {
  CaptureKind kind = CaptureKind.idle;

  bool tryBeginTmp() {
    if (kind != CaptureKind.idle) return false;
    kind = CaptureKind.tmp;
    return true;
  }

  bool tryDiscardTmp() {
    if (kind != CaptureKind.tmp) return false;
    kind = CaptureKind.idle;
    return true;
  }

  /// Grant the feedback session the writer. Refuses [CaptureKind.recording].
  /// Idempotent when already [CaptureKind.feedback].
  bool tryAcquireFeedback() {
    if (kind == CaptureKind.recording) return false;
    if (kind == CaptureKind.feedback) return true;
    kind = CaptureKind.feedback;
    return true;
  }

  /// Writer closed. Idempotent when not [CaptureKind.feedback].
  bool tryReleaseFeedback() {
    if (kind != CaptureKind.feedback) return false;
    kind = CaptureKind.idle;
    return true;
  }

  /// Record from idle or tmp. Refuses [CaptureKind.feedback] and an
  /// already-open recording.
  bool tryBeginRecording() {
    if (kind != CaptureKind.idle && kind != CaptureKind.tmp) return false;
    kind = CaptureKind.recording;
    return true;
  }

  /// Recording writer closed. Idempotent when not [CaptureKind.recording].
  bool tryReleaseRecording() {
    if (kind != CaptureKind.recording) return false;
    kind = CaptureKind.idle;
    return true;
  }
}
