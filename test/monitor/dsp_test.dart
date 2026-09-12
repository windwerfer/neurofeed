import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/dsp.dart';

void main() {
  test('Hamming 256-pt: ends 0.08, midpoint 1.0', () {
    final w = hammingWindow(256);
    expect(w.length, 256);
    expect(w[0], closeTo(0.08, 1e-12));
    expect(w[128], closeTo(1.0, 1e-12));
  });

  test('FFT power is 1/N²; DC of ones is 0.54² after Hamming', () {
    final spec = fft(List<double>.filled(256, 1.0), n: 256);
    expect(spec.power[0], closeTo(0.54 * 0.54, 1e-9));
  });

  test('band edges 1–4 / 4–8 / 8–13 / 13–30 / 30–50 at 256-pt', () {
    expect(freqBin(1, 256), 1);
    expect(freqBin(4, 256), 4);
    expect(freqBin(8, 256), 8);
    expect(freqBin(13, 256), 13);
    expect(freqBin(30, 256), 30);
    expect(freqBin(50, 256), 50);
    expect(gammaHiHz(256), 50);

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
