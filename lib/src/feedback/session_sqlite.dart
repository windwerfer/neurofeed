/// SQLite implementation for session metadata cache (NFED6).
///
/// Replaces the file-based cache with a proper SQLite database.
/// Sessions table has typed columns for fast sort/filter without JSON parsing.
/// Markers table stores user/gesture markers for self-labeling.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:path_provider/path_provider.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';

/// Resolves the cache directory for the session metadata SQLite database.
/// - Linux/Windows/macOS: `.cache` subfolder of the history folder
/// - Android: `getApplicationCacheDirectory()` (app cache folder)
/// - iOS: `getApplicationCacheDirectory()` (app cache folder)
Future<Directory> resolveSessionCacheDir(SessionStorage history) async {
  if (Platform.isAndroid || Platform.isIOS) {
    return await getApplicationCacheDirectory();
  }
  // Linux/Windows/macOS: use .cache subfolder of history folder
  if (history is FileSystemSessionStorage) {
    return Directory('${history.location}${Platform.pathSeparator}.cache');
  }
  // SAF on non-Android (unlikely) - fallback to app cache
  return await getApplicationCacheDirectory();
}

/// Singleton SQLite database for session metadata.
class SessionSqlite {
  SessionSqlite._(this._db);

  static const int kSchemaUserVersion = 2;

  static Future<SessionSqlite> open({required Directory cacheDirectory}) async {
    // Initialize native sqlite3 for Flutter (workaround for old Android versions)
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();

    // Ensure cache directory exists
    if (!await cacheDirectory.exists()) {
      await cacheDirectory.create(recursive: true);
    }

    final dbPath = p.join(cacheDirectory.path, 'session_metadata.db');
    final db = sqlite3.open(dbPath);

    final instance = SessionSqlite._(db);
    await instance._initSchema();
    return instance;
  }

  final Database _db;

  Database get db => _db;

  /// Set when open wiped the sessions table for a schema bump. SessionStore
  /// consumes this to trigger a one-shot reindex from disk.
  bool _needsReindex = false;

  bool get needsReindex => _needsReindex;

  /// Clear the one-shot reindex flag (after SessionStore schedules backfill).
  bool consumeNeedsReindex() {
    final v = _needsReindex;
    _needsReindex = false;
    return v;
  }

