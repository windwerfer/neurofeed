import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/session_export.dart';
import 'package:muse_ml/src/feedback/session_metadata.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/rust/api/session_format.dart'
    show
        ComputedFrame,
        FeedbackInfo,
        GuardrailInfo,
        PeakAlphaInfo,
        containerEncodeV5,
        sessionHeaderBytes,
        sessionFrameBytes,
        encodeSessionEvent;
import 'package:muse_ml/src/rust/frb_generated.dart';

/// Load the host build of the Rust lib so FFI calls work under `flutter test`.
/// Build it with `cargo build --manifest-path rust/Cargo.toml`.
final String _rustLibPath =
    '${Directory.current.path}/rust/target/debug/librust_lib_muse_ml.so';

/// A minimal valid WebP thumbnail (1x1 transparent).
const _webp1x1 = [
  0x52, 0x49, 0x46, 0x46, 0x1A, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50,
  0x56, 0x50, 0x38, 0x58, 0x0A, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00,
  0x2F, 0xFF, 0xF0, 0x0E, 0x10, 0x00, 0x00, 0x00, 0x1C, 0x00, 0x00, 0x00,
  0x30, 0x30, 0x31, 0x20, 0x00, 0x00, 0x00, 0x13, 0x04, 0x40, 0x9D, 0x01,
  0x2A, 0x01, 0x00, 0x03, 0x13, 0x1F, 0x03,
];

/// Build a v5 container with test data: 3 seconds of bands + EEG + computed frames.
Uint8List _buildV5Container({
  required Map<String, dynamic> metadataJson,
  required List<ComputedFrame> computedFrames,
}) {
  // Build raw body (v4 format): session header + 3 seconds of events
  final events = <int>[];
  for (var s = 0; s < 3; s++) {
    for (var e = 0; e < 4; e++) {
      final t = s * 1000 + 500.0;
      events.addAll(
        encodeSessionEvent(
          event: MuseEventDto.bands(
            BandsDto(
              electrode: e,
              timestamp: t,
              delta: 100 + e * 100 + s + 1,
              theta: 200 + e * 100 + s + 1,
              alpha: 300 + e * 100 + s + 1,
              beta: 400 + e * 100 + s + 1,
              gamma: 500 + e * 100 + s + 1,
              lineNoiseRatio: 0.05,
            ),
          ),
        ),
      );
    }
    final eeg = Float64List(256);
    for (var i = 0; i < 256; i++) {
      eeg[i] = i * 0.5;
    }
    events.addAll(
      encodeSessionEvent(
        event: MuseEventDto.eeg(
          EegDto(
            index: s,
            electrode: 1,
            timestamp: s * 1000.0,
            samples: eeg,
          ),
        ),
      ),
    );
  }
  final rawBody = Uint8List.fromList([
    ...sessionHeaderBytes(),
    ...sessionFrameBytes(data: events),
  ]);

  // Encode metadata JSON to bytes
  final metadataBytes = utf8.encode(jsonEncode(metadataJson));

  // Assemble v5 container using Rust FFI
  return containerEncodeV5(
    thumbnail: _webp1x1,
    metadataJson: metadataBytes,
    computedFrames: computedFrames,
    rawBody: rawBody,
  );
}

