import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/panes/bands_context_strip.dart';
import 'package:muse_ml/src/monitor/panes/time_series_pane.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

void _portrait(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('Histogram/PSD split is 70/30 flex, not a user setting', () {
    expect(kHistogramPsdPrimaryFlex, 7);
    expect(kBandsContextStripFlex, 3);
    expect(kHistogramPsdPrimaryFlex + kBandsContextStripFlex, 10);
  });

  testWidgets('HistogramPsdSplit is Column + two Expanded panes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          height: 1000,
          child: HistogramPsdSplit(
            key: Key('split'),
            primary: SizedBox.expand(child: Text('primary')),
            strip: SizedBox.expand(child: Text('strip')),
          ),
        ),
      ),
    );
    expect(find.text('primary'), findsOneWidget);
    expect(find.text('strip'), findsOneWidget);
    final column = tester.widget<Column>(
      find.descendant(
        of: find.byKey(const Key('split')),
        matching: find.byType(Column),
      ),
    );
    expect(column.children, hasLength(2));
    expect((column.children[0] as Expanded).flex, kHistogramPsdPrimaryFlex);
    expect((column.children[1] as Expanded).flex, kBandsContextStripFlex);
  });

  testWidgets('BandsContextStrip reuses TimeSeriesPane and 30s window', (
    tester,
  ) async {
    _portrait(tester);
    final strip = ViewportController()
      ..windowSeconds = ViewportController.bandsDefaultWindowSeconds;
    final epoch = ViewportController()
      ..windowSeconds = ViewportController.histogramDefaultWindowSeconds;
    addTearDown(strip.dispose);
    addTearDown(epoch.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: BandsContextStrip(
              stripViewport: strip,
              epochViewport: epoch,
              series: const [],
              stripNewestElapsed: 40,
              stripOldestElapsed: 0,
              highlightStartElapsed: 32,
              highlightEndElapsed: 40,
              connected: false,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(TimeSeriesPane), findsOneWidget);
    expect(find.byKey(const ValueKey('bands-context-window')), findsOneWidget);
    expect(find.text('30s'), findsOneWidget);
    expect(find.text('8s'), findsNothing);
  });

  testWidgets('landscape cinema hides strip window dropdown', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final strip = ViewportController()
      ..windowSeconds = ViewportController.bandsDefaultWindowSeconds;
    final epoch = ViewportController()..windowSeconds = 8;
    addTearDown(strip.dispose);
    addTearDown(epoch.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BandsContextStrip(
            stripViewport: strip,
            epochViewport: epoch,
            series: const [],
            stripNewestElapsed: 40,
            stripOldestElapsed: 0,
            highlightStartElapsed: 32,
            highlightEndElapsed: 40,
            connected: false,
          ),
        ),
      ),
    );
    expect(find.byType(TimeSeriesPane), findsOneWidget);
    expect(find.byKey(const ValueKey('bands-context-window')), findsNothing);
  });
}
