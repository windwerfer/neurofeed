import 'dart:typed_data';

import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';
import 'package:muse_ml/src/monitor/cache/sweep_mean.dart';
import 'package:muse_ml/src/monitor/dsp.dart';

const int kWelchHopSamples = kDefaultFftN >> 1;

bool _sameElectrodes(Set<int> a, Set<int> b) =>
    a.length == b.length && a.containsAll(b);

class SlidingWelch {
  Spectrum? spectrum;
  final List<Float64List> _periodograms = [];
  Set<int> _electrodes = const {};
  double startElapsed = 0;
  double endElapsed = 0;
  Float64List? _windowScratch;
  Float64List? _hopScratch;

  bool update({
    required SweepBuffer buffer,
    required Set<int> electrodes,
    required double startElapsed,
    required double endElapsed,
    required double? newestElapsed,
    bool forceFull = false,
  }) {
    if (!forceFull &&
        _periodograms.isNotEmpty &&
        _sameElectrodes(_electrodes, electrodes)) {
      final endSamples =
          ((endElapsed - this.endElapsed) * SweepBuffer.sampleRate).round();
      final startSamples =
          ((startElapsed - this.startElapsed) * SweepBuffer.sampleRate).round();
      if (endSamples == 0 && startSamples == 0) return false;
      final hops = endSamples ~/ kWelchHopSamples;
      final sameSpan = (startSamples - endSamples).abs() <= 2;
      if (endSamples > 0 &&
          sameSpan &&
          hops > 0 &&
          hops < _periodograms.length &&
          _appendHops(
            buffer: buffer,
            electrodes: electrodes,
            newestElapsed: newestElapsed,
            hops: hops,
          )) {
        return true;
      }
      if (hops == 0 && sameSpan) return false;
    }

    _recompute(
      buffer: buffer,
      electrodes: electrodes,
      startElapsed: startElapsed,
      endElapsed: endElapsed,
      newestElapsed: newestElapsed,
    );
    return true;
  }

  bool _appendHops({
    required SweepBuffer buffer,
    required Set<int> electrodes,
    required double? newestElapsed,
    required int hops,
  }) {
    const nSec = kDefaultFftN / SweepBuffer.sampleRate;
    const hopSec = kWelchHopSamples / SweepBuffer.sampleRate;
    final originEnd = endElapsed;
    final originStart = startElapsed;
    for (var h = 1; h <= hops; h++) {
      final hopEnd = originEnd + hopSec * h;
      _hopScratch = meanEegWindow(
        buffer: buffer,
        electrodes: electrodes,
        startElapsed: hopEnd - nSec,
        endElapsed: hopEnd,
        newestElapsed: newestElapsed,
        out: _hopScratch,
      );
      if (_hopScratch!.length != kDefaultFftN) return false;
      if (_periodograms.isEmpty) return false;
      _periodograms.removeAt(0);
      _periodograms.add(fft(_hopScratch!, n: kDefaultFftN).power);
    }
    _store(electrodes, originStart + hopSec * hops, originEnd + hopSec * hops);
    spectrum = _average();
    return true;
  }

  void _recompute({
    required SweepBuffer buffer,
    required Set<int> electrodes,
    required double startElapsed,
    required double endElapsed,
    required double? newestElapsed,
  }) {
    _periodograms.clear();
    if (!buffer.hasData) {
      spectrum = null;
      _store(electrodes, startElapsed, endElapsed);
      return;
    }
    _windowScratch = meanEegWindow(
      buffer: buffer,
      electrodes: electrodes,
      startElapsed: startElapsed,
      endElapsed: endElapsed,
      newestElapsed: newestElapsed,
      out: _windowScratch,
    );
    final samples = _windowScratch!;
    const n = kDefaultFftN;
    if (samples.length < n) {
      spectrum = samples.isEmpty
          ? Spectrum(
              n: n,
              sampleRate: kFftSampleRate,
              power: Float64List((n >> 1) + 1),
            )
          : fft(samples, n: n);
      if (samples.isNotEmpty) {
        _periodograms.add(spectrum!.power);
      }
      _store(electrodes, startElapsed, endElapsed);
      return;
    }
    final hop = n >> 1;
    final slice = Float64List(n);
    for (var start = 0; start + n <= samples.length; start += hop) {
      for (var i = 0; i < n; i++) {
        slice[i] = samples[start + i];
      }
      _periodograms.add(fft(slice, n: n).power);
    }
    spectrum = _average();
    _store(electrodes, startElapsed, endElapsed);
  }