/// Create test metadata with optional calibration and drowsiness data.
SessionMetadata _metadata({
  bool withCalibration = false,
  bool withDrowsiness = false,
  bool withMusic = false,
  bool withGestures = false,
}) {
  final now = DateTime.utc(2026, 8, 19, 10, 30);
  final meta = SessionMetadata(
    protocol: ProtocolType.drowsiness,
    durationMinutes: 15,
    elapsedSeconds: 3,
    sound: 'Bowl Chimes',
    savedAt: now.toIso8601String(),
    recordedChannels: const ['TP9', 'AF7', 'AF8', 'TP10'],
    recordedData: const ['eeg', 'bands', 'pulse', 'movement'],
    sessionSettings: SessionSettings(
      dynamicAdapt: true,
      responsiveness: 0.5,
      baselinePercentile: 40,
      guardrailEnabled: true,
      guardrailEngine: 'lunaLarge',
      warningThresholdPercentile: 75,
      warningSound: 'softBowl',
      musicFolder: null,
      musicMinCutoffHz: 200,
      musicMaxCutoffHz: 8000,
      musicInvert: false,
      musicShuffle: false,
       binauralPresetId: '',
       binauralCarrierHz: 200,
       binauralBeatHz: 10,
       backgroundBinauralPresetId: '',
       backgroundBinauralCarrierHz: 200,
       backgroundBinauralBeatHz: 4,
       markersInFeedbackEnabled: true,
      eyeMarkersEnabled: false,
    ),
    calibration: withCalibration
        ? SessionCalibration(
            version: 2,
            kind: 'single',
            calibrationId: 'eyes-closed-01',
            calibrationJson: {'test': 'data'},
            calibrationStartSecs: 0,
            calibrationEndSecs: 5,
            trainingStartSecs: 5,
            usedStartAnyway: false,
            greenStableSeconds: 3,
            faultyPadSeconds: 20,
            baseline: SessionBaselineStats(
              percentile: 40,
              count: 100,
              mean: 1.5,
              stddev: 0.3,
              floor: 1.0,
              ceiling: 2.0,
            ),
            phases: [
              SessionCalibrationPhase(
                name: 'Intro',
                durationSecs: 5,
                sampleCount: 0,
                clipFile: 'assets/audio/calibration/test.opus',
                spokenText: 'Test intro',
                eyes: 'closed',
                kind: 'intro',
                startSecs: 0,
                endSecs: 5,
              ),
              SessionCalibrationPhase(
                name: 'Baseline',
                durationSecs: 90,
                sampleCount: 900,
                eyes: 'closed',
                startSecs: 5,
                endSecs: 95,
              ),
            ],
            recalibrations: [],
          )
        : null,
    drowsiness: withDrowsiness
        ? SessionDrowsiness(
            scoreTotalPct: 15.0,
            meanSleepDir: 0.3,
            threshold: 0.5,
            series: [
              for (var i = 0; i < 3; i++)
                DrowsinessSample(
                  offsetSecs: i.toDouble(),
                  sleepDir: 0.2 + i * 0.1,
                  delta: 100 + i * 10,
                  warning: i == 2,
                ),
            ],
            buckets: [],
            bucketWidthSecs: 0,
          )
        : null,
    music: withMusic
        ? SessionMusic(
            trackCount: 2,
            minCutoffHz: 200,
            maxCutoffHz: 8000,
            invert: false,
            shuffle: false,
            tracks: [
              MusicTrackMarker(offsetSecs: 0, name: 'Track 1'),
              MusicTrackMarker(offsetSecs: 90, name: 'Track 2'),
            ],
            series: [
              for (var i = 0; i < 3; i++)
                MusicCutoffSample(offsetSecs: i.toDouble(), cutoffHz: 200 + i * 100),
            ],
            buckets: [],
            bucketWidthSecs: 0,
          )
        : null,
    gestures: withGestures
        ? <GestureMarker>[
            GestureMarker(type: GestureType.doubleBlink, offsetSeconds: 1),
            GestureMarker(type: GestureType.doubleClench, offsetSeconds: 2),
            GestureMarker(type: GestureType.eyeUp, offsetSeconds: 3),
          ]
        : const [],
  );
  return meta;
}

