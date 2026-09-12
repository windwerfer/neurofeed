import 'dart:math' as math;
import 'dart:typed_data';

const int kDefaultFftN = 256;
const double kFftSampleRate = 256.0;
const int kHistogramBins = 64;
const double kHistogramDefaultHalfRange = 100;
const int kStftHopSamples = 64;
const double kLogEpsilon = 1e-12;

const double kBandDeltaLoHz = 1;
const double kBandDeltaHiHz = 4;
const double kBandThetaLoHz = 4;
const double kBandThetaHiHz = 8;
const double kBandAlphaLoHz = 8;
const double kBandAlphaHiHz = 13;
const double kBandBetaLoHz = 13;
const double kBandBetaHiHz = 30;
const double kBandGammaLoHz = 30;
const double kBandGammaHiHz = 50;

bool isPowerOfTwo(int n) => n >= 2 && (n & (n - 1)) == 0;

void assertPowerOfTwo(int n) {
  if (!isPowerOfTwo(n)) {
    throw ArgumentError.value(n, 'n', 'FFT size must be a power of two');
  }
}

final Map<int, Float64List> _hammingCache = {};

/// Periodic Hamming: `0.54 - 0.46·cos(2πi/n)`.
Float64List hammingWindow(int n) {
  assertPowerOfTwo(n);
  return _hammingCache.putIfAbsent(n, () {
    final w = Float64List(n);
    for (var i = 0; i < n; i++) {
      w[i] = 0.54 - 0.46 * math.cos(2 * math.pi * i / n);
    }
    return w;
  });
}

double powerToDb(double power) {
  final v = power.isFinite && power > kLogEpsilon ? power : kLogEpsilon;
  return 10.0 * math.log(v) / math.ln10;
}

double hzPerBin(int n, {double sampleRate = kFftSampleRate}) => sampleRate / n;

int freqBin(double hz, int n, {double sampleRate = kFftSampleRate}) =>
    (hz / hzPerBin(n, sampleRate: sampleRate)).round();

double gammaHiHz(int n, {double sampleRate = kFftSampleRate}) {
  final nyquist = sampleRate / 2;
  return math.min(kBandGammaHiHz, nyquist);
}

class Spectrum {
  Spectrum({required this.n, required this.sampleRate, required this.power});

  final int n;
  final double sampleRate;
  final Float64List power;

  double get binHz => hzPerBin(n, sampleRate: sampleRate);

  double freqAt(int bin) => bin * binHz;
}

