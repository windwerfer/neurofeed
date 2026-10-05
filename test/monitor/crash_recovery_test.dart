import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/monitor/recording/crash_recovery.dart';
import 'package:neurofeed/src/monitor/recording/recording_metadata.dart';
import 'package:neurofeed/src/rust/api/session_format.dart';
import 'package:neurofeed/src/rust/frb_generated.dart';
import 'package:neurofeed/src/spine/assemble.dart';
import 'package:neurofeed/src/session_format/models.dart';
import 'package:neurofeed/src/settings.dart';

final String _rustLibPath =
    '${Directory.current.path}/rust/target/debug/librust_lib_neurofeed.so';

RecordingMetadata _meta() => RecordingMetadata(
  formatVersion: 5,
  appVersion: 'dev',
  kind: 'recording',
  savedAt: DateTime.utc(2026, 9, 12, 12),
  startedAt: DateTime.utc(2026, 9, 12, 11, 50),
  elapsedSeconds: 12,
  durationS: 12,
  device: const DeviceInfo(
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
    scratch = await Directory.systemTemp.createTemp('neurofeed_rec_crash_');
  });

  tearDown(() async {
    if (await scratch.exists()) {
      await scratch.delete(recursive: true);
    }
  });

  test('recordingIdFrom is prefix-strict', () {
    expect(recordingIdFrom('recording_123.raw', '.raw'), '123');
    expect(recordingIdFrom('recording_123.neurofeed', '.neurofeed'), '123');
    expect(recordingIdFrom('tmp_123.raw', '.raw'), isNull);
    expect(recordingIdFrom('session_123.raw', '.raw'), isNull);
    expect(recordingIdFrom('recording_.raw', '.raw'), isNull);
  });

  test('recovered recording stats come from the computed frames', () async {
    const line =
        '{"t":1,"bands":[[1,2,3,4,5],[1,2,3,4,5],[1,2,3,4,5],[1,2,3,4,5]],'
        '"pulse":60,"movement":0.01,"spo2":97,"lineNoise":[0,0,0,0],'
        '"signalQuality":[90,90,90,90],'
        '"guardrail":{"sleepDir":0.0,"clarity":1.0,"warning":false,"delta":0.0},'
        '"feedback":{"ratio":1.0,"threshold":1.0,"inTarget":true,"pct":1.0},'
        '"gestures":[]}\n'
        '{"t":2,"bands":[[1,2,3,4,5],[1,2,3,4,5],[1,2,3,4,5],[1,2,3,4,5]],'
        '"pulse":80,"movement":0.01,"spo2":99,"lineNoise":[0,0,0,0],'
        '"signalQuality":[90,90,90,90],'
        '"guardrail":{"sleepDir":0.0,"clarity":1.0,"warning":false,"delta":0.0},'
        '"feedback":{"ratio":1.0,"threshold":1.0,"inTarget":true,"pct":1.0},'
        '"gestures":[]}\n';
    await File('${scratch.path}/recording_1002.raw').writeAsBytes([1, 2, 3, 4]);
    await File('${scratch.path}/recording_1002.computed').writeAsString(line);
    await File(
      '${scratch.path}/recording_1002.json',
    ).writeAsString(jsonEncode(_meta().toJson()));

    final recovered = await scanRecoverableRecordings(scratch);
    final head = parseHead(
      bytes: Uint8List.fromList(recovered.single.scratch.readAsBytesSync()),
    );
    final meta = jsonDecode(utf8.decode(head.metadataJson)) as Map;
    final hr = (meta['stats'] as Map)['hr'] as Map;
    expect(hr['mean'], 70);
    expect(hr['min'], 60);
    expect(hr['max'], 80);
  });

  test('leftover recording_ temps assemble to scratch .neurofeed', () async {
    await File('${scratch.path}/recording_1001.raw').writeAsBytes([1, 2, 3, 4]);
    await File('${scratch.path}/recording_1001.computed').writeAsString('');
    await File(
      '${scratch.path}/recording_1001.json',
    ).writeAsString(jsonEncode(_meta().toJson()));

    final recovered = await scanRecoverableRecordings(scratch);
    expect(recovered, hasLength(1));
    expect(recovered.single.id, '1001');
    expect(recovered.single.scratch.existsSync(), isTrue);
    expect(
      recovered.single.scratch.uri.pathSegments.last,
      'recording_1001.neurofeed',
    );
    expect(File('${scratch.path}/recording_1001.raw').existsSync(), isFalse);
    expect(File('${scratch.path}/recording_1001.computed').existsSync(), isFalse);
    expect(File('${scratch.path}/recording_1001.json').existsSync(), isFalse);

    final head = parseHead(
      bytes: Uint8List.fromList(recovered.single.scratch.readAsBytesSync()),
    );
    final meta = jsonDecode(utf8.decode(head.metadataJson)) as Map;
    expect(meta['kind'], 'recording');
  });

  test('recovered recording keeps the frozen device.conditioning', () async {
    final meta = _meta().toJson();
    const conditioning = SignalConditioning(
      highPassHz: 0.5,
      notchQ: 10,
      notchHz: [50, 60],
      notchSource: 'undecided',
    );
    (meta['device'] as Map)['conditioning'] = conditioning.toJson();
    await File('${scratch.path}/recording_4004.raw').writeAsBytes([1, 2, 3, 4]);
    await File('${scratch.path}/recording_4004.computed').writeAsString('');
    await File('${scratch.path}/recording_4004.json').writeAsString(jsonEncode(meta));

    final recovered = await scanRecoverableRecordings(scratch);
    final head = parseHead(
      bytes: Uint8List.fromList(recovered.single.scratch.readAsBytesSync()),
    );
    final stored = jsonDecode(utf8.decode(head.metadataJson)) as Map;
    expect((stored['device'] as Map)['conditioning'], conditioning.toJson());
  });

  test('leftover assembled .neurofeed is returned without a second assemble', () async {
    final scratchFile = await writeScratch(
      dir: scratch,
      id: '2002',
      prefix: 'recording',
      metadataJson: _meta().toJson(),
      rawBody: const [1, 2, 3, 4],
      computedJsonl: const [],
    );
    await File('${scratch.path}/recording_2002.raw').writeAsBytes([9, 9]);
    final before = scratchFile.lengthSync();

    final recovered = await scanRecoverableRecordings(scratch);
    expect(recovered, hasLength(1));
    expect(recovered.single.id, '2002');
    expect(recovered.single.scratch.path, scratchFile.path);
    expect(scratchFile.lengthSync(), before);
    expect(File('${scratch.path}/recording_2002.raw').existsSync(), isFalse);
  });

  test('tmp_ and session_ are left untouched', () async {
    await File('${scratch.path}/tmp_1.raw').writeAsString('tmp');
    await File('${scratch.path}/tmp_1.computed').writeAsString('tmp');
    await File('${scratch.path}/session_9.raw').writeAsString('ses');
    await File('${scratch.path}/session_9.neurofeed').writeAsString('ses');
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
    expect(File('${scratch.path}/session_9.neurofeed').existsSync(), isTrue);

    final n = await deleteLeftoverTmpCaptures(scratch);
    expect(n, 2);
    expect(File('${scratch.path}/tmp_1.raw').existsSync(), isFalse);
    expect(File('${scratch.path}/session_9.raw').existsSync(), isTrue);
    expect(File('${scratch.path}/session_9.neurofeed').existsSync(), isTrue);
    expect(
      File('${scratch.path}/recording_3.neurofeed').existsSync(),
      isTrue,
    );
  });

  test('recovered metadata without sidecar never labels unknown widths as Muse', () {
    expect(
      recoveredRecordingMetadata(elapsedSeconds: 1).device.channelLabels,
      ['TP9', 'AF7', 'AF8', 'TP10'],
    );
    expect(
      recoveredRecordingMetadata(elapsedSeconds: 1, channelCount: 5)
          .device
          .channelLabels,
      ['TP9', 'AF7', 'AF8', 'TP10', 'AUX1'],
    );
    final eight = recoveredRecordingMetadata(elapsedSeconds: 1, channelCount: 8);
    expect(eight.device.channelCount, 8);
    expect(eight.device.channelLabels.first, 'CH1');
  });
}
