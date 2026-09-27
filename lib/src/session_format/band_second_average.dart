import 'package:neurofeed/src/rust/api/muse.dart';

/// Per-electrode band accumulator for one computed 1 Hz frame.
///
/// [add] sums every band update since the last [take]; [take] returns the
/// mean per electrode and resets. An electrode with no update in the
/// window repeats its last value.
class BandSecondAverage {
  BandSecondAverage(this.channelCount)
    : _last = List.generate(channelCount, (_) => List<double>.filled(5, 0)),
      _lastLineNoise = List.filled(channelCount, 0.0),
      _sum = List.generate(channelCount, (_) => List<double>.filled(5, 0)),
      _sumLineNoise = List.filled(channelCount, 0.0),
      _count = List.filled(channelCount, 0);

  final int channelCount;
  final List<List<double>> _last;
  final List<double> _lastLineNoise;
  final List<List<double>> _sum;
  final List<double> _sumLineNoise;
  final List<int> _count;

  void add(int electrode, BandsDto b) {
    if (electrode < 0 || electrode >= channelCount) return;
    final s = _sum[electrode];
    s[0] += b.delta;
    s[1] += b.theta;
    s[2] += b.alpha;
    s[3] += b.beta;
    s[4] += b.gamma;
    _sumLineNoise[electrode] += b.lineNoiseRatio;
    _count[electrode]++;
  }

  ({List<List<double>> bands, List<double> lineNoise}) take() {
    for (var e = 0; e < channelCount; e++) {
      final n = _count[e];
      if (n == 0) continue;
      _last[e] = [for (final v in _sum[e]) v / n];
      _lastLineNoise[e] = _sumLineNoise[e] / n;
      _sum[e].fillRange(0, 5, 0);
      _sumLineNoise[e] = 0;
      _count[e] = 0;
    }
    return (
      bands: [for (final b in _last) List<double>.from(b)],
      lineNoise: List<double>.from(_lastLineNoise),
    );
  }
}
