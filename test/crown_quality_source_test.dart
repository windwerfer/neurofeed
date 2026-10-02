import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/connection_provider.dart';
import 'package:neurofeed/src/feedback/computed_sampler.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/monitor/recording/monitor_sampler.dart';
import 'package:neurofeed/src/rust/api/device_config.dart';
import 'package:neurofeed/src/rust/api/muse.dart';
import 'package:neurofeed/src/session_format/computed_frame.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/spine/assemble.dart';
import 'package:shared_preferences/shared_preferences.dart';

MuseEventDto _pad(
  List<double> values,
  QualitySource source, [
  List<double>? crown,
]) => MuseEventDto.padQuality(
  PadQualityDto(
    values: Float64List.fromList(values),
    source: source,
    crown: crown == null ? null : Float64List.fromList(crown),
  ),
);

MuseEventDto _eeg(int electrode, double startMs, double value) =>
    MuseEventDto.eeg(
      EegDto(
        index: 0,
        electrode: electrode,
        timestamp: startMs,
        samples: Float64List.fromList(
          List.generate(256, (i) => i.isEven ? value : -value),
        ),
      ),
    );

ComputedFrame _frame({String? source, List<double>? crown}) => ComputedFrame(
  t: 1,
  bands: const [
    [1, 2, 3, 4, 5],
  ],
  lineNoise: const [0.01],
  signalQuality: const [90],
  guardrail: const GuardrailInfo(
    sleepDir: 0,
    clarity: 0,
    warning: false,
    delta: 0,
  ),
  feedback: const FeedbackInfo(ratio: 0, threshold: 0, inTarget: false, pct: 0),
  gestures: const [],
  signalQualitySource: source,
  crownSignalQuality: crown,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('crown_quality_source setting', () {
    test('defaults to crown and persists app', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await Settings.load();
      expect(settings.crownQualitySource, QualitySource.crown);
      await settings.setCrownQualitySource(QualitySource.app);
      final reloaded = await Settings.load();
      expect(reloaded.crownQualitySource, QualitySource.app);
    });

    test('unknown stored value reads as crown', () async {
      SharedPreferences.setMockInitialValues({'crown_quality_source': 'v1'});
      final settings = await Settings.load();
      expect(settings.crownQualitySource, QualitySource.crown);
    });
  });

  group('PadQuality events drive app state', () {
    late AppStateNotifier app;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      app = AppStateNotifier.forTest(await Settings.load());
      app.debugSetConnected(
        kind: DeviceKind.neurosity,
        name: 'Crown',
        id: 'sim:crown',
        firmware: 'Crown',
      );
    });

    tearDown(() => app.dispose());

    test('crown second, then app fallback second', () {
      final crown = [0.9, 0.2, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9];
      app.debugAddEvent(
        _pad([92, 21, 92, 92, 92, 92, 92, 92], QualitySource.crown, crown),
      );
      expect(app.state.signalQuality, [92, 21, 92, 92, 92, 92, 92, 92]);
      expect(app.state.signalQualitySource, QualitySource.crown);
      expect(app.state.crownSignalQuality, crown);

      app.debugAddEvent(_pad(List.filled(8, 55), QualitySource.app));
      expect(app.state.signalQuality, List<double>.filled(8, 55));
      expect(app.state.signalQualitySource, QualitySource.app);
      expect(app.state.crownSignalQuality, isNull);
    });

    test('EEG does not replace a PadQuality score', () {
      app.debugAddEvent(
        _pad(List.filled(8, 88), QualitySource.crown, List.filled(8, 0.8)),
      );
      for (var s = 0; s < 3; s++) {
        for (var e = 0; e < 8; e++) {
          app.debugAddEvent(_eeg(e, 1000.0 * s, 300));
        }
      }
      expect(app.state.signalQuality, List<double>.filled(8, 88));
    });

    test('disconnect clears source and Crown values', () {
      app.debugMarkUserDisconnected();
      app.debugAddEvent(
        _pad(List.filled(8, 88), QualitySource.crown, List.filled(8, 0.8)),
      );
      app.debugAddEvent(const MuseEventDto.disconnected());
      expect(app.state.signalQuality, isNull);
      expect(app.state.signalQualitySource, isNull);
      expect(app.state.crownSignalQuality, isNull);
    });
  });

  test(
    'Muse quality comes from PadQuality and does not record a source',
    () async {
      SharedPreferences.setMockInitialValues({});
      final app = AppStateNotifier.forTest(await Settings.load());
      addTearDown(app.dispose);
      app.debugSetConnected();
      for (var s = 0; s < 3; s++) {
        for (var e = 0; e < 4; e++) {
          app.debugAddEvent(_eeg(e, 1000.0 * s, 5));
        }
      }
      expect(app.state.signalQuality, isNull);
      expect(app.state.signalQualitySource, isNull);
      expect(app.state.crownSignalQuality, isNull);

      app.debugAddEvent(_pad(const [90, 80, 70, 60], QualitySource.app));
      expect(app.state.signalQuality, [90, 80, 70, 60]);
      expect(app.state.signalQualitySource, isNull);
      expect(app.state.crownSignalQuality, isNull);

      app.debugAddEvent(
        _pad(const [1, 2, 3, 4, 5], QualitySource.crown, List.filled(8, 0.5)),
      );
      expect(app.state.signalQuality, [1, 2, 3, 4, 5]);
      expect(app.state.signalQualitySource, isNull);
      expect(app.state.crownSignalQuality, isNull);

      app.debugAddEvent(_eeg(0, 4000, 80));
      expect(app.state.signalQuality, [1, 2, 3, 4, 5]);
    },
  );

  group('computed frame quality source', () {
    test('JSON round-trip keeps source and Crown values', () {
      final f = _frame(
        source: 'crown',
        crown: [0.9, 0.1, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8],
      );
      final json = jsonDecode(jsonEncode(f.toJson())) as Map<String, dynamic>;
      expect(json['signalQualitySource'], 'crown');
      expect(json['crownSignalQuality'], hasLength(8));
      final back = ComputedFrame.fromJson(json);
      expect(back.signalQualitySource, 'crown');
      expect(back.crownSignalQuality, f.crownSignalQuality);
      final ffi = toFfiFrame(back);
      expect(ffi.signalQualitySource, 'crown');
      expect(ffi.crownSignalQuality![1], closeTo(0.1, 1e-6));
    });

    test('keys are omitted when unset', () {
      final json = _frame().toJson();
      expect(json.containsKey('signalQualitySource'), isFalse);
      expect(json.containsKey('crownSignalQuality'), isFalse);
      final app = _frame(source: 'app').toJson();
      expect(app['signalQualitySource'], 'app');
      expect(app.containsKey('crownSignalQuality'), isFalse);
    });

    test('samplers stamp the latest source on each frame', () {
      final frames = <ComputedFrame>[];
      final start = DateTime.utc(2026, 9, 27);
      final sampler = ComputedSampler(
        onFrame: frames.add,
        recordingStart: start,
        now: () => start.add(const Duration(seconds: 1)),
      );
      sampler.updateSignalQualitySource(
        QualitySource.crown,
        List.filled(8, 0.9),
      );
      sampler.emitFrame();
      sampler.updateSignalQualitySource(QualitySource.app, null);
      sampler.emitFrame();
      expect(frames[0].signalQualitySource, 'crown');
      expect(frames[0].crownSignalQuality, List<double>.filled(8, 0.9));
      expect(frames[1].signalQualitySource, 'app');
      expect(frames[1].crownSignalQuality, isNull);

      final mon = <ComputedFrame>[];
      final monitor = MonitorSampler(
        channelCount: 8,
        captureStartedAtMs: 0,
        onFrame: mon.add,
        nowMs: () => 1000,
      );
      monitor.emitFrame();
      monitor.updateSignalQualitySource(
        QualitySource.crown,
        List.filled(8, 0.8),
      );
      monitor.emitFrame();
      expect(mon[0].signalQualitySource, isNull);
      expect(mon[1].signalQualitySource, 'crown');
      expect(mon[1].crownSignalQuality, List<double>.filled(8, 0.8));
    });
  });

  test('sessionSettings carries crownQualitySource', () {
    const ss = SessionSettings(
      dynamicAdapt: false,
      responsiveness: 0,
      baselinePercentile: 50,
      guardrailEnabled: false,
      guardrailEngine: 'none',
      warningThresholdPercentile: 0,
      warningSound: '',
      musicFolder: null,
      musicMinCutoffHz: 0,
      musicMaxCutoffHz: 0,
      musicInvert: false,
      musicShuffle: false,
      binauralPresetId: '',
      binauralCarrierHz: 0,
      binauralBeatHz: 0,
      backgroundBinauralPresetId: '',
      backgroundBinauralCarrierHz: 0,
      backgroundBinauralBeatHz: 0,
      markersInFeedbackEnabled: false,
      eyeMarkersEnabled: false,
      crownQualitySource: 'app',
    );
    final json = ss.toJson();
    expect(json['crownQualitySource'], 'app');
    expect(SessionSettings.fromJson(json)!.crownQualitySource, 'app');
  });
}
