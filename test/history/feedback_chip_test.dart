import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/connection_provider.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';
import 'package:neurofeed/src/feedback/trust/trust_pane.dart';
import 'package:neurofeed/src/feedback/trust/trust_viewport.dart';
import 'package:neurofeed/src/history/history_trust_viewport.dart';
import 'package:neurofeed/src/history/session_trust.dart';
import 'package:neurofeed/src/rust/api/session_format.dart';
import 'package:neurofeed/src/rust/frb_generated.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/spine/assemble.dart';
import 'package:neurofeed/src/views/feedback_dashboard.dart';
import 'package:neurofeed/src/views/feedback_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

final String _rustLibPath =
    '${Directory.current.path}/rust/target/debug/librust_lib_neurofeed.so';

const _rewardFooter = '10% in zone · 7 chimes · 1% inhibited';
const _guardFooter = '50% warning · 2 chimes · 10% over ceiling';

Float32List _band() =>
    Float32List.fromList(const [10.0, 20.0, 40.0, 15.0, 5.0]);

ComputedFrame _frame(
  int i, {
  bool rewardClean = true,
  bool omitReward = false,
  bool inTarget = false,
  bool heldBack = false,
  double percentile = 70,
  bool guardClean = true,
  bool warning = false,
  bool ceilingOver = false,
}) {
  return ComputedFrame(
    t: i.toDouble(),
    bands: [_band(), _band(), _band(), _band()],
    pulse: 64,
    movement: 0.05,
    spo2: 97,
    lineNoise: Float32List.fromList(const [0.01, 0.01, 0.01, 0.01]),
    signalQuality: Uint8List.fromList(const [90, 90, 90, 90]),
    guardrail: GuardrailInfo(
      sleepDir: 0.2,
      clarity: 0.8,
      warning: warning,
      delta: 0.3,
      featurePercentile: 40,
      warnOver: warning,
      ceilingOver: ceilingOver,
      clean: guardClean,
    ),
    feedback: FeedbackInfo(
      ratio: 1.2,
      threshold: 1,
      inTarget: inTarget,
      pct: 0.5,
      percentile: percentile,
      thresholdPercentile: 40,
      heldBack: heldBack,
      inhibitTags: const [],
      clean: omitReward ? null : rewardClean,
      betaRel: rewardClean ? 0.2 : 0.9,
      deltaRel: 0.1,
    ),
    gestures: const [],
  );
}

List<ComputedFrame> _concentrationFrames() => [
  for (var i = 0; i < 80; i++)
    _frame(
      i,
      rewardClean: i != 1,
      percentile: i == 1 ? 11 : 70,
      inTarget: i < 9 && i != 1,
      heldBack: i == 0,
      warning: i >= 40,
      ceilingOver: i >= 72,
    ),
];

const _audioEvents = <Map<String, Object?>>[
  {'type': 'reward_chime', 't': 1},
  {'type': 'reward_chime', 't': 2},
  {'type': 'reward_chime', 't': 3},
  {'type': 'reward_chime', 't': 4},
  {'type': 'reward_chime', 't': 5},
  {'type': 'reward_chime', 't': 6},
  {'type': 'reward_chime', 't': 7},
  {'type': 'guard_chime', 't': 8},
  {'type': 'guard_chime', 't': 9},
  {'type': 'not_a_chime', 't': 10},
];

const _annotations = <Map<String, Object?>>[
  {'onset': 6, 'duration': 0, 'type': 'double_blink'},
  {'onset': 7, 'duration': 0, 'type': 'eye_up'},
  {'onset': 8, 'duration': 0, 'type': 'double_jaw_clench'},
];

