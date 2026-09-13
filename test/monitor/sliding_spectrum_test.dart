import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/cache/sliding_spectrum.dart';
import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';
import 'package:muse_ml/src/monitor/cache/sweep_mean.dart';
import 'package:muse_ml/src/monitor/dsp.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

EegDto _eeg(int electrode, List<double> samples, {double ts = 0}) => EegDto(
  index: 0,
  electrode: electrode,
  timestamp: ts,
  samples: Float64List.fromList(samples),
);

const double _hopSec = kWelchHopSamples / SweepBuffer.sampleRate;
const double _psdWindowSec = 4;
const double _histWindowSec = 8;

void _appendSine(
  SweepBuffer buf, {
  required int electrode,
  required int count,
  required double hz,
}) {
  final origin = buf.channelCount(electrode);
  var i = 0;
  while (i < count) {
    final take = math.min(256, count - i);
    buf.append(
      _eeg(electrode, [
        for (var k = 0; k < take; k++)
          math.sin(
            2 * math.pi * hz * (origin + i + k) / SweepBuffer.sampleRate,
          ),
      ]),
    );
    i += take;
  }
}

void _appendUv(SweepBuffer buf, {required int count, required double uv}) {
  var i = 0;
  while (i < count) {
    final take = math.min(256, count - i);
    buf.append(_eeg(0, List<double>.filled(take, uv)));
    i += take;
  }
}

double _newest(SweepBuffer buf) =>
    (buf.sampleCount - 1) / SweepBuffer.sampleRate;

Float64List _mean(
  SweepBuffer buf,
  Set<int> electrodes,
  double start,
  double end,
) => meanEegWindow(
  buffer: buf,
  electrodes: electrodes,
  startElapsed: start,
  endElapsed: end,
  newestElapsed: _newest(buf),
);

void _expectSpectrum(Spectrum a, Spectrum b, {double tol = 1e-9}) {
  expect(a.n, b.n);
  expect(a.power.length, b.power.length);
  for (var k = 0; k < a.power.length; k++) {
    expect(a.power[k], closeTo(b.power[k], tol), reason: 'bin $k');
  }
}

