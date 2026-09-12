import 'dart:typed_data';

import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

/// Mean of selected electrodes over `[startElapsed, endElapsed)` via
/// [SweepBuffer.sampleAt]. No second EEG ring.
Float64List meanEegWindow({
  required SweepBuffer buffer,
  required Iterable<int> electrodes,
  required double startElapsed,
  required double endElapsed,
  required double? newestElapsed,
}) {
  final span = endElapsed - startElapsed;
  if (span <= 0) return Float64List(0);
  final n = (span * SweepBuffer.sampleRate).round();
  if (n <= 0) return Float64List(0);
  final selected = electrodes.toList();
  final out = Float64List(n);
  if (selected.isEmpty) {
    for (var i = 0; i < n; i++) {
      out[i] = double.nan;
    }
    return out;
  }
  for (var i = 0; i < n; i++) {
    final elapsed = startElapsed + i / SweepBuffer.sampleRate;
    var sum = 0.0;
    var count = 0;
    for (final e in selected) {
      final idx = ramIndexForElapsed(
        elapsed: elapsed,
        ramCount: buffer.channelCount(e),
        ramNewestElapsed: newestElapsed,
      );
      if (idx == null) continue;
      final v = buffer.sampleAt(e, idx);
      if (!v.isFinite) continue;
      sum += v;
      count++;
    }
    out[i] = count == 0 ? double.nan : sum / count;
  }
  return out;
}

double sweepNewestElapsed(SweepBuffer buffer, double? ramNewestElapsed) {
  if (ramNewestElapsed != null) return ramNewestElapsed;
  if (buffer.sampleCount <= 0) return 0;
  return (buffer.sampleCount - 1) / SweepBuffer.sampleRate;
}
