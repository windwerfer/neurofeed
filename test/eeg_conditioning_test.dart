import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/monitor/recording/recording_metadata.dart';
import 'package:neurofeed/src/rust/api/eeg_conditioning.dart';
import 'package:neurofeed/src/rust/api/session_format.dart';
import 'package:neurofeed/src/rust/frb_generated.dart';
import 'package:neurofeed/src/session_format/eeg_conditioning_meta.dart';
import 'package:neurofeed/src/session_format/metadata.dart';
import 'package:neurofeed/src/session_format/models.dart';
import 'package:neurofeed/src/settings.dart';

final String _rustLibPath =
    '${Directory.current.path}/rust/target/debug/librust_lib_neurofeed.so';

const _startMs = 1790000000000;

const _live = EegConditioning(
  highPassHz: 0.5,
  notchQ: 30,
  decisions: [
    NotchDecision(timestampMs: _startMs - 2000.0, notchHz: null),
    NotchDecision(timestampMs: _startMs + 61500.0, notchHz: 50),
  ],
);

DeviceInfo _device(String firmware, List<String> labels) => DeviceInfo(
  name: firmware,
  id: 'id-$firmware',
  firmware: firmware,
  model: firmware,
  sensors: const ['EEG'],
  channelCount: labels.length,
  channelLabels: labels,
  rawFiltering: RawFiltering.deviceUnfiltered,
  conditioning: signalConditioningFrom(_live, startMs: _startMs),
);

/// Muse-style 12-sample packets for [channels]: offset + 10 µV alpha +
/// 60 µV hum at [mainsHz].
List<EegSampleRecord> _packets({
  required int channels,
  required int packetSamples,
  required double offset,
  required double mainsHz,
  required double seconds,
}) {
  final out = <EegSampleRecord>[];
  for (var n = 0; n < seconds * 256; n += packetSamples) {
    for (var e = 0; e < channels; e++) {
      out.add(
        EegSampleRecord(
          timestamp: _startMs + n * 1000.0 / 256,
          electrode: e,
          samples: Float32List.fromList([
            for (var k = n; k < n + packetSamples; k++)
              offset +
                  e * 11 +
                  10 * math.sin(2 * math.pi * 10 * k / 256) +
                  60 * math.sin(2 * math.pi * mainsHz * k / 256),
          ]),
        ),
      );
    }
  }
  return out;
}

void main() {
  group('rawFiltering / conditioning metadata', () {
    for (final (firmware, labels) in [
      ('Classic', const ['TP9', 'AF7', 'AF8', 'TP10']),
      ('Athena', const ['TP9', 'AF7', 'AF8', 'TP10']),
      ('Crown', const ['CP3', 'C3', 'F5', 'PO3', 'PO4', 'F6', 'C4', 'CP4']),
    ]) {
      test('$firmware recording round-trips', () {
        final meta = RecordingMetadata(
          formatVersion: 6,
          appVersion: 'test',
          kind: 'recording',
          savedAt: DateTime.utc(2026, 9, 27),
          startedAt: DateTime.fromMillisecondsSinceEpoch(_startMs),
          elapsedSeconds: 120,
          durationS: 120,
          device: _device(firmware, labels),
          streams: RecordingMetadata.streamsConfig(
            RecordingStream.values.toSet(),
          ),
        );
        final json = meta.toJson();
        final device = json['device'] as Map;
        expect(device['rawFiltering'], {
          'storedAsReceived': true,
          'highPassHz': null,
          'notchHz': null,
        });
        expect(device['conditioning'], {
          'highPassHz': 0.5,
          'notchQ': 30.0,
          'notchHz': 50.0,
          'notchChanges': [
            {'onset': -2.0, 'notchHz': null},
            {'onset': 61.5, 'notchHz': 50.0},
          ],
        });
        final back = RecordingMetadata.fromJson(json).device;
        expect(back.rawFiltering!.storedAsReceived, isTrue);
        expect(back.rawFiltering!.edfPrefiltering, 'HP:DC N:none');
        expect(back.conditioning!.notchHz, 50);
        expect(back.conditioning!.notchChanges.map((c) => c.onset), [
          -2.0,
          61.5,
        ]);
      });
    }

    test('no decision yet: notchHz null, no changes', () {
      final c = signalConditioningFrom(
        const EegConditioning(highPassHz: 0.5, notchQ: 30, decisions: []),
        startMs: _startMs,
      );
      expect(c.notchHz, isNull);
      expect(c.notchChanges, isEmpty);
      expect(SignalConditioning.fromJson(c.toJson())!.highPassHz, 0.5);
    });

    test('feedback metadata carries both blocks through SessionMetadata', () {
      final json = buildFeedbackMetadata(
        meta: SessionMetadata(
          protocol: 'alpha',
          durationMinutes: 5,
          elapsedSeconds: 300,
          sound: 'Ambient',
          savedAt: '2026-09-27T23:00:00.000+07:00',
          timeZone: 'Asia/Bangkok',
          recordedChannels: const ['TP9', 'AF7', 'AF8', 'TP10'],
          rawFiltering: RawFiltering.deviceUnfiltered,
          conditioning: signalConditioningFrom(_live, startMs: _startMs),
        ),
        subject: const SubjectInfo(id: 'anon'),
      );
      final device = json['device'] as Map;
      expect((device['rawFiltering'] as Map)['storedAsReceived'], isTrue);
      expect((device['conditioning'] as Map)['notchHz'], 50.0);
      final back = SessionMetadata.fromJson(json)!;
      expect(back.rawFiltering!.notchHz, isNull);
      expect(back.conditioning!.notchChanges.length, 2);
      final flat = SessionMetadata.fromJson(back.toJson())!;
      expect(flat.conditioning!.notchHz, 50);
    });

    test('EDF prefiltering text', () {
      expect(RawFiltering.deviceUnfiltered.edfPrefiltering, 'HP:DC N:none');
      expect(
        const RawFiltering(highPassHz: 0.1, notchHz: 50).edfPrefiltering,
        'HP:0.1Hz N:50Hz',
      );
    });
  });

  group('conditionEeg (Rust)', () {
    setUpAll(() async {
      await RustLib.init(externalLibrary: ExternalLibrary.open(_rustLibPath));
    });

    for (final (name, channels, packet, offset) in [
      ('Muse', 4, 12, 800.0),
      ('Crown', 8, 16, -2.0e5),
    ]) {
      test('$name: offset + hum removed, input RAW unchanged', () {
        final raw = _packets(
          channels: channels,
          packetSamples: packet,
          offset: offset,
          mainsHz: 50,
          seconds: 4,
        );
        final before = [for (final r in raw) List<double>.of(r.samples)];
        final out = conditionEeg(eeg: raw);
        expect(out.eeg.length, raw.length);
        expect(out.conditioning.decisions.single.notchHz, 50);
        for (var i = 0; i < raw.length; i++) {
          expect(raw[i].samples, before[i]);
          expect(out.eeg[i].electrode, raw[i].electrode);
          expect(out.eeg[i].timestamp, raw[i].timestamp);
          expect(out.eeg[i].samples.length, raw[i].samples.length);
        }
        // Last second: only the 10 µV alpha is left.
        final lastSecond = out.eeg.where(
          (r) => r.timestamp >= _startMs + 3000 && r.electrode == 1,
        );
        final peak = lastSecond
            .expand((r) => r.samples)
            .map((v) => v.abs())
            .reduce(math.max);
        expect(peak, inInclusiveRange(9.0, 11.0));
      });
    }
  });
}