/// Create test computed frames for a 3-second session (FFI format).
List<ComputedFrame> _buildComputedFrames() {
  final frames = <ComputedFrame>[];
  for (var s = 0; s < 3; s++) {
    // Bands: 4 electrodes x 5 bands each = 20 floats per frame
    final bands = Float32List(20);
    for (var i = 0; i < 20; i++) {
      bands[i] = 100.0 + i * 10.0 + s;
    }
    frames.add(ComputedFrame(
      t: (s * 1000 + 500).toDouble(),
      bands: [bands],
      pulse: 70.0 + s,
      movement: 0.1,
      peakAlpha: PeakAlphaInfo(freq: 10.0, power: 100.0),
      spo2: 98.0,
      lineNoise: Float32List.fromList([0.05, 0.04, 0.06, 0.05]),
      signalQuality: Uint8List.fromList([80, 85, 90, 75]),
      guardrail: GuardrailInfo(
        sleepDir: 0.3,
        clarity: 0.8,
        warning: false,
        delta: 100.0,
      ),
      feedback: FeedbackInfo(
        ratio: 1.5 + s * 0.1,
        threshold: 1.2,
        inTarget: true,
        pct: 0.6,
      ),
      gestures: s == 1 ? ['blink'] : [],
    ));
  }
  return frames;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late SessionStorage storage;
  late SessionStore store;
  const id = 'abc12345';

  setUpAll(() async {
    await RustLib.init(externalLibrary: ExternalLibrary.open(_rustLibPath));
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('muse_export_test');
    storage = FileSystemSessionStorage(tmp);
    store = SessionStore(storage: Future.value(storage));

    // Build raw body (v4 format): session header + 3 seconds of events
    final events = <int>[];
    for (var s = 0; s < 3; s++) {
      for (var e = 0; e < 4; e++) {
        final t = s * 1000 + 500.0;
        events.addAll(
          encodeSessionEvent(
            event: MuseEventDto.bands(
              BandsDto(
                electrode: e,
                timestamp: t,
                delta: 100 + e * 100 + s + 1,
                theta: 200 + e * 100 + s + 1,
                alpha: 300 + e * 100 + s + 1,
                beta: 400 + e * 100 + s + 1,
                gamma: 500 + e * 100 + s + 1,
                lineNoiseRatio: 0.05,
              ),
            ),
          ),
        );
      }
      final eeg = Float64List(256);
      for (var i = 0; i < 256; i++) {
        eeg[i] = i * 0.5;
      }
      events.addAll(
        encodeSessionEvent(
          event: MuseEventDto.eeg(
            EegDto(
              index: s,
              electrode: 1,
              timestamp: s * 1000.0,
              samples: eeg,
            ),
          ),
        ),
      );
    }
    final rawBody = Uint8List.fromList([
      ...sessionHeaderBytes(),
      ...sessionFrameBytes(data: events),
    ]);

    // Publish session with raw body (publishSession will wrap in v5 container)
    final meta = _metadata(
      withCalibration: true,
      withDrowsiness: true,
      withMusic: true,
      withGestures: true,
    );
    final computedFrames = _buildComputedFrames();
    await store.publishSession(
      id,
      rawBody,
      meta,
      pngBytes: _webp1x1,
      computedFrames: computedFrames,
    );
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<List<String>> exportDirEntries(String sub) async {
    final dir = Directory('${tmp.path}/export/$sub');
    if (!await dir.exists()) {
      return [];
    }
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList();
  }

  test('CSV export writes per-second absolute bands and raw EEG', () async {
    final result = await SessionExporter(store, storage).exportSessions(
      sessions: [SessionSummary(id: id, metadata: _metadata())],
      kind: ExportKind.csv,
    );
    expect(result.fileCount, 1);
    expect(result.warnings, isEmpty);

    final entries = await exportDirEntries('');
    expect(entries, hasLength(1));
    final csv = await File('${tmp.path}/export/${entries.single}').readAsString();

    final lines = csv.trim().split('\n');
    expect(lines, hasLength(4));
    expect(
      lines.first,
      startsWith('TimeStamp,Delta_TP9,Theta_TP9,Alpha_TP9,Beta_TP9,'
          'Gamma_TP9,Delta_AF7,'),
    );
    expect(lines.first, endsWith('RAW_AF7'));
    expect(lines.first, isNot(contains('RAW_TP9')));

    // Row 1 (second 0): electrode 1 delta = 100 + 100 + 0 + 1 = 201.0
    final row = lines[1].split(',');
    expect(row, hasLength(22));
    expect(row[6], '201.000'); // Delta_AF7 at index 6
    expect(row[21], isNotEmpty); // RAW_AF7
    // Timestamp anchored at savedAt - elapsedSeconds.
    expect(row.first, '2026-08-19 10:29:57.000');
    // Second 1: delta = 202.0
    expect(lines[2].split(',')[6], '202.000');
  });

  test('EDF export produces an EDF+ header with one annotated signal', () async {
    final result = await SessionExporter(store, storage).exportSessions(
      sessions: [SessionSummary(id: id, metadata: _metadata())],
      kind: ExportKind.edf,
    );
    expect(result.warnings, isEmpty);

    final entries = await exportDirEntries('');
    expect(entries, hasLength(1));
    final edf = await File('${tmp.path}/export/${entries.single}').readAsBytes();
    expect(String.fromCharCodes(edf.sublist(0, 8)), '0       ');
    // Numeric header fields are right-justified ASCII, not binary.
    expect(String.fromCharCodes(edf.sublist(252, 256)).trim(), '2'); // nsig
    // signal[0] label: 'AF7'
    expect(String.fromCharCodes(edf.sublist(256, 260)), 'AF7 ');
    // 3 full seconds + trailing partial second = 4 records.
    expect(String.fromCharCodes(edf.sublist(236, 244)).trim(), '4');
  });

  test('PNG thumbnail export writes the stored thumbnail', () async {
    final result = await SessionExporter(store, storage).exportSessions(
      sessions: [SessionSummary(id: id, metadata: _metadata())],
      kind: ExportKind.pngThumbnail,
    );
    expect(result.warnings, isEmpty);

    final entries = await exportDirEntries('');
    expect(entries, hasLength(1));
    final png = await File('${tmp.path}/export/${entries.single}').readAsBytes();
    expect(png, _webp1x1); // Note: thumbnail is stored as WebP in v5
  });

  test('PNG all export rasterizes every chart into a per-session folder',
      () async {
    final result = await SessionExporter(store, storage).exportSessions(
      sessions: [SessionSummary(id: id, metadata: _metadata())],
      kind: ExportKind.pngAll,
    );
    expect(result.warnings, isEmpty);

    final entries = await exportDirEntries('20260819_103000_drowsiness_abc12345');
    expect(entries, contains('thumbnail.png'));
    expect(entries, contains('bands.png'));
    expect(entries, contains('alpha_vs_theta.png'));
    expect(entries, contains('movement.png'));
    expect(entries, contains('heart_rate.png'));
    for (final name in entries) {
      final bytes = await File(
        '${tmp.path}/export/20260819_103000_drowsiness_abc12345/$name',
      ).readAsBytes();
      if (name == 'thumbnail.png') {
        expect(bytes, _webp1x1);
        continue;
      }
      expect(bytes.length, greaterThan(1000), reason: name);
      // PNG magic.
      expect(bytes[0], 0x89);
      expect(bytes[1], 0x50);
    }
  });

  test('PDF export produces a vector document', () async {
    final result = await SessionExporter(store, storage).exportSessions(
      sessions: [SessionSummary(id: id, metadata: _metadata())],
      kind: ExportKind.pdf,
    );
    expect(result.warnings, isEmpty);

    final entries = await exportDirEntries('');
    expect(entries, hasLength(1));
    final pdf = await File('${tmp.path}/export/${entries.single}').readAsBytes();
    expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
  });

  test('export of a session without EEG warns instead of failing', () async {
    // Build raw body without EEG data
    final events = <int>[];
    for (var e = 0; e < 4; e++) {
      events.addAll(
        encodeSessionEvent(
          event: MuseEventDto.bands(
            BandsDto(
              electrode: e,
              timestamp: 500,
              delta: 1,
              theta: 2,
              alpha: 3,
              beta: 4,
              gamma: 5,
              lineNoiseRatio: 0,
            ),
          ),
        ),
      );
    }
    // No EEG events
    final rawBody = Uint8List.fromList([
      ...sessionHeaderBytes(),
      ...sessionFrameBytes(data: events),
    ]);

    final metadata = _metadata();
    final computedFrames = _buildComputedFrames();

    final otherId = 'noeeg${DateTime.now().millisecondsSinceEpoch}';
    await store.publishSession(
      otherId,
      rawBody,
      metadata,
      pngBytes: _webp1x1,
      computedFrames: computedFrames,
    );
    final result = await SessionExporter(store, storage).exportSessions(
      sessions: [SessionSummary(id: otherId, metadata: metadata)],
      kind: ExportKind.edf,
    );
    expect(result.fileCount, 0);
    expect(result.warnings, hasLength(1));
    expect(result.warnings.single.message, contains('no raw EEG'));
  });

  test('delete removes the session file', () async {
    expect(await store.delete(id), isTrue);
    expect(await store.list(), isEmpty);
    expect(await store.delete(id), isFalse);
  });

  test('CSV export includes calibration trim (training start offset)', () async {
    // Session with calibration: calibration ends at 5s, training starts at 5s
    final metaWithCal = _metadata(withCalibration: true);
    final computedFrames = _buildComputedFrames();

    // Build raw body
    final events = <int>[];
    for (var s = 0; s < 3; s++) {
      for (var e = 0; e < 4; e++) {
        final t = s * 1000 + 500.0;
        events.addAll(
          encodeSessionEvent(
            event: MuseEventDto.bands(
              BandsDto(
                electrode: e,
                timestamp: t,
                delta: 100 + e * 100 + s + 1,
                theta: 200 + e * 100 + s + 1,
                alpha: 300 + e * 100 + s + 1,
                beta: 400 + e * 100 + s + 1,
                gamma: 500 + e * 100 + s + 1,
                lineNoiseRatio: 0.05,
              ),
            ),
          ),
        );
      }
      final eeg = Float64List(256);
      for (var i = 0; i < 256; i++) {
        eeg[i] = i * 0.5;
      }
      events.addAll(
        encodeSessionEvent(
          event: MuseEventDto.eeg(
            EegDto(
              index: s,
              electrode: 1,
              timestamp: s * 1000.0,
              samples: eeg,
            ),
          ),
        ),
      );
    }
    final rawBody = Uint8List.fromList([
      ...sessionHeaderBytes(),
      ...sessionFrameBytes(data: events),
    ]);

    const calId = 'cal_test';
    await store.publishSession(
      calId,
      rawBody,
      metaWithCal,
      pngBytes: _webp1x1,
      computedFrames: computedFrames,
    );

    final result = await SessionExporter(store, storage).exportSessions(
      sessions: [SessionSummary(id: calId, metadata: metaWithCal)],
      kind: ExportKind.csv,
    );
    expect(result.fileCount, 1);
    expect(result.warnings, isEmpty);

    final entries = await exportDirEntries('');
    expect(entries, hasLength(1));
    final csv = await File('${tmp.path}/export/${entries.single}').readAsString();

    final lines = csv.trim().split('\n');
    expect(lines, hasLength(4));

    final row = lines[1].split(',');
    expect(row.first, '2026-08-19 10:29:57.000'); // savedAt - elapsedSeconds
  });

  test('export preserves gesture markers in metadata', () async {
    final metaWithGestures = _metadata(withGestures: true);
    final computedFrames = _buildComputedFrames();

    // Build raw body
    final events = <int>[];
    for (var s = 0; s < 3; s++) {
      for (var e = 0; e < 4; e++) {
        final t = s * 1000 + 500.0;
        events.addAll(
          encodeSessionEvent(
            event: MuseEventDto.bands(
              BandsDto(
                electrode: e,
                timestamp: t,
                delta: 100 + e * 100 + s + 1,
                theta: 200 + e * 100 + s + 1,
                alpha: 300 + e * 100 + s + 1,
                beta: 400 + e * 100 + s + 1,
                gamma: 500 + e * 100 + s + 1,
                lineNoiseRatio: 0.05,
              ),
            ),
          ),
        );
      }
      final eeg = Float64List(256);
      for (var i = 0; i < 256; i++) {
        eeg[i] = i * 0.5;
      }
      events.addAll(
        encodeSessionEvent(
          event: MuseEventDto.eeg(
            EegDto(
              index: s,
              electrode: 1,
              timestamp: s * 1000.0,
              samples: eeg,
            ),
          ),
        ),
      );
    }
    final rawBody = Uint8List.fromList([
      ...sessionHeaderBytes(),
      ...sessionFrameBytes(data: events),
    ]);

    const gestId = 'gest_test';
    await store.publishSession(
      gestId,
      rawBody,
      metaWithGestures,
      pngBytes: _webp1x1,
      computedFrames: computedFrames,
    );

    final result = await SessionExporter(store, storage).exportSessions(
      sessions: [SessionSummary(id: gestId, metadata: metaWithGestures)],
      kind: ExportKind.csv,
    );
    expect(result.fileCount, 1);
    expect(result.warnings, isEmpty);
  });
}