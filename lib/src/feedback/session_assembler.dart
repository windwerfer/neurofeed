import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:muse_ml/src/feedback/computed_frame.dart' as dart;
import 'package:muse_ml/src/rust/api/session_format.dart' as ffi;

/// 1×1 transparent WebP. Never pass empty bytes to `image.decodeImage`.
const List<int> placeholderWebP = [
  0x52, 0x49, 0x46, 0x46, 0x1A, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50,
  0x56, 0x50, 0x38, 0x58, 0x0A, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00,
  0x2F, 0xFF, 0xF0, 0x0E, 0x10, 0x00, 0x00, 0x00, 0x1C, 0x00, 0x00, 0x00,
  0x30, 0x30, 0x31, 0x20, 0x00, 0x00, 0x00, 0x13, 0x04, 0x40, 0x9D, 0x01,
  0x2A, 0x01, 0x00, 0x03, 0x13, 0x1F, 0x03,
];

ffi.ComputedFrame toFfiFrame(dart.ComputedFrame frame) {
  return ffi.ComputedFrame(
    t: frame.t,
    bands: frame.bands.map((b) => Float32List.fromList(b)).toList(),
    pulse: frame.pulse,
    movement: frame.movement,
    peakAlpha: frame.peakAlpha != null
        ? ffi.PeakAlphaInfo(
            freq: frame.peakAlpha!.freq,
            power: frame.peakAlpha!.power,
          )
        : null,
    spo2: frame.spo2,
    lineNoise: Float32List.fromList(frame.lineNoise),
    signalQuality: Uint8List.fromList(frame.signalQuality),
    guardrail: ffi.GuardrailInfo(
      sleepDir: frame.guardrail.sleepDir,
      clarity: frame.guardrail.clarity,
      warning: frame.guardrail.warning,
      delta: frame.guardrail.delta,
    ),
    feedback: ffi.FeedbackInfo(
      ratio: frame.feedback.ratio,
      threshold: frame.feedback.threshold,
      inTarget: frame.feedback.inTarget,
      pct: frame.feedback.pct,
    ),
    gestures: frame.gestures,
  );
}

List<ffi.ComputedFrame> parseComputedJsonl(Uint8List bytes) {
  if (bytes.isEmpty) return const [];
  try {
    final frames = <ffi.ComputedFrame>[];
    for (final line in utf8.decode(bytes).split('\n')) {
      if (line.trim().isEmpty) continue;
      frames.add(
        toFfiFrame(dart.ComputedFrame.fromJson(jsonDecode(line))),
      );
    }
    return frames;
  } catch (e) {
    debugPrint('[session] failed to parse computed JSONL: $e');
    return const [];
  }
}

/// PNG → 640×360 WebP. Empty or invalid input yields [placeholderWebP].
Uint8List encodeThumbnailWebP(Uint8List pngBytes) {
  if (pngBytes.isEmpty) {
    return Uint8List.fromList(placeholderWebP);
  }
  try {
    final image = img.decodeImage(pngBytes);
    if (image == null) {
      debugPrint('[session] thumbnail: failed to decode PNG, using placeholder');
      return Uint8List.fromList(placeholderWebP);
    }
    final resized = img.copyResize(image, width: 640, height: 360);
    return Uint8List.fromList(img.encodeWebP(resized));
  } catch (e) {
    debugPrint('[session] thumbnail encode failed: $e');
    return Uint8List.fromList(placeholderWebP);
  }
}

/// Single wrapper around `containerEncodeV5`. Empty thumbnails become the
/// placeholder WebP so the decoder never sees `Uint8List(0)`.
Uint8List assembleV5Container({
  required List<int> thumbnail,
  required Map<String, Object?> metadataJson,
  required List<ffi.ComputedFrame> computedFrames,
  required List<int> rawBody,
}) {
  final thumb = thumbnail.isEmpty ? placeholderWebP : thumbnail;
  return ffi.containerEncodeV5(
    thumbnail: Uint8List.fromList(thumb),
    metadataJson: utf8.encode(jsonEncode(metadataJson)),
    computedFrames: computedFrames,
    rawBody: Uint8List.fromList(rawBody),
  );
}

class ComputedScalars {
  const ComputedScalars({
    this.avgHr,
    this.avgSpo2,
    this.peakAlphaHz,
    this.peakAlphaPower,
    this.pctInTarget,
    this.avgMovement,
    this.guardrailWarnCount,
    this.avgSleepDir,
  });

  final double? avgHr;
  final double? avgSpo2;
  final double? peakAlphaHz;
  final double? peakAlphaPower;
  final double? pctInTarget;
  final double? avgMovement;
  final int? guardrailWarnCount;
  final double? avgSleepDir;
}

ComputedScalars extractComputedScalars(List<ffi.ComputedFrame> frames) {
  if (frames.isEmpty) return const ComputedScalars();

  var hrSum = 0.0;
  var hrN = 0;
  var spo2Sum = 0.0;
  var spo2N = 0;
  var movSum = 0.0;
  var movN = 0;
  var sleepSum = 0.0;
  var inTarget = 0;
  var warn = 0;
  double? peakHz;
  double? peakPower;

  for (final f in frames) {
    final p = f.pulse;
    if (p != null) {
      hrSum += p;
      hrN++;
    }
    final s = f.spo2;
    if (s != null) {
      spo2Sum += s;
      spo2N++;
    }
    final m = f.movement;
    if (m != null) {
      movSum += m;
      movN++;
    }
    sleepSum += f.guardrail.sleepDir;
    if (f.feedback.inTarget) inTarget++;
    if (f.guardrail.warning) warn++;
    final pa = f.peakAlpha;
    if (pa != null && (peakPower == null || pa.power > peakPower)) {
      peakPower = pa.power;
      peakHz = pa.freq;
    }
  }

  return ComputedScalars(
    avgHr: hrN == 0 ? null : hrSum / hrN,
    avgSpo2: spo2N == 0 ? null : spo2Sum / spo2N,
    peakAlphaHz: peakHz,
    peakAlphaPower: peakPower,
    pctInTarget: inTarget * 100 / frames.length,
    avgMovement: movN == 0 ? null : movSum / movN,
    guardrailWarnCount: warn,
    avgSleepDir: sleepSum / frames.length,
  );
}
