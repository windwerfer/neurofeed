import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/audio/reward_output.dart';
import 'package:neurofeed/src/feedback/feature_bus.dart';
import 'package:neurofeed/src/feedback/feature_catalog.dart';
import 'package:neurofeed/src/feedback/feedback_phase.dart';
import 'package:neurofeed/src/feedback/protocol.dart';
import 'package:neurofeed/src/feedback/protocol_catalog.dart';
import 'package:neurofeed/src/feedback/reward_lane.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/feedback/target_state.dart';
import 'package:neurofeed/src/feedback/trust/trust_trace.dart';
import 'package:neurofeed/src/rust/api/muse.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Out implements RewardOutput {
  final List<({double percentile, bool inTarget})> calls = [];

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void onSample({required double percentile, required bool inTarget}) =>
      calls.add((percentile: percentile, inTarget: inTarget));

  @override
  void setMuffle(bool on) {}
}

class _Frame {
  _Frame(this.ratio, this.threshold, this.inTarget, this.clean, this.heldBack);
  final double ratio;
  final double? threshold;
  final bool inTarget;
  final bool? clean;
  final bool? heldBack;
}

const _montage = ['TP9', 'AF7', 'AF8', 'TP10'];

BandsDto _pad(int e) => BandsDto(
  electrode: e,
  timestamp: 0,
  delta: 1,
  theta: 1,
  alpha: 2,
  beta: 0.5,
  gamma: 0.1,
  signalQuality: 100,
  lineNoiseRatio: 0,
);

RewardTick _tick({bool clean = true, bool guardBlocks = false}) => RewardTick(
  phase: FeedbackPhase.playing,
  sampleIsClean: clean,
  quality: const [100, 100, 100, 100],
  dirtyReason: clean ? null : TrustDirtyReason.movement,
  guardBlocks: guardBlocks,
);

