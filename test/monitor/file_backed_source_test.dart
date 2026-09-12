import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/cache/file_backed_source.dart';
import 'package:muse_ml/src/monitor/cache/recording_index.dart';
import 'package:muse_ml/src/monitor/recording/monitor_recorder.dart';
import 'package:muse_ml/src/monitor/recording/recording_metadata.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/rust/api/session_format.dart';
import 'package:muse_ml/src/rust/frb_generated.dart';
import 'package:muse_ml/src/session_v5/models.dart';
import 'package:muse_ml/src/settings.dart';

final String _rustLibPath =
    '${Directory.current.path}/rust/target/debug/librust_lib_muse_ml.so';

const int _startMs = 1700000000000;

RecordingMetadata _meta() => RecordingMetadata(
  formatVersion: 5,
  appVersion: 'test',
  kind: 'tmp',
  savedAt: DateTime.utc(2026, 9, 7),
  startedAt: DateTime.utc(2026, 9, 7),
  elapsedSeconds: 0,
  durationS: 0,
  device: const DeviceInfoV5(
    name: 'test',
    id: 'sim:muse-2',
    firmware: 'Classic',
    model: 'Classic',
    sensors: ['EEG'],
    channelCount: 4,
    channelLabels: ['TP9', 'AF7', 'AF8', 'TP10'],
  ),
  streams: RecordingMetadata.streamsConfig(RecordingStream.values.toSet()),
);

MuseEventDto _eeg(int elapsedMs, {int electrode = 0}) => MuseEventDto.eeg(
  EegDto(
    index: 0,
    electrode: electrode,
    timestamp: (_startMs + elapsedMs).toDouble(),
    samples: Float64List.fromList([1.0, 2.0, 3.0]),
  ),
);

MuseEventDto _bands(int elapsedMs) => MuseEventDto.bands(
  BandsDto(
    electrode: 1,
    timestamp: (_startMs + elapsedMs).toDouble(),
    delta: 1,
    theta: 2,
    alpha: 3,
    beta: 4,
    gamma: 5,
    lineNoiseRatio: 0.05,
  ),
);

MonitorRecorder _recorder() => MonitorRecorder(
  tmpCap: const Duration(hours: 1),
  sidecarInterval: const Duration(hours: 1),
);

