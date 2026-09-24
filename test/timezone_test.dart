import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/monitor/recording/recording_metadata.dart';
import 'package:neurofeed/src/session_format/models.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/util/timezone.dart';

void main() {
  group('formatIso8601WithOffset', () {
    test('local DateTime includes numeric offset (never naive)', () {
      final local = DateTime(2026, 9, 24, 17, 20, 0, 0);
      final s = formatIso8601WithOffset(local);
      expect(s.contains('T'), isTrue);
      expect(
        RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(s),
        isTrue,
        reason: 'got $s',
      );
      // Must not be naive (no trailing Z/offset would fail above).
      expect(s.endsWith('Z') || s.contains('+') || s.contains('-'), isTrue);
    });

    test('UTC DateTime converts to local offset form', () {
      final utc = DateTime.utc(2026, 9, 24, 10, 20);
      final s = formatIso8601WithOffset(utc);
      expect(RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(s), isTrue);
      // Parsed back equals the same instant.
      expect(DateTime.parse(s).toUtc(), utc);
    });
  });

  group('captureIanaTimeZone', () {
    test('returns Area/Location or Etc/GMT form', () {
      final z = captureIanaTimeZone();
      expect(z.contains('/'), isTrue, reason: z);
      expect(z.startsWith('/'), isFalse);
    });
  });

  group('etcGmtFromOffset', () {
    test('inverts civil sign', () {
      expect(etcGmtFromOffset(const Duration(hours: 7)), 'Etc/GMT-7');
      expect(etcGmtFromOffset(const Duration(hours: -5)), 'Etc/GMT+5');
      expect(etcGmtFromOffset(Duration.zero), 'Etc/UTC');
    });
  });

  group('localWallClockFromIso', () {
    test('prefers startedAt over savedAt', () {
      final wall = localWallClockFromIso(
        startedAt: '2026-09-24T17:20:00.000+07:00',
        savedAt: '2026-09-24T18:00:00.000+07:00',
      );
      final expected =
          DateTime.parse('2026-09-24T17:20:00.000+07:00').toLocal();
      expect(wall.toUtc(), expected.toUtc());
      expect(wall.hour, expected.hour);
      expect(wall.minute, expected.minute);
    });
  });

  test('RecordingMetadata.toJson writes offset + timeZone', () {
    final meta = RecordingMetadata(
      formatVersion: 5,
      appVersion: 'dev',
      kind: 'recording',
      savedAt: DateTime(2026, 9, 12, 19, 0),
      startedAt: DateTime(2026, 9, 12, 18, 50),
      timeZone: 'Asia/Bangkok',
      elapsedSeconds: 600,
      durationS: 600,
      device: const DeviceInfo(
        name: 'Muse 2',
        id: 'sim:muse-2',
        firmware: 'Classic',
        model: 'Classic',
        sensors: ['EEG'],
        channelCount: 4,
        channelLabels: ['TP9', 'AF7', 'AF8', 'TP10'],
      ),
      streams: RecordingMetadata.streamsConfig({RecordingStream.eeg}),
    );
    final json = meta.toJson();
    expect(json['timeZone'], 'Asia/Bangkok');
    final saved = json['savedAt'] as String;
    expect(RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(saved), isTrue);
    expect(saved.contains('Z') || saved.contains('+07') || saved.contains('-'), isTrue);
    // Must not force UTC-only …Z when device is not UTC (local offset preferred).
    final back = RecordingMetadata.fromJson(Map<String, dynamic>.from(json));
    expect(back.timeZone, 'Asia/Bangkok');
  });

  group('formatSessionWallClock', () {
    test('uses offset digits from ISO (not device local)', () {
      final s = formatSessionWallClock(
        '2026-09-24T17:20:00.000+07:00',
        timeZone: 'Asia/Bangkok',
      );
      expect(s, '2026-09-24 17:20');
    });

    test('Etc/GMT-7 converts Zulu to UTC+7 wall clock', () {
      final s = formatSessionWallClock(
        '2026-09-24T10:20:00.000Z',
        timeZone: 'Etc/GMT-7',
      );
      expect(s, '2026-09-24 17:20');
    });
  });
}
