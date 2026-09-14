import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/feedback/feedback_phase.dart';
import 'package:muse_ml/src/feedback/session_metadata.dart';
import 'package:muse_ml/src/feedback/trust/trust_chips.dart';
import 'package:muse_ml/src/feedback/trust/trust_gestures.dart';
import 'package:muse_ml/src/feedback/trust/trust_graphs.dart';
import 'package:muse_ml/src/feedback/trust/trust_runs.dart';
import 'package:muse_ml/src/feedback/trust/trust_trace.dart';
import 'package:muse_ml/src/feedback/trust/trust_viewport.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

TrustRewardSample _r({
  required double t,
  required bool clean,
  required bool inTarget,
  bool heldBack = false,
  List<String> tags = const [],
  double percentile = 60,
  TrustDirtyReason? dirty,
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
    test(
      'gray fill+stroke when above line + inhibit fail; label beta high',
      () {
        final run = rewardRuns([
          _r(
            t: 0,
            clean: true,
            inTarget: false,
            heldBack: true,
            tags: ['beta'],
          ),
          _r(
            t: 1,
            clean: true,
            inTarget: false,
            heldBack: true,
            tags: ['beta'],
          ),
        ]).single;
        expect(run.kind, TrustStrokeKind.heldBack);
        expect(rewardRunLabel(run), 'beta high');
        expect(
          shouldPaintHeldBackFill(gate: kTrustHeldBackFill, kind: run.kind),
          isTrue,
        );
      },
    );

    test('below-the-line is not gray', () {
      final run = rewardRuns([_r(t: 0, clean: true, inTarget: false)]).single;
      expect(run.kind, TrustStrokeKind.below);
      expect(shouldPaintHeldBackFill(gate: true, kind: run.kind), isFalse);
    });

    test('kTrustHeldBackFill gates the fill', () {
      expect(
        shouldPaintHeldBackFill(gate: false, kind: TrustStrokeKind.heldBack),
        isFalse,
      );
      expect(
        shouldPaintHeldBackFill(gate: true, kind: TrustStrokeKind.heldBack),
        isTrue,
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
