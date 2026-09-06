import 'package:muse_ml/src/rust/api/features.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

/// Native-value range and synthetic-baseline window for one feature id.
class FeatureOverrideRange {
  const FeatureOverrideRange({
    required this.min,
    required this.max,
    required this.seedLow,
    required this.seedHigh,
    required this.initial,
  });

  final double min;
  final double max;
  final double seedLow;
  final double seedHigh;
  final double initial;
}

/// Debug latch: replace [FeatureDto.value] for selected ids before the bus
/// and lanes see the event. Does not invent ticks; live 1 Hz cadence stays.
class FeatureOverride {
  static const int baselineSampleCount = 21;

  bool enabled = false;
  final Map<String, double> _values = {};

  Map<String, double> get values => Map.unmodifiable(_values);

  double? valueOf(String id) => _values[id];

  static FeatureOverrideRange rangeFor(String id) {
    switch (id) {
      case 'band.atr':
      case 'band.tar':
      case 'band.btr':
        return const FeatureOverrideRange(
          min: 0,
          max: 3,
          seedLow: 0.2,
          seedHigh: 0.6,
          initial: 0.4,
        );
      case 'band.delta':
        return const FeatureOverrideRange(
          min: 0,
          max: 1,
          seedLow: 0.05,
          seedHigh: 0.15,
          initial: 0.10,
        );
      default:
        return const FeatureOverrideRange(
          min: 0,
          max: 1,
          seedLow: 0.2,
          seedHigh: 0.4,
          initial: 0.3,
        );
    }
  }

  static double initial(String id) => rangeFor(id).initial;

  static List<double> baselineSamples(String id) {
    final r = rangeFor(id);
    const n = baselineSampleCount;
    return [
      for (var i = 0; i < n; i++)
        r.seedLow + (r.seedHigh - r.seedLow) * i / (n - 1),
    ];
  }

  void set(String id, double? value) {
    if (value == null) {
      _values.remove(id);
      return;
    }
    final r = rangeFor(id);
    _values[id] = value.clamp(r.min, r.max).toDouble();
  }

  void setIfAbsent(String id) {
    _values.putIfAbsent(id, () => initial(id));
  }

  void clear() {
    enabled = false;
    _values.clear();
  }

  MuseEventDto apply(MuseEventDto event) {
    if (!enabled) {
      return event;
    }
    if (event is! MuseEventDto_Feature) {
      return event;
    }
    final dto = event.field0;
    final v = _values[dto.id];
    if (v == null) {
      return event;
    }
    return MuseEventDto.feature(
      FeatureDto(id: dto.id, timestamp: dto.timestamp, value: v),
    );
  }
}
