import 'package:flutter/foundation.dart';

/// Follow-only window for trust graphs. Pinch / Ctrl+scroll zoom; never Inspect.
class TrustViewport extends ChangeNotifier {
  static const double defaultWindowSeconds = 75;
  static const double minWindowSeconds = 15;
  static const double maxWindowSeconds = 300;
  static const double followLeadSeconds = 1.0;

  TrustViewport({double? windowSeconds})
    : windowSeconds = (windowSeconds ?? defaultWindowSeconds).clamp(
        minWindowSeconds,
        maxWindowSeconds,
      );

  double windowSeconds;
  double? _sampleAnchor;
  double? _wallAnchor;

  void setWindowSeconds(double secs) {
    final next = secs.clamp(minWindowSeconds, maxWindowSeconds).toDouble();
    if (next == windowSeconds) return;
    windowSeconds = next;
    notifyListeners();
  }

  /// Scale the window. Right edge stays now (Follow).
  void pinch({required double scaleFromStart, required double windowAtStart}) {
    if (scaleFromStart <= 0 || !scaleFromStart.isFinite) return;
    setWindowSeconds(windowAtStart / scaleFromStart);
  }

  void zoomBy(double factor) {
    if (factor <= 0 || !factor.isFinite) return;
    setWindowSeconds(windowSeconds * factor);
  }

  void noteSample(double newestElapsed, {double? wallNow}) {
    final now = wallNow ?? DateTime.now().millisecondsSinceEpoch / 1000.0;
    if (_sampleAnchor == null || _wallAnchor == null) {
      _sampleAnchor = newestElapsed;
      _wallAnchor = now;
      return;
    }
    if ((newestElapsed - _sampleAnchor!).abs() < 1e-12) return;
    _wallAnchor = _wallAnchor! + (newestElapsed - _sampleAnchor!);
    _sampleAnchor = newestElapsed;
  }

  void resetFollowAnchors() {
    _sampleAnchor = null;
    _wallAnchor = null;
  }

  double followNewest(double newestElapsed, {double? wallNow}) {
    if (followLeadSeconds <= 0) return newestElapsed;
    final now = wallNow ?? DateTime.now().millisecondsSinceEpoch / 1000.0;
    if (_sampleAnchor == null || _wallAnchor == null) {
      return newestElapsed - followLeadSeconds;
    }
    return _sampleAnchor! + (now - _wallAnchor!) - followLeadSeconds;
  }

  double visibleEnd(double newestElapsed, {double? wallNow}) =>
      followNewest(newestElapsed, wallNow: wallNow);

  double visibleStart(double newestElapsed, {double? wallNow}) =>
      visibleEnd(newestElapsed, wallNow: wallNow) - windowSeconds;

  bool get rightEdgeIsNow => true;
}
