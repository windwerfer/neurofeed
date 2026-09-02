import 'dart:async';

import 'package:muse_ml/src/rust/api/muse.dart';

/// One subscribed-feature sample from [MuseEventDto.Feature].
class FeatureSample {
  const FeatureSample({required this.id, required this.t, required this.value});

  final String id;

  /// Milliseconds epoch, same convention as [FeatureDto.timestamp].
  final double t;

  /// Native feature value. Never coerced from a missing sample.
  final double value;
}

/// Fan-out of [MuseEventDto.Feature] to per-id streams.
class FeatureBus {
  final Map<String, StreamController<FeatureSample>> _controllers = {};
  final Map<String, FeatureSample> _latest = {};

  /// Live samples for [id]. Broadcast; a late subscriber does not replay.
  Stream<FeatureSample> of(String id) => _controllerFor(id).stream;

  FeatureSample? latest(String id) => _latest[id];

  /// No-op for non-Feature events. Missing ticks are not published as 0.
  void publish(MuseEventDto event) {
    if (event is! MuseEventDto_Feature) {
      return;
    }
    final dto = event.field0;
    final sample = FeatureSample(
      id: dto.id,
      t: dto.timestamp,
      value: dto.value,
    );
    _latest[dto.id] = sample;
    final controller = _controllers[dto.id];
    if (controller != null && !controller.isClosed) {
      controller.add(sample);
    }
  }

  StreamController<FeatureSample> _controllerFor(String id) {
    return _controllers.putIfAbsent(
      id,
      () => StreamController<FeatureSample>.broadcast(sync: true),
    );
  }

  void reset() {
    _latest.clear();
  }

  void dispose() {
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
    _latest.clear();
  }
}