Future<MonitorRecorder> _started(Directory dir) async {
  final rec = _recorder();
  await rec.startTmp(
    dir: dir,
    recordStreams: RecordingStream.values.toSet(),
    metadata: _meta,
    captureStartedAtMs: _startMs,
  );
  return rec;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init(externalLibrary: ExternalLibrary.open(_rustLibPath));
  });

  test('completeFrames omits a truncated last frame', () {
    final bytes = Uint8List.fromList([4, 0, 0, 0, 1, 2, 3, 4, 9, 9]);
    expect(completeFrames(bytes), [4, 0, 0, 0, 1, 2, 3, 4]);
  });

  test('flushRaw indexes one entry at the .raw size', () async {
    final dir = await Directory.systemTemp.createTemp('muse_idx_');
    addTearDown(() => dir.delete(recursive: true));
    final rec = await _started(dir);

    rec.writeEvent(_eeg(5000));
    rec.flushRaw();

    expect(rec.index.entries, hasLength(1));
    final raw = File(rec.currentFilePath!);
    expect(rec.index.entries.single.fileLength, raw.lengthSync());
    expect(
      rec.index.entries.single.fileLength,
      greaterThan(kMuseBodyHeaderLength),
    );
    expect(rec.index.entries.single.elapsedT, closeTo(5.0, 0.001));
    expect(rec.index.covering(0, 10)!.startOffset, kMuseBodyHeaderLength);

    await rec.discard();
  });

  test('flushRaw indexes recording_ on the same RecordingIndex', () async {
    final dir = await Directory.systemTemp.createTemp('muse_rec_idx_');
    addTearDown(() => dir.delete(recursive: true));
    final rec = _recorder();
    await rec.startRecording(
      dir: dir,
      recordStreams: RecordingStream.values.toSet(),
      metadata: _meta,
      captureStartedAtMs: _startMs,
    );

    rec.writeEvent(_eeg(5000));
    rec.flushRaw();

    expect(rec.prefix, 'recording');
    expect(rec.currentFilePath, contains('recording_'));
    expect(rec.index.entries, hasLength(1));
    final raw = File(rec.currentFilePath!);
    expect(rec.index.entries.single.fileLength, raw.lengthSync());
    expect(rec.index.entries.single.elapsedT, closeTo(5.0, 0.001));
    expect(rec.index.covering(0, 10)!.startOffset, kMuseBodyHeaderLength);

    await rec.discard();
  });

  test('getRange returns elapsed t, not unix seconds', () async {
    final dir = await Directory.systemTemp.createTemp('muse_range_');
    addTearDown(() => dir.delete(recursive: true));
    final rec = await _started(dir);

    rec.writeEvent(_eeg(5000));
    rec.writeEvent(_bands(5000));
    rec.flushRaw();

    final data = rec.source!.getRange(0, 10);
    expect(data.eeg, isNotEmpty);
    expect(data.eeg.first.timestamp, closeTo(5.0, 0.01));
    expect(data.eeg.first.timestamp, lessThan(100));
    expect(data.bands, isNotEmpty);
    expect(data.bands.first.timestamp, closeTo(5.0, 0.01));
    expect(data.eegSamples.toInt(), data.eeg.first.samples.length);

    await rec.discard();
  });

  test('slice without header fails parse; prepend path succeeds', () async {
    final dir = await Directory.systemTemp.createTemp('muse_hdr_');
    addTearDown(() => dir.delete(recursive: true));
    final rec = await _started(dir);

    rec.writeEvent(_eeg(1000));
    rec.flushRaw();
    final raw = File(rec.currentFilePath!).readAsBytesSync();
    expect(raw.length, greaterThan(kMuseBodyHeaderLength));

    expect(
      () => sessionParseBody(bytes: raw.sublist(kMuseBodyHeaderLength)),
      throwsA(
        predicate(
          (e) =>
              e.toString().contains('Not a .muse file') ||
              e.toString().contains('Truncated .muse header'),
        ),
      ),
    );
    expect(sessionParseBody(bytes: raw).eeg, isNotEmpty);
    expect(rec.source!.getRange(0, 10).eeg, isNotEmpty);

    await rec.discard();
  });

  test(
    'getRange reads from a frame boundary; incomplete tail omitted',
    () async {
      final dir = await Directory.systemTemp.createTemp('muse_frm_');
      addTearDown(() => dir.delete(recursive: true));
      final rec = await _started(dir);

      rec.writeEvent(_eeg(1000));
      rec.flushRaw();
      final firstLen = rec.index.entries.single.fileLength;

      rec.writeEvent(_eeg(10000));
      rec.flushRaw();
      expect(rec.index.entries, hasLength(2));

      final span = rec.index.covering(8, 12);
      expect(span, isNotNull);
      expect(span!.startOffset, firstLen);
      expect(span.startOffset, greaterThan(kMuseBodyHeaderLength));

      final late = rec.source!.getRange(8, 12);
      expect(late.eeg, hasLength(1));
      expect(late.eeg.single.timestamp, closeTo(10.0, 0.01));

      final early = rec.source!.getRange(0, 2);
      expect(early.eeg, hasLength(1));
      expect(early.eeg.single.timestamp, closeTo(1.0, 0.01));

      final raw = File(rec.currentFilePath!);
      raw.writeAsBytesSync(const [1, 0, 0], mode: FileMode.append);
      rec.index.add(elapsedT: 10.0, fileLength: raw.lengthSync());
      final withJunk = rec.source!.getRange(8, 12);
      expect(withJunk.eeg, hasLength(1));
      expect(withJunk.eeg.single.timestamp, closeTo(10.0, 0.01));

      await rec.discard();
    },
  );

  test('rotate / new tmp clears the index', () async {
    final dir = await Directory.systemTemp.createTemp('muse_rot_');
    addTearDown(() => dir.delete(recursive: true));
    final rec = await _started(dir);

    rec.writeEvent(_eeg(1000));
    rec.flushRaw();
    expect(rec.index.entries, hasLength(1));
    final oldPath = rec.currentFilePath;

    await rec.discard();
    expect(rec.index.isEmpty, isTrue);
    expect(rec.source, isNull);

    await rec.startTmp(
      dir: dir,
      recordStreams: RecordingStream.values.toSet(),
      metadata: _meta,
      captureStartedAtMs: _startMs,
    );
    expect(rec.index.isEmpty, isTrue);
    expect(rec.currentFilePath, isNot(oldPath));

    rec.writeEvent(_eeg(2000));
    rec.flushRaw();
    expect(rec.index.entries, hasLength(1));
    expect(rec.index.entries.single.elapsedT, closeTo(2.0, 0.01));
    expect(rec.source!.getRange(0, 10).eeg, hasLength(1));

    await rec.discard();
  });

  test('captureStartedAtMs == null yields no unix-epoch range', () async {
    final dir = await Directory.systemTemp.createTemp('muse_null_');
    addTearDown(() => dir.delete(recursive: true));
    final rec = await _started(dir);

    rec.writeEvent(_eeg(5000));
    rec.flushRaw();
    final path = rec.currentFilePath!;
    final index = RecordingIndex()
      ..add(elapsedT: 5.0, fileLength: File(path).lengthSync());

    final src = FileBackedSource(
      file: File(path),
      index: index,
      captureStartedAtMs: null,
    );
    final data = src.getRange(0, 1e12);
    expect(data.eeg, isEmpty);
    expect(data.bands, isEmpty);
    expect(data.eegSamples, BigInt.zero);

    await rec.discard();
  });

  test('bands-only flush is skipped until an EEG timestamp exists', () async {
    final dir = await Directory.systemTemp.createTemp('muse_bands_');
    addTearDown(() => dir.delete(recursive: true));
    final rec = await _started(dir);

    rec.writeEvent(_bands(1000));
    rec.flushRaw();
    expect(rec.index.isEmpty, isTrue);

    rec.writeEvent(_eeg(2000));
    rec.flushRaw();
    expect(rec.index.entries, hasLength(1));

    rec.writeEvent(_bands(3000));
    rec.flushRaw();
    expect(rec.index.entries, hasLength(2));
    expect(rec.index.entries.last.elapsedT, closeTo(2.0, 0.01));

    await rec.discard();
  });
}
