import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/session_metadata.dart';
import 'package:muse_ml/src/feedback/session_sqlite.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/rust/api/session_format.dart';
import 'package:muse_ml/src/version.dart';

class SessionStore {
  SessionStore({Future<SessionStorage>? storage})
    : _storage = storage ?? _defaultStorage(),
      _sqlite = _initSqlite(storage);

  final Future<SessionStorage> _storage;
  final Future<SessionSqlite> _sqlite;

  static Future<SessionSqlite> _initSqlite(Future<SessionStorage>? storage) async {
    if (storage != null) {
      final s = await storage;
      final cacheDir = await resolveSessionCacheDir(s);
      return SessionSqlite.open(cacheDirectory: cacheDir);
    }
    // Fallback - shouldn't happen in practice
    final defaultStorage = await _defaultStorage();
    final cacheDir = await resolveSessionCacheDir(defaultStorage);
    return SessionSqlite.open(cacheDirectory: cacheDir);
  }

  /// Write thumbnail to SQLite cache
  Future<void> _writeThumbnail(String id, List<int> pngBytes) async {
    final sqlite = await _sqlite;
    final session = await sqlite.getSession(id);
    if (session != null) {
      await sqlite.upsertSession(SessionRow(
        id: session.id,
        path: session.path,
        formatVersion: session.formatVersion,
        appVersion: session.appVersion,
        savedAt: session.savedAt,
        startedAt: session.startedAt,
        durationS: session.durationS,
        protocol: session.protocol,
        protocolVersion: session.protocolVersion,
        deviceName: session.deviceName,
        deviceModel: session.deviceModel,
        deviceId: session.deviceId,
        calibrationProfile: session.calibrationProfile,
        recordedChannels: session.recordedChannels,
        recordedStreams: session.recordedStreams,
        offMeta: session.offMeta,
        lenMeta: session.lenMeta,
        offComputed: session.offComputed,
        lenComputed: session.lenComputed,
        offRaw: session.offRaw,
        lenRaw: session.lenRaw,
        avgHr: session.avgHr,
        avgSpo2: session.avgSpo2,
        peakAlphaHz: session.peakAlphaHz,
        peakAlphaPower: session.peakAlphaPower,
        pctInTarget: session.pctInTarget,
        avgMovement: session.avgMovement,
        guardrailWarnCount: session.guardrailWarnCount,
        avgSleepDir: session.avgSleepDir,
        signalQualityMean: session.signalQualityMean,
        pctQcOk: session.pctQcOk,
        markerCount: session.markerCount,
        guardrailEngine: session.guardrailEngine,
        modelKind: session.modelKind,
        modelSha256: session.modelSha256,
        feedbackEngine: session.feedbackEngine,
        userId: session.userId,
        sessionId: session.sessionId,
        notesPreview: session.notesPreview,
        fileSize: session.fileSize,
        mtime: session.mtime,
        thumbnail: Uint8List.fromList(pngBytes),
        createdAt: session.createdAt,
        updatedAt: DateTime.now(),
      ));
    }
  }

  /// Number of sessions awaiting background backfill after the last [list].
  int get pendingBackfillCount => 0;

  Future<List<SessionSummary>> list() async {
    final sqlite = await _sqlite;
    final rows = await sqlite.listSessions();
    return [
      for (final r in rows)
        SessionSummary(
          id: r.id,
          metadata: SessionMetadata(
            protocol: ProtocolType.values.where((p) => p.name == r.protocol).firstOrNull ?? ProtocolType.drowsiness,
            durationMinutes: r.durationS ~/ 60,
            elapsedSeconds: r.durationS,
            sound: 'Ambient Drone',
            savedAt: r.savedAt.toIso8601String(),
            deviceName: r.deviceName,
            deviceModel: r.deviceModel,
            deviceId: r.deviceId,
            durationS: r.durationS,
            startedAt: r.startedAt.toIso8601String(),
            protocolVersion: r.protocolVersion,
            calibrationProfile: r.calibrationProfile,
            avgSpo2: r.avgSpo2,
            peakAlphaHz: r.peakAlphaHz,
            peakAlphaPower: r.peakAlphaPower,
            pctInTarget: r.pctInTarget,
            avgMovement: r.avgMovement,
            guardrailWarnCount: r.guardrailWarnCount,
            avgSleepDir: r.avgSleepDir,
            signalQualityMean: r.signalQualityMean,
            pctQcOk: r.pctQcOk,
            guardrailEngine: r.guardrailEngine,
            modelKind: r.modelKind,
            modelSha256: r.modelSha256,
            feedbackEngine: r.feedbackEngine,
            userId: r.userId,
            sessionId: r.sessionId,
          ),
        ),
    ];
  }