void _fftInPlace(Float64List re, Float64List im) {
  final n = re.length;
  var j = 0;
  for (var i = 1; i < n; i++) {
    var bit = n >> 1;
    while (j & bit != 0) {
      j ^= bit;
      bit >>= 1;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  var len = 2;
  while (len <= n) {
    final angle = -2.0 * math.pi / len;
    final wlenRe = math.cos(angle);
    final wlenIm = math.sin(angle);
    final half = len >> 1;
    for (var i = 0; i < n; i += len) {
      var wRe = 1.0;
      var wIm = 0.0;
      for (var k = 0; k < half; k++) {
        final p = i + k;
        final q = p + half;
        final uRe = re[p];
        final uIm = im[p];
        final vRe = wRe * re[q] - wIm * im[q];
        final vIm = wRe * im[q] + wIm * re[q];
        re[p] = uRe + vRe;
        im[p] = uIm + vIm;
        re[q] = uRe - vRe;
        im[q] = uIm - vIm;
        final tRe = wRe * wlenRe - wIm * wlenIm;
        final tIm = wRe * wlenIm + wIm * wlenRe;
        wRe = tRe;
        wIm = tIm;
      }
    }
    len <<= 1;
  }
}

Spectrum fft(
  List<double> samples, {
  int n = kDefaultFftN,
  double sampleRate = kFftSampleRate,
}) {
  assertPowerOfTwo(n);
  final re = Float64List(n);
  final im = Float64List(n);
  final w = hammingWindow(n);
  final copy = math.min(samples.length, n);
  for (var i = 0; i < copy; i++) {
    final v = samples[i];
    re[i] = (v.isFinite ? v : 0.0) * w[i];
  }
  _fftInPlace(re, im);
  final half = n >> 1;
  final power = Float64List(half + 1);
  final norm = 1.0 / (n * n);
  for (var k = 0; k <= half; k++) {
    power[k] = (re[k] * re[k] + im[k] * im[k]) * norm;
  }
  return Spectrum(n: n, sampleRate: sampleRate, power: power);
}

double bandPower(Spectrum s, double loHz, double hiHz) {
  final lo = freqBin(loHz, s.n, sampleRate: s.sampleRate);
  var hi = freqBin(hiHz, s.n, sampleRate: s.sampleRate);
  final last = s.power.length - 1;
  if (hi > last) hi = last;
  var sum = 0.0;
  for (var k = lo; k <= hi; k++) {
    if (k < 1) continue;
    sum += s.power[k];
  }
  return sum;
}

double? alphaPeakHz(Spectrum s) {
  final lo = freqBin(kBandAlphaLoHz, s.n, sampleRate: s.sampleRate);
  final hi = freqBin(kBandAlphaHiHz, s.n, sampleRate: s.sampleRate);
  var maxP = 0.0;
  var maxK = lo;
  for (var k = lo; k <= hi && k < s.power.length; k++) {
    if (k < 1) continue;
    if (s.power[k] > maxP) {
      maxP = s.power[k];
      maxK = k;
    }
  }
  if (maxP < 1e-12) return null;
  return s.freqAt(maxK);
}

Spectrum welch(
  List<double> samples, {
  int n = kDefaultFftN,
  double sampleRate = kFftSampleRate,
}) {
  assertPowerOfTwo(n);
  final hop = n >> 1;
  final acc = Float64List((n >> 1) + 1);
  var count = 0;
  final finite = Float64List(n);
  for (var start = 0; start + n <= samples.length; start += hop) {
    for (var i = 0; i < n; i++) {
      finite[i] = samples[start + i];
    }
    final spec = fft(finite, n: n, sampleRate: sampleRate);
    for (var k = 0; k < acc.length; k++) {
      acc[k] += spec.power[k];
    }
    count++;
  }
  if (count == 0) {
    if (samples.isEmpty) {
      return Spectrum(n: n, sampleRate: sampleRate, power: acc);
    }
    return fft(samples, n: n, sampleRate: sampleRate);
  }
  for (var k = 0; k < acc.length; k++) {
    acc[k] /= count;
  }
  return Spectrum(n: n, sampleRate: sampleRate, power: acc);
}

class StftColumn {
  StftColumn(this.elapsed, this.db);
  final double elapsed;
  final Float64List db;
}

List<StftColumn> stftColumns(
  List<double> samples, {
  required double startElapsed,
  int n = kDefaultFftN,
  int hop = kStftHopSamples,
  double sampleRate = kFftSampleRate,
}) {
  assertPowerOfTwo(n);
  if (hop < 1) hop = 1;
  final out = <StftColumn>[];
  final slice = Float64List(n);
  for (var i = 0; i + n <= samples.length; i += hop) {
    for (var k = 0; k < n; k++) {
      slice[k] = samples[i + k];
    }
    final spec = fft(slice, n: n, sampleRate: sampleRate);
    final db = Float64List(spec.power.length);
    for (var k = 0; k < db.length; k++) {
      db[k] = powerToDb(spec.power[k]);
    }
    out.add(StftColumn(startElapsed + (i + n) / sampleRate, db));
  }
  return out;
}

List<int> histogramCounts(
  List<double> samples, {
  double halfRange = kHistogramDefaultHalfRange,
  int binCount = kHistogramBins,
}) {
  final counts = List<int>.filled(binCount, 0);
  if (halfRange <= 0 || binCount <= 0) return counts;
  final width = (2 * halfRange) / binCount;
  for (final v in samples) {
    if (!v.isFinite) continue;
    if (v < -halfRange || v > halfRange) continue;
    var i = ((v + halfRange) / width).floor();
    if (i >= binCount) i = binCount - 1;
    if (i < 0) i = 0;
    counts[i]++;
  }
  return counts;
}

int histogramBinFor(
  double uv, {
  double halfRange = kHistogramDefaultHalfRange,
  int binCount = kHistogramBins,
}) {
  if (binCount <= 0 || halfRange <= 0) return 0;
  final width = (2 * halfRange) / binCount;
  var i = ((uv + halfRange) / width).floor();
  if (i < 0) return 0;
  if (i >= binCount) return binCount - 1;
  return i;
}
