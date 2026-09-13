import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';
import 'package:muse_ml/src/monitor/dsp.dart';
import 'package:muse_ml/src/monitor/graph_shell.dart';
import 'package:muse_ml/src/monitor/panes/histogram_pane.dart';
import 'package:muse_ml/src/monitor/panes/psd_pane.dart';
import 'package:muse_ml/src/monitor/panes/spectrogram_pane.dart';
import 'package:muse_ml/src/monitor/panes/sweep_pane.dart';
import 'package:muse_ml/src/monitor/panes/time_series_pane.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

void _portrait(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _boundaryOf(Type pane) => find.descendant(
  of: find.byType(pane),
  matching: find.byType(RepaintBoundary),
);

void main() {
  testWidgets('plot ListenableBuilder does not rebuild GraphShell', (
    tester,
  ) async {
    _portrait(tester);
    final plot = ValueNotifier(0);
    addTearDown(plot.dispose);
    final viewport = ViewportController();
    addTearDown(viewport.dispose);
    var shellBuilds = 0;
    var plotBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              shellBuilds++;
              return GraphShell(
                title: 'Histogram',
                viewport: viewport,
                windowOptions: ViewportController.histogramPsdWindowOptions,
                onFollow: () {},
                onInspect: () {},
                onWindowChanged: (_) {},
                body: ListenableBuilder(
                  listenable: plot,
                  builder: (context, _) {
                    plotBuilds++;
                    return Text('plot-$plotBuilds');
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(find.text('Follow'), findsOneWidget);
    final shells = shellBuilds;
    final plots = plotBuilds;
    plot.value++;
    await tester.pump();
    expect(shellBuilds, shells);
    expect(plotBuilds, plots + 1);
    expect(find.text('Follow'), findsOneWidget);
  });

  testWidgets('SweepPane wraps the plot in RepaintBoundary', (tester) async {
    _portrait(tester);
    final viewport = ViewportController();
    addTearDown(viewport.dispose);
    final buffer = SweepBuffer()..setDisplayWindow(viewport.windowSamples);
    addTearDown(buffer.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 200,
          child: SweepPane(
            electrode: 0,
            label: 'AF7',
            buffer: buffer,
            viewport: viewport,
            yScale: SharedYScale(),
            showXAxis: true,
            traceColor: const Color(0xFFFFFFFF),
            wipeColor: const Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
    expect(_boundaryOf(SweepPane), findsOneWidget);
  });

  testWidgets('TimeSeriesPane wraps the plot in RepaintBoundary', (
    tester,
  ) async {
    _portrait(tester);
    final viewport = ViewportController();
    addTearDown(viewport.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 200,
          child: TimeSeriesPane(
            series: const [],
            viewport: viewport,
            newestElapsed: 0,
            connected: false,
          ),
        ),
      ),
    );
    expect(_boundaryOf(TimeSeriesPane), findsOneWidget);
  });

  testWidgets('HistogramPane wraps the plot in RepaintBoundary', (
    tester,
  ) async {
    _portrait(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 200,
          child: HistogramPane(
            counts: List<int>.filled(kHistogramBins, 0),
            halfRange: 100,
            connected: false,
          ),
        ),
      ),
    );
    expect(_boundaryOf(HistogramPane), findsOneWidget);
  });

  testWidgets('PsdPane wraps the plot in RepaintBoundary', (tester) async {
    _portrait(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 400,
          height: 200,
          child: PsdPane(spectrum: null, maxHz: 60, connected: false),
        ),
      ),
    );
    expect(_boundaryOf(PsdPane), findsOneWidget);
  });

  testWidgets('SpectrogramPane wraps the plot in RepaintBoundary', (
    tester,
  ) async {
    _portrait(tester);
    final viewport = ViewportController();
    addTearDown(viewport.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 200,
          child: SpectrogramPane(
            columns: const [],
            viewport: viewport,
            newestElapsed: 0,
            magMin: -40,
            magMax: 0,
            connected: false,
          ),
        ),
      ),
    );
    expect(_boundaryOf(SpectrogramPane), findsOneWidget);
  });
}
