import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/audio/guard_output.dart';
import 'package:muse_ml/src/audio/reward_output.dart';
import 'package:muse_ml/src/feedback/guard_lane.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/reward_lane.dart';
import 'package:muse_ml/src/feedback/target_state.dart';
import 'package:muse_ml/src/feedback/trust/nerd_model.dart';
import 'package:muse_ml/src/feedback/trust/nerd_sheet.dart';
import 'package:muse_ml/src/feedback/trust/trust_trace.dart';

class _Out implements RewardOutput {
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void onSample({required double percentile, required bool inTarget}) {}

  @override
  void setMuffle(bool on) {}
}

class _GuardOut implements GuardOutput {
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void onGuard({required bool active, required double intensity}) {}
}

RewardLane _reward({
  bool hasReward = true,
  List<TargetCondition> inhibit = const [],
}) {
  final engine = RatioEngine();
  final lane = RewardLane(
    engine: engine,
    output: _Out(),
    onStats: (_) {},
    onComputedFeedback:
        ({
          required ratio,
          required threshold,
          required inTarget,
          required inTargetPct,
        }) {},
    onThresholdChanged: () {},
  );
  lane.configure(
    hasReward: hasReward,
    featureId: 'band.atr',
    inhibit: inhibit,
    electrodeNames: const ['AF7', 'AF8'],
    montageNames: const ['TP9', 'AF7', 'AF8', 'TP10'],
  );
  engine
    ..addBaselineSample(0.8)
    ..addBaselineSample(1.0)
    ..addBaselineSample(1.2)
    ..addBaselineSample(1.4)
    ..computeThreshold();
  lane.lastNative = 1.23;
  lane.lastPercentile = engine.percentileOf(1.23);
  lane.lastRelative = const RelativeTarget(
    deltaRel: 0.15,
    thetaRel: 0.20,
    alphaRel: 0.30,
    betaRel: 0.25,
    gammaRel: 0.10,
  );
  return lane;
}

GuardLane _guard({required bool enabled, bool bandMath = true}) {
  final lane = GuardLane(guardOutput: _GuardOut(), rewardOutput: _Out())
    ..configure(
      enabled: enabled,
      bandMath: bandMath,
      featureId: 'band.delta',
      deltaElectrodes: const [1, 2],
    );
  if (enabled) {
    lane.baselineSleepDir.addAll([0.05, 0.08, 0.10, 0.12, 0.20]);
    lane.threshold = 0.12;
    lane.lastDelta = 0.11;
    lane.lastSleepDir = 0.11;
  }
  return lane;
}

NerdSheetSnapshot _snap({
  RewardLane? reward,
  GuardLane? guard,
  List<TargetCondition> inhibit = const [BetaCeiling(0.20)],
  TrustTrace? trace,
  DateTime? now,
}) {
  return nerdSheetFromLanes(
    reward: reward ?? _reward(inhibit: inhibit),
    guard: guard ?? _guard(enabled: false),
    inhibit: inhibit,
    rewardLabel: 'ATR',
    guardLabel: 'δ',
    trace: trace ?? TrustTrace(),
    now: now ?? DateTime.utc(2026, 1, 1),
    warningThresholdPercentile: 75,
  );
}

