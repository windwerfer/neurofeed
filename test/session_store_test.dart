import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/feedback/session_sqlite.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/monitor/recording/recording_metadata.dart';
import 'package:muse_ml/src/monitor/recording/recording_store.dart';
import 'package:muse_ml/src/rust/api/session_format.dart';
import 'package:muse_ml/src/rust/frb_generated.dart';
import 'package:muse_ml/src/session_v5/assemble.dart';
import 'package:muse_ml/src/session_v5/models.dart';
import 'package:muse_ml/src/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        '${Directory.current.path}/rust/target/debug/librust_lib_muse_ml.so',
      ),
    );
  });

  test('SessionStore publish and list test', () async {
    final tmp = await Directory.systemTemp.createTemp('muse_store_test');
    final storage = FileSystemSessionStorage(tmp);
    final store = SessionStore(storage: Future.value(storage));

    final metadata = SessionMetadata(
      protocol: 'drowsiness',
      durationMinutes: 5,
      elapsedSeconds: 300,
      sound: 'Ambient Drone',
      savedAt: DateTime.now().toIso8601String(),
    );

    // Use v5 format with empty computed frames (dummy body [1,2,3,4] is valid v4 raw body)
    await store.publishSession(
      'test1234',
      metadata,
      rawBody: [1, 2, 3, 4],
      computedFrames: const <ComputedFrame>[],
    );
    final list = await store.list();
    expect(list.length, 1);
    expect(list.first.id, 'test1234');
    expect(list.first.metadata.protocol, 'drowsiness');
    expect(list.first.kind, 'feedback');
    expect(list.first.path, 'session_test1234.muse.feedback');

    await tmp.delete(recursive: true);
  });

  test(
    'list includes recording rows; no directory backfill without a row',
    () async {
      final tmp = await Directory.systemTemp.createTemp('muse_hist_list_');
      addTearDown(() => tmp.delete(recursive: true));
      final storage = FileSystemSessionStorage(tmp);
      final cacheDir = await resolveSessionCacheDir(storage);
      final sqlite = await SessionSqlite.open(cacheDirectory: cacheDir);
      final recStore = RecordingStore(storage: storage, sqlite: sqlite);

      final scratch = scratchDirectory(storage);
      await scratch.create(recursive: true);
      final scratchV5 = await writeScratchV5(
        dir: scratch,
        id: '9001',
        prefix: 'recording',
        metadataJson: _recordingMeta().toJson(),
        rawBody: const [1, 2, 3, 4],
        computedJsonl: const [],
      );
      await recStore.publish(scratchV5);
      sqlite.close();

      await File(
        '${tmp.path}/recording_orphan.muse.feedback',
      ).writeAsBytes([1, 2, 3, 4]);

      final store = SessionStore(storage: Future.value(storage));
      await store.publishSession(
        'fb1',
        SessionMetadata(
          protocol: 'drowsiness',
          durationMinutes: 1,
          elapsedSeconds: 60,
          sound: 'Ambient Drone',
          savedAt: DateTime.now().toIso8601String(),
        ),
        rawBody: const [1, 2, 3, 4],
        computedFrames: const <ComputedFrame>[],
      );

      final list = await store.list();
      expect(list.map((s) => s.id), containsAll(['9001', 'fb1']));
      expect(list.any((s) => s.id == 'orphan'), isFalse);
      final rec = list.firstWhere((s) => s.id == '9001');
      expect(rec.kind, 'recording');
      expect(rec.path, 'recording_9001.muse.feedback');
      expect(list.firstWhere((s) => s.id == 'fb1').kind, 'feedback');
    },
  );

  test('delete recording uses sqlite path not session_\$id', () async {
    final tmp = await Directory.systemTemp.createTemp('muse_hist_del_');
    addTearDown(() => tmp.delete(recursive: true));
    final storage = FileSystemSessionStorage(tmp);
    final cacheDir = await resolveSessionCacheDir(storage);
    final sqlite = await SessionSqlite.open(cacheDirectory: cacheDir);
    final recStore = RecordingStore(storage: storage, sqlite: sqlite);

    final scratch = scratchDirectory(storage);
    await scratch.create(recursive: true);
    final scratchV5 = await writeScratchV5(
      dir: scratch,
      id: '8008',
      prefix: 'recording',
      metadataJson: _recordingMeta().toJson(),
      rawBody: const [1, 2, 3, 4],
      computedJsonl: const [],
    );
    await recStore.publish(scratchV5);
    sqlite.close();

    final published = File('${tmp.path}/recording_8008.muse.feedback');
    expect(published.existsSync(), isTrue);

    final store = SessionStore(storage: Future.value(storage));
    expect(await store.delete('8008'), isTrue);
    expect(published.existsSync(), isFalse);
    expect(
      File('${tmp.path}/session_8008.muse.feedback').existsSync(),
      isFalse,
    );
    final after = await store.list();
    expect(after.any((s) => s.id == '8008'), isFalse);
  });

  test('moveAllTo copies session_ and recording_ containers', () async {
    final srcDir = await Directory.systemTemp.createTemp('muse_move_src_');
    final dstDir = await Directory.systemTemp.createTemp('muse_move_dst_');
    addTearDown(() => srcDir.delete(recursive: true));
    addTearDown(() => dstDir.delete(recursive: true));
    final src = FileSystemSessionStorage(srcDir);
    final dst = FileSystemSessionStorage(dstDir);
    await src.writeFileAtomic('session_1.muse.feedback', const [1, 2]);
    await src.writeFileAtomic('recording_2.muse.feedback', const [3, 4]);
    await src.writeFileAtomic('tmp_3.muse.feedback', const [5, 6]);

    final store = SessionStore(storage: Future.value(src));
    final moved = await store.moveAllTo(dst);
    expect(moved, 2);
    expect(await dst.fileExists('session_1.muse.feedback'), isTrue);
    expect(await dst.fileExists('recording_2.muse.feedback'), isTrue);
    expect(await dst.fileExists('tmp_3.muse.feedback'), isFalse);
    expect(await src.fileExists('session_1.muse.feedback'), isFalse);
    expect(await src.fileExists('recording_2.muse.feedback'), isFalse);
  });
}

RecordingMetadata _recordingMeta() => RecordingMetadata(
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
