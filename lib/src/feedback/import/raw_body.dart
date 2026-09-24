import 'dart:typed_data';

import 'package:neurofeed/src/rust/api/muse.dart';
import 'package:neurofeed/src/rust/api/session_format.dart';

/// Muse-native EEG packet size used when packing continuous samples.
const int kEegPacketSamples = 12;

/// Absolute Muse band powers for one electrode at one instant (Bels).
class BandValues {
  const BandValues({
    required this.delta,
    required this.theta,
    required this.alpha,
    required this.beta,
    required this.gamma,
  });
  final double delta;
  final double theta;
  final double alpha;
  final double beta;
  final double gamma;
}

/// One timestamped set of per-electrode bands.
class BandInstant {
  const BandInstant({required this.timestampMs, required this.byElectrode});
  final double timestampMs;
  final Map<int, BandValues> byElectrode;
}

/// Build a framed raw body (header + one zstd frame) from encoded event bytes.
Uint8List assembleRawBody(List<int> encodedEvents) {
  final header = sessionHeaderBytes();
  if (encodedEvents.isEmpty) {
    return header;
  }
  final frame = sessionFrameBytes(data: encodedEvents);
  final out = Uint8List(header.length + frame.length);
  out.setAll(0, header);
  out.setAll(header.length, frame);
  return out;
}

/// Pack continuous per-electrode µV samples into Muse-shaped EEG packets.
///
/// [samplesByElectrode] keys are electrode indices. Timestamps are ms from
/// recording start. [sampleRateHz] drives packet spacing.
List<int> encodeEegPackets({
  required Map<int, List<double>> samplesByElectrode,
  required double sampleRateHz,
  int packetSamples = kEegPacketSamples,
}) {
  final rate = sampleRateHz <= 0 ? 256.0 : sampleRateHz;
  final events = <int>[];
  final electrodes = samplesByElectrode.keys.toList()..sort();
  for (final el in electrodes) {
    final samples = samplesByElectrode[el]!;
    if (samples.isEmpty) continue;
    var index = 0;
    for (var i = 0; i < samples.length; i += packetSamples) {
      final end = i + packetSamples > samples.length
          ? samples.length
          : i + packetSamples;
      final chunk = samples.sublist(i, end);
      final tsMs = (i / rate) * 1000.0;
      events.addAll(
        encodeSessionEvent(
          event: MuseEventDto.eeg(
            EegDto(
              index: index,
              electrode: el,
              timestamp: tsMs,
              samples: Float64List.fromList(chunk),
            ),
          ),
        ),
      );
      index++;
    }
  }
  return events;
}

/// Encode absolute band rows (Bels) as raw `bands` tags.
List<int> encodeBandEvents(List<BandInstant> rows) {
  final events = <int>[];
  for (final row in rows) {
    for (final e in row.byElectrode.entries) {
      final b = e.value;
      events.addAll(
        encodeSessionEvent(
          event: MuseEventDto.bands(
            BandsDto(
              electrode: e.key,
              timestamp: row.timestampMs,
              delta: b.delta,
              theta: b.theta,
              alpha: b.alpha,
              beta: b.beta,
              gamma: b.gamma,
              lineNoiseRatio: 0,
            ),
          ),
        ),
      );
    }
  }
  return events;
}

/// Muse-ish PPG samples per packet (simulator / Classic).
const int kPpgPacketSamples = 6;

/// One XYZ sample at [timestampMs] (recording-relative).
class ImuSample {
  const ImuSample({
    required this.timestampMs,
    required this.x,
    required this.y,
    required this.z,
  });
  final double timestampMs;
  final double x;
  final double y;
  final double z;
}

/// Encode accelerometer samples as Muse raw tag 3 (one sample per event).
///
/// Note: [encodeSessionEvent] for IMU stamps wall-clock `now` (live-capture
/// quirk); relative [ImuSample.timestampMs] is not on the wire today.
List<int> encodeAccelerometerEvents(List<ImuSample> samples) {
  final events = <int>[];
  for (var i = 0; i < samples.length; i++) {
    final s = samples[i];
    events.addAll(
      encodeSessionEvent(
        event: MuseEventDto.accelerometer(
          ImuDto(
            sequenceId: i & 0xffff,
            samples: [XyzDto(x: s.x, y: s.y, z: s.z)],
          ),
        ),
      ),
    );
  }
  return events;
}

/// Encode gyroscope samples as Muse raw tag 4.
List<int> encodeGyroscopeEvents(List<ImuSample> samples) {
  final events = <int>[];
  for (var i = 0; i < samples.length; i++) {
    final s = samples[i];
    events.addAll(
      encodeSessionEvent(
        event: MuseEventDto.gyroscope(
          ImuDto(
            sequenceId: i & 0xffff,
            samples: [XyzDto(x: s.x, y: s.y, z: s.z)],
          ),
        ),
      ),
    );
  }
  return events;
}

/// Pack continuous per-channel PPG samples into Muse-shaped PPG packets.
List<int> encodePpgPackets({
  required Map<int, List<double>> samplesByChannel,
  required List<double> timestampsMs,
  int packetSamples = kPpgPacketSamples,
}) {
  final events = <int>[];
  final channels = samplesByChannel.keys.toList()..sort();
  for (final ch in channels) {
    final samples = samplesByChannel[ch]!;
    if (samples.isEmpty) continue;
    var index = 0;
    for (var i = 0; i < samples.length; i += packetSamples) {
      final end = i + packetSamples > samples.length
          ? samples.length
          : i + packetSamples;
      final chunk = samples.sublist(i, end);
      final tsMs = i < timestampsMs.length
          ? timestampsMs[i]
          : (timestampsMs.isEmpty ? 0.0 : timestampsMs.last);
      events.addAll(
        encodeSessionEvent(
          event: MuseEventDto.ppg(
            PpgDto(
              index: index,
              channel: ch,
              timestamp: tsMs,
              samples: Float64List.fromList(chunk),
            ),
          ),
        ),
      );
      index++;
    }
  }
  return events;
}