  Spectrum _average() {
    final bins = (kDefaultFftN >> 1) + 1;
    final acc = Float64List(bins);
    if (_periodograms.isEmpty) {
      return Spectrum(n: kDefaultFftN, sampleRate: kFftSampleRate, power: acc);
    }
    for (final p in _periodograms) {
      for (var k = 0; k < bins; k++) {
        acc[k] += p[k];
      }
    }
    final count = _periodograms.length;
    for (var k = 0; k < bins; k++) {
      acc[k] /= count;
    }
    return Spectrum(n: kDefaultFftN, sampleRate: kFftSampleRate, power: acc);
  }

  void _store(Set<int> electrodes, double startElapsed, double endElapsed) {
    _electrodes = Set<int>.from(electrodes);
    this.startElapsed = startElapsed;
    this.endElapsed = endElapsed;
  }
}

class SlidingHistogram {
  static const double _eps = 1e-9;

  List<int> counts = List<int>.filled(kHistogramBins, 0);
  Set<int> _electrodes = const {};
  double startElapsed = 0;
  double endElapsed = 0;
  double _halfRange = kHistogramDefaultHalfRange;
  bool _hasState = false;
  Float64List? _scratch;

  bool update({
    required SweepBuffer buffer,
    required Set<int> electrodes,
    required double startElapsed,
    required double endElapsed,
    required double? newestElapsed,
    required double halfRange,
    bool forceFull = false,
  }) {
    if (!forceFull &&
        _hasState &&
        _sameElectrodes(_electrodes, electrodes) &&
        (halfRange - _halfRange).abs() < _eps &&
        (startElapsed - this.startElapsed).abs() < _eps &&
        (endElapsed - this.endElapsed).abs() < _eps) {
      return false;
    }

    if (!forceFull &&
        _hasState &&
        _sameElectrodes(_electrodes, electrodes) &&
        (halfRange - _halfRange).abs() < _eps &&
        startElapsed + _eps >= this.startElapsed &&
        endElapsed + _eps >= this.endElapsed &&
        startElapsed < this.endElapsed - _eps) {
      return _slide(
        buffer: buffer,
        electrodes: electrodes,
        startElapsed: startElapsed,
        endElapsed: endElapsed,
        newestElapsed: newestElapsed,
        halfRange: halfRange,
      );
    }

    _recompute(
      buffer: buffer,
      electrodes: electrodes,
      startElapsed: startElapsed,
      endElapsed: endElapsed,
      newestElapsed: newestElapsed,
      halfRange: halfRange,
    );
    return true;
  }

  bool _slide({
    required SweepBuffer buffer,
    required Set<int> electrodes,
    required double startElapsed,
    required double endElapsed,
    required double? newestElapsed,
    required double halfRange,
  }) {
    final leave = meanEegWindow(
      buffer: buffer,
      electrodes: electrodes,
      startElapsed: this.startElapsed,
      endElapsed: startElapsed,
      newestElapsed: newestElapsed,
    );
    _scratch = meanEegWindow(
      buffer: buffer,
      electrodes: electrodes,
      startElapsed: this.endElapsed,
      endElapsed: endElapsed,
      newestElapsed: newestElapsed,
      out: _scratch,
    );
    if (leave.isEmpty && _scratch!.isEmpty) return false;
    _accum(leave, -1, halfRange);
    _accum(_scratch!, 1, halfRange);
    _store(electrodes, startElapsed, endElapsed, halfRange);
    return true;
  }

  void _recompute({
    required SweepBuffer buffer,
    required Set<int> electrodes,
    required double startElapsed,
    required double endElapsed,
    required double? newestElapsed,
    required double halfRange,
  }) {
    _scratch = meanEegWindow(
      buffer: buffer,
      electrodes: electrodes,
      startElapsed: startElapsed,
      endElapsed: endElapsed,
      newestElapsed: newestElapsed,
      out: _scratch,
    );
    counts = histogramCounts(_scratch!, halfRange: halfRange);
    _store(electrodes, startElapsed, endElapsed, halfRange);
  }

  void _accum(List<double> samples, int sign, double halfRange) {
    if (halfRange <= 0) return;
    final width = (2 * halfRange) / kHistogramBins;
    for (final v in samples) {
      if (!v.isFinite) continue;
      if (v < -halfRange || v > halfRange) continue;
      var i = ((v + halfRange) / width).floor();
      if (i >= kHistogramBins) i = kHistogramBins - 1;
      if (i < 0) i = 0;
      counts[i] += sign;
    }
  }

  void _store(
    Set<int> electrodes,
    double startElapsed,
    double endElapsed,
    double halfRange,
  ) {
    _electrodes = Set<int>.from(electrodes);
    this.startElapsed = startElapsed;
    this.endElapsed = endElapsed;
    _halfRange = halfRange;
    _hasState = true;
  }
}
