import 'dart:typed_data';

import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';
import 'package:muse_ml/src/monitor/cache/sweep_mean.dart';
import 'package:muse_ml/src/monitor/dsp.dart';

class StftRing {
  static const double _eps = 1e-6;

  List<StftColumn> _columns = const [];
  int _lastHopIndex = -1;
  Set<int> _electrodes = const {};
  double _start = 0;
  double _end = 0;

  static int _hopIndex(double elapsed) =>
      (elapsed * SweepBuffer.sampleRate).round() ~/ kStftHopSamples;

  static bool _sameElectrodes(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  List<StftColumn> columnsFor({
    required SweepBuffer buffer,
    required Set<int> electrodes,
    required double start,
    required double end,
    required double newest,
  }) {
    if (_columns.isNotEmpty &&
        _sameElectrodes(_electrodes, electrodes) &&
        (start - _start).abs() < _eps &&
        (end - _end).abs() < _eps) {
      return _columns;
    }

    const hopSec = kStftHopSamples / SweepBuffer.sampleRate;
    if (_columns.isNotEmpty &&
        _sameElectrodes(_electrodes, electrodes) &&
        _lastHopIndex >= 0 &&
        _hopIndex(end) == _lastHopIndex + 1 &&
        (start - _start - hopSec).abs() < _eps &&
        (end - _end - hopSec).abs() < _eps) {
      return _appendHop(
        buffer: buffer,
        electrodes: electrodes,
        start: start,
        end: end,
        newest: newest,
        hopSec: hopSec,
      );
    }

    return _recompute(
      buffer: buffer,
      electrodes: electrodes,
      start: start,
      end: end,
      newest: newest,
    );
  }

  List<StftColumn> _appendHop({
    required SweepBuffer buffer,
    required Set<int> electrodes,
    required double start,
    required double end,
    required double newest,
    required double hopSec,
  }) {
    final pad = kDefaultFftN / SweepBuffer.sampleRate;
    final elapsed = _columns.last.elapsed + hopSec;
    final slice = meanEegWindow(
      buffer: buffer,
      electrodes: electrodes,
      startElapsed: elapsed - pad,
      endElapsed: elapsed,
      newestElapsed: newest,
    );
    final next = <StftColumn>[
      for (final c in _columns)
        if (c.elapsed >= start - _eps) c,
      _column(slice, elapsed),
    ];
    _store(next, electrodes, start, end);
    return _columns;
  }

  List<StftColumn> _recompute({
    required SweepBuffer buffer,
    required Set<int> electrodes,
    required double start,
    required double end,
    required double newest,
  }) {
    final pad = kDefaultFftN / SweepBuffer.sampleRate;
    final samples = meanEegWindow(
      buffer: buffer,
      electrodes: electrodes,
      startElapsed: start - pad,
      endElapsed: end,
      newestElapsed: newest,
    );
    _store(
      stftColumns(samples, startElapsed: start - pad),
      electrodes,
      start,
      end,
    );
    return _columns;
  }

  void _store(
    List<StftColumn> columns,
    Set<int> electrodes,
    double start,
    double end,
  ) {
    _columns = columns;
    _electrodes = Set<int>.from(electrodes);
    _start = start;
    _end = end;
    _lastHopIndex = _hopIndex(end);
  }

  static StftColumn _column(List<double> samples, double elapsed) {
    final spec = fft(samples, n: kDefaultFftN);
    final db = Float64List(spec.power.length);
    for (var k = 0; k < db.length; k++) {
      db[k] = powerToDb(spec.power[k]);
    }
    return StftColumn(elapsed, db);
  }
}
