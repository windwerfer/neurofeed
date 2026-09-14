import 'package:muse_ml/src/feedback/session_metadata.dart';
import 'package:muse_ml/src/feedback/trust/trust_trace.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

/// Double-blink / double-clench detector for the live trust ring.
/// Persist is applied by the caller; detection always runs.
class TrustGestureTracker {
  DateTime lastBlinkAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastClenchAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool clenchWasActive = false;

  void reset() {
    lastBlinkAt = DateTime.fromMillisecondsSinceEpoch(0);
    lastClenchAt = DateTime.fromMillisecondsSinceEpoch(0);
    clenchWasActive = false;
  }

  List<GestureType> ingest(GestureDto g, DateTime now) {
    final out = <GestureType>[];
    if (g.blinkCount >= 2) {
      out.add(GestureType.doubleBlink);
      lastBlinkAt = DateTime.fromMillisecondsSinceEpoch(0);
    } else if (g.blinkCount > 0) {
      if (now.difference(lastBlinkAt) <= const Duration(seconds: 2)) {
        out.add(GestureType.doubleBlink);
        lastBlinkAt = DateTime.fromMillisecondsSinceEpoch(0);
      } else {
        lastBlinkAt = now;
      }
    }
    if (g.clench && !clenchWasActive) {
      if (now.difference(lastClenchAt) <= const Duration(seconds: 2)) {
        out.add(GestureType.doubleClench);
        lastClenchAt = DateTime.fromMillisecondsSinceEpoch(0);
      } else {
        lastClenchAt = now;
      }
    }
    clenchWasActive = g.clench;
    return out;
  }
}

void recordLiveMark({
  required TrustTrace live,
  required List<GestureMarker> persisted,
  required bool persistEnabled,
  required GestureType type,
  required double t,
}) {
  live.addMark(TrustGestureMark(t: t, type: type));
  if (persistEnabled) {
    persisted.add(GestureMarker(type: type, offsetSeconds: t.round()));
  }
}
