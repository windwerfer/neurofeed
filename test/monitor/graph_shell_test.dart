import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/graph_shell.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

void main() {
  testWidgets('GraphShell shows Follow/Inspect and hides Record', (
    tester,
  ) async {
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

  testWidgets('custom when window is not a preset; preset restores', (
    tester,
  ) async {
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
}
