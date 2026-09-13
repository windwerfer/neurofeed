import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/charts/band_style.dart';
import 'package:muse_ml/src/monitor/band_toggles.dart';

void main() {
  test('default all on; last one stays', () {
    var selected = allBandIndices();
    expect(selected, {0, 1, 2, 3, 4});
    selected = toggleVisibleBand(selected, 0);
    selected = toggleVisibleBand(selected, 1);
    selected = toggleVisibleBand(selected, 2);
    selected = toggleVisibleBand(selected, 3);
    expect(selected, {4});
    selected = toggleVisibleBand(selected, 4);
    expect(selected, {4});
    selected = toggleVisibleBand(selected, 0);
    expect(selected, {0, 4});
  });

  test('isBandVisible is all when null', () {
    expect(isBandVisible(2, null), isTrue);
    expect(isBandVisible(2, {0, 2}), isTrue);
    expect(isBandVisible(1, {0, 2}), isFalse);
  });

  testWidgets('tap padding of a chip toggles; last chip stays depressed', (
    tester,
  ) async {
    var selected = allBandIndices();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return BandToggles(
                selected: selected,
                onToggle: (i) => setState(() {
                  selected = toggleVisibleBand(selected, i);
                }),
              );
            },
          ),
        ),
      ),
    );
    for (final n in bandNames) {
      expect(find.text(n), findsOneWidget);
    }

    final delta = tester.getRect(
      find.byKey(const ValueKey('band-toggle-delta')),
    );
    await tester.tapAt(Offset(delta.left + 3, delta.center.dy));
    await tester.pump();
    expect(selected.contains(0), isFalse);

    for (final name in ['theta', 'alpha', 'beta']) {
      await tester.tap(find.byKey(ValueKey('band-toggle-$name')));
      await tester.pump();
    }
    expect(selected, {4});

    final gamma = tester.getRect(
      find.byKey(const ValueKey('band-toggle-gamma')),
    );
    await tester.tapAt(Offset(gamma.left + 3, gamma.center.dy));
    await tester.pump();
    expect(selected, {4});
  });
}
