import 'dart:ui';

import 'package:neurofeed/src/charts/dashed_polyline.dart';

export 'package:neurofeed/src/charts/dashed_polyline.dart' show paintDashedPolyline;

const kBandsOvershootHold = true;

Iterable<double> overshootScaleValues(
  Iterable<double> values, {
  double? currentMax,
}) sync* {
  for (final v in values) {
    if (!v.isFinite) continue;
    if (kBandsOvershootHold && currentMax != null && v > currentMax) {
      continue;
    }
    yield v;
  }
}

/// Paint Y for a band sample. Dashed when sticky [unusable] (bad quality)
/// **or** overshoot (value above current [yMax]). Sticky-unusable always
/// holds last good Y; pure overshoot can become solid again if yMax grows.
({double y, bool dashed}) overshootPaintY({
  required double value,
  required double yMax,
  required double lastInRangeY,
  bool unusable = false,
}) {
  if (unusable || (kBandsOvershootHold && value > yMax)) {
    return (y: lastInRangeY, dashed: true);
  }
  return (y: value, dashed: false);
}
