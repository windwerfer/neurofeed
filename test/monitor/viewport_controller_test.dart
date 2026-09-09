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
}
