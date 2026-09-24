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
