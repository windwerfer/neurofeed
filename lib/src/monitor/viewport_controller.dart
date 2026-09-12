import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';

enum ViewportMode { follow, inspect }

class ViewportController extends ChangeNotifier {
  static const double defaultWindowSeconds = 10;
  static const int defaultWindowSamples = 2560;
  static const List<double> eegWindowOptions = [2, 4, 8, 10];
  static const double bandsDefaultWindowSeconds = 30;
  static const List<double> bandsWindowOptions = [15, 30, 60, 120];
  static const double bandsZoomFloor = 5;
  static const double bandsZoomCap = 1800;
  static const double histogramDefaultWindowSeconds = 8;
  static const double psdDefaultWindowSeconds = 4;
  static const List<double> histogramPsdWindowOptions = [2, 4, 8];
  static const double spectrogramDefaultWindowSeconds = 20;
  static const List<double> spectrogramWindowOptions = [10, 20, 30, 120, 300];
  static const double spectrogramZoomFloor = 5;
  static const double spectrogramZoomCap = 300;

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

  void followStrip() {
    if (mode == ViewportMode.follow) return;
    mode = ViewportMode.follow;
    inspectStartElapsed = null;
    notifyListeners();
  }

  void enterInspectStrip({required double newestElapsed}) {
    if (mode == ViewportMode.inspect && inspectStartElapsed != null) return;
    mode = ViewportMode.inspect;
    inspectStartElapsed = newestElapsed - windowSeconds;
    notifyListeners();
  }

  void setStripWindowSeconds(double secs, {double? newestElapsed}) {
    windowSeconds = secs;
    if (mode == ViewportMode.inspect && newestElapsed != null) {
      inspectStartElapsed = _clampStripStart(
        inspectStartElapsed ?? newestElapsed - secs,
        newestElapsed: newestElapsed,
        oldestElapsed: 0,
      );
    }
    notifyListeners();
  }

  double stripVisibleStart({required double newestElapsed}) {
    if (mode == ViewportMode.follow) {
      return newestElapsed - windowSeconds;
    }
    return inspectStartElapsed ?? newestElapsed - windowSeconds;
  }

  double stripVisibleEnd({required double newestElapsed}) =>
      stripVisibleStart(newestElapsed: newestElapsed) + windowSeconds;

  void panStrip(
    double deltaSeconds, {
    required double newestElapsed,
    double oldestElapsed = 0,
  }) {
    if (mode != ViewportMode.inspect) return;
    final start =
        (inspectStartElapsed ?? newestElapsed - windowSeconds) + deltaSeconds;
    inspectStartElapsed = _clampStripStart(
      start,
      newestElapsed: newestElapsed,
      oldestElapsed: oldestElapsed,
    );
    notifyListeners();
  }

  void pinchX({
    required double scaleFromStart,
    required double windowAtStart,
    required double focalElapsed,
    required double focalFraction,
    required double newestElapsed,
    required double elapsedCap,
    double oldestElapsed = 0,
    double zoomFloor = bandsZoomFloor,
    double zoomCap = bandsZoomCap,
  }) {
    if (scaleFromStart <= 0 || !scaleFromStart.isFinite) return;
    if (mode != ViewportMode.inspect) {
      mode = ViewportMode.inspect;
    }
    final cap = math.max(zoomFloor, math.min(elapsedCap, zoomCap));
    var next = windowAtStart / scaleFromStart;
    if (next < zoomFloor) next = zoomFloor;
    if (next > cap) next = cap;
    windowSeconds = next;
    inspectStartElapsed = _clampStripStart(
      focalElapsed - focalFraction * next,
      newestElapsed: newestElapsed,
      oldestElapsed: oldestElapsed,
    );
    notifyListeners();
  }

  double _clampStripStart(
    double start, {
    required double newestElapsed,
    required double oldestElapsed,
  }) {
    final minStart = oldestElapsed;
    final maxStart = newestElapsed - windowSeconds;
    if (maxStart < minStart) {
      if (start < maxStart) return maxStart;
      if (start > minStart) return minStart;
      return start;
    }
    if (start < minStart) return minStart;
    if (start > maxStart) return maxStart;
    return start;
  }
}

bool windowIsPreset(double seconds, List<double> options) {
  for (final o in options) {
    if ((o - seconds).abs() < 1e-6) return true;
  }
  return false;
}

double presetOrCustomValue(double seconds, List<double> options) {
  for (final o in options) {
    if ((o - seconds).abs() < 1e-6) return o;
  }
  return seconds;
}

String formatWindowSeconds(double seconds) => '${seconds.round()}s';

String formatSpectrogramWindow(double seconds) {
  if (seconds >= 60 && (seconds % 60).abs() < 1e-6) {
    return '${(seconds / 60).round()}min';
  }
  return formatWindowSeconds(seconds);
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