  Future<void> _initSchema() async {
    // Wipe before CREATE INDEX — a legacy sessions table may lack new columns.
    final existing = _db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='sessions'",
    );
    if (existing.isNotEmpty && !_hasColumn('experimental_scalars')) {
      // Clean cut: wipe and recreate full schema (no ALTER-add migration).
      _db.execute('DROP TABLE IF EXISTS state_markers');
      _db.execute('DROP TABLE IF EXISTS sessions');
      _needsReindex = true;
    }
    _createTables();
    _db.execute('PRAGMA user_version = $kSchemaUserVersion');
  }

  bool _hasColumn(String name) {
    final cols = _db.select('PRAGMA table_info(sessions)');
    return cols.any((r) => r['name'] == name);
  }

  void _createTables() {
    _db.execute(
      r"""
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY NOT NULL,
        path TEXT NOT NULL UNIQUE,
        format_version INTEGER NOT NULL DEFAULT 6,
        app_version TEXT NOT NULL,
        saved_at TEXT NOT NULL,
        started_at TEXT NOT NULL,
        duration_s INTEGER NOT NULL,
        protocol TEXT NOT NULL,
        kind TEXT NOT NULL DEFAULT 'feedback',
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
        hr_min REAL,
        hr_max REAL,
        avg_spo2 REAL,
        spo2_min REAL,
        spo2_max REAL,
        peak_alpha_hz REAL,
        peak_alpha_power REAL,
        peak_alpha_mean_hz REAL,
        pct_in_target REAL,
        avg_movement REAL,
        stillness_pct REAL,
        guardrail_warn_count INTEGER,
        avg_sleep_dir REAL,
        avg_alpha_rel REAL,
        guard_warn_pct REAL,
        guard_threshold REAL,
        signal_quality_mean REAL,
        pct_qc_ok REAL,
        quality_channel_usable TEXT,
        annotation_pause_s REAL,
        annotation_bad_quality_s REAL,
        annotation_disconnect_s REAL,
        battery_start_pct REAL,
        battery_end_pct REAL,
        experimental_scalars TEXT,
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
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000),
        time_zone TEXT,
        saved_at_ms INTEGER
      )
""",
    );
    _db.execute('CREATE INDEX IF NOT EXISTS idx_sessions_saved_at ON sessions(saved_at DESC)');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_sessions_started_at ON sessions(started_at DESC)');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_sessions_protocol ON sessions(protocol)');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_sessions_device_id ON sessions(device_id)');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id)');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_sessions_guardrail_engine ON sessions(guardrail_engine)');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_sessions_session_id ON sessions(session_id)');

    _db.execute(
      r"""
      CREATE TABLE IF NOT EXISTS state_markers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        t REAL NOT NULL,
        source TEXT NOT NULL,
        label TEXT,
        confidence INTEGER CHECK (confidence IS NULL OR (confidence BETWEEN 0 AND 10)),
        intensity INTEGER,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000)
      )
""",
    );
    _db.execute('CREATE INDEX IF NOT EXISTS idx_state_markers_session_t ON state_markers(session_id, t)');
  }
  /// Insert or replace a session row.
  Future<void> upsertSession(SessionRow row) async {
    _db.execute('''
      INSERT INTO sessions (
        id, path, format_version, app_version, saved_at, started_at, duration_s,
        protocol, kind, protocol_version, device_name, device_model, device_id,
        calibration_profile, recorded_channels, recorded_streams,
        off_meta, len_meta, off_computed, len_computed, off_raw, len_raw,
        avg_hr, hr_min, hr_max, avg_spo2, spo2_min, spo2_max,
        peak_alpha_hz, peak_alpha_power, peak_alpha_mean_hz,
        pct_in_target, avg_movement, stillness_pct,
        guardrail_warn_count, avg_sleep_dir, avg_alpha_rel, guard_warn_pct, guard_threshold,
        signal_quality_mean, pct_qc_ok, quality_channel_usable,
        annotation_pause_s, annotation_bad_quality_s, annotation_disconnect_s,
        battery_start_pct, battery_end_pct, experimental_scalars,
        marker_count,
        guardrail_engine, model_kind, model_sha256, feedback_engine,
        user_id, session_id, notes_preview,
        file_size, mtime, thumbnail, created_at, updated_at,
        time_zone, saved_at_ms
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        path = excluded.path,
        format_version = excluded.format_version,
        app_version = excluded.app_version,
        saved_at = excluded.saved_at,
        started_at = excluded.started_at,
        duration_s = excluded.duration_s,
        protocol = excluded.protocol,
        kind = excluded.kind,
        protocol_version = excluded.protocol_version,
        device_name = excluded.device_name,
        device_model = excluded.device_model,
        device_id = excluded.device_id,
        calibration_profile = excluded.calibration_profile,
        recorded_channels = excluded.recorded_channels,
        recorded_streams = excluded.recorded_streams,
        off_meta = excluded.off_meta,
        len_meta = excluded.len_meta,
        off_computed = excluded.off_computed,
        len_computed = excluded.len_computed,
        off_raw = excluded.off_raw,
        len_raw = excluded.len_raw,
        avg_hr = excluded.avg_hr,
        hr_min = excluded.hr_min,
        hr_max = excluded.hr_max,
        avg_spo2 = excluded.avg_spo2,
        spo2_min = excluded.spo2_min,
        spo2_max = excluded.spo2_max,
        peak_alpha_hz = excluded.peak_alpha_hz,
        peak_alpha_power = excluded.peak_alpha_power,
        peak_alpha_mean_hz = excluded.peak_alpha_mean_hz,
        pct_in_target = excluded.pct_in_target,
        avg_movement = excluded.avg_movement,
        stillness_pct = excluded.stillness_pct,
        guardrail_warn_count = excluded.guardrail_warn_count,
        avg_sleep_dir = excluded.avg_sleep_dir,
        avg_alpha_rel = excluded.avg_alpha_rel,
        guard_warn_pct = excluded.guard_warn_pct,
        guard_threshold = excluded.guard_threshold,
        signal_quality_mean = excluded.signal_quality_mean,
        pct_qc_ok = excluded.pct_qc_ok,
        quality_channel_usable = excluded.quality_channel_usable,
        annotation_pause_s = excluded.annotation_pause_s,
        annotation_bad_quality_s = excluded.annotation_bad_quality_s,
        annotation_disconnect_s = excluded.annotation_disconnect_s,
        battery_start_pct = excluded.battery_start_pct,
        battery_end_pct = excluded.battery_end_pct,
        experimental_scalars = excluded.experimental_scalars,
        marker_count = excluded.marker_count,
        guardrail_engine = excluded.guardrail_engine,
        model_kind = excluded.model_kind,
        model_sha256 = excluded.model_sha256,
        feedback_engine = excluded.feedback_engine,
        user_id = excluded.user_id,
        session_id = excluded.session_id,
        notes_preview = excluded.notes_preview,
        file_size = excluded.file_size,
        mtime = excluded.mtime,
        thumbnail = excluded.thumbnail,
        updated_at = excluded.updated_at,
        time_zone = excluded.time_zone,
        saved_at_ms = excluded.saved_at_ms
    ''', row.toList());
  }

  /// Get a session by id.
  Future<SessionRow?> getSession(String id) async {
    final result = _db.select('SELECT * FROM sessions WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return SessionRow.fromRow(result.first);
  }

  /// List all sessions, newest first.
  Future<List<SessionRow>> listSessions() async {
    final result = _db.select('SELECT * FROM sessions ORDER BY COALESCE(saved_at_ms, 0) DESC, saved_at DESC');
    return result.map((r) => SessionRow.fromRow(r)).toList();
  }

  /// Delete a session and its markers.
  Future<void> deleteSession(String id) async {
    _db.execute('DELETE FROM state_markers WHERE session_id = ?', [id]);
    _db.execute('DELETE FROM sessions WHERE id = ?', [id]);
  }

  /// Insert or replace markers for a session.
  Future<void> upsertMarkers(String sessionId, List<MarkerRow> markers) async {
    for (final m in markers) {
      _db.execute('''
        INSERT INTO state_markers (session_id, t, source, label, confidence, intensity, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, strftime('%s','now') * 1000)
        ON CONFLICT(id) DO UPDATE SET
          t = excluded.t,
          source = excluded.source,
          label = excluded.label,
          confidence = excluded.confidence,
          intensity = excluded.intensity,
          updated_at = excluded.updated_at
      ''', [m.sessionId, m.t, m.source, m.label, m.confidence, m.intensity]);
    }
  }

  /// Get markers for a session.
  Future<List<MarkerRow>> getMarkers(String sessionId) async {
    final result = _db.select(
      'SELECT * FROM state_markers WHERE session_id = ? ORDER BY t',
      [sessionId],
    );
    return result.map((r) => MarkerRow.fromRow(r)).toList();
  }

  /// Delete markers for a session.
  Future<void> deleteMarkers(String sessionId) async {
    _db.execute('DELETE FROM state_markers WHERE session_id = ?', [sessionId]);
  }

  void close() => _db.dispose();
}
/// Row for sessions table.
class SessionRow {
  final String id;
  final String path;
  final int formatVersion;
  final String appVersion;
  final DateTime savedAt;
  final DateTime startedAt;
  final int durationS;
  final String protocol;
  /// `feedback` or `recording`. Existing rows migrate to `feedback`.
  final String kind;
  final String? protocolVersion;
  final String? deviceName;
  final String? deviceModel;
  final String? deviceId;
  final String? calibrationProfile;
  final String recordedChannels;
  final String recordedStreams;
  final int offMeta;
  final int lenMeta;
  final int offComputed;
  final int lenComputed;
  final int offRaw;
  final int lenRaw;
  final double? avgHr;
  final double? hrMin;
  final double? hrMax;
  final double? avgSpo2;
  final double? spo2Min;
  final double? spo2Max;
  final double? peakAlphaHz;
  final double? peakAlphaPower;
  final double? peakAlphaMeanHz;
  final double? pctInTarget;
  final double? avgMovement;
  final double? stillnessPct;
  final int? guardrailWarnCount;
  final double? avgSleepDir;
  final double? avgAlphaRel;
  final double? guardWarnPct;
  final double? guardThreshold;
  final double? signalQualityMean;
  final double? pctQcOk;
  final String? qualityChannelUsable;
  final double? annotationPauseS;
  final double? annotationBadQualityS;
  final double? annotationDisconnectS;
  final double? batteryStartPct;
  final double? batteryEndPct;
  final String? experimentalScalars;
  final int markerCount;
  final String? guardrailEngine;
  final String? modelKind;
  final String? modelSha256;
  final String? feedbackEngine;
  final String? userId;
  final String? sessionId;
  final String? notesPreview;
  final int fileSize;
  final int mtime;
  final Uint8List? thumbnail;
  final DateTime createdAt;
  final DateTime updatedAt;
  /// IANA id for wall-clock display (v6).
  final String? timeZone;
  /// UTC epoch ms for list sorting (v6).
  final int? savedAtMs;

