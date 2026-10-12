import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/connection_provider.dart';
import 'package:neurofeed/src/feedback/feedback_state.dart';
import 'package:neurofeed/src/feedback/protocol_catalog.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';
import 'package:neurofeed/src/monitor/monitor_controller.dart';
import 'package:neurofeed/src/monitor/monitor_providers.dart';
import 'package:neurofeed/src/reve/model_engine.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/spine/scratch_writer.dart';
import 'package:neurofeed/src/views/feedback_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:io';

/// Target Settings (gear on the Feedback Sound tile): the experimental
/// bandStability section and the Dwell time slider.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Settings settings;
  late ProviderContainer container;
  late Directory history;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await Settings.load();
    history = await Directory.systemTemp.createTemp('neurofeed_tsd_');
    final catalog = await ProtocolCatalog.load();
    container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        appStateProvider.overrideWith(
          (ref) => AppStateNotifier.forTest(settings),
        ),
        sessionStorageProvider.overrideWith(
          (ref) => FileSystemSessionStorage(history),
        ),
        modelEngineNotifierProvider.overrideWith(_MissingModelEngine.new),
        protocolCatalogProvider.overrideWith((ref) async => catalog),
        monitorControllerProvider.overrideWith(
          () => MonitorController(
            createRecorder: () =>
                SessionRecorder(headerBytes: () => Uint8List(12)),
            liveConditioning: () => null,
          ),
        ),
      ],
    );
    await container.read(protocolCatalogProvider.future);
  });

  tearDown(() async {
    container.dispose();
    if (await history.exists()) await history.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester, String protocol) async {
    container.read(feedbackStateProvider.notifier).selectProtocol(protocol);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: TargetSettingsDialog())),
      ),
    );
    await tester.pump();
  }

  testWidgets('bandStability: band / window / difficulty / dwell; no '
      'percentile slider', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, 'bandStability');
    expect(find.text('Steadiness (experimental)'), findsOneWidget);
    expect(find.byKey(const Key('stability-band')), findsOneWidget);
    expect(find.byKey(const Key('stability-window-slider')), findsOneWidget);
    expect(
      find.byKey(const Key('stability-difficulty-slider')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reward-dwell-slider')), findsOneWidget);
    expect(find.text('Reward threshold'), findsNothing);
    expect(find.text('Stability window: 10 s'), findsOneWidget);
    expect(
      find.text('Difficulty: 10 % steadier than baseline'),
      findsOneWidget,
    );
    expect(find.text('Dwell time: 2.5 s'), findsOneWidget);

    await tester.tap(find.text('Theta'));
    await tester.pump();
    expect(settings.stabilityBand, 'band.theta');

    // Drag the sliders to their right ends.
    Future<void> dragRight(Key key) async {
      await tester.drag(find.byKey(key), const Offset(800, 0));
      await tester.pump();
    }

    await dragRight(const Key('stability-window-slider'));
    expect(settings.stabilityWindowSeconds, 30);
    expect(find.text('Stability window: 30 s'), findsOneWidget);
    await dragRight(const Key('stability-difficulty-slider'));
    expect(settings.stabilityDifficulty, closeTo(0.5, 1e-9));
    await dragRight(const Key('reward-dwell-slider'));
    expect(settings.rewardDwellSeconds, 20);
    expect(find.text('Dwell time: 20.0 s'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(settings.stabilityBand, 'band.alpha');
    expect(settings.stabilityWindowSeconds, 10);
    expect(settings.stabilityDifficulty, closeTo(0.1, 1e-9));
    expect(settings.rewardDwellSeconds, 2.5);
  });

  testWidgets('uptrain protocol: percentile slider + dwell, no stability '
      'section', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, 'restAwake');
    expect(find.text('Reward threshold'), findsOneWidget);
    expect(find.byKey(const Key('reward-dwell-slider')), findsOneWidget);
    expect(find.byKey(const Key('stability-band')), findsNothing);
    expect(find.text('Steadiness (experimental)'), findsNothing);
  });
}

class _MissingModelEngine extends ModelEngineNotifier {
  @override
  ModelEngineState build() => const ModelEngineNotInstalled();
}
