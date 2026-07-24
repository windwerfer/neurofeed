import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/charts/eeg_data_source.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

const List<String> bandNames = ['delta', 'theta', 'alpha', 'beta', 'gamma'];
const List<Color> bandColors = [
  Color(0xFF4FC3F7),
  Color(0xFFFF7043),
  Color(0xFF66BB6A),
  Color(0xFFAB47BC),
  Color(0xFFFFA726),
];

int bandCountPerElectrode = bandNames.length;

int bandChannelId(int electrode, int bandIndex) => electrode * bandCountPerElectrode + bandIndex;

int electrodeFromChannel(int channel) => channel ~/ bandCountPerElectrode;

int bandIndexFromChannel(int channel) => channel % bandCountPerElectrode;

String bandChannelName(int channel) {
  final e = electrodeFromChannel(channel);
  final b = bandIndexFromChannel(channel);
  return '${channelName(e)} ${bandNames[b]}';
}

Color bandChannelColor(int channel) {
  final b = bandIndexFromChannel(channel);
  return bandColors[b % bandColors.length];
}

class BandCache extends ChangeNotifier implements EegDataSource {
  static const int _capacityPerBand = 60000;

  final Map<int, _BandRing> _channels = {};

  @override
  double get maxTimeWindowSecs => 7200.0;

  void appendBands(BandsDto dto) {
    final ts = dto.timestamp / 1000.0;
    _insert(dto.electrode, 0, ts, dto.delta);
    _insert(dto.electrode, 1, ts, dto.theta);
    _insert(dto.electrode, 2, ts, dto.alpha);
    _insert(dto.electrode, 3, ts, dto.beta);
    _insert(dto.electrode, 4, ts, dto.gamma);
    notifyListeners();
  }

  void _insert(int electrode, int bandIdx, double t, double v) {
    final id = bandChannelId(electrode, bandIdx);
    final buf = _channels.putIfAbsent(id, () => _BandRing(_capacityPerBand));
    buf.add(t, v);
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
        name: bandChannelName(ch),
        color: bandChannelColor(ch),
        unit: 'µV²/Hz',
        samples: hidden ? const [] : getRange(ch, startT, endT),
        visible: !hidden,
      ));
    }
    return result;
  }

  void clear() => _channels.clear();
}

class _BandRing {
  final Float64List timestamps;
  final Float64List values;
  int _head = 0;
  int _count = 0;

  _BandRing(int capacity)
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