void main() {
  test('pile histogram domain includes live and threshold', () {
    final h = NerdHistogram.fromSamples(
      const [1.0, 1.0, 1.2, 1.4],
      extras: const [0.5, 2.0],
    );
    expect(h.min, lessThan(0.5));
    expect(h.max, greaterThan(2.0));
    expect(h.xFraction(h.min), closeTo(0, 1e-9));
    expect(h.xFraction(h.max), closeTo(1, 1e-9));
    expect(h.binOf(1.0), lessThan(h.binOf(1.4)));
    expect(h.counts[h.binOf(1.0)], greaterThanOrEqualTo(2));
  });

  test('live triangle and threshold tick map onto the pile', () {
    final reward = _reward();
    final snap = _snap(reward: reward);
    final pile = snap.rewardPile!;
    expect(pile.live, 1.23);
    expect(pile.threshold, reward.engine.threshold);
    expect(pile.thresholdLabel, 'release');
    final xLive = pile.histogram.xFraction(pile.live!);
    final xThr = pile.histogram.xFraction(pile.threshold!);
    expect(xLive, inInclusiveRange(0, 1));
    expect(xThr, inInclusiveRange(0, 1));
    expect(xLive, isNot(closeTo(xThr, 1e-9)));
  });

  test('band stack carries inhibit ceilings', () {
    final stack = nerdBandStack(
      const RelativeTarget(
        deltaRel: 0.15,
        thetaRel: 0.2,
        alphaRel: 0.3,
        betaRel: 0.25,
        gammaRel: 0.1,
      ),
      const [BetaCeiling(0.20), DeltaCeiling(0.30)],
    )!;
    expect(stack.betaCeiling, 0.20);
    expect(stack.deltaCeiling, 0.30);
    expect(stack.beta, 0.25);
    expect(_snap().bands?.betaCeiling, 0.20);
  });

  test('guard block only if the lane ran', () {
    expect(_snap(guard: _guard(enabled: false)).hasGuard, isFalse);
    expect(_snap(guard: _guard(enabled: true)).hasGuard, isTrue);
  });

  test('band-math guard pile has δ ceiling tick; AI does not', () {
    final band = _snap(guard: _guard(enabled: true, bandMath: true));
    expect(band.guardPile!.extraTick, guardrailDeltaCeiling);
    expect(band.guardPile!.extraTickLabel, 'δ ceiling');
    expect(band.guardRows.any((r) => r.id == NerdRowId.liveDelta), isFalse);

    final ai = _snap(guard: _guard(enabled: true, bandMath: false));
    expect(ai.guardPile!.extraTick, isNull);
    expect(ai.guardRows.any((r) => r.id == NerdRowId.liveDelta), isTrue);
    expect(ai.guardRows.any((r) => r.id == NerdRowId.deltaCeiling), isTrue);
  });

  test('chime cooldown remaining is nerd-only math', () {
    final t0 = DateTime.utc(2026, 1, 1, 12);
    expect(nerdChimeRemaining(now: t0, lastChimeAt: t0).inSeconds, 20);
    expect(
      nerdChimeRemaining(
        now: t0.add(const Duration(seconds: 8)),
        lastChimeAt: t0,
      ).inSeconds,
      12,
    );
    expect(
      nerdChimeRemaining(
        now: t0.add(const Duration(seconds: 25)),
        lastChimeAt: t0,
      ),
      Duration.zero,
    );
  });

  testWidgets('(i) rows present; tap opens explanation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NerdSheetBody(snapshot: _snap())),
      ),
    );
    expect(find.byKey(const Key('nerd-sheet')), findsOneWidget);
    expect(find.text('Nerd'), findsOneWidget);
    expect(find.byKey(const Key('nerd-reward-pile')), findsOneWidget);
    expect(find.byKey(const Key('nerd-band-stack')), findsOneWidget);
    expect(find.byKey(const Key('nerd-guard-pile')), findsNothing);
    expect(find.text('Feature probe'), findsNothing);
    for (final id in [
      NerdRowId.live,
      NerdRowId.pOfPile,
      NerdRowId.threshold,
      NerdRowId.mean,
      NerdRowId.spread,
      NerdRowId.samples,
      NerdRowId.success,
    ]) {
      expect(find.byKey(Key('nerd-row-$id')), findsOneWidget);
      expect(find.byKey(Key('nerd-info-$id')), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('nerd-info-${NerdRowId.live}')));
    await tester.pumpAndSettle();
    expect(find.text('Live metric'), findsWidgets);
    expect(
      find.text(
        'Native feature this second. Sound compares this to the threshold.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('guard (i) rows when the lane ran', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NerdSheetBody(snapshot: _snap(guard: _guard(enabled: true))),
        ),
      ),
    );
    expect(find.byKey(const Key('nerd-guard-pile')), findsOneWidget);
    for (final id in [
      NerdRowId.guardLive,
      NerdRowId.pOfRest,
      NerdRowId.warnThr,
      NerdRowId.warning,
      NerdRowId.cooldown,
    ]) {
      await tester.scrollUntilVisible(
        find.byKey(Key('nerd-row-$id')),
        80,
        scrollable: find.byType(Scrollable),
      );
      expect(find.byKey(Key('nerd-row-$id')), findsOneWidget);
      expect(find.byKey(Key('nerd-info-$id')), findsOneWidget);
    }
    await tester.scrollUntilVisible(
      find.byKey(const Key('nerd-info-${NerdRowId.cooldown}')),
      80,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.byKey(const Key('nerd-info-${NerdRowId.cooldown}')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Minimum 20 s between warning bowls. Sparse vs the continuous warning.',
      ),
      findsOneWidget,
    );
  });
}
