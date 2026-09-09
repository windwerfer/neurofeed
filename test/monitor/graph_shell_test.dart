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
}
