import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';
import 'package:muse_ml/src/monitor/device_montage.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';
import 'package:muse_ml/src/rust/api/device_config.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:shared_preferences/shared_preferences.dart';

EegDto _eeg(int electrode, List<double> samples, {double ts = 0}) => EegDto(
  index: 0,
  electrode: electrode,
  timestamp: ts,
  samples: Float64List.fromList(samples),
);

void main() {
  test('default window is 2560 samples / 10 s', () {
    final v = ViewportController();
    expect(v.windowSeconds, 10);
    expect(v.windowSamples, 2560);
    expect(ViewportController.defaultWindowSamples, 2560);
  });

  test('Muse-4 vs Crown-8 montage from lastConnectedKind', () {
    expect(electrodeNamesForKind(null), kMuseElectrodeNames);
    expect(electrodeNamesForKind(DeviceKind.muse), hasLength(4));
    expect(channelCountForKind(DeviceKind.muse), 4);
    expect(electrodeNamesForKind(DeviceKind.neurosity), kCrownElectrodeNames);
    expect(channelCountForKind(DeviceKind.neurosity), 8);
  });

  test('Follow wipe advances dispPos; Inspect freeze stops wrap', () {
    final buf = SweepBuffer();
    buf.setDisplayWindow(10);
    buf.append(_eeg(0, List<double>.filled(15, 1)));
    expect(buf.frozen, isFalse);
    expect(buf.cursor, 15);

    final v = ViewportController()..windowSeconds = 10 / SweepBuffer.sampleRate;
    expect(v.windowSamples, 10);
    v.enterInspectFromSweep(buf, newestElapsed: 15 / SweepBuffer.sampleRate);
    expect(v.mode, ViewportMode.inspect);
    expect(buf.frozen, isTrue);
    expect(buf.cursor, 5);

    buf.append(_eeg(0, List<double>.filled(3, 2)));
    expect(buf.cursor, 8);
    expect(buf.displaySample(0, 5), 2);
    expect(buf.displaySample(0, 7), 2);

    buf.append(_eeg(0, List<double>.filled(20, 3)));
    expect(buf.cursor, 10);
    expect(buf.frozen, isTrue);

    v.follow(buf);
    expect(v.mode, ViewportMode.follow);
    expect(buf.frozen, isFalse);
    buf.append(_eeg(0, [4]));
    expect(buf.cursor, greaterThan(10));
  });

  test('no eeg_layout_* writes', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('eeg_layout_')), isEmpty);
  });

  test('Inspect older than 5 min RAM calls FileBackedSource', () {
    var calls = 0;
    final hit = inspectFileRange<String>(
      startElapsed: 10,
      endElapsed: 20,
      ramCount: 300 * 256,
      ramNewestElapsed: 600,
      captureStartedAtMs: 1,
      getRange: (a, b) {
        calls++;
        expect(a, 10);
        expect(b, 20);
        return 'file';
      },
    );
    expect(hit, 'file');
    expect(calls, 1);

    calls = 0;
    final ram = inspectFileRange<String>(
      startElapsed: 500,
      endElapsed: 510,
      ramCount: 300 * 256,
      ramNewestElapsed: 600,
      captureStartedAtMs: 1,
      getRange: (a, b) {
        calls++;
        return 'file';
      },
    );
    expect(ram, isNull);
    expect(calls, 0);
  });

  test('null captureStartedAtMs never uses file-backed', () {
    var calls = 0;
    final hit = inspectFileRange<String>(
      startElapsed: 0,
      endElapsed: 10,
      ramCount: 0,
      ramNewestElapsed: 10,
      captureStartedAtMs: null,
      getRange: (a, b) {
        calls++;
        return 'file';
      },
    );
    expect(hit, isNull);
    expect(calls, 0);
  });

  test('formatElapsed is m:ss', () {
    expect(formatElapsed(0), '0:00');
    expect(formatElapsed(65), '1:05');
    expect(formatElapsed(3601), '1:00:01');
  });

  test('elapsedTicks space out by width', () {
    final wide = elapsedTicks(start: 0, end: 10, widthPx: 800);
    final narrow = elapsedTicks(start: 0, end: 10, widthPx: 200);
    expect(wide.length, greaterThan(narrow.length));
    expect(wide.first, greaterThanOrEqualTo(0));
    expect(wide.last, lessThanOrEqualTo(10));
  });

  test('histogram/PSD/spectrogram window presets', () {
    expect(ViewportController.histogramDefaultWindowSeconds, 8);
    expect(ViewportController.psdDefaultWindowSeconds, 4);
    expect(ViewportController.histogramPsdWindowOptions, [2, 4, 8]);
    expect(ViewportController.spectrogramDefaultWindowSeconds, 20);
    expect(ViewportController.spectrogramWindowOptions, [10, 20, 30, 120, 300]);
    expect(formatSpectrogramWindow(20), '20s');
    expect(formatSpectrogramWindow(120), '2min');
    expect(formatSpectrogramWindow(300), '5min');
    expect(
      windowIsPreset(8, ViewportController.histogramPsdWindowOptions),
      isTrue,
    );
    expect(
      windowIsPreset(7, ViewportController.histogramPsdWindowOptions),
      isFalse,
    );
  });

  test('spectrogram pinchX cap is 5 min', () {
    final v = ViewportController()
      ..windowSeconds = ViewportController.spectrogramDefaultWindowSeconds;
    v.pinchX(
      scaleFromStart: 0.01,
      windowAtStart: 20,
      focalElapsed: 100,
      focalFraction: 0.5,
      newestElapsed: 400,
      elapsedCap: 400,
      zoomFloor: ViewportController.spectrogramZoomFloor,
      zoomCap: ViewportController.spectrogramZoomCap,
    );
    expect(v.windowSeconds, ViewportController.spectrogramZoomCap);
  });

  test('bands default window is 30 s with 15/30/60/120 presets', () {
    expect(ViewportController.bandsDefaultWindowSeconds, 30);
    expect(ViewportController.bandsWindowOptions, [15, 30, 60, 120]);
    final v = ViewportController()
      ..windowSeconds = ViewportController.bandsDefaultWindowSeconds;
    expect(v.windowSeconds, 30);
    expect(windowIsPreset(30, ViewportController.bandsWindowOptions), isTrue);
    expect(windowIsPreset(47, ViewportController.bandsWindowOptions), isFalse);
  });

  test('pinchX sets a custom window; preset restore; Follow keeps length', () {
    final v = ViewportController()
      ..windowSeconds = ViewportController.bandsDefaultWindowSeconds;
    v.pinchX(
      scaleFromStart: 30 / 47,
      windowAtStart: 30,
      focalElapsed: 40,
      focalFraction: 0.5,
      newestElapsed: 80,
      elapsedCap: 80,
    );
    expect(v.mode, ViewportMode.inspect);
    expect(v.windowSeconds, closeTo(47, 0.05));
    expect(
      windowIsPreset(v.windowSeconds, ViewportController.bandsWindowOptions),
      isFalse,
    );

    v.setStripWindowSeconds(30, newestElapsed: 80);
    expect(v.windowSeconds, 30);
    expect(
      windowIsPreset(v.windowSeconds, ViewportController.bandsWindowOptions),
      isTrue,
    );
    expect(v.mode, ViewportMode.inspect);

    v.windowSeconds = 47;
    v.followStrip();
    expect(v.mode, ViewportMode.follow);
    expect(v.windowSeconds, 47);
  });

  test('alignEpochToContext right-aligns T on the strip window', () {
    final epoch = ViewportController()..windowSeconds = 8;
    final context = ViewportController()..windowSeconds = 30;
    context.enterInspectStrip(newestElapsed: 80);
    expect(context.stripVisibleStart(newestElapsed: 80), closeTo(50, 1e-9));
    alignEpochToContext(
      epoch: epoch,
      context: context,
      contextNewestElapsed: 80,
    );
    expect(epoch.mode, ViewportMode.inspect);
    expect(epoch.stripVisibleStart(newestElapsed: 80), closeTo(72, 1e-9));
    expect(epoch.stripVisibleEnd(newestElapsed: 80), closeTo(80, 1e-9));
    expect(epoch.windowSeconds, 8);

    context.followStrip();
    alignEpochToContext(
      epoch: epoch,
      context: context,
      contextNewestElapsed: 80,
    );
    expect(epoch.mode, ViewportMode.follow);
  });

  test('bandsContextZoomFloor is max(5 s, T); context covers epoch T', () {
    expect(bandsContextZoomFloor(2), ViewportController.bandsZoomFloor);
    expect(bandsContextZoomFloor(8), 8);
    expect(bandsContextZoomFloor(4), ViewportController.bandsZoomFloor);

    final context = ViewportController()..windowSeconds = 5;
    ensureContextCoversEpoch(
      context: context,
      epochSeconds: 8,
      newestElapsed: 40,
    );
    expect(context.windowSeconds, 8);
    ensureContextCoversEpoch(
      context: context,
      epochSeconds: 4,
      newestElapsed: 40,
    );
    expect(context.windowSeconds, 8);
  });

  test('pinchX zoom floor is 5 s and cap is min(elapsed, 1800)', () {
    final v = ViewportController()..windowSeconds = 30;
    v.pinchX(
      scaleFromStart: 100,
      windowAtStart: 30,
      focalElapsed: 20,
      focalFraction: 0.5,
      newestElapsed: 40,
      elapsedCap: 40,
    );
    expect(v.windowSeconds, ViewportController.bandsZoomFloor);

    v.pinchX(
      scaleFromStart: 0.01,
      windowAtStart: 30,
      focalElapsed: 20,
      focalFraction: 0.5,
      newestElapsed: 100,
      elapsedCap: 100,
    );
    expect(v.windowSeconds, 100);

    v.pinchX(
      scaleFromStart: 0.01,
      windowAtStart: 30,
      focalElapsed: 20,
      focalFraction: 0.5,
      newestElapsed: 2000,
      elapsedCap: 2000,
    );
    expect(v.windowSeconds, ViewportController.bandsZoomCap);
  });
}
