import 'dart:math' as math;
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/feedback/target_state.dart';
import 'package:neurofeed/src/monitor/signal_usable.dart';
import 'package:neurofeed/src/rust/api/session_format.dart' as ffi;

/// Map [GestureType] → locked snake_case annotation `type`.
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
  final experimental = assembleExperimentalBands(frames);
  if (experimental != null) {
    stats.addAll(experimental);
  }
  return stats.isEmpty ? null : stats;
}

/// Band indices on [ComputedFrame.bands] rows: δ θ α β γ.
const int kBandDelta = 0;
const int kBandTheta = 1;
const int kBandAlpha = 2;
const int kBandBeta = 3;
const int kBandGamma = 4;

const int kMinUsableSecondsForExperimentalBands = 30;

/// Muse channel indices matching default `device.channelLabels`.
const int kChTp9 = 0;
const int kChAf7 = 1;
const int kChAf8 = 2;
const int kChTp10 = 3;

bool _frameUsable(ffi.ComputedFrame f) {
  if (f.signalQuality.isEmpty) return false;
  final mean =
      f.signalQuality.map((e) => e.toDouble()).reduce((a, b) => a + b) /
      f.signalQuality.length;
  return mean >= kUsableSignalThreshold;
}

double? _channelMeanBand(List<List<num>> bands, int bandIdx) {
  if (bands.isEmpty) return null;
  var sum = 0.0;
  var n = 0;
  for (final ch in bands) {
    if (bandIdx >= ch.length) continue;
    final v = ch[bandIdx].toDouble();
    if (v.isNaN) continue;
    sum += v;
    n++;
  }
  return n == 0 ? null : sum / n;
}

double? _relAlpha(List<num> ch) {
  if (ch.length < 5) return null;
  final total = ch[0] + ch[1] + ch[2] + ch[3] + ch[4];
  if (total <= 0) return null;
  return ch[2] / total;
}

