import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/connect_source.dart';
import 'package:neurofeed/src/connect_window.dart';
import 'package:neurofeed/src/connection_provider.dart';
import 'package:neurofeed/src/device_type_switch.dart';
import 'package:neurofeed/src/feedback/feedback_phase.dart';
import 'package:neurofeed/src/monitor/monitor_state.dart';
import 'package:neurofeed/src/rust/api/muse.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('deviceTypeSwitchBlock', () {
    test('idle link never asks', () {
      expect(
        deviceTypeSwitchBlock(
          linked: false,
          kind: CaptureKind.recording,
          phase: FeedbackPhase.playing,
        ),
        DeviceTypeSwitchBlock.none,
      );
    });

    test('tmp capture does not ask', () {
      expect(
        deviceTypeSwitchBlock(
          linked: true,
          kind: CaptureKind.tmp,
          phase: FeedbackPhase.idle,
        ),
        DeviceTypeSwitchBlock.none,
      );
    });

    test('explicit recording asks and stays a recording', () {
      expect(
        deviceTypeSwitchBlock(
          linked: true,
          kind: CaptureKind.recording,
          phase: FeedbackPhase.idle,
        ),
        DeviceTypeSwitchBlock.recording,
      );
      expect(
        deviceTypeSwitchMessage(
          block: DeviceTypeSwitchBlock.recording,
          deviceName: 'Muse 2 (Simulated)',
          nextTypeLabel: 'Neurosity',
        ),
        'Disconnect Muse 2 (Simulated)? This recording stays open until you '
        'stop it. NeuroFeed will then look for a Neurosity device.',
      );
    });

    test('playing session asks and ends on disconnect', () {
      expect(
        deviceTypeSwitchBlock(
          linked: true,
          kind: CaptureKind.feedback,
          phase: FeedbackPhase.playing,
        ),
        DeviceTypeSwitchBlock.session,
      );
      expect(
        deviceTypeSwitchBlock(
          linked: true,
          kind: CaptureKind.tmp,
          phase: FeedbackPhase.paused,
        ),
        DeviceTypeSwitchBlock.session,
      );
      expect(
        deviceTypeSwitchBlock(
          linked: true,
          kind: CaptureKind.feedback,
          phase: FeedbackPhase.interrupted,
        ),
        DeviceTypeSwitchBlock.session,
      );
      expect(
        deviceTypeSwitchMessage(
          block: DeviceTypeSwitchBlock.session,
          deviceName: '',
          nextTypeLabel: 'Simulator',
        ),
        'Disconnect this device? This ends the feedback session. '
        'NeuroFeed will then look for a Simulator device.',
      );
    });

    test('calibration asks without claiming the session ends', () {
      expect(
        deviceTypeSwitchBlock(
          linked: true,
          kind: CaptureKind.feedback,
          phase: FeedbackPhase.calibrating,
        ),
        DeviceTypeSwitchBlock.calibration,
      );
      expect(
        deviceTypeSwitchMessage(
          block: DeviceTypeSwitchBlock.calibration,
          deviceName: 'Muse S',
          nextTypeLabel: 'Muse',
        ),
        contains('Calibration is still running'),
      );
    });

    test('ended session does not ask', () {
      expect(
        deviceTypeSwitchBlock(
          linked: true,
          kind: CaptureKind.feedback,
          phase: FeedbackPhase.ended,
        ),
        DeviceTypeSwitchBlock.none,
      );
    });
  });

  group('switchConnectSource', () {
    late Settings settings;
    late AppStateNotifier app;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = await Settings.load();
      app = AppStateNotifier.forTest(settings);
    });

    tearDown(() {
      app.dispose();
    });

    test('same type while connected does not drop the link', () async {
      app.debugSetConnected();
      final ok = await app.switchConnectSource(ConnectSource.muse);
      expect(ok, isTrue);
      expect(app.state.status.connected, isTrue);
      expect(app.state.connectSource, ConnectSource.muse);
      expect(app.allowAutoReconnect, isTrue);
      expect(app.state.scanning, isFalse);
    });

    test('opening the window while connected does not scan', () {
      app.debugSetConnected();
      app.toggleConnectWindow();
      expect(app.state.connectWindowOpen, isTrue);
      expect(app.state.status.connected, isTrue);
      expect(app.state.scanning, isFalse);
      expect(app.allowAutoReconnect, isTrue);
    });

    test(
      'connected muse switches to neurosity only after disconnect',
      () async {
        app.debugSetConnected(name: 'Muse 2 (Simulated)', id: 'sim:muse-2');
        final ok = await app.switchConnectSource(ConnectSource.neurosity);
        expect(ok, isTrue);
        expect(app.state.status.connected, isFalse);
        expect(app.state.disconnecting, isFalse);
        expect(app.state.connectSource, ConnectSource.neurosity);
        expect(app.state.connectWindowOpen, isTrue);
        expect(app.state.scanning, isTrue);
        expect(app.state.devices, isEmpty);
        expect(app.allowAutoReconnect, isFalse);
      },
    );

    test('failed disconnect keeps the headset and the old type', () async {
      app.debugSetConnected();
      app.debugFailNextDisconnect();
      final ok = await app.switchConnectSource(ConnectSource.neurosity);
      expect(ok, isFalse);
      expect(app.state.status.connected, isTrue);
      expect(app.state.connectSource, ConnectSource.muse);
      expect(app.state.disconnecting, isFalse);
      expect(app.state.scanning, isFalse);
      expect(app.allowAutoReconnect, isTrue);
      expect(app.state.scanMessage, contains('Could not disconnect'));
    });

    test('connecting attempt is dropped before the new scan', () async {
      app.debugSetConnecting('Crown');
      final ok = await app.switchConnectSource(ConnectSource.neurosity);
      expect(ok, isTrue);
      expect(app.state.connectingTo, isNull);
      expect(app.state.status.connected, isFalse);
      expect(app.state.connectSource, ConnectSource.neurosity);
      expect(app.state.scanning, isTrue);
      expect(app.state.connectWindowOpen, isTrue);
    });

    test('debug on shows the simulator catalog after disconnect', () async {
      await settings.setEnableSimulatedDevices(true);
      app.debugSetConnected();
      final ok = await app.switchConnectSource(ConnectSource.simulator);
      expect(ok, isTrue);
      expect(app.state.status.connected, isFalse);
      expect(app.state.connectSource, ConnectSource.simulator);
      expect(app.state.scanning, isFalse);
      expect(app.state.connectWindowOpen, isTrue);
      expect(
        app.state.devices.map((d) => d.id),
        simulatorCatalog.map((d) => d.id),
      );
    });

    test(
      'debug off treats Simulator as Muse and does not disconnect',
      () async {
        app.debugSetConnected();
        final ok = await app.switchConnectSource(ConnectSource.simulator);
        expect(ok, isTrue);
        expect(app.state.status.connected, isTrue);
        expect(app.state.connectSource, ConnectSource.muse);
      },
    );

    test('user disconnect closes the window and does not scan', () async {
      app.debugSetConnected();
      app.toggleConnectWindow();
      expect(app.state.connectWindowOpen, isTrue);

      await app.disconnectDevice();

      expect(app.state.status.connected, isFalse);
      expect(app.state.connectWindowOpen, isFalse);
      expect(app.state.scanning, isFalse);
      expect(app.state.connectSource, ConnectSource.muse);
      expect(app.allowAutoReconnect, isFalse);
    });

    test('stale connected event after a type change is ignored', () async {
      app.debugSetConnected(name: 'Muse 2 (Simulated)', id: 'sim:muse-2');
      final ok = await app.switchConnectSource(ConnectSource.neurosity);
      expect(ok, isTrue);

      app.debugAddEvent(const MuseEventDto.connected('Muse 2 (Simulated)'));

      expect(app.state.status.connected, isFalse);
      expect(app.state.connectSource, ConnectSource.neurosity);
      expect(app.state.scanning, isTrue);
      expect(app.state.connectWindowOpen, isTrue);
    });

    test('idle change to simulator does not arm a reconnect', () async {
      await settings.setEnableSimulatedDevices(true);
      final ok = await app.switchConnectSource(ConnectSource.simulator);
      expect(ok, isTrue);
      expect(app.state.connectSource, ConnectSource.simulator);
      expect(app.allowAutoReconnect, isTrue);
      expect(app.state.scanning, isFalse);
      expect(app.state.devices, isNotEmpty);
    });
  });

  group('device type dropdown', () {
    late Settings settings;
    late AppStateNotifier app;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = await Settings.load();
      app = AppStateNotifier.forTest(settings);
    });

    tearDown(() {
      if (app.mounted) app.dispose();
    });

    Future<void> pumpWindow(
      WidgetTester tester, {
      required DeviceTypeSwitchBlock block,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => settings),
            appStateProvider.overrideWith((ref) => app),
            deviceTypeSwitchBlockProvider.overrideWith((ref) => block),
          ],
          child: const MaterialApp(home: Scaffold(body: ConnectWindow())),
        ),
      );
    }

    Future<void> pick(WidgetTester tester, String label) async {
      await tester.tap(find.byType(DropdownButtonFormField<ConnectSource>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('Cancel stays connected and resets the dropdown', (
      tester,
    ) async {
      app.debugSetConnected(name: 'Muse 2 (Simulated)');
      await pumpWindow(tester, block: DeviceTypeSwitchBlock.recording);
      await pick(tester, 'Neurosity');

      expect(find.text('Recording in progress'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(
        find.textContaining('This recording stays open until you stop it'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(app.state.status.connected, isTrue);
      expect(app.state.connectSource, ConnectSource.muse);
      expect(find.text('Recording in progress'), findsNothing);
      expect(find.text('Muse'), findsWidgets);
    });

    testWidgets('Disconnect then scans the new type', (tester) async {
      app.debugSetConnected(name: 'Muse 2 (Simulated)');
      await pumpWindow(tester, block: DeviceTypeSwitchBlock.recording);
      await pick(tester, 'Neurosity');
      await tester.tap(find.text('Disconnect'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(app.state.status.connected, isFalse);
      expect(app.state.connectSource, ConnectSource.neurosity);
      expect(app.state.scanning, isTrue);
      expect(app.state.connectWindowOpen, isTrue);
      expect(find.text('Scanning…'), findsOneWidget);
      expect(find.text('Recording in progress'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('device list follows the light theme', (tester) async {
      await settings.setEnableSimulatedDevices(true);
      final switched = await app.switchConnectSource(ConnectSource.simulator);
      expect(switched, isTrue);
      expect(app.state.devices, isNotEmpty);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => settings),
            appStateProvider.overrideWith((ref) => app),
            deviceTypeSwitchBlockProvider.overrideWith(
              (ref) => DeviceTypeSwitchBlock.none,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.deepPurple,
                brightness: Brightness.light,
              ),
            ),
            home: const Scaffold(body: ConnectWindow()),
          ),
        ),
      );
      await tester.pump();

      final title = tester.element(find.text('Muse 2'));
      final scheme = Theme.of(title).colorScheme;
      expect(DefaultTextStyle.of(title).style.color, scheme.onSurface);
      final row = tester.widget<Material>(
        find
            .ancestor(of: find.text('Muse 2'), matching: find.byType(Material))
            .first,
      );
      expect(
        ThemeData.estimateBrightnessForColor(row.color!),
        Brightness.light,
      );
      expect(
        tester
            .widgetList<Material>(find.byType(Material))
            .any((material) => material.color == const Color(0xFF1E212A)),
        isFalse,
      );
    });

    testWidgets('no recording disconnects without a dialog', (tester) async {
      app.debugSetConnected(name: 'Muse 2 (Simulated)');
      await pumpWindow(tester, block: DeviceTypeSwitchBlock.none);
      await pick(tester, 'Neurosity');
      await tester.pump();

      expect(find.text('Recording in progress'), findsNothing);
      expect(find.text('Session in progress'), findsNothing);
      expect(app.state.status.connected, isFalse);
      expect(app.state.connectSource, ConnectSource.neurosity);
      expect(app.state.scanning, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
