import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/feedback/session_sqlite.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/monitor/recording/crash_recovery.dart';
import 'package:muse_ml/src/monitor/recording/recording_metadata.dart';
import 'package:muse_ml/src/monitor/recording/recording_store.dart';
import 'package:muse_ml/src/rust/frb_generated.dart';
import 'package:muse_ml/src/session_v5/assemble.dart';
import 'package:muse_ml/src/session_v5/models.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:sqlite3/sqlite3.dart';

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

SessionRow _feedbackRow(String id) {
  final now = DateTime.utc(2026, 1, 1);
  return SessionRow(
    id: id,
    path: 'session_$id.muse.feedback',
    formatVersion: 5,
    appVersion: 'dev',
    savedAt: now,
    startedAt: now,
    durationS: 30,
    protocol: 'drowsiness',
    recordedChannels: 'TP9,AF7,AF8,TP10',
    recordedStreams: 'eeg',
    offMeta: 0,
    lenMeta: 0,
    offComputed: 0,
    lenComputed: 0,
    offRaw: 0,
    lenRaw: 0,
    markerCount: 0,
    fileSize: 4,
    mtime: now.millisecondsSinceEpoch,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init(externalLibrary: ExternalLibrary.open(_rustLibPath));
  });

  late Directory history;
  late Directory scratch;
  late SessionStorage storage;
  late SessionSqlite sqlite;
  late RecordingStore store;

  setUp(() async {
    history = await Directory.systemTemp.createTemp('muse_rec_store_');
    storage = FileSystemSessionStorage(history);
    scratch = scratchDirectory(storage);
    await scratch.create(recursive: true);
    sqlite = await SessionSqlite.open(cacheDirectory: scratch);
    store = RecordingStore(storage: storage, sqlite: sqlite);
  });

  tearDown(() async {
    sqlite.close();
    if (await history.exists()) {
      await history.delete(recursive: true);
    }
  });

  test('publish upserts kind=recording; existing rows stay feedback', () async {
    await sqlite.upsertSession(_feedbackRow('oldfb'));

    final scratchV5 = await writeScratchV5(
      dir: scratch,
      id: '3003',
      prefix: 'recording',
      metadataJson: _meta().toJson(),
      rawBody: const [1, 2, 3, 4],
      computedJsonl: const [],
    );
    await File('${scratch.path}/recording_3003.raw').writeAsBytes([9]);

    await store.publish(scratchV5);

    expect(scratchV5.existsSync(), isFalse);
    expect(File('${scratch.path}/recording_3003.raw').existsSync(), isFalse);
    final published = File('${history.path}/recording_3003.muse.feedback');
    expect(published.existsSync(), isTrue);

    final rec = await sqlite.getSession('3003');
    expect(rec, isNotNull);
    expect(rec!.kind, 'recording');
    expect(rec.protocol, isEmpty);
    expect(rec.path, 'recording_3003.muse.feedback');
    expect(rec.deviceId, 'sim:muse-2');

    final fb = await sqlite.getSession('oldfb');
    expect(fb, isNotNull);
    expect(fb!.kind, 'feedback');
    expect(fb.protocol, 'drowsiness');
  });

  test('discard deletes scratch and does not upsert', () async {
    final scratchV5 = await writeScratchV5(
      dir: scratch,
      id: '4004',
      prefix: 'recording',
      metadataJson: _meta().toJson(),
      rawBody: const [1, 2, 3, 4],
      computedJsonl: const [],
    );
    await File('${scratch.path}/recording_4004.json').writeAsString('{}');

    await store.discard(scratchV5);

    expect(scratchV5.existsSync(), isFalse);
    expect(File('${scratch.path}/recording_4004.json').existsSync(), isFalse);
    expect(await sqlite.getSession('4004'), isNull);
    expect(
      File('${history.path}/recording_4004.muse.feedback').existsSync(),
      isFalse,
    );
  });

  test('ALTER TABLE migrates existing rows to kind=feedback', () async {
    final dir = await Directory.systemTemp.createTemp('muse_kind_mig_');
    addTearDown(() => dir.delete(recursive: true));
    final dbPath = '${dir.path}/session_metadata.db';
    final raw = sqlite3.open(dbPath);
    raw.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY NOT NULL,
        path TEXT NOT NULL UNIQUE,
        format_version INTEGER NOT NULL DEFAULT 5,
        app_version TEXT NOT NULL,
        saved_at TEXT NOT NULL,
        started_at TEXT NOT NULL,
        duration_s INTEGER NOT NULL,
        protocol TEXT NOT NULL,
        protocol_version TEXT,
        device_name TEXT,
        device_model TEXT,
        device_id TEXT,
        calibration_profile TEXT,
        recorded_channels TEXT NOT NULL,
        recorded_streams TEXT NOT NULL,
        off_meta INTEGER NOT NULL,
        len_meta INTEGER NOT NULL,
        off_computed INTEGER NOT NULL,
        len_computed INTEGER NOT NULL,
        off_raw INTEGER NOT NULL,
        len_raw INTEGER NOT NULL,
        avg_hr REAL,
        avg_spo2 REAL,
        peak_alpha_hz REAL,
        peak_alpha_power REAL,
        pct_in_target REAL,
        avg_movement REAL,
        guardrail_warn_count INTEGER,
        avg_sleep_dir REAL,
        signal_quality_mean REAL,
        pct_qc_ok REAL,
        marker_count INTEGER DEFAULT 0,
        guardrail_engine TEXT,
        model_kind TEXT,
        model_sha256 TEXT,
        feedback_engine TEXT,
        user_id TEXT,
        session_id TEXT,
        notes_preview TEXT,
        file_size INTEGER NOT NULL,
        mtime INTEGER NOT NULL,
        thumbnail BLOB,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000)
      )
    ''');
    raw.execute('''
      INSERT INTO sessions (
        id, path, format_version, app_version, saved_at, started_at, duration_s,
        protocol, recorded_channels, recorded_streams,
        off_meta, len_meta, off_computed, len_computed, off_raw, len_raw,
        file_size, mtime
      ) VALUES (
        'legacy', 'session_legacy.muse.feedback', 5, 'dev',
        '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 10,
        'drowsiness', 'TP9,AF7,AF8,TP10', 'eeg',
        0, 0, 0, 0, 0, 0,
        1, 0
      )
    ''');
    raw.dispose();

    final migrated = await SessionSqlite.open(cacheDirectory: dir);
    addTearDown(migrated.close);
    final row = await migrated.getSession('legacy');
    expect(row, isNotNull);
    expect(row!.kind, 'feedback');
    expect(row.protocol, 'drowsiness');
  });
}
