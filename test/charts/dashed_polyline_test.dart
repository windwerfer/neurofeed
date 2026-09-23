import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/charts/dashed_polyline.dart';

void main() {
  test('continuous phase on dense hold leaves gaps', () {
    // 30× 2px segments = 60px path — old code restarted dash each segment.
    final parts = dashedIntervals(60, dash: 6, gap: 4);
    final gapLen = parts
        .where((p) => !p.draw)
        .fold<double>(0, (a, p) => a + p.length);
    final drawLen = parts
        .where((p) => p.draw)
        .fold<double>(0, (a, p) => a + p.length);
    expect(gapLen, greaterThan(15));
    expect(drawLen, greaterThan(15));
    expect(gapLen + drawLen, closeTo(60, 1e-9));
  });

  test('two-point collapsed hold still gets continuous dash gaps', () {
    // Collapsed 1→3 span is a single long segment (e.g. 100px).
    final parts = dashedIntervals(100, dash: 6, gap: 4);
    final gapLen = parts
        .where((p) => !p.draw)
        .fold<double>(0, (a, p) => a + p.length);
    expect(parts.length, greaterThan(2));
    expect(gapLen, greaterThan(30));
    expect(parts.first.draw, isTrue);
  });
}
