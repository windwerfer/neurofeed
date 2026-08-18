import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/streaming/streaming_models.dart';

/// One emitted sample row of a sensor group (all channels at one timestep).
@immutable
class GroupSample {
  const GroupSample(this.groupId, this.timestamp, this.values);

  final String groupId;

  /// Seconds since epoch of the first sample in the row (device clock).
  final double timestamp;

  /// Channel values, length == group channel count.
  final List<double> values;
}

/// Common interface for network stream senders (OSC, LSL, …).
abstract interface class StreamSender {
  int get packetsSent;
  int get bytesSent;

  void push(GroupSample sample);

  Future<void> stop();
}

/// Per-channel sample queues recombined into lockstep rows. Each group's
/// channels are fed by separate events (one per electrode / optical channel /
/// accel vs gyro); a row is emitted only when every channel has a sample,
/// so the streams stay sample-aligned.
class GroupMixer {
  GroupMixer(this.def);

  final StreamGroupDef def;
  final List<List<double>> _samples = [];
  final List<List<double>> _timestamps = [];

  /// Total samples dropped because a channel queue overflowed (a lead/lag
  /// between channels — logged by the caller).
  int droppedSamples = 0;
  double _lastDropLog = 0;

  void reset() {
    _samples
      ..clear()
      ..addAll(List.generate(def.channelCount, (_) => <double>[]));
    _timestamps
      ..clear()
      ..addAll(List.generate(def.channelCount, (_) => <double>[]));
    droppedSamples = 0;
  }

  void add(int channel, double timestamp, List<double> samples) {
    if (channel < 0 || channel >= def.channelCount || samples.isEmpty) return;
    final q = _samples[channel];
    if (q.length + samples.length > maxQueuedPerChannel) {
      final drop = min(q.length, samples.length);
      q.removeRange(0, drop);
      _timestamps[channel].removeRange(0, drop);
      droppedSamples += drop;
      if (timestamp - _lastDropLog > 5) {
        _lastDropLog = timestamp;
        debugPrint('[streaming] ${def.id} ch$channel dropped samples '
            '(arrival lead/lag)');
      }
    }
    q.addAll(samples);
    final perSample = def.nominalRate > 0 ? 1.0 / def.nominalRate : 0.0;
    final ts = _timestamps[channel];
    for (var i = 0; i < samples.length; i++) {
      ts.add(timestamp - (samples.length - 1 - i) * perSample);
    }
  }

  /// Emits complete rows, oldest first. Returns at most [limit] rows.
  List<GroupSample> drain(int limit) {
    final out = <GroupSample>[];
    while (out.length < limit) {
      if (!_samples.every((q) => q.isNotEmpty)) break;
      final values = <double>[];
      double ts = 0;
      for (var c = 0; c < def.channelCount; c++) {
        values.add(_samples[c].removeAt(0));
        ts = _timestamps[c].removeAt(0);
      }
      out.add(GroupSample(def.id, ts, values));
    }
    return out;
  }

  /// Latest buffered timestamp of any channel, or 0 when all queues are empty.
  double get lastTimestamp {
    var maxTs = 0.0;
    for (final q in _timestamps) {
      if (q.isNotEmpty && q.last > maxTs) maxTs = q.last;
    }
    return maxTs;
  }

  static const maxQueuedPerChannel = 128;
}