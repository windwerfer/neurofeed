import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:muse_ml/src/charts/session_recorder.dart';
import 'package:muse_ml/src/feedback/computed_frame.dart' as dart;
import 'package:muse_ml/src/feedback/computed_sampler.dart';
import 'package:muse_ml/src/feedback/session_assembler.dart';
import 'package:muse_ml/src/feedback/session_chart_data.dart';
import 'package:muse_ml/src/feedback/session_metadata.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/rust/api/session_format.dart';
import 'package:muse_ml/src/rust/frb_generated.dart';

final String _rustLibPath =
    '${Directory.current.path}/rust/target/debug/librust_lib_muse_ml.so';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ComputedSampler t', () {
    test('t is seconds from recording start', () {
      final start = DateTime.utc(2026, 1, 1, 12);
      var now = start;
      dart.ComputedFrame? last;
      final sampler = ComputedSampler(
        onFrame: (f) => last = f,
        recordingStart: start,
        now: () => now,
      );
      now = start.add(const Duration(seconds: 2, milliseconds: 250));
      sampler.emitFrame();
      expect(last, isNotNull);
      expect(last!.t, closeTo(2.25, 0.001));
    });
  });

  group('v5 assemble + charts', () {
    setUpAll(() async {
      await RustLib.init(
        externalLibrary: ExternalLibrary.open(_rustLibPath),
      );
    });

    test('recorder flushRaw frames so sessionParseBody sees bands', () async {
      final dir = await Directory.systemTemp.createTemp('muse_rec_');
      addTearDown(() => dir.delete(recursive: true));
      final rec = SessionRecorder();
      await rec.start(dir);
      rec.writeEvent(
        MuseEventDto.bands(
          BandsDto(
            electrode: 1,
            timestamp: 500,
            delta: 1,
            theta: 2,
            alpha: 3,
            beta: 4,
            gamma: 5,
            lineNoiseRatio: 0.05,
          ),
        ),
      );
      rec.flushRaw();
      final temps = await rec.readTemps();
      expect(temps, isNotNull);
      final parsed = sessionParseBody(bytes: temps!.raw);
      expect(parsed.bands, isNotEmpty);
      await rec.stop();
    });

    test('JSONL → FFI → containerEncodeV5 → v5ExtractComputed round-trips t',
        () {
      final dartFrames = [_dartFrame(0), _dartFrame(1), _dartFrame(2)];
      final ffiFrames = dartFrames.map(toFfiFrame).toList();
      final v5 = assembleV5Container(
        thumbnail: placeholderWebP,
        metadataJson: {'protocol': 'drowsiness'},
        computedFrames: ffiFrames,
        rawBody: sessionHeaderBytes(),
      );
      final extracted = v5ExtractComputed(bytes: v5);
      expect(extracted.map((f) => f.t), [0, 1, 2]);
      expect(extracted.first.bands, hasLength(4));
      expect(extracted.first.bands[1][2], closeTo(221.0, 0.01));
    });

    test('prepareChartDataFromComputed has x and alphaRel for 4-ch frames', () {
      final frames = [
        for (var t = 0; t < 3; t++) toFfiFrame(_dartFrame(t.toDouble())),
      ];
      final prepared = prepareChartDataFromComputed(frames);
      expect(prepared.x, isNotEmpty);
      expect(prepared.alphaRel, hasLength(prepared.x.length));
      expect(prepared.x.first, 0);
    });

    test('empty thumbnail assemble does not throw; magic is MUSE5\\0', () {
      final v5 = assembleV5Container(
        thumbnail: const [],
        metadataJson: {'protocol': 'drowsiness'},
        computedFrames: const [],
        rawBody: sessionHeaderBytes(),
      );
      expect(v5.sublist(0, 6), [0x4D, 0x55, 0x53, 0x45, 0x35, 0x00]);
    });

    test('publishSession writes history not scratch; SQLite row; no summary',
        () async {
      final tmp = await Directory.systemTemp.createTemp('muse_pub_');
      addTearDown(() => tmp.delete(recursive: true));
      final storage = FileSystemSessionStorage(tmp);
      final store = SessionStore(storage: Future.value(storage));
      final meta = SessionMetadata(
        protocol: 'drowsiness',
        durationMinutes: 1,
        elapsedSeconds: 3,
        sound: 'Ambient Drone',
        savedAt: DateTime.utc(2026, 9, 2).toIso8601String(),
        music: const SessionMusic(
          trackCount: 1,
          minCutoffHz: 200,
          maxCutoffHz: 8000,
          invert: false,
          shuffle: false,
          series: [MusicCutoffSample(offsetSecs: 0, cutoffHz: 400)],
        ),
      );
      await store.publishSession(
        'abc123',
        meta,
        rawBody: sessionHeaderBytes(),
        computedFrames: [toFfiFrame(_dartFrame(0))],
      );
      final name = 'session_abc123.muse.feedback';
      expect(await storage.fileExists(name), isTrue);
      expect(tmp.path.contains('.cache'), isFalse);
      final list = await store.list();
      expect(list, hasLength(1));
      expect(list.first.id, 'abc123');
      final bytes = await store.readContainer('abc123');
      expect(bytes, isNotNull);
      final head = v5ParseHead(bytes: bytes!);
      final decoded = SessionMetadata.fromJsonBytes(head.metadataJson)!;
      expect(decoded.toJson().containsKey('summary'), isFalse);
      expect(decoded.music?.series, isNotEmpty);
      expect(decoded.music?.toJson().containsKey('buckets'), isFalse);
    });
  });
}
