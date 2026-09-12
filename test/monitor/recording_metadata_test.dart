import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/recording/recording_metadata.dart';
import 'package:muse_ml/src/session_v5/models.dart';
import 'package:muse_ml/src/settings.dart';

void main() {
  test('RecordingMetadata kind recording round-trips', () {
    final meta = RecordingMetadata(
      formatVersion: 5,
      appVersion: 'dev',
      kind: 'recording',
      savedAt: DateTime.utc(2026, 9, 12, 12),
      startedAt: DateTime.utc(2026, 9, 12, 11, 50),
      elapsedSeconds: 600,
      durationS: 600,
      device: const DeviceInfoV5(
        name: 'Muse 2 (Simulated)',
        id: 'sim:muse-2',
        firmware: 'Classic',
        model: 'Classic',
        sensors: ['EEG', 'PPG', 'IMU'],
        channelCount: 4,
        channelLabels: ['TP9', 'AF7', 'AF8', 'TP10'],
      ),
      streams: RecordingMetadata.streamsConfig(RecordingStream.values.toSet()),
    );
    final json = meta.toJson();
    expect(json['kind'], 'recording');
    final back = RecordingMetadata.fromJson(json);
    expect(back.kind, 'recording');
    expect(back.formatVersion, 5);
    expect(back.streams.eeg.enabled, isTrue);
    expect(back.streams.eeg.rateHz, 256);
    expect(back.streams.gestures.enabled, isFalse);
    expect(back.streams.gestures.rateHz, 0);
    expect(
      StreamsConfig.fromJson(json['streams'] as Map<String, dynamic>),
      isNotNull,
    );
  });
}
