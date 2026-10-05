import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/trust/trust_viewport.dart';
import 'package:neurofeed/src/history/history_trust_viewport.dart';

void main() {
  test('default window ends at the last sample and is 75 s', () {
    final viewport = HistoryTrustViewport()..anchorTo(180);
    expect(viewport.windowSeconds, 75);
    expect(viewport.visibleEnd(180), 180);
    expect(viewport.visibleStart(180), closeTo(105, 1e-9));
    expect(viewport.visibleEnd(0, wallNow: 1), 180);
  });

  test('drag moves the start', () {
    final viewport = HistoryTrustViewport()..anchorTo(200);
    final start = viewport.visibleStart(200);
    final end = viewport.visibleEnd(200);
    viewport.dragBy(dx: 40, plotWidth: 200);
    expect(viewport.visibleStart(200), lessThan(start));
    expect(viewport.visibleEnd(200), lessThan(end));
    expect(
      viewport.visibleEnd(200) - viewport.visibleStart(200),
      closeTo(75, 1e-9),
    );
  });

  test('pinch and zoom clamp to 15–300', () {
    final viewport = HistoryTrustViewport()..anchorTo(500);
    viewport.pinch(scaleFromStart: 0.2, windowAtStart: 75);
    expect(viewport.windowSeconds, 300);
    expect(viewport.visibleEnd(500), 500);

    viewport.pinch(scaleFromStart: 1000, windowAtStart: viewport.windowSeconds);
    expect(viewport.windowSeconds, 15);
    expect(viewport.visibleEnd(500), 500);

    viewport.zoomBy(100);
    expect(viewport.windowSeconds, 300);
    viewport.zoomBy(0.001);
    expect(viewport.windowSeconds, 15);
    expect(viewport.visibleEnd(500, wallNow: 1e9), 500);
  });

  test('a live TrustViewport is not involved', () {
    final viewport = HistoryTrustViewport()..anchorTo(180);
    expect(viewport, isA<HistoryTrustViewport>());
    expect(viewport, isNot(isA<TrustViewport>()));
    expect(viewport.rightEdgeIsNow, isFalse);
    expect(viewport.visibleEnd(180, wallNow: 0), 180);
    expect(viewport.visibleEnd(180, wallNow: 1e9), 180);
    expect(viewport.visibleEnd(180), isNot(179));
  });
}
