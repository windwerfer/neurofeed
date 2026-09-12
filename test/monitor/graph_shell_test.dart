import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/graph_shell.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

void _portrait(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('GraphShell shows Follow/Inspect and hides Record', (
    tester,
  ) async {
    _portrait(tester);
    final viewport = ViewportController();
    addTearDown(viewport.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GraphShell(
            title: 'Raw EEG',
            viewport: viewport,
            windowOptions: ViewportController.eegWindowOptions,
            onFollow: () {},
            onInspect: () {},
            onWindowChanged: (_) {},
            body: const SizedBox.expand(child: Text('pane')),
          ),
        ),
      ),
    );
    expect(find.text('Follow'), findsOneWidget);
    expect(find.text('Inspect'), findsOneWidget);
    expect(find.text('Record'), findsNothing);
    expect(find.text('Add graph'), findsNothing);
    expect(find.text('pane'), findsOneWidget);
  });

  testWidgets('landscape cinema hides toolbar; pane stays', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewport = ViewportController();
    addTearDown(viewport.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GraphShell(
            title: 'Histogram',
            viewport: viewport,
            windowOptions: ViewportController.histogramPsdWindowOptions,
            onFollow: () {},
            onInspect: () {},
            onWindowChanged: (_) {},
            inspectRangeLabel: '0:00–0:08',
            body: const SizedBox.expand(child: Text('pane')),
          ),
        ),
      ),
    );
    expect(find.text('Follow'), findsNothing);
    expect(find.text('Inspect'), findsNothing);
    expect(find.text('pane'), findsOneWidget);
  });

  testWidgets('spectrogram window labels use min; inspect range shown', (
    tester,
  ) async {
    _portrait(tester);
    final viewport = ViewportController()
      ..windowSeconds = ViewportController.spectrogramDefaultWindowSeconds
      ..mode = ViewportMode.inspect;
    addTearDown(viewport.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GraphShell(
            title: 'Spectrogram',
            viewport: viewport,
            windowOptions: ViewportController.spectrogramWindowOptions,
            formatWindow: formatSpectrogramWindow,
            onFollow: () {},
            onInspect: () {},
            onWindowChanged: (_) {},
            inspectRangeLabel: '0:00–0:20',
            body: const SizedBox.expand(),
          ),
        ),
      ),
    );
    expect(find.text('20s'), findsOneWidget);
    expect(find.text('0:00–0:20'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<double>));
    await tester.pumpAndSettle();
    expect(find.text('2min'), findsOneWidget);
    expect(find.text('5min'), findsOneWidget);
  });

  testWidgets('custom when window is not a preset; preset restores', (
    tester,
  ) async {
    _portrait(tester);
    final viewport = ViewportController()..windowSeconds = 47;
    addTearDown(viewport.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: viewport,
            builder: (context, _) {
              return GraphShell(
                title: 'Bands',
                viewport: viewport,
                windowOptions: ViewportController.bandsWindowOptions,
                onFollow: () {},
                onInspect: () {},
                onWindowChanged: (v) =>
                    viewport.setStripWindowSeconds(v, newestElapsed: 60),
                body: const SizedBox.expand(),
              );
            },
          ),
        ),
      ),
    );
    expect(find.text('custom'), findsOneWidget);
    expect(find.text('SMOOTH'), findsNothing);
    expect(find.text('REALTIME'), findsNothing);

    await tester.tap(find.byType(DropdownButton<double>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30s').last);
    await tester.pumpAndSettle();
    expect(viewport.windowSeconds, 30);
    expect(find.text('custom'), findsNothing);
    expect(find.text('30s'), findsOneWidget);
  });

  testWidgets('Follow is disabled when followEnabled is false', (tester) async {
    _portrait(tester);
    final viewport = ViewportController()
      ..mode = ViewportMode.inspect
      ..inspectStartElapsed = 0;
    addTearDown(viewport.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GraphShell(
            title: 'Recording',
            followEnabled: false,
            viewport: viewport,
            windowOptions: ViewportController.eegWindowOptions,
            onFollow: () => viewport.mode = ViewportMode.follow,
            onInspect: () {},
            onWindowChanged: (_) {},
            body: const SizedBox.expand(),
          ),
        ),
      ),
    );
    expect(find.text('Follow'), findsOneWidget);
    expect(find.text('Inspect'), findsOneWidget);
    await tester.tap(find.text('Follow'));
    await tester.pump();
    expect(viewport.mode, ViewportMode.inspect);
  });
}
