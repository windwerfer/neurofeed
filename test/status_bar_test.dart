import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/monitor/device_montage.dart';
import 'package:neurofeed/src/rust/api/device_config.dart';
import 'package:neurofeed/src/status_bar.dart';

void main() {
  test('pad glyphs follow the device pad count', () {
    expect(
      signalPads(
        headCount: channelCountForKind(DeviceKind.muse),
      ).map((p) => p.glyph),
      ['/', '‾', '‾', '\\'],
    );
    expect(
      signalPads(headCount: channelCountForKind(DeviceKind.neurosity)),
      hasLength(8),
    );
  });

  test('Muse AUX dots sit between the overlines, capped at 4', () {
    final one = signalPads(headCount: 4, auxChannels: 1);
    expect(one.map((p) => p.glyph), ['/', '‾', '•', '‾', '\\']);
    expect(one.map((p) => p.electrode), [0, 1, 4, 2, 3]);

    final athena = signalPads(headCount: 4, auxChannels: 4);
    expect(athena.map((p) => p.glyph), [
      '/',
      '‾',
      '•',
      '•',
      '•',
      '•',
      '‾',
      '\\',
    ]);
    expect(athena.map((p) => p.electrode), [0, 1, 4, 5, 6, 7, 2, 3]);

    expect(
      signalPads(headCount: 4, auxChannels: 9).where((p) => p.glyph == '•'),
      hasLength(4),
    );
    expect(
      signalPads(headCount: 8, auxChannels: 4).map((p) => p.glyph),
      List.filled(8, '•'),
    );
  });

  testWidgets('Crown ring places front pads above back pads', (tester) async {
    const green = Color(0xFF4CAF50);
    const orange = Color(0xFFFF9800);
    const red = Color(0xFFF44336);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.center,
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                signalQualityRow(const [90, 90, 50, 90, 90, 10, 90, 90], 8),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final texts = tester.widgetList<Text>(find.text('•')).toList();
    expect(texts, hasLength(8));
    final marks = [
      for (final text in texts)
        (rect: tester.getRect(find.byWidget(text)), color: text.style?.color),
    ]..sort((a, b) => a.rect.center.dy.compareTo(b.rect.center.dy));
    final top = marks.take(2).toList()
      ..sort((a, b) => a.rect.center.dx.compareTo(b.rect.center.dx));
    final bottom = marks.skip(6).take(2).toList()
      ..sort((a, b) => a.rect.center.dx.compareTo(b.rect.center.dx));
    final middle = marks.skip(2).take(4).toList();
    expect(top[0].color, orange);
    expect(top[1].color, red);
    expect(bottom[0].color, green);
    expect(bottom[1].color, green);
    final midLeft = middle
        .map((mark) => mark.rect.center.dx)
        .reduce((a, b) => a < b ? a : b);
    final midRight = middle
        .map((mark) => mark.rect.center.dx)
        .reduce((a, b) => a > b ? a : b);
    expect(top[0].rect.center.dx, greaterThan(midLeft + 3));
    expect(top[1].rect.center.dx, lessThan(midRight - 3));
    expect(bottom[0].rect.center.dx, greaterThan(midLeft + 3));
    expect(bottom[1].rect.center.dx, lessThan(midRight - 3));
    expect(bottom[0].rect.center.dy, greaterThan(top[0].rect.center.dy + 8));
    final ring = tester.getSize(find.byType(Table));
    expect(ring.height, inInclusiveRange(20, 32));
    expect(ring.width, inInclusiveRange(20, 32));
  });

  testWidgets('Muse AUX dots take the AUX electrode scores', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: signalQualityRow(
          const [90, 80, 70, 60, 10, 50],
          4,
          auxChannels: 2,
        ),
      ),
    );
    final texts = tester.widgetList<Text>(find.byType(Text)).toList();
    expect(texts.map((t) => t.data), ['/', '‾', '•', '•', '‾', '\\']);
    expect(texts[2].style?.color, const Color(0xFFF44336));
    expect(texts[3].style?.color, const Color(0xFFFF9800));
    expect(texts[0].style?.color, const Color(0xFF4CAF50));
    expect(texts[4].style?.color, const Color(0xFFFF9800));
  });
}
