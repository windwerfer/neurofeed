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

Float64List _nanDb({int n = 129}) {
  final db = Float64List(n);
  for (var i = 0; i < n; i++) {
    db[i] = double.nan;
  }
  return db;
}

SpectrogramPanePainter _painter({
  ViewportController? viewport,
  double newestElapsed = 20,
  double wallNow = 0,
  double magMin = -40,
  double magMax = 0,
  bool connected = true,
  ui.Image? heatmap,
  double? heatFirstElapsed,
  double? heatHopSec,
  int? heatColumnCount,
}) {
  return SpectrogramPanePainter(
    viewport: viewport ?? ViewportController(),
    newestElapsed: newestElapsed,
    wallNow: wallNow,
    magMin: magMin,
    magMax: magMax,
    connected: connected,
    heatmap: heatmap,
    heatFirstElapsed: heatFirstElapsed,
    heatHopSec: heatHopSec,
    heatColumnCount: heatColumnCount,
    axisColor: const Color(0xFF888888),
    gridColor: const Color(0xFF444444),
    chartBackground: const Color(0xFF121212),
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
  test('shouldRepaint when heat geometry changes', () {
    expect(
      _painter(heatFirstElapsed: 1).shouldRepaint(_painter(heatFirstElapsed: 0)),
      isTrue,
    );
    expect(
      _painter(heatHopSec: 0.5).shouldRepaint(_painter(heatHopSec: 0.25)),
      isTrue,
    );
    expect(
      _painter(heatColumnCount: 2).shouldRepaint(_painter(heatColumnCount: 1)),
      isTrue,
    );
    expect(_painter().shouldRepaint(_painter()), isFalse);
  });

  test('shouldRepaint when mag range changes', () {
    expect(
      _painter(magMin: -20).shouldRepaint(_painter(magMin: -40)),
      isTrue,
    );
    expect(
      _painter(magMax: -10).shouldRepaint(_painter(magMax: 0)),
      isTrue,
    );
    expect(_painter().shouldRepaint(_painter()), isFalse);
  });

  test('shouldRepaint when wallNow changes', () {
    expect(
      _painter(wallNow: 1).shouldRepaint(_painter(wallNow: 0)),
      isTrue,
    );
  });

  test(
    'shouldRepaint when newestElapsed or viewport identity fields change',
    () {
      expect(
        _painter(newestElapsed: 21).shouldRepaint(_painter(newestElapsed: 20)),
        isTrue,
      );
      final inspect = ViewportController()
        ..mode = ViewportMode.inspect
        ..inspectStartElapsed = 4;
      expect(
        _painter(viewport: inspect).shouldRepaint(_painter()),
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

  test('NaN / empty STFT bins rasterize transparent (not colormap blue)', () {
    final cols = [
      StftColumn(0, _nanDb()),
      StftColumn(0.25, _db(fill: 0)),
    ];
    final bmp = rasterizeSpectrogramBgra(cols, magMin: -40, magMax: 0)!;
    expect(bmp.width, 2);
    // Empty column stays fully transparent (surface shows through).
    final emptyOff = bmp.pixelOffset(0, 0);
    expect(bmp.bytes.sublist(emptyOff, emptyOff + 4), [0, 0, 0, 0]);
    // Signal column still maps magMax to the last colormap stop.
    _expectBgra(
      bmp.bytes,
      bmp.pixelOffset(1, 0),
      SpectrogramPanePainter.colorFor(1),
    );
  });

  test('stftColumns marks all-NaN windows as empty db', () {
    final n = kDefaultFftN;
    final samples = Float64List(n * 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = double.nan;
    }
    final cols = stftColumns(samples, startElapsed: 0);
    expect(cols, isNotEmpty);
    for (final c in cols) {
      expect(c.db.every((v) => v.isNaN), isTrue);
    }
  });
}
