import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';

enum ViewportMode { follow, inspect }

class ViewportController extends ChangeNotifier {
  static const double defaultWindowSeconds = 10;
  static const int defaultWindowSamples = 2560;
  static const List<double> eegWindowOptions = [2, 4, 8, 10];

  ViewportMode mode = ViewportMode.follow;
  double windowSeconds = defaultWindowSeconds;

  /// Left-edge elapsed seconds while Inspecting. Null in Follow.
  double? inspectStartElapsed;

  int get windowSamples => (windowSeconds * SweepBuffer.sampleRate).round();

  void follow(SweepBuffer buffer) {
    if (mode == ViewportMode.follow && !buffer.frozen) return;
    buffer.resume();
    mode = ViewportMode.follow;
    inspectStartElapsed = null;
    if (buffer.displayWindow != windowSamples) {
      buffer.setDisplayWindow(windowSamples);
    }
    notifyListeners();
  }

  /// HOLD: wipe + previous pass vanish; origin stays put; new samples fill
  /// the blank to the right until the window edge.
  void enterInspectFromSweep(SweepBuffer buffer, {double? newestElapsed}) {
    buffer.freeze();
    mode = ViewportMode.inspect;
    final window = buffer.displayWindow;
    final cursor = window <= 0 ? 0 : buffer.cursor % window;
    if (newestElapsed != null) {
      inspectStartElapsed = cursor <= 0
          ? newestElapsed
          : newestElapsed - (cursor - 1) / SweepBuffer.sampleRate;
    } else {
      inspectStartElapsed =
          (buffer.sampleCount - cursor) / SweepBuffer.sampleRate;
    }
    if (inspectStartElapsed! < 0) inspectStartElapsed = 0;
    notifyListeners();
  }

  void setWindowSeconds(double secs, SweepBuffer buffer) {
    if (windowSeconds == secs) {
      if (mode == ViewportMode.follow) {
        buffer.setDisplayWindow(windowSamples);
      }
      return;
    }
    windowSeconds = secs;
    if (mode == ViewportMode.follow) {
      buffer.setDisplayWindow(windowSamples);
    }
    notifyListeners();
  }

  /// Shift the Inspect window. Negative [deltaSeconds] is older (pan left).
  void panSeconds(double deltaSeconds, {double? newestElapsed}) {
    if (mode != ViewportMode.inspect) return;
    var start = (inspectStartElapsed ?? 0) + deltaSeconds;
    if (start < 0) start = 0;
    if (newestElapsed != null && start > newestElapsed) {
      start = newestElapsed < 0 ? 0 : newestElapsed;
    }
    inspectStartElapsed = start;
    notifyListeners();
  }
}

/// Format elapsed-from-capture for the EEG x-axis (`m:ss`, or `h:mm:ss`).
String formatElapsed(double seconds) {
  var s = seconds.isFinite ? seconds : 0.0;
  if (s < 0) s = 0;
  final total = s.floor();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final r = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }
  return '$m:${r.toString().padLeft(2, '0')}';
}

/// Comfortably spaced tick times in `[start, end]`, at least [minPx] apart.
List<double> elapsedTicks({
  required double start,
  required double end,
  required double widthPx,
  double minPx = 80,
}) {
  final span = end - start;
  if (span <= 0 || widthPx <= 0) return const [];
  const nice = [1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 60.0, 120.0, 300.0];
  final maxTicks = (widthPx / minPx).floor().clamp(2, 12);
  var step = nice.last;
  for (final n in nice) {
    if (span / n <= maxTicks) {
      step = n;
      break;
    }
  }
  final first = (start / step).ceil() * step;
  final ticks = <double>[];
  for (var t = first; t <= end + 1e-9; t += step) {
    ticks.add(t);
  }
  return ticks;
}

/// Inspect uses the tmp/recording file when the window starts older than
/// the SweepBuffer RAM ring. Null [captureStartedAtMs] never means unix epoch.
bool inspectNeedsFileBacked({
  required double startElapsed,
  required int ramCount,
  required double? ramNewestElapsed,
  required int? captureStartedAtMs,
}) {
  if (captureStartedAtMs == null) return false;
  if (ramNewestElapsed == null) return false;
  if (ramCount <= 0) return true;
  final oldest = ramNewestElapsed - (ramCount - 1) / SweepBuffer.sampleRate;
  return startElapsed < oldest;
}

T? inspectFileRange<T>({
  required double startElapsed,
  required double endElapsed,
  required int ramCount,
  required double? ramNewestElapsed,
  required int? captureStartedAtMs,
  required T? Function(double start, double end) getRange,
}) {
  if (!inspectNeedsFileBacked(
    startElapsed: startElapsed,
    ramCount: ramCount,
    ramNewestElapsed: ramNewestElapsed,
    captureStartedAtMs: captureStartedAtMs,
  )) {
    return null;
  }
  return getRange(startElapsed, endElapsed);
}

int? ramIndexForElapsed({
  required double elapsed,
  required int ramCount,
  required double? ramNewestElapsed,
}) {
  if (ramCount <= 0) return null;
  if (ramNewestElapsed == null) {
    final i = (elapsed * SweepBuffer.sampleRate).round();
    if (i < 0 || i >= ramCount) return null;
    return i;
  }
  final i =
      ramCount -
      1 -
      ((ramNewestElapsed - elapsed) * SweepBuffer.sampleRate).round();
  if (i < 0 || i >= ramCount) return null;
  return i;
}
