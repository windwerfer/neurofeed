import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/charts/eeg_data_source.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

class LiveCache extends ChangeNotifier implements EegDataSource {
  static const int _durationSecs = 300;
  static const double _sampleRate = 256.0;

  final int _maxSamples;
  final Map<int, _RingChannel> _channels = {};

  LiveCache() : _maxSamples = (_durationSecs * _sampleRate).toInt();

  @override
  double get maxTimeWindowSecs => _durationSecs.toDouble();

  int get maxSamples => _maxSamples;

  void appendEeg(EegDto dto) {
    final buf =
        _channels.putIfAbsent(dto.electrode, () => _RingChannel(_maxSamples));
    final dt = 1.0 / _sampleRate;
    final baseSecs = dto.timestamp / 1000.0;
    for (int i = 0; i < dto.samples.length; i++) {
      buf.add(baseSecs + i * dt, dto.samples[i]);
    }
    notifyListeners();
  }

  @override
  List<int> get channels => _channels.keys.toList()..sort();

  @override
  bool get hasData => _channels.isNotEmpty;

  @override
  double get latestTimestamp {
    double latest = 0;
    for (final buf in _channels.values) {
      if (buf.length > 0 && buf.timestampAt(buf.length - 1) > latest) {
        latest = buf.timestampAt(buf.length - 1);
      }
    }
    return latest;
  }

  @override
  double get oldestTimestamp {
    double oldest = double.infinity;
    for (final buf in _channels.values) {
      if (buf.length > 0 && buf.timestampAt(0) < oldest) {
        oldest = buf.timestampAt(0);
      }
    }
    return oldest == double.infinity ? 0 : oldest;
  }

  @override
  List<ChartSample> getRange(int channel, double startT, double endT) {
    final buf = _channels[channel];
    if (buf == null || buf.length == 0) return const [];
    final lo = buf.lowerBound(startT);
    final hi = buf.upperBound(endT);
    if (lo >= hi) return const [];
    return List.generate(
        hi - lo, (i) => ChartSample(buf.timestampAt(lo + i), buf.valueAt(lo + i)));
  }

  @override
  List<SeriesSlice> slices({
    required double startT,
    required double endT,
    required Set<int> hiddenChannels,
  }) {
    final result = <SeriesSlice>[];
    for (final ch in channels) {
      final hidden = hiddenChannels.contains(ch);
      result.add(SeriesSlice(
        name: channelName(ch),
        color: channelColor(ch),
        unit: 'µV',
        samples: hidden ? const [] : getRange(ch, startT, endT),
        visible: !hidden,
      ));
    }
    return result;
  }

  void clear() => _channels.clear();
}

class _RingChannel {
  final Float64List timestamps;
  final Float64List values;
  int _head = 0;
  int _count = 0;

  _RingChannel(int capacity)
      : timestamps = Float64List(capacity),
        values = Float64List(capacity);

  int get length => _count;

  void add(double t, double v) {
    timestamps[_head] = t;
    values[_head] = v;
    _head = (_head + 1) % timestamps.length;
    if (_count < timestamps.length) _count++;
  }

  int _physicalIndex(int i) =>
      (_head - _count + i + timestamps.length) % timestamps.length;

  double timestampAt(int i) => timestamps[_physicalIndex(i)];
  double valueAt(int i) => values[_physicalIndex(i)];

  int lowerBound(double t) {
    int lo = 0, hi = _count;
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
    int lo = 0, hi = _count;
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
}
