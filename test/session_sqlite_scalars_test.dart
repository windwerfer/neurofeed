import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/session_scalars.dart';
import 'package:neurofeed/src/feedback/session_sqlite.dart';
import 'package:sqlite3/sqlite3.dart';

SessionRow _row({
  required String id,
  double? avgHr,
  double? hrMin,
  double? hrMax,
  double? avgSpo2,
  double? spo2Min,
  double? spo2Max,
  double? peakAlphaHz,
  double? peakAlphaPower,
  double? peakAlphaMeanHz,
  double? stillnessPct,
  String? qualityChannelUsable,
  double? annotationPauseS,
  double? batteryStartPct,
  double? avgAlphaRel,
  double? guardWarnPct,
  double? guardThreshold,
  String? experimentalScalars,
}) {
  final now = DateTime.utc(2026, 9, 24, 12);
  return SessionRow(
    id: id,
    path: 'session_$id.neurofeed',
    formatVersion: 6,
    appVersion: 'dev',
    savedAt: now,
    startedAt: now,
    durationS: 60,
    protocol: 'drowsiness',
    recordedChannels: 'TP9,AF7,AF8,TP10',
    recordedStreams: '',
    offMeta: 0,
    lenMeta: 0,
    offComputed: 0,
    lenComputed: 0,
    offRaw: 0,
    lenRaw: 0,
    avgHr: avgHr,
    hrMin: hrMin,
    hrMax: hrMax,
    avgSpo2: avgSpo2,
    spo2Min: spo2Min,
    spo2Max: spo2Max,
    peakAlphaHz: peakAlphaHz,
    peakAlphaPower: peakAlphaPower,
    peakAlphaMeanHz: peakAlphaMeanHz,
    stillnessPct: stillnessPct,
    qualityChannelUsable: qualityChannelUsable,
    annotationPauseS: annotationPauseS,
    batteryStartPct: batteryStartPct,
    avgAlphaRel: avgAlphaRel,
    guardWarnPct: guardWarnPct,
    guardThreshold: guardThreshold,
    experimentalScalars: experimentalScalars,
    markerCount: 0,
    fileSize: 10,
    mtime: now.millisecondsSinceEpoch,
    createdAt: now,
    updatedAt: now,
    timeZone: 'Asia/Bangkok',
    savedAtMs: now.millisecondsSinceEpoch,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SessionRowScalars.fromV6Metadata maps nested stats + outcome', () {
    final scalars = SessionRowScalars.fromV6Metadata({
      'stats': {
        'hr': {'mean': 68.0, 'min': 50.0, 'max': 90.0},
        'spo2': {'mean': 98.0, 'min': 96.0, 'max': 99.0},
        'peakAlpha': {
          'meanHz': 10.1,
          'maxPowerHz': 10.4,
          'maxPower': 5.2,
        },
        'movement': {'mean': 0.02, 'stillnessPct': 70.0},
        'quality': {
          'mean': 86.0,
          'pctGood': 92.0,
          'channelUsable': {'TP9': 0.9, 'AF7': 0.8},
        },
        'annotationSeconds': {
          'pause': 10.0,
          'bad_quality': 5.0,
          'disconnect': 2.0,
        },
        'battery': {'startPct': 80.0, 'endPct': 75.0},
        'experimental': {
          'bands': {'meanAlphaAbs': 4.6},
        },
      },
      'feedback': {
        'outcomeScalars': {
          'pctInTarget': 62.0,
          'avgAlphaRel': 0.42,
          'guardrailWarnCount': 3,
          'guardWarnPct': 12.5,
          'avgSleepDir': 0.34,
          'guardThreshold': 0.55,
        },
      },
    });

    expect(scalars.avgHr, 68.0);
    expect(scalars.hrMin, 50.0);
    expect(scalars.hrMax, 90.0);
    expect(scalars.avgSpo2, 98.0);
    expect(scalars.peakAlphaHz, 10.4);
    expect(scalars.peakAlphaMeanHz, 10.1);
    expect(scalars.stillnessPct, 70.0);
    expect(scalars.pctQcOk, 92.0);
    expect(jsonDecode(scalars.qualityChannelUsable!), {'TP9': 0.9, 'AF7': 0.8});
    expect(scalars.annotationPauseS, 10.0);
    expect(scalars.batteryStartPct, 80.0);
    expect(scalars.avgAlphaRel, 0.42);
    expect(scalars.guardWarnPct, 12.5);
    expect(scalars.guardThreshold, 0.55);
    expect(jsonDecode(scalars.experimentalScalars!), {
      'bands': {'meanAlphaAbs': 4.6},
    });
  });

  test('SessionRow round-trip of new scalar columns + experimental JSON', () async {
    final tmp = await Directory.systemTemp.createTemp('nf_sqlite_scalars_');
    addTearDown(() => tmp.delete(recursive: true));

    final db = await SessionSqlite.open(cacheDirectory: tmp);
    addTearDown(db.close);

    final experimental = jsonEncode({
      'bands': {'meanAlphaAbs': 4.6, 'meanAlphaRel': 0.31},
    });
    final channelUsable = jsonEncode({'TP9': 0.94, 'AF7': 0.88});

    await db.upsertSession(
      _row(
        id: 'rt1',
        avgHr: 70,
        hrMin: 55,
        hrMax: 88,
        avgSpo2: 97.5,
        spo2Min: 95,
        spo2Max: 99,
        peakAlphaHz: 10.4,
        peakAlphaPower: 5.0,
        peakAlphaMeanHz: 10.0,
        stillnessPct: 71,
        qualityChannelUsable: channelUsable,
        annotationPauseS: 12,
        batteryStartPct: 81,
        avgAlphaRel: 0.4,
        guardWarnPct: 11,
        guardThreshold: 0.5,
        experimentalScalars: experimental,
      ),
    );

    final got = await db.getSession('rt1');
    expect(got, isNotNull);
    expect(got!.avgHr, 70);
    expect(got.hrMin, 55);
    expect(got.hrMax, 88);
    expect(got.avgSpo2, 97.5);
    expect(got.spo2Min, 95);
    expect(got.spo2Max, 99);
    expect(got.peakAlphaHz, 10.4);
    expect(got.peakAlphaPower, 5.0);
    expect(got.peakAlphaMeanHz, 10.0);
    expect(got.stillnessPct, 71);
    expect(got.qualityChannelUsable, channelUsable);
    expect(got.annotationPauseS, 12);
    expect(got.batteryStartPct, 81);
    expect(got.avgAlphaRel, 0.4);
    expect(got.guardWarnPct, 11);
    expect(got.guardThreshold, 0.5);
    expect(got.experimentalScalars, experimental);
    expect(got.timeZone, 'Asia/Bangkok');
  });

  test('open wipes legacy schema missing experimental_scalars and recreates', () async {
    final tmp = await Directory.systemTemp.createTemp('nf_sqlite_wipe_');
    addTearDown(() => tmp.delete(recursive: true));

    final dbPath = '${tmp.path}/session_metadata.db';
    final legacy = sqlite3.open(dbPath);
    legacy.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY NOT NULL,
        path TEXT NOT NULL UNIQUE,
        format_version INTEGER NOT NULL DEFAULT 5,
        app_version TEXT NOT NULL,
        saved_at TEXT NOT NULL,
        started_at TEXT NOT NULL,
        duration_s INTEGER NOT NULL,
        protocol TEXT NOT NULL,
        recorded_channels TEXT NOT NULL,
        recorded_streams TEXT NOT NULL,
        off_meta INTEGER NOT NULL,
        len_meta INTEGER NOT NULL,
        off_computed INTEGER NOT NULL,
        len_computed INTEGER NOT NULL,
        off_raw INTEGER NOT NULL,
        len_raw INTEGER NOT NULL,
        avg_hr REAL,
        marker_count INTEGER DEFAULT 0,
        file_size INTEGER NOT NULL,
        mtime INTEGER NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    legacy.execute(
      "INSERT INTO sessions (id, path, format_version, app_version, saved_at, started_at, duration_s, protocol, recorded_channels, recorded_streams, off_meta, len_meta, off_computed, len_computed, off_raw, len_raw, file_size, mtime) VALUES ('old', 'session_old.neurofeed', 5, 'dev', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 1, 'x', '', '', 0, 0, 0, 0, 0, 0, 1, 0)",
    );
    legacy.dispose();

    final db = await SessionSqlite.open(cacheDirectory: tmp);
    addTearDown(db.close);

    expect(db.needsReindex, isTrue);
    final cols = db.db.select('PRAGMA table_info(sessions)');
    final names = {for (final r in cols) r['name'] as String};
    expect(names.contains('experimental_scalars'), isTrue);
    expect(names.contains('hr_min'), isTrue);
    expect(names.contains('avg_alpha_rel'), isTrue);
    // Wipe dropped the legacy row.
    expect(await db.getSession('old'), isNull);
    expect(db.consumeNeedsReindex(), isTrue);
    expect(db.needsReindex, isFalse);

    // Fresh upsert still works on recreated table.
    await db.upsertSession(
      _row(id: 'new', experimentalScalars: '{"bands":{}}'),
    );
    expect((await db.getSession('new'))?.experimentalScalars, '{"bands":{}}');
  });

  test('copyWith preserves new scalar fields', () {
    final row = _row(
      id: 'c1',
      hrMin: 40,
      experimentalScalars: '{"bands":{}}',
      avgAlphaRel: 0.3,
    );
    final next = row.copyWith(notesPreview: 'hi', fileSize: 99);
    expect(next.hrMin, 40);
    expect(next.experimentalScalars, '{"bands":{}}');
    expect(next.avgAlphaRel, 0.3);
    expect(next.notesPreview, 'hi');
    expect(next.fileSize, 99);
  });
}
