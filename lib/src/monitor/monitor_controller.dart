import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/monitor/cache/band_cache.dart';
import 'package:muse_ml/src/monitor/cache/file_backed_source.dart';
import 'package:muse_ml/src/monitor/cache/recording_index.dart';
import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';
import 'package:muse_ml/src/monitor/monitor_state.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';
import 'package:muse_ml/src/monitor/recording/capture_lease.dart';
import 'package:muse_ml/src/monitor/recording/monitor_recorder.dart';
import 'package:muse_ml/src/monitor/recording/monitor_sampler.dart';
import 'package:muse_ml/src/monitor/recording/recording_metadata.dart';
import 'package:muse_ml/src/rust/api/device_config.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/session_v5/models.dart';
import 'package:muse_ml/src/session_v5/scratch_writer.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:muse_ml/src/version.dart';

class MonitorController extends Notifier<MonitorState> {
  MonitorController({
    this.tmpCap = MonitorRecorder.kTmpCap,
    this.sidecarInterval = MonitorRecorder.kSidecarInterval,
    SessionRecorder Function()? createRecorder,
  }) : _createRecorder = createRecorder ?? (() => SessionRecorder());

  final Duration tmpCap;
  final Duration sidecarInterval;
  final SessionRecorder Function() _createRecorder;

  final BandCache bandCache = BandCache();
  final SweepBuffer sweepBuffer = SweepBuffer()
    ..setDisplayWindow(ViewportController.defaultWindowSamples);
  final CaptureLease _lease = CaptureLease();

  StreamSubscription<MuseEventDto>? _eventSub;
  MonitorRecorder? _capture;
  MonitorSampler? _sampler;
  Future<void> _op = Future.value();
  int? _latestEegTsMs;

  @visibleForTesting
  Future<void> get pendingOps => _op;

  RecordingIndex get recordingIndex => _capture!.index;

  FileBackedSource? get fileBackedSource => _capture?.source;

  /// Elapsed seconds of the newest EEG sample, or null if the capture
  /// clock is unknown. Never treats a null start as unix epoch.
  double? get ramNewestElapsed {
    final start = state.captureStartedAtMs;
    final ts = _latestEegTsMs;
    if (start == null || ts == null) return null;
    return (ts - start) / 1000.0;
  }

  @override
  MonitorState build() {
    _capture ??=
        MonitorRecorder(
            writer: _createRecorder(),
            tmpCap: tmpCap,
            sidecarInterval: sidecarInterval,
          )
          ..onRotate = () {
            unawaited(_serialized(_rotateTmpUnlocked));
          };

    final app = ref.read(appStateProvider.notifier);
    _eventSub ??= app.eventStream.listen(_onEvent);
    ref.listen(appStateProvider.select((s) => s.status.connected), (
      prev,
      next,
    ) {
      if (next) {
        unawaited(_serialized(_startTmpUnlocked));
      } else {
        unawaited(_serialized(_onDisconnectedUnlocked));
      }
    });
    ref.listen(appStateProvider.select((s) => s.lastConnectedKind), (
      prev,
      next,
    ) {
      if (_lease.kind == CaptureKind.idle) {
        state = MonitorState.idle(deviceKind: next);
      }
    });
    ref.onDispose(() {
      _eventSub?.cancel();
      _eventSub = null;
      _stopSampler();
      unawaited(_capture?.discard() ?? Future<void>.value());
    });
    final current = ref.read(appStateProvider);
    if (current.status.connected) {
      debugPrint(
        '[monitor] hydrate connected kind=${current.lastConnectedKind}',
      );
      unawaited(_serialized(_startTmpUnlocked));
    }
    return MonitorState.idle(deviceKind: current.lastConnectedKind);
  }

