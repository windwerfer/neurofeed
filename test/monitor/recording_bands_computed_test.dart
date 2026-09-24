import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/monitor/panes/time_series_pane.dart';
import 'package:neurofeed/src/monitor/views/recording_dashboard.dart';
import 'package:neurofeed/src/rust/api/session_format.dart';
import 'package:neurofeed/src/rust/frb_generated.dart';
import 'package:neurofeed/src/session_format/computed_frame.dart' as dart;
import 'package:neurofeed/src/spine/assemble.dart';

final String _rustLibPath =
    '${Directory.current.path}/rust/target/debug/librust_lib_neurofeed.so';

ComputedFrame _ffiFrame(double t, List<List<double>> bands) {
  return ComputedFrame(
    t: t,
    bands: [for (final b in bands) Float32List.fromList(b)],
    lineNoise: Float32List(bands.length),
    signalQuality: Uint8List(bands.length),
    guardrail: const GuardrailInfo(
      sleepDir: 0,
      clarity: 0,
      warning: false,
      delta: 0,
    ),
    feedback: const FeedbackInfo(
      ratio: 0,
      threshold: 0,
      inTarget: false,
      pct: 0,
    ),
    gestures: const [],
  );
}

dart.ComputedFrame _dartFrame(double t) {
  return dart.ComputedFrame(
    t: t,
    bands: [
      for (var e = 0; e < 4; e++)
        [100.0 + e, 80.0 + e, 220.0 + e, 50.0 + e, 30.0 + e],
    ],
    pulse: 70 + t,
    movement: 0.05,
    peakAlpha: dart.PeakAlphaInfo(freq: 10.0, power: 100.0 + t),
    spo2: 98.0,
    lineNoise: const [0.05, 0.04, 0.06, 0.05],
    signalQuality: const [80, 85, 90, 75],
    guardrail: const dart.GuardrailInfo(
      sleepDir: 0.3,
      clarity: 0.8,
      warning: false,
      delta: 100.0,
    ),
    feedback: const dart.FeedbackInfo(
      ratio: 1.5,
      threshold: 1.2,
      inTarget: true,
      pct: 0.6,
    ),
    gestures: const [],
  );
}