void main() {
  test('Welch hop is n/2 at 256-pt', () {
    expect(kWelchHopSamples, 128);
    expect(kWelchHopSamples, kDefaultFftN >> 1);
  });

  test('sliding Welch matches welch(); one hop keeps the alpha peak', () {
    final buf = SweepBuffer();
    final n = (_psdWindowSec * SweepBuffer.sampleRate).round();
    _appendSine(buf, electrode: 0, count: n, hz: 10);

    var newest = _newest(buf);
    var start = newest - _psdWindowSec;
    var end = newest;
    final sliding = SlidingWelch();
    expect(
      sliding.update(
        buffer: buf,
        electrodes: {0},
        startElapsed: start,
        endElapsed: end,
        newestElapsed: newest,
      ),
      isTrue,
    );
    expect(sliding.spectrum, isNotNull);
    final samples = _mean(buf, {0}, start, end);
    _expectSpectrum(sliding.spectrum!, welch(samples));
    expect(alphaPeakHz(sliding.spectrum!), closeTo(10, 1));
    expect(alphaPeakHz(welch(samples)), closeTo(10, 1));
    final first = sliding.spectrum;

    expect(
      sliding.update(
        buffer: buf,
        electrodes: {0},
        startElapsed: start,
        endElapsed: end,
        newestElapsed: newest,
      ),
      isFalse,
    );
    expect(identical(sliding.spectrum, first), isTrue);

    _appendSine(buf, electrode: 0, count: 12, hz: 10);
    newest = _newest(buf);
    expect(
      sliding.update(
        buffer: buf,
        electrodes: {0},
        startElapsed: newest - _psdWindowSec,
        endElapsed: newest,
        newestElapsed: newest,
      ),
      isFalse,
    );
    expect(identical(sliding.spectrum, first), isTrue);

    _appendSine(buf, electrode: 0, count: kWelchHopSamples - 12, hz: 10);
    newest = _newest(buf);
    start += _hopSec;
    end += _hopSec;
    expect(
      sliding.update(
        buffer: buf,
        electrodes: {0},
        startElapsed: start,
        endElapsed: end,
        newestElapsed: newest,
      ),
      isTrue,
    );
    expect(identical(sliding.spectrum, first), isFalse);
    final slid = _mean(buf, {0}, start, end);
    _expectSpectrum(sliding.spectrum!, welch(slid));
    expect(alphaPeakHz(sliding.spectrum!), closeTo(10, 1));
    final fresh = SlidingWelch();
    fresh.update(
      buffer: buf,
      electrodes: {0},
      startElapsed: start,
      endElapsed: end,
      newestElapsed: newest,
    );
    _expectSpectrum(sliding.spectrum!, fresh.spectrum!);
  });

  test('sliding Welch electrode change matches a fresh ring', () {
    final buf = SweepBuffer();
    final n = (_psdWindowSec * SweepBuffer.sampleRate).round();
    _appendSine(buf, electrode: 0, count: n, hz: 10);
    _appendSine(buf, electrode: 1, count: n, hz: 20);
    final newest = _newest(buf);
    final start = newest - _psdWindowSec;
    final end = newest;

    final sliding = SlidingWelch();
    sliding.update(
      buffer: buf,
      electrodes: {0},
      startElapsed: start,
      endElapsed: end,
      newestElapsed: newest,
    );
    final one = sliding.spectrum;
    expect(one, isNotNull);
    expect(alphaPeakHz(one!), closeTo(10, 1));

    expect(
      sliding.update(
        buffer: buf,
        electrodes: {0, 1},
        startElapsed: start,
        endElapsed: end,
        newestElapsed: newest,
      ),
      isTrue,
    );
    expect(identical(sliding.spectrum, one), isFalse);
    final twoSamples = _mean(buf, {0, 1}, start, end);
    _expectSpectrum(sliding.spectrum!, welch(twoSamples));
  });

  test('sliding histogram matches histogramCounts after a slide', () {
    final buf = SweepBuffer();
    final n = (_histWindowSec * SweepBuffer.sampleRate).round();
    _appendUv(buf, count: n ~/ 2, uv: 10);
    _appendUv(buf, count: n ~/ 2, uv: 40);

    var newest = _newest(buf);
    var start = newest - _histWindowSec;
    var end = newest;
    final sliding = SlidingHistogram();
    expect(
      sliding.update(
        buffer: buf,
        electrodes: {0},
        startElapsed: start,
        endElapsed: end,
        newestElapsed: newest,
        halfRange: 100,
      ),
      isTrue,
    );
    expect(
      listEquals(sliding.counts, histogramCounts(_mean(buf, {0}, start, end))),
      isTrue,
    );
    final identity = sliding.counts;

    _appendUv(buf, count: kWelchHopSamples, uv: 70);
    newest = _newest(buf);
    start += _hopSec;
    end += _hopSec;
    expect(
      sliding.update(
        buffer: buf,
        electrodes: {0},
        startElapsed: start,
        endElapsed: end,
        newestElapsed: newest,
        halfRange: 100,
      ),
      isTrue,
    );
    expect(identical(sliding.counts, identity), isTrue);
    final expected = histogramCounts(_mean(buf, {0}, start, end));
    expect(listEquals(sliding.counts, expected), isTrue);
    expect(
      sliding.counts.reduce((a, b) => a + b),
      expected.reduce((a, b) => a + b),
    );
    expect(sliding.counts[histogramBinFor(70)], greaterThan(0));
  });

  test('meanEegWindow reuses an output buffer of the same length', () {
    final buf = SweepBuffer();
    _appendUv(buf, count: 256, uv: 12);
    final newest = _newest(buf);
    final scratch = Float64List(256);
    final reused = meanEegWindow(
      buffer: buf,
      electrodes: {0},
      startElapsed: 0,
      endElapsed: 1,
      newestElapsed: newest,
      out: scratch,
    );
    expect(identical(reused, scratch), isTrue);
    expect(reused.first, closeTo(12, 1e-9));
    final other = meanEegWindow(
      buffer: buf,
      electrodes: {0},
      startElapsed: 0,
      endElapsed: 0.5,
      newestElapsed: newest,
      out: scratch,
    );
    expect(identical(other, scratch), isFalse);
    expect(other, hasLength(128));
  });
}