/// Locked `stats.experimental.bands` (Must + Sensible + Cool). Omits the nest
/// when fewer than [kMinUsableSecondsForExperimentalBands] usable seconds.
Map<String, Object?>? assembleExperimentalBands(
  List<ffi.ComputedFrame> frames, {
  bool includeSensible = true,
  bool includeCool = true,
}) {
  final usable = <ffi.ComputedFrame>[];
  for (final f in frames) {
    if (!_frameUsable(f)) continue;
    if (f.bands.isEmpty) continue;
    usable.add(f);
  }
  if (usable.length < kMinUsableSecondsForExperimentalBands) {
    return null;
  }

  var meanAlphaAbsSum = 0.0;
  var meanAlphaAbsN = 0;
  var meanAlphaThetaSum = 0.0;
  var meanAlphaThetaN = 0;
  var faaSum = 0.0;
  var faaN = 0;
  var meanAlphaRelSum = 0.0;
  var meanAlphaRelN = 0;
  var ftaaSum = 0.0;
  var ftaaN = 0;
  var meanBetaThetaSum = 0.0;
  var meanBetaThetaN = 0;
  var meanThetaAbsSum = 0.0;
  var meanThetaAbsN = 0;
  var meanBetaAbsSum = 0.0;
  var meanBetaAbsN = 0;
  var taaSum = 0.0;
  var taaN = 0;

  // Per-channel session-mean absolute α for crossChannelAlphaVar.
  final chAlphaSum = <double>[];
  final chAlphaN = <int>[];

  for (final f in usable) {
    final bands = [
      for (final row in f.bands) List<num>.from(row),
    ];
    // Ensure channel sum lists sized
    while (chAlphaSum.length < bands.length) {
      chAlphaSum.add(0);
      chAlphaN.add(0);
    }
    for (var i = 0; i < bands.length; i++) {
      if (bands[i].length > kBandAlpha) {
        final a = bands[i][kBandAlpha].toDouble();
        if (!a.isNaN && a > 0) {
          chAlphaSum[i] += a;
          chAlphaN[i]++;
        }
      }
    }

    final meanA = _channelMeanBand(bands, kBandAlpha);
    final meanT = _channelMeanBand(bands, kBandTheta);
    final meanB = _channelMeanBand(bands, kBandBeta);
    if (meanA != null) {
      meanAlphaAbsSum += meanA;
      meanAlphaAbsN++;
    }
    if (meanA != null && meanT != null && meanT > 0) {
      meanAlphaThetaSum += meanA / meanT;
      meanAlphaThetaN++;
    }
    if (meanT != null) {
      meanThetaAbsSum += meanT;
      meanThetaAbsN++;
    }
    if (meanB != null) {
      meanBetaAbsSum += meanB;
      meanBetaAbsN++;
    }
    if (meanB != null && meanT != null && meanT > 0) {
      meanBetaThetaSum += meanB / meanT;
      meanBetaThetaN++;
    }

    // Relative α: all-channel mean of per-channel relative α
    var relSum = 0.0;
    var relN = 0;
    for (final ch in bands) {
      final r = _relAlpha(ch);
      if (r == null) continue;
      relSum += r;
      relN++;
    }
    if (relN > 0) {
      meanAlphaRelSum += relSum / relN;
      meanAlphaRelN++;
    }

    if (bands.length > kChAf8) {
      final a7 = bands[kChAf7].length > kBandAlpha
          ? bands[kChAf7][kBandAlpha].toDouble()
          : 0.0;
      final a8 = bands[kChAf8].length > kBandAlpha
          ? bands[kChAf8][kBandAlpha].toDouble()
          : 0.0;
      if (a7 > 0 && a8 > 0) {
        faaSum += _ln(a8) - _ln(a7);
        faaN++;
      }
      if (bands.length > kChTp10) {
        final t9 = bands[kChTp9][kBandAlpha].toDouble();
        final t10 = bands[kChTp10][kBandAlpha].toDouble();
        if (a7 > 0 && a8 > 0 && t9 > 0 && t10 > 0) {
          final frontal = (a7 + a8) / 2;
          final temporal = (t9 + t10) / 2;
          ftaaSum += _ln(frontal) - _ln(temporal);
          ftaaN++;
        }
        if (t9 > 0 && t10 > 0) {
          taaSum += _ln(t10) - _ln(t9);
          taaN++;
        }
      }
    }
  }

  final bandsOut = <String, Object?>{};
  if (meanAlphaAbsN > 0) {
    bandsOut['meanAlphaAbs'] = meanAlphaAbsSum / meanAlphaAbsN;
  }
  if (meanAlphaThetaN > 0) {
    bandsOut['meanAlphaTheta'] = meanAlphaThetaSum / meanAlphaThetaN;
  }
  if (faaN > 0) {
    bandsOut['frontalAlphaAsym'] = faaSum / faaN;
  }

  // crossChannelAlphaVar: population variance of per-channel session-mean α
  final means = <double>[];
  for (var i = 0; i < chAlphaSum.length; i++) {
    if (chAlphaN[i] > 0) means.add(chAlphaSum[i] / chAlphaN[i]);
  }
  if (means.length >= 2) {
    final m = means.reduce((a, b) => a + b) / means.length;
    var varSum = 0.0;
    for (final v in means) {
      final d = v - m;
      varSum += d * d;
    }
    bandsOut['crossChannelAlphaVar'] = varSum / means.length;
  }

  if (includeSensible) {
    if (meanAlphaRelN > 0) {
      bandsOut['meanAlphaRel'] = meanAlphaRelSum / meanAlphaRelN;
    }
    if (ftaaN > 0) {
      bandsOut['frontalTemporalAlphaAsym'] = ftaaSum / ftaaN;
    }
    if (meanBetaThetaN > 0) {
      bandsOut['meanBetaTheta'] = meanBetaThetaSum / meanBetaThetaN;
    }
  }
  if (includeCool) {
    if (meanThetaAbsN > 0) {
      bandsOut['meanThetaAbs'] = meanThetaAbsSum / meanThetaAbsN;
    }
    if (meanBetaAbsN > 0) {
      bandsOut['meanBetaAbs'] = meanBetaAbsSum / meanBetaAbsN;
    }
    if (taaN > 0) {
      bandsOut['temporalAlphaAsym'] = taaSum / taaN;
    }
  }

  if (bandsOut.isEmpty) return null;
  return {
    'experimental': {'bands': bandsOut},
  };
}

double _ln(double x) => math.log(x);
