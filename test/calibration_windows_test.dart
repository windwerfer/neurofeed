import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/audio/calibration_clips.dart';
import 'package:neurofeed/src/feedback/calibration_runner.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/session_format/metadata.dart';
import 'package:neurofeed/src/settings.dart';

CalibrationManifest _manifest() => CalibrationManifest(
  version: 2,
  calibrations: {
    'eyes-closed-01': Calibration(
      id: 'eyes-closed-01',
      name: 'Eyes Closed',
      single: CalibrationRecipe.single(
        seconds: 45,
        eyes: 'closed',
        intros: const [
          CalibrationStep(id: 'intro', file: 'clip.opus', text: 'rest'),
        ],
      ),
      staged: CalibrationRecipe.staged(
        stages: const [
          CalibrationStep(id: 'reve-artifacts', file: 'a.opus', seconds: 1),
          CalibrationStep(
            id: 'reve-eyes-open-counting',
            file: 'o.opus',
            seconds: 1,
            eyes: 'open',
            challengeText: ['Count'],
          ),
          CalibrationStep(
            id: 'reve-eyes-closed-drifting',
            file: 'c.opus',
            seconds: 45,
            eyes: 'closed',
          ),
        ],
      ),
    ),
  },
  protocolCalibration: const {'calibrateRecord': 'eyes-closed-01'},
);

