import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:neurofeed/src/charts/eeg_data_source.dart';
import 'package:neurofeed/src/monitor/cache/frame_coalesced_notify.dart';
import 'package:neurofeed/src/rust/api/muse.dart';

/// Classic Muse PPG infrared channel index (ambient=0, IR=1, red=2).
const int kPpgInfraredChannel = 1;

/// Live Pulse / SpO2 / IR PPG rings for the HR+SpO2 monitor.
class OpticalCache extends ChangeNotifier with FrameCoalescedNotify {
  static const double ppgSampleRate = 64.0;
  static const int metricCapacity = 1800;
  static const int ppgCapacity = 64 * 300;

  final _MetricRing _pulse = _MetricRing(metricCapacity);
  final _MetricRing _spo2 = _MetricRing(metricCapacity);
  final _MetricRing _ppgIr = _MetricRing(ppgCapacity);

  double _pulseSum = 0;
  int _pulseN = 0;

  bool get hasPulse => _pulse.length > 0;
  bool get hasSpo2 => _spo2.length > 0;
  bool get hasPpg => _ppgIr.length > 0;
  bool get hasData => hasPulse || hasSpo2 || hasPpg;

  double get latestTimestamp {
    var latest = 0.0;
    for (final buf in [_pulse, _spo2, _ppgIr]) {
      if (buf.length > 0) {
        final t = buf.timestampAt(buf.length - 1);
        if (t > latest) latest = t;
      }
    }
    return latest;
  }

  double get oldestTimestamp {
    var oldest = double.infinity;
    for (final buf in [_pulse, _spo2, _ppgIr]) {
      if (buf.length > 0) {
        final t = buf.timestampAt(0);
        if (t < oldest) oldest = t;
      }
    }
    return oldest == double.infinity ? 0 : oldest;
  }

  /// Mean of every Pulse sample since [clear] (capture / tmp start).
  double? get avgHr => _pulseN > 0 ? _pulseSum / _pulseN : null;

  void appendPulse(PulseDto dto) {
    if (!dto.bpm.isFinite || dto.bpm <= 0) return;
    final t = dto.timestamp / 1000.0;
    _pulse.add(t, dto.bpm);
    _pulseSum += dto.bpm;
    _pulseN++;
    notifyListenersCoalesced();
  }

  void appendSpO2(SpO2Dto dto) {
    if (!dto.spo2.isFinite || dto.spo2 <= 0) return;
    _spo2.add(dto.timestamp / 1000.0, dto.spo2);
    notifyListenersCoalesced();
  }

  void appendPpg(PpgDto dto) {
    if (dto.channel != kPpgInfraredChannel) return;
    final n = dto.samples.length;
    if (n == 0) return;
    final endT = dto.timestamp / 1000.0;
    for (var i = 0; i < n; i++) {
      final t = endT - (n - 1 - i) / ppgSampleRate;
      final v = dto.samples[i];
      if (!v.isFinite) continue;
      _ppgIr.add(t, v);
    }
    notifyListenersCoalesced();
  }

  List<ChartSample> pulseRange(double startUnix, double endUnix) =>
      _pulse.range(startUnix, endUnix);

  List<ChartSample> spo2Range(double startUnix, double endUnix) =>
      _spo2.range(startUnix, endUnix);

  List<ChartSample> ppgIrRange(double startUnix, double endUnix) =>
      _ppgIr.range(startUnix, endUnix);

  void clear() {
    _pulse.clear();
    _spo2.clear();
    _ppgIr.clear();
    _pulseSum = 0;
    _pulseN = 0;
    notifyListeners();
  }
}

double opticalOriginUnix(OpticalCache cache, int? captureStartedAtMs) {
  if (captureStartedAtMs != null) {
    return captureStartedAtMs / 1000.0;
  }
  if (cache.hasData) return cache.oldestTimestamp;
  return 0;
}

class _MetricRing {
  final Float64List timestamps;
  final Float64List values;
  int _head = 0;
  int _count = 0;

  _MetricRing(int capacity)
    : timestamps = Float64List(capacity),
      values = Float64List(capacity);

  int get length => _count;

  void add(double t, double v) {
    timestamps[_head] = t;
    values[_head] = v;
    _head = (_head + 1) % timestamps.length;
    if (_count < timestamps.length) _count++;
  }

  void clear() {
    _head = 0;
    _count = 0;
  }

  int _physicalIndex(int i) =>
      (_head - _count + i + timestamps.length) % timestamps.length;

  double timestampAt(int i) => timestamps[_physicalIndex(i)];
  double valueAt(int i) => values[_physicalIndex(i)];

  int lowerBound(double t) {
    var lo = 0;
    var hi = _count;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (timestampAt(mid) < t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  int upperBound(double t) {
    var lo = 0;
    var hi = _count;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (timestampAt(mid) <= t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  List<ChartSample> range(double startT, double endT) {
    if (_count == 0) return const [];
    final lo = lowerBound(startT);
    final hi = upperBound(endT);
    if (lo >= hi) return const [];
    return List.generate(
      hi - lo,
      (i) => ChartSample(timestampAt(lo + i), valueAt(lo + i)),
    );
  }
}
