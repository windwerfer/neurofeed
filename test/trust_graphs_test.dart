import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/feedback_phase.dart';
import 'package:neurofeed/src/feedback/guardrail_mode.dart';
import 'package:neurofeed/src/feedback/protocol.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/feedback/trust/trust_chips.dart';
import 'package:neurofeed/src/feedback/trust/trust_gestures.dart';
import 'package:neurofeed/src/feedback/trust/trust_graphs.dart';
import 'package:neurofeed/src/feedback/trust/trust_guard.dart';
import 'package:neurofeed/src/feedback/trust/trust_inhibit.dart';
import 'package:neurofeed/src/feedback/trust/trust_more.dart';
import 'package:neurofeed/src/feedback/trust/trust_runs.dart';
import 'package:neurofeed/src/feedback/trust/trust_trace.dart';
import 'package:neurofeed/src/feedback/trust/trust_viewport.dart';
import 'package:neurofeed/src/rust/api/muse.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

TrustRewardSample _r({
  required double t,
  required bool clean,
  required bool inTarget,
  bool heldBack = false,
  List<String> tags = const [],
  double percentile = 60,
  TrustDirtyReason? dirty,
  double? betaRel,
  double? deltaRel,
}) => TrustRewardSample(
  t: t,
  native: 1,
  percentile: percentile,
  thresholdPercentile: 40,
  inTarget: inTarget,
  heldBack: heldBack,
  inhibitTags: tags,
  clean: clean,
  dirtyReason: dirty,
  betaRel: betaRel,
  deltaRel: deltaRel,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('chips', () {
    test('defaults Reward on, Guard off, More on; guardrailOnly Guard on', () {
      const both = TrustLaneFlags(hasReward: true, guardRunning: true);
      expect(both.showRewardChip, isTrue);
      expect(both.showGuardChip, isTrue);
      expect(both.showRow, isTrue);
      expect(both.defaultGuardOn, isFalse);

      const guardOnly = TrustLaneFlags(hasReward: false, guardRunning: true);
      expect(guardOnly.showRewardChip, isFalse);
      expect(guardOnly.showGuardChip, isTrue);
      expect(guardOnly.defaultGuardOn, isTrue);

      const recordOnly = TrustLaneFlags(hasReward: false, guardRunning: false);
      expect(recordOnly.showRow, isFalse);
    });

    test(
      'omit Reward without a reward lane; omit Guard without a live guard',
      () {
        const noReward = TrustLaneFlags(hasReward: false, guardRunning: true);
        expect(noReward.showRewardChip, isFalse);
        const noGuard = TrustLaneFlags(hasReward: true, guardRunning: false);
        expect(noGuard.showGuardChip, isFalse);
      },
    );

    test(
      'persist three bools; never-set Guard follows defaultGuardOn',
      () async {
        SharedPreferences.setMockInitialValues({});
        final settings = await Settings.load();
        expect(settings.trustRewardVisible, isTrue);
        expect(settings.trustMoreVisible, isTrue);
        expect(settings.trustGuardVisibleOrNull, isNull);
        expect(settings.trustGuardVisible(rewardChipShown: true), isFalse);
        expect(settings.trustGuardVisible(rewardChipShown: false), isTrue);

        await settings.setTrustRewardVisible(false);
        await settings.setTrustGuardVisible(true);
        await settings.setTrustMoreVisible(false);
        expect(settings.trustRewardVisible, isFalse);
        expect(settings.trustGuardVisible(rewardChipShown: true), isTrue);
        expect(settings.trustMoreVisible, isFalse);
      },
    );

    testWidgets(
      'chip row hides for recordOnly; omits Reward on guardrailOnly',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TrustChipRow(
                flags: const TrustLaneFlags(
                  hasReward: false,
                  guardRunning: false,
                ),
                rewardOn: true,
                guardOn: true,
                moreOn: true,
                onReward: (_) {},
                onGuard: (_) {},
                onMore: (_) {},
              ),
            ),
          ),
        );
        expect(find.text('Reward'), findsNothing);
        expect(find.text('Guard'), findsNothing);
        expect(find.text('More'), findsNothing);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TrustChipRow(
                flags: const TrustLaneFlags(
                  hasReward: false,
                  guardRunning: true,
                ),
                rewardOn: false,
                guardOn: true,
                moreOn: true,
                onReward: (_) {},
                onGuard: (_) {},
                onMore: (_) {},
              ),
            ),
          ),
        );
        expect(find.text('Reward'), findsNothing);
        expect(find.text('Guard'), findsOneWidget);
        expect(find.text('More'), findsOneWidget);
      },
    );
  });

  group('held back', () {
    test('above line + inhibit fail is held back; label beta high', () {
      final run = rewardRuns([
        _r(t: 0, clean: true, inTarget: false, heldBack: true, tags: ['beta']),
        _r(t: 1, clean: true, inTarget: false, heldBack: true, tags: ['beta']),
      ]).single;
      expect(run.kind, TrustStrokeKind.heldBack);
      expect(rewardRunLabel(run), 'beta high');
    });

    test('gray wash when inhibit is out, even below the line', () {
      final belowOut = _r(t: 0, clean: true, inTarget: false, tags: ['beta']);
      final belowOk = _r(t: 1, clean: true, inTarget: false);
      final aboveOut = _r(
        t: 2,
        clean: true,
        inTarget: false,
        heldBack: true,
        tags: ['delta'],
      );
      expect(shouldPaintInhibitWash(gate: true, sample: belowOut), isTrue);
      expect(shouldPaintInhibitWash(gate: true, sample: belowOk), isFalse);
      expect(shouldPaintInhibitWash(gate: true, sample: aboveOut), isTrue);
      expect(shouldPaintInhibitWash(gate: false, sample: belowOut), isFalse);
    });

    test('dirty is not a gray wash', () {
      expect(
        shouldPaintInhibitWash(
          gate: true,
          sample: _r(
            t: 0,
            clean: false,
            inTarget: false,
            tags: ['beta'],
            dirty: TrustDirtyReason.movement,
          ),
        ),
        isFalse,
      );
    });

    test('kTrustInhibitWash gates the fill', () {
      final out = _r(t: 0, clean: true, inTarget: true, tags: ['beta']);
      expect(kTrustInhibitWash, isTrue);
      expect(
        shouldPaintInhibitWash(gate: kTrustInhibitWash, sample: out),
        isTrue,
      );
      expect(shouldPaintInhibitWash(gate: false, sample: out), isFalse);
    });

    test('fill occupancy uses next sample t, so 5 s is wider than 1 s', () {
      const visEnd = 75.0;
      final oneSecond = heldBackFillEnd(tEnd: 1, nextT: 2, visEnd: visEnd) - 1;
      final fiveSeconds =
          heldBackFillEnd(tEnd: 4, nextT: 5, visEnd: visEnd) - 0;
      expect(oneSecond, 1);
      expect(fiveSeconds, 5);
      expect(fiveSeconds, greaterThan(oneSecond));
      expect(heldBackFillEnd(tEnd: 10, nextT: null, visEnd: 15), 15);
    });

    test('kind change still joins a segment instead of two dots', () {
      final inZone = _r(t: 0, clean: true, inTarget: true);
      final held = _r(
        t: 1,
        clean: true,
        inTarget: false,
        heldBack: true,
        tags: ['beta'],
      );
      final runs = rewardRuns([inZone, held]);
      expect(runs, hasLength(2));
      expect(
        runStrokeSamples(runs[0].samples, runs[1].samples.first),
        hasLength(2),
      );
    });
  });

  group('verdict', () {
    test('priority noisy > held back > below > in zone', () {
      expect(
        rewardVerdict(_r(t: 0, clean: false, inTarget: true, heldBack: true)),
        TrustRewardVerdict.noisy,
      );
      expect(
        rewardVerdict(_r(t: 0, clean: true, inTarget: false, heldBack: true)),
        TrustRewardVerdict.heldBack,
      );
      expect(
        rewardVerdict(_r(t: 0, clean: true, inTarget: false)),
        TrustRewardVerdict.below,
      );
      expect(
        rewardVerdict(_r(t: 0, clean: true, inTarget: true)),
        TrustRewardVerdict.inZone,
      );
    });
  });

  group('More', () {
    testWidgets('strip populates immediately; no warming up', (tester) async {
      final samples = [
        _r(t: 0, clean: true, inTarget: true),
        _r(t: 1, clean: true, inTarget: false),
        _r(t: 2, clean: true, inTarget: true),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TrustRewardMore(samples: samples)),
        ),
      );
      expect(find.text('warming up…'), findsNothing);
      expect(find.textContaining('% in zone'), findsOneWidget);
    });

    testWidgets('More glued to visible lanes; guard More is one block', (
      tester,
    ) async {
      final trace = TrustTrace();
      final viewport = TrustViewport();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrustGraphsColumn(
              trace: trace,
              viewport: viewport,
              showReward: true,
              showGuard: false,
              showMore: true,
              rewardLabel: 'ATR',
              guardLabel: 'δ',
              rewardColor: Colors.green,
              guardColor: Colors.blue,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('trust-reward-more')), findsOneWidget);
      expect(find.byKey(const Key('trust-guard-more')), findsNothing);
      expect(find.byKey(const Key('trust-reward-pane')), findsOneWidget);
      expect(find.byKey(const Key('trust-inhibit-pane-beta')), findsNothing);
      expect(find.byKey(const Key('trust-inhibit-pane-delta')), findsNothing);
      expect(find.byKey(const Key('trust-guard-warn-pane')), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrustGraphsColumn(
              trace: trace,
              viewport: viewport,
              showReward: false,
              showGuard: true,
              showMore: true,
              rewardLabel: 'ATR',
              guardLabel: 'δ',
              rewardColor: Colors.green,
              guardColor: Colors.blue,
              guardPanes: trustGuardPaneSpecs(guardFeatureAiDrowsiness),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('trust-reward-more')), findsNothing);
      expect(find.byKey(const Key('trust-guard-more')), findsOneWidget);
      expect(find.byKey(const Key('trust-guard-warn-pane')), findsOneWidget);
      expect(find.byKey(const Key('trust-guard-ceiling-pane')), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrustGraphsColumn(
              trace: trace,
              viewport: viewport,
              showReward: true,
              showGuard: true,
              showMore: false,
              rewardLabel: 'ATR',
              guardLabel: 'δ',
              rewardColor: Colors.green,
              guardColor: Colors.blue,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('trust-reward-more')), findsNothing);
      expect(find.byKey(const Key('trust-guard-more')), findsNothing);
    });

    testWidgets('inhibit panes 0/1/2 under Reward; hidden if Reward is off', (
      tester,
    ) async {
      final trace = TrustTrace();
      final viewport = TrustViewport();
      final none = trustInhibitSpecs(const []);
      final one = trustInhibitSpecs(const [BetaCeiling(0.25)]);
      final two = trustInhibitSpecs([
        const BetaCeiling(0.25),
        const DeltaCeiling(0.5),
      ]);

      Future<void> pump({
        required bool showReward,
        required List<TrustInhibitSpec> inhibit,
      }) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrustGraphsColumn(
              trace: trace,
              viewport: viewport,
              showReward: showReward,
              showGuard: !showReward,
              showMore: false,
              rewardLabel: 'ATR',
              guardLabel: 'δ',
              rewardColor: Colors.green,
              guardColor: Colors.blue,
              inhibit: inhibit,
            ),
          ),
        ),
      );

      await pump(showReward: true, inhibit: none);
      expect(find.byKey(const Key('trust-reward-pane')), findsOneWidget);
      expect(find.byKey(const Key('trust-inhibit-pane-beta')), findsNothing);
      expect(find.byKey(const Key('trust-inhibit-pane-delta')), findsNothing);

      await pump(showReward: true, inhibit: one);
      expect(find.byKey(const Key('trust-reward-pane')), findsOneWidget);
      expect(find.byKey(const Key('trust-inhibit-pane-beta')), findsOneWidget);
      expect(find.byKey(const Key('trust-inhibit-pane-delta')), findsNothing);

      await pump(showReward: true, inhibit: two);
      expect(find.byKey(const Key('trust-reward-pane')), findsOneWidget);
      expect(find.byKey(const Key('trust-inhibit-pane-beta')), findsOneWidget);
      expect(find.byKey(const Key('trust-inhibit-pane-delta')), findsOneWidget);

      await pump(showReward: false, inhibit: two);
      expect(find.byKey(const Key('trust-reward-pane')), findsNothing);
      expect(find.byKey(const Key('trust-inhibit-pane-beta')), findsNothing);
      expect(find.byKey(const Key('trust-inhibit-pane-delta')), findsNothing);
    });

    testWidgets('guard panes follow distinct warn signals', (tester) async {
      final trace = TrustTrace();
      final viewport = TrustViewport();

      Future<void> pump(List<TrustGuardPaneId> panes) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrustGraphsColumn(
              trace: trace,
              viewport: viewport,
              showReward: false,
              showGuard: true,
              showMore: false,
              rewardLabel: 'ATR',
              guardLabel: 'δ',
              rewardColor: Colors.green,
              guardColor: Colors.blue,
              guardPanes: panes,
            ),
          ),
        ),
      );

      await pump(trustGuardPaneSpecs(guardFeatureBandDelta));
      expect(find.byKey(const Key('trust-guard-warn-pane')), findsOneWidget);
      expect(find.byKey(const Key('trust-guard-ceiling-pane')), findsNothing);

      await pump(trustGuardPaneSpecs(guardFeatureAiDrowsiness));
      expect(find.byKey(const Key('trust-guard-warn-pane')), findsOneWidget);
      expect(find.byKey(const Key('trust-guard-ceiling-pane')), findsOneWidget);
    });
  });

  group('guard panes', () {
    test('specs: none empty; band-math warn only; AI warn + ceiling', () {
      expect(trustGuardPaneSpecs(guardFeatureNone), isEmpty);
      expect(trustGuardPaneSpecs(guardFeatureBandDelta), [
        TrustGuardPaneId.warn,
      ]);
      expect(trustGuardPaneSpecs(guardFeatureAiDrowsiness), [
        TrustGuardPaneId.warn,
        TrustGuardPaneId.ceiling,
      ]);
    });
  });

  group('inhibit', () {
    test('specs: one or two ceilings, omitted when empty', () {
      expect(trustInhibitSpecs(const []), isEmpty);
      expect(trustInhibitSpecs(const [BetaCeiling(0.25)]), [
        const TrustInhibitSpec(id: TrustInhibitId.beta, ceiling: 0.25),
      ]);
      final both = trustInhibitSpecs(const [
        BetaCeiling(0.25),
        DeltaCeiling(0.5),
      ]);
      expect(both, hasLength(2));
      expect(both[0].id, TrustInhibitId.beta);
      expect(both[1].id, TrustInhibitId.delta);
      expect(inhibitPaneLabel(both), 'β · δ');
    });

    test('series and overshoot colors stay distinct for two inhibitors', () {
      const error = Color(0xFFB00020);
      final beta = inhibitSeriesColor(TrustInhibitId.beta);
      final delta = inhibitSeriesColor(TrustInhibitId.delta);
      final betaOver = inhibitOvershootColor(TrustInhibitId.beta, error);
      final deltaOver = inhibitOvershootColor(TrustInhibitId.delta, error);
      expect(beta, isNot(delta));
      expect(betaOver, isNot(beta));
      expect(deltaOver, isNot(delta));
      expect(betaOver, isNot(deltaOver));
      expect(betaOver, isNot(delta));
      expect(deltaOver, isNot(beta));
    });

    test('overshoot is y > ceiling; dirty is dotted not overshoot', () {
      const spec = TrustInhibitSpec(id: TrustInhibitId.beta, ceiling: 0.25);
      final inside = _r(t: 0, clean: true, inTarget: true, betaRel: 0.10);
      final over = _r(
        t: 1,
        clean: true,
        inTarget: false,
        tags: ['beta'],
        heldBack: true,
        betaRel: 0.40,
      );
      final dirty = _r(
        t: 2,
        clean: false,
        inTarget: false,
        dirty: TrustDirtyReason.movement,
        betaRel: 0.40,
      );
      expect(inhibitStrokeKind(inside, spec), TrustInhibitKind.inside);
      expect(inhibitStrokeKind(over, spec), TrustInhibitKind.overshoot);
      expect(inhibitStrokeKind(dirty, spec), TrustInhibitKind.dirty);
      final runs = inhibitRuns([inside, over, dirty], spec);
      expect(runs.map((r) => r.kind), [
        TrustInhibitKind.inside,
        TrustInhibitKind.overshoot,
        TrustInhibitKind.dirty,
      ]);
    });

    test('wash spans cover inhibit-out occupancy including below-the-line', () {
      final spans = inhibitWashSpans([
        _r(t: 0, clean: true, inTarget: false, tags: ['beta']),
        _r(t: 1, clean: true, inTarget: false, tags: ['beta']),
        _r(t: 2, clean: true, inTarget: false),
        _r(t: 3, clean: true, inTarget: false, heldBack: true, tags: ['delta']),
      ], visEnd: 10);
      expect(spans, hasLength(2));
      expect(spans[0].tStart, 0);
      expect(spans[0].tEnd, 2);
      expect(spans[1].tStart, 3);
      expect(spans[1].tEnd, 10);
    });

    test('dirty holds last clean inhibit Y', () {
      final trace = TrustTrace();
      trace.pushReward(
        _r(t: 0, clean: true, inTarget: true, betaRel: 0.12, deltaRel: 0.20),
      );
      trace.pushReward(
        _r(
          t: 1,
          clean: false,
          inTarget: false,
          dirty: TrustDirtyReason.movement,
          betaRel: 0.90,
          deltaRel: 0.90,
        ),
      );
      expect(trace.reward.last.plotBetaRel, 0.12);
      expect(trace.reward.last.plotDeltaRel, 0.20);
      expect(trace.reward.last.plotPercentile, 60);
    });

    test('axis max leaves room above the highest ceiling', () {
      expect(
        inhibitAxisMax(const [
          TrustInhibitSpec(id: TrustInhibitId.beta, ceiling: 0.25),
        ]),
        0.5,
      );
      expect(
        inhibitAxisMax(const [
          TrustInhibitSpec(id: TrustInhibitId.beta, ceiling: 0.25),
          TrustInhibitSpec(id: TrustInhibitId.delta, ceiling: 0.5),
        ]),
        closeTo(0.7, 1e-9),
      );
    });
  });

  group('viewport', () {
    test('default 75 s, clamp 15–300, pinch and zoom stay Follow', () {
      final v = TrustViewport();
      expect(v.windowSeconds, 75);
      expect(v.rightEdgeIsNow, isTrue);
      v.setWindowSeconds(5);
      expect(v.windowSeconds, 15);
      v.setWindowSeconds(900);
      expect(v.windowSeconds, 300);
      v.setWindowSeconds(75);
      v.pinch(scaleFromStart: 2, windowAtStart: 75);
      expect(v.windowSeconds, closeTo(37.5, 1e-9));
      expect(v.rightEdgeIsNow, isTrue);
      v.zoomBy(2);
      expect(v.windowSeconds, closeTo(75, 1e-9));
      expect(v.rightEdgeIsNow, isTrue);
    });
  });

  group('marks', () {
    test('Blink/Jaw land on the live ring when persist is off', () {
      final live = TrustTrace();
      final persisted = <GestureMarker>[];
      final tracker = TrustGestureTracker();
      final t0 = DateTime.utc(2026, 1, 1);
      expect(
        tracker.ingest(
          const GestureDto(timestamp: 0, blinkCount: 1, clench: false, eye: 0),
          t0,
        ),
        isEmpty,
      );
      final types = tracker.ingest(
        const GestureDto(timestamp: 1, blinkCount: 1, clench: false, eye: 0),
        t0.add(const Duration(seconds: 1)),
      );
      expect(types, [GestureType.doubleBlink]);
      recordLiveMark(
        live: live,
        persisted: persisted,
        persistEnabled: false,
        type: types.single,
        t: 3,
      );
      expect(live.marks, hasLength(1));
      expect(live.marks.single.label, 'Blink');
      expect(persisted, isEmpty);

      tracker.ingest(
        const GestureDto(timestamp: 2, blinkCount: 0, clench: true, eye: 0),
        t0.add(const Duration(seconds: 3)),
      );
      tracker.ingest(
        const GestureDto(timestamp: 2.5, blinkCount: 0, clench: false, eye: 0),
        t0.add(const Duration(milliseconds: 3500)),
      );
      final jaw = tracker.ingest(
        const GestureDto(timestamp: 3, blinkCount: 0, clench: true, eye: 0),
        t0.add(const Duration(seconds: 4)),
      );
      expect(jaw, [GestureType.doubleClench]);
      recordLiveMark(
        live: live,
        persisted: persisted,
        persistEnabled: false,
        type: jaw.single,
        t: 5,
      );
      expect(live.marks.last.label, 'Jaw');
      expect(persisted, isEmpty);
    });
  });

  group('calibration', () {
    test('graphs/More are not built while calibrating', () {
      expect(trustGraphsVisible(FeedbackPhase.calibrating), isFalse);
      expect(trustGraphsVisible(FeedbackPhase.idle), isFalse);
      expect(trustGraphsVisible(FeedbackPhase.playing), isTrue);
      expect(trustGraphsVisible(FeedbackPhase.paused), isTrue);
    });
  });
}