void main() {
  test('bandSeriesFromComputed averages selected electrodes in dB', () {
    final frames = [
      _ffiFrame(1.0, [
        [100, 100, 100, 100, 100],
        [10000, 10000, 10000, 10000, 10000],
      ]),
      _ffiFrame(2.0, [
        [100, 100, 100, 100, 100],
        [10000, 10000, 10000, 10000, 10000],
      ]),
    ];
    final series = bandSeriesFromComputed(
      frames: frames,
      electrodes: const [0],
      startElapsed: 0,
      endElapsed: 10,
    );
    expect(series.length, 5);
    expect(series[0].length, 2);
    expect(series[0][0].elapsed, closeTo(1.0, 1e-9));
    expect(series[0][0].db, closeTo(linearToDb(100), 1e-6));
    expect(series[0][1].db, closeTo(linearToDb(100), 1e-6));

    final both = bandSeriesFromComputed(
      frames: frames,
      electrodes: const [0, 1],
      startElapsed: 0,
      endElapsed: 10,
    );
    final expected = (linearToDb(100) + linearToDb(10000)) / 2;
    expect(both[2][0].db, closeTo(expected, 1e-6));
  });

  test('bandSeriesFromComputed skips frames outside window', () {
    final frames = [
      _ffiFrame(0.0, [
        [100, 100, 100, 100, 100],
      ]),
      _ffiFrame(50.0, [
        [100, 100, 100, 100, 100],
      ]),
    ];
    final series = bandSeriesFromComputed(
      frames: frames,
      electrodes: const [0],
      startElapsed: 40,
      endElapsed: 60,
    );
    expect(series[0].length, 1);
    expect(series[0][0].elapsed, closeTo(50.0, 1e-9));
  });

  test('open with computed present + data null → Bands from frames', () {
    final frames = [
      _ffiFrame(1.0, [
        [100, 100, 100, 100, 100],
        [100, 100, 100, 100, 100],
        [100, 100, 100, 100, 100],
        [100, 100, 100, 100, 100],
      ]),
      _ffiFrame(2.0, [
        [200, 200, 200, 200, 200],
        [200, 200, 200, 200, 200],
        [200, 200, 200, 200, 200],
        [200, 200, 200, 200, 200],
      ]),
    ];
    // History first paint: frames loaded, raw SessionData still null.
    const SessionData? data = null;
    final series = recordingBandSeries(
      frames: frames,
      rawBands: data?.bands ?? const [],
      electrodes: const [0, 1, 2, 3],
      startElapsed: 0,
      endElapsed: 30,
      originMs: 0,
    );
    expect(series.length, 5);
    expect(series[0], isNotEmpty);
    expect(series[0].length, 2);
    expect(series[2][0].db, closeTo(linearToDb(100), 1e-6));
  });

  test('Bands must not depend on visiting EEG when computed exists', () {
    final frames = [
      _ffiFrame(5.0, [
        [1000, 1000, 1000, 1000, 1000],
      ]),
    ];
    final withoutRaw = recordingBandSeries(
      frames: frames,
      rawBands: const [],
      electrodes: const [0],
      startElapsed: 0,
      endElapsed: 30,
      originMs: 0,
    );
    final withRawIgnored = recordingBandSeries(
      frames: frames,
      rawBands: const [
        BandsRecord(
          timestamp: 5000,
          electrode: 0,
          delta: 1,
          theta: 1,
          alpha: 1,
          beta: 1,
          gamma: 1,
        ),
      ],
      electrodes: const [0],
      startElapsed: 0,
      endElapsed: 30,
      originMs: 0,
    );
    expect(withoutRaw[0], isNotEmpty);
    expect(withRawIgnored[0].single.db, withoutRaw[0].single.db);
    expect(withoutRaw[0].single.db, closeTo(linearToDb(1000), 1e-6));

    final empty = recordingBandSeries(
      frames: const [],
      rawBands: const [],
      electrodes: const [0],
      startElapsed: 0,
      endElapsed: 30,
      originMs: 0,
    );
    expect(empty[0], isEmpty);
  });

  group('camelCase computed JSONL extract (live recording wire)', () {
    setUpAll(() async {
      await RustLib.init(externalLibrary: ExternalLibrary.open(_rustLibPath));
    });

    test('Dart toJsonBytes → assemble → extractComputed keeps bands',
        () async {
      final dir = await Directory.systemTemp.createTemp('nf_bands_hist_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      // Live writers emit camelCase JSONL (not Rust serde snake_case).
      final jsonl = BytesBuilder();
      for (var t = 0; t < 3; t++) {
        jsonl.add(_dartFrame(t.toDouble()).toJsonBytes());
        jsonl.addByte(0x0a);
      }

      final file = await writeScratch(
        dir: dir,
        id: 'bands_hist',
        prefix: 'recording',
        metadataJson: const {'kind': 'recording'},
        computedJsonl: jsonl.toBytes(),
        rawBody: sessionHeaderBytes(),
      );

      final frames = await extractComputedFromPath(path: file.path);
      expect(frames, hasLength(3));
      expect(frames.first.bands, hasLength(4));
      expect(frames.first.bands[0][2], closeTo(220.0, 0.01));
      expect(frames.first.lineNoise, hasLength(4));
      expect(frames.first.feedback.inTarget, isTrue);

      // Prefix-only extract (History Bands-first open path).
      final bytes = await file.readAsBytes();
      final header = parseHeader(bytes: bytes);
      final prefix = bytes.sublist(0, header.rawOffset.toInt());
      final fromPrefix = extractComputed(bytes: prefix);
      expect(fromPrefix, hasLength(3));

      final series = recordingBandSeries(
        frames: fromPrefix,
        rawBands: const [],
        electrodes: const [0, 1, 2, 3],
        startElapsed: 0,
        endElapsed: 30,
        originMs: 0,
      );
      expect(series[2], isNotEmpty);
    });

    test('Dart camelCase keys match wire contract', () {
      final json = jsonDecode(utf8.decode(_dartFrame(1).toJsonBytes()))
          as Map<String, dynamic>;
      expect(json.containsKey('lineNoise'), isTrue);
      expect(json.containsKey('signalQuality'), isTrue);
      expect(json.containsKey('peakAlpha'), isTrue);
      expect((json['guardrail'] as Map).containsKey('sleepDir'), isTrue);
      expect((json['feedback'] as Map).containsKey('inTarget'), isTrue);
      expect(json.containsKey('line_noise'), isFalse);
    });
  });
}