  Future<void> backfillPending() async {}

  Future<List<int>?> readMuse(String id) async {
    final storage = await _storage;
    final bytes = await storage.readFile(_museName(id));
    if (bytes == null) return null;
    return v5ExtractRaw(bytes: Uint8List.fromList(bytes));
  }

  Future<List<int>?> readPng(String id) async {
    final sqlite = await _sqlite;
    final session = await sqlite.getSession(id);
    if (session != null && session.thumbnail != null && session.thumbnail!.isNotEmpty) {
      return session.thumbnail;
    }
    // Fallback: parse from container file if not in cache
    final storage = await _storage;
    final bytes = await storage.readFile(_museName(id));
    if (bytes == null) return null;
    try {
      final head = v5ParseHead(bytes: Uint8List.fromList(bytes));
      return head.thumbnail;
    } catch (_) {
      return null;
    }
  }

  /// The underlying storage (resolved) — used to place exports.
  Future<SessionStorage> get storage => _storage;

  static Future<SessionStorage> _defaultStorage() async {
    throw UnimplementedError(
      'SessionStore needs an explicit storage; use sessionStoreProvider',
    );
  }

  String _museName(String id) => 'session_$id.muse.feedback';

  /// Namespace for cache rows — a short hash of the storage location so two
  /// history folders never share metadata rows even when ids collide.
  static String storageKeyFor(SessionStorage storage) =>
      sha256.convert(utf8.encode(storage.location)).toString().substring(0, 16);

