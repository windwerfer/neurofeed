import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/device_montage.dart';
import 'package:muse_ml/src/monitor/electrode_toggles.dart';
import 'package:muse_ml/src/rust/api/device_config.dart';

void main() {
  test('default all on; last one stays', () {
    var selected = allElectrodeIndices(4);
    expect(selected, {0, 1, 2, 3});
    selected = toggleAverageElectrode(selected, 0);
    selected = toggleAverageElectrode(selected, 1);
    selected = toggleAverageElectrode(selected, 2);
    expect(selected, {3});
    selected = toggleAverageElectrode(selected, 3);
    expect(selected, {3});
    selected = toggleAverageElectrode(selected, 0);
    expect(selected, {0, 3});
  });

  test('Muse-4 vs Crown-8 labels from lastConnectedKind', () {
    expect(electrodeNamesForKind(DeviceKind.muse), kMuseElectrodeNames);
    expect(electrodeNamesForKind(DeviceKind.neurosity), kCrownElectrodeNames);
    expect(allElectrodeIndices(4), hasLength(4));
    expect(allElectrodeIndices(8), hasLength(8));
  });

  testWidgets('toggles show Muse names; last chip stays depressed', (
    tester,
  ) async {
    var selected = allElectrodeIndices(4);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return ElectrodeToggles(
                names: kMuseElectrodeNames,
                selected: selected,
                onToggle: (i) => setState(() {
                  selected = toggleAverageElectrode(selected, i);
                }),
              );
            },
          ),
        ),
      ),
    );
    expect(find.text('TP9'), findsOneWidget);
    expect(find.text('AF7'), findsOneWidget);
    expect(find.text('AF8'), findsOneWidget);
    expect(find.text('TP10'), findsOneWidget);

    await tester.tap(find.text('TP9'));
    await tester.pump();
    await tester.tap(find.text('AF7'));
    await tester.pump();
    await tester.tap(find.text('AF8'));
    await tester.pump();
    expect(selected, {3});
    await tester.tap(find.text('TP10'));
    await tester.pump();
    expect(selected, {3});
  });

  testWidgets('Crown-8 labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ElectrodeToggles(
            names: kCrownElectrodeNames,
            selected: allElectrodeIndices(8),
            onToggle: (_) {},
          ),
        ),
      ),
    );
    for (final n in kCrownElectrodeNames) {
      expect(find.text(n), findsOneWidget);
    }
  });
}
