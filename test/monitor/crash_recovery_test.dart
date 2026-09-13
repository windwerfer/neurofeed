import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/recording/crash_recovery.dart';
import 'package:muse_ml/src/monitor/recording/recording_metadata.dart';
import 'package:muse_ml/src/rust/api/session_format.dart';
import 'package:muse_ml/src/rust/frb_generated.dart';
import 'package:muse_ml/src/session_v5/assemble.dart';
import 'package:muse_ml/src/session_v5/models.dart';
import 'package:muse_ml/src/settings.dart';

final String _rustLibPath =
    '${Directory.current.path}/rust/target/debug/librust_lib_muse_ml.so';

RecordingMetadata _meta() => RecordingMetadata(
  formatVersion: 5,
  appVersion: 'dev',
  kind: 'recording',
  savedAt: DateTime.utc(2026, 9, 12, 12),
  startedAt: DateTime.utc(2026, 9, 12, 11, 50),
  elapsedSeconds: 12,
  durationS: 12,
  device: const DeviceInfoV5(
    name: 'Muse 2 (Simulated)',
    id: 'sim:muse-2',
    firmware: 'Classic',
    model: 'Classic',
    sensors: ['EEG', 'PPG', 'IMU'],
    channelCount: 4,
    channelLabels: ['TP9', 'AF7', 'AF8', 'TP10'],
  ),
  streams: RecordingMetadata.streamsConfig(RecordingStream.values.toSet()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init(externalLibrary: ExternalLibrary.open(_rustLibPath));
  });

  late Directory scratch;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('muse_rec_crash_');
  });

  tearDown(() async {
    if (await scratch.exists()) {
      await scratch.delete(recursive: true);
    }
  });

  test('recordingIdFrom is prefix-strict', () {
    expect(recordingIdFrom('recording_123.raw', '.raw'), '123');
    expect(recordingIdFrom('recording_123.muse.feedback', '.muse.feedback'), '123');
    expect(recordingIdFrom('tmp_123.raw', '.raw'), isNull);
    expect(recordingIdFrom('session_123.raw', '.raw'), isNull);
    expect(recordingIdFrom('recording_.raw', '.raw'), isNull);
  });

  test('leftover recording_ temps assemble to scratch v5', () async {
    await File('${scratch.path}/recording_1001.raw').writeAsBytes([1, 2, 3, 4]);
    await File('${scratch.path}/recording_1001.computed').writeAsString('');
    await File(
      '${scratch.path}/recording_1001.json',
    ).writeAsString(jsonEncode(_meta().toJson()));

    final recovered = await scanRecoverableRecordings(scratch);
    expect(recovered, hasLength(1));
    expect(recovered.single.id, '1001');
    expect(recovered.single.scratchV5.existsSync(), isTrue);
    expect(
      recovered.single.scratchV5.uri.pathSegments.last,
      'recording_1001.muse.feedback',
    );
    expect(File('${scratch.path}/recording_1001.raw').existsSync(), isFalse);
    expect(File('${scratch.path}/recording_1001.computed').existsSync(), isFalse);
    expect(File('${scratch.path}/recording_1001.json').existsSync(), isFalse);

    final head = v5ParseHead(
      bytes: Uint8List.fromList(recovered.single.scratchV5.readAsBytesSync()),
    );
    final meta = jsonDecode(utf8.decode(head.metadataJson)) as Map;
    expect(meta['kind'], 'recording');
  });

  test('leftover assembled v5 is returned without a second assemble', () async {
    final v5 = await writeScratchV5(
      dir: scratch,
      id: '2002',
      prefix: 'recording',
      metadataJson: _meta().toJson(),
      rawBody: const [1, 2, 3, 4],
      computedJsonl: const [],
    );
    await File('${scratch.path}/recording_2002.raw').writeAsBytes([9, 9]);
    final before = v5.lengthSync();

    final recovered = await scanRecoverableRecordings(scratch);
    expect(recovered, hasLength(1));
    expect(recovered.single.id, '2002');
    expect(recovered.single.scratchV5.path, v5.path);
    expect(v5.lengthSync(), before);
    expect(File('${scratch.path}/recording_2002.raw').existsSync(), isFalse);
  });

  test('tmp_ and session_ are left untouched', () async {
    await File('${scratch.path}/tmp_1.raw').writeAsString('tmp');
    await File('${scratch.path}/tmp_1.computed').writeAsString('tmp');
    await File('${scratch.path}/session_9.raw').writeAsString('ses');
    await File('${scratch.path}/session_9.muse.feedback').writeAsString('ses');
    await File('${scratch.path}/recording_3.raw').writeAsBytes([1, 2, 3, 4]);
    await File('${scratch.path}/recording_3.computed').writeAsString('');
    await File(
      '${scratch.path}/recording_3.json',
    ).writeAsString(jsonEncode(_meta().toJson()));

    final recovered = await scanRecoverableRecordings(scratch);
    expect(recovered.map((r) => r.id).toList(), ['3']);
    expect(File('${scratch.path}/tmp_1.raw').existsSync(), isTrue);
    expect(File('${scratch.path}/tmp_1.computed').existsSync(), isTrue);
    expect(File('${scratch.path}/session_9.raw').existsSync(), isTrue);
    expect(File('${scratch.path}/session_9.muse.feedback').existsSync(), isTrue);

    final n = await deleteLeftoverTmpCaptures(scratch);
    expect(n, 2);
    expect(File('${scratch.path}/tmp_1.raw').existsSync(), isFalse);
    expect(File('${scratch.path}/session_9.raw').existsSync(), isTrue);
    expect(File('${scratch.path}/session_9.muse.feedback').existsSync(), isTrue);
    expect(
      File('${scratch.path}/recording_3.muse.feedback').existsSync(),
      isTrue,
    );
  });
}
