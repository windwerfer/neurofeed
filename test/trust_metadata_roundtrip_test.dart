import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/session_v5/metadata_v6.dart';
import 'package:neurofeed/src/settings.dart';

void main() {
  test('baselineSamples + inhibitCeilingOverrides + audioEvents round-trip in feedback{}', () {
    final meta = SessionMetadata(
      protocol: 'concentration',
      durationMinutes: 10,
      elapsedSeconds: 500,
      sound: 'Ambient',
      savedAt: '2026-09-24T17:30:00.000+07:00',
      timeZone: 'Asia/Bangkok',
      sessionId: 's1',
      calibration: SessionCalibration(
        version: 2,
        kind: 'single',
        calibrationId: 'eyes-closed-01',
        baselineSamples: [0.8, 0.9, 1.0, 1.1],
        recalibrations: [
          SessionRecalibration(
            atSecs: 200,
            baseline: const SessionBaselineStats(percentile: 40, count: 40),
            baselineSamples: [1.2, 1.3],
          ),
        ],
      ),
      sessionSettings: SessionSettings(
        dynamicAdapt: true,
        responsiveness: 0.5,
        baselinePercentile: 40,
        guardrailEnabled: true,
        guardrailEngine: 'band.delta',
        warningThresholdPercentile: 75,
        warningSound: 'softBowl',
        musicFolder: null,
        musicMinCutoffHz: 200,
        musicMaxCutoffHz: 8000,
        musicInvert: false,
        musicShuffle: false,
        binauralPresetId: '',
        binauralCarrierHz: 200,
        binauralBeatHz: 10,
        backgroundBinauralPresetId: '',
        backgroundBinauralCarrierHz: 200,
        backgroundBinauralBeatHz: 10,
        markersInFeedbackEnabled: true,
        eyeMarkersEnabled: false,
        inhibitCeilingOverrides: {'beta': 0.35, 'delta': 0.4},
      ),
      audioEvents: const [
        {'onset': 142.0, 'type': 'reward_chime'},
        {'onset': 410.0, 'type': 'guard_chime'},
      ],
    );

    final json = buildFeedbackMetadataV6(
      meta: meta,
      subject: const SubjectInfo(id: 'anon'),
    );
    final fb = json['feedback'] as Map;
    final cal = fb['calibration'] as Map;
    expect(cal['baselineSamples'], [0.8, 0.9, 1.0, 1.1]);
    final recal = (cal['recalibrations'] as List).first as Map;
    expect(recal['baselineSamples'], [1.2, 1.3]);
    final ss = fb['sessionSettings'] as Map;
    expect(ss['inhibitCeilingOverrides'], {'beta': 0.35, 'delta': 0.4});
    expect(fb['audioEvents'], [
      {'onset': 142.0, 'type': 'reward_chime'},
      {'onset': 410.0, 'type': 'guard_chime'},
    ]);
    expect(json.containsKey('audioEvents'), isFalse);

    // Round-trip calibration / settings through SessionMetadata JSON
    final calBack = SessionCalibration.fromJson(
      Map<String, Object?>.from(cal),
    )!;
    expect(calBack.baselineSamples, [0.8, 0.9, 1.0, 1.1]);
    expect(calBack.recalibrations.first.baselineSamples, [1.2, 1.3]);
    final ssBack = SessionSettings.fromJson(Map<String, Object?>.from(ss))!;
    expect(ssBack.inhibitCeilingOverrides, {'beta': 0.35, 'delta': 0.4});
  });
}
