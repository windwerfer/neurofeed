import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/trust/trust_graphs.dart';
import 'package:neurofeed/src/feedback/trust/trust_pane.dart';
import 'package:neurofeed/src/feedback/trust/trust_trace.dart';
import 'package:neurofeed/src/feedback/trust/trust_viewport.dart';
import 'package:neurofeed/src/history/history_trust_viewport.dart';
import 'package:neurofeed/src/history/session_trust.dart';

/// Stability chart (rolling CV ÷ baseline CV vs baseline 1.0 / target line,
/// dirty spans dashed) replaces the percentile reward pane for bandStability.
List<TrustRewardSample> _samples() => [
  for (var i = 0; i < 20; i++)
    TrustRewardSample(
      t: i.toDouble(),
      native: i.isEven ? 0.8 : 1.1,
      percentile: 50,
      thresholdPercentile: 60,
      threshold: 0.9,
      inTarget: i.isEven,
      heldBack: false,
      inhibitTags: const [],
      clean: i < 15,
      dirtyReason: i < 15 ? null : TrustDirtyReason.movement,
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget live(TrustRewardChart chart) {
    final trace = TrustTrace();
    for (final s in _samples()) {
      trace.pushReward(s);
    }
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TrustGraphsColumn(
            trace: trace,
            viewport: TrustViewport(),
            showReward: true,
            showGuard: false,
            showMore: true,
            rewardLabel: 'Alpha',
            guardLabel: 'AI',
            rewardColor: Colors.teal,
            guardColor: Colors.blue,
            rewardChart: chart,
          ),
        ),
      ),
    );
  }

  testWidgets('live: stability chart swaps out the percentile pane', (
    tester,
  ) async {
    await tester.pumpWidget(live(TrustRewardChart.stability));
    expect(find.byKey(const Key('trust-stability-pane')), findsOneWidget);
    expect(find.byKey(const Key('trust-reward-pane')), findsNothing);
    expect(find.byType(StabilityTrustPane), findsOneWidget);

    await tester.pumpWidget(live(TrustRewardChart.percentile));
    expect(find.byKey(const Key('trust-stability-pane')), findsNothing);
    expect(find.byKey(const Key('trust-reward-pane')), findsOneWidget);
  });

  Widget history(TrustRewardChart chart) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 1200,
        child: HistoryTrustReplay(
          trust: SessionTrust(
            reward: _samples(),
            guard: const [],
            marks: const [],
            pctInZone: 50,
            pctInhibited: 0,
            pctWarning: null,
            pctCeiling: null,
            rewardChimes: 0,
            guardChimes: 0,
          ),
          viewport: HistoryTrustViewport(),
          showReward: true,
          showGuard: false,
          onReward: (_) {},
          onGuard: (_) {},
          inhibit: const [],
          guardPanes: const [],
          rewardLabel: 'Alpha',
          guardLabel: 'AI',
          rewardColor: Colors.teal,
          guardColor: Colors.blue,
          rewardChart: chart,
        ),
      ),
    ),
  );

  testWidgets('history: stability sessions replay the stability chart', (
    tester,
  ) async {
    await tester.pumpWidget(history(TrustRewardChart.stability));
    expect(find.byKey(const Key('trust-stability-pane')), findsOneWidget);
    expect(find.byKey(const Key('trust-reward-pane')), findsNothing);

    await tester.pumpWidget(history(TrustRewardChart.percentile));
    expect(find.byKey(const Key('trust-stability-pane')), findsNothing);
    expect(find.byKey(const Key('trust-reward-pane')), findsOneWidget);
  });
}
