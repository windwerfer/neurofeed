import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/feedback/session_metadata.dart';
import 'package:muse_ml/src/feedback/protocol.dart';

void main() {
  group('SessionMetadata round-trip', () {
    test('full metadata serializes and deserializes correctly', () {
      final now = DateTime.utc(2026, 8, 19, 10, 30);
      final original = SessionMetadata(
        protocol: ProtocolType.drowsiness,
        durationMinutes: 15,
        elapsedSeconds: 900,
        sound: 'Bowl Chimes',
        savedAt: now.toIso8601String(),
        notes: 'Test session notes',
        stats: SessionStatsData(
          peakAlphaFreq: 10.5,
          peakAlphaPower: 120.0,
          targetPct: 65.0,
          stillnessPct: 85.0,
          avgBpm: 72.0,
          avgAlphaRel: 0.35,
        ),
        deviceName: 'Muse S',
        deviceModel: 'Muse S Gen 2',
        deviceId: '00:11:22:33:44:55',
        recordedChannels: ['TP9', 'AF7', 'AF8', 'TP10'],
        recordedData: ['eeg', 'bands', 'pulse', 'movement', 'spo2'],
        summary: SessionOverview(
          bucketCount: 400,
          bucketWidthSecs: 2.25,
          startSecs: 0,
          endSecs: 900,
          trainingStartSecs: 95.0,
          bands: {
            1: BandPowerSeries(
              delta: List.filled(400, 0.25),
              theta: List.filled(400, 0.20),
              alpha: List.filled(400, 0.35),
              beta: List.filled(400, 0.15),
              gamma: List.filled(400, 0.05),
            ),
            2: BandPowerSeries(
              delta: List.filled(400, 0.26),
              theta: List.filled(400, 0.19),
              alpha: List.filled(400, 0.36),
              beta: List.filled(400, 0.14),
              gamma: List.filled(400, 0.05),
            ),
          },
          pulse: List.generate(400, (i) => 70.0 + (i % 10) * 0.5),
          spo2: List.generate(400, (i) => 98.0 - (i % 5) * 0.2),
          movement: List.generate(400, (i) => 0.1 + (i % 20) * 0.01),
          peakAlphaFreq: List.generate(400, (i) => 10.0 + (i % 4) * 0.1),
          peakAlphaPower: List.generate(400, (i) => 100.0 + (i % 10) * 5.0),
        ),
        gestures: [
          GestureMarker(type: GestureType.doubleBlink, offsetSeconds: 100),
          GestureMarker(type: GestureType.doubleClench, offsetSeconds: 250),
          GestureMarker(type: GestureType.eyeUp, offsetSeconds: 400),
          GestureMarker(type: GestureType.eyeDown, offsetSeconds: 550),
        ],
        calibration: SessionCalibration(
          version: 2,
          kind: 'staged',
          calibrationId: 'eyes-closed-01',
          calibrationJson: {'name': 'Eyes Closed', 'staged': {'stages': []}},
          calibrationStartSecs: 0,
          calibrationEndSecs: 90,
          trainingStartSecs: 95,
          usedStartAnyway: false,
          greenStableSeconds: 3,
          faultyPadSeconds: 20,
          baseline: SessionBaselineStats(
            percentile: 40,
            count: 900,
            mean: 1.5,
            stddev: 0.3,
            floor: 1.0,
            ceiling: 2.0,
          ),
          phases: [
            SessionCalibrationPhase(
              name: 'Artifacts',
              durationSecs: 15,
              sampleCount: 150,
              clipFile: 'assets/audio/calibration/artifacts.opus',
              spokenText: 'Blink and clench',
              eyes: null,
              challengeText: null,
              kind: 'stage',
              startSecs: 0,
              endSecs: 15,
            ),
            SessionCalibrationPhase(
              name: 'Eyes open',
              durationSecs: 30,
              sampleCount: 300,
              clipFile: 'assets/audio/calibration/eyes_open.opus',
              spokenText: 'Keep eyes open',
              eyes: 'open',
              challengeText: 'Name capital cities',
              kind: 'stage',
              startSecs: 15,
              endSecs: 45,
            ),
            SessionCalibrationPhase(
              name: 'Eyes closed',
              durationSecs: 45,
              sampleCount: 450,
              clipFile: 'assets/audio/calibration/eyes_closed.opus',
              spokenText: 'Close eyes and rest',
              eyes: 'closed',
              challengeText: null,
              kind: 'stage',
              startSecs: 45,
              endSecs: 90,
            ),
          ],
          recalibrations: [
            SessionRecalibration(
              atSecs: 300,
              baseline: SessionBaselineStats(
                percentile: 40,
                count: 300,
                mean: 1.6,
                stddev: 0.25,
                floor: 1.1,
                ceiling: 2.1,
              ),
            ),
            SessionRecalibration(
              atSecs: 600,
              baseline: SessionBaselineStats(
                percentile: 40,
                count: 300,
                mean: 1.55,
                stddev: 0.28,
                floor: 1.05,
                ceiling: 2.05,
              ),
            ),
          ],
        ),
        drowsiness: SessionDrowsiness(
          scoreTotalPct: 12.5,
          meanSleepDir: 0.35,
          threshold: 0.6,
          series: [
            for (var i = 0; i < 10; i++)
              DrowsinessSample(
                offsetSecs: i * 90.0,
                sleepDir: 0.2 + i * 0.03,
                delta: 80.0 + i * 5.0,
                warning: i > 7,
              ),
          ],
          buckets: [
            for (var i = 0; i < 400; i++)
              DrowsinessSample(
                offsetSecs: i * 2.25,
                sleepDir: 0.3,
                delta: 100.0,
                warning: false,
              ),
          ],
          bucketWidthSecs: 2.25,
        ),
        music: SessionMusic(
          trackCount: 3,
          minCutoffHz: 200,
          maxCutoffHz: 8000,
          invert: false,
          shuffle: true,
          tracks: [
            MusicTrackMarker(offsetSecs: 0, name: 'Track 1 - Ambient'),
            MusicTrackMarker(offsetSecs: 300, name: 'Track 2 - Drone'),
            MusicTrackMarker(offsetSecs: 600, name: 'Track 3 - Rain'),
          ],
          series: [
            for (var i = 0; i < 10; i++)
              MusicCutoffSample(
                offsetSecs: i * 90.0,
                cutoffHz: 2000.0 + i * 500.0,
              ),
          ],
          buckets: [
            for (var i = 0; i < 400; i++)
              MusicCutoffSample(
                offsetSecs: i * 2.25,
                cutoffHz: 4500.0,
              ),
          ],
          bucketWidthSecs: 2.25,
        ),
        feedbackSound: 'Bowl chimes',
        metadataDescription: 'Trains the calm-awake rest state...',
        sessionSettings: SessionSettings(
          dynamicAdapt: true,
          responsiveness: 0.5,
          baselinePercentile: 40,
          guardrailEnabled: true,
          guardrailEngine: 'lunaLarge',
          warningThresholdPercentile: 75,
          warningSound: 'softBowl',
          musicFolder: '/storage/emulated/0/Music',
          musicMinCutoffHz: 200,
          musicMaxCutoffHz: 8000,
          musicInvert: false,
          musicShuffle: true,
          binauralPresetId: 'alpha',
          binauralCarrierHz: 200,
          binauralBeatHz: 10,
          markersInFeedbackEnabled: true,
          eyeMarkersEnabled: false,
        ),
        durationS: 900,
        startedAt: now.toIso8601String(),
        protocolVersion: '2',
        calibrationProfile: 'eyes-closed-01',
        avgSpo2: 98.2,
        peakAlphaHz: 10.3,
        peakAlphaPower: 125.0,
        pctInTarget: 65.0,
        avgMovement: 0.15,
        guardrailWarnCount: 3,
        avgSleepDir: 0.35,
        signalQualityMean: 85.0,
        pctQcOk: 92.0,
        guardrailEngine: 'lunaLarge',
        modelKind: 'lunaLarge',
        modelSha256: 'abc123...',
        feedbackEngine: 'ratio',
        userId: 'user_123',
        sessionId: 'session_abc12345',
      );

      // Serialize to JSON
      final json = original.toJson();

      // Deserialize back
      final restored = SessionMetadata.fromJson(json)!;

      // Verify all fields match
      expect(restored.protocol, equals(original.protocol));
      expect(restored.durationMinutes, equals(original.durationMinutes));
      expect(restored.elapsedSeconds, equals(original.elapsedSeconds));
      expect(restored.sound, equals(original.sound));
      expect(restored.savedAt, equals(original.savedAt));
      expect(restored.notes, equals(original.notes));
      expect(restored.stats?.peakAlphaFreq, equals(original.stats?.peakAlphaFreq));
      expect(restored.stats?.peakAlphaPower, equals(original.stats?.peakAlphaPower));
      expect(restored.stats?.targetPct, equals(original.stats?.targetPct));
      expect(restored.stats?.stillnessPct, equals(original.stats?.stillnessPct));
      expect(restored.stats?.avgBpm, equals(original.stats?.avgBpm));
      expect(restored.stats?.avgAlphaRel, equals(original.stats?.avgAlphaRel));
      expect(restored.deviceName, equals(original.deviceName));
      expect(restored.deviceModel, equals(original.deviceModel));
      expect(restored.deviceId, equals(original.deviceId));
      expect(restored.recordedChannels, equals(original.recordedChannels));
      expect(restored.recordedData, equals(original.recordedData));
      expect(restored.summary?.bucketCount, equals(original.summary?.bucketCount));
      expect(restored.summary?.bucketWidthSecs, equals(original.summary?.bucketWidthSecs));
      expect(restored.summary?.startSecs, equals(original.summary?.startSecs));
      expect(restored.summary?.endSecs, equals(original.summary?.endSecs));
      expect(restored.summary?.trainingStartSecs, equals(original.summary?.trainingStartSecs));
      expect(restored.gestures.length, equals(original.gestures.length));
      for (var i = 0; i < original.gestures.length; i++) {
        expect(restored.gestures[i].type, equals(original.gestures[i].type));
        expect(restored.gestures[i].offsetSeconds, equals(original.gestures[i].offsetSeconds));
      }
      expect(restored.calibration?.version, equals(original.calibration?.version));
      expect(restored.calibration?.kind, equals(original.calibration?.kind));
      expect(restored.calibration?.calibrationId, equals(original.calibration?.calibrationId));
      expect(restored.calibration?.trainingStartOffsetSecs, equals(original.calibration?.trainingStartOffsetSecs));
      expect(restored.calibration?.phases.length, equals(original.calibration?.phases.length));
      expect(restored.calibration?.recalibrations.length, equals(original.calibration?.recalibrations.length));
      expect(restored.drowsiness?.scoreTotalPct, equals(original.drowsiness?.scoreTotalPct));
      expect(restored.drowsiness?.meanSleepDir, equals(original.drowsiness?.meanSleepDir));
      expect(restored.drowsiness?.threshold, equals(original.drowsiness?.threshold));
      expect(restored.music?.trackCount, equals(original.music?.trackCount));
      expect(restored.music?.tracks.length, equals(original.music?.tracks.length));
      expect(restored.feedbackSound, equals(original.feedbackSound));
      expect(restored.metadataDescription, equals(original.metadataDescription));
      expect(restored.sessionSettings?.dynamicAdapt, equals(original.sessionSettings?.dynamicAdapt));
      expect(restored.sessionSettings?.baselinePercentile, equals(original.sessionSettings?.baselinePercentile));
      expect(restored.sessionSettings?.guardrailEngine, equals(original.sessionSettings?.guardrailEngine));
      expect(restored.durationS, equals(original.durationS));
      expect(restored.startedAt, equals(original.startedAt));
      expect(restored.protocolVersion, equals(original.protocolVersion));
      expect(restored.calibrationProfile, equals(original.calibrationProfile));
      expect(restored.avgSpo2, equals(original.avgSpo2));
      expect(restored.peakAlphaHz, equals(original.peakAlphaHz));
      expect(restored.peakAlphaPower, equals(original.peakAlphaPower));
      expect(restored.pctInTarget, equals(original.pctInTarget));
      expect(restored.avgMovement, equals(original.avgMovement));
      expect(restored.guardrailWarnCount, equals(original.guardrailWarnCount));
      expect(restored.avgSleepDir, equals(original.avgSleepDir));
      expect(restored.signalQualityMean, equals(original.signalQualityMean));
      expect(restored.pctQcOk, equals(original.pctQcOk));
      expect(restored.guardrailEngine, equals(original.guardrailEngine));
      expect(restored.modelKind, equals(original.modelKind));
      expect(restored.modelSha256, equals(original.modelSha256));
      expect(restored.feedbackEngine, equals(original.feedbackEngine));
      expect(restored.userId, equals(original.userId));
      expect(restored.sessionId, equals(original.sessionId));
    });

    test('minimal metadata round-trip', () {
      final original = SessionMetadata(
        protocol: ProtocolType.alertnessOpen,
        durationMinutes: 10,
        elapsedSeconds: 600,
        sound: 'Ambient Drone',
        savedAt: DateTime.utc(2026, 1, 1, 12, 0).toIso8601String(),
      );

      final json = original.toJson();
      final restored = SessionMetadata.fromJson(json)!;

      expect(restored.protocol, equals(ProtocolType.alertnessOpen));
      expect(restored.durationMinutes, equals(10));
      expect(restored.elapsedSeconds, equals(600));
      expect(restored.sound, equals('Ambient Drone'));
      expect(restored.gestures, isEmpty);
      expect(restored.calibration, isNull);
      expect(restored.drowsiness, isNull);
      expect(restored.music, isNull);
    });

    test('gesture marker round-trip', () {
      final markers = [
        GestureMarker(type: GestureType.doubleBlink, offsetSeconds: 1),
        GestureMarker(type: GestureType.doubleClench, offsetSeconds: 2),
        GestureMarker(type: GestureType.eyeUp, offsetSeconds: 3),
        GestureMarker(type: GestureType.eyeDown, offsetSeconds: 4),
      ];

      for (final marker in markers) {
        final json = marker.toJson();
        final restored = GestureMarker.fromJson(json)!;
        expect(restored.type, equals(marker.type));
        expect(restored.offsetSeconds, equals(marker.offsetSeconds));
      }
    });

    test('session calibration round-trip', () {
      final cal = SessionCalibration(
        version: 2,
        kind: 'single',
        calibrationId: 'eyes-open-01',
        calibrationJson: {'test': 'data'},
        calibrationStartSecs: 0,
        calibrationEndSecs: 90,
        trainingStartSecs: 95,
        usedStartAnyway: false,
        greenStableSeconds: 3,
        faultyPadSeconds: 20,
        baseline: SessionBaselineStats(
          percentile: 40,
          count: 100,
          mean: 1.5,
          stddev: 0.3,
        ),
        phases: [
          SessionCalibrationPhase(
            name: 'Intro',
            durationSecs: 5,
            sampleCount: 0,
            clipFile: 'assets/audio/calibration/intro.opus',
            spokenText: 'Welcome',
            eyes: 'open',
            kind: 'intro',
            startSecs: 0,
            endSecs: 5,
          ),
        ],
        recalibrations: [
          SessionRecalibration(
            atSecs: 300,
            baseline: SessionBaselineStats(
              percentile: 40,
              count: 50,
              mean: 1.6,
              stddev: 0.25,
            ),
          ),
        ],
      );

      final json = cal.toJson();
      final restored = SessionCalibration.fromJson(json)!;

      expect(restored.version, equals(2));
      expect(restored.kind, equals('single'));
      expect(restored.calibrationId, equals('eyes-open-01'));
      expect(restored.trainingStartOffsetSecs, equals(95.0));
      expect(restored.phases.length, equals(1));
      expect(restored.recalibrations.length, equals(1));
    });
  });
}