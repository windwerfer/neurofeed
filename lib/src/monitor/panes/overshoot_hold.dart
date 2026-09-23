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

/// One flushed polyline for Bands overshoot/unusable painting.
class OvershootPaintRun {
  const OvershootPaintRun({required this.dashed, required this.points});

  final bool dashed;
  final List<({double elapsed, double y})> points;
}

/// Partition samples into solid/dashed paint runs with polished joins:
/// - solid→dashed: solid ends at last good; dashed seeds from that point
/// - dashed hold collapses to two horizontal endpoints at last-good Y
/// - dashed→solid: dashed ends at last hold; solid starts at resume (no
///   diagonal into live Y)
List<OvershootPaintRun> buildOvershootPaintRuns(
  Iterable<({double elapsed, double value, bool unusable})> samples, {
  required double yMax,
  double fallbackLastInRangeY = 0,
}) {
  final runs = <OvershootPaintRun>[];
  var lastInRange = fallbackLastInRangeY;
  var haveInRange = false;
  final solid = <({double elapsed, double y})>[];
  final dashed = <({double elapsed, double y})>[];
  var prevDashed = false;

  void flushSolid() {
    if (solid.length >= 2) {
      runs.add(OvershootPaintRun(dashed: false, points: List.of(solid)));
    }
    solid.clear();
  }

  void flushDashed() {
    if (dashed.length >= 2) {
      runs.add(OvershootPaintRun(dashed: true, points: List.of(dashed)));
    }
    dashed.clear();
  }

  for (final s in samples) {
    final hold = overshootPaintY(
      value: s.value,
      yMax: yMax,
      lastInRangeY: haveInRange ? lastInRange : fallbackLastInRangeY,
      unusable: s.unusable,
    );
    if (!hold.dashed) {
      lastInRange = s.value;
      haveInRange = true;
    }
    final o = (elapsed: s.elapsed, y: hold.y);

    if (hold.dashed != prevDashed &&
        (solid.isNotEmpty || dashed.isNotEmpty)) {
      if (prevDashed) {
        // dashed → solid: do not append resume into dashed.
        flushDashed();
      } else {
        // solid → dashed: flush solid at last good only; seed dashed.
        final seed = solid.isNotEmpty ? solid.last : null;
        flushSolid();
        if (seed != null) dashed.add(seed);
      }
    }

    if (hold.dashed) {
      // Collapse a consecutive hold to two endpoints (one horizontal span).
      if (dashed.length >= 2) {
        dashed[dashed.length - 1] = o;
      } else {
        dashed.add(o);
      }
    } else {
      solid.add(o);
    }
    prevDashed = hold.dashed;
  }
  flushSolid();
  flushDashed();
  return runs;
}
