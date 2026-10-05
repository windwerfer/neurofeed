import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/connection_provider.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';
import 'package:neurofeed/src/history/history_dashboard_summary.dart';
import 'package:neurofeed/src/rust/api/session_format.dart';
import 'package:neurofeed/src/rust/frb_generated.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/spine/assemble.dart';
import 'package:neurofeed/src/views/feedback_dashboard.dart';
import 'package:shared_preferences/shared_preferences.dart';

final String _rustLibPath =
    '${Directory.current.path}/rust/target/debug/librust_lib_neurofeed.so';

ComputedFrame _frame(double t) {
  Float32List band() =>
      Float32List.fromList(const [10.0, 20.0, 40.0, 15.0, 5.0]);
  return ComputedFrame(
    t: t,
    bands: [band(), band(), band(), band()],
    pulse: 64,
    movement: 0.05,
    spo2: 97,
    lineNoise: Float32List.fromList(const [0.01, 0.01, 0.01, 0.01]),
    signalQuality: Uint8List.fromList(const [90, 90, 90, 90]),
    guardrail: const GuardrailInfo(
      sleepDir: 0.2,
      clarity: 0.8,
      warning: false,
      delta: 0.1,
      featurePercentile: 40,
      warnOver: false,
      ceilingOver: false,
      clean: true,
    ),
    feedback: const FeedbackInfo(
      ratio: 1.2,
      threshold: 1,
      inTarget: true,
      pct: 0.5,
      percentile: 70,
      thresholdPercentile: 40,
      heldBack: false,
      inhibitTags: const [],
      clean: true,
      betaRel: 0.2,
      deltaRel: 0.1,
    ),
    gestures: const [],
  );
}

