import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/history/history_dashboard_summary.dart';
import 'package:neurofeed/src/history/session_trust.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Map<String, Object?> _recordingStats = {
  'hr': {'mean': 64.2, 'min': 54, 'max': 91},
  'spo2': {'mean': 97.4, 'min': 96, 'max': 99},
  'peakAlpha': {'meanHz': 9.8, 'maxPowerHz': 10.2, 'maxPower': 5.2},
  'movement': {'mean': 0.02, 'stillnessPct': 71.2},
  'quality': {
    'mean': 86.4,
    'pctGood': 86.4,
    'channelUsable': {'TP9': 0.94, 'AF7': 0.88},
  },
  'annotationSeconds': {'pause': 10, 'bad_quality': 15, 'disconnect': 8},
  'battery': {'startPct': 81, 'endPct': 76},
  'experimental': {
    'bands': {'meanAlphaAbs': 4.6, 'meanAlphaTheta': 1.7},
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fromSessionTrust copies percents and chime counts', () {
    const trust = SessionTrust(
      reward: [],
      guard: [],
      marks: [],
      pctInZone: 62,
      pctInhibited: null,
      pctWarning: 4,
      pctCeiling: 9,
      rewardChimes: 14,
      guardChimes: 2,
    );
    final totals = HistoryDashboardTotals.fromSessionTrust(trust);
    expect(totals.pctInZone, 62);
    expect(totals.pctInhibited, isNull);
    expect(totals.pctWarning, 4);
    expect(totals.rewardChimes, 14);
    expect(totals.guardChimes, 2);
  });

  testWidgets('More defaults closed, writes the pref, and reopens', (
    tester,
  ) async {
    final settings = await _settings(tester);
    expect(settings.historyDashboardMoreExpanded, isFalse);

    await _pump(
      tester,
      settings,
      const HistoryDashboardSummary(
        durationS: 90,
        stats: {
          'annotationSeconds': {'pause': 10},
        },
      ),
    );
    expect(find.text('More'), findsOneWidget);
    expect(find.text('1:30'), findsOneWidget);
    expect(find.text('Pause 0:10'), findsNothing);

    await tester.tap(find.text('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(settings.historyDashboardMoreExpanded, isTrue);
    expect(find.text('Pause 0:10'), findsOneWidget);
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getBool('history_dashboard_more_expanded'), isTrue);

    final again = await tester.runAsync(Settings.load);
    await _pump(
      tester,
      again!,
      const HistoryDashboardSummary(
        durationS: 90,
        stats: {
          'annotationSeconds': {'pause': 10},
        },
      ),
    );
    expect(again.historyDashboardMoreExpanded, isTrue);
    expect(find.text('Pause 0:10'), findsOneWidget);
  });

  testWidgets('recording stats omit feedback cells and keep More closed', (
    tester,
  ) async {
    final settings = await _settings(tester);
    await _pump(
      tester,
      settings,
      const HistoryDashboardSummary(
        durationS: 18 * 60,
        elapsedSeconds: 5,
        stats: _recordingStats,
      ),
    );

    expect(find.text('18:00'), findsOneWidget);
    expect(find.text('86% good'), findsOneWidget);
    expect(find.text('71% still'), findsOneWidget);
    expect(find.text('Peak α 10.2 Hz'), findsOneWidget);
    expect(find.text('64 bpm'), findsOneWidget);
    expect(find.text('SpO₂ 97%'), findsOneWidget);
    expect(find.textContaining('in zone'), findsNothing);
    expect(find.textContaining('chime'), findsNothing);
    expect(find.textContaining('inhibited'), findsNothing);
    expect(find.text('Pause 0:10'), findsNothing);
    expect(find.text('Mean α 4.6'), findsNothing);
    expect(find.text('0:05'), findsNothing);

    await tester.tap(find.text('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Heart rate 54–91 bpm'), findsOneWidget);
    expect(find.text('SpO₂ 96–99%'), findsOneWidget);
    expect(find.text('Battery 81% → 76%'), findsOneWidget);
    expect(find.text('Pause 0:10'), findsOneWidget);
    expect(find.text('Bad contact 0:15'), findsOneWidget);
    expect(find.text('Disconnect 0:08'), findsOneWidget);
    expect(find.text('TP9 94%'), findsOneWidget);
    expect(find.text('AF7 88%'), findsOneWidget);
    expect(find.text('Mean α 4.6'), findsOneWidget);
    expect(find.text('α/θ 1.7'), findsOneWidget);
    expect(find.textContaining('in zone'), findsNothing);
    expect(find.textContaining('chime'), findsNothing);
  });

  testWidgets('empty and partial stats omit absent cells', (tester) async {
    final settings = await _settings(tester);
    await _pump(tester, settings, const HistoryDashboardSummary());
    expect(tester.takeException(), isNull);
    expect(find.text('More'), findsOneWidget);
    expect(find.textContaining('0'), findsNothing);
    expect(find.textContaining('—'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('chime'), findsNothing);

    await _pump(
      tester,
      settings,
      const HistoryDashboardSummary(
        stats: {
          'hr': 'nope',
          'spo2': 3,
          'quality': {'pctGood': null, 'channelUsable': 'x'},
          'movement': {'stillnessPct': 'still'},
          'peakAlpha': {'meanHz': 10.0},
          'battery': {'startPct': null, 'endPct': null},
          'annotationSeconds': {'pause': 'x'},
          'experimental': true,
        },
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('bpm'), findsNothing);
    expect(find.textContaining('Peak'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('0'), findsNothing);
    expect(find.text('Mean α'), findsNothing);

    await tester.tap(find.text('More'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Battery'), findsNothing);
    expect(find.textContaining('Pause'), findsNothing);
  });

  testWidgets('durationS wins, and 0 falls through to elapsed', (tester) async {
    final settings = await _settings(tester);

    await _pump(
      tester,
      settings,
      const HistoryDashboardSummary(durationS: 0, elapsedSeconds: 125),
    );
    expect(find.text('2:05'), findsOneWidget);
    expect(find.text('0:00'), findsNothing);

    await _pump(
      tester,
      settings,
      const HistoryDashboardSummary(elapsedSeconds: 90),
    );
    expect(find.text('1:30'), findsOneWidget);
  });

  testWidgets('feedback totals fill in-zone cells and More', (tester) async {
    final settings = await _settings(tester, {
      'history_dashboard_more_expanded': true,
    });
    expect(settings.historyDashboardMoreExpanded, isTrue);

    await _pump(
      tester,
      settings,
      const HistoryDashboardSummary(
        stats: {
          'hr': {'min': 54, 'max': 91},
          'battery': {'startPct': 80},
          'quality': {'pctGood': 86},
        },
        feedback: HistoryDashboardTotals(
          pctInZone: 62,
          pctInhibited: null,
          pctWarning: 4,
          rewardChimes: 14,
          guardChimes: 0,
        ),
      ),
    );

    expect(find.text('62% in zone'), findsOneWidget);
    expect(find.text('86% good'), findsOneWidget);
    expect(find.text('14 chimes'), findsOneWidget);
    expect(find.text('— inhibited'), findsOneWidget);
    expect(find.text('4% guard warning'), findsOneWidget);
    expect(find.text('0 guard chimes'), findsOneWidget);
    expect(find.text('Heart rate 54–91 bpm'), findsOneWidget);
    expect(find.text('Battery 80% → —'), findsOneWidget);
    expect(find.textContaining('bpm'), findsNWidgets(1));
  });
}

Future<Settings> _settings(
  WidgetTester tester, [
  Map<String, Object> prefs = const {},
]) async {
  final loaded = await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues(prefs);
    return Settings.load();
  });
  return loaded!;
}

Future<void> _pump(WidgetTester tester, Settings settings, Widget body) {
  return tester.pumpWidget(
    ProviderScope(
      key: ValueKey(identityHashCode(settings)),
      overrides: [settingsProvider.overrideWith((ref) => settings)],
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: body)),
      ),
    ),
  );
}
