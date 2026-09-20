import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/agent/agent_commands.dart';
import 'package:neurofeed/src/connection_provider.dart';
import 'package:neurofeed/src/feedback/feedback_state.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';
import 'package:neurofeed/src/monitor/monitor_controller.dart';
import 'package:neurofeed/src/monitor/monitor_providers.dart';
import 'package:neurofeed/src/monitor/monitor_state.dart';
import 'package:neurofeed/src/rust/api/device_config.dart';
import 'package:neurofeed/src/spine/scratch_writer.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory history;
  late Settings settings;
  late AppStateNotifier app;
  late ProviderContainer container;
  late AgentCommands agent;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await Settings.load();
    history = await Directory.systemTemp.createTemp('neurofeed_agent_rec_');
    final storage = FileSystemSessionStorage(history);
    app = AppStateNotifier.forTest(settings);
    container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        appStateProvider.overrideWith((ref) => app),
        sessionStorageProvider.overrideWith((ref) => storage),
        monitorControllerProvider.overrideWith(
          () => MonitorController(
            createRecorder: () =>
                SessionRecorder(headerBytes: () => Uint8List(12)),
          ),
        ),
      ],
    );
    agent = AgentCommands(container);
  });

  tearDown(() async {
    container.dispose();
    if (await history.exists()) {
      await history.delete(recursive: true);
    }
  });

  Future<void> settle() =>
      container.read(monitorControllerProvider.notifier).pendingOps;

  test('POST /record/start 412 disconnected', () async {
    container.read(monitorControllerProvider);
    final res = await agent.handle(
      method: 'POST',
      path: '/record/start',
      body: const {},
    );
    expect(res.status, 412);
    expect(res.body['error'], 'disconnected');
  });

  test('POST /record/start 409 feedback_active', () async {
    container.read(monitorControllerProvider);
    app.debugSetConnected();
    await settle();
    expect(
      await container
          .read(monitorControllerProvider.notifier)
          .acquireFeedbackLease(),
      isTrue,
    );
    await settle();
    expect(
      container.read(monitorControllerProvider).kind,
      CaptureKind.feedback,
    );

    final res = await agent.handle(
      method: 'POST',
      path: '/record/start',
      body: const {},
    );
    expect(res.status, 409);
    expect(res.body['error'], 'feedback_active');
  });

  test('POST /session/start 409 recording_active', () async {
    container.read(monitorControllerProvider);
    app.debugSetConnected();
    await settle();
    await container.read(monitorControllerProvider.notifier).startRecording();
    await settle();
    expect(
      container.read(monitorControllerProvider).kind,
      CaptureKind.recording,
    );

    final res = await agent.handle(
      method: 'POST',
      path: '/session/start',
      body: const {'skipCalibration': true},
    );
    expect(res.status, 409);
    expect(res.body['error'], 'recording_active');
  });

  test(
    'POST /session/start 409 crown_refused before recording_active',
    () async {
      container.read(monitorControllerProvider);
      app.debugSetConnected(kind: DeviceKind.neurosity, id: 'sim:crown-osc');
      await settle();
      await container.read(monitorControllerProvider.notifier).startRecording();
      await settle();

      final res = await agent.handle(
        method: 'POST',
        path: '/session/start',
        body: const {},
      );
      expect(res.status, 409);
      expect(res.body['error'], 'crown_refused');
    },
  );

  test(
    'POST /session/start 412 not_connected before recording checks',
    () async {
      container.read(monitorControllerProvider);
      final res = await agent.handle(
        method: 'POST',
        path: '/session/start',
        body: const {},
      );
      expect(res.status, 412);
      expect(res.body['error'], 'not_connected');
    },
  );

  test('POST /session/start 409 unsaved_session', () async {
    container.read(monitorControllerProvider);
    app.debugSetConnected();
    await settle();
    container.read(feedbackStateProvider.notifier).restoreEndedSession(
      id: 'unsaved1',
      scratchPath: '${history.path}/session_unsaved1.neurofeed',
      metadata: SessionMetadata(
        protocol: 'drowsiness',
        durationMinutes: 1,
        elapsedSeconds: 10,
        sound: 'Ambient Drone',
        savedAt: DateTime.utc(2026, 9, 14).toIso8601String(),
      ),
    );
    final res = await agent.handle(
      method: 'POST',
      path: '/session/start',
      body: const {'skipCalibration': true},
    );
    expect(res.status, 409);
    expect(res.body['error'], 'unsaved_session');
  });

  test('POST /session/reset 409 unsaved_session', () async {
    container.read(feedbackStateProvider.notifier).restoreEndedSession(
      id: 'unsaved2',
      scratchPath: '${history.path}/session_unsaved2.neurofeed',
      metadata: SessionMetadata(
        protocol: 'drowsiness',
        durationMinutes: 1,
        elapsedSeconds: 10,
        sound: 'Ambient Drone',
        savedAt: DateTime.utc(2026, 9, 14).toIso8601String(),
      ),
    );
    final res = await agent.handle(
      method: 'POST',
      path: '/session/reset',
      body: const {},
    );
    expect(res.status, 409);
    expect(res.body['error'], 'unsaved_session');
    expect(container.read(feedbackStateProvider).phase, FeedbackPhase.ended);
  });

  test('POST /record/start while connected starts recording', () async {
    container.read(monitorControllerProvider);
    app.debugSetConnected();
    await settle();
    final res = await agent.handle(
      method: 'POST',
      path: '/record/start',
      body: const {},
    );
    expect(res.status, 200);
    expect(res.body['ok'], true);
    expect(res.body['captureKind'], 'recording');
  });
}
