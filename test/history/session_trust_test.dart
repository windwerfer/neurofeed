import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/feedback/trust/trust_trace.dart';
import 'package:neurofeed/src/history/session_trust.dart';
import 'package:neurofeed/src/rust/api/session_format.dart' as ffi;
import 'package:neurofeed/src/session_format/stats_assemble.dart';

ffi.ComputedFrame _frame({
  required double t,
  bool? rewardClean,
  bool inTarget = false,
  bool? heldBack,
  double percentile = 50,
  double ratio = 1,
  double? betaRel,
  double? deltaRel,
  String? rewardDirty,
  List<String>? inhibitTags,
  bool? guardClean,
  bool warning = false,
  bool? warnOver,
  bool? ceilingOver,
  double featurePercentile = 50,
  double guardDelta = 0,
  String? guardDirty,
}) {
  return ffi.ComputedFrame(
    t: t,
    bands: const [],
    lineNoise: Float32List(0),
    signalQuality: Uint8List(0),
    guardrail: ffi.GuardrailInfo(
      sleepDir: 0,
      clarity: 0,
      warning: warning,
      delta: guardDelta,
      featurePercentile: guardClean == null ? null : featurePercentile,
      warnOver: warnOver,
      ceilingOver: ceilingOver,
      clean: guardClean,
      dirtyReason: guardDirty,
    ),
    feedback: ffi.FeedbackInfo(
      ratio: ratio,
      threshold: 1,
      inTarget: inTarget,
      pct: 0,
      percentile: rewardClean == null ? null : percentile,
      thresholdPercentile: rewardClean == null ? null : 40,
      heldBack: heldBack,
      inhibitTags: inhibitTags,
      clean: rewardClean,
      dirtyReason: rewardDirty,
      betaRel: betaRel,
      deltaRel: deltaRel,
    ),
    gestures: const [],
  );
}

