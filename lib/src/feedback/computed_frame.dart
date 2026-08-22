import 'package:freezed_annotation/freezed_annotation.dart';
import 'dart:convert';

part 'computed_frame.freezed.dart';

@freezed
abstract class PeakAlphaInfo with _$PeakAlphaInfo {
  const factory PeakAlphaInfo({
    required double freq,
    required double power,
  }) = _PeakAlphaInfo;
}

@freezed
abstract class GuardrailInfo with _$GuardrailInfo {
  const factory GuardrailInfo({
    required double sleepDir,
    required double clarity,
    required bool warning,
    required double delta,
  }) = _GuardrailInfo;
}

@freezed
abstract class FeedbackInfo with _$FeedbackInfo {
  const factory FeedbackInfo({
    required double ratio,
    required double threshold,
    required bool inTarget,
    required double pct,
  }) = _FeedbackInfo;
}

@freezed
abstract class ComputedFrame with _$ComputedFrame {
  const factory ComputedFrame({
    required double t,
    required List<List<double>> bands,
    double? pulse,
    double? movement,
    PeakAlphaInfo? peakAlpha,
    double? spo2,
    required List<double> lineNoise,
    required List<int> signalQuality,
    required GuardrailInfo guardrail,
    required FeedbackInfo feedback,
    required List<String> gestures,
  }) = _ComputedFrame;
}

extension ComputedFrameJson on ComputedFrame {
  Map<String, dynamic> toJson() => {
        't': t,
        'bands': bands,
        'pulse': pulse,
        'movement': movement,
        'peakAlpha': peakAlpha?.toJson(),
        'spo2': spo2,
        'lineNoise': lineNoise,
        'signalQuality': signalQuality,
        'guardrail': guardrail.toJson(),
        'feedback': feedback.toJson(),
        'gestures': gestures,
      };

  List<int> toJsonBytes() => utf8.encode(jsonEncode(toJson()));
}

ComputedFrame _computedFrameFromJson(Map<String, dynamic> json) => ComputedFrame(
      t: (json['t'] as num).toDouble(),
      bands: (json['bands'] as List).map((e) => (e as List).map((v) => (v as num).toDouble()).toList()).toList(),
      pulse: (json['pulse'] as num?)?.toDouble(),
      movement: (json['movement'] as num?)?.toDouble(),
      peakAlpha: json['peakAlpha'] != null ? _peakAlphaInfoFromJson(json['peakAlpha'] as Map<String, dynamic>) : null,
      spo2: (json['spo2'] as num?)?.toDouble(),
      lineNoise: (json['lineNoise'] as List).map((e) => (e as num).toDouble()).toList(),
      signalQuality: (json['signalQuality'] as List).map((e) => (e as num).toInt()).toList(),
      guardrail: _guardrailInfoFromJson(json['guardrail'] as Map<String, dynamic>),
      feedback: _feedbackInfoFromJson(json['feedback'] as Map<String, dynamic>),
      gestures: (json['gestures'] as List).map((e) => e as String).toList(),
    );

PeakAlphaInfo _peakAlphaInfoFromJson(Map<String, dynamic> json) => PeakAlphaInfo(
      freq: (json['freq'] as num).toDouble(),
      power: (json['power'] as num).toDouble(),
    );

GuardrailInfo _guardrailInfoFromJson(Map<String, dynamic> json) => GuardrailInfo(
      sleepDir: (json['sleepDir'] as num).toDouble(),
      clarity: (json['clarity'] as num).toDouble(),
      warning: json['warning'] as bool,
      delta: (json['delta'] as num).toDouble(),
    );

FeedbackInfo _feedbackInfoFromJson(Map<String, dynamic> json) => FeedbackInfo(
      ratio: (json['ratio'] as num).toDouble(),
      threshold: (json['threshold'] as num).toDouble(),
      inTarget: json['inTarget'] as bool,
      pct: (json['pct'] as num).toDouble(),
    );

extension PeakAlphaInfoJson on PeakAlphaInfo {
  Map<String, dynamic> toJson() => {
        'freq': freq,
        'power': power,
      };

  static PeakAlphaInfo fromJson(Map<String, dynamic> json) => PeakAlphaInfo(
        freq: (json['freq'] as num).toDouble(),
        power: (json['power'] as num).toDouble(),
      );
}

extension GuardrailInfoJson on GuardrailInfo {
  Map<String, dynamic> toJson() => {
        'sleepDir': sleepDir,
        'clarity': clarity,
        'warning': warning,
        'delta': delta,
      };

  static GuardrailInfo fromJson(Map<String, dynamic> json) => GuardrailInfo(
        sleepDir: (json['sleepDir'] as num).toDouble(),
        clarity: (json['clarity'] as num).toDouble(),
        warning: json['warning'] as bool,
        delta: (json['delta'] as num).toDouble(),
      );
}

extension FeedbackInfoJson on FeedbackInfo {
  Map<String, dynamic> toJson() => {
        'ratio': ratio,
        'threshold': threshold,
        'inTarget': inTarget,
        'pct': pct,
      };

  static FeedbackInfo fromJson(Map<String, dynamic> json) => FeedbackInfo(
        ratio: (json['ratio'] as num).toDouble(),
        threshold: (json['threshold'] as num).toDouble(),
        inTarget: json['inTarget'] as bool,
        pct: (json['pct'] as num).toDouble(),
      );
}