import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/monitor/dsp.dart';

void main() {
  test('Hamming 256-pt: ends 0.08, midpoint 1.0', () {
    final w = hammingWindow(256);
    expect(w.length, 256);
    expect(w[0], closeTo(0.08, 1e-12));
    expect(w[128], closeTo(1.0, 1e-12));
  });

  test('one-sided PSD: a 10 µV sine carries 50 µV² in its band', () {
    for (final hz in [10.0, 10.5]) {
      final spec = fft([
        for (var i = 0; i < 256; i++) 10 * math.sin(2 * math.pi * hz * i / 256),
      ], n: 256);
      expect(bandPower(spec, kBandAlphaLoHz, kBandAlphaHiHz), closeTo(50, 1));
    }
  });

  test('bands [1,4) [4,8) [8,13) [13,30) [30,45): each bin in one band', () {
    expect(gammaHiHz(256), 45);
    const edges = [
      (kBandDeltaLoHz, kBandDeltaHiHz),
      (kBandThetaLoHz, kBandThetaHiHz),
      (kBandAlphaLoHz, kBandAlphaHiHz),
      (kBandBetaLoHz, kBandBetaHiHz),
      (kBandGammaLoHz, kBandGammaHiHz),
    ];
    for (var f = 1; f <= 50; f++) {
      final inBands = edges.where((e) => f >= e.$1 && f < e.$2).length;
      expect(inBands, f < 45 ? 1 : 0, reason: '$f Hz');
    }

    final spec = fft([
      for (var i = 0; i < 256; i++) math.cos(2 * math.pi * 10 * i / 256),
    ], n: 256);
    expect(
      bandPower(spec, kBandDeltaLoHz, kBandDeltaHiHz),
      greaterThanOrEqualTo(0),
    );
    expect(bandPower(spec, kBandAlphaLoHz, kBandAlphaHiHz), greaterThan(0));
    expect(
      bandPower(spec, kBandAlphaLoHz, kBandAlphaHiHz),
      greaterThan(bandPower(spec, kBandDeltaLoHz, kBandDeltaHiHz)),
    );
    expect(alphaPeakHz(spec), closeTo(10, 1));
  });

  test('n accepts other powers of two', () {
    expect(isPowerOfTwo(128), isTrue);
    expect(isPowerOfTwo(256), isTrue);
    expect(isPowerOfTwo(512), isTrue);
    expect(isPowerOfTwo(255), isFalse);
    expect(fft(List<double>.filled(128, 0.0), n: 128).n, 128);
    expect(fft(List<double>.filled(512, 0.0), n: 512).n, 512);
    expect(fft([1, 0, 0, 0], n: 4).n, 4);
    expect(() => fft([0], n: 255), throwsArgumentError);
    expect(() => hammingWindow(3), throwsArgumentError);
  });

  test('Welch hop is 50% of n; incomplete tail is skipped', () {
    final samples = List<double>.generate(
      256 + 128 + 10,
      (i) => math.sin(2 * math.pi * 10 * i / 256),
    );
    final spec = welch(samples, n: 256);
    expect(spec.n, 256);
    expect(spec.power.length, 129);
    expect(alphaPeakHz(spec), closeTo(10, 1));
  });

  test('STFT hop ~0.25 s at 256 Hz', () {
    expect(kStftHopSamples / kFftSampleRate, closeTo(0.25, 1e-9));
    final samples = List<double>.filled(256 + 64 * 3, 0.0);
    final cols = stftColumns(
      samples,
      startElapsed: 0,
      n: 256,
      hop: kStftHopSamples,
    );
    expect(cols, hasLength(4));
    expect(cols[1].elapsed - cols[0].elapsed, closeTo(0.25, 1e-9));
  });
}