Map<String, Object?> _meta({
  required String protocol,
  Map<String, Object?>? sessionSettings,
  List<Map<String, Object?>> audioEvents = const [],
  List<Map<String, Object?>> annotations = const [],
  num elapsed = 80,
}) {
  return {
    'formatVersion': 6,
    'kind': 'feedback',
    'savedAt': '2026-10-02T00:00:00Z',
    'startedAt': '2026-10-02T00:00:00Z',
    'elapsedSeconds': elapsed,
    'durationS': elapsed,
    'notes': 'kept',
    if (annotations.isNotEmpty) 'annotations': annotations,
    'stats': {
      'quality': {'pctGood': 86},
      'movement': {'stillnessPct': 71},
    },
    'feedback': {
      'protocol': protocol,
      'durationMinutes': 15,
      'sound': 'Ambient Drone',
      if (sessionSettings != null) 'sessionSettings': sessionSettings,
      if (audioEvents.isNotEmpty) 'audioEvents': audioEvents,
    },
  };
}

SessionTrust _trust(List<ComputedFrame> frames) => readSessionTrust(
  frames: frames,
  annotations: [
    for (final row in _annotations)
      SessionAnnotation(
        onset: (row['onset'] as num).toDouble(),
        duration: (row['duration'] as num).toDouble(),
        type: row['type'] as String,
      ),
  ],
  audioEvents: _audioEvents,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init(externalLibrary: ExternalLibrary.open(_rustLibPath));
  });

  test('concentration totals are the whole session, not the 75 s window', () {
    final trust = _trust(_concentrationFrames());
    expect(trust.pctInZone!.round(), 10);
    expect(trust.pctInhibited!.round(), 1);
    expect(trust.pctWarning!.round(), 50);
    expect(trust.pctCeiling!.round(), 10);
    expect(trust.rewardChimes, 7);
    expect(trust.guardChimes, 2);
    expect(historyRewardFooter(trust), _rewardFooter);
    expect(historyGuardFooter(trust, ceiling: true), _guardFooter);
    expect(historyGuardFooter(trust, ceiling: false), '50% warning · 2 chimes');
    expect(trust.reward[1].percentile, 11);
    expect(trust.reward[1].plotPercentile, 70);
    expect(trust.reward[1].plotBetaRel, 0.2);
    expect(trust.marks.map((mark) => mark.label), ['Blink', 'Jaw']);
  });

  testWidgets('Feedback chip replays panes and ignores trust prefs', (
    tester,
  ) async {
    final settings = await _settings(
      tester,
      prefs: {
        'trust_reward_visible': false,
        'trust_guard_visible': true,
        'inhibit_ceilings': jsonEncode({
          'concentration': {'beta': 0.11},
        }),
      },
    );
    final frames = _concentrationFrames();
    final file = await tester.runAsync(
      () => _write(
        _meta(
          protocol: 'concentration',
          sessionSettings: {
            'guardFeature': 'ai.a_vig',
            'inhibitCeilingOverrides': {'beta': 0.42},
          },
          audioEvents: _audioEvents,
          annotations: _annotations,
        ),
        frames,
      ),
    );
    _deleteLater(file!);
    await _open(tester, settings, file.path);

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Feedback'), findsOneWidget);
    expect(find.text('10% in zone'), findsOneWidget);
    expect(find.text(_rewardFooter), findsNothing);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('HR+SpO2'), findsOneWidget);
    expect(find.text('Movement'), findsOneWidget);
    expect(find.textContaining('Bands (relative power'), findsNothing);
    expect(find.text('Sleep guardrail (AI model)'), findsNothing);
    expect(find.byKey(const Key('trust-reward-pane')), findsNothing);
    expect(find.text('Save'), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.text('Feedback'));
    await tester.pump();

    expect(find.text('Notes'), findsNothing);
    expect(find.text(_rewardFooter), findsOneWidget);
    expect(find.text('In zone'), findsNothing);
    expect(find.textContaining('Above the line'), findsNothing);
    expect(find.textContaining('in for'), findsNothing);
    expect(find.byKey(const Key('trust-reward-more')), findsNothing);
    expect(find.byKey(const Key('trust-guard-more')), findsNothing);

    final reward = tester.widget<RewardTrustPane>(
      find.byKey(const Key('trust-reward-pane')),
    );
    expect(reward.viewport, isA<HistoryTrustViewport>());
    expect(reward.viewport, isNot(isA<TrustViewport>()));
    expect(reward.label, 'α');
    expect(reward.samples, hasLength(80));
    expect(reward.samples[1].percentile, 11);
    expect(reward.samples[1].plotPercentile, 70);
    expect(reward.samples[1].plotBetaRel, closeTo(0.2, 1e-5));
    expect(reward.marks.map((mark) => mark.label), ['Blink', 'Jaw']);

    final inhibit = tester.widget<InhibitTrustPane>(
      find.byKey(const Key('trust-inhibit-pane-beta')),
    );
    expect(inhibit.spec.ceiling, 0.42);
    expect(identical(inhibit.samples, reward.samples), isTrue);
    expect(identical(inhibit.marks, reward.marks), isTrue);
    expect(find.byKey(const Key('trust-inhibit-pane-delta')), findsNothing);

    expect(find.byKey(const Key('trust-guard-warn-pane')), findsNothing);
    expect(find.byKey(const Key('trust-guard-ceiling-pane')), findsNothing);
    expect(find.textContaining('over ceiling'), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('history-trust-range'))).data,
      '0:04 – 1:19',
    );

    final toggles = tester.widget<ToggleButtons>(find.byType(ToggleButtons));
    expect(toggles.isSelected, [true, false]);
    expect(settings.trustRewardVisible, isFalse);
    expect(settings.trustGuardVisible(rewardChipShown: true), isTrue);

    final viewport = reward.viewport as HistoryTrustViewport;
    final start = viewport.visibleStart(79);
    viewport.dragBy(dx: 40, plotWidth: 200);
    await tester.pump();
    expect(viewport.visibleStart(79), isNot(start));
    expect(find.text(_rewardFooter), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('history-trust-range'))).data,
      isNot('0:04 – 1:19'),
    );

    await tester.tap(find.text('Guard'));
    await tester.pump();
    final warn = tester.widget<GuardWarnPane>(
      find.byKey(const Key('trust-guard-warn-pane')),
    );
    expect(warn.label, 'A-vig');
    expect(warn.samples, hasLength(80));
    expect(identical(warn.marks, reward.marks), isTrue);
    expect(find.byKey(const Key('trust-guard-ceiling-pane')), findsOneWidget);
    expect(find.text(_guardFooter), findsOneWidget);
    expect(find.text('In zone'), findsNothing);
    expect(find.textContaining('in for'), findsNothing);

    await tester.tap(find.text('Reward'));
    await tester.pump();
    expect(find.byKey(const Key('trust-reward-pane')), findsNothing);
    expect(find.text(_rewardFooter), findsNothing);
    expect(find.text(_guardFooter), findsOneWidget);
    expect(settings.trustRewardVisible, isFalse);
    expect(settings.trustGuardVisible(rewardChipShown: true), isTrue);
    expect(
      tester.widget<ToggleButtons>(find.byType(ToggleButtons)).isSelected,
      [false, true],
    );

    await tester.tap(find.text('Dashboard'));
    await tester.pump();
    expect(find.text('Notes'), findsOneWidget);
    expect(find.textContaining('Bands (relative power'), findsNothing);
    expect(find.text('10% in zone'), findsOneWidget);
    expect(find.text(_rewardFooter), findsNothing);
  });

  testWidgets('legacy recordOnly fixture has no Feedback chip', (tester) async {
    final settings = await _settings(tester);
    final file = await tester.runAsync(
      () => _write(_meta(protocol: 'recordOnly', elapsed: 5), [
        _frame(0, inTarget: true),
        _frame(1, inTarget: true),
      ]),
    );
    _deleteLater(file!);
    await _open(tester, settings, file.path);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Feedback'), findsNothing);
    expect(find.text('HR+SpO2'), findsOneWidget);
    expect(find.text('Movement'), findsOneWidget);
    expect(find.text('100% in zone'), findsOneWidget);
    expect(find.byKey(const Key('trust-reward-pane')), findsNothing);
  });

  testWidgets('guardrailOnly shows guard panes only, without a ceiling', (
    tester,
  ) async {
    final settings = await _settings(tester);
    final file = await tester.runAsync(
      () => _write(_meta(protocol: 'guardrailOnly', elapsed: 2), [
        _frame(0, omitReward: true, warning: true),
        _frame(1, omitReward: true, warning: false),
      ]),
    );
    _deleteLater(file!);
    await _open(tester, settings, file.path);
    expect(find.text('Feedback'), findsOneWidget);

    await tester.tap(find.text('Feedback'));
    await tester.pump();

    expect(find.textContaining('in zone'), findsNothing);
    expect(find.text('Reward'), findsNothing);
    expect(find.byKey(const Key('trust-reward-pane')), findsNothing);
    expect(find.byKey(const Key('history-reward-footer')), findsNothing);
    expect(find.byKey(const Key('trust-inhibit-pane-beta')), findsNothing);
    expect(find.byKey(const Key('trust-guard-warn-pane')), findsOneWidget);
    expect(find.byKey(const Key('trust-guard-ceiling-pane')), findsNothing);
    expect(find.text('50% warning · 0 chimes'), findsOneWidget);
    expect(find.textContaining('over ceiling'), findsNothing);
    expect(find.text('In zone'), findsNothing);
    expect(find.textContaining('Above the line'), findsNothing);
    expect(find.textContaining('in for'), findsNothing);
    expect(
      tester.widget<ToggleButtons>(find.byType(ToggleButtons)).isSelected,
      [true],
    );
  });

  testWidgets('null percents render as an em dash', (tester) async {
    final settings = await _settings(tester);
    final file = await tester.runAsync(
      () => _write(
        _meta(
          protocol: 'concentration',
          elapsed: 1,
          sessionSettings: {'guardFeature': 'band.delta'},
        ),
        [_frame(0, rewardClean: false, guardClean: false)],
      ),
    );
    _deleteLater(file!);
    await _open(tester, settings, file.path);
    await tester.tap(find.text('Feedback'));
    await tester.pump();
    expect(find.text('— in zone · 0 chimes · — inhibited'), findsOneWidget);
    expect(find.textContaining('over ceiling'), findsNothing);

    await tester.tap(find.text('Guard'));
    await tester.pump();
    expect(find.text('— warning · 0 chimes'), findsOneWidget);
    expect(find.textContaining('over ceiling'), findsNothing);
    expect(find.byKey(const Key('trust-guard-ceiling-pane')), findsNothing);
    expect(find.byType(FeedbackSessionView), findsNothing);
  });
}