/// Runs one calibration with a controllable clock: every prompt clip "plays"
/// for 3 s, artifact / challenge stages use their real 1 s timers, and the
/// rest window is fed 45 accepted frames one second apart.
Future<({CalibrationRunner runner, List<Map<String, dynamic>> meta})> _run(
  CalibrationPlan plan,
) async {
  final base = DateTime.utc(2026, 10, 6, 14);
  final realStart = DateTime.now();
  var extra = Duration.zero;
  DateTime clock() => base.add(DateTime.now().difference(realStart) + extra);
  final meta = <Map<String, dynamic>>[];
  late CalibrationRunner runner;
  runner = CalibrationRunner(
    loadManifest: () async => _manifest(),
    playClip: (_) async => extra += const Duration(seconds: 3),
    writeMetadata: meta.add,
    updateUi: (_) {},
    isActive: () => true,
    protocolOf: () => 'calibrateRecord',
    sessionStartAt: () => base,
    onCollectionEyes: (_) {},
    onFinished: () {},
    baselineFrameValid: () => true,
    clock: clock,
  );
  final done = runner.playAndBaseline(plan: plan);
  for (var i = 0; i < 400 && !runner.collectingBaselineWindow; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(runner.collectingBaselineWindow, isTrue);
  for (var i = 0; i < 46 && runner.collectingBaselineWindow; i++) {
    extra += const Duration(seconds: 1);
    runner.noteBaselineFrame(featureId: 'band.atr');
    runner.finishBaselineFrame();
  }
  await done;
  return (runner: runner, meta: meta);
}

void main() {
  test('staged calibration records each stage\'s quiet window', () async {
    final (:runner, :meta) = await _run(CalibrationPlan.stagedAi);
    expect(runner.kind, 'staged');
    final w = runner.stageWindows;
    expect(
      [for (final x in w) x.stage],
      [
        calibrationWindowArtifacts,
        calibrationWindowEyesOpenClear,
        calibrationWindowEyesClosedRest,
      ],
    );
    expect([for (final x in w) x.eyes], [null, 'open', 'closed']);
    expect(
      [for (final x in w) x.clipId],
      [
        'reve-artifacts',
        'reve-eyes-open-counting',
        'reve-eyes-closed-drifting',
      ],
    );

    // Each window starts after its prompt clip ended (quiet part only) and
    // windows are ordered and do not overlap the next prompt.
    final phases = runner.clipPhases;
    expect(phases, hasLength(3));
    for (var i = 0; i < 3; i++) {
      expect(w[i].startSecs, greaterThanOrEqualTo(phases[i].endSecs!));
      expect(w[i].endSecs, greaterThan(w[i].startSecs));
      if (i < 2) {
        expect(w[i].endSecs, lessThanOrEqualTo(phases[i + 1].startSecs!));
      }
    }
    // Timer stages ~1 s; the rest window covers the 45 fed seconds.
    expect(w[0].durationSecs, closeTo(1, 0.5));
    expect(w[1].durationSecs, closeTo(1, 0.5));
    expect(w[2].durationSecs, closeTo(45, 1.5));
    expect(w[0].startedAt, isNotNull);
    expect(DateTime.parse(w[0].startedAt!).isUtc, isTrue);

    // One calibration_window sidecar line per stage (crash recovery).
    final lines = [
      for (final m in meta)
        if (m['type'] == 'calibration_window') m,
    ];
    expect(lines, hasLength(3));
    expect(lines.last['stage'], calibrationWindowEyesClosedRest);
    expect(lines.last['eyes'], 'closed');
    expect(lines.first.containsKey('eyes'), isFalse);
  });

  test('single calibration writes no windows', () async {
    final (:runner, :meta) = await _run(CalibrationPlan.baselineOnly);
    expect(runner.kind, 'single');
    expect(runner.stageWindows, isEmpty);
    expect(meta.where((m) => m['type'] == 'calibration_window'), isEmpty);
  });

  group('calibration windows metadata', () {
    const windows = [
      SessionCalibrationWindow(
        stage: calibrationWindowArtifacts,
        startSecs: 6.1,
        endSecs: 21.1,
        startedAt: '2026-10-06T21:00:06.100+07:00',
        endedAt: '2026-10-06T21:00:21.100+07:00',
        clipId: 'reve-artifacts',
      ),
      SessionCalibrationWindow(
        stage: calibrationWindowEyesOpenClear,
        eyes: 'open',
        startSecs: 27.4,
        endSecs: 57.4,
        clipId: 'reve-eyes-open-counting',
      ),
      SessionCalibrationWindow(
        stage: calibrationWindowEyesClosedRest,
        eyes: 'closed',
        startSecs: 63,
        endSecs: 110,
        clipId: 'reve-eyes-closed-drifting',
      ),
    ];

    SessionMetadata session(SessionCalibration cal) => SessionMetadata(
      protocol: 'calibrateRecord',
      durationMinutes: 10,
      elapsedSeconds: 600,
      sound: 'None',
      savedAt: DateTime.utc(2026, 10, 6, 14).toIso8601String(),
      calibration: cal,
    );

    test('round-trips through SessionCalibration and SessionMetadata', () {
      const cal = SessionCalibration(
        version: 2,
        kind: 'staged',
        calibrationId: 'eyes-closed-01',
        windows: windows,
      );
      final json = cal.toJson();
      expect(json['windows'], hasLength(3));
      final back = SessionCalibration.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      )!;
      expect(back.windows, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(back.windows[i].toJson(), windows[i].toJson());
      }

      final meta = session(cal);
      final restored = SessionMetadata.fromJson(
        jsonDecode(jsonEncode(meta.toJson())) as Map<String, Object?>,
      )!;
      expect(restored.calibration!.windows, hasLength(3));
      expect(
        restored.calibration!.windows.last.stage,
        calibrationWindowEyesClosedRest,
      );
      expect(restored.calibration!.windows.first.eyes, isNull);
      expect(
        restored.calibration!.windows.first.startedAt,
        '2026-10-06T21:00:06.100+07:00',
      );
    });

    test('v6 writer (feedback.calibration.windows) -> reader', () {
      const cal = SessionCalibration(
        version: 2,
        kind: 'staged',
        calibrationId: 'eyes-closed-01',
        windows: windows,
      );
      final v6 = buildFeedbackMetadata(
        meta: session(cal),
        subject: const SubjectInfo(id: 'anon'),
      );
      final fb = v6['feedback'] as Map;
      final written = (fb['calibration'] as Map)['windows'] as List;
      expect(written, hasLength(3));
      expect((written[1] as Map)['stage'], 'eyes_open_clear');
      final read = SessionMetadata.fromJson(
        jsonDecode(jsonEncode(v6)) as Map<String, Object?>,
      )!;
      expect(
        [for (final w in read.calibration!.windows) w.stage],
        ['artifacts', 'eyes_open_clear', 'eyes_closed_rest'],
      );
      expect(read.calibration!.windows[2].endSecs, 110);
    });

    test('old sessions without windows still load (empty list)', () {
      final old = <String, Object?>{
        'version': 2,
        'kind': 'staged',
        'calibrationId': 'eyes-closed-01',
        'phases': [
          {'name': 'reve-artifacts', 'durationSecs': 6, 'sampleCount': 0},
        ],
      };
      final cal = SessionCalibration.fromJson(old)!;
      expect(cal.windows, isEmpty);
      expect(cal.phases, hasLength(1));
      expect(cal.toJson().containsKey('windows'), isFalse);
    });

    test('malformed window entries are dropped, not fatal', () {
      final cal = SessionCalibration.fromJson(<String, Object?>{
        'version': 2,
        'kind': 'staged',
        'calibrationId': 'eyes-closed-01',
        'windows': [
          {'stage': 'artifacts', 'startSecs': 1, 'endSecs': 2},
          {'stage': 'eyes_open_clear'},
          'garbage',
        ],
      })!;
      expect(cal.windows, hasLength(1));
      expect(cal.windows.single.stage, calibrationWindowArtifacts);
    });
  });
}