  Future<T> _serialized<T>(Future<T> Function() fn) {
    final done = Completer<T>();
    _op = _op.then((_) async {
      try {
        done.complete(await fn());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  Future<bool> acquireFeedbackLease() {
    return _serialized(() async {
      final wasTmp = _lease.kind == CaptureKind.tmp;
      if (!_lease.tryAcquireFeedback()) {
        debugPrint('[monitor] lease refuse recording_active');
        return false;
      }
      if (wasTmp) {
        await _stopTmpWriter();
      }
      final app = ref.read(appStateProvider);
      state = MonitorState.idle(
        deviceKind: app.lastConnectedKind,
      ).copyWith(kind: CaptureKind.feedback);
      debugPrint('[monitor] lease feedback');
      return true;
    });
  }

  Future<void> releaseFeedbackLease() {
    return _serialized(() async {
      if (!_lease.tryReleaseFeedback()) return;
      debugPrint('[monitor] lease release');
      final app = ref.read(appStateProvider);
      state = MonitorState.idle(deviceKind: app.lastConnectedKind);
      if (app.status.connected) {
        await _startTmpUnlocked();
      }
    });
  }

  @visibleForTesting
  Future<void> rotateTmp() => _serialized(_rotateTmpUnlocked);

  Future<void> _startTmpUnlocked() async {
    if (!ref.read(appStateProvider).status.connected) return;
    if (!_lease.tryBeginTmp()) return;
    try {
      final storage = await ref.read(sessionStorageProvider.future);
      await storage.ensureDir();
      final dir = scratchDirectory(storage);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final app = ref.read(appStateProvider);
      final settings = ref.read(settingsProvider);
      final names = electrodeNamesForKind(app.lastConnectedKind);
      final startedAt = _latestEegTsMs ?? DateTime.now().millisecondsSinceEpoch;
      state = MonitorState(
        kind: CaptureKind.tmp,
        electrodeNames: names,
        channelCount: names.length,
        captureStartedAtMs: startedAt,
      );
      await _capture!.startTmp(
        dir: dir,
        recordStreams: settings.recordStreams,
        metadata: _currentMetadata,
        captureStartedAtMs: startedAt,
      );
      state = state.copyWith(captureId: _capture!.captureId);
      _startSampler(names.length, startedAt);
    } catch (e, st) {
      debugPrint('[monitor] tmp start failed: $e\n$st');
      _lease.tryDiscardTmp();
      _stopSampler();
      final app = ref.read(appStateProvider);
      state = MonitorState.idle(deviceKind: app.lastConnectedKind);
    }
  }

  Future<void> _rotateTmpUnlocked() async {
    if (_lease.kind != CaptureKind.tmp) return;
    _latestEegTsMs = null;
    await _stopTmpWriter();
    _lease.tryDiscardTmp();
    final app = ref.read(appStateProvider);
    state = MonitorState.idle(deviceKind: app.lastConnectedKind);
    await _startTmpUnlocked();
  }

  Future<void> _onDisconnectedUnlocked() async {
    if (_lease.kind != CaptureKind.tmp) return;
    await _stopTmpWriter();
    _lease.tryDiscardTmp();
    _latestEegTsMs = null;
    sweepBuffer.clear();
    state = MonitorState(
      kind: CaptureKind.idle,
      electrodeNames: state.electrodeNames,
      channelCount: state.channelCount,
    );
  }

  Future<void> _stopTmpWriter() async {
    _stopSampler();
    await _capture?.discard();
  }

  void _startSampler(int channelCount, int startedAtMs) {
    _stopSampler();
    _sampler = MonitorSampler(
      channelCount: channelCount,
      captureStartedAtMs: startedAtMs,
      onFrame: (frame) => _capture?.appendComputed(frame),
    )..start();
  }

  void _stopSampler() {
    _sampler?.stop();
    _sampler = null;
  }

  RecordingMetadata _currentMetadata() {
    final app = ref.read(appStateProvider);
    final settings = ref.read(settingsProvider);
    final started =
        state.captureStartedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    final elapsed = ((DateTime.now().millisecondsSinceEpoch - started) / 1000)
        .round();
    final kind = app.lastConnectedKind;
    return RecordingMetadata(
      formatVersion: 5,
      appVersion: appVersion,
      kind: 'tmp',
      savedAt: DateTime.now().toUtc(),
      startedAt: DateTime.fromMillisecondsSinceEpoch(started, isUtc: true),
      elapsedSeconds: elapsed,
      durationS: elapsed,
      device: DeviceInfoV5(
        name: app.status.name,
        id: app.status.id,
        firmware: app.status.firmware,
        model: app.status.firmware,
        sensors: kind == DeviceKind.neurosity
            ? const ['EEG', 'IMU']
            : const ['EEG', 'PPG', 'IMU'],
        channelCount: state.channelCount,
        channelLabels: state.electrodeNames,
      ),
      streams: RecordingMetadata.streamsConfig(settings.recordStreams),
    );
  }

  void _onEvent(MuseEventDto event) {
    switch (event) {
      case MuseEventDto_Eeg():
        _latestEegTsMs = event.field0.timestamp.round();
        sweepBuffer.append(event.field0);
      case MuseEventDto_Bands():
        bandCache.appendBands(event.field0);
        _sampler?.updateBands(event.field0.electrode, event.field0);
      case MuseEventDto_Pulse():
        _sampler?.updatePulse(event.field0);
      case MuseEventDto_Movement():
        _sampler?.updateMovement(event.field0);
      case MuseEventDto_PeakAlpha():
        _sampler?.updatePeakAlpha(event.field0);
      case MuseEventDto_SpO2():
        _sampler?.updateSpO2(event.field0);
      case MuseEventDto_Gestures():
        _sampler?.updateGestures(event.field0);
      default:
        break;
    }
    if (_lease.kind == CaptureKind.tmp ||
        _lease.kind == CaptureKind.recording) {
      _capture?.writeEvent(event);
    }
  }
}
