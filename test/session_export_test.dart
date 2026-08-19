import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/session_export.dart';
import 'package:muse_ml/src/feedback/session_pdf_export.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/rust/api/session_format.dart';
import 'package:muse_ml/src/rust/frb_generated.dart';

/// Load the host build of the Rust lib so FFI calls work under `flutter test`.
/// Build it with `cargo build --manifest-path rust/Cargo.toml`.
final String _rustLibPath =
    '${Directory.current.path}/rust/target/debug/librust_lib_muse_ml.so';

const _png1x1 = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0xDA, 0x63, 0x64, 0x60, 0xF8, 0x5F,
  0x0F, 0x00, 0x02, 0x87, 0x01, 0x80, 0xEB, 0x47, 0xBA, 0x92, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

/// A 3-second body: 4 band streams (one per electrode, 1 Hz) + one EEG
/// stream (electrode 1 = AF7, 256 samples/sec).
Uint8List _buildBody() {
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
  return Uint8List.fromList([
    ...sessionHeaderBytes(),
    ...sessionFrameBytes(data: events),
  ]);
}

SessionMetadata _metadata() => SessionMetadata(
  protocol: ProtocolType.drowsiness,
  durationMinutes: 0,
  elapsedSeconds: 3,
  sound: 'Bowl Chimes',
  savedAt: DateTime.utc(2026, 8, 19, 10, 30),
  recordedChannels: const ['TP9', 'AF7', 'AF8', 'TP10'],
);

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
    await store.publishSession(
      id,
      _buildBody(),
      _metadata(),
      pngBytes: _png1x1,
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
    // Column layout: 1 (TimeStamp) + 4 electrodes x 5 bands = 21, then RAW_AF7.
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
    expect(png, _png1x1);
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
        expect(bytes, _png1x1);
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
    final otherId = 'noeeg0001';
    await store.publishSession(
      otherId,
      Uint8List.fromList([
        ...sessionHeaderBytes(),
        ...sessionFrameBytes(data: events),
      ]),
      _metadata(),
    );
    final result = await SessionExporter(store, storage).exportSessions(
      sessions: [SessionSummary(id: otherId, metadata: _metadata())],
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
}