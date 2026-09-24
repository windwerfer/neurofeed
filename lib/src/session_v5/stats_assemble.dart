import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/feedback/target_state.dart';
import 'package:neurofeed/src/monitor/signal_usable.dart';
import 'package:neurofeed/src/rust/api/session_format.dart' as ffi;

/// Map v5 [GestureType] → locked snake_case annotation `type`.
String gestureAnnotationType(GestureType type) => switch (type) {
  GestureType.doubleBlink => 'double_blink',
  GestureType.doubleClench => 'double_jaw_clench',
  GestureType.eyeUp => 'eye_up',
  GestureType.eyeDown => 'eye_down',
};

/// Build root `annotations[]` from pause/quality/disconnect intervals plus
/// gesture instants (`duration: 0`). Merges adjacent same-type intervals.
List<SessionAnnotation> assembleAnnotations({
  List<SessionAnnotation> intervals = const [],
  List<GestureMarker> gestures = const [],
}) {
  final out = <SessionAnnotation>[
    ...intervals,
    for (final g in gestures)
      SessionAnnotation(
        onset: g.offsetSeconds.toDouble(),
        duration: 0,
        type: gestureAnnotationType(g.type),
      ),
  ]..sort((a, b) {
    final c = a.onset.compareTo(b.onset);
    if (c != 0) return c;
    return a.type.compareTo(b.type);
  });
  return mergeAdjacentIntervalAnnotations(out);
}

/// Merge adjacent same-`type` rows with `duration > 0` when they abut/overlap.
List<SessionAnnotation> mergeAdjacentIntervalAnnotations(
  List<SessionAnnotation> input,
) {
  if (input.isEmpty) return const [];
  final sorted = List<SessionAnnotation>.from(input)
    ..sort((a, b) => a.onset.compareTo(b.onset));
  final out = <SessionAnnotation>[];
  for (final a in sorted) {
    if (a.duration <= 0 || out.isEmpty) {
      out.add(a);
      continue;
    }
    final prev = out.last;
    if (prev.type == a.type &&
        prev.duration > 0 &&
        a.onset <= prev.onset + prev.duration + 1e-6) {
      final end = (a.onset + a.duration).clamp(
        prev.onset + prev.duration,
        double.infinity,
      );
      out[out.length - 1] = SessionAnnotation(
        onset: prev.onset,
        duration: end - prev.onset,
        type: prev.type,
      );
    } else {
      out.add(a);
    }
  }
  return out;
}

/// Sum of interval `duration` by type for `stats.annotationSeconds`.
Map<String, double> annotationSecondsFrom(List<SessionAnnotation> anns) {
  final out = <String, double>{};
  for (final a in anns) {
    if (a.duration <= 0) continue;
    if (a.type != 'pause' &&
        a.type != 'bad_quality' &&
        a.type != 'disconnect') {
      continue;
    }
    out[a.type] = (out[a.type] ?? 0) + a.duration;
  }
  return out;
}

/// Locked base `stats` object for v6 metadata (without experimental bands).
Map<String, Object?>? assembleBaseStats({
  required List<ffi.ComputedFrame> frames,
  List<SessionAnnotation> annotations = const [],
  List<String> channelLabels = const ['TP9', 'AF7', 'AF8', 'TP10'],
  double? batteryStartPct,
  double? batteryEndPct,
}) {
  if (frames.isEmpty && annotations.isEmpty) return null;

  double? hrMean, hrMin, hrMax;
  double? spo2Mean, spo2Min, spo2Max;
  var hrSum = 0.0, hrN = 0;
  var spo2Sum = 0.0, spo2N = 0;
  var movSum = 0.0, movN = 0, stillN = 0;
  var peakPower = double.negativeInfinity;
  double? maxPowerHz;
  var peakHzSum = 0.0, peakHzN = 0;
  var qSum = 0.0, qN = 0, goodN = 0;
  final channelGood = List<int>.filled(channelLabels.length, 0);
  final channelSeen = List<int>.filled(channelLabels.length, 0);

  for (final f in frames) {
    final p = f.pulse;
    if (p != null) {
      hrSum += p;
      hrN++;
      hrMin = hrMin == null ? p : (p < hrMin ? p : hrMin);
      hrMax = hrMax == null ? p : (p > hrMax ? p : hrMax);
    }
    final s = f.spo2;
    if (s != null) {
      spo2Sum += s;
      spo2N++;
      spo2Min = spo2Min == null ? s : (s < spo2Min ? s : spo2Min);
      spo2Max = spo2Max == null ? s : (s > spo2Max ? s : spo2Max);
    }
    final m = f.movement;
    if (m != null) {
      movSum += m;
      movN++;
      if (m <= movementGateThreshold) stillN++;
    }
    final pa = f.peakAlpha;
    if (pa != null) {
      peakHzSum += pa.freq;
      peakHzN++;
      if (pa.power > peakPower) {
        peakPower = pa.power;
        maxPowerHz = pa.freq;
      }
    }
    if (f.signalQuality.isNotEmpty) {
      final mean =
          f.signalQuality.map((e) => e.toDouble()).reduce((a, b) => a + b) /
          f.signalQuality.length;
      qSum += mean;
      qN++;
      if (mean >= kUsableSignalThreshold) goodN++;
      final n = f.signalQuality.length < channelLabels.length
          ? f.signalQuality.length
          : channelLabels.length;
      for (var i = 0; i < n; i++) {
        channelSeen[i]++;
        if (f.signalQuality[i] >= kUsableSignalThreshold) {
          channelGood[i]++;
        }
      }
    }
  }

  final stats = <String, Object?>{};
  if (hrN > 0) {
    hrMean = hrSum / hrN;
    stats['hr'] = {'mean': hrMean, 'min': hrMin, 'max': hrMax};
  }
  if (spo2N > 0) {
    spo2Mean = spo2Sum / spo2N;
    stats['spo2'] = {'mean': spo2Mean, 'min': spo2Min, 'max': spo2Max};
  }
  if (peakHzN > 0 && maxPowerHz != null) {
    stats['peakAlpha'] = {
      'meanHz': peakHzSum / peakHzN,
      'maxPowerHz': maxPowerHz,
      'maxPower': peakPower,
    };
  }
  if (movN > 0) {
    stats['movement'] = {
      'mean': movSum / movN,
      'stillnessPct': stillN * 100.0 / movN,
    };
  }
  if (qN > 0) {
    final channelUsable = <String, double>{};
    for (var i = 0; i < channelLabels.length; i++) {
      if (channelSeen[i] == 0) continue;
      channelUsable[channelLabels[i]] = channelGood[i] / channelSeen[i];
    }
    stats['quality'] = {
      'mean': qSum / qN,
      'pctGood': goodN * 100.0 / qN,
      if (channelUsable.isNotEmpty) 'channelUsable': channelUsable,
    };
  }
  final annSecs = annotationSecondsFrom(annotations);
  if (annSecs.isNotEmpty) {
    stats['annotationSeconds'] = annSecs;
  }
  if (batteryStartPct != null || batteryEndPct != null) {
    stats['battery'] = {
      ?'startPct': batteryStartPct,
      ?'endPct': batteryEndPct,
    };
  }
  return stats.isEmpty ? null : stats;
}
