import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:neurofeed/src/charts/band_style.dart';
import 'package:neurofeed/src/charts/eeg_data_source.dart';
import 'package:neurofeed/src/monitor/cache/frame_coalesced_notify.dart';
import 'package:neurofeed/src/monitor/signal_usable.dart';
import 'package:neurofeed/src/rust/api/muse.dart';

export 'package:neurofeed/src/charts/band_style.dart';

final int bandCountPerElectrode = bandNames.length;

int bandChannelId(int electrode, int bandIndex) =>
    electrode * bandCountPerElectrode + bandIndex;

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

class BandCache extends ChangeNotifier
    with FrameCoalescedNotify
    implements EegDataSource {
  static const int _capacityPerBand = 1800;

  final Map<int, _BandRing> _channels = {};

  /// Scores for the sticky unusable stamp. Live appends remember each
  /// electrode's [BandsDto.signalQuality]. A caller-supplied list replaces
  /// that until [setSignalQuality] clears it.
  List<double>? _signalQuality;
  final Map<int, double> _windowQuality = {};
  bool _qualityFromCaller = false;

  /// Electrodes currently selected in the Bands UI. Empty → only per-pad
  /// quality stamps; non-empty enables the "all selected dirty → dash all
  /// shown" append rule.
  Set<int> _selectedElectrodes = const {};

  @override
  double get maxTimeWindowSecs => 1800.0;

  /// Install a whole quality vector, or clear it so the next bands use their
  /// own window scores.
  void setSignalQuality(List<double>? quality) {
    _signalQuality = quality;
    _qualityFromCaller = quality != null;
    if (quality == null) _windowQuality.clear();
  }

  /// Wire Bands electrode selection for the all-selected-dirty stamp rule.
  void setSelectedElectrodes(Set<int> electrodes) {
    _selectedElectrodes = Set<int>.of(electrodes);
  }

  @visibleForTesting
  List<double>? get debugSignalQuality => _signalQuality;

  @visibleForTesting
  Set<int> get debugSelectedElectrodes => _selectedElectrodes;

  void appendBands(BandsDto dto, {List<double>? signalQuality}) {
    if (signalQuality != null) {
      _signalQuality = signalQuality;
      _qualityFromCaller = true;
    } else if (!_qualityFromCaller) {
      if (dto.electrode >= 0) {
        _windowQuality[dto.electrode] = dto.signalQuality;
      }
      _signalQuality = _windowQualityVector();
    }
    final unusable = shouldStampBandUnusable(
      electrode: dto.electrode,
      quality: _signalQuality,
      selectedElectrodes: _selectedElectrodes,
    );
    final ts = dto.timestamp / 1000.0;
    _insert(dto.electrode, 0, ts, dto.delta, unusable);
    _insert(dto.electrode, 1, ts, dto.theta, unusable);
    _insert(dto.electrode, 2, ts, dto.alpha, unusable);
    _insert(dto.electrode, 3, ts, dto.beta, unusable);
    _insert(dto.electrode, 4, ts, dto.gamma, unusable);
    notifyListenersCoalesced();
  }

  List<double> _windowQualityVector() {
    var n = 0;
    for (final electrode in _windowQuality.keys) {
      if (electrode >= n) n = electrode + 1;
    }
    final out = List<double>.filled(n, 0);
    for (final entry in _windowQuality.entries) {
      out[entry.key] = entry.value;
    }
    return out;
  }

  void _insert(int electrode, int bandIdx, double t, double v, bool unusable) {
    final id = bandChannelId(electrode, bandIdx);
    final buf = _channels.putIfAbsent(id, () => _BandRing(_capacityPerBand));
    buf.add(t, v, unusable);
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
      hi - lo,
      (i) => ChartSample(
        buf.timestampAt(lo + i),
        buf.valueAt(lo + i),
        unusable: buf.unusableAt(lo + i),
      ),
    );
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
      result.add(
        SeriesSlice(
          name: bandChannelName(ch),
          color: bandChannelColor(ch),
          unit: 'µV²/Hz',
          samples: hidden ? const [] : getRange(ch, startT, endT),
          visible: !hidden,
        ),
      );
    }
    return result;
  }

  /// Hold-last-Y samples stamped unusable so live Bands draw a dashed gap
  /// while the device is gone (disconnect) or quality is missing. Live-only —
  /// does not feed the Rust capture writer.
  void appendHeldUnusableGap(double timestampMs) {
    if (_channels.isEmpty) return;
    final ts = timestampMs / 1000.0;
    final ids = _channels.keys.toList();
    for (final id in ids) {
      final buf = _channels[id];
      if (buf == null || buf.length == 0) continue;
      final v = buf.valueAt(buf.length - 1);
      _insert(electrodeFromChannel(id), bandIndexFromChannel(id), ts, v, true);
    }
    notifyListenersCoalesced();
  }

  void clear() {
    _windowQuality.clear();
    _signalQuality = null;
    _qualityFromCaller = false;
    if (_channels.isEmpty) return;
    _channels.clear();
    notifyListeners();
  }
}

class _BandRing {
  final Float64List timestamps;
  final Float64List values;
  final Uint8List unusable;
  int _head = 0;
  int _count = 0;

  _BandRing(int capacity)
    : timestamps = Float64List(capacity),
      values = Float64List(capacity),
      unusable = Uint8List(capacity);

  int get length => _count;

  void add(double t, double v, bool isUnusable) {
    timestamps[_head] = t;
    values[_head] = v;
    unusable[_head] = isUnusable ? 1 : 0;
    _head = (_head + 1) % timestamps.length;
    if (_count < timestamps.length) _count++;
  }

  int _physicalIndex(int i) =>
      (_head - _count + i + timestamps.length) % timestamps.length;

  double timestampAt(int i) => timestamps[_physicalIndex(i)];
  double valueAt(int i) => values[_physicalIndex(i)];
  bool unusableAt(int i) => unusable[_physicalIndex(i)] != 0;

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
