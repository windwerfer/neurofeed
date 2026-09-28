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
import 'package:shared_preferences/shared_preferences.dart';

final String _rustLibPath =
    '${Directory.current.path}/rust/target/debug/librust_lib_neurofeed.so';

const _startMs = 1790000000000;

SignalConditioning _conditioning(List<double> notchHz, String source) =>
    SignalConditioning(
      highPassHz: 0.5,
      notchQ: 10,
      notchHz: notchHz,
      notchSource: source,
    );

DeviceInfo _device(
  String firmware,
  List<String> labels,
  SignalConditioning conditioning,
) => DeviceInfo(
  name: firmware,
  id: 'id-$firmware',
  firmware: firmware,
  model: firmware,
  sensors: const ['EEG'],
  channelCount: labels.length,
  channelLabels: labels,
  rawFiltering: RawFiltering.deviceUnfiltered,
  conditioning: conditioning,
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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('rawFiltering / conditioning metadata', () {
    for (final (firmware, labels, notchHz, source) in [
      ('Classic', const ['TP9', 'AF7', 'AF8', 'TP10'], [50.0], 'detected'),
      ('Athena', const ['TP9', 'AF7', 'AF8', 'TP10'], <double>[], 'saved'),
      (
        'Crown',
        const ['CP3', 'C3', 'F5', 'PO3', 'PO4', 'F6', 'C4', 'CP4'],
        [50.0, 60.0],
        'undecided',
      ),
    ]) {
      test('$firmware recording round-trips notch $notchHz ($source)', () {
        final meta = RecordingMetadata(
          formatVersion: 6,
          appVersion: 'test',
          kind: 'recording',
          savedAt: DateTime.utc(2026, 9, 27),
          startedAt: DateTime.fromMillisecondsSinceEpoch(_startMs),
          elapsedSeconds: 120,
          durationS: 120,
          device: _device(firmware, labels, _conditioning(notchHz, source)),
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
          'notchQ': 10.0,
          'notchHz': notchHz,
          'notchSource': source,
        });
        final back = RecordingMetadata.fromJson(json).device;
        expect(back.rawFiltering!.storedAsReceived, isTrue);
        expect(back.rawFiltering!.edfPrefiltering, 'HP:DC N:none');
        expect(back.conditioning!.notchHz, notchHz);
        expect(back.conditioning!.notchSource, source);
      });
    }

    test('Rust conditioning maps to the metadata block and back', () {
      final rust = EegConditioning(
        highPassHz: 0.5,
        notchQ: 10,
        notchHz: Float64List.fromList([60]),
        notchSource: NotchSource.saved,
      );
      final c = signalConditioningFrom(rust);
      expect(c.toJson(), {
        'highPassHz': 0.5,
        'notchQ': 10.0,
        'notchHz': [60.0],
        'notchSource': 'saved',
      });
      final again = eegConditioningFrom(c);
      expect(again.notchHz, [60.0]);
      expect(again.notchSource, NotchSource.saved);
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
          conditioning: _conditioning([50.0], 'detected'),
        ),
        subject: const SubjectInfo(id: 'anon'),
      );
      final device = json['device'] as Map;
      expect((device['rawFiltering'] as Map)['storedAsReceived'], isTrue);
      expect((device['conditioning'] as Map)['notchHz'], [50.0]);
      final back = SessionMetadata.fromJson(json)!;
      expect(back.rawFiltering!.notchHz, isNull);
      expect(back.conditioning!.notchSource, 'detected');
      final flat = SessionMetadata.fromJson(back.toJson())!;
      expect(flat.conditioning!.notchHz, [50.0]);
    });

    test('saved mains per device id round-trip in settings', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await Settings.load();
      expect(settings.savedMainsFor('muse-1'), isNull);
      await settings.setSavedMains('muse-1', [50]);
      await settings.setSavedMains('crown-1', []);
      expect(settings.savedMainsFor('muse-1'), [50.0]);
      expect(settings.savedMainsFor('crown-1'), isEmpty);
      await settings.setSavedMains('muse-1', [60]);
      expect(settings.savedMainsFor('muse-1'), [60.0]);
      expect(settings.savedMainsFor(''), isNull);
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
        final out = conditionEeg(eeg: raw, conditioning: null);
        expect(out.eeg.length, raw.length);
        expect(out.conditioning.notchHz, [50.0]);
        expect(out.conditioning.notchSource, NotchSource.detected);
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
  
    test('recorded notch is used as is (no scan)', () {
      final raw = _packets(
        channels: 4,
        packetSamples: 12,
        offset: 800,
        mainsHz: 50,
        seconds: 4,
      );
      final none = EegConditioning(
        highPassHz: 0.5,
        notchQ: 10,
        notchHz: Float64List(0),
        notchSource: NotchSource.saved,
      );
      final out = conditionEeg(eeg: raw, conditioning: none);
      expect(out.conditioning.notchHz, isEmpty);
      expect(out.conditioning.notchSource, NotchSource.saved);
      final peak = out.eeg
          .where((r) => r.timestamp >= _startMs + 3000 && r.electrode == 1)
          .expand((r) => r.samples)
          .map((v) => v.abs())
          .reduce(math.max);
      expect(peak, greaterThan(50));
    });

    test('live notch: saved value seeds it, else both', () {
      setSavedMains(notchHz: Float64List.fromList([60]));
      final saved = liveEegConditioning();
      expect(saved.notchHz, [60.0]);
      expect(saved.notchSource, NotchSource.saved);
      expect(saved.notchQ, 10);
      expect(liveMainsDecision(), isNull);
      setSavedMains(notchHz: null);
      final undecided = liveEegConditioning();
      expect(undecided.notchHz, [50.0, 60.0]);
      expect(undecided.notchSource, NotchSource.undecided);
    });
  });
}