void main() {
  test('dirty second holds the previous clean percentile', () {
    final read = readSessionTrust(
      frames: [
        _frame(
          t: 0,
          rewardClean: false,
          percentile: 12,
          ratio: 0.2,
          betaRel: 0.2,
          deltaRel: 0.3,
          rewardDirty: 'movement',
          guardClean: false,
          featurePercentile: 11,
          guardDelta: 0.2,
          guardDirty: 'blink',
        ),
        _frame(
          t: 1,
          rewardClean: true,
          percentile: 80,
          ratio: 1.5,
          betaRel: 0.5,
          deltaRel: 0.6,
          inTarget: true,
          guardClean: true,
          featurePercentile: 70,
          guardDelta: 0.8,
        ),
        _frame(
          t: 2,
          rewardClean: false,
          percentile: 5,
          ratio: 0.1,
          betaRel: 0.9,
          deltaRel: 0.1,
          rewardDirty: 'jaw',
          guardClean: false,
          featurePercentile: 4,
          guardDelta: 0.1,
          guardDirty: 'pads',
        ),
        _frame(
          t: 3,
          rewardClean: true,
          percentile: 40,
          inTarget: false,
          guardClean: true,
          featurePercentile: 20,
          guardDelta: 0.3,
        ),
        _frame(
          t: 4,
          rewardClean: false,
          percentile: 1,
          betaRel: 0.01,
          deltaRel: 0.01,
          rewardDirty: 'movement',
          guardClean: false,
          featurePercentile: 2,
          guardDelta: 0.05,
        ),
      ],
    );

    final first = read.reward.first;
    expect(first.plotPercentile, 12);
    expect(first.plotBetaRel, 0.2);
    expect(first.plotDeltaRel, 0.3);
    expect(first.percentile, 12);
    expect(first.native, 0.2);
    expect(first.thresholdPercentile, 40);
    expect(first.dirtyReason, TrustDirtyReason.movement);
    expect(first.clean, isFalse);

    expect(read.reward[1].plotPercentile, 80);
    expect(read.reward[1].plotBetaRel, 0.5);
    expect(read.reward[1].plotDeltaRel, 0.6);

    final held = read.reward[2];
    expect(held.plotPercentile, 80);
    expect(held.plotBetaRel, 0.5);
    expect(held.plotDeltaRel, 0.6);
    expect(held.percentile, 5);
    expect(held.betaRel, 0.9);
    expect(held.deltaRel, 0.1);
    expect(held.dirtyReason, TrustDirtyReason.jaw);

    expect(read.reward[3].plotPercentile, 40);
    expect(read.reward[3].plotBetaRel, 0.5);
    expect(read.reward[3].plotDeltaRel, 0.6);

    expect(read.reward[4].plotPercentile, 40);
    expect(read.reward[4].plotBetaRel, 0.5);
    expect(read.reward[4].plotDeltaRel, 0.6);

    expect(read.guard.first.plotFeaturePercentile, 11);
    expect(read.guard.first.plotDelta, 0.2);
    expect(read.guard.first.dirtyReason, TrustDirtyReason.blink);
    expect(read.guard[1].plotFeaturePercentile, 70);
    expect(read.guard[1].plotDelta, 0.8);
    expect(read.guard[2].plotFeaturePercentile, 70);
    expect(read.guard[2].plotDelta, 0.8);
    expect(read.guard[2].featurePercentile, 4);
    expect(read.guard[2].dirtyReason, TrustDirtyReason.pads);
    expect(read.guard[4].plotFeaturePercentile, 20);
    expect(read.guard[4].plotDelta, 0.3);
  });

  test('in-zone percent ignores a calibration second and a noisy second, '
      'and weights a 60 s gap as the median gap', () {
    final frames = [
      _frame(t: 0, rewardClean: true, inTarget: true, percentile: 90),
      _frame(t: 10, rewardClean: true, inTarget: true, percentile: 70),
      _frame(
        t: 11,
        rewardClean: false,
        inTarget: true,
        heldBack: true,
        percentile: 1,
        rewardDirty: 'movement',
      ),
      _frame(t: 12, rewardClean: true, inTarget: false, percentile: 30),
      _frame(t: 72, rewardClean: true, inTarget: false, percentile: 20),
    ];
    final weights = frameSeconds(frames);
    expect(frames[4].t - frames[3].t, 60);
    expect(weights, [10, 1, 1, 10, 10]);

    final read = readSessionTrust(frames: frames, trainingStartOffsetSecs: 10);
    expect(read.reward, hasLength(5));
    expect(read.reward.first.t, 0);
    expect(read.pctInZone, closeTo(100 / 21, 1e-9));
    expect(read.pctInhibited, 0);
    expect(read.pctWarning, isNull);
    expect(read.pctCeiling, isNull);
  });

  test('heldBack on a dirty second does not add inhibited time', () {
    final read = readSessionTrust(
      frames: [
        _frame(t: 0, rewardClean: true, inTarget: true, heldBack: false),
        _frame(
          t: 1,
          rewardClean: false,
          heldBack: true,
          inhibitTags: const ['beta'],
          rewardDirty: 'movement',
        ),
        _frame(
          t: 2,
          rewardClean: true,
          inTarget: false,
          heldBack: true,
          inhibitTags: const ['beta'],
        ),
      ],
    );
    expect(read.reward[1].heldBack, isTrue);
    expect(read.reward[1].clean, isFalse);
    expect(read.pctInhibited, 50);
    expect(read.pctInZone, 50);
  });

  test(
    'null percent when every second is noisy, and when the frames are a recording',
    () {
      final noisy = readSessionTrust(
        frames: [
          for (var t = 0; t < 3; t++)
            _frame(
              t: t.toDouble(),
              rewardClean: false,
              inTarget: true,
              heldBack: true,
              guardClean: false,
              warning: true,
              ceilingOver: true,
            ),
        ],
      );
      expect(noisy.reward, isNotEmpty);
      expect(noisy.guard, isNotEmpty);
      expect(noisy.pctInZone, isNull);
      expect(noisy.pctInhibited, isNull);
      expect(noisy.pctWarning, isNull);
      expect(noisy.pctCeiling, isNull);

      final recording = readSessionTrust(
        frames: [
          for (var t = 0; t < 3; t++)
            _frame(t: t.toDouble(), inTarget: true, warning: true),
        ],
      );
      expect(recording.reward, isEmpty);
      expect(recording.guard, isEmpty);
      expect(recording.marks, isEmpty);
      expect(recording.pctInZone, isNull);
      expect(recording.pctInhibited, isNull);
      expect(recording.pctWarning, isNull);
      expect(recording.pctCeiling, isNull);
      expect(recording.rewardChimes, 0);
      expect(recording.guardChimes, 0);
    },
  );

  test('chime count ignores any other audioEvents type', () {
    final read = readSessionTrust(
      frames: const [],
      audioEvents: const [
        {'onset': 1, 'type': 'reward_chime'},
        {'onset': 2, 'type': 'guard_chime'},
        {'onset': 3, 'type': 'reward'},
        {'onset': 4, 'type': 'other'},
        {'type': 'reward_chime'},
        {'onset': 5},
        {'type': 'guard_chime'},
        {'type': 'GUARD_CHIME'},
      ],
    );
    expect(read.rewardChimes, 2);
    expect(read.guardChimes, 2);
    expect(read.reward, isEmpty);
    expect(read.guard, isEmpty);
  });

  test('marks are double_blink and double_jaw_clench only', () {
    final read = readSessionTrust(
      frames: const [],
      annotations: const [
        SessionAnnotation(onset: 4, duration: 0, type: 'double_blink'),
        SessionAnnotation(onset: 5, duration: 0, type: 'eye_up'),
        SessionAnnotation(onset: 6, duration: 0, type: 'eye_down'),
        SessionAnnotation(onset: 7, duration: 1, type: 'double_blink'),
        SessionAnnotation(onset: 8, duration: 0, type: 'double_jaw_clench'),
        SessionAnnotation(onset: 9, duration: 0, type: 'pause'),
        SessionAnnotation(onset: 10, duration: 3, type: 'double_jaw_clench'),
        SessionAnnotation(onset: 11, duration: 0, type: 'doubleBlink'),
      ],
    );
    expect(read.marks, hasLength(2));
    expect(read.marks[0].t, 4);
    expect(read.marks[0].type, GestureType.doubleBlink);
    expect(read.marks[1].t, 8);
    expect(read.marks[1].type, GestureType.doubleClench);
  });

  test('guard warning and ceiling count clean seconds only', () {
    final read = readSessionTrust(
      frames: [
        _frame(
          t: 0,
          guardClean: true,
          warning: true,
          warnOver: false,
          ceilingOver: false,
        ),
        _frame(
          t: 1,
          guardClean: false,
          warning: true,
          warnOver: true,
          ceilingOver: true,
        ),
        _frame(
          t: 2,
          guardClean: true,
          warning: false,
          warnOver: true,
          ceilingOver: true,
        ),
        _frame(
          t: 3,
          guardClean: true,
          warning: true,
          warnOver: false,
          ceilingOver: false,
        ),
      ],
    );
    expect(read.pctWarning, closeTo(200 / 3, 1e-9));
    expect(read.pctCeiling, closeTo(100 / 3, 1e-9));
    expect(read.pctInZone, isNull);
    expect(read.reward, isEmpty);
    expect(read.guard[0].warningActive, isTrue);
    expect(read.guard[0].warnOver, isFalse);
    expect(read.guard[2].warningActive, isFalse);
    expect(read.guard[2].warnOver, isTrue);
    expect(read.guard[2].ceilingOver, isTrue);
  });
}
