import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Rolling live stats for the nerd-stats bubble during a feedback session.
///
/// Maintains the last [window] of ATR samples (band events arrive at ~10Hz)
/// and exposes their average plus its percentile rank within the session
/// baseline distribution.
class LiveStats extends ChangeNotifier {
  static const Duration window = Duration(seconds: 2);

  final List<(DateTime, double)> _samples = [];

  double? currentAtr;
  double? currentPercentile;
  double? threshold;
  int? baselinePercentile;
  int? baselineCount;
  double? baselineMean;
  double? baselineStddev;
  double? successRate;

  void push(double atr, double? Function(double) percentileOf) {
    final now = DateTime.now();
    _samples.add((now, atr));
    _samples.removeWhere((s) => now.difference(s.$1) > window);
    if (_samples.isEmpty) {
      return;
    }
    currentAtr = _samples.fold<double>(0, (a, s) => a + s.$2) / _samples.length;
    currentPercentile = percentileOf(currentAtr!);
    notifyListeners();
  }

  void setThreshold(double? value) {
    threshold = value;
    notifyListeners();
  }

  void setBaseline({
    int? percentile,
    int? count,
    double? mean,
    double? stddev,
  }) {
    baselinePercentile = percentile;
    baselineCount = count;
    baselineMean = mean;
    baselineStddev = stddev;
    notifyListeners();
  }

  void setSuccessRate(double? value) {
    successRate = value;
    notifyListeners();
  }

  void reset() {
    _samples.clear();
    currentAtr = null;
    currentPercentile = null;
    threshold = null;
    baselinePercentile = null;
    baselineCount = null;
    baselineMean = null;
    baselineStddev = null;
    successRate = null;
    notifyListeners();
  }
}

final liveStatsProvider = ChangeNotifierProvider<LiveStats>((ref) => LiveStats());
