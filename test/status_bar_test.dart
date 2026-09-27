import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/monitor/device_montage.dart';
import 'package:neurofeed/src/rust/api/device_config.dart';
import 'package:neurofeed/src/status_bar.dart';

void main() {
  test('pad glyphs follow the device pad count', () {
    expect(padSymbols(channelCountForKind(DeviceKind.muse)), [
      '/',
      '‾',
      '‾',
      '\\',
    ]);
    expect(padSymbols(channelCountForKind(DeviceKind.neurosity)), hasLength(8));
  });

  testWidgets('Crown shows 8 pads coloured by quality', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: signalQualityRow(const [90, 90, 50, 90, 90, 10, 90, 90], 8),
      ),
    );
    final texts = tester.widgetList<Text>(find.byType(Text)).toList();
    expect(texts, hasLength(8));
    expect(texts[2].style?.color, const Color(0xFFFF9800));
    expect(texts[5].style?.color, const Color(0xFFF44336));
    expect(texts[7].style?.color, const Color(0xFF4CAF50));
  });
}
