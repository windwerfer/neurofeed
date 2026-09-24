import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/monitor/recording/recording_metadata.dart';
import 'package:neurofeed/src/session_v5/metadata_v6.dart';
import 'package:neurofeed/src/session_v5/models.dart';
import 'package:neurofeed/src/settings.dart';

void main() {
  test('recording v6 metadata has NFED6 identity fields', () {
    final json = buildRecordingMetadataV6(
      meta: RecordingMetadata(
        formatVersion: 6,
        appVersion: 'dev',
        kind: 'recording',
        savedAt: DateTime(2026, 9, 24, 17, 30),
        startedAt: DateTime(2026, 9, 24, 17, 20),
        timeZone: 'Asia/Bangkok',
        sessionId: 'sess-1',
        elapsedSeconds: 600,
        durationS: 600,
        device: const DeviceInfoV5(
          name: 'Muse',
          id: 'id',
          firmware: 'f',
          model: 'm',
          sensors: ['EEG'],
          channelCount: 4,
          channelLabels: ['TP9', 'AF7', 'AF8', 'TP10'],
        ),
        streams: RecordingMetadata.streamsConfig({RecordingStream.eeg}),
      ),
      subject: const SubjectInfo(id: 'anon-1', nickname: 'River'),
    );
    expect(json['formatVersion'], 6);
    expect(json['kind'], 'recording');
    expect(json['sessionId'], 'sess-1');
    expect(json['timeZone'], 'Asia/Bangkok');
    expect((json['subject'] as Map)['id'], 'anon-1');
    expect(json.containsKey('feedback'), isFalse);
    expect((json['savedAt'] as String).contains('+') || (json['savedAt'] as String).endsWith('Z'), isTrue);
  });

  test('feedback v6 nests protocol under feedback{}', () {
    final json = buildFeedbackMetadataV6(
      meta: SessionMetadata(
        protocol: 'drowsiness',
        durationMinutes: 15,
        elapsedSeconds: 100,
        sound: 'Ambient',
        savedAt: '2026-09-24T17:30:00.000+07:00',
        startedAt: '2026-09-24T17:20:00.000+07:00',
        timeZone: 'Asia/Bangkok',
        sessionId: 'fb-1',
      ),
      subject: const SubjectInfo(id: 'anon-1'),
    );
    expect(json['formatVersion'], 6);
    expect(json['kind'], 'feedback');
    final fb = json['feedback'] as Map;
    expect(fb['protocol'], 'drowsiness');
    expect(fb['durationMinutes'], 15);
    expect(json.containsKey('protocol'), isFalse);
  });

  test('fromJson reads nested feedback{} dialect (History/export)', () {
    final built = buildFeedbackMetadataV6(
      meta: SessionMetadata(
        protocol: 'drowsiness',
        durationMinutes: 15,
        elapsedSeconds: 100,
        sound: 'Ambient',
        savedAt: '2026-09-24T17:30:00.000+07:00',
        startedAt: '2026-09-24T17:20:00.000+07:00',
        timeZone: 'Asia/Bangkok',
        sessionId: 'fb-1',
        pctInTarget: 42.5,
        userId: 'should-be-overridden-by-subject',
      ),
      subject: const SubjectInfo(id: 'anon-1', nickname: 'River'),
    );
    final restored = SessionMetadata.fromJson(built)!;
    expect(restored.protocol, 'drowsiness');
    expect(restored.durationMinutes, 15);
    expect(restored.timeZone, 'Asia/Bangkok');
    expect(restored.userId, 'anon-1');
    expect(restored.pctInTarget, 42.5);
    expect(restored.sessionId, 'fb-1');
    expect(built.containsKey('protocol'), isFalse);
  });
}
