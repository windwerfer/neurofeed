/// SQLite implementation for v5 session metadata cache.
///
/// Replaces the file-based cache with a proper SQLite database.
/// Sessions table has typed columns for fast sort/filter without JSON parsing.
/// Markers table stores user/gesture markers for self-labeling.
library;

import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:path_provider/path_provider.dart';

import 'session_metadata.dart';
import 'session_v5_models.dart';

/// Singleton SQLite database for session metadata.
class SessionSqlite {
  SessionSqlite._(this._db);

  static Future<SessionSqlite> open({Directory? inDirectory}) async {
    // Initialize native sqlite3 for Flutter (workaround for old Android versions)
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();

    final dir = inDirectory ?? await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'session_metadata.db');
    final db = sqlite3.open(dbPath);

    final instance = SessionSqlite._(db);
    await instance._initSchema();
    return instance;
  }

  final Database _db;

  Database get db => _db;

  Future<void> _initSchema() async {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
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
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000)
      )
    ''');

    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sessions_saved_at ON sessions(saved_at DESC)
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sessions_started_at ON sessions(started_at DESC)
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sessions_protocol ON sessions(protocol)
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sessions_device_id ON sessions(device_id)
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id)
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sessions_guardrail_engine ON sessions(guardrail_engine)
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sessions_session_id ON sessions(session_id)
    ''');

    _db.execute('''
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
    ''');

    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_state_markers_session_t ON state_markers(session_id, t)
    ''');
  }

  /// Insert or replace a session row.
  Future<void> upsertSession(SessionRow row) async {
    _db.execute('''
      INSERT INTO sessions (
        id, path, format_version, app_version, saved_at, started_at, duration_s,
        protocol, protocol_version, device_name, device_model, device_id,
        calibration_profile, recorded_channels, recorded_streams,
        off_meta, len_meta, off_computed, len_computed, off_raw, len_raw,
        avg_hr, avg_spo2, peak_alpha_hz, peak_alpha_power,
        pct_in_target, avg_movement, guardrail_warn_count, avg_sleep_dir,
        signal_quality_mean, pct_qc_ok, marker_count,
        guardrail_engine, model_kind, model_sha256, feedback_engine,
        user_id, session_id, notes_preview,
        file_size, mtime, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        path = excluded.path,
        format_version = excluded.format_version,
        app_version = excluded.app_version,
        saved_at = excluded.saved_at,
        started_at = excluded.started_at,
        duration_s = excluded.duration_s,
        protocol = excluded.protocol,
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
        avg_spo2 = excluded.avg_spo2,
        peak_alpha_hz = excluded.peak_alpha_hz,
        peak_alpha_power = excluded.peak_alpha_power,
        pct_in_target = excluded.pct_in_target,
        avg_movement = excluded.avg_movement,
        guardrail_warn_count = excluded.guardrail_warn_count,
        avg_sleep_dir = excluded.avg_sleep_dir,
        signal_quality_mean = excluded.signal_quality_mean,
        pct_qc_ok = excluded.pct_qc_ok,
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
        updated_at = excluded.updated_at
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
    final result = _db.select('SELECT * FROM sessions ORDER BY saved_at DESC');
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

  /// Clear all data (for "Clear Cache" button).
  Future<void> clearAll() async {
    _db.execute('DELETE FROM state_markers');
    _db.execute('DELETE FROM sessions');
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
  final double? avgSpo2;
  final double? peakAlphaHz;
  final double? peakAlphaPower;
  final double? pctInTarget;
  final double? avgMovement;
  final int? guardrailWarnCount;
  final double? avgSleepDir;
  final double? signalQualityMean;
  final double? pctQcOk;
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
  final DateTime createdAt;
  final DateTime updatedAt;

  SessionRow({
    required this.id,
    required this.path,
    required this.formatVersion,
    required this.appVersion,
    required this.savedAt,
    required this.startedAt,
    required this.durationS,
    required this.protocol,
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
    this.avgSpo2,
    this.peakAlphaHz,
    this.peakAlphaPower,
    this.pctInTarget,
    this.avgMovement,
    this.guardrailWarnCount,
    this.avgSleepDir,
    this.signalQualityMean,
    this.pctQcOk,
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
    required this.createdAt,
    required this.updatedAt,
  });

  List<Object?> toList() => [
    id, path, formatVersion, appVersion,
    savedAt.toIso8601String(), startedAt.toIso8601String(),
    durationS, protocol, protocolVersion, deviceName, deviceModel, deviceId,
    calibrationProfile, recordedChannels, recordedStreams,
    offMeta, lenMeta, offComputed, lenComputed, offRaw, lenRaw,
    avgHr, avgSpo2, peakAlphaHz, peakAlphaPower,
    pctInTarget, avgMovement, guardrailWarnCount, avgSleepDir,
    signalQualityMean, pctQcOk, markerCount,
    guardrailEngine, modelKind, modelSha256, feedbackEngine,
    userId, sessionId, notesPreview,
    fileSize, mtime,
    createdAt.millisecondsSinceEpoch, updatedAt.millisecondsSinceEpoch,
  ];

  static SessionRow fromRow(Row row) {
    DateTime _dt(dynamic v) => v is int
        ? DateTime.fromMillisecondsSinceEpoch(v)
        : DateTime.parse(v as String);

    return SessionRow(
      id: row['id'] as String,
      path: row['path'] as String,
      formatVersion: row['format_version'] as int,
      appVersion: row['app_version'] as String,
      savedAt: _dt(row['saved_at']),
      startedAt: _dt(row['started_at']),
      durationS: row['duration_s'] as int,
      protocol: row['protocol'] as String,
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
      avgSpo2: (row['avg_spo2'] as num?)?.toDouble(),
      peakAlphaHz: (row['peak_alpha_hz'] as num?)?.toDouble(),
      peakAlphaPower: (row['peak_alpha_power'] as num?)?.toDouble(),
      pctInTarget: (row['pct_in_target'] as num?)?.toDouble(),
      avgMovement: (row['avg_movement'] as num?)?.toDouble(),
      guardrailWarnCount: (row['guardrail_warn_count'] as num?)?.toInt(),
      avgSleepDir: (row['avg_sleep_dir'] as num?)?.toDouble(),
      signalQualityMean: (row['signal_quality_mean'] as num?)?.toDouble(),
      pctQcOk: (row['pct_qc_ok'] as num?)?.toDouble(),
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
      createdAt: _dt(row['created_at']),
      updatedAt: _dt(row['updated_at']),
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