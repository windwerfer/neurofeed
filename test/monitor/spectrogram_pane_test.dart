import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/dsp.dart';
import 'package:muse_ml/src/monitor/panes/spectrogram_pane.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

Float64List _db({int n = 129, double fill = -40, int? hotBin, double hot = 0}) {
  final db = Float64List(n);
  for (var i = 0; i < n; i++) {
    db[i] = fill;
  }
  if (hotBin != null) db[hotBin] = hot;
  return db;
}

SpectrogramPanePainter _painter({
  required List<StftColumn> columns,
  ViewportController? viewport,
  double newestElapsed = 20,
  double magMin = -40,
  double magMax = 0,
  bool connected = true,
  ui.Image? heatmap,
}) {
  return SpectrogramPanePainter(
    columns: columns,
    viewport: viewport ?? ViewportController(),
    newestElapsed: newestElapsed,
    magMin: magMin,
    magMax: magMax,
    connected: connected,
    heatmap: heatmap,
    axisColor: const Color(0xFF888888),
    gridColor: const Color(0xFF444444),
  );
}

void _expectBgra(Uint8List bytes, int offset, Color color) {
  final argb = color.toARGB32();
  expect(bytes[offset], argb & 0xFF);
  expect(bytes[offset + 1], (argb >> 8) & 0xFF);
  expect(bytes[offset + 2], (argb >> 16) & 0xFF);
  expect(bytes[offset + 3], (argb >> 24) & 0xFF);
}

void main() {
  test('shouldRepaint when columns change', () {
    final a = [StftColumn(0, _db())];
    final b = [StftColumn(0.25, _db())];
    expect(_painter(columns: b).shouldRepaint(_painter(columns: a)), isTrue);
    expect(_painter(columns: a).shouldRepaint(_painter(columns: a)), isFalse);
  });

  test('shouldRepaint when mag range changes', () {
    final cols = [StftColumn(0, _db())];
    expect(
      _painter(
        columns: cols,
        magMin: -20,
      ).shouldRepaint(_painter(columns: cols, magMin: -40)),
      isTrue,
    );
    expect(
      _painter(
        columns: cols,
        magMax: -10,
      ).shouldRepaint(_painter(columns: cols, magMax: 0)),
      isTrue,
    );
    expect(
      _painter(columns: cols).shouldRepaint(_painter(columns: cols)),
      isFalse,
    );
  });

  test(
    'shouldRepaint when newestElapsed or viewport identity fields change',
    () {
      final cols = [StftColumn(0, _db())];
      expect(
        _painter(
          columns: cols,
          newestElapsed: 21,
        ).shouldRepaint(_painter(columns: cols, newestElapsed: 20)),
        isTrue,
      );
      final inspect = ViewportController()
        ..mode = ViewportMode.inspect
        ..inspectStartElapsed = 4;
      expect(
        _painter(
          columns: cols,
          viewport: inspect,
        ).shouldRepaint(_painter(columns: cols)),
        isTrue,
      );
    },
  );

  test('empty columns do not rasterize', () {
    expect(rasterizeSpectrogramBgra(const [], magMin: -40, magMax: 0), isNull);
  });

  test('known hot bin rasterizes a non-zero pixel matching colorFor', () {
    const hotBin = 10;
    final col = StftColumn(1.0, _db(hotBin: hotBin));
    final bmp = rasterizeSpectrogramBgra([col], magMin: -40, magMax: 0);
    expect(bmp, isNotNull);
    expect(bmp!.width, 1);
    expect(bmp.height, 60);

    final hotY = bmp.height - 1 - hotBin;
    final hotOff = bmp.pixelOffset(0, hotY);
    final coldOff = bmp.pixelOffset(0, bmp.height - 1);
    expect(
      bmp.bytes[hotOff] + bmp.bytes[hotOff + 1] + bmp.bytes[hotOff + 2],
      greaterThan(0),
    );
    _expectBgra(bmp.bytes, hotOff, SpectrogramPanePainter.colorFor(1));
    _expectBgra(bmp.bytes, coldOff, SpectrogramPanePainter.colorFor(0));
    expect(
      bmp.bytes.sublist(hotOff, hotOff + 4),
      isNot(bmp.bytes.sublist(coldOff, coldOff + 4)),
    );
  });

  test('two columns rasterize width 2; magMax bin is the last stop', () {
    final cols = [
      StftColumn(0, _db(fill: -40)),
      StftColumn(0.25, _db(fill: 0)),
    ];
    final bmp = rasterizeSpectrogramBgra(cols, magMin: -40, magMax: 0)!;
    expect(bmp.width, 2);
    expect(bmp.height, 60);
    _expectBgra(
      bmp.bytes,
      bmp.pixelOffset(0, 0),
      SpectrogramPanePainter.colorFor(0),
    );
    _expectBgra(
      bmp.bytes,
      bmp.pixelOffset(1, 0),
      SpectrogramPanePainter.colorFor(1),
    );
  });
}