Future<File> _fixture() async {
  final dir = await Directory.systemTemp.createTemp('nf_session_summary_');
  final bytes = assembleContainer(
    thumbnail: const [],
    metadataJson: {
      'formatVersion': 6,
      'kind': 'feedback',
      'savedAt': '2026-10-02T00:00:00Z',
      'startedAt': '2026-10-02T00:00:00Z',
      'elapsedSeconds': 5,
      'durationS': 90,
      'notes': 'kept',
      'stats': {
        'quality': {'pctGood': 86.4},
        'movement': {'stillnessPct': 71.2},
        'hr': {'mean': 64.2, 'min': 54, 'max': 91},
        'peakAlpha': {'maxPowerHz': 10.2},
        'annotationSeconds': {'pause': 10},
      },
      'feedback': {
        'protocol': 'recordOnly',
        'durationMinutes': 15,
        'sound': 'Ambient Drone',
        'audioEvents': [
          {'type': 'reward_chime', 't': 1},
          {'type': 'guard_chime', 't': 2},
          {'type': 'not_a_chime', 't': 3},
        ],
      },
    },
    computedFrames: [_frame(0), _frame(1)],
    rawBody: sessionHeaderBytes(),
  );
  final file = File('${dir.path}/session_summary.neurofeed');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init(externalLibrary: ExternalLibrary.open(_rustLibPath));
  });

  testWidgets('history summary is Dashboard, with stats and graph chips', (
    tester,
  ) async {
    final settings = await _settings(tester);
    final file = await tester.runAsync(_fixture);
    addTearDown(() async {
      final parent = file!.parent;
      if (await parent.exists()) await parent.delete(recursive: true);
    });
    await _open(tester, settings, file!.path, readOnly: true);

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Feedback'), findsNothing);
    expect(find.text('Bands'), findsOneWidget);
    expect(find.text('Raw EEG'), findsOneWidget);
    expect(find.text('Histogram'), findsOneWidget);
    expect(find.text('PSD'), findsOneWidget);
    expect(find.text('Spectrogram'), findsOneWidget);
    expect(find.text('HR+SpO2'), findsOneWidget);
    expect(find.text('Movement'), findsOneWidget);
    expect(find.text('Session summary'), findsNothing);
    expect(find.text('Target time'), findsNothing);
    expect(find.text('1:30'), findsOneWidget);
    expect(find.text('100% in zone'), findsOneWidget);
    expect(find.text('86% good'), findsOneWidget);
    expect(find.text('71% still'), findsOneWidget);
    expect(find.text('Peak α 10.2 Hz'), findsOneWidget);
    expect(find.text('64 bpm'), findsOneWidget);
    expect(find.text('1 chimes'), findsOneWidget);
    expect(find.text('Pause 0:10'), findsNothing);
    expect(find.text('1 guard chimes'), findsNothing);
    expect(find.text('kept'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Discard'), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    expect(_canPop(tester), isTrue);
    _expectSummaryThumbnail(tester);

    expect(find.textContaining('Alpha vs Theta'), findsNothing);
    expect(find.textContaining('Bands (relative power'), findsNothing);
    expect(find.text('Movement score'), findsNothing);
    expect(find.text('Heart rate / SpO₂'), findsNothing);
    expect(find.text('Sleep guardrail (AI model)'), findsNothing);
    expect(find.text('Low-pass cutoff'), findsNothing);

    await tester.tap(find.text('Bands'));
    await tester.pump();
    expect(find.text('Notes'), findsNothing);
    expect(find.text('Follow'), findsNothing);
    expect(find.text('Inspect'), findsNothing);
    final window = find.text('30s');
    for (var i = 0; i < 40 && window.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(window, findsOneWidget);
    expect(find.text('TP9'), findsOneWidget);

    await tester.ensureVisible(find.text('HR+SpO2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HR+SpO2'));
    await tester.pump();
    expect(find.text('Notes'), findsNothing);
    expect(find.text('Follow'), findsNothing);
    expect(find.text('Inspect'), findsNothing);
    expect(find.text('TP9'), findsNothing);
    expect(find.text('30s'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('history-hr-spo2-detail-window')),
      findsNothing,
    );

    await tester.ensureVisible(find.text('Movement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Movement'));
    await tester.pump();
    expect(find.text('TP9'), findsNothing);
    expect(find.text('30s'), findsOneWidget);

    await tester.ensureVisible(find.text('Dashboard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dashboard'));
    await tester.pump();
    expect(find.text('Notes'), findsOneWidget);
    expect(find.textContaining('Bands (relative power'), findsNothing);
    expect(find.text('Sleep guardrail (AI model)'), findsNothing);

    await tester.tap(find.text('More'));
    await tester.pump();
    expect(find.text('Pause 0:10'), findsOneWidget);
    expect(find.text('0% inhibited'), findsOneWidget);
    expect(find.text('0% guard warning'), findsOneWidget);
    expect(find.text('1 guard chimes'), findsOneWidget);
    expect(settings.historyDashboardMoreExpanded, isTrue);
  });

  testWidgets('live summary keeps Save and Discard in the app bar', (
    tester,
  ) async {
    final settings = await _settings(tester);
    final file = await tester.runAsync(_fixture);
    addTearDown(() async {
      final parent = file!.parent;
      if (await parent.exists()) await parent.delete(recursive: true);
    });
    await _open(tester, settings, file!.path, readOnly: false);

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('100% in zone'), findsOneWidget);
    expect(find.text('86% good'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(_canPop(tester), isFalse);
    expect(find.text('Notes'), findsOneWidget);
    _expectSummaryThumbnail(tester);

    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(bar.automaticallyImplyLeading, isFalse);
    expect(bar.actions, isNotNull);
    expect(bar.actions, hasLength(2));
  });
}

void _expectSummaryThumbnail(WidgetTester tester) {
  final summary = find.byType(HistoryDashboardSummary);
  expect(summary, findsOneWidget);
  final boundaries = find.ancestor(
    of: summary,
    matching: find.byType(RepaintBoundary),
  );
  expect(boundaries, findsWidgets);
  expect(tester.widget<RepaintBoundary>(boundaries.first).key, isNotNull);
  expect(
    find.descendant(of: boundaries.first, matching: find.text('Notes')),
    findsNothing,
  );
}

bool _canPop(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byType(FeedbackDashboardView),
    matching: find.byWidgetPredicate((widget) => widget is PopScope),
  );
  final widget = tester.widget<PopScope<dynamic>>(finder);
  return widget.canPop;
}

Future<Settings> _settings(WidgetTester tester) async {
  final loaded = await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    return Settings.load();
  });
  return loaded!;
}

Future<void> _open(
  WidgetTester tester,
  Settings settings,
  String path, {
  required bool readOnly,
}) async {
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
                      readOnly: readOnly,
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
  final dashboard = find.text('100% in zone');
  for (var i = 0; i < 40 && dashboard.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}