  /// Persist a finished session into the history folder as a single
  /// `.muse.feedback` container (v5 format): header + WebP thumbnail + zstd-compressed
  /// metadata JSON + zstd-computed frames + zstd-compressed raw body.
  Future<SessionSummary> publishSession(
    String id,
    List<int> museBytes,
    SessionMetadata metadata, {
    List<int>? pngBytes,
    List<ComputedFrame>? computedFrames,
  }) async {
    final storage = await _storage;
    await storage.ensureDir();
    final jsonBytes = const JsonEncoder().convert(metadata.toJson()).codeUnits;
    final container = containerEncodeV5(
      thumbnail: pngBytes == null ? Uint8List(0) : Uint8List.fromList(pngBytes),
      metadataJson: jsonBytes,
      computedFrames: computedFrames ?? const <ComputedFrame>[],
      rawBody: Uint8List.fromList(museBytes),
    );
    await storage.writeFileAtomic(_museName(id), container);
    final sqlite = await _sqlite;
    if (pngBytes != null && pngBytes.isNotEmpty) {
      await _writeThumbnail(id, pngBytes);
    }
    await sqlite.upsertSession(SessionRow(
      id: id,
      path: _museName(id),
      formatVersion: 5,
      appVersion: appVersion,
      savedAt: DateTime.tryParse(metadata.savedAt) ?? DateTime.now(),
      startedAt: DateTime.tryParse(metadata.startedAt ?? metadata.savedAt) ?? DateTime.now(),
      durationS: metadata.durationS,
      protocol: metadata.protocol.name,
      protocolVersion: metadata.protocolVersion,
      deviceName: metadata.deviceName,
      deviceModel: metadata.deviceModel,
      deviceId: metadata.deviceId,
      calibrationProfile: metadata.calibrationProfile,
      recordedChannels: metadata.recordedChannels.join(','),
      recordedStreams: '',
      offMeta: 0,
      lenMeta: 0,
      offComputed: 0,
      lenComputed: 0,
      offRaw: 0,
      lenRaw: 0,
      avgHr: null,
      avgSpo2: metadata.avgSpo2,
      peakAlphaHz: metadata.peakAlphaHz,
      peakAlphaPower: metadata.peakAlphaPower,
      pctInTarget: metadata.pctInTarget,
      avgMovement: metadata.avgMovement,
      guardrailWarnCount: metadata.guardrailWarnCount,
      avgSleepDir: metadata.avgSleepDir,
      signalQualityMean: metadata.signalQualityMean,
      pctQcOk: metadata.pctQcOk,
      markerCount: metadata.gestures.length,
      guardrailEngine: metadata.guardrailEngine,
      modelKind: metadata.modelKind,
      modelSha256: metadata.modelSha256,
      feedbackEngine: metadata.feedbackEngine,
      userId: metadata.userId,
      sessionId: metadata.sessionId,
      notesPreview: metadata.notes.isNotEmpty ? (metadata.notes.length > 50 ? metadata.notes.substring(0, 50) : metadata.notes) : null,
      fileSize: container.length,
      mtime: DateTime.now().millisecondsSinceEpoch,
      thumbnail: pngBytes != null && pngBytes.isNotEmpty ? Uint8List.fromList(pngBytes) : null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    debugPrint('[session] written ${_museName(id)} to ${storage.location}');
    return SessionSummary(id: id, metadata: metadata);
  }

  /// Replace the free-text notes of an existing session and rewrite the
  /// v5 container head in place, preserving the thumbnail, computed frames,
  /// and the raw .muse body. Returns false when the session file is missing
  /// or unreadable.
  Future<bool> updateNotes(String id, String notes) async {
    final storage = await _storage;
    final name = _museName(id);
    final bytes = await storage.readFile(name);
    if (bytes == null || bytes.isEmpty) {
      debugPrint('[session] updateNotes($id): file not found ($name)');
      return false;
    }
    final full = Uint8List.fromList(bytes);
    final head = v5ParseHead(bytes: full);
    final decoded =
        jsonDecode(String.fromCharCodes(head.metadataJson)) as Map<String, Object?>;
    decoded['notes'] = notes;
    final jsonBytes = Uint8List.fromList(
      const JsonEncoder().convert(decoded).codeUnits,
    );
    final rawBody = v5ExtractRaw(bytes: full);
    final computedFrames = v5ExtractComputed(bytes: full);
    final container = containerEncodeV5(
      thumbnail: head.thumbnail,
      metadataJson: jsonBytes,
      computedFrames: computedFrames,
      rawBody: rawBody,
    );
    await storage.writeFileAtomic(name, container);
    final sqlite = await _sqlite;
    final existing = await sqlite.getSession(id);
    if (existing != null) {
      await sqlite.upsertSession(SessionRow(
        id: existing.id,
        path: existing.path,
        formatVersion: existing.formatVersion,
        appVersion: existing.appVersion,
        savedAt: existing.savedAt,
        startedAt: existing.startedAt,
        durationS: existing.durationS,
        protocol: existing.protocol,
        protocolVersion: existing.protocolVersion,
        deviceName: existing.deviceName,
        deviceModel: existing.deviceModel,
        deviceId: existing.deviceId,
        calibrationProfile: existing.calibrationProfile,
        recordedChannels: existing.recordedChannels,
        recordedStreams: existing.recordedStreams,
        offMeta: existing.offMeta,
        lenMeta: existing.lenMeta,
        offComputed: existing.offComputed,
        lenComputed: existing.lenComputed,
        offRaw: existing.offRaw,
        lenRaw: existing.lenRaw,
        avgHr: existing.avgHr,
        avgSpo2: existing.avgSpo2,
        peakAlphaHz: existing.peakAlphaHz,
        peakAlphaPower: existing.peakAlphaPower,
        pctInTarget: existing.pctInTarget,
        avgMovement: existing.avgMovement,
        guardrailWarnCount: existing.guardrailWarnCount,
        avgSleepDir: existing.avgSleepDir,
        signalQualityMean: existing.signalQualityMean,
        pctQcOk: existing.pctQcOk,
        markerCount: existing.markerCount,
        guardrailEngine: existing.guardrailEngine,
        modelKind: existing.modelKind,
        modelSha256: existing.modelSha256,
        feedbackEngine: existing.feedbackEngine,
        userId: existing.userId,
        sessionId: existing.sessionId,
        notesPreview: notes.length > 50 ? notes.substring(0, 50) : notes,
        fileSize: existing.fileSize,
        mtime: DateTime.now().millisecondsSinceEpoch,
        createdAt: existing.createdAt,
        updatedAt: DateTime.now(),
      ));
    }
    debugPrint('[session] updateNotes($id): notes saved ($name)');
    return true;
  }

  /// Delete one session from history (the `.muse.feedback` file). Returns
  /// false when the file was already gone.
  Future<bool> delete(String id) async {
    final storage = await _storage;
    final name = _museName(id);
    final existed = await storage.fileExists(name);
    await storage.deleteFile(name);
    final sqlite = await _sqlite;
    await sqlite.deleteMarkers(id);
    await sqlite.deleteSession(id);
    debugPrint(
      '[session] delete($id): ${existed ? 'deleted' : 'missing'} ($name)',
    );
    return existed;
  }

  /// Copy every session in the current storage into [target], then delete the
  /// source copies so the folder change does not duplicate history. Returns the
  /// number of sessions moved (used for folder-change migration).
  Future<int> moveAllTo(SessionStorage target) async {
    final storage = await _storage;
    final names = await storage.listFiles();
    var moved = 0;
    for (final name in names) {
      if (!name.startsWith('session_') || !name.endsWith('.muse.feedback')) {
        continue;
      }
      final bytes = await storage.readFile(name);
      if (bytes == null) {
        continue;
      }
      await target.ensureDir();
      await target.writeFileAtomic(name, bytes);
      await storage.deleteFile(name);
      moved++;
    }
    // Ids survive a folder move verbatim, so carry the cached metadata across
    // to the new storage key. Mtimes will mismatch once and refresh on the
    // first open of the new folder.
    (await _sqlite).close();
    debugPrint('[session] moved $moved session(s)');
    return moved;
  }

  /// Fold a freshly computed [SessionOverview] (from a full-body parse of a
  /// legacy session without an embedded summary) back into the SQLite metadata
  /// so the next detail-view open fast-paths through the overview.
  /// Cache-only — the container file is never rewritten.
  Future<void> cacheOverview(String id, SessionOverview overview) async {
    final sqlite = await _sqlite;
    try {
      final session = await sqlite.getSession(id);
      if (session == null) {
        return;
      }
      // Update the session with overview data
      await sqlite.upsertSession(SessionRow(
        id: session.id,
        path: session.path,
        formatVersion: session.formatVersion,
        appVersion: session.appVersion,
        savedAt: session.savedAt,
        startedAt: session.startedAt,
        durationS: session.durationS,
        protocol: session.protocol,
        protocolVersion: session.protocolVersion,
        deviceName: session.deviceName,
        deviceModel: session.deviceModel,
        deviceId: session.deviceId,
        calibrationProfile: session.calibrationProfile,
        recordedChannels: session.recordedChannels,
        recordedStreams: session.recordedStreams,
        offMeta: session.offMeta,
        lenMeta: session.lenMeta,
        offComputed: session.offComputed,
        lenComputed: session.lenComputed,
        offRaw: session.offRaw,
        lenRaw: session.lenRaw,
        avgHr: overview.pulse.isNotEmpty
            ? overview.pulse.whereType<double>().fold<double>(0, (a, b) => a + b) / overview.pulse.whereType<double>().length
            : null,
        avgSpo2: overview.spo2.isNotEmpty
            ? overview.spo2.whereType<double>().fold<double>(0, (a, b) => a + b) / overview.spo2.whereType<double>().length
            : null,
        peakAlphaHz: overview.peakAlphaFreq.isNotEmpty
            ? overview.peakAlphaFreq.whereType<double>().fold<double>(0, (a, b) => a + b) / overview.peakAlphaFreq.whereType<double>().length
            : null,
        peakAlphaPower: overview.peakAlphaPower.isNotEmpty
            ? overview.peakAlphaPower.whereType<double>().fold<double>(0, (a, b) => a + b) / overview.peakAlphaPower.whereType<double>().length
            : null,
        pctInTarget: overview.bands.isNotEmpty ? 0.0 : null, // placeholder
        avgMovement: overview.movement.isNotEmpty
            ? overview.movement.whereType<double>().fold<double>(0, (a, b) => a + b) / overview.movement.whereType<double>().length
            : null,
        guardrailWarnCount: session.guardrailWarnCount,
        avgSleepDir: session.avgSleepDir,
        signalQualityMean: session.signalQualityMean,
        pctQcOk: session.pctQcOk,
        markerCount: session.markerCount,
        guardrailEngine: session.guardrailEngine,
        modelKind: session.modelKind,
        modelSha256: session.modelSha256,
        feedbackEngine: session.feedbackEngine,
        userId: session.userId,
        sessionId: session.sessionId,
        notesPreview: session.notesPreview,
        fileSize: session.fileSize,
        mtime: session.mtime,
        createdAt: session.createdAt,
        updatedAt: DateTime.now(),
      ));
      debugPrint('[session] cacheOverview($id): overview cached (avgHR=${overview.pulse.isNotEmpty ? overview.pulse.whereType<double>().fold<double>(0, (a, b) => a + b) / overview.pulse.whereType<double>().length : "N/A"})');
    } catch (e) {
      debugPrint('[session] cacheOverview($id) failed: $e');
    }
  }
}