  SessionRow({
    required this.id,
    required this.path,
    required this.formatVersion,
    required this.appVersion,
    required this.savedAt,
    required this.startedAt,
    required this.durationS,
    required this.protocol,
    this.kind = 'feedback',
    this.protocolVersion,
    this.deviceName,
    this.deviceModel,
    this.deviceId,
    this.calibrationProfile,
    required this.recordedChannels,
    required this.recordedStreams,
    required this.offMeta,
    required this.lenMeta,
    required this.offComputed,
    required this.lenComputed,
    required this.offRaw,
    required this.lenRaw,
    this.avgHr,
    this.hrMin,
    this.hrMax,
    this.avgSpo2,
    this.spo2Min,
    this.spo2Max,
    this.peakAlphaHz,
    this.peakAlphaPower,
    this.peakAlphaMeanHz,
    this.pctInTarget,
    this.avgMovement,
    this.stillnessPct,
    this.guardrailWarnCount,
    this.avgSleepDir,
    this.avgAlphaRel,
    this.guardWarnPct,
    this.guardThreshold,
    this.signalQualityMean,
    this.pctQcOk,
    this.qualityChannelUsable,
    this.annotationPauseS,
    this.annotationBadQualityS,
    this.annotationDisconnectS,
    this.batteryStartPct,
    this.batteryEndPct,
    this.experimentalScalars,
    required this.markerCount,
    this.guardrailEngine,
    this.modelKind,
    this.modelSha256,
    this.feedbackEngine,
    this.userId,
    this.sessionId,
    this.notesPreview,
    required this.fileSize,
    required this.mtime,
    this.thumbnail,
    required this.createdAt,
    required this.updatedAt,
    this.timeZone,
    this.savedAtMs,
  });