/// Alternating baseline 0.30 / 0.36 → every 2-sample window has the same CV.
List<double> _baseline(int n) => [
  for (var i = 0; i < n; i++) i.isEven ? 0.30 : 0.36,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('CV helpers', () {
    test('coefficientOfVariation = population SD ÷ |mean|', () {
      expect(coefficientOfVariation([1, 3]), closeTo(0.5, 1e-12));
      expect(coefficientOfVariation([1]), isNull);
      expect(coefficientOfVariation([1, -1]), isNull);
    });

    test('rollingCvs: full windows; short input → one CV; window ≥ 2', () {
      expect(rollingCvs([1, 3, 1, 3], 2), [0.5, 0.5, 0.5]);
      expect(rollingCvs([1, 3], 10), [0.5]);
      expect(rollingCvs([1, 3, 1, 3], 1), hasLength(3));
    });

    test('StabilityConfig defaults and clamps', () {
      const c = StabilityConfig();
      expect(c.windowSeconds, 10);
      expect(c.difficulty, 0.10);
      expect(c.initialThreshold, closeTo(0.9, 1e-12));
      expect(const StabilityConfig(windowSeconds: 1).effectiveWindow, 2);
      expect(c.copyWith(windowSeconds: 99).windowSeconds, 30);
      expect(c.copyWith(windowSeconds: 0).windowSeconds, 1);
      expect(c.copyWith(difficulty: 0.9).difficulty, 0.5);
      expect(c.copyWith(difficulty: -1).difficulty, 0);
    });
  });

  group('RatioEngine stability mode', () {
    RatioEngine engine({int window = 4, double difficulty = 0.1}) {
      final e = RatioEngine(epochWindow: const Duration(milliseconds: 1))
        ..setStability(
          StabilityConfig(windowSeconds: window, difficulty: difficulty),
        );
      for (final v in _baseline(20)) {
        e.addBaselineSample(v);
      }
      e.computeThreshold();
      return e;
    }

    test('baseline CV from rolling windows; threshold = 1 − difficulty', () {
      final e = engine();
      final expected = coefficientOfVariation([0.30, 0.36, 0.30, 0.36])!;
      expect(e.baselineCv, closeTo(expected, 1e-12));
      expect(e.threshold, closeTo(0.9, 1e-12));
      expect(e.baselineMean, closeTo(1.0, 1e-9)); // pile = window ratios
    });

    test('lower ratio is in target; warm-up returns null', () {
      final e = engine();
      expect(e.isInTarget(0.5), isTrue);
      expect(e.isInTarget(0.9), isTrue);
      expect(e.isInTarget(0.95), isFalse);
      expect(e.pushStabilitySample(0.33), isNull);
      expect(e.pushStabilitySample(0.33), isNull);
      expect(e.pushStabilitySample(0.33), isNull);
      // 4th clean sample fills the window: flat signal → r = 0.
      expect(e.pushStabilitySample(0.33), closeTo(0, 1e-12));
    });

    test('adapt: too easy → harder (lower), too hard → back up to the '
        'difficulty, never easier than it', () async {
      final e = engine()..setResponsiveness(1.0);
      for (var i = 0; i < 5; i++) {
        e.recordEpoch(true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
      e.recordEpoch(true);
      e.adapt();
      expect(e.threshold!, lessThan(0.9));
      final harder = e.threshold!;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      e
        ..recordEpoch(false)
        ..recordEpoch(false)
        ..recordEpoch(true);
      e.adapt();
      expect(e.threshold!, greaterThan(harder));
      expect(e.threshold!, lessThanOrEqualTo(0.9));
    });

    test('difficulty and window change live', () {
      final e = engine();
      e.setStabilityDifficulty(0.3);
      expect(e.threshold, closeTo(0.7, 1e-12));
      e.setStabilityWindow(2);
      expect(e.stability!.windowSeconds, 2);
      expect(e.threshold, closeTo(0.7, 1e-12));
      expect(e.stabilityWindowFill, (0, 2));
    });

    test('normal mode is untouched', () {
      final e = RatioEngine();
      for (final v in [1.0, 2.0, 3.0]) {
        e.addBaselineSample(v);
      }
      e.computeThreshold();
      expect(e.stability, isNull);
      expect(e.isInTarget(5), isTrue);
      expect(e.pushStabilitySample(1), isNull);
    });
  });

  group('RewardLane stability path', () {
    late _Out out;
    late List<_Frame> frames;
    late RatioEngine engine;
    late RewardLane lane;

    setUp(() {
      out = _Out();
      frames = [];
      engine = RatioEngine()
        ..setStability(const StabilityConfig(windowSeconds: 3));
      lane = RewardLane(
        engine: engine,
        output: out,
        onStats: (_) {},
        onComputedFeedback:
            ({
              required ratio,
              required threshold,
              required inTarget,
              required inTargetPct,
              percentile,
              thresholdPercentile,
              heldBack,
              inhibitTags,
              clean,
              dirtyReason,
              betaRel,
              deltaRel,
            }) =>
                frames.add(_Frame(ratio, threshold, inTarget, clean, heldBack)),
        onThresholdChanged: () {},
      );
      lane.configure(
        hasReward: true,
        featureId: 'band.alpha',
        inhibit: const [],
        electrodeNames: const ['AF7', 'AF8'],
        montageNames: _montage,
      );
      lane.onBands(_pad(1));
      lane.onBands(_pad(2));
      for (final v in _baseline(12)) {
        lane.onFeature(
          FeatureSample(id: 'band.alpha', t: 0, value: v),
          const RewardTick(
            phase: FeedbackPhase.calibrating,
            sampleIsClean: true,
            quality: [100, 100, 100, 100],
            acceptBaselineSample: true,
          ),
        );
      }
      engine.computeThreshold();
    });

    void feed(double v, RewardTick t) =>
        lane.onFeature(FeatureSample(id: 'band.alpha', t: 0, value: v), t);

    test('warm-up produces nothing; a steady window rewards', () {
      feed(0.33, _tick());
      feed(0.33, _tick());
      expect(lane.lastProduced, isFalse);
      expect(out.calls, isEmpty);
      expect(frames, isEmpty);
      feed(0.33, _tick());
      expect(lane.lastProduced, isTrue);
      expect(lane.lastInTarget, isTrue);
      expect(out.calls.single.inTarget, isTrue);
      expect(out.calls.single.percentile, 100); // r = 0 → calmest
      expect(frames.single.ratio, closeTo(0, 1e-12));
      expect(frames.single.threshold, closeTo(0.9, 1e-12));
    });

    test('dirty samples are excluded from the window, not unsteady', () {
      feed(0.33, _tick());
      feed(0.33, _tick());
      // A wild dirty sample must not enter the window nor break the run.
      feed(5.0, _tick(clean: false));
      expect(out.calls, isEmpty);
      expect(lane.lastDirty, isTrue);
      feed(0.33, _tick());
      expect(lane.lastInTarget, isTrue, reason: 'window = 3 clean 0.33');
      // Dirty after a verdict: held ratio recorded as a dirty frame.
      feed(9.0, _tick(clean: false));
      expect(frames.last.clean, isFalse);
      expect(frames.last.ratio, closeTo(0, 1e-12));
      expect(out.calls, hasLength(1));
    });

    test('a fluctuating window is not rewarded', () {
      for (final v in [0.2, 0.5, 0.2]) {
        feed(v, _tick());
      }
      expect(lane.lastInTarget, isFalse);
      expect(out.calls.last.percentile, lessThan(60));
    });

    test('guard warning holds a steady second back', () {
      for (var i = 0; i < 3; i++) {
        feed(0.33, _tick(guardBlocks: true));
      }
      expect(lane.lastInTarget, isFalse);
      expect(lane.lastHeldBack, isTrue);
      expect(lane.lastInhibitTags, ['guard']);
      expect(frames.last.heldBack, isTrue);
    });
  });

  test('stabilityOutputPercentile anchors (rain / music / binaural)', () {
    expect(stabilityOutputPercentile(1.5, 0.9), 0);
    expect(stabilityOutputPercentile(2.5, 0.9), 0);
    expect(stabilityOutputPercentile(1.0, 0.9), closeTo(50, 1e-9));
    expect(stabilityOutputPercentile(0.9, 0.9), closeTo(60, 1e-9));
    expect(stabilityOutputPercentile(0.75, 0.9), closeTo(80, 1e-9));
    expect(stabilityOutputPercentile(0.6, 0.9), 100);
    expect(stabilityOutputPercentile(0.0, 0.1), 100);
    expect(stabilityOutputPercentile(double.nan, 0.9), 0);
  });

  group('settings + session metadata', () {
    test('Settings defaults, clamps and band validation', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await Settings.load();
      expect(s.rewardDwellSeconds, 2.5);
      expect(s.stabilityBand, 'band.alpha');
      expect(s.stabilityWindowSeconds, 10);
      expect(s.stabilityDifficulty, 0.10);
      await s.setRewardDwellSeconds(50);
      expect(s.rewardDwellSeconds, 20);
      await s.setRewardDwellSeconds(0.5);
      expect(s.rewardDwellSeconds, 2);
      await s.setStabilityBand('band.atr');
      expect(s.stabilityBand, 'band.alpha');
      await s.setStabilityBand('band.theta');
      expect(s.stabilityBand, 'band.theta');
      await s.setStabilityWindowSeconds(31);
      expect(s.stabilityWindowSeconds, 30);
      await s.setStabilityDifficulty(0.8);
      expect(s.stabilityDifficulty, 0.5);
    });

    test('SessionSettings round-trips dwell + stability; old files null', () {
      SessionSettings base({double? dwell, StabilitySessionSettings? st}) =>
          SessionSettings(
            dynamicAdapt: true,
            responsiveness: 0.5,
            baselinePercentile: 40,
            guardrailEnabled: true,
            guardrailEngine: 'cbramod',
            warningThresholdPercentile: 75,
            warningSound: 'softBowl',
            musicFolder: null,
            musicMinCutoffHz: 0,
            musicMaxCutoffHz: 0,
            musicInvert: false,
            musicShuffle: false,
            binauralPresetId: '',
            binauralCarrierHz: 0,
            binauralBeatHz: 0,
            backgroundBinauralPresetId: '',
            backgroundBinauralCarrierHz: 0,
            backgroundBinauralBeatHz: 0,
            markersInFeedbackEnabled: false,
            eyeMarkersEnabled: false,
            rewardDwellSeconds: dwell,
            stability: st,
          );
      final json = base(
        dwell: 4,
        st: const StabilitySessionSettings(
          band: 'band.beta',
          windowSeconds: 12,
          difficulty: 0.2,
          baselineCv: 0.07,
        ),
      ).toJson();
      final back = SessionSettings.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      )!;
      expect(back.rewardDwellSeconds, 4);
      expect(back.stability!.band, 'band.beta');
      expect(back.stability!.windowSeconds, 12);
      expect(back.stability!.difficulty, 0.2);
      expect(back.stability!.baselineCv, 0.07);
      final old = base().toJson();
      expect(old.containsKey('stability'), isFalse);
      expect(old.containsKey('rewardDwellSeconds'), isFalse);
      final oldBack = SessionSettings.fromJson(old)!;
      expect(oldBack.stability, isNull);
      expect(oldBack.rewardDwellSeconds, isNull);
    });
  });

  group('catalog', () {
    test('bandStability: experimental copy, stability policy, AI guard, '
        'no δ rail', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final catalog = await ProtocolCatalog.load();
      final doc = catalog.forName('bandStability')!;
      expect(doc.isStabilityReward, isTrue);
      expect(doc.reward!.feature, defaultStabilityBand);
      expect(doc.reward!.policy, stabilityPolicy);
      expect(doc.reward!.inhibit, isEmpty);
      expect(doc.guard!.feature, 'ai.a_vig');
      expect(doc.guard!.muffleReward, isTrue);
      expect(doc.guard!.toJson().containsKey('deltaRail'), isFalse);
      for (final text in [doc.title, doc.subtitle, doc.guideText]) {
        expect(text.toLowerCase(), contains('experimental'));
      }
      expect(doc.guideText.toLowerCase(), contains('no evidence'));
      expect(doc.metadataDescription!.toLowerCase(), contains('no evidence'));
      // Snapshot records the band the session actually ran.
      final snap = doc.resolved(
        guardFeature: 'ai.a_vig',
        rewardFeature: 'band.theta',
      );
      expect(snap.reward!.feature, 'band.theta');
      expect(snap.reward!.policy, stabilityPolicy);
      expect(snap.guard!.feature, 'ai.a_vig');
    });

    test('band.theta / band.beta are reward features', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final features = FeatureCatalog.fromJson(
        jsonDecode(await rootBundle.loadString(FeatureCatalog.asset)) as Map,
      );
      for (final id in stabilityBandFeatures) {
        expect(features[id]!.usableAsReward(), isTrue, reason: id);
      }
    });
  });
}