void _deleteLater(File file) {
  addTearDown(() async {
    final parent = file.parent;
    if (await parent.exists()) await parent.delete(recursive: true);
  });
}

Future<File> _write(
  Map<String, Object?> metadata,
  List<ComputedFrame> frames,
) async {
  final dir = await Directory.systemTemp.createTemp('nf_feedback_chip_');
  final bytes = assembleContainer(
    thumbnail: const [],
    metadataJson: metadata,
    computedFrames: frames,
    rawBody: sessionHeaderBytes(),
  );
  final file = File('${dir.path}/session_chip.neurofeed');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<Settings> _settings(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
}) async {
  final loaded = await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues(prefs);
    return Settings.load();
  });
  return loaded!;
}

Future<void> _open(WidgetTester tester, Settings settings, String path) async {
  tester.view.physicalSize = const Size(1200, 2800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        appStateProvider.overrideWith(
          (ref) => AppStateNotifier.forTest(ref.read(settingsProvider)),
        ),
        sessionStorageProvider.overrideWith(
          (ref) async => FileSystemSessionStorage(Directory.systemTemp),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FeedbackDashboardView(
                      sessionPath: path,
                      readOnly: true,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  final ready = find.text('Notes');
  for (var i = 0; i < 40 && ready.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  expect(ready, findsOneWidget);
}
