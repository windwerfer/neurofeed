import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/freeform_insets.dart';

void main() {
  test('leaves a normal status-bar inset alone', () {
    const size = Size(393, 628);
    const insets = EdgeInsets.only(top: 40, bottom: 24);
    expect(clampBrokenFreeformInsets(insets, size), insets);
  });

  test('drops a caption inset that equals the window height', () {
    const size = Size(393, 628);
    expect(
      clampBrokenFreeformInsets(const EdgeInsets.only(top: 628), size),
      EdgeInsets.zero,
    );
  });

  test('drops only the absurd edge', () {
    const size = Size(393, 628);
    expect(
      clampBrokenFreeformInsets(
        const EdgeInsets.only(top: 628, bottom: 16),
        size,
      ),
      const EdgeInsets.only(bottom: 16),
    );
  });

  testWidgets(
    'SafeArea keeps the shell when freeform padding fills the window',
    (tester) async {
      const size = Size(393, 628);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: EdgeInsets.only(top: 628),
            viewPadding: EdgeInsets.only(top: 628),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: FreeformInsetClamp(
              child: SafeArea(child: SizedBox.expand(key: Key('shell'))),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byKey(const Key('shell'))).height,
        size.height,
      );
    },
  );
}
