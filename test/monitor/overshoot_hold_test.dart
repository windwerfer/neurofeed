import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/monitor/panes/overshoot_hold.dart';

void main() {
  test('value above Y-max does not feed auto scale', () {
    expect(kBandsOvershootHold, isTrue);
    final scaled = overshootScaleValues([10, 20, 100], currentMax: 25).toList();
    expect(scaled, [10, 20]);
  });

  test('null currentMax includes all finite values', () {
    final scaled = overshootScaleValues([10, double.nan, 100]).toList();
    expect(scaled, [10, 100]);
  });

  test('overshoot paints dashed at last in-range Y', () {
    final hold = overshootPaintY(value: 100, yMax: 25, lastInRangeY: 20);
    expect(hold.y, 20);
    expect(hold.dashed, isTrue);

    final inRange = overshootPaintY(value: 18, yMax: 25, lastInRangeY: 20);
    expect(inRange.y, 18);
    expect(inRange.dashed, isFalse);
  });

  test('unusable holds last good Y even when value in range', () {
    final hold = overshootPaintY(
      value: 18,
      yMax: 25,
      lastInRangeY: 20,
      unusable: true,
    );
    expect(hold.y, 20);
    expect(hold.dashed, isTrue);
  });

  test('unusable plus overshoot stays dashed at last good Y', () {
    final hold = overshootPaintY(
      value: 100,
      yMax: 25,
      lastInRangeY: 12,
      unusable: true,
    );
    expect(hold.y, 12);
    expect(hold.dashed, isTrue);
  });

  group('buildOvershootPaintRuns joins', () {
    test('solid→dashed does not append first hold into solid', () {
      // Points: good @10, good @12, unusable spike @99, unusable @50,
      // then two goods so resume solid flushes (≥2 pts).
      final runs = buildOvershootPaintRuns(
        const [
          (elapsed: 1.0, value: 10, unusable: false),
          (elapsed: 2.0, value: 12, unusable: false),
          (elapsed: 3.0, value: 99, unusable: true),
          (elapsed: 4.0, value: 50, unusable: true),
          (elapsed: 5.0, value: 14, unusable: false),
          (elapsed: 6.0, value: 15, unusable: false),
        ],
        yMax: 40,
        fallbackLastInRangeY: 40,
      );

      expect(runs, hasLength(3));
      expect(runs[0].dashed, isFalse);
      // Solid ends at last good (t=2, y=12) — no horizontal stub to t=3.
      expect(runs[0].points.last.elapsed, 2.0);
      expect(runs[0].points.last.y, 12);
      expect(runs[0].points.map((p) => p.elapsed), [1.0, 2.0]);
      // First hold must not appear in any solid run.
      for (final r in runs.where((r) => !r.dashed)) {
        expect(r.points.any((p) => p.elapsed == 3.0), isFalse);
      }
    });

    test('hold collapses to one dashed horizontal from last good through last hold',
        () {
      final runs = buildOvershootPaintRuns(
        const [
          (elapsed: 1.0, value: 10, unusable: false),
          (elapsed: 2.0, value: 12, unusable: false),
          (elapsed: 3.0, value: 99, unusable: true),
          (elapsed: 3.5, value: 80, unusable: true),
          (elapsed: 4.0, value: 50, unusable: true),
          (elapsed: 5.0, value: 14, unusable: false),
        ],
        yMax: 40,
        fallbackLastInRangeY: 40,
      );

      final dashed = runs.where((r) => r.dashed).toList();
      expect(dashed, hasLength(1));
      expect(dashed.single.points, hasLength(2));
      // Seeded at last good (t=2,y=12) → last hold (t=4,y=12).
      expect(dashed.single.points.first.elapsed, 2.0);
      expect(dashed.single.points.first.y, 12);
      expect(dashed.single.points.last.elapsed, 4.0);
      expect(dashed.single.points.last.y, 12);
      // Intermediate spike samples are not vertices.
      expect(
        dashed.single.points.map((p) => p.elapsed).toList(),
        [2.0, 4.0],
      );
    });

    test('dashed→solid resumes at live Y without dashed diagonal', () {
      final runs = buildOvershootPaintRuns(
        const [
          (elapsed: 1.0, value: 10, unusable: false),
          (elapsed: 2.0, value: 12, unusable: false),
          (elapsed: 3.0, value: 99, unusable: true),
          (elapsed: 4.0, value: 50, unusable: true),
          (elapsed: 5.0, value: 14, unusable: false),
          (elapsed: 6.0, value: 15, unusable: false),
        ],
        yMax: 40,
        fallbackLastInRangeY: 40,
      );

      expect(runs, hasLength(3));
      final dashed = runs[1];
      expect(dashed.dashed, isTrue);
      // Dashed must not include resume (t=5, y=14).
      expect(dashed.points.any((p) => p.elapsed == 5.0), isFalse);
      expect(dashed.points.every((p) => p.y == 12), isTrue);

      final resume = runs[2];
      expect(resume.dashed, isFalse);
      expect(resume.points.first.elapsed, 5.0);
      expect(resume.points.first.y, 14);
      expect(resume.points.map((p) => p.y), [14, 15]);
    });

    test('pure overshoot (not unusable) also collapses horizontally', () {
      final runs = buildOvershootPaintRuns(
        const [
          (elapsed: 1.0, value: 10, unusable: false),
          (elapsed: 2.0, value: 20, unusable: false),
          (elapsed: 3.0, value: 100, unusable: false), // overshoot
          (elapsed: 4.0, value: 90, unusable: false), // overshoot
          (elapsed: 5.0, value: 18, unusable: false),
        ],
        yMax: 25,
        fallbackLastInRangeY: 25,
      );

      final dashed = runs.where((r) => r.dashed).single;
      expect(dashed.points, hasLength(2));
      expect(dashed.points.first, (elapsed: 2.0, y: 20));
      expect(dashed.points.last, (elapsed: 4.0, y: 20));
    });
  });
}