  SessionRow copyWith({
    String? notesPreview,
    int? fileSize,
    int? mtime,
    DateTime? updatedAt,
    Uint8List? thumbnail,
  }) {
    return SessionRow(
      id: id,
      path: path,
      formatVersion: formatVersion,
      appVersion: appVersion,
      savedAt: savedAt,
      startedAt: startedAt,
      durationS: durationS,
      protocol: protocol,
      kind: kind,
      protocolVersion: protocolVersion,
      deviceName: deviceName,
      deviceModel: deviceModel,
      deviceId: deviceId,
      calibrationProfile: calibrationProfile,
      recordedChannels: recordedChannels,
      recordedStreams: recordedStreams,
      offMeta: offMeta,
      lenMeta: lenMeta,
      offComputed: offComputed,
      lenComputed: lenComputed,
      offRaw: offRaw,
      lenRaw: lenRaw,
      avgHr: avgHr,
      hrMin: hrMin,
      hrMax: hrMax,
      avgSpo2: avgSpo2,
      spo2Min: spo2Min,
      spo2Max: spo2Max,
      peakAlphaHz: peakAlphaHz,
      peakAlphaPower: peakAlphaPower,
      peakAlphaMeanHz: peakAlphaMeanHz,
      pctInTarget: pctInTarget,
      avgMovement: avgMovement,
      stillnessPct: stillnessPct,
      guardrailWarnCount: guardrailWarnCount,
      avgSleepDir: avgSleepDir,
      avgAlphaRel: avgAlphaRel,
      guardWarnPct: guardWarnPct,
      guardThreshold: guardThreshold,
      signalQualityMean: signalQualityMean,
      pctQcOk: pctQcOk,
      qualityChannelUsable: qualityChannelUsable,
      annotationPauseS: annotationPauseS,
      annotationBadQualityS: annotationBadQualityS,
      annotationDisconnectS: annotationDisconnectS,
      batteryStartPct: batteryStartPct,
      batteryEndPct: batteryEndPct,
      experimentalScalars: experimentalScalars,
      markerCount: markerCount,
      guardrailEngine: guardrailEngine,
      modelKind: modelKind,
      modelSha256: modelSha256,
      feedbackEngine: feedbackEngine,
      userId: userId,
      sessionId: sessionId,
      notesPreview: notesPreview ?? this.notesPreview,
      fileSize: fileSize ?? this.fileSize,
      mtime: mtime ?? this.mtime,
      thumbnail: thumbnail ?? this.thumbnail,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      timeZone: timeZone,
      savedAtMs: savedAtMs,
    );
  }

