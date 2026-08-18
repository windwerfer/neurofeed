import 'dart:async';

import 'package:liblsl/lsl.dart';
import 'package:muse_ml/src/streaming/streaming_mixer.dart';
import 'package:muse_ml/src/streaming/streaming_models.dart';

/// Streams sensor groups as LSL outlets (one outlet per group), discoverable
/// by LSL clients (LabRecorder, OpenViBE, …) on the local network. liblsl
/// assigns timestamps at push time; channel labels are attached as metadata.
class LslStreamer implements StreamSender {
  LslStreamer(this.config);

  final StreamingConfig config;

  final Map<String, LSLStreamInfoWithMetadata> _infos = {};
  final Map<String, LSLOutlet> _outlets = {};

  @override
  int packetsSent = 0;

  @override
  int bytesSent = 0;

  Future<void> start(String deviceName) async {
    for (final group in config.groups) {
      if (_outlets.containsKey(group.id)) continue;
      final info = await LSL.createStreamInfo(
        streamName: streamNameOf(group),
        streamType: _contentType(group),
        channelCount: group.channelCount,
        sampleRate: group.nominalRate,
        channelFormat: LSLChannelFormat.float32,
        sourceId: '${streamNameOf(group)}.$deviceName',
      );
      final channels = info.description.value.addChildElement('channels');
      for (final name in group.channelNames) {
        final ch = channels.addChildElement('channel');
        ch.addChildValue('label', name);
        ch.addChildValue('unit', 'µV');
      }
      final outlet = await LSL.createOutlet(
        streamInfo: info,
        chunkSize: 0,
        maxBuffer: maxBufferSeconds,
        useIsolates: false,
      );
      _infos[group.id] = info;
      _outlets[group.id] = outlet;
    }
  }

  @override
  void push(GroupSample sample) {
    final outlet = _outlets[sample.groupId];
    if (outlet == null) return;
    outlet.pushSampleSync(sample.values);
    packetsSent++;
    bytesSent += 4 * sample.values.length;
  }

  @override
  Future<void> stop() async {
    for (final outlet in _outlets.values) {
      outlet.destroy();
    }
    _outlets.clear();
    for (final info in _infos.values) {
      info.destroy();
    }
    _infos.clear();
  }

  String streamNameOf(StreamGroupDef group) => '${config.prefix}${group.name}';

  LSLContentType _contentType(StreamGroupDef group) => switch (group.id) {
    'eeg' => LSLContentType.eeg,
    'ppg' => LSLContentType.custom('PPG'),
    'imu' => LSLContentType.custom('IMU'),
    'bands' => LSLContentType.custom('Bands'),
    _ => LSLContentType.markers,
  };

  /// Seconds of buffered samples before old ones are dropped; a live stream
  /// needs only a small jitter buffer.
  static const maxBufferSeconds = 5;
}