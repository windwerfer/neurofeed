import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/audio/guard_output.dart';
import 'package:neurofeed/src/audio/reward_output.dart';
import 'package:neurofeed/src/feedback/feature_bus.dart';
import 'package:neurofeed/src/feedback/feedback_phase.dart';
import 'package:neurofeed/src/feedback/guard_lane.dart';
import 'package:neurofeed/src/feedback/guardrail_mode.dart';
import 'package:neurofeed/src/history/session_trust.dart';
import 'package:neurofeed/src/rust/api/session_format.dart' as ffi;

class _Reward implements RewardOutput {
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  void onSample({required double percentile, required bool inTarget}) {}
  @override
  void setMuffle(bool on) {}
}

class _Guard implements GuardOutput {
  final List<bool> active = [];
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  void onGuard({required bool active, required double intensity}) =>
      this.active.add(active);
}

GuardTick _tick() => GuardTick(
  phase: FeedbackPhase.playing,
  collectionEyes: null,
  muffleReward: false,
  sessionStartAt: DateTime.now(),
  writeWarningMetadata:
      ({
        required sleepDir,
        required delta,
        required threshold,
        required bandMath,
      }) {},
  updateComputed:
      ({
        required sleepDir,
        required clarity,
        required delta,
        required warning,
        threshold,
        featurePercentile,
        warnOver,
        clean,
        dirtyReason,
      }) {},
);

/// Bug 2026-10-13: fixed-P ai.a_vig session, warn pane showed the trace above
/// the line for 20+ s but no guard sound. The warn decision was P > 0.50; the
/// pane plotted the percentile of the calibration baseline against a
/// hard-coded 75 line. Calibration P is low (eyes closed but awake), so any
/// live P above all of it pinned the trace at 100 while still < 0.50.
void main() {
  late _Guard out;
  late GuardLane lane;

  setUp(() {
    out = _Guard();
    lane = GuardLane(guardOutput: out, rewardOutput: _Reward())
      ..configure(
        enabled: true,
        bandMath: false,
        featureId: guardFeatureAiAVig,
        deltaElectrodes: const [],
        thresholdMode: guardThresholdModeFixed,
        fixedThreshold: 0.5,
      )
      ..clearCaptured = true
      ..baselineSleepDir.addAll([for (var i = 0; i < 60; i++) i / 600])
      ..finalizeBaseline(warningThresholdPercentile: 75, captureAnchor: false);
  });

  void feed(double p, int seconds) {
    for (var i = 0; i < seconds; i++) {
      lane.onFeature(
        FeatureSample(id: guardFeatureAiAVig, t: i.toDouble(), value: p),
        _tick(),
      );
    }
  }

  test('fixed mode: P = 0.30 for 25 s is quiet AND plots below the line', () {
    feed(0.30, 25);
    expect(out.active, everyElement(isFalse));
    expect(lane.warningActive, isFalse);
    // The chart must agree with the decision.
    final y = lane.trustPlotValue(lane.lastSleepDir)!;
    expect(y, closeTo(30, 1e-9));
    expect(lane.trustWarnLine, closeTo(50, 1e-9));
    expect(y < lane.trustWarnLine, isTrue);
  });

  test('fixed mode: P = 0.60 warns (guard sound) and plots above', () {
    feed(0.60, 3);
    expect(out.active, everyElement(isTrue));
    expect(lane.warningActive, isTrue);
    expect(
      lane.trustPlotValue(lane.lastSleepDir)! > lane.trustWarnLine,
      isTrue,
    );
  });

  test('percentile mode keeps baseline percentile vs the user percentile', () {
    lane.setThresholdMode(
      guardThresholdModePercentile,
      warningThresholdPercentile: 80,
    );
    expect(lane.trustWarnLine, 80);
    feed(0.30, 1);
    expect(lane.trustPlotValue(0.30), 100);
    expect(lane.warningActive, isTrue);
  });

  group('history replay', () {
    ffi.ComputedFrame frame(double t, double p) => ffi.ComputedFrame(
      t: t,
      bands: const [],
      lineNoise: Float32List(0),
      signalQuality: Uint8List(0),
      guardrail: ffi.GuardrailInfo(
        sleepDir: p,
        clarity: 0,
        warning: false,
        delta: 0,
        featurePercentile: 100,
        warnOver: false,
        clean: true,
      ),
      feedback: const ffi.FeedbackInfo(
        ratio: 1,
        threshold: 1,
        inTarget: false,
        pct: 0,
      ),
      gestures: const [],
    );

    test('fixed sessions replay P × 100 against the P cut', () {
      final trust = readSessionTrust(
        frames: [frame(0, 0.3), frame(1, 0.3)],
        guardFixedThreshold: 0.5,
        guardWarnPercentile: 75,
      );
      expect(trust.guard.last.featurePercentile, closeTo(30, 1e-6));
      expect(trust.guard.last.warnLine, 50);
    });

    test('percentile sessions keep stored percentile; old files no line', () {
      final pct = readSessionTrust(
        frames: [frame(0, 0.3)],
        guardWarnPercentile: 80,
      );
      expect(pct.guard.single.featurePercentile, 100);
      expect(pct.guard.single.warnLine, 80);
      final old = readSessionTrust(frames: [frame(0, 0.3)]);
      expect(old.guard.single.warnLine, isNull);
    });
  });
}