  List<Object?> toList() => [
    id, path, formatVersion, appVersion,
    savedAt.toUtc().toIso8601String(), startedAt.toUtc().toIso8601String(),
    durationS, protocol, kind, protocolVersion, deviceName, deviceModel, deviceId,
    calibrationProfile, recordedChannels, recordedStreams,
    offMeta, lenMeta, offComputed, lenComputed, offRaw, lenRaw,
    avgHr, hrMin, hrMax, avgSpo2, spo2Min, spo2Max,
    peakAlphaHz, peakAlphaPower, peakAlphaMeanHz,
    pctInTarget, avgMovement, stillnessPct,
    guardrailWarnCount, avgSleepDir, avgAlphaRel, guardWarnPct, guardThreshold,
    signalQualityMean, pctQcOk, qualityChannelUsable,
    annotationPauseS, annotationBadQualityS, annotationDisconnectS,
    batteryStartPct, batteryEndPct, experimentalScalars,
    markerCount,
    guardrailEngine, modelKind, modelSha256, feedbackEngine,
    userId, sessionId, notesPreview,
    fileSize, mtime, thumbnail,
    createdAt.millisecondsSinceEpoch, updatedAt.millisecondsSinceEpoch,
    timeZone, savedAtMs,
  ];

  static SessionRow fromRow(Row row) {
    DateTime parseDt(dynamic v) => v is int
        ? DateTime.fromMillisecondsSinceEpoch(v)
        : DateTime.parse(v as String);

    return SessionRow(
      id: row['id'] as String,
      path: row['path'] as String,
      formatVersion: row['format_version'] as int,
      appVersion: row['app_version'] as String,
      savedAt: parseDt(row['saved_at']),
      startedAt: parseDt(row['started_at']),
      durationS: row['duration_s'] as int,
      protocol: row['protocol'] as String,
      kind: row['kind'] as String? ?? 'feedback',
      protocolVersion: row['protocol_version'] as String?,
      deviceName: row['device_name'] as String?,
      deviceModel: row['device_model'] as String?,
      deviceId: row['device_id'] as String?,
      calibrationProfile: row['calibration_profile'] as String?,
      recordedChannels: row['recorded_channels'] as String,
      recordedStreams: row['recorded_streams'] as String,
      offMeta: row['off_meta'] as int,
      lenMeta: row['len_meta'] as int,
      offComputed: row['off_computed'] as int,
      lenComputed: row['len_computed'] as int,
      offRaw: row['off_raw'] as int,
      lenRaw: row['len_raw'] as int,
      avgHr: (row['avg_hr'] as num?)?.toDouble(),
      hrMin: (row['hr_min'] as num?)?.toDouble(),
      hrMax: (row['hr_max'] as num?)?.toDouble(),
      avgSpo2: (row['avg_spo2'] as num?)?.toDouble(),
      spo2Min: (row['spo2_min'] as num?)?.toDouble(),
      spo2Max: (row['spo2_max'] as num?)?.toDouble(),
      peakAlphaHz: (row['peak_alpha_hz'] as num?)?.toDouble(),
      peakAlphaPower: (row['peak_alpha_power'] as num?)?.toDouble(),
      peakAlphaMeanHz: (row['peak_alpha_mean_hz'] as num?)?.toDouble(),
      pctInTarget: (row['pct_in_target'] as num?)?.toDouble(),
      avgMovement: (row['avg_movement'] as num?)?.toDouble(),
      stillnessPct: (row['stillness_pct'] as num?)?.toDouble(),
      guardrailWarnCount: (row['guardrail_warn_count'] as num?)?.toInt(),
      avgSleepDir: (row['avg_sleep_dir'] as num?)?.toDouble(),
      avgAlphaRel: (row['avg_alpha_rel'] as num?)?.toDouble(),
      guardWarnPct: (row['guard_warn_pct'] as num?)?.toDouble(),
      guardThreshold: (row['guard_threshold'] as num?)?.toDouble(),
      signalQualityMean: (row['signal_quality_mean'] as num?)?.toDouble(),
      pctQcOk: (row['pct_qc_ok'] as num?)?.toDouble(),
      qualityChannelUsable: row['quality_channel_usable'] as String?,
      annotationPauseS: (row['annotation_pause_s'] as num?)?.toDouble(),
      annotationBadQualityS: (row['annotation_bad_quality_s'] as num?)?.toDouble(),
      annotationDisconnectS: (row['annotation_disconnect_s'] as num?)?.toDouble(),
      batteryStartPct: (row['battery_start_pct'] as num?)?.toDouble(),
      batteryEndPct: (row['battery_end_pct'] as num?)?.toDouble(),
      experimentalScalars: row['experimental_scalars'] as String?,
      markerCount: row['marker_count'] as int,
      guardrailEngine: row['guardrail_engine'] as String?,
      modelKind: row['model_kind'] as String?,
      modelSha256: row['model_sha256'] as String?,
      feedbackEngine: row['feedback_engine'] as String?,
      userId: row['user_id'] as String?,
      sessionId: row['session_id'] as String?,
      notesPreview: row['notes_preview'] as String?,
      fileSize: row['file_size'] as int,
      mtime: row['mtime'] as int,
      thumbnail: row['thumbnail'] as Uint8List?,
      createdAt: parseDt(row['created_at']),
      updatedAt: parseDt(row['updated_at']),
      timeZone: row['time_zone'] as String?,
      savedAtMs: (row['saved_at_ms'] as num?)?.toInt(),
    );
  }
}

/// Row for state_markers table.
class MarkerRow {
  final int? id;
  final String sessionId;
  final double t;
  final String source;
  final String? label;
  final int? confidence;
  final int? intensity;
  final DateTime createdAt;
  final DateTime updatedAt;

  MarkerRow({
    this.id,
    required this.sessionId,
    required this.t,
    required this.source,
    this.label,
    this.confidence,
    this.intensity,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  List<Object?> toList() => [
    sessionId, t, source, label, confidence, intensity,
  ];

  static MarkerRow fromRow(Row row) => MarkerRow(
    id: row['id'] as int?,
    sessionId: row['session_id'] as String,
    t: (row['t'] as num).toDouble(),
    source: row['source'] as String,
    label: row['label'] as String?,
    confidence: row['confidence'] as int?,
    intensity: row['intensity'] as int?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
  );
}
