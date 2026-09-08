import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/monitor/monitor_controller.dart';
import 'package:muse_ml/src/monitor/monitor_providers.dart';
import 'package:muse_ml/src/monitor/monitor_state.dart';
import 'package:muse_ml/src/monitor/recording/capture_lease.dart';
import 'package:muse_ml/src/monitor/recording/crash_recovery.dart';
import 'package:muse_ml/src/session_v5/models.dart';
import 'package:muse_ml/src/session_v5/scratch_writer.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CaptureLease', () {
    test('idle → tmp → discard → idle', () {
      final lease = CaptureLease();
      expect(lease.tryBeginTmp(), isTrue);
      expect(lease.kind, CaptureKind.tmp);
      expect(lease.tryBeginTmp(), isFalse);
      expect(lease.tryDiscardTmp(), isTrue);
      expect(lease.kind, CaptureKind.idle);
    });

    test('tmp → feedback discards the tmp slot', () {
      final lease = CaptureLease();
      expect(lease.tryBeginTmp(), isTrue);
      expect(lease.tryAcquireFeedback(), isTrue);
      expect(lease.kind, CaptureKind.feedback);
      expect(lease.tryDiscardTmp(), isFalse);
    });

    test('recording refuses feedback', () {
      final lease = CaptureLease()..kind = CaptureKind.recording;
      expect(lease.tryAcquireFeedback(), isFalse);
      expect(lease.kind, CaptureKind.recording);
    });

    test('release is idempotent and only from feedback', () {
      final lease = CaptureLease();
      expect(lease.tryReleaseFeedback(), isFalse);
      expect(lease.tryAcquireFeedback(), isTrue);
      expect(lease.tryReleaseFeedback(), isTrue);
      expect(lease.kind, CaptureKind.idle);
      expect(lease.tryReleaseFeedback(), isFalse);
    });
  });

  group('deleteLeftoverTmpCaptures', () {
    test('deletes tmp_ only', () async {
      final dir = await Directory.systemTemp.createTemp('muse_tmp_glob_');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/tmp_1.raw').writeAsString('x');
      await File('${dir.path}/tmp_1.computed').writeAsString('x');
      await File('${dir.path}/tmp_1.json').writeAsString('{}');
      await File('${dir.path}/tmp_1.json.tmp').writeAsString('{}');
      await File('${dir.path}/session_1.raw').writeAsString('x');
      await File('${dir.path}/recording_1.raw').writeAsString('x');

      final n = await deleteLeftoverTmpCaptures(dir);
      expect(n, 4);
      expect(File('${dir.path}/tmp_1.raw').existsSync(), isFalse);
      expect(File('${dir.path}/session_1.raw').existsSync(), isTrue);
      expect(File('${dir.path}/recording_1.raw').existsSync(), isTrue);
    });
  });

  group('MonitorController tmp lease', () {
    late Directory history;
    late Directory scratch;
    late Settings settings;
    late AppStateNotifier app;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = await Settings.load();
      history = await Directory.systemTemp.createTemp('muse_hist_');
      final storage = FileSystemSessionStorage(history);
      scratch = scratchDirectory(storage);
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
    });

    tearDown(() async {
      container.dispose();
      if (await history.exists()) {
        await history.delete(recursive: true);
      }
    });

    Future<void> settle() =>
        container.read(monitorControllerProvider.notifier).pendingOps;

    List<File> tmpFiles() {
      if (!scratch.existsSync()) return const [];
      return scratch
          .listSync()
          .whereType<File>()
          .where((f) => f.uri.pathSegments.last.startsWith('tmp_'))
          .toList();
    }

    List<File> sessionFiles() {
      if (!scratch.existsSync()) return const [];
      return scratch
          .listSync()
          .whereType<File>()
          .where((f) => f.uri.pathSegments.last.startsWith('session_'))
          .toList();
    }

    test(
      'connect while idle → tmp_\$ts.{raw,computed,json} (not session_)',
      () async {
        container.read(monitorControllerProvider);
        expect(
          container.read(monitorControllerProvider).kind,
          CaptureKind.idle,
        );

        app.debugSetConnected();
        await settle();

        final mon = container.read(monitorControllerProvider);
        expect(mon.kind, CaptureKind.tmp);
        expect(mon.captureId, isNotNull);
        expect(mon.captureStartedAtMs, isNotNull);

        final names = tmpFiles().map((f) => f.uri.pathSegments.last).toList();
        expect(names.any((n) => n.endsWith('.raw')), isTrue);
        expect(names.any((n) => n.endsWith('.computed')), isTrue);
        expect(names.any((n) => n.endsWith('.json')), isTrue);
        expect(names.every((n) => n.startsWith('tmp_')), isTrue);
        expect(sessionFiles(), isEmpty);
      },
    );

    test('disconnect while tmp → files gone', () async {
      container.read(monitorControllerProvider);
      app.debugSetConnected();
      await settle();
      expect(tmpFiles(), isNotEmpty);

      app.debugSetConnected(connected: false);
      await settle();

      expect(container.read(monitorControllerProvider).kind, CaptureKind.idle);
      expect(tmpFiles(), isEmpty);
    });

    test(
      'successful end() while still connected → captureKind == tmp',
      () async {
        container.read(monitorControllerProvider);
        app.debugSetConnected();
        await settle();

        final notifier = container.read(monitorControllerProvider.notifier);
        expect(await notifier.acquireFeedbackLease(), isTrue);
        await settle();
        expect(
          container.read(monitorControllerProvider).kind,
          CaptureKind.feedback,
        );
        expect(tmpFiles(), isEmpty);

        await notifier.releaseFeedbackLease();
        await settle();
        expect(container.read(monitorControllerProvider).kind, CaptureKind.tmp);
        expect(tmpFiles(), isNotEmpty);
      },
    );

    test('assembleScratchV5 returns null → stays feedback, no tmp_*', () async {
      container.read(monitorControllerProvider);
      app.debugSetConnected();
      await settle();

      final notifier = container.read(monitorControllerProvider.notifier);
      expect(await notifier.acquireFeedbackLease(), isTrue);
      await settle();
      expect(
        container.read(monitorControllerProvider).kind,
        CaptureKind.feedback,
      );
      expect(tmpFiles(), isEmpty);
    });

    test(
      'reset / discardSession after stop → lease released; tmp restarts',
      () async {
        container.read(monitorControllerProvider);
        app.debugSetConnected();
        await settle();

        final notifier = container.read(monitorControllerProvider.notifier);
        expect(await notifier.acquireFeedbackLease(), isTrue);
        await settle();
        await notifier.releaseFeedbackLease();
        await settle();

        expect(container.read(monitorControllerProvider).kind, CaptureKind.tmp);
        expect(tmpFiles(), isNotEmpty);
      },
    );

    test('StreamsConfig.fromJson ten keys on the tmp sidecar', () async {
      container.read(monitorControllerProvider);
      app.debugSetConnected();
      await settle();

      final jsonFile = tmpFiles().firstWhere((f) => f.path.endsWith('.json'));
      final map =
          jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
      expect(map['kind'], 'tmp');
      final streamsJson = map['streams'] as Map<String, dynamic>;
      expect(
        streamsJson.keys,
        containsAll([
          'eeg',
          'bands',
          'pulse',
          'spo2',
          'movement',
          'peakAlpha',
          'imu',
          'ppg',
          'telemetry',
          'gestures',
        ]),
      );
      final streams = StreamsConfig.fromJson(streamsJson);
      expect(streams, isNotNull);
      expect(streams!.eeg.enabled, isTrue);
      expect(streams.eeg.rateHz, 256);
      expect(streams.gestures.enabled, isFalse);
      expect(streams.gestures.rateHz, 0);
    });

    test('Settings.recordStreams applies to tmp sidecar', () async {
      await settings.setRecordStreams({RecordingStream.bands});
      container.read(monitorControllerProvider);
      app.debugSetConnected();
      await settle();

      final jsonFile = tmpFiles().firstWhere((f) => f.path.endsWith('.json'));
      final map =
          jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
      final streams = StreamsConfig.fromJson(
        map['streams'] as Map<String, dynamic>,
      )!;
      expect(streams.bands.enabled, isTrue);
      expect(streams.eeg.enabled, isFalse);
      expect(streams.eeg.rateHz, 0);
    });

    test('hydrate if already connected starts tmp', () async {
      app.debugSetConnected();
      container.read(monitorControllerProvider);
      await settle();
      expect(container.read(monitorControllerProvider).kind, CaptureKind.tmp);
      expect(tmpFiles(), isNotEmpty);
    });

    test('rotate tmp clears the recording index', () async {
      container.read(monitorControllerProvider);
      app.debugSetConnected();
      await settle();

      final notifier = container.read(monitorControllerProvider.notifier);
      notifier.recordingIndex.add(elapsedT: 1, fileLength: 100);
      expect(notifier.recordingIndex.entries, isNotEmpty);

      await notifier.rotateTmp();
      await settle();

      expect(notifier.recordingIndex.entries, isEmpty);
      expect(container.read(monitorControllerProvider).kind, CaptureKind.tmp);
      expect(tmpFiles(), isNotEmpty);
    });
  });
}